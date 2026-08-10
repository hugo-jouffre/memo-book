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

/** Comparaison à temps constant, pour ne pas fuiter d'information par timing. */
export function tokenHashEquals(a: string, b: string): boolean {
  const bufferA = Buffer.from(a, "hex");
  const bufferB = Buffer.from(b, "hex");
  if (bufferA.length !== bufferB.length) return false;
  return timingSafeEqual(bufferA, bufferB);
}

/** Extrait le token d'un en-tête `Authorization: Bearer <token>`. */
export function parseBearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match?.[1]?.trim() || null;
}
