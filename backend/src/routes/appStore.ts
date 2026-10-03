import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { AppStoreVerificationError, type AppStoreNotification } from "../services/appStore.js";
import { applyStoreKitTransaction } from "../services/appStoreSubscriptions.js";
import { isAcceptedAppStoreProduct } from "../services/subscriptionCatalog.js";
import { readProfile } from "./profile.js";

/**
 * L'abonnement acheté par StoreKit — voir `services/appStoreSubscriptions.ts`.
 *
 * Deux routes, et ce n'est pas un doublon : **l'app** dit ce qu'elle vient
 * d'acheter, pour que le micro s'ouvre tout de suite ; **Apple** dit tout le
 * reste, y compris ce qui se passe quand l'app est fermée. L'une sans l'autre
 * laisserait soit attendre après avoir payé, soit raconter sans limite après
 * avoir résilié.
 */

const purchaseBody = z.object({
  /** `Transaction.jwsRepresentation`, tel que StoreKit le rend. */
  signedTransaction: z.string().min(1),
  /** Le voyage que l'achat finance, quand l'offre a été ouverte depuis un voyage. */
  memoId: z.string().uuid().optional(),
});

const notificationBody = z.object({ signedPayload: z.string().min(1) });

/** Les routes de l'app — derrière une session de compte. */
export function registerAppStoreRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * L'app vient d'acheter, de restaurer, ou retrouve au lancement une
   * transaction qu'elle n'a pas encore finie. Le récit devient illimité dans
   * la seconde, sans attendre Apple.
   *
   * ⚠️ **L'app ne finit la transaction (`transaction.finish()`) qu'après un 2xx
   * d'ici.** Tant qu'elle ne l'a pas fait, StoreKit la lui rend à chaque
   * lancement : c'est ce qui rend un achat fait hors réseau impossible à perdre.
   * Cette route est donc rejouée, et elle est sûre à rejouer.
   *
   * Rend le profil, comme la résiliation : c'est ce que l'écran garde.
   */
  app.post("/v1/subscriptions/app-store", async (request) => {
    const accountId = accountIdOf(request);
    const body = purchaseBody.parse(request.body ?? {});

    let transaction;
    try {
      transaction = await context.appStore.verifyTransaction(body.signedTransaction);
    } catch (cause) {
      if (cause instanceof AppStoreVerificationError) {
        request.log.warn({ err: cause }, "Transaction App Store refusée");
        throw HttpError.badRequest(cause.message, "invalid_transaction");
      }
      throw cause;
    }

    await applyStoreKitTransaction(context, {
      accountId,
      transaction,
      renewal: null,
      status: null,
      ...(body.memoId === undefined ? {} : { memoId: body.memoId }),
    });

    return readProfile(context, accountId);
  });
}

/**
 * Les notifications App Store Server, **version 2** — sans session : c'est la
 * signature d'Apple qui authentifie l'appel.
 *
 * À poser dans *App Store Connect ▸ App Information ▸ App Store Server
 * Notifications*, la même adresse pour la production et le sandbox :
 * `https://<api>/v1/webhooks/app-store`.
 *
 * Même règle que le webhook Stripe : **une erreur de traitement est journalisée
 * puis acquittée**. Apple rejoue tout ce qui n'est pas un 200 pendant trois
 * jours, et un bug déterministe reviendrait à chaque fois.
 */
export function registerAppStoreWebhookRoutes(app: FastifyInstance, context: AppContext): void {
  app.post("/v1/webhooks/app-store", async (request, reply) => {
    const body = notificationBody.safeParse(request.body);
    if (!body.success) {
      return reply.code(400).send({ error: "missing_payload" });
    }

    let notification: AppStoreNotification;
    try {
      notification = await context.appStore.verifyNotification(body.data.signedPayload);
    } catch (cause) {
      if (cause instanceof AppStoreVerificationError) {
        request.log.warn({ err: cause }, "Notification App Store refusée");
        return reply.code(400).send({ error: "invalid_signature", message: cause.message });
      }
      throw cause;
    }

    const log = request.log.child({
      notificationId: notification.notificationId,
      notificationType: notification.type,
      subtype: notification.subtype,
    });

    try {
      await handleNotification(context, notification, log);
    } catch (cause) {
      log.error({ err: cause }, "Notification App Store : traitement échoué");
    }

    return reply.code(200).send({ received: true });
  });
}

type NotificationLogger = Pick<FastifyInstance["log"], "info" | "warn">;

async function handleNotification(
  context: AppContext,
  notification: AppStoreNotification,
  log: NotificationLogger,
): Promise<void> {
  // « Request a Test Notification » dans App Store Connect : la preuve que
  // l'adresse et la signature tiennent. Rien à écrire.
  if (notification.type === "TEST") {
    log.info("Notification App Store de test reçue.");
    return;
  }

  const { transaction } = notification;
  if (!transaction) {
    log.info("Notification App Store sans transaction, ignorée.");
    return;
  }

  // Un produit que le catalogue ne connaît pas n'ouvre pas l'abonnement : on
  // l'acquitte sans rien en faire. Le mensuel **et l'ancien hebdomadaire**
  // passent — les renouvellements, expirations et remboursements d'un abonné
  // de la semaine doivent continuer d'écrire sa ligne (03/10/2026).
  if (!isAcceptedAppStoreProduct(transaction.productId)) {
    log.info({ productId: transaction.productId }, "Produit App Store non traité, ignoré.");
    return;
  }

  const subscription = await applyStoreKitTransaction(context, {
    transaction,
    renewal: notification.renewal,
    status: notification.status,
    signedAt: notification.signedAt,
  });

  if (!subscription) {
    log.warn(
      { originalTransactionId: transaction.originalTransactionId },
      "Notification App Store pour un achat qu'aucun compte ne porte.",
    );
    return;
  }

  log.info(
    { subscriptionId: subscription.id, status: subscription.status },
    "Abonnement App Store mis à jour.",
  );
}
