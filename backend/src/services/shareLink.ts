import type { Env } from "../env.js";
import { publicApiBaseUrl } from "./avatars.js";

/**
 * **Le lien de prévisualisation d'un carnet** : `https://<hôte>/c/<jeton>`.
 *
 * Il préfixait `https://memo-book.com`, où aucune page n'a jamais répondu : le
 * lien que la feuille « Partager » et « Recevoir sur WhatsApp » envoyaient
 * menait nulle part (T229, Hugo 06/10/2026 — « configurer le lien de
 * prévisualisation au moment du partage d'un carnet »). La page existe
 * désormais, et c'est **l'API** qui la sert (`routes/sharePage.ts`) : l'hôte
 * par défaut est donc le sien (`publicApiBaseUrl`).
 *
 * `SHARE_PUBLIC_BASE_URL` reste un forçage, pour le jour où le site servira
 * `/c/…` lui-même (une réécriture vers l'API, un domaine dédié). Vide — le
 * défaut — : l'hôte de l'API.
 */
export function shareBaseUrl(
  env: Pick<Env, "SHARE_PUBLIC_BASE_URL" | "API_PUBLIC_BASE_URL" | "RAILWAY_PUBLIC_DOMAIN" | "APP_LINK_BASE_URL">,
): string {
  const forced = env.SHARE_PUBLIC_BASE_URL.trim().replace(/\/+$/, "");
  return forced || publicApiBaseUrl(env);
}

/** L'adresse publique d'un carnet partagé. */
export function shareUrlOf(env: Parameters<typeof shareBaseUrl>[0], slug: string): string {
  return `${shareBaseUrl(env)}/c/${slug}`;
}
