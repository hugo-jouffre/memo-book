import type { PrintOrder } from "@prisma/client";
import type { AppContext } from "../context.js";
import { writeLedgerEntry } from "./walletLedger.js";

/**
 * Ce qui arrive à l'argent d'une commande **après** sa création : elle est
 * abandonnée, refusée, annulée, ou remboursée.
 *
 * **La part de cagnotte est réservée à la création** (`POST /v1/memos/:id/orders`
 * écrit le débit), pour qu'une seconde commande partie en parallèle ne puisse
 * pas dépenser la même somme. Jusqu'au 01/10/2026, rien ne la rendait : une
 * feuille de paiement refermée, une carte refusée, une app tuée laissaient
 * l'argent bloqué sur un brouillon pour toujours. Tout ce qui ferme une
 * commande non payée passe désormais par `releaseUnpaidOrder`.
 *
 * **Une seule clé pour rendre la cagnotte**, quel que soit le chemin —
 * annulation par l'app, intention annulée, ménage des brouillons, remboursement
 * total. Ils peuvent arriver ensemble ; l'unicité de
 * `wallet_entries.idempotencyKey` en laisse passer un.
 */

/** Combien de temps un brouillon garde sa réservation avant le ménage. */
export const ABANDONED_ORDER_HOURS = 24;

export type ReleaseOutcome =
  /** Fermée, et la part de cagnotte rendue s'il y en avait une. */
  | "released"
  /** Stripe refuse d'annuler : payée, ou paiement en cours. Le webhook conclura. */
  | "paid"
  /** Plus un brouillon — déjà payée, ou déjà fermée. Rien à faire. */
  | "not_draft";

/**
 * Ferme une commande **qui n'a pas été payée**, et rend sa part de cagnotte.
 *
 * **L'intention s'annule d'abord**, et c'est Stripe qui tranche : une intention
 * annulée ne peut plus être payée, et une intention payée ne peut plus être
 * annulée. Sans cet ordre, un paiement validé à la seconde où le ménage passe
 * aurait encaissé une commande déjà fermée et remboursé la cagnotte avec.
 */
export async function releaseUnpaidOrder(
  context: AppContext,
  orderId: string,
  reason: string,
): Promise<ReleaseOutcome> {
  const order = await context.prisma.printOrder.findUnique({ where: { id: orderId } });
  if (!order || order.status !== "draft") return "not_draft";

  if (order.stripePaymentIntentId) {
    const cancelled = await context.payments.cancelIntent(order.stripePaymentIntentId);
    if (!cancelled) return "paid";
  }

  await returnWalletShare(context, order, "Réservation rendue");

  const { count } = await context.prisma.printOrder.updateMany({
    where: { id: order.id, status: "draft" },
    data: { status: "cancelled", error: reason },
  });

  if (count > 0) {
    context.logger.info(
      { orderId: order.id, walletCents: order.walletAppliedCents ?? 0, reason },
      "Commande non payée fermée",
    );
  }
  return "released";
}

/**
 * Le ménage : les brouillons trop vieux pour être encore payés rendent ce
 * qu'ils réservaient. Appelé par la tâche horaire.
 *
 * Un par un, parce que chacun demande d'abord à Stripe d'annuler son
 * intention. Ils se comptent en unités, pas en milliers.
 */
export async function releaseAbandonedOrders(context: AppContext, now = new Date()): Promise<number> {
  const before = new Date(now.getTime() - ABANDONED_ORDER_HOURS * 3_600_000);
  const stale = await context.prisma.printOrder.findMany({
    where: { status: "draft", createdAt: { lt: before } },
    select: { id: true },
  });

  let released = 0;
  for (const { id } of stale) {
    try {
      const outcome = await releaseUnpaidOrder(context, id, "Commande non payée, annulée au bout de 24 h.");
      if (outcome === "released") released += 1;
    } catch (cause) {
      // Une commande qui résiste ne retient pas les autres ; elle repassera à
      // la prochaine heure.
      context.logger.error({ err: cause, orderId: id }, "Ménage d'une commande non payée échoué");
    }
  }
  return released;
}

export type RefundOutcome = "partial" | "cancelled" | "already_printing";

/**
 * Un remboursement de la carte, tel que `charge.refunded` le décrit —
 * `refundedCents` est **cumulé**, comme chez Stripe.
 *
 * - **Partiel** : on l'inscrit, rien d'autre. Un geste commercial sur des
 *   frais de port n'annule pas un carnet.
 * - **Total, avant l'impression** : la commande est annulée, et sa part de
 *   cagnotte revient — l'argent repart d'où il vient, la carte comme la
 *   cagnotte.
 * - **Total, une fois en impression ou expédiée** : le carnet est parti, le
 *   statut ne ment pas. La part de cagnotte ne revient pas d'elle-même : c'est
 *   au support de décider, et le log le lui dit.
 */
export async function recordOrderRefund(
  context: AppContext,
  order: PrintOrder,
  refundedCents: number,
  fullyRefunded: boolean,
): Promise<RefundOutcome> {
  // Le plus grand l'emporte : deux événements de remboursement peuvent
  // arriver dans le désordre, et le cumul ne redescend jamais.
  await context.prisma.printOrder.updateMany({
    where: { id: order.id, refundedCents: { lt: refundedCents } },
    data: { refundedCents },
  });

  if (!fullyRefunded) return "partial";

  if (order.status === "in_production" || order.status === "shipped") {
    context.logger.warn(
      { orderId: order.id, status: order.status, walletCents: order.walletAppliedCents ?? 0 },
      "Commande remboursée en entier après l'impression : la part de cagnotte est à trancher par le support",
    );
    return "already_printing";
  }

  await returnWalletShare(context, order, "Commande remboursée");
  await context.prisma.printOrder.updateMany({
    where: { id: order.id, status: { in: ["draft", "submitted"] } },
    data: { status: "cancelled", error: "Commande remboursée." },
  });
  return "cancelled";
}

/**
 * Rend à la cagnotte ce que la commande y avait **réellement** prélevé — lu sur
 * le registre, pas sur `walletAppliedCents` : une commande dont le débit a
 * échoué n'a rien à rendre.
 */
async function returnWalletShare(context: AppContext, order: PrintOrder, label: string): Promise<void> {
  if (!order.orderedByAccountId) return;

  const debit = await context.prisma.walletEntry.findFirst({
    where: { printOrderId: order.id, kind: "order_payment", amountCents: { lt: 0 } },
    select: { amountCents: true },
  });
  if (!debit) return;

  await writeLedgerEntry(context.prisma, {
    accountId: order.orderedByAccountId,
    amountCents: -debit.amountCents,
    kind: "refund",
    label,
    printOrderId: order.id,
    idempotencyKey: `order-wallet-return:${order.id}`,
  });
}
