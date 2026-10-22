import { Prisma, type Subscription } from "@prisma/client";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import type { StoreKitState } from "./appStoreSubscriptions.js";
import type { GooglePlayPurchase } from "./googlePlay.js";
import { visibleToAccount } from "./memoOwnership.js";
import { CATALOG_CURRENCY, GOOGLE_PLAY_PRODUCTS, isAcceptedGooglePlayProduct } from "./subscriptionCatalog.js";
import { LIVING_SUBSCRIPTION_STATUSES } from "./subscriptions.js";

/**
 * L'abonnement Google Play, recopié dans `subscriptions` — **Google a le
 * dernier mot**, comme Apple pour StoreKit (`appStoreSubscriptions.ts`).
 *
 * Deux portes, la même écriture :
 *
 * - **l'app**, juste après l'achat (`POST /v1/subscriptions/google-play`) ;
 * - **Google**, à chaque événement (`POST /v1/webhooks/google-play`,
 *   notifications temps réel par Pub/Sub).
 *
 * Les deux relisent l'abonnement chez Google avant d'écrire : ce qu'on écrit
 * est toujours l'état du moment, jamais celui qu'une notification décrivait.
 *
 * Une ligne par **jeton d'achat** (`providerSubscriptionId`) ; une ligne de
 * `subscription_transactions` par commande payée (`GPA.…`, `GPA.…..0`, …).
 */

/** Les états Google qui ont un abonnement à écrire. `pending` attend le paiement. */
export function isWritableGooglePlayState(state: GooglePlayPurchase["state"]): boolean {
  return state !== "pending" && state !== "pending_purchase_canceled" && state !== "unknown";
}

/** Les états d'un achat **payé**, qu'il faut acquitter. */
export function needsAcknowledgement(purchase: GooglePlayPurchase): boolean {
  return (
    !purchase.acknowledged &&
    (purchase.state === "active" || purchase.state === "canceled" || purchase.state === "grace_period")
  );
}

/**
 * Traduit l'état Google dans les statuts que lisent déjà l'accès illimité et
 * le profil — la même table que pour Apple :
 *
 * | Chez Google | Ici | Accès |
 * |---|---|---|
 * | actif, renouvellement armé | `active` | oui |
 * | résilié (`CANCELED`), période en cours | `cancelled` | jusqu'à `renewsAt` |
 * | délai de grâce | `past_due` | oui, c'est Google qui l'accorde |
 * | suspendu (`ON_HOLD`), en pause | `expired` | non, la période n'est pas payée |
 * | expiré | `expired` | non |
 * | révoqué, remboursé | `expired` | non, dès la révocation |
 *
 * ⚠️ Pour ce qui ne donne plus accès, `renewsAt` ne dépasse jamais
 * maintenant : `expired` avec une date à venir **ouvrirait** l'illimité
 * (`PAID_THROUGH_SUBSCRIPTION_STATUSES`), et la fin de période d'un abonnement
 * en pause peut être devant.
 */
export function googlePlayState(purchase: GooglePlayPurchase, now: Date, revoked: boolean): StoreKitState {
  const notAfterNow = (date: Date | null) => (date === null || date > now ? now : date);

  if (revoked) return { status: "expired", renewsAt: now, autoRenews: false };

  switch (purchase.state) {
    case "active":
      return {
        status: purchase.autoRenews === false ? "cancelled" : "active",
        renewsAt: purchase.expiresAt,
        autoRenews: purchase.autoRenews,
      };
    case "canceled":
      return { status: "cancelled", renewsAt: purchase.expiresAt, autoRenews: false };
    case "grace_period":
      return { status: "past_due", renewsAt: purchase.expiresAt, autoRenews: purchase.autoRenews };
    case "on_hold":
    case "paused":
      return { status: "expired", renewsAt: notAfterNow(purchase.expiresAt), autoRenews: purchase.autoRenews };
    default:
      return { status: "expired", renewsAt: notAfterNow(purchase.expiresAt), autoRenews: false };
  }
}

export interface ApplyGooglePlayInput {
  /** Le compte qui envoie l'achat ; absent quand c'est Google qui notifie. */
  accountId?: string;
  purchase: GooglePlayPurchase;
  /** Le voyage que l'achat finance, quand l'app le dit. */
  memoId?: string;
  /** Remboursé ou révoqué : l'accès se ferme tout de suite. */
  revokedOrderId?: string | null;
  revoked?: boolean;
  /** L'instant de la lecture chez Google. */
  observedAt?: Date;
}

/**
 * Inscrit un abonnement Google Play. **Sûr à rejouer** : l'app renvoie son
 * achat à chaque lancement tant qu'il n'est pas acquitté, et Pub/Sub renvoie
 * sa notification jusqu'au 2xx.
 *
 * Rend `null` quand l'achat ne mène à aucun compte : une notification pour un
 * achat dont l'app n'a jamais parlé, et sans `obfuscatedExternalAccountId`.
 */
export async function applyGooglePlayPurchase(
  context: AppContext,
  input: ApplyGooglePlayInput,
): Promise<Subscription | null> {
  if (!isAcceptedGooglePlayProduct(input.purchase.productId)) {
    throw HttpError.badRequest(`Produit Google Play inconnu : ${input.purchase.productId}.`, "unknown_product");
  }

  try {
    return await writeGooglePlayPurchase(context, input);
  } catch (cause) {
    // L'app et Google parlent souvent du même achat en même temps : la
    // seconde écriture relit la ligne que la première vient de créer.
    if (cause instanceof Prisma.PrismaClientKnownRequestError && cause.code === "P2002") {
      return writeGooglePlayPurchase(context, input);
    }
    throw cause;
  }
}

async function writeGooglePlayPurchase(
  context: AppContext,
  input: ApplyGooglePlayInput,
): Promise<Subscription | null> {
  const { prisma } = context;
  const { purchase } = input;
  const observedAt = input.observedAt ?? new Date();

  const [existing, linked] = await Promise.all([
    prisma.subscription.findUnique({ where: { providerSubscriptionId: purchase.purchaseToken } }),
    purchase.linkedPurchaseToken
      ? prisma.subscription.findUnique({ where: { providerSubscriptionId: purchase.linkedPurchaseToken } })
      : Promise.resolve(null),
  ]);

  if (input.accountId !== undefined) {
    // L'achat a été fait **depuis un autre compte MemoBook** sur ce téléphone :
    // l'app pose l'id du compte connecté à l'achat (`setObfuscatedAccountId`).
    // Un compte supprimé depuis ne compte pas — Google continue de prélever,
    // et le nouveau compte doit pouvoir restaurer. Un achat sans id (un code
    // promo utilisé dans le Play Store) se rattache au compte qui l'envoie.
    if (
      purchase.accountId !== null &&
      purchase.accountId !== input.accountId &&
      (await prisma.account.findUnique({ where: { id: purchase.accountId }, select: { id: true } })) !== null
    ) {
      throw new HttpError(403, "Cet achat a été fait depuis un autre compte MemoBook.", "transaction_account_mismatch");
    }
    if (existing && existing.accountId !== input.accountId) {
      throw new HttpError(
        409,
        "Cet abonnement Google Play est déjà rattaché à un autre compte MemoBook.",
        "subscription_owned_elsewhere",
      );
    }
  }

  const candidate =
    existing?.accountId ??
    input.accountId ??
    (linked?.provider === "google_play" ? linked.accountId : null) ??
    purchase.accountId;
  if (!candidate) return null;
  const account = await prisma.account.findUnique({ where: { id: candidate }, select: { id: true } });
  if (!account) return null;
  const accountId = account.id;

  const memoId = input.memoId ? await visibleMemoId(context, accountId, input.memoId) : null;
  const state = googlePlayState(purchase, observedAt, input.revoked === true);
  // Les lectures chez Google sont l'état du moment : une lecture plus ancienne
  // que la dernière appliquée (deux requêtes croisées) ne touche pas à l'état.
  const isStale = existing?.providerUpdatedAt != null && observedAt < existing.providerUpdatedAt;
  const product = GOOGLE_PLAY_PRODUCTS[purchase.productId]!;

  return prisma.$transaction(async (tx) => {
    const fields = {
      status: state.status,
      renewsAt: state.renewsAt,
      autoRenews: state.autoRenews,
      cancelledAt: cancelledAtFor(state.status, existing?.cancelledAt ?? null, observedAt),
      environment: purchase.environment,
      providerUpdatedAt: observedAt,
      productId: purchase.productId,
      interval: product.interval,
      priceCents: purchase.priceCents ?? product.priceCents,
      ...(purchase.currency === null ? {} : { currency: purchase.currency }),
      ...(memoId === null ? {} : { memoId }),
    };

    const subscription =
      isStale && existing
        ? existing
        : existing
          ? await tx.subscription.update({ where: { id: existing.id }, data: fields })
          : await tx.subscription.create({
              data: {
                ...fields,
                accountId,
                provider: "google_play",
                currency: purchase.currency ?? CATALOG_CURRENCY,
                providerSubscriptionId: purchase.purchaseToken,
                startedAt: purchase.startedAt ?? observedAt,
              },
            });

    // **L'ancien jeton est remplacé** : réabonnement ou changement d'offre.
    // Sa ligne se ferme, sinon le compte aurait deux abonnements vivants pour
    // un seul prélèvement — et deux rappels de résiliation.
    if (
      linked &&
      linked.provider === "google_play" &&
      linked.accountId === accountId &&
      linked.id !== subscription.id &&
      (LIVING_SUBSCRIPTION_STATUSES as readonly string[]).includes(linked.status)
    ) {
      await tx.subscription.update({
        where: { id: linked.id },
        data: {
          status: "expired",
          autoRenews: false,
          renewsAt: linked.renewsAt && linked.renewsAt < observedAt ? linked.renewsAt : observedAt,
          cancelledAt: linked.cancelledAt ?? observedAt,
          providerUpdatedAt: observedAt,
        },
      });
    }

    // La commande payée — une par période. `GPA.…` la première, `GPA.…..0`
    // au premier renouvellement. Seulement quand elle est payée : pendant le
    // délai de grâce ou la suspension, la dernière commande est celle qui
    // échoue.
    if (purchase.orderId && (purchase.state === "active" || purchase.state === "canceled")) {
      const isFirstOrder = !purchase.orderId.includes("..");
      await tx.subscriptionTransaction.upsert({
        where: { transactionId: purchase.orderId },
        create: {
          subscriptionId: subscription.id,
          memoId: subscription.memoId,
          transactionId: purchase.orderId,
          originalTransactionId: purchase.purchaseToken,
          productId: purchase.productId,
          purchasedAt: isFirstOrder ? (purchase.startedAt ?? observedAt) : observedAt,
          expiresAt: purchase.expiresAt,
          priceCents: purchase.priceCents,
          currency: purchase.currency,
          environment: purchase.environment,
          revokedAt: null,
        },
        update: {},
      });
    }

    // Le remboursement : la commande nommée par Google, ou à défaut toutes
    // celles du jeton qui ne le sont pas déjà (une révocation coupe l'accès
    // au jour même).
    if (input.revoked) {
      await tx.subscriptionTransaction.updateMany({
        where: {
          subscriptionId: subscription.id,
          revokedAt: null,
          ...(input.revokedOrderId ? { transactionId: input.revokedOrderId } : {}),
        },
        data: { revokedAt: observedAt },
      });
    }

    return subscription;
  });
}

/** Le jour de la résiliation : posé une fois, effacé quand l'abonnement repart. */
function cancelledAtFor(status: Subscription["status"], previous: Date | null, at: Date): Date | null {
  if (status === "active" || status === "trialing" || status === "past_due") return null;
  return previous ?? at;
}

/** Le voyage annoncé par l'app, s'il est bien à ce compte ; ignoré sinon. */
async function visibleMemoId(context: AppContext, accountId: string, memoId: string): Promise<string | null> {
  const memo = await context.prisma.memo.findFirst({
    where: { AND: [{ id: memoId }, visibleToAccount(accountId)] },
    select: { id: true },
  });
  return memo?.id ?? null;
}
