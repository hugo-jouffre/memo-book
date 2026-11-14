import type { Env } from "../env.js";
import { resolvePublicApiBaseUrl, type PublicBaseSource } from "./avatars.js";
import { selectedRenderer, type RendererKind } from "./apitemplate.js";

/**
 * **Pourquoi un carnet sort sans photos**, répondu sans ouvrir Railway.
 *
 * Les trois pannes qui donnent un carnet vide sont toutes des pannes de
 * configuration, et aucune ne se voit : le carnet se compose, se déclare prêt,
 * et n'a pas une image (Hugo, 11 puis 13/11/2026).
 *
 * 1. Le moteur est **simulé** — `RENDERER=auto` sans `APITEMPLATE_API_KEY`.
 * 2. L'adresse des photos est une **boucle locale**, que le moteur, qui
 *    télécharge depuis ses serveurs, ne joindra jamais.
 * 3. L'adresse posée n'a **pas de protocole** — `api.exemple.fr` au lieu de
 *    `https://api.exemple.fr`. Collée à un chemin, elle ne joint rien.
 * 4. L'adresse est juste mais vient d'un **repli** (`APP_LINK_BASE_URL`,
 *    faite pour les liens des e-mails) : juste aujourd'hui, fausse le jour où
 *    cette variable-là changera de valeur.
 *
 * Le worker n'a ni domaine ni contrôle de santé : il **annonce** donc ce
 * diagnostic au démarrage, dans ses logs. L'API, elle, le sert dans `/health`.
 * Rien ici n'est secret : un nom de moteur et une adresse déjà publique.
 */

export interface PhotosDiagnostic {
  /** Le moteur qui composera le carnet. */
  renderer: RendererKind;
  /** La racine où le moteur ira chercher `GET /v1/trip-photos/:file`. */
  photoBaseUrl: string;
  /** Le maillon qui a donné cette racine. */
  photoBaseUrlFrom: PublicBaseSource;
  /** Vide quand rien ne s'oppose à des photos dans le carnet. */
  problems: string[];
}

type DiagnosticEnv = Pick<
  Env,
  | "API_PUBLIC_BASE_URL"
  | "RAILWAY_PUBLIC_DOMAIN"
  | "APP_LINK_BASE_URL"
  | "NODE_ENV"
  | "RENDERER"
  | "APITEMPLATE_API_KEY"
  | "live"
>;

const LOOPBACK = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])([:/]|$)/i;

export function photosDiagnostic(env: DiagnosticEnv): PhotosDiagnostic {
  const { url, from, schemeAssumed } = resolvePublicApiBaseUrl(env);
  const renderer = selectedRenderer(env);
  const production = env.NODE_ENV === "production";
  const problems: string[] = [];

  // Avant tout le reste, et quel que soit le moteur : une variable mal écrite
  // est un défaut de configuration, pas une conséquence du rendu choisi.
  if (schemeAssumed) {
    problems.push(
      `API_PUBLIC_BASE_URL ne porte pas son protocole : on a supposé ${url}. Écris l'adresse entière, https:// compris.`,
    );
  }

  if (renderer === "fake") {
    problems.push(
      "Le moteur de PDF est simulé : le carnet sortira sans mise en page ni photos. Pose APITEMPLATE_API_KEY, ou RENDERER=local sur une machine de développement.",
    );
  }

  // Un moteur `local` compose sur place, avec son propre Chromium : une
  // boucle locale lui va très bien. Les deux reproches qui suivent ne
  // concernent donc que le moteur qui télécharge depuis ses serveurs.
  if (renderer === "apitemplate") {
    if (LOOPBACK.test(url)) {
      problems.push(
        `Les photos seraient servies sur ${url}, que le moteur de PDF ne peut pas joindre : pose API_PUBLIC_BASE_URL sur ce service.`,
      );
    } else if (production && from !== "API_PUBLIC_BASE_URL") {
      problems.push(
        `L'adresse des photos vient de ${from}, pas de API_PUBLIC_BASE_URL : elle est juste aujourd'hui, mais rien ne la tient. Pose API_PUBLIC_BASE_URL sur ce service.`,
      );
    }

    if (production && url.startsWith("http://")) {
      problems.push(`L'adresse des photos n'est pas en https : ${url}.`);
    }
  }

  return { renderer, photoBaseUrl: url, photoBaseUrlFrom: from, problems };
}
