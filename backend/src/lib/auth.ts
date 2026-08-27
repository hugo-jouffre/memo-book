import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * Les jetons porteurs du back-end. Trois familles, un seul mécanisme : 32
 * octets aléatoires côté client, une empreinte SHA-256 côté serveur.
 *
 *   - **appareil** — l'identité anonyme du premier lancement, avant tout compte
 *   - **session** — une connexion ouverte sur un compte (`POST /v1/auth/login`)
 *   - **réinitialisation** — le jeton porté par le lien reçu par email
 *
 * SHA-256 et non Argon2 : ces jetons sont déjà 256 bits d'aléa, il n'y a pas de
 * dictionnaire à ralentir. Un mot de passe, lui, passe par `lib/password.ts`.
 */
export function generateToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
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

/**
 * Forme canonique d'une adresse email : minuscules, sans espaces autour. C'est
 * elle qui est stockée et comparée — sans quoi « Cla@… » et « cla@… » seraient
 * deux comptes.
 */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}
