import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context.js";
import { PAYMENT_KIND } from "../services/billing.js";
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

async function handleEvent(
  context: AppContext,
  event: PaymentEvent,
  log: EventLogger,
): Promise<void> {
  const { prisma } = context;

  // Une recharge de cagnotte n'a pas de commande : elle se reconnaît à son
  // `metadata.kind` et se traite à part, avant toute recherche de commande.
  if (event.kind === PAYMENT_KIND.walletTopup) {
    await handleTopup(context, event, log);
    return;
  }

  // `metadata.orderId` d'abord — c'est nous qui l'avons posé. L'intention
  // ensuite, parce qu'un `charge.*` ne porte pas nos métadonnées.
  const order = event.orderId
    ? await prisma.printOrder.findUnique({ where: { id: event.orderId } })
    : event.intentId
      ? await prisma.printOrder.findUnique({
          where: { stripePaymentIntentId: event.intentId },
        })
      : null;

  if (!order) {
    // Pas une erreur : le compte Stripe reçoit aussi les événements d'autres
    // produits, et un paiement de cagnotte n'a pas de commande.
    log.info("Webhook Stripe sans commande correspondante, ignoré");
    return;
  }

  switch (event.type) {
    case "payment_intent.succeeded": {
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
      await prisma.printOrder.updateMany({
        where: { id: order.id, status: "draft" },
        data: { error: "Le paiement a été refusé." },
      });
      log.warn({ orderId: order.id }, "Paiement refusé");
      return;
    }

    case "charge.refunded": {
      // Remboursement d'une carte : l'argent repart d'où il vient, il ne
      // devient pas du crédit de cagnotte. Écrire une `WalletEntry` ici
      // créditerait une somme que l'utilisateur n'a jamais eue sur sa cagnotte.
      await prisma.printOrder.updateMany({
        where: { id: order.id, status: { not: "cancelled" } },
        data: { status: "cancelled", error: "Commande remboursée." },
      });
      log.info({ orderId: order.id }, "Commande remboursée et annulée");
      return;
    }

    default:
      log.info("Type d'événement non traité, acquitté");
  }
}

/**
 * Créditer une cagnotte après un encaissement réussi.
 *
 * L'idempotence tient sur `wallet_entries.stripeEventId`, qui est unique : un
 * rejeu bute sur la contrainte et ne crédite pas deux fois. C'est la base qui
 * arbitre, pas une lecture préalable — celle-ci aurait sa propre fenêtre de
 * course entre deux livraisons simultanées.
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

  if (!event.accountId || !event.amountCents) {
    log.warn("Recharge sans compte ou sans montant, ignorée");
    return;
  }

  const result = await writeLedgerEntry(context.prisma, {
    accountId: event.accountId,
    amountCents: event.amountCents,
    kind: "topup",
    label: "Recharge de la cagnotte",
    stripeEventId: event.id,
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
