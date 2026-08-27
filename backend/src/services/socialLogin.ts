import type { Env } from "../env.js";
import { HttpError } from "../lib/httpError.js";

export const SOCIAL_PROVIDERS = ["apple", "google", "facebook"] as const;
export type SocialProvider = (typeof SOCIAL_PROVIDERS)[number];

/** Ce qu'un fournisseur nous apprend sur la personne qui vient de s'authentifier. */
export interface SocialProfile {
  /** Identifiant stable chez le fournisseur. Jamais l'email : Apple le masque. */
  subject: string;
  email?: string;
  firstName?: string;
  lastName?: string;
}

export interface SocialVerifier {
  verify(provider: SocialProvider, credential: string): Promise<SocialProfile>;
}

/**
 * Vérification réelle des jetons d'identité (JWT Apple, `id_token` Google,
 * jeton d'accès Facebook). **Pas encore écrite** : elle demande les client IDs
 * des trois fournisseurs, qui ne sont pas encore créés.
 *
 * Elle échoue franchement plutôt que de laisser passer : accepter un jeton non
 * vérifié en production, c'est laisser n'importe qui se connecter en tant que
 * n'importe qui.
 */
export class UnconfiguredSocialVerifier implements SocialVerifier {
  async verify(provider: SocialProvider): Promise<SocialProfile> {
    throw new HttpError(
      503,
      `La connexion ${provider} n'est pas encore configurée sur ce serveur.`,
      "social_provider_unavailable",
    );
  }
}

/**
 * Double des tests et du développement local, actif uniquement hors mode
 * `live`. Le « jeton » est lu tel quel : `apple:sub-123`, ou une forme longue
 * `apple:sub-123|cla@exemple.fr|Cla|Thioll`.
 */
export class FakeSocialVerifier implements SocialVerifier {
  async verify(provider: SocialProvider, credential: string): Promise<SocialProfile> {
    const [prefix, ...rest] = credential.split(":");
    if (prefix !== provider || rest.length === 0) {
      throw HttpError.badRequest(
        "Jeton de connexion invalide.",
        "invalid_social_token",
      );
    }

    const [subject, email, firstName, lastName] = rest.join(":").split("|");
    if (!subject) {
      throw HttpError.badRequest(
        "Jeton de connexion invalide.",
        "invalid_social_token",
      );
    }

    return {
      subject,
      ...(email ? { email } : {}),
      ...(firstName ? { firstName } : {}),
      ...(lastName ? { lastName } : {}),
    };
  }
}

export function createSocialVerifier(env: Env): SocialVerifier {
  return env.live ? new UnconfiguredSocialVerifier() : new FakeSocialVerifier();
}

/**
 * Un email relais Apple (`xxxx@privaterelay.appleid.com`) est accepté tel quel :
 * Apple fait suivre le courrier vers la vraie boîte tant que l'accès n'est pas
 * révoqué. On ne force personne à saisir une adresse personnelle.
 */
export function isAppleRelayEmail(email: string): boolean {
  return email.toLowerCase().endsWith("@privaterelay.appleid.com");
}
