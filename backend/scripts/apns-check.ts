/**
 * La clé APNs posée sur un service répond-elle ? — **sans rien envoyer à
 * personne, et sans jamais afficher une valeur.**
 *
 *     railway run --service worker --environment production -- npm run apns:check
 *
 * Le client APNs du serveur, tel quel, envoie une notification à un jeton
 * d'appareil factice (soixante-quatre zéros), en sandbox puis en production.
 * Apple répond avant de regarder le téléphone :
 *
 * - `BadDeviceToken` — la clé est **acceptée**, seul le faux téléphone est
 *   refusé : c'est la réponse attendue ;
 * - `InvalidProviderToken` — la clé est **refusée** : `APNS_KEY_ID` n'est pas
 *   l'identifiant de ce `.p8` (il est dans son nom, `AuthKey_<KEY_ID>.p8`), ou
 *   la clé n'a pas le service « Apple Push Notifications service (APNs) »,
 *   ou `APNS_TEAM_ID` n'est pas l'équipe.
 *
 * Voir `docs/notifications.md` § Configuration.
 */
import { ApnsPushSender, normalizePrivateKey } from "../src/services/apns.js";

const keyId = process.env.APNS_KEY_ID ?? "";
const teamId = process.env.APNS_TEAM_ID ?? "";
const rawKey = process.env.APNS_PRIVATE_KEY ?? "";

const shape = (value: string, expected: RegExp) => (value === "" ? "absente" : expected.test(value) ? "ok" : "forme inattendue");
console.log(`APNS_KEY_ID       ${shape(keyId, /^[A-Z0-9]{10}$/)}`);
console.log(`APNS_TEAM_ID      ${teamId === "" ? "absente" : teamId === "HP2A94889S" ? "ok (HP2A94889S)" : "différente de HP2A94889S"}`);
console.log(`APNS_PRIVATE_KEY  ${rawKey === "" ? "absente" : rawKey.includes("BEGIN") ? "ok" : "sans ses lignes d'en-tête (le serveur les remet)"}`);
for (const stray of ["APPLE_PRIVATE_KEY", "APNS_KEY", "APNS_P8"]) {
  if (process.env[stray]) console.log(`${stray.padEnd(17)} posée, mais le serveur ne la lit pas : la renommer APNS_PRIVATE_KEY`);
}

if (keyId === "" || teamId === "" || rawKey === "") {
  console.log("\nIncomplet : aucune notification ne partira tant que les trois ne sont pas posées.");
  process.exit(1);
}

const sender = new ApnsPushSender(
  { keyId, teamId, privateKey: normalizePrivateKey(rawKey), topic: process.env.APPLE_BUNDLE_ID || "com.memobook.app" },
  { warn: () => {} },
);

let accepted = true;
for (const environment of ["sandbox", "production"] as const) {
  const outcome = await sender.send(
    { token: "0".repeat(64), environment },
    { deliveryId: "apns-check", title: "apns-check", body: "apns-check", link: null, threadId: "apns-check" },
  );
  const reason = outcome.kind === "sent" ? "envoyée ?!" : outcome.reason;
  const verdict = reason === "BadDeviceToken" ? "clé acceptée" : reason === "InvalidProviderToken" ? "clé REFUSÉE" : "à lire";
  if (reason !== "BadDeviceToken") accepted = false;
  console.log(`${environment.padEnd(10)} → ${reason} — ${verdict}`);
}
await sender.close();
process.exit(accepted ? 0 : 1);
