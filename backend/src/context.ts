import { PrismaClient } from "@prisma/client";
import pino, { type Logger } from "pino";
import type { Env } from "./env.js";
import { InlineQueue, PgBossQueue, type JobQueue } from "./jobs/queue.js";
import { createBookRenderer, type BookRenderer } from "./services/apitemplate.js";
import { createRedactor, type Redactor } from "./services/redaction.js";
import { createSocialVerifier, type SocialVerifier } from "./services/socialIdentity.js";
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

  const base: AppContext = {
    env,
    logger,
    prisma: new PrismaClient({ datasourceUrl: env.DATABASE_URL }),
    queue:
      env.NODE_ENV === "test" ? new InlineQueue() : new PgBossQueue(env.DATABASE_URL),
    storage: createMediaStorage(env),
    socialVerifier: createSocialVerifier(env),
    transcriber: createTranscriber(env),
    redactor: createRedactor(env),
    structurer: createStructurer(env),
    publisher: createAssetPublisher(env),
    renderer: createBookRenderer(env),
  };

  return { ...base, ...options.overrides };
}
