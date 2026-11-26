import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PrismaClient } from "@prisma/client";
import type { FastifyInstance } from "fastify";
import pino from "pino";
import { STRUCTURE_TIMING } from "../src/jobs/structure.js";
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

/**
 * **La base que la suite vide — et jamais celle de développement.**
 *
 * Le commentaire d'avant disait déjà « elle ne doit jamais tomber sur la base
 * de développement », et le code retombait dessus : `TEST_DATABASE_URL` absent
 * de `backend/.env`, `npm run test` visait `DATABASE_URL`, c'est-à-dire la base
 * locale de Hugo — et `resetDatabase` la vide table par table, à chaque
 * fichier. Vu le 19/11/2026, et **recommencé le 26/11/2026** : trois passages
 * de la suite ont effacé un compte et son carnet, irrécupérables.
 *
 * Un commentaire ne protège rien. Alors :
 *
 * - `TEST_DATABASE_URL` est pris tel quel, mais **refusé** s'il désigne la même
 *   base que `DATABASE_URL` ;
 * - sans lui, on **dérive** `<base>_test` de `DATABASE_URL` plutôt que de
 *   retomber dessus (`memobook` → `memobook_test`, qui existe) ;
 * - et dans tous les cas, la base visée ne peut pas être celle de
 *   développement. La suite s'arrête plutôt que d'effacer.
 *
 * ⚠️ Une base dérivée doit exister et porter le schéma :
 * `DATABASE_URL=<…>_test npx prisma migrate deploy`.
 */
export function testDatabaseUrl(
  explicit = process.env["TEST_DATABASE_URL"],
  development = process.env["DATABASE_URL"],
): string {
  if (explicit) {
    if (development && sameDatabase(explicit, development)) {
      throw new Error(
        "TEST_DATABASE_URL désigne la même base que DATABASE_URL : la suite la viderait. " +
          "Donne-lui une base à elle (par exemple la même URL suffixée `_test`).",
      );
    }
    return explicit;
  }
  if (!development) return "postgresql://memobook:memobook@localhost:5432/memobook_test";

  const derived = withDatabaseSuffix(development, "_test");
  if (sameDatabase(derived, development)) {
    // Rien à dériver. Soit `DATABASE_URL` désigne déjà une base de test — et
    // la vider est alors sans conséquence —, soit on n'a pas su lire son nom,
    // et on s'arrête : une URL qu'on ne comprend pas n'est pas une base qu'on
    // a le droit d'effacer.
    if (databaseNameOf(development).endsWith("_test")) return development;
    throw new Error(
      "Impossible de dériver une base de test depuis DATABASE_URL : pose TEST_DATABASE_URL.",
    );
  }
  return derived;
}

/** Le nom de la base dans une URL Postgres — le chemin, sans ses paramètres. */
function databaseNameOf(url: string): string {
  try {
    return new URL(url).pathname.replace(/^\//, "");
  } catch {
    return "";
  }
}

function sameDatabase(left: string, right: string): boolean {
  const name = databaseNameOf(left);
  return name !== "" && name === databaseNameOf(right);
}

/** `postgresql://…/memobook?connection_limit=5` → `…/memobook_test?connection_limit=5`. */
function withDatabaseSuffix(url: string, suffix: string): string {
  try {
    const parsed = new URL(url);
    const name = parsed.pathname.replace(/^\//, "");
    if (name === "" || name.endsWith(suffix)) return url;
    parsed.pathname = `/${name}${suffix}`;
    return parsed.toString();
  } catch {
    return url;
  }
}

export function testEnv() {
  return loadEnv({
    NODE_ENV: "test",
    LOG_LEVEL: "silent",
    DATABASE_URL: testDatabaseUrl(),
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

  // **L'accalmie de la composition, raccourcie** (T307). La file des tests est
  // en ligne : valider une étape exécute la composition *dans* la requête, et
  // quarante-cinq secondes d'accalmie feraient expirer chaque test qui valide
  // quoi que ce soit. On garde le chemin de code, pas son horloge — c'est ce
  // que `STRUCTURE_TIMING` annonce en étant une variable. Le comportement
  // lui-même se tient dans `test/accalmieDeLaComposition.test.ts`, qui pose
  // ses propres durées.
  STRUCTURE_TIMING.settleQuietMs = 10;
  STRUCTURE_TIMING.pollMs = 5;

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
  // **Un interblocage se rejoue** (01/10/2026). Le `TRUNCATE … CASCADE` prend
  // un verrou exclusif table par table ; une requête restée en vol du test
  // précédent — un envoi sans attente, une cascade de suppression — peut tenir
  // une table que le `TRUNCATE` attend, et attendre celle qu'il tient déjà.
  // Postgres en tue un (40P01) : c'est arrivé une fois en CI, sur #74. Le
  // rejouer après un instant suffit, la requête en vol a fini.
  const truncate = () =>
    prisma.$executeRawUnsafe(
      'TRUNCATE TABLE ' +
        [
          "notification_deliveries",
          "push_tokens",
          "school_holidays",
          "feedback_answers",
          "feedback_responses",
          "feedback_questions",
          "feedback_campaigns",
          "support_messages",
          "faq_votes",
          "showcases",
          "memo_gallery_categories",
          "gallery_categories",
          "trip_themes",
          "wallet_entries",
          "payment_cards",
          "subscription_transactions",
          "subscriptions",
          "cover_photos",
          "account_connectors",
          "print_order_copies",
          "print_orders",
          "renders",
          "trip_daily_usage",
          "chat_messages",
          "photo_stickers",
          "entries",
          "media_assets",
          "expenses",
          "memo_steps",
          "memo_notification_preferences",
          "memo_members",
          "memos",
          "devices",
          "sessions",
          "password_resets",
          "data_exports",
          "identities",
          "accounts",
        ]
          .map((table) => `"${table}"`)
          .join(", ") +
        " RESTART IDENTITY CASCADE",
    );

  for (let attempt = 1; ; attempt += 1) {
    try {
      await truncate();
      return;
    } catch (cause) {
      const deadlocked = JSON.stringify(cause).includes("40P01");
      if (!deadlocked || attempt >= 3) throw cause;
      await new Promise((resolve) => setTimeout(resolve, 200 * attempt));
    }
  }
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

const fixtures = resolve(dirname(fileURLToPath(import.meta.url)), "fixtures/audio");

/**
 * **Un vrai vocal**, et non quelques octets : le serveur mesure la durée dans
 * le fichier (`lib/mp4Duration.ts`) et refuse ce qu'il ne lit pas. Deux `.m4a`
 * AAC encodés par `afconvert` — ~2,1 s et ~7,1 s une fois l'amorce de
 * l'encodeur comptée.
 */
export const VOICE_FIXTURES = {
  short: readFileSync(resolve(fixtures, "vocal-2s.m4a")),
  long: readFileSync(resolve(fixtures, "vocal-7s.m4a")),
} as const;
