import { hash, verify } from "@node-rs/argon2";

/**
 * Politique de mot de passe, partagée mot pour mot avec l'app iOS
 * (`MemoBookCore/PasswordPolicy.swift`). Le client valide pour donner un retour
 * immédiat, le serveur revalide parce qu'un client n'est jamais une garantie.
 *
 * ⚠️ Les critères ci-dessous sont une proposition : le détail fonctionnel dit
 * « mot de passe respectant les critères de sécurité définis » sans les
 * définir. À confirmer avec Clara (voir la fiche *Sign Up*).
 */
export const PASSWORD_MIN_LENGTH = 8;

/**
 * Argon2 hache jusqu'à 4 Go d'entrée : la borne haute n'est pas là pour la
 * mémoire, mais pour qu'un corps de requête d'un mégaoctet ne devienne pas un
 * déni de service à peu de frais.
 */
export const PASSWORD_MAX_LENGTH = 200;

export type PasswordProblem = "too_short" | "too_long" | "needs_letter_and_digit";

/** `null` quand le mot de passe convient. */
export function checkPassword(password: string): PasswordProblem | null {
  if (password.length < PASSWORD_MIN_LENGTH) return "too_short";
  if (password.length > PASSWORD_MAX_LENGTH) return "too_long";
  if (!/\p{L}/u.test(password) || !/\d/.test(password)) return "needs_letter_and_digit";
  return null;
}

/** Message affichable, en français et au tutoiement (R9 de `ui-development.md`). */
export function passwordProblemMessage(problem: PasswordProblem): string {
  switch (problem) {
    case "too_short":
      return `Ton mot de passe doit faire au moins ${PASSWORD_MIN_LENGTH} caractères.`;
    case "too_long":
      return `Ton mot de passe ne peut pas dépasser ${PASSWORD_MAX_LENGTH} caractères.`;
    case "needs_letter_and_digit":
      return "Ton mot de passe doit contenir au moins une lettre et un chiffre.";
  }
}

/**
 * Argon2id aux paramètres recommandés par l'OWASP (19 Mio, 2 passes) — ce sont
 * les valeurs par défaut de `@node-rs/argon2`, écrites ici pour qu'un changement
 * soit un choix et pas un effet de bord d'une mise à jour.
 */
/**
 * `Algorithm.Argon2id`. L'énumération de `@node-rs/argon2` est un `const enum`
 * ambient, que `verbatimModuleSyntax` interdit d'importer : on écrit sa valeur.
 */
const ARGON2ID = 2;

const options = {
  algorithm: ARGON2ID,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
} as const;

export function hashPassword(password: string): Promise<string> {
  return hash(password, options);
}

/**
 * `false` plutôt qu'une exception quand l'empreinte stockée est illisible : une
 * ligne corrompue en base ne doit pas devenir un 500 sur l'écran de connexion.
 */
export async function verifyPassword(
  passwordHash: string,
  password: string,
): Promise<boolean> {
  try {
    return await verify(passwordHash, password, options);
  } catch {
    return false;
  }
}
