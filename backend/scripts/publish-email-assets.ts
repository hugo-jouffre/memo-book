/**
 * Publie les images des e-mails sur un bucket Supabase **public**, et affiche
 * la racine à passer aux gabarits.
 *
 *     npm run emails:assets
 *
 * Pourquoi un bucket à part de `memobook-media` : celui-là est privé, et doit
 * le rester — il contient les vocaux et les photos des voyageurs, qui ne
 * sortent que par une URL signée. Une image d'e-mail a le besoin exactement
 * inverse : une URL publique, stable, et qui ne périme jamais. Une boîte de
 * réception ouvre l'image des mois après l'envoi, sans session et sans
 * signature ; et la moitié d'entre elles la re-téléchargent par un proxy.
 *
 * C'est aussi pour cela que ces fichiers ne peuvent pas vivre sur
 * `memo-book.com` tant que le site n'est pas publié : une image d'e-mail qui
 * répond 404 ne se rattrape pas, le message est déjà parti.
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PrismaClient } from "@prisma/client";
import { CreateBucketCommand, HeadBucketCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

const here = dirname(fileURLToPath(import.meta.url));
const ENV_FILE = resolve(here, "../.env");
if (existsSync(ENV_FILE)) process.loadEnvFile(ENV_FILE);

const ASSETS_DIR = resolve(here, "../../assets/emails");

/** Séparé de `S3_BUCKET`, volontairement — voir l'en-tête. */
const BUCKET = process.env.MAIL_ASSETS_BUCKET ?? "memobook-public";
const PREFIX = "emails";

const CONTENT_TYPES: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
};

/**
 * La racine publique se déduit de l'endpoint S3 : les deux portent la même
 * référence de projet, mais pas le même hôte — `…storage.supabase.co` pour le
 * protocole S3, `…supabase.co/storage/v1/object/public` pour la lecture
 * anonyme. Les confondre donne un 400 sans explication.
 */
function publicBaseUrl(endpoint: string): string {
  const host = new URL(endpoint).hostname;
  const ref = host.split(".")[0];
  if (!ref) throw new Error(`S3_ENDPOINT inattendu : ${endpoint}`);
  return `https://${ref}.supabase.co/storage/v1/object/public/${BUCKET}/${PREFIX}`;
}

async function ensureBucket(client: S3Client): Promise<void> {
  try {
    await client.send(new HeadBucketCommand({ Bucket: BUCKET }));
    console.log(`  • bucket « ${BUCKET} » déjà là`);
    return;
  } catch {
    // Absent : on le crée juste en dessous.
  }
  await client.send(new CreateBucketCommand({ Bucket: BUCKET }));
  console.log(`  ✓ bucket « ${BUCKET} » créé`);
}

/**
 * Un bucket créé par l'API S3 naît **privé** — c'est le défaut de Supabase, et
 * `setup-supabase.ts` le dit déjà pour `memobook-media`. Le drapeau ne
 * s'atteint pas en S3 : il vit dans `storage.buckets`, et c'est exactement ce
 * que bascule la case « Public bucket » du tableau de bord.
 */
async function makePublic(): Promise<void> {
  const prisma = new PrismaClient();
  try {
    const rows = await prisma.$queryRawUnsafe<Array<{ public: boolean }>>(
      "select public from storage.buckets where id = $1",
      BUCKET,
    );
    if (rows[0]?.public === true) {
      console.log(`  • bucket déjà public`);
      return;
    }
    await prisma.$executeRawUnsafe(
      "update storage.buckets set public = true where id = $1",
      BUCKET,
    );
    console.log(`  ✓ bucket passé en public`);
  } finally {
    await prisma.$disconnect();
  }
}

async function upload(client: S3Client): Promise<string[]> {
  const names = readdirSync(ASSETS_DIR).filter((name) => extname(name) in CONTENT_TYPES);
  if (names.length === 0) throw new Error(`Aucune image dans ${ASSETS_DIR}.`);

  for (const name of names) {
    await client.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: `${PREFIX}/${name}`,
        Body: readFileSync(resolve(ASSETS_DIR, name)),
        ContentType: CONTENT_TYPES[extname(name)],
        // Un an, immuable : une image d'e-mail est rechargée par des proxies
        // pendant des mois. Changer le dessin, c'est changer le nom du fichier.
        CacheControl: "public, max-age=31536000, immutable",
      }),
    );
    console.log(`  ✓ ${PREFIX}/${name}`);
  }
  return names;
}

async function main() {
  const endpoint = process.env.S3_ENDPOINT ?? "";
  if (endpoint === "") throw new Error("S3_ENDPOINT est vide : rien à publier.");

  const client = new S3Client({
    endpoint,
    region: process.env.S3_REGION ?? "us-east-1",
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== "false",
    credentials: {
      accessKeyId: process.env.S3_ACCESS_KEY_ID ?? "",
      secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? "",
    },
  });

  await ensureBucket(client);
  await makePublic();
  const names = await upload(client);

  const base = publicBaseUrl(endpoint);
  console.log(`\nRacine publique :\n  ${base}`);
  console.log(`\nÀ vérifier d'un navigateur, puis à poser dans backend/.env :`);
  console.log(`  MAIL_ASSETS_BASE_URL=${base}`);
  console.log(`\nPuis relancer « npm run emails:sync » pour que les gabarits la portent.`);
  console.log(`\nImages publiées : ${names.join(", ")}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
