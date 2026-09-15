import { PrismaClient } from "@prisma/client";
import pino, { type Logger } from "pino";
import type { Env } from "./env.js";
import { InlineQueue, PgBossQueue, type JobQueue } from "./jobs/queue.js";
import { splitPoolBudget, withConnectionLimit } from "./lib/databasePool.js";
import { createBookRenderer, type BookRenderer } from "./services/apitemplate.js";
import { createRedactor, type Redactor } from "./services/redaction.js";
import { createSocialVerifier, type SocialVerifier } from "./services/socialIdentity.js";
import { createMailer, type Mailer } from "./services/mailer.js";
import { createMediaStorage, type MediaStorage } from "./services/storage.js";
import { createStructurer, type Structurer } from "./services/structuring.js";
import { createTranscriber, type Transcriber } from "./services/transcription.js";
import { createAssetPublisher, type AssetPublisher } from "./services/webflow.js";

/**
 * Toutes les dépendances du back-end, résolues une fois au démarrage. Les
 * routes et les jobs ne construisent jamais leurs propres clients : ils
 * reçoivent ce contexte, ce qui rend le pipeline testable de bout en bout avec
 * des implémentations simulées.
 */
export interface AppContext {
  env: Env;
  logger: Logger;
  prisma: PrismaClient;
  queue: JobQueue;
  storage: MediaStorage;
  /** Vérifie les jetons d'identité Apple et Google. */
  socialVerifier: SocialVerifier;
  /** Envoie les e-mails de l'app — aujourd'hui, celui du mot de passe oublié. */
  mailer: Mailer;
  transcriber: Transcriber;
  redactor: Redactor;
  structurer: Structurer;
  publisher: AssetPublisher;
  renderer: BookRenderer;
}

export interface CreateContextOptions {
  /** Surcharges pour les tests. */
  overrides?: Partial<AppContext>;
}

export function createContext(env: Env, options: CreateContextOptions = {}): AppContext {
  const logger = pino({ level: env.LOG_LEVEL });
  const pool = splitPoolBudget(env.DATABASE_POOL_SIZE);

  const queue =
    env.NODE_ENV === "test"
      ? new InlineQueue()
      : new PgBossQueue(env.DATABASE_URL, { maxConnections: pool.boss });

  // Les pannes de la file vont dans les logs du serveur — et nulle part
  // ailleurs. Sans écouteur, Node relancerait l'événement `error` d'un
  // `EventEmitter` et terminerait le processus : une file en carafe emporterait
  // l'API avec elle. Voir `PgBossQueue`.
  if (queue instanceof PgBossQueue) {
    queue.onError = (error) => logger.error({ err: error }, "Panne de la file de travaux.");
  }

  const base: AppContext = {
    env,
    logger,
    prisma: new PrismaClient({
      datasourceUrl: withConnectionLimit(env.DATABASE_URL, pool.prisma),
    }),
    queue,
    storage: createMediaStorage(env),
    socialVerifier: createSocialVerifier(env),
    mailer: createMailer(env, logger),
    transcriber: createTranscriber(env),
    redactor: createRedactor(env),
    structurer: createStructurer(env),
    publisher: createAssetPublisher(env),
    renderer: createBookRenderer(env),
  };

  return { ...base, ...options.overrides };
}
