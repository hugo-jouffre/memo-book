import { PrismaClient } from "@prisma/client";
import type { FastifyInstance } from "fastify";
import pino from "pino";
import { buildApp } from "../src/app.js";
import { createContext, type AppContext } from "../src/context.js";
import { loadEnv } from "../src/env.js";

/**
 * Un back-end complet branché sur des implémentations simulées : file en ligne,
 * stockage en mémoire, transcription et rendu déterministes. Seule la base est
 * réelle — c'est elle qui porte les contraintes qu'on veut vérifier.
 */
export interface TestHarness {
  app: FastifyInstance;
  context: AppContext;
  prisma: PrismaClient;
  close(): Promise<void>;
}

export function testEnv() {
  return loadEnv({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    // `TEST_DATABASE_URL` d'abord : la suite vide les tables à chaque fichier,
    // elle ne doit jamais tomber sur la base de développement. Voir `.env`.
    DATABASE_URL:
      process.env["TEST_DATABASE_URL"] ??
      process.env["DATABASE_URL"] ??
      "postgresql://memobook:memobook@localhost:5432/memobook",
    S3_ENDPOINT: "http://localhost:9000",
    S3_BUCKET: "memobook-media",
    S3_ACCESS_KEY_ID: "test",
    S3_SECRET_ACCESS_KEY: "test",
    PIPELINE_MODE: "fake",
  });
}

export async function createHarness(
  overrides: Partial<AppContext> = {},
): Promise<TestHarness> {
  const env = testEnv();
  const context = createContext(env, {
    overrides: { logger: pino({ level: "silent" }), ...overrides },
  });
  const app = await buildApp(context);
  await app.ready();

  return {
    app,
    context,
    prisma: context.prisma,
    async close() {
      await app.close();
      await context.prisma.$disconnect();
    },
  };
}

/**
 * Vide les tables entre deux suites.
 *
 * Les tables sont nommées **une par une** plutôt que de compter sur les
 * cascades : `showcases` et `feedback_campaigns` ne dépendent de rien, et
 * seraient restées d'une suite à l'autre. Une table oubliée ici, c'est un test
 * qui passe seul et échoue en série.
 */
export async function resetDatabase(prisma: PrismaClient): Promise<void> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE ' +
      [
        "feedback_answers",
        "feedback_responses",
        "feedback_questions",
        "feedback_campaigns",
        "showcases",
        "memo_gallery_categories",
        "gallery_categories",
        "wallet_entries",
        "payment_cards",
        "subscriptions",
        "account_connectors",
        "print_orders",
        "renders",
        "entries",
        "media_assets",
        "expenses",
        "memo_steps",
        "memo_members",
        "memos",
        "devices",
        "sessions",
        "identities",
        "accounts",
      ]
        .map((table) => `"${table}"`)
        .join(", ") +
      " RESTART IDENTITY CASCADE",
  );
}

/** Ouvre un compte et renvoie l'en-tête d'autorisation de sa session. */
export async function registerAccount(
  app: FastifyInstance,
  email = "voyageur@memobook.app",
): Promise<{ accountId: string; authorization: string }> {
  const response = await app.inject({
    method: "POST",
    url: "/v1/auth/signup",
    payload: { email, password: "carnet2026", firstName: "Hugo" },
  });

  const body = response.json<{ token: string; account: { id: string } }>();
  return { accountId: body.account.id, authorization: `Bearer ${body.token}` };
}

/** Enregistre un appareil et renvoie l'en-tête d'autorisation à réutiliser. */
export async function registerDevice(
  app: FastifyInstance,
): Promise<{ deviceId: string; authorization: string }> {
  const response = await app.inject({
    method: "POST",
    url: "/v1/devices",
    payload: { platform: "ios" },
  });

  const body = response.json<{ deviceId: string; token: string }>();
  return { deviceId: body.deviceId, authorization: `Bearer ${body.token}` };
}

/** Construit un corps multipart minimal, sans dépendance supplémentaire. */
export function multipartBody(
  fields: Record<string, string>,
  file: { field: string; filename: string; contentType: string; content: Buffer },
): { payload: Buffer; contentType: string } {
  const boundary = `----memobook${Date.now()}`;
  const parts: Buffer[] = [];

  for (const [name, value] of Object.entries(fields)) {
    parts.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`,
      ),
    );
  }

  parts.push(
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="${file.field}"; filename="${file.filename}"\r\n` +
        `Content-Type: ${file.contentType}\r\n\r\n`,
    ),
    file.content,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  );

  return {
    payload: Buffer.concat(parts),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}
