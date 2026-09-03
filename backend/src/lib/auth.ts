import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * Authentification provisoire par appareil, le temps que les comptes
 * utilisateur arrivent. L'app s'enregistre une fois et conserve son token ;
 * le serveur n'en garde qu'une empreinte.
 *
 * Quand l'auth réelle arrivera, seul `resolveDevice` (src/plugins/auth.ts) est
 * à remplacer — routes et jobs ne connaissent que `request.deviceId`.
 */
export function generateDeviceToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashDeviceToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** Les tokens de session se hachent pareil : même algorithme, même usage. */
export const hashSessionToken = hashDeviceToken;

/** Comparaison à temps constant, pour ne pas fuiter d'information par timing. */
export function tokenHashEquals(a: string, b: string): boolean {
  const bufferA = Buffer.from(a, "hex");
  const bufferB = Buffer.from(b, "hex");
  if (bufferA.length !== bufferB.length) return false;
  return timingSafeEqual(bufferA, bufferB);
}

/**
 * Token de session d'un compte. Même forme que celui d'un appareil — opaque,
 * tiré au hasard, stocké haché — et pour la même raison : le serveur peut le
 * révoquer en supprimant une ligne.
 *
 * On ne signe pas de JWT ici. Un JWT reste valable jusqu'à son expiration même
 * après un mot de passe changé ou un appareil perdu ; ce serait échanger une
 * requête en base contre une fenêtre pendant laquelle on ne sait plus fermer la
 * porte.
 */
export function generateSessionToken(): string {
  return randomBytes(32).toString("base64url");
}

/** Durée de vie d'une session. Repoussée à chaque usage — voir `requireAccount`. */
export const SESSION_TTL_DAYS = 90;

export function sessionExpiry(from: Date = new Date()): Date {
  return new Date(from.getTime() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000);
}

/** Extrait le token d'un en-tête `Authorization: Bearer <token>`. */
export function parseBearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match?.[1]?.trim() || null;
}
