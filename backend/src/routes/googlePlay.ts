import type { FastifyBaseLogger, FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { isDatabaseUnavailable } from "../lib/databasePool.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import {
  GOOGLE_PLAY_NOTIFICATION,
  GooglePlayNotConfiguredError,
  GooglePlayPurchaseError,
  GooglePlayPushRejectedError,
  GooglePlayUnavailableError,
  parsePushMessage,
  type GooglePlayNotification,
  type GooglePlayPurchase,
} from "../services/googlePlay.js";
import {
  applyGooglePlayPurchase,
  isWritableGooglePlayState,
  needsAcknowledgement,
} from "../services/googlePlaySubscriptions.js";
import { isAcceptedGooglePlayProduct } from "../services/subscriptionCatalog.js";
import { readProfile } from "./profile.js";

/**
 * L'abonnement acheté par Google Play — voir `services/googlePlay.ts` et
 * `services/googlePlaySubscriptions.ts`. Les deux mêmes portes que pour
 * l'App Store (`routes/appStore.ts`) : l'app après l'achat, Google pour tout
 * le reste.
 */

const purchaseBody = z.object({
  /** `Purchase.purchaseToken`, tel que Google Play Billing le rend. */
  purchaseToken: z.string().min(1).max(4096),
  productId: z.string().min(1),
  /** Le voyage que l'achat finance ; l'app envoie `null` hors d'un voyage. */
  memoId: z.string().uuid().nullish(),
});

/** Les routes de l'app — derrière une session de compte. */
export function registerGooglePlayRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * L'app vient d'acheter, de restaurer, ou retrouve au lancement un achat
   * qu'elle n'a pas vu acquitté (`SubscriptionStore.deliverUnfinished`).
   *
   * Les codes sont ceux qu'attend l'app (`AppDependencies.deliveringTransaction`) :
   * **400, 403 et 409 sont définitifs** — elle n'y revient plus pour ce jeton ;
   * tout le reste (503 compris) laisse l'achat non acquitté, et elle le
   * renverra.
   *
   * ⚠️ **On acquitte ici, après l'écriture.** Un acquittement qui échoue ne
   * fait pas échouer la route : l'abonnement est ouvert, l'app voit toujours
   * l'achat non acquitté et le renverra au prochain lancement, et la
   * notification `SUBSCRIPTION_PURCHASED` retente de son côté. Google laisse
   * trois jours.
   */
  app.post("/v1/subscriptions/google-play", async (request) => {
    const accountId = accountIdOf(request);
    const body = purchaseBody.parse(request.body ?? {});

    if (!isAcceptedGooglePlayProduct(body.productId)) {
      throw HttpError.badRequest(`Produit Google Play inconnu : ${body.productId}.`, "unknown_product");
    }

    const purchase = await readPurchase(context, body.purchaseToken, request.log);

    if (purchase.productId !== body.productId) {
      throw HttpError.badRequest("Ce jeton n'est pas un achat de ce produit.", "product_mismatch");
    }
    if (purchase.state === "pending") {
      // Pas encore payé (un paiement en espèces, une carte à valider) : pas
      // un refus — l'app le renverra quand Google l'aura conclu.
      throw new HttpError(422, "Cet achat Google Play n'est pas encore payé.", "purchase_pending");
    }
    if (!isWritableGooglePlayState(purchase.state)) {
      throw HttpError.badRequest("Cet achat Google Play n'a pas abouti.", "invalid_purchase");
    }

    const subscription = await applyGooglePlayPurchase(context, {
      accountId,
      purchase,
      ...(body.memoId ? { memoId: body.memoId } : {}),
    });

    if (subscription) await acknowledge(context, purchase, request.log);

    return readProfile(context, accountId);
  });
}

async function readPurchase(
  context: AppContext,
  purchaseToken: string,
  log: FastifyBaseLogger,
): Promise<GooglePlayPurchase> {
  try {
    return await context.googlePlay.readSubscription(purchaseToken);
  } catch (cause) {
    if (cause instanceof GooglePlayNotConfiguredError) {
      log.error({ err: cause }, "Google Play non configuré : achat Android refusé.");
      throw new HttpError(
        503,
        "L'abonnement Google Play n'est pas encore disponible sur ce serveur.",
        "google_play_unavailable",
      );
    }
    if (cause instanceof GooglePlayPurchaseError) {
      log.warn({ err: cause }, "Achat Google Play refusé");
      throw HttpError.badRequest(cause.message, "invalid_purchase");
    }
    if (cause instanceof GooglePlayUnavailableError) {
      log.warn({ err: cause }, "Google Play injoignable");
      throw new HttpError(503, "Google Play ne répond pas. Réessaie dans un instant.", "google_play_unreachable");
    }
    throw cause;
  }
}

async function acknowledge(context: AppContext, purchase: GooglePlayPurchase, log: FastifyBaseLogger) {
  if (!needsAcknowledgement(purchase)) return;
  try {
    await context.googlePlay.acknowledge(purchase);
  } catch (cause) {
    log.error({ err: cause, orderId: purchase.orderId }, "Acquittement Google Play échoué — à retenter.");
  }
}

/**
 * Les notifications temps réel de Google Play (*Real-time developer
 * notifications*), poussées par **Pub/Sub** — sans session : c'est le jeton
 * OIDC du push (ou le secret partagé de l'URL) qui authentifie l'appel. Voir
 * `GOOGLE_PLAY_PUSH_AUDIENCE` dans `env.ts`.
 *
 * À poser dans *Play Console ▸ Monétiser ▸ Configuration de la monétisation ▸
 * Notifications en temps réel* : le sujet Pub/Sub, et un abonnement **push**
 * vers `https://<api>/v1/webhooks/google-play`.
 *
 * Pub/Sub rejoue tout ce qui n'est pas un 2xx, sept jours durant. Même règle
 * que le webhook App Store : une erreur qui se reproduirait à l'identique est
 * journalisée puis acquittée ; une base ou un Google injoignables répondent
 * 503, et Pub/Sub renverra.
 */
export function registerGooglePlayWebhookRoutes(app: FastifyInstance, context: AppContext): void {
  app.post("/v1/webhooks/google-play", async (request, reply) => {
    const query = request.query as Record<string, unknown> | undefined;
    try {
      await context.googlePlay.verifyPush({
        authorization: request.headers.authorization,
        secret: typeof query?.["secret"] === "string" ? query["secret"] : undefined,
      });
    } catch (cause) {
      if (cause instanceof GooglePlayNotConfiguredError) {
        request.log.error({ err: cause }, "Webhook Google Play non configuré.");
        return reply.code(503).send({ error: "webhook_not_configured", message: cause.message });
      }
      if (cause instanceof GooglePlayPushRejectedError) {
        request.log.warn({ err: cause }, "Notification Google Play refusée");
        return reply.code(401).send({ error: "unauthorized", message: cause.message });
      }
      throw cause;
    }

    const notification = parsePushMessage(request.body);
    if (!notification) {
      // Authentifié mais illisible : le rejouer n'y changerait rien.
      request.log.warn("Notification Google Play illisible, acquittée.");
      return reply.code(200).send({ received: true });
    }

    const log = request.log.child({
      packageName: notification.packageName,
      notificationType: notification.subscription?.notificationType ?? (notification.voided ? "voided" : null),
    });

    try {
      await handleNotification(context, notification, log);
    } catch (cause) {
      log.error({ err: cause }, "Notification Google Play : traitement échoué");
      if (isDatabaseUnavailable(cause) || cause instanceof GooglePlayUnavailableError) {
        return reply.code(503).send({ error: "temporarily_unavailable" });
      }
    }

    return reply.code(200).send({ received: true });
  });
}

type NotificationLogger = Pick<FastifyBaseLogger, "info" | "warn" | "error">;

async function handleNotification(
  context: AppContext,
  notification: GooglePlayNotification,
  log: NotificationLogger,
): Promise<void> {
  // « Envoyer une notification de test » dans la Play Console : la preuve que
  // le sujet, l'abonnement push et l'authentification tiennent.
  if (notification.isTest) {
    log.info("Notification Google Play de test reçue.");
    return;
  }

  if (notification.packageName !== context.googlePlay.packageName) {
    log.warn("Notification Google Play pour un autre paquet, ignorée.");
    return;
  }

  // Le remboursement d'un abonnement (`productType` 1). Un achat unique n'a
  // rien à faire ici : MemoBook n'en vend pas sur Google Play.
  if (notification.voided) {
    if (notification.voided.productType !== null && notification.voided.productType !== 1) {
      log.info("Achat unique remboursé, ignoré.");
      return;
    }
    await refresh(context, notification.voided.purchaseToken, log, {
      revoked: true,
      revokedOrderId: notification.voided.orderId,
    });
    return;
  }

  if (!notification.subscription) {
    log.info("Notification Google Play sans abonnement, ignorée.");
    return;
  }

  const { notificationType, purchaseToken } = notification.subscription;
  await refresh(context, purchaseToken, log, {
    revoked: notificationType === GOOGLE_PLAY_NOTIFICATION.revoked,
    revokedOrderId: null,
  });
}

/** Relit l'abonnement chez Google, l'écrit, et l'acquitte s'il ne l'est pas. */
async function refresh(
  context: AppContext,
  purchaseToken: string,
  log: NotificationLogger,
  options: { revoked: boolean; revokedOrderId: string | null },
): Promise<void> {
  let purchase: GooglePlayPurchase;
  try {
    purchase = await context.googlePlay.readSubscription(purchaseToken);
  } catch (cause) {
    // Un jeton que Google ne connaît plus ne reviendra pas : acquitté.
    if (cause instanceof GooglePlayPurchaseError) {
      log.warn({ err: cause }, "Notification Google Play pour un jeton inconnu, ignorée.");
      return;
    }
    // Non configuré : Pub/Sub doit renvoyer, une fois la clé posée.
    if (cause instanceof GooglePlayNotConfiguredError) {
      throw new GooglePlayUnavailableError(cause.message);
    }
    throw cause;
  }

  if (!isAcceptedGooglePlayProduct(purchase.productId)) {
    log.info({ productId: purchase.productId }, "Produit Google Play non traité, ignoré.");
    return;
  }
  if (!isWritableGooglePlayState(purchase.state)) {
    log.info({ state: purchase.state }, "Achat Google Play pas encore payé, rien à écrire.");
    return;
  }

  const subscription = await applyGooglePlayPurchase(context, {
    purchase,
    revoked: options.revoked,
    revokedOrderId: options.revokedOrderId,
  });

  if (!subscription) {
    // Personne à qui ouvrir l'abonnement : on n'acquitte pas. Si l'app le
    // remet dans les trois jours, il s'ouvrira ; sinon Google rembourse.
    log.warn({ orderId: purchase.orderId }, "Notification Google Play pour un achat qu'aucun compte ne porte.");
    return;
  }

  if (needsAcknowledgement(purchase)) {
    try {
      await context.googlePlay.acknowledge(purchase);
    } catch (cause) {
      log.error({ err: cause, orderId: purchase.orderId }, "Acquittement Google Play échoué — à retenter.");
      throw cause;
    }
  }

  log.info(
    { subscriptionId: subscription.id, status: subscription.status },
    "Abonnement Google Play mis à jour.",
  );
}
