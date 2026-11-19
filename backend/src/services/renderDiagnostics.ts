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

/**
 * **Ce qui casse en silence** — l'état de la chaîne, lisible d'un `curl`
 * (T274, 19/11/2026).
 *
 * Deux fois en un mois, la composition des carnets s'est arrêtée sans que rien
 * ne le dise : fin octobre le crédit Anthropic était épuisé, le 17/11 c'est
 * celui d'OpenAI — « You have no credits remaining ». `/health` répondait
 * `ok` les deux fois, parce qu'il ne regarde que la base, la file et le
 * schéma : tout ce qui **tient le service debout**, rien de ce qu'il
 * **produit**.
 *
 * Ces trois chiffres ne coûtent rien (deux `count` et une lecture), ne font
 * **pas** tomber `/health` — un rendu raté ne doit pas bloquer un
 * déploiement ni tuer le service — et répondent à la seule question qu'on se
 * pose en revenant d'un week-end : est-ce que les carnets sortent encore ?
 */
export interface PipelineDiagnostic {
  /** Rendus échoués dans les 24 dernières heures. */
  rendersFailedLastDay: number;
  /** Le dernier échec, s'il y en a eu un : c'est lui qui nomme la cause. */
  lastRenderError: { at: string; message: string } | null;
  /**
   * Récits (jamais les photos : elles n'ont rien à rédiger) en attente de
   * rédaction depuis **plus d'une heure**. Une rédaction fraîche est normale ;
   * une qui dure est un souvenir qui n'entrera jamais dans un carnet, et qui
   * bloque sa composition.
   */
  memoriesAwaitingRedaction: number;
}

interface PipelineReader {
  render: {
    count(args: unknown): Promise<number>;
    findFirst(args: unknown): Promise<{ createdAt: Date; error: string | null } | null>;
  };
  entry: { count(args: unknown): Promise<number> };
}

/**
 * Le diagnostic est **gardé une minute** : `/health` est interrogé par Railway
 * à chaque battement, et trois requêtes par battement finiraient par peser sur
 * une table qui grossit.
 */
let cached: { at: number; value: PipelineDiagnostic } | null = null;
const CACHE_MS = 60_000;

export async function pipelineDiagnostic(
  prisma: PipelineReader,
  now: Date = new Date(),
): Promise<PipelineDiagnostic> {
  if (cached && now.getTime() - cached.at < CACHE_MS) return cached.value;

  const since = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const anHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

  const [rendersFailedLastDay, lastFailure, memoriesAwaitingRedaction] = await Promise.all([
    prisma.render.count({ where: { status: "failed", createdAt: { gte: since } } }),
    prisma.render.findFirst({
      where: { status: "failed" },
      orderBy: { createdAt: "desc" },
      select: { createdAt: true, error: true },
    }),
    prisma.entry.count({
      where: {
        redactionStatus: "pending",
        kind: { not: "photo" },
        createdAt: { lt: anHourAgo },
      },
    }),
  ]);

  const value: PipelineDiagnostic = {
    rendersFailedLastDay,
    lastRenderError: lastFailure
      ? {
          at: lastFailure.createdAt.toISOString(),
          // Tronqué : certaines erreurs de fournisseur tiennent sur dix lignes,
          // et c'est la première qui nomme la cause.
          message: (lastFailure.error ?? "").slice(0, 300),
        }
      : null,
    memoriesAwaitingRedaction,
  };

  cached = { at: now.getTime(), value };
  return value;
}

/** Pour les tests : le diagnostic suivant sera recalculé. */
export function forgetPipelineDiagnostic(): void {
  cached = null;
}
