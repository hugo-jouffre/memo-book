/**
 * Le compte de service FCM posé sur un service répond-il ? — **sans rien
 * envoyer à personne, et sans jamais afficher une valeur.** Le jumeau de
 * `apns-check.ts` (lot B3, 22/10/2026).
 *
 *     railway run --service worker --environment production -- npm run fcm:check
 *
 * Le client FCM du serveur, tel quel, demande un jeton d'accès à Google puis
 * envoie un message à un jeton d'appareil factice. FCM répond avant de
 * chercher le téléphone :
 *
 * - `INVALID_ARGUMENT` ou `UNREGISTERED` — le compte de service est
 *   **accepté**, seul le faux téléphone est refusé : la réponse attendue ;
 * - `Compte de service FCM refusé…`, `PERMISSION_DENIED`, `UNAUTHENTICATED` —
 *   le JSON n'est pas celui du projet, ou l'API « Firebase Cloud Messaging »
 *   n'y est pas activée.
 *
 * Voir `docs/notifications.md` § Configuration.
 */
import { FcmPushSender, readFcmCredentials } from "../src/services/fcm.js";

const read = readFcmCredentials(process.env.FCM_SERVICE_ACCOUNT_JSON ?? "", process.env.FCM_PROJECT_ID ?? "");
if (read === null) {
  console.log("FCM_SERVICE_ACCOUNT_JSON absente : aucune notification Android ne partira.");
  process.exit(1);
}
if ("error" in read) {
  console.log(read.error);
  process.exit(1);
}
console.log(`FCM_SERVICE_ACCOUNT_JSON ok — projet ${read.credentials.projectId}`);

const sender = new FcmPushSender(read.credentials, { warn: () => {} });
const outcome = await sender.send(
  { token: "fcm-check-jeton-factice", environment: "production", provider: "fcm" },
  { deliveryId: "fcm-check", title: "fcm-check", body: "fcm-check", link: null, threadId: "fcm-check" },
);
const reason = outcome.kind === "sent" ? "envoyée ?!" : outcome.reason;
const accepted = reason === "INVALID_ARGUMENT" || reason === "UNREGISTERED";
console.log(`→ ${reason} — ${accepted ? "compte de service accepté" : "à lire"}`);
process.exit(accepted ? 0 : 1);
