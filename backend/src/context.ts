import { PrismaClient } from "@prisma/client";
import pino, { type Logger } from "pino";
import type { Env } from "./env.js";
import { InlineQueue, PgBossQueue, type JobQueue } from "./jobs/queue.js";
import { splitPoolBudget, withConnectionLimit } from "./lib/databasePool.js";
import { SchemaGuard } from "./lib/schemaGuard.js";
import { createAppStoreVerifier, type AppStoreVerifier } from "./services/appStore.js";
import { createBookRenderer, type BookRenderer } from "./services/apitemplate.js";
import { createRedactor, type Redactor } from "./services/redaction.js";
import { createResponder, type MemoResponder } from "./services/conversation.js";
import { createSocialVerifier, type SocialVerifier } from "./services/socialIdentity.js";
import { createMailer, type Mailer } from "./services/mailer.js";
import { createPaymentGateway, type PaymentGateway } from "./services/payments.js";
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
  /** Dit si la base a toutes les migrations que ce code attend — voir `lib/schemaGuard.ts`. */
  schema: SchemaGuard;
  queue: JobQueue;
  storage: MediaStorage;
  /** Vérifie les jetons d'identité Apple et Google. */
  socialVerifier: SocialVerifier;
  /** Envoie les e-mails de l'app : le mot de passe oublié, et l'export des données. */
  mailer: Mailer;
  transcriber: Transcriber;
  redactor: Redactor;
  /** MEMO, dans la conversation — voir `services/conversation.ts`. */
  responder: MemoResponder;
  structurer: Structurer;
  publisher: AssetPublisher;
  renderer: BookRenderer;
  /** Encaissement Stripe : carnets imprimés et cagnotte. Jamais l'abonnement. */
  payments: PaymentGateway;
  /** L'abonnement : vérifie ce qu'Apple signe — voir `services/appStore.ts`. */
  appStore: AppStoreVerifier;
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

  const base: Omit<AppContext, "schema"> = {
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
    responder: createResponder(env),
    structurer: createStructurer(env),
    publisher: createAssetPublisher(env),
    renderer: createBookRenderer(env),
    payments: createPaymentGateway(env),
    appStore: createAppStoreVerifier(env),
  };

  const context = { ...base, ...options.overrides };
  // Construit après les surcharges : le garde lit la base que le reste lit.
  return { ...context, schema: options.overrides?.schema ?? new SchemaGuard(context.prisma) };
}
