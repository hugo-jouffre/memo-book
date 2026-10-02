#!/usr/bin/env tsx
/**
 * La chaîne des aperçus de personnalisation : des PNG du dépôt aux images que
 * l'app affiche en tête de l'écran « Personnalisations ».
 *
 *   npm run previews:build     prépare les images et le manifeste, ne publie rien
 *   npm run previews:publish   publie ce qui manque, puis le manifeste
 *   npm run previews:check     échoue si le manifeste versionné est périmé (CI)
 *
 * **La source** reste `assets/illustrations/aperçu personnalisation/` : 200
 * exports Figma d'environ 800 Ko, plus l'image de repli. Ils ne partent ni dans
 * l'app (146 Mo) ni dans l'image du serveur (`.dockerignore`).
 *
 * **La destination** est le bucket public `memobook-public`, sous `apercus/`,
 * à côté des images d'e-mail. Pas `memobook-media` : celui-là est privé et
 * doit le rester, il porte les vocaux et les photos des voyageurs. Un aperçu
 * est un asset produit, le même pour tout le monde, lu sans session.
 *
 * Ajouter un aperçu, c'est déposer son PNG dans le dossier — nommé comme les
 * autres, voir `docs/apercu-personnalisation.md` — puis lancer
 * `previews:publish` et commiter `apercus-personnalisation.manifest.json`.
 * Aucune ligne de code à toucher, sauf pour un assortiment typographique
 * nouveau (`FONT_COMBOS`).
 *
 * ## Ce que la chaîne fait à chaque image
 *
 * Les exports ont neuf tailles, de 942×867 à 943×880, et les pages n'y sont
 * pas posées au même endroit : jusqu'à deux pixels d'écart, et l'ombre du bas
 * rognée sur certains. Redimensionner chacun dans son propre cadre ne suffit
 * pas — les pages bougeraient d'un aperçu à l'autre, à chaque cran de curseur.
 *
 * Chaque source est donc **recalée** : le centre des pages opaques (alpha
 * ≥ 95 %, l'ombre n'y compte pas) est posé au même point d'un cadre commun de
 * 942×879, puis le tout est réduit à 900×840 et encodé en WebP. Le centre ne
 * dépend que de l'image elle-même : un aperçu ajouté plus tard se recale seul,
 * sans image de référence. Une source dont le contenu déborderait du cadre est
 * refusée plutôt que rognée en silence.
 *
 * WebP et non PNG : il faut garder la transparence (les deux pages flottent sur
 * le fond de l'écran, avec leur ombre), et un PNG de 900 px pèse ~570 Ko là où
 * le WebP en pèse ~110. iOS le décode nativement depuis la version 14.
 *
 * ## Rejouable
 *
 * Le nom d'une image publiée est l'empreinte de **sa source et de la recette**
 * (taille, qualité, cadre). Une source inchangée garde son nom, et un nom déjà
 * présent dans le bucket n'est pas renvoyé : une seconde exécution ne publie
 * rien. Changer un pixel de la source, ou un réglage ci-dessous, change le nom
 * — d'où un cache d'un an, immuable, sans invalidation à prévoir.
 *
 * Le manifeste est le seul objet qui change d'adresse fixe. Il n'est renvoyé
 * que si son contenu diffère, et part **après** les images : il ne désigne
 * jamais un fichier pas encore en ligne. Rien n'est jamais supprimé du bucket :
 * une app qui a gardé l'ancien manifeste en cache doit encore trouver ses
 * images.
 */

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import {
  GetObjectCommand,
  HeadBucketCommand,
  ListObjectsV2Command,
  NoSuchKey,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import sharp from "sharp";

const here = dirname(fileURLToPath(import.meta.url));

export const SOURCE_DIR = resolve(here, "../../assets/illustrations/aperçu personnalisation");
/**
 * Le manifeste versionné. À côté du dossier et non dedans : le dossier ne
 * contient que des aperçus, et le sélecteur de l'app vérifie que chacun de ses
 * fichiers en est un (`make-customisation-preview-manifest.py`).
 */
export const MANIFEST_FILE = resolve(
  here,
  "../../assets/illustrations/apercus-personnalisation.manifest.json",
);
/** Les images préparées, pour les regarder avant de publier. Hors du dépôt. */
const OUT_DIR = resolve(here, "../.previews-out");

const BUCKET = process.env.PUBLIC_ASSETS_BUCKET ?? "memobook-public";
const PREFIX = "apercus";

/** Le repli : ASCII, sans cédille — voir `docs/apercu-personnalisation.md`. */
export const FALLBACK_SOURCE = "apercu non existant.png";

// La recette. Toucher à l'une de ces valeurs change le nom de toutes les
// images, et les republie toutes — c'est voulu.

/**
 * ~300 pt de large dans la tête de l'écran, soit 900 px sur un iPhone @3x. En
 * 600, l'aperçu était mou ; chaque image pèse ~110 Ko au lieu de ~60.
 */
const OUTPUT = { width: 900, height: 840 } as const;
/** Le cadre commun, en pixels source : la largeur des exports, au rapport de la sortie. */
const FRAME = { width: 942, height: 879 } as const;
/** Où tombe le centre des pages dans ce cadre. Mesuré sur les 201 exports du 02/10/2026. */
const ANCHOR = { x: 460, y: 411 } as const;
/** Un pixel compte pour le centre à partir de cette opacité : les pages, pas l'ombre. */
const OPAQUE = 242;
/** En deçà, un pixel peut tomber hors du cadre : la dernière frange de l'ombre. */
const VISIBLE = 8;
const WEBP = { quality: 82, alphaQuality: 90, effort: 6 } as const;
const RECIPE = [
  "v1",
  `${OUTPUT.width}x${OUTPUT.height}`,
  `cadre ${FRAME.width}x${FRAME.height}@${ANCHOR.x},${ANCHOR.y}`,
  `opaque ${OPAQUE}`,
  `webp q${WEBP.quality} a${WEBP.alphaQuality} e${WEBP.effort}`,
].join(" · ");

const IMMUTABLE = "public, max-age=31536000, immutable";
/** Un aperçu ajouté arrive sur les téléphones au plus tard cinq minutes après. */
const MANIFEST_CACHE = "public, max-age=300";

// ---------------------------------------------------------------- les noms

/**
 * Le segment `Typos=` des noms de fichier, vers l'identifiant de
 * `BookFontCombo`. Reproduit tels quels les noms Figma, faute comprise :
 * « Hellelujah » est figée dans cinquante fichiers.
 */
export const FONT_COMBOS: Readonly<Record<string, string>> = {
  "Playfair Display - Hansley - Gloria Hallelujah": "travel-journal",
  "Hansley - Gloria Hellelujah": "handwritten",
  "Playfair Display": "editorial",
};

/** Une combinaison de réglages, dans les noms de `BookCustomisation`. */
export interface PreviewState {
  rulesEnabled: boolean;
  photoTextRatio: number;
  funFactsEnabled: boolean;
  decorationQuota: number;
  /** L'identifiant de `BookFontCombo`. */
  fontCombo: string;
}

function onOff(value: string, file: string): boolean {
  if (value === "on") return true;
  if (value === "off") return false;
  throw new Error(`${file} : « ${value} » n'est ni on ni off.`);
}

function integer(value: string, file: string, suffix = ""): number {
  const match = new RegExp(`^(\\d+)${suffix}$`).exec(value);
  if (!match?.[1]) {
    throw new Error(`${file} : « ${value} » n'est pas un nombre${suffix ? ` suivi de ${suffix}` : ""}.`);
  }
  return Number(match[1]);
}

/**
 * Lit les cinq réglages dans un nom de fichier.
 *
 * `Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=2, Typos=…png`. Le nom
 * est ramené en NFC d'abord : un fichier glissé depuis le Finder peut arriver
 * en NFD, et « Pointillés » ne s'y reconnaîtrait plus.
 */
export function parsePreviewName(file: string): PreviewState {
  const name = file.normalize("NFC").replace(/\.png$/i, "");
  const segments = new Map<string, string>();
  for (const segment of name.split(", ")) {
    const at = segment.indexOf("=");
    if (at < 0) throw new Error(`${file} : segment « ${segment} » sans « = ».`);
    segments.set(segment.slice(0, at), segment.slice(at + 1));
  }

  const take = (key: string): string => {
    const value = segments.get(key);
    if (value === undefined) throw new Error(`${file} : il manque « ${key}= ».`);
    segments.delete(key);
    return value;
  };

  const typos = take("Typos");
  const fontCombo = FONT_COMBOS[typos];
  if (!fontCombo) {
    throw new Error(
      `${file} : assortiment « ${typos} » inconnu. S'il est nouveau, l'ajouter à FONT_COMBOS ` +
        `(backend/scripts/customisation-previews.ts) avec l'identifiant de son BookFontCombo.`,
    );
  }

  const state: PreviewState = {
    rulesEnabled: onOff(take("Pointillés"), file),
    photoTextRatio: integer(take("Ratio image"), file, "%"),
    funFactsEnabled: onOff(take("Fun fact"), file),
    decorationQuota: integer(take("Stickers"), file),
    fontCombo,
  };
  if (segments.size > 0) {
    throw new Error(`${file} : segment inattendu « ${[...segments.keys()].join(", ")} ».`);
  }
  return state;
}

// --------------------------------------------------------------- le manifeste

export interface PreviewEntry extends PreviewState {
  /** Relatif à l'adresse du manifeste. */
  file: string;
  /** Le PNG d'origine, pour retrouver d'où vient une image. */
  source: string;
}

export interface PreviewManifest {
  $comment: string;
  version: 1;
  width: number;
  height: number;
  fallback: { file: string; source: string };
  previews: PreviewEntry[];
}

/** Le nom publié : l'empreinte de la source et de la recette. */
export function publishedName(source: Buffer): string {
  const hash = createHash("sha256").update(RECIPE).update("\n").update(source).digest("hex");
  return `${hash.slice(0, 20)}.webp`;
}

const ORDER: Array<keyof PreviewState> = [
  "fontCombo",
  "rulesEnabled",
  "photoTextRatio",
  "funFactsEnabled",
  "decorationQuota",
];

function compareStates(a: PreviewState, b: PreviewState): number {
  for (const key of ORDER) {
    const left = a[key];
    const right = b[key];
    if (left < right) return -1;
    if (left > right) return 1;
  }
  return 0;
}

const stateKey = (state: PreviewState): string => ORDER.map((key) => String(state[key])).join("|");

export interface SourceFile {
  name: string;
  bytes: Buffer;
}

/**
 * Le manifeste que consomme le sélecteur. Sans date ni chemin local : deux
 * exécutions sur les mêmes sources doivent produire les mêmes octets, sinon
 * il serait republié à chaque fois.
 */
export function buildManifest(sources: readonly SourceFile[]): PreviewManifest {
  let fallback: PreviewManifest["fallback"] | undefined;
  const previews: PreviewEntry[] = [];
  const seen = new Map<string, string>();

  for (const { name, bytes } of sources) {
    const file = publishedName(bytes);
    if (name.normalize("NFC") === FALLBACK_SOURCE) {
      fallback = { file, source: FALLBACK_SOURCE };
      continue;
    }
    const state = parsePreviewName(name);
    const key = stateKey(state);
    const twin = seen.get(key);
    if (twin) {
      throw new Error(`Deux aperçus pour la même combinaison : « ${twin} » et « ${name} ».`);
    }
    seen.set(key, name);
    previews.push({ ...state, file, source: name.normalize("NFC") });
  }

  if (!fallback) throw new Error(`Le repli « ${FALLBACK_SOURCE} » manque dans ${SOURCE_DIR}.`);
  previews.sort(compareStates);

  return {
    $comment:
      "Engendré par `npm run previews:build` (backend/scripts/customisation-previews.ts), " +
      "ne pas éditer à la main. Chaque `file` se résout contre l'adresse de ce manifeste ; " +
      "une combinaison absente prend `fallback`.",
    version: 1,
    width: OUTPUT.width,
    height: OUTPUT.height,
    fallback,
    previews,
  };
}

export const serializeManifest = (manifest: PreviewManifest): string =>
  `${JSON.stringify(manifest, null, 2)}\n`;

export function readSources(): SourceFile[] {
  return readdirSync(SOURCE_DIR)
    .filter((name) => /\.png$/i.test(name))
    .sort()
    .map((name) => ({ name, bytes: readFileSync(resolve(SOURCE_DIR, name)) }));
}

// ------------------------------------------------------------------ l'image

/**
 * Recale, réduit et encode une source. Voir l'en-tête pour le pourquoi.
 */
export async function renderPreview(source: Buffer, name: string): Promise<Buffer> {
  const { data, info } = await sharp(source)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;

  let sumX = 0;
  let sumY = 0;
  let count = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if ((data[(y * width + x) * channels + 3] ?? 0) >= OPAQUE) {
        sumX += x;
        sumY += y;
        count++;
      }
    }
  }
  if (count === 0) throw new Error(`${name} : aucune zone opaque, rien à recaler.`);

  const left = Math.round(sumX / count) - ANCHOR.x;
  const top = Math.round(sumY / count) - ANCHOR.y;

  let overflow = 0;
  for (let y = 0; y < height; y++) {
    const insideY = y >= top && y < top + FRAME.height;
    for (let x = 0; x < width; x++) {
      if (insideY && x >= left && x < left + FRAME.width) continue;
      if ((data[(y * width + x) * channels + 3] ?? 0) > VISIBLE) overflow++;
    }
  }
  if (overflow > 0) {
    throw new Error(
      `${name} : ${overflow} pixels visibles hors du cadre commun. L'export n'a pas la ` +
        `composition des autres : le refaire, ou élargir FRAME et ANCHOR (ce qui republiera tout).`,
    );
  }

  // Le cadre peut dépasser la source d'un ou deux pixels : on l'étend d'abord
  // en transparent, puis on découpe. Deux passes, parce que sharp n'applique
  // pas `extend` et `extract` dans l'ordre où on les chaîne.
  const pad = {
    left: Math.max(0, -left),
    top: Math.max(0, -top),
    right: Math.max(0, left + FRAME.width - width),
    bottom: Math.max(0, top + FRAME.height - height),
  };
  const padded = await sharp(data, { raw: { width, height, channels } })
    .extend({ ...pad, background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .raw()
    .toBuffer();

  return sharp(padded, {
    raw: { width: width + pad.left + pad.right, height: height + pad.top + pad.bottom, channels },
  })
    .extract({ left: left + pad.left, top: top + pad.top, ...FRAME })
    .resize(OUTPUT.width, OUTPUT.height, { fit: "fill", kernel: "lanczos3" })
    .webp(WEBP)
    .toBuffer();
}

/** Prépare dans `.previews-out/` ce qui n'y est pas encore. */
async function renderAll(
  sources: readonly SourceFile[],
  manifest: PreviewManifest,
): Promise<number> {
  mkdirSync(OUT_DIR, { recursive: true });
  const byName = new Map(sources.map((source) => [source.name.normalize("NFC"), source]));
  const wanted = [manifest.fallback, ...manifest.previews];

  let rendered = 0;
  for (const { file, source } of wanted) {
    const target = resolve(OUT_DIR, file);
    if (existsSync(target)) continue;
    const input = byName.get(source.normalize("NFC"));
    if (!input) throw new Error(`Source introuvable : ${source}`);
    writeFileSync(target, await renderPreview(input.bytes, source));
    rendered++;
  }
  writeFileSync(resolve(OUT_DIR, "manifest.json"), serializeManifest(manifest));
  return rendered;
}

// --------------------------------------------------------------- publication

function s3Client(): { client: S3Client; endpoint: string } {
  const endpoint = process.env.S3_ENDPOINT ?? "";
  const accessKeyId = process.env.S3_ACCESS_KEY_ID ?? "";
  const secretAccessKey = process.env.S3_SECRET_ACCESS_KEY ?? "";
  if (!endpoint || !accessKeyId || !secretAccessKey) {
    throw new Error(
      "S3_ENDPOINT, S3_ACCESS_KEY_ID et S3_SECRET_ACCESS_KEY sont nécessaires pour publier (backend/.env).",
    );
  }
  const client = new S3Client({
    endpoint,
    region: process.env.S3_REGION ?? "us-east-1",
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE !== "false",
    credentials: { accessKeyId, secretAccessKey },
    // Pas de somme de contrôle CRC32 non standard : voir `services/storage.ts`.
    requestChecksumCalculation: "WHEN_REQUIRED",
    responseChecksumValidation: "WHEN_REQUIRED",
  });
  return { client, endpoint };
}

/**
 * La lecture anonyme, déduite de l'endpoint S3 comme dans
 * `publish-email-assets.ts` : même référence de projet, autre hôte.
 */
function publicBaseUrl(endpoint: string): string {
  const ref = new URL(endpoint).hostname.split(".")[0];
  if (!ref) throw new Error(`S3_ENDPOINT inattendu : ${endpoint}`);
  return `https://${ref}.supabase.co/storage/v1/object/public/${BUCKET}/${PREFIX}`;
}

async function listPublished(client: S3Client): Promise<Set<string>> {
  const keys = new Set<string>();
  let token: string | undefined;
  do {
    const page = await client.send(
      new ListObjectsV2Command({ Bucket: BUCKET, Prefix: `${PREFIX}/`, ContinuationToken: token }),
    );
    for (const object of page.Contents ?? []) if (object.Key) keys.add(object.Key);
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (token);
  return keys;
}

async function publishedManifest(client: S3Client): Promise<string | undefined> {
  try {
    const object = await client.send(
      new GetObjectCommand({ Bucket: BUCKET, Key: `${PREFIX}/manifest.json` }),
    );
    return await object.Body?.transformToString("utf8");
  } catch (error) {
    if (error instanceof NoSuchKey) return undefined;
    throw error;
  }
}

/** Quelques envois à la fois : 200 images une par une, c'est une minute d'attente. */
async function inBatches<T>(
  items: readonly T[],
  size: number,
  run: (item: T) => Promise<void>,
): Promise<void> {
  for (let start = 0; start < items.length; start += size) {
    await Promise.all(items.slice(start, start + size).map(run));
  }
}

async function publish(manifest: PreviewManifest): Promise<void> {
  const { client, endpoint } = s3Client();
  await client.send(new HeadBucketCommand({ Bucket: BUCKET })).catch(() => {
    throw new Error(
      `Bucket « ${BUCKET} » introuvable. Il naît avec \`npm run emails:assets\`, qui le rend public.`,
    );
  });

  const online = await listPublished(client);
  const files = [manifest.fallback, ...manifest.previews].map((entry) => entry.file);
  const missing = [...new Set(files)].filter((file) => !online.has(`${PREFIX}/${file}`));

  await inBatches(missing, 8, async (file) => {
    await client.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: `${PREFIX}/${file}`,
        Body: readFileSync(resolve(OUT_DIR, file)),
        ContentType: "image/webp",
        CacheControl: IMMUTABLE,
      }),
    );
  });
  const already = files.length - missing.length;
  console.log(`Images : ${missing.length} envoyée(s), ${already} déjà en ligne.`);

  const body = serializeManifest(manifest);
  if ((await publishedManifest(client)) === body) {
    console.log("Manifeste : inchangé.");
  } else {
    await client.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: `${PREFIX}/manifest.json`,
        Body: body,
        ContentType: "application/json; charset=utf-8",
        CacheControl: MANIFEST_CACHE,
      }),
    );
    console.log("Manifeste : publié.");
  }

  const orphans = [...online].filter(
    (key) => key !== `${PREFIX}/manifest.json` && !files.includes(key.slice(PREFIX.length + 1)),
  );
  if (orphans.length > 0) {
    console.log(`(${orphans.length} image(s) en ligne qu'aucun aperçu ne désigne plus, laissées en place.)`);
  }

  // La vérification qui compte : ce que lit un téléphone, sans session.
  const base = publicBaseUrl(endpoint);
  for (const url of [`${base}/manifest.json`, `${base}/${manifest.fallback.file}`]) {
    const response = await fetch(url);
    const cache = response.headers.get("cache-control") ?? "—";
    if (!response.ok) {
      throw new Error(`${url} répond ${response.status} : le bucket est-il bien public ?`);
    }
    console.log(`  ✓ ${response.status} ${cache}  ${url}`);
  }
  console.log(`\nL'adresse du manifeste, celle que l'app lit :\n  ${base}/manifest.json`);
}

// --------------------------------------------------------------------- main

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: { check: { type: "boolean" }, publish: { type: "boolean" } },
  });

  const sources = readSources();
  const manifest = buildManifest(sources);
  const serialized = serializeManifest(manifest);

  if (values.check) {
    const committed = existsSync(MANIFEST_FILE) ? readFileSync(MANIFEST_FILE, "utf8") : "";
    if (committed !== serialized) {
      console.error(
        "Le manifeste des aperçus ne correspond plus aux PNG du dossier.\n" +
          "Lancer `npm run previews:publish` dans backend/, puis commiter manifest.json.",
      );
      process.exit(1);
    }
    console.log(`Manifeste à jour : ${manifest.previews.length} aperçus et un repli.`);
    return;
  }

  const rendered = await renderAll(sources, manifest);
  writeFileSync(MANIFEST_FILE, serialized);
  console.log(
    `${manifest.previews.length} aperçus et un repli, ${OUTPUT.width}×${OUTPUT.height} — ` +
      `${rendered} préparé(s), les autres déjà dans ${basename(OUT_DIR)}/.`,
  );

  if (values.publish) await publish(manifest);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
