import type { Env } from "../env.js";

/**
 * La photo de profil : ce qu'on garde, et l'adresse à laquelle l'app la lit.
 *
 * **On garde une clé de stockage, jamais une URL.** Le stockage ne sait
 * produire que des liens signés, qui expirent en une heure — un avatar, lui,
 * s'affiche tous les jours, sur le profil, l'accueil, la file des
 * co-voyageurs d'un voyage. Il passe donc par l'API : `GET /v1/avatars/:file`
 * lit l'objet et le sert, **sans session** — `AsyncImage` n'envoie pas
 * d'en-tête, et un avatar se montre à ceux qui partagent le voyage. La clé est
 * un UUID : elle ne se devine pas, et c'est tout ce qu'un avatar demande.
 *
 * L'adresse se calcule à la lecture, jamais à l'écriture : changer d'hôte ne
 * demande alors aucune migration. Voir `publicApiBaseUrl`.
 */

/** Le préfixe des objets dans le stockage. */
export const AVATAR_PREFIX = "avatars";

/** Ce qu'un nom de fichier d'avatar a le droit d'être : un UUID et une image. */
export const AVATAR_FILENAME = /^[0-9a-f-]{36}\.(jpg|jpeg|png)$/;

/** Le type MIME de la réponse, d'après l'extension retenue à l'écriture. */
export function avatarMimeType(filename: string): string {
  return filename.endsWith(".png") ? "image/png" : "image/jpeg";
}

/**
 * L'adresse publique de l'API, sans barre finale.
 *
 * `API_PUBLIC_BASE_URL` d'abord ; sinon `APP_LINK_BASE_URL`, qui est
 * l'adresse de l'API en production (voir `env.ts`) ; sinon la boucle locale du
 * développement — celle que le simulateur vise.
 */
export function publicApiBaseUrl(env: Pick<Env, "API_PUBLIC_BASE_URL" | "APP_LINK_BASE_URL">) {
  const configured = env.API_PUBLIC_BASE_URL.trim();
  if (configured) return configured.replace(/\/+$/, "");
  if (/^https?:\/\//.test(env.APP_LINK_BASE_URL)) {
    return env.APP_LINK_BASE_URL.replace(/\/+$/, "");
  }
  return "http://localhost:3000";
}

/**
 * La racine retenue pour la session du serveur — posée une fois par
 * `configureAvatarUrls` au démarrage (`buildApp`), lue par tous les
 * sérialiseurs. Une variable de module plutôt qu'un `env` passé à chaque
 * appel : `serializeCompanion` et `serializeOwner` sont appelés au fond de
 * `serializeTrip`, et faire descendre la configuration à travers six
 * signatures pour une racine d'URL n'apprendrait rien à personne.
 */
let configuredBaseUrl = "http://localhost:3000";

export function configureAvatarUrls(
  env: Pick<Env, "API_PUBLIC_BASE_URL" | "APP_LINK_BASE_URL">,
): void {
  configuredBaseUrl = publicApiBaseUrl(env);
}

/**
 * L'URL que l'app affiche pour un compte : sa photo envoyée depuis le profil
 * d'abord, sinon celle qu'un fournisseur a donnée (`avatarUrl`), sinon rien.
 */
export function avatarUrlOf(account: {
  avatarStorageKey: string | null;
  avatarUrl: string | null;
}): string | null {
  if (account.avatarStorageKey) {
    const filename = account.avatarStorageKey.slice(AVATAR_PREFIX.length + 1);
    return `${configuredBaseUrl}/v1/avatars/${filename}`;
  }
  return account.avatarUrl ?? null;
}
