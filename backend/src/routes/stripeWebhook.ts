import type { FastifyInstance } from "fastify";
import Stripe from "stripe";
import type { AppContext } from "../context.js";
import { isDatabaseUnavailable } from "../lib/databasePool.js";
import { PAYMENT_KIND } from "../services/billing.js";
import { recordOrderRefund, releaseUnpaidOrder } from "../services/orderPayments.js";
import type { PaymentEvent } from "../services/payments.js";
import { writeLedgerEntry } from "../services/walletLedger.js";

/**
 * Le retour de Stripe — et **la seule chose** qui fait passer une commande de
 * `draft` à `submitted`.
 *
 * Pourquoi pas le retour de l'app, qui arriverait plus tôt : entre le moment où
 * l'utilisateur valide Face ID et celui où l'app rappelle le serveur, l'app
 * peut être tuée, le réseau peut tomber, le téléphone peut s'éteindre. Le
 * paiement, lui, a eu lieu. Stripe rejoue son webhook jusqu'à obtenir un 2xx ;
 * c'est le seul canal qui ne perd pas d'argent.
 *
 * Deux conséquences, et elles gouvernent tout le fichier :
 *
 * 1. **Un même événement arrivera plusieurs fois.** Le rejeu est le mode normal
 *    de fonctionnement, pas un incident. Chaque écriture doit donc être sûre à
 *    répéter.
 * 2. **Une erreur non gérée est une boucle.** Un 500 fait rejouer, et un bug
 *    qui lève à chaque fois fait rejouer indéfiniment. On acquitte donc tout ce
 *    qu'on ne sait pas traiter, au lieu de le faire échouer.
 *
 *    **Sauf une panne passagère** (01/10/2026) : la base saturée (le pooler
 *    Supabase plafonne à quinze clients), Stripe injoignable. Acquitter celle-là
 *    perdait l'événement — une commande payée restait en `draft` pour toujours,
 *    une recharge n'était jamais créditée. Elle répond 500, et Stripe rejoue
 *    plus tard ; les écritures étant sûres à répéter, le rejeu ne coûte rien.
 */

/** L'en-tête que Stripe pose, et qui porte la signature. */
const SIGNATURE_HEADER = "stripe-signature";

export async function registerStripeWebhookRoutes(
  app: FastifyInstance,
  context: AppContext,
): Promise<void> {
  // Une portée à part, uniquement pour le parseur de corps. Fastify encapsule
  // `addContentTypeParser` dans le plugin qui l'enregistre : le reste de l'API
  // continue de recevoir du JSON déjà décodé.
  await app.register(async (scope) => {
    // **Le piège numéro un des webhooks Stripe.** La signature porte sur les
    // octets reçus. Laisser Fastify parser puis re-sérialiser change un espace
    // ou l'ordre d'une clé, et la vérification échoue sur un corps pourtant
    // authentique. On garde donc le `Buffer` tel quel.
    scope.addContentTypeParser(
      "application/json",
      { parseAs: "buffer" },
      (_request, body, done) => {
        done(null, body);
      },
    );

    scope.post("/v1/webhooks/stripe", async (request, reply) => {
      const signature = request.headers[SIGNATURE_HEADER];

      if (typeof signature !== "string") {
        return reply.code(400).send({ error: "missing_signature" });
      }

      if (!Buffer.isBuffer(request.body)) {
        // Ne devrait pas arriver : le parseur ci-dessus rend toujours un
        // Buffer. Si ça arrive, c'est que quelqu'un a ajouté un parseur plus
        // haut, et la signature serait invérifiable — mieux vaut refuser.
        return reply.code(400).send({ error: "raw_body_unavailable" });
      }

      let event;
      try {
        event = context.payments.verifyEvent(request.body, signature);
      } catch (cause) {
        const message = cause instanceof Error ? cause.message : String(cause);
        // 400 et non 500 : une signature invalide n'est pas une panne, c'est un
        // appel qu'on rejette. Stripe ne rejoue pas les 4xx, et c'est très bien
        // — rejouer un appel non signé ne le rendrait pas signé.
        request.log.warn({ err: cause }, "Webhook Stripe refusé");
        return reply.code(400).send({ error: "invalid_signature", message });
      }

      const log = request.log.child({ eventId: event.id, eventType: event.type });

      try {
        await handleEvent(context, event, log);
      } catch (cause) {
        if (isTransient(cause)) {
          // La base ou Stripe ne répondent pas : ce n'est pas l'événement qui
          // est en cause, c'est le moment. Stripe rejouera.
          log.warn({ err: cause }, "Webhook Stripe : panne passagère, Stripe rejouera");
          return reply.code(500).send({ error: "temporarily_unavailable" });
        }
        // On journalise et on acquitte. Un 500 ferait rejouer, et si le bug est
        // déterministe le rejeu ne réussira jamais : on aurait juste un
        // événement qui revient toutes les heures pendant trois jours. La trace
        // dans les journaux est le bon endroit pour le rattraper.
        log.error({ err: cause }, "Webhook Stripe : traitement échoué");
      }

      return reply.code(200).send({ received: true });
    });
  });
}

type EventLogger = Pick<FastifyInstance["log"], "info" | "warn" | "error">;

/** Ce qui vaut un rejeu : la base saturée ou injoignable, Stripe hors d'atteinte. */
function isTransient(cause: unknown): boolean {
  return (
    isDatabaseUnavailable(cause) ||
    cause instanceof Stripe.errors.StripeConnectionError ||
    cause instanceof Stripe.errors.StripeAPIError ||
    cause instanceof Stripe.errors.StripeRateLimitError
  );
}

async function handleEvent(
  context: AppContext,
  event: PaymentEvent,
  log: EventLogger,
): Promise<void> {
  const { prisma } = context;

  // Une recharge de cagnotte n'a pas de commande : elle se reconnaît à son
  // `metadata.kind` et se traite à part, avant toute recherche de commande.
  if (event.kind === PAYMENT_KIND.walletTopup && event.type.startsWith("payment_intent.")) {
    await handleTopup(context, event, log);
    return;
  }

  // `metadata.orderId` d'abord — c'est nous qui l'avons posé. L'intention
  // ensuite, parce qu'un `charge.*` ne porte pas forcément nos métadonnées.
  const order = event.orderId
    ? await prisma.printOrder.findUnique({ where: { id: event.orderId } })
    : event.intentId
      ? await prisma.printOrder.findUnique({
          where: { stripePaymentIntentId: event.intentId },
        })
      : null;

  if (!order) {
    // Une charge de recharge remboursée ou contestée : elle se retrouve par
    // son intention, au registre de la cagnotte.
    if (event.type === "charge.refunded" || event.type === "charge.dispute.created") {
      await handleTopupCharge(context, event, log);
      return;
    }
    // Pas une erreur : le compte Stripe reçoit aussi les événements d'autres
    // produits.
    log.info("Webhook Stripe sans commande correspondante, ignoré");
    return;
  }

  switch (event.type) {
    case "payment_intent.succeeded": {
      // **Ce qui a été payé, et pas ce qu'on croit avoir demandé.** Une
      // intention modifiée à la main dans le tableau de bord, ou une devise
      // inattendue, ne doit pas faire partir un carnet payé à moitié.
      if (
        order.amountCents !== null &&
        (event.amountCents !== order.amountCents || (event.currency ?? "eur") !== "eur")
      ) {
        log.error(
          {
            orderId: order.id,
            expectedCents: order.amountCents,
            receivedCents: event.amountCents,
            currency: event.currency,
          },
          "Paiement d'un montant inattendu : commande laissée en brouillon, à vérifier",
        );
        return;
      }

      if (order.status === "cancelled") {
        // Ne devrait pas arriver : une commande ne se ferme qu'après que Stripe
        // a accepté d'annuler son intention. Si ça arrive, l'argent est pris
        // pour une commande fermée — le support doit rembourser.
        log.error({ orderId: order.id }, "Paiement reçu pour une commande annulée : à rembourser");
        return;
      }

      // `updateMany` avec `status: "draft"` dans le `where` : c'est la base qui
      // décide, en une instruction, si la transition a déjà eu lieu. Lire puis
      // écrire laisserait la place à deux rejeux simultanés — Stripe en envoie,
      // et `submittedAt` ne doit être posée qu'une fois.
      const { count } = await prisma.printOrder.updateMany({
        where: { id: order.id, status: "draft" },
        data: { status: "submitted", submittedAt: new Date(), error: null },
      });

      if (count === 0) {
        log.info({ orderId: order.id }, "Paiement déjà acquitté, rien à faire");
        return;
      }

      log.info(
        { orderId: order.id, amountCents: order.amountCents },
        "Commande payée et prête à partir à l'impression",
      );

      // ⚠️ **Il n'y a pas encore d'imprimeur branché.** La commande reste donc
      // en `submitted` jusqu'à ce qu'un humain la traite. C'est le bon état :
      // l'argent est encaissé, la commande est traçable, et `in_production`
      // viendra du jour où un fournisseur d'impression sera choisi.
      return;
    }

    case "payment_intent.payment_failed": {
      // La feuille de paiement réessaie sur **la même** intention : la
      // commande reste ouverte, avec sa réservation. C'est le ménage qui la
      // fermera si personne ne revient.
      await prisma.printOrder.updateMany({
        where: { id: order.id, status: "draft" },
        data: { error: "Le paiement a été refusé." },
      });
      log.warn({ orderId: order.id }, "Paiement refusé");
      return;
    }

    case "payment_intent.canceled": {
      // Annulée chez Stripe — par le ménage, par l'app, ou à la main dans le
      // tableau de bord : la commande se ferme et rend sa part de cagnotte.
      const outcome = await releaseUnpaidOrder(context, order.id, "Paiement annulé.");
      log.info({ orderId: order.id, outcome }, "Intention annulée");
      return;
    }

    case "charge.refunded": {
      // Le cumul remboursé, et si c'est tout : voir `recordOrderRefund`. La
      // carte est remboursée par Stripe ; la part de cagnotte, elle, revient
      // ici, et seulement sur un remboursement total avant l'impression.
      const outcome = await recordOrderRefund(
        context,
        order,
        event.amountCents ?? 0,
        event.fullyRefunded,
      );
      log.info({ orderId: order.id, refundedCents: event.amountCents, outcome }, "Commande remboursée");
      return;
    }

    case "charge.dispute.created": {
      // Un litige : la banque reprend l'argent le temps de trancher. Rien ne
      // se décide automatiquement — mais rien ne doit partir sans que le
      // support l'ait vu.
      await prisma.printOrder.update({
        where: { id: order.id },
        data: { error: "Litige bancaire ouvert." },
      });
      log.error({ orderId: order.id, status: order.status }, "Litige ouvert sur une commande");
      return;
    }

    default:
      log.info("Type d'événement non traité, acquitté");
  }
}

/**
 * Créditer une cagnotte après un encaissement réussi.
 *
 * **Une seule fois par intention** (`topup:<intention>`), et plus seulement par
 * événement : Stripe peut envoyer deux événements distincts pour le même
 * paiement, et l'ancienne clé — l'identifiant de l'événement — les aurait
 * crédités deux fois. L'intention est gardée sur l'écriture : c'est elle qu'un
 * remboursement retrouvera.
 */
async function handleTopup(
  context: AppContext,
  event: PaymentEvent,
  log: EventLogger,
): Promise<void> {
  if (event.type !== "payment_intent.succeeded") {
    log.info("Recharge non aboutie, rien à créditer");
    return;
  }

  if (!event.accountId || !event.amountCents || !event.intentId) {
    log.warn("Recharge sans compte, sans montant ou sans intention, ignorée");
    return;
  }

  const result = await writeLedgerEntry(context.prisma, {
    accountId: event.accountId,
    amountCents: event.amountCents,
    kind: "topup",
    label: "Recharge de la cagnotte",
    stripeEventId: event.id,
    idempotencyKey: `topup:${event.intentId}`,
    stripePaymentIntentId: event.intentId,
  });

  if (result.outcome === "duplicate") {
    log.info({ accountId: event.accountId }, "Recharge déjà créditée, rejeu ignoré");
    return;
  }

  if (result.outcome === "written") {
    log.info(
      { accountId: event.accountId, amountCents: event.amountCents, balance: result.balanceCents },
      "Cagnotte créditée",
    );
  }
}

/**
 * Une recharge remboursée ou contestée.
 *
 * **Remboursée : la cagnotte rend ce que la carte a récupéré** (01/10/2026). La
 * carte retrouvait son argent et la cagnotte gardait le crédit — de l'argent
 * qui sortait deux fois. On reprend ce qui n'a pas encore été repris, plafonné
 * au solde : s'il a déjà été dépensé dans un carnet, on reprend ce qui reste,
 * et le support voit le reste.
 */
async function handleTopupCharge(
  context: AppContext,
  event: PaymentEvent,
  log: EventLogger,
): Promise<void> {
  if (!event.intentId) {
    log.info("Charge sans intention, ignorée");
    return;
  }

  const { prisma } = context;
  const credit = await prisma.walletEntry.findFirst({
    where: { stripePaymentIntentId: event.intentId, kind: "topup", amountCents: { gt: 0 } },
  });

  if (!credit) {
    log.info("Charge sans commande ni recharge correspondante, ignorée");
    return;
  }

  if (event.type === "charge.dispute.created") {
    log.error(
      { accountId: credit.accountId, intentId: event.intentId, amountCents: credit.amountCents },
      "Litige ouvert sur une recharge de cagnotte : à trancher par le support",
    );
    return;
  }

  // Ce qui a déjà été repris pour cette intention, par les remboursements
  // précédents — le cumul de Stripe moins ce qu'on a déjà inscrit.
  const taken = await prisma.walletEntry.aggregate({
    where: { stripePaymentIntentId: event.intentId, kind: "adjustment" },
    _sum: { amountCents: true },
  });
  const refunded = Math.min(event.amountCents ?? 0, credit.amountCents);
  const due = refunded + (taken._sum.amountCents ?? 0);
  if (due <= 0) {
    log.info({ intentId: event.intentId }, "Remboursement de recharge déjà repris");
    return;
  }

  const result = await writeLedgerEntry(prisma, {
    accountId: credit.accountId,
    amountCents: -due,
    kind: "adjustment",
    label: "Recharge remboursée sur ta carte",
    stripeEventId: event.id,
    stripePaymentIntentId: event.intentId,
    clampToBalance: true,
  });

  if (result.outcome === "written") {
    if (result.clampedCents > 0) {
      log.error(
        { accountId: credit.accountId, intentId: event.intentId, missingCents: result.clampedCents },
        "Recharge remboursée déjà dépensée : le reste est à reprendre par le support",
      );
    } else {
      log.info({ accountId: credit.accountId, takenCents: due }, "Recharge remboursée reprise");
    }
  }
}
