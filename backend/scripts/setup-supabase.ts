/**
 * Prépare — et vérifie — un projet Supabase pour MemoBook.
 *
 *   npm run supabase:setup     applique ce qui manque, puis vérifie
 *   npm run supabase:check     vérifie seulement, ne touche à rien
 *
 * Le script est **idempotent** : le relancer sur un projet déjà prêt ne change
 * rien et se contente de le confirmer. Il ne supprime jamais rien.
 *
 * Ce qu'il fait, dans l'ordre :
 *
 *   1. Vérifie que `DATABASE_URL` répond, et qu'elle est utilisable — c'est le
 *      point où l'on se trompe, et l'erreur n'apparaît sinon qu'au premier job.
 *   2. Applique les migrations Prisma en attente.
 *   3. Confirme que le schéma et la base disent la même chose.
 *   4. Crée le bucket de médias et fait un aller-retour complet dessus.
 *   5. Mesure ce qui est consommé, face aux limites du plan gratuit.
 *
 * Rien ici n'est propre à Supabase, sauf la détection du pooler et les seuils
 * du plan gratuit. Pointer `DATABASE_URL` et les `S3_*` ailleurs suffit à
 * vérifier un autre hébergeur — c'est justement ce qu'on veut pouvoir faire.
 */

import { execFileSync } from "node:child_process";
import { PrismaClient } from "@prisma/client";
import {
  CreateBucketCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { loadEnv, type Env } from "../src/env.js";

const CHECK_ONLY = process.argv.includes("--check");

/**
 * Les limites du plan gratuit Supabase, au moment d'écrire ces lignes. Elles
 * ne servent qu'à prévenir avant que ça coince — le script n'échoue jamais
 * dessus, il alerte.
 *
 * Le seuil d'alerte est à 80 % : au-delà, il reste le temps de décider, et
 * c'est exactement le moment où le déménagement vers Postgres et Backblaze
 * doit être préparé plutôt que subi.
 */
const FREE_TIER = {
  databaseBytes: 500 * 1024 * 1024,
  storageBytes: 1024 * 1024 * 1024,
  /** Taille maximale d'un fichier, réglage par défaut du bucket. */
  fileBytes: 50 * 1024 * 1024,
  warnAtRatio: 0.8,
} as const;

/** Ce que le back-end envoie de plus gros — voir `routes/entries.ts`. */
const MAX_MEDIA_BYTES = 25 * 1024 * 1024;

// ---------------------------------------------------------------------------
// Affichage
// ---------------------------------------------------------------------------

const problems: string[] = [];
const warnings: string[] = [];

function section(title: string): void {
  console.log(`\n\x1b[1m${title}\x1b[0m`);
}

function ok(message: string): void {
  console.log(`  \x1b[32m✓\x1b[0m ${message}`);
}

function did(message: string): void {
  console.log(`  \x1b[36m→\x1b[0m ${message}`);
}

function warn(message: string, detail?: string): void {
  warnings.push(message);
  console.log(`  \x1b[33m!\x1b[0m ${message}`);
  if (detail) console.log(`    ${detail}`);
}

function fail(message: string, detail?: string): void {
  problems.push(message);
  console.log(`  \x1b[31m✗\x1b[0m ${message}`);
  if (detail) console.log(`    ${detail}`);
}

function humanBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} o`;
  const units = ["Ko", "Mo", "Go"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value < 10 ? 1 : 0)} ${units[unit]}`;
}

function quota(used: number, limit: number, label: string): void {
  const ratio = used / limit;
  const line = `${label} : ${humanBytes(used)} sur ${humanBytes(limit)} (${(ratio * 100).toFixed(1)} %)`;
  if (ratio >= FREE_TIER.warnAtRatio) {
    warn(line, "Le moment de préparer le déménagement — voir docs/supabase.md § 6.");
  } else {
    ok(line);
  }
}

// ---------------------------------------------------------------------------
// 1. La connexion
// ---------------------------------------------------------------------------

/**
 * Le piège de Supabase, et il coûte une soirée : il expose **deux** chaînes de
 * connexion, et une seule convient.
 *
 * Le pooler en mode transaction (port 6543) rend chaque requête à une session
 * différente. Trois choses cassent alors, et aucune ne se voit tout de suite :
 * les migrations Prisma, qui posent un verrou consultatif le temps de
 * s'appliquer ; pg-boss, qui s'appuie sur des verrous de session pour ne pas
 * traiter un job deux fois ; et les requêtes préparées.
 *
 * Mieux vaut refuser de démarrer ici que découvrir le problème quand un vocal
 * sera transcrit deux fois.
 */
function inspectConnection(env: Env): { host: string; isTransactionPooler: boolean } {
  const url = new URL(env.DATABASE_URL);
  const port = url.port || "5432";
  const pgbouncer = url.searchParams.get("pgbouncer") === "true";
  const isTransactionPooler = port === "6543" || pgbouncer;

  did(`hôte : ${url.hostname}:${port}`);

  if (isTransactionPooler) {
    fail(
      "DATABASE_URL pointe sur le pooler en mode transaction.",
      [
        "Les migrations Prisma et pg-boss ont besoin d'une session stable.",
        "Dans Supabase ▸ Connect, prends « Session pooler » (port 5432),",
        "pas « Transaction pooler » (port 6543).",
      ].join("\n    "),
    );
  }

  if (url.searchParams.get("sslmode") === "disable") {
    fail(
      "sslmode=disable sur une base distante.",
      "Retire le paramètre : Supabase impose TLS, et le désactiver fait passer le mot de passe en clair.",
    );
  }

  if (!url.password) {
    warn(
      "Aucun mot de passe dans DATABASE_URL.",
      "Supabase ne le montre qu'à la création du projet. Il se réinitialise dans Settings ▸ Database.",
    );
  }

  return { host: url.hostname, isTransactionPooler };
}

/**
 * Confirme par l'usage ce que le port laisse deviner : un verrou consultatif
 * posé par une requête doit encore exister à la suivante.
 */
async function probeSession(prisma: PrismaClient): Promise<void> {
  const key = 727073; // « pgs » en chiffres, arbitraire et sans conflit.

  try {
    // `pg_try_advisory_lock` et non `pg_advisory_lock` : la variante bloquante
    // rend `void`, que Prisma ne sait pas désérialiser, et elle attendrait
    // indéfiniment si le verrou était déjà pris.
    await prisma.$queryRawUnsafe<{ locked: boolean }[]>(
      `SELECT pg_try_advisory_lock(${key}) AS locked`,
    );
    const held = await prisma.$queryRawUnsafe<{ n: bigint }[]>(
      `SELECT count(*) AS n FROM pg_locks WHERE locktype = 'advisory' AND objid = ${key}`,
    );
    await prisma.$queryRawUnsafe<{ unlocked: boolean }[]>(
      `SELECT pg_advisory_unlock(${key}) AS unlocked`,
    );

    if (Number(held[0]?.n ?? 0) > 0) {
      ok("Session stable : les verrous survivent d'une requête à l'autre.");
    } else {
      fail(
        "Les verrous ne survivent pas d'une requête à l'autre.",
        "La connexion ne garde pas de session. Prends le « Session pooler » de Supabase.",
      );
    }
  } catch (cause) {
    warn(`Sonde de session impossible : ${(cause as Error).message}`);
  }
}

async function checkDatabase(env: Env, prisma: PrismaClient): Promise<void> {
  section("1. La base");

  const { isTransactionPooler } = inspectConnection(env);

  // Une base injoignable est un diagnostic, pas un plantage : le script existe
  // pour rendre un verdict lisible, y compris quand rien ne répond.
  try {
    const version = await prisma.$queryRaw<{ v: string }[]>`SELECT version() AS v`;
    const short = version[0]?.v.split(" ").slice(0, 2).join(" ") ?? "inconnue";
    ok(`connectée — ${short}`);
  } catch (cause) {
    const message = (cause as Error).message;
    fail(
      "Impossible de joindre la base.",
      [
        message.includes("Can't reach database server")
          ? "Vérifie l'hôte, le port et le mot de passe de DATABASE_URL."
          : message.split("\n")[0],
        "Un projet du plan gratuit en pause met quelques minutes à se réveiller.",
      ].join("\n    "),
    );
    return;
  }

  if (!isTransactionPooler) await probeSession(prisma);
}

// ---------------------------------------------------------------------------
// 2 et 3. Les migrations
// ---------------------------------------------------------------------------

function prisma(...args: string[]): string {
  return execFileSync("npx", ["prisma", ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: process.env,
  });
}

function applyMigrations(): void {
  section(CHECK_ONLY ? "2. Les migrations (vérification seule)" : "2. Les migrations");

  if (CHECK_ONLY) {
    try {
      prisma("migrate", "status");
      ok("Toutes les migrations sont appliquées.");
    } catch (cause) {
      const output = String((cause as { stdout?: string }).stdout ?? "");
      if (output.includes("have not yet been applied")) {
        fail(
          "Des migrations sont en attente.",
          "Lance `npm run supabase:setup` (ou `npx prisma migrate deploy`).",
        );
      } else {
        fail("Impossible de lire l'état des migrations.", output.trim().split("\n").at(-1));
      }
    }
    return;
  }

  const output = prisma("migrate", "deploy");
  const applied = output.match(/Applying migration `([^`]+)`/g) ?? [];

  if (applied.length === 0) {
    ok("Aucune migration en attente.");
  } else {
    for (const line of applied) {
      did(`appliquée : ${line.replace(/Applying migration `|`/g, "")}`);
    }
  }
}

/**
 * Le schéma et la base doivent dire exactement la même chose. Une dérive
 * signifie qu'on a modifié la base à la main quelque part — dans l'éditeur SQL
 * de Supabase, typiquement — et la prochaine migration partira d'un état qu'elle
 * ne connaît pas.
 */
function checkDrift(): void {
  section("3. Le schéma");

  try {
    prisma(
      "migrate",
      "diff",
      "--from-schema-datasource",
      "prisma/schema.prisma",
      "--to-schema-datamodel",
      "prisma/schema.prisma",
      "--exit-code",
    );
    ok("Le schéma et la base sont d'accord.");
  } catch {
    fail(
      "Dérive entre `schema.prisma` et la base.",
      "Quelque chose a été modifié hors migration. `npx prisma migrate diff ... --script` montre quoi.",
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Le stockage
// ---------------------------------------------------------------------------

function storageClient(env: Env): S3Client | null {
  if (!env.S3_ENDPOINT || !env.S3_ACCESS_KEY_ID || !env.S3_SECRET_ACCESS_KEY) return null;

  return new S3Client({
    endpoint: env.S3_ENDPOINT,
    region: env.S3_REGION,
    forcePathStyle: env.S3_FORCE_PATH_STYLE,
    credentials: {
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    },
  });
}

async function ensureBucket(client: S3Client, bucket: string): Promise<boolean> {
  try {
    await client.send(new HeadBucketCommand({ Bucket: bucket }));
    ok(`bucket « ${bucket} » présent`);
    return true;
  } catch {
    // Absent, ou invisible faute de droit sur l'opération. On tente de le créer.
  }

  if (CHECK_ONLY) {
    fail(`Bucket « ${bucket} » introuvable.`);
    return false;
  }

  try {
    await client.send(new CreateBucketCommand({ Bucket: bucket }));
    did(`bucket « ${bucket} » créé — il reste privé, c'est le défaut`);
    return true;
  } catch (cause) {
    fail(
      `Impossible de créer le bucket « ${bucket} ».`,
      [
        (cause as Error).message,
        "Crée-le à la main : Supabase ▸ Storage ▸ New bucket, nom exact ci-dessus,",
        "et **laisse-le privé**. Puis relance ce script.",
      ].join("\n    "),
    );
    return false;
  }
}

/**
 * Un aller-retour complet, avec le même client que le back-end. Vérifier que
 * les clés existent ne dit rien ; les quatre opérations que le produit utilise
 * réellement, si.
 */
async function roundTrip(client: S3Client, bucket: string): Promise<void> {
  const key = `_verification/${Date.now()}.txt`;
  const body = Buffer.from("memobook setup", "utf8");

  await client.send(
    new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: "text/plain" }),
  );

  const read = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const bytes = Buffer.from(await read.Body!.transformToByteArray());

  if (!bytes.equals(body)) {
    fail("L'objet relu ne correspond pas à celui qui a été écrit.");
    return;
  }

  const url = await getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), {
    expiresIn: 60,
  });

  if (!url.includes("X-Amz-Signature")) {
    fail(
      "Les URL signées ne sont pas signées.",
      "L'app télécharge les vocaux par ce chemin : sans signature, le bucket privé est inutilisable.",
    );
    return;
  }

  await client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
  ok("écriture, lecture, URL signée et suppression : les quatre passent");
}

async function checkStorage(env: Env): Promise<S3Client | null> {
  section("4. Le stockage des médias");

  const client = storageClient(env);

  if (!client) {
    fail(
      "Stockage non configuré (S3_ENDPOINT, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY).",
      [
        "Sans ces variables, les médias vivent en mémoire et ne survivent pas à un redémarrage.",
        "En production, le serveur refuse alors de démarrer — c'est voulu.",
        "Supabase ▸ Storage ▸ S3 Connection ▸ New access key.",
      ].join("\n    "),
    );
    return null;
  }

  const bucket = env.S3_BUCKET;
  if (!bucket) {
    fail("S3_BUCKET est vide.");
    return null;
  }

  if (!env.S3_FORCE_PATH_STYLE) {
    warn(
      "S3_FORCE_PATH_STYLE=false.",
      "Supabase attend le style chemin. Mets `true` tant que tu es dessus.",
    );
  }

  did(`point d'accès : ${env.S3_ENDPOINT}`);

  if (!(await ensureBucket(client, bucket))) return null;

  await roundTrip(client, bucket);
  return client;
}

// ---------------------------------------------------------------------------
// 5. Les limites
// ---------------------------------------------------------------------------

async function measure(prismaClient: PrismaClient, client: S3Client | null, env: Env) {
  section("5. Ce qui est consommé");

  const rows = await prismaClient.$queryRaw<{ size: bigint }[]>`
    SELECT pg_database_size(current_database()) AS size
  `;
  quota(Number(rows[0]?.size ?? 0), FREE_TIER.databaseBytes, "Base");

  if (client && env.S3_BUCKET) {
    let total = 0;
    let count = 0;
    let token: string | undefined;

    do {
      const page = await client.send(
        new ListObjectsV2Command({ Bucket: env.S3_BUCKET, ContinuationToken: token }),
      );
      for (const object of page.Contents ?? []) {
        total += object.Size ?? 0;
        count += 1;
      }
      token = page.NextContinuationToken;
    } while (token);

    quota(total, FREE_TIER.storageBytes, `Stockage (${count} objet${count > 1 ? "s" : ""})`);
  }

  if (MAX_MEDIA_BYTES > FREE_TIER.fileBytes) {
    warn(
      `Le back-end accepte ${humanBytes(MAX_MEDIA_BYTES)} par fichier, au-dessus de la limite du bucket.`,
    );
  } else {
    ok(
      `Taille maximale d'un envoi : ${humanBytes(MAX_MEDIA_BYTES)}, sous la limite de ${humanBytes(FREE_TIER.fileBytes)}.`,
    );
  }

  // Le plan gratuit met le projet en pause après une semaine sans requête. Ce
  // n'est pas une perte de données, mais c'est une surprise de plusieurs minutes
  // le jour où l'on relance l'app en démo.
  console.log(
    "\n  \x1b[2mLe plan gratuit met le projet en pause après 7 jours sans requête.\x1b[0m",
  );
  console.log(
    "  \x1b[2mLe réveil prend quelques minutes : à savoir avant une démonstration.\x1b[0m",
  );
}

// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const env = loadEnv();

  console.log(
    `\x1b[1mMemoBook — ${CHECK_ONLY ? "vérification" : "configuration"} de l'hébergement\x1b[0m`,
  );

  const prismaClient = new PrismaClient({ datasourceUrl: env.DATABASE_URL });

  try {
    await checkDatabase(env, prismaClient);

    // Inutile d'aller plus loin si la connexion ne peut pas porter une
    // migration : tout ce qui suit échouerait pour la même raison, et trois
    // erreurs de plus n'aideraient personne à trouver la première.
    const databaseUsable = problems.length === 0;

    if (databaseUsable) {
      applyMigrations();
      checkDrift();
    } else {
      section("2 et 3. Les migrations");
      console.log("  \x1b[2mignorées : la connexion doit d'abord être corrigée\x1b[0m");
    }

    // Le stockage est indépendant de la base : il se vérifie même quand elle
    // ne répond pas, et c'est autant de corrigé en un seul passage.
    const client = await checkStorage(env);

    if (databaseUsable) await measure(prismaClient, client, env);
  } finally {
    await prismaClient.$disconnect();
  }

  section("Bilan");

  if (problems.length > 0) {
    console.log(`  \x1b[31m${problems.length} point(s) à corriger.\x1b[0m`);
    for (const problem of problems) console.log(`    · ${problem}`);
    console.log("\n  Le détail de chaque réglage est dans docs/supabase.md.");
    process.exitCode = 1;
    return;
  }

  if (warnings.length > 0) {
    console.log(`  \x1b[33m${warnings.length} avertissement(s), rien de bloquant.\x1b[0m`);
  }

  console.log("  \x1b[32mL'hébergement est prêt.\x1b[0m");
  console.log("\n  Ensuite :");
  console.log("    npm run db:seed     un voyageur, deux voyages et de quoi remplir l'app");
  console.log("    npm run dev         l'API sur http://localhost:3000");
  console.log("    curl localhost:3000/health");
}

main().catch((error: unknown) => {
  console.error(`\n\x1b[31m${(error as Error).message}\x1b[0m`);
  process.exit(1);
});
