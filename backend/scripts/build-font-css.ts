#!/usr/bin/env tsx
/**
 * Fabrique le bloc `@font-face` embarqué de `templates/travel-journal/fonts.css`.
 *
 * Les polices sont inlinées en base64 plutôt que référencées par URL : APITemplate
 * ne reçoit que deux chaînes (`body` + `css`), donc aucun chemin relatif n'y
 * résout, et dépendre d'un CDN rendrait le rendu non reproductible et non
 * testable hors ligne. Le coût est quelques centaines de kilo-octets de CSS.
 *
 *   npm run fonts:build            télécharge depuis Google Fonts puis régénère
 *   npm run fonts:build -- --local régénère depuis les .woff2 déjà versionnés
 */
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { TEMPLATE_DIR } from "../src/lib/templates.js";

const FONTS_DIR = resolve(TEMPLATE_DIR, "assets/fonts");
const OUTPUT = resolve(TEMPLATE_DIR, "fonts.css");

/**
 * Seuls `latin` et `latin-ext` nous servent : le carnet est en français.
 *
 * Attention, les sous-ensembles Google sont DISJOINTS, pas emboîtés :
 * `latin-ext` ne couvre que U+0100 et au-delà, sans l'ASCII de base. Il faut
 * donc embarquer les deux, chacun avec sa `unicode-range`, exactement comme le
 * fait Google — n'en garder qu'un fait retomber tout le texte sur la police de
 * repli, sans le moindre message d'erreur.
 */
const SUBSETS = ["latin", "latin-ext"];

interface FaceSpec {
  family: string;
  /** Nom de famille utilisé dans `style.css`. */
  cssFamily: string;
  weights: number[];
}

const FACES: FaceSpec[] = [
  { family: "Playfair Display", cssFamily: "Playfair Display", weights: [400, 700, 900] },
  { family: "Gloria Hallelujah", cssFamily: "Gloria Hallelujah", weights: [400] },
];

const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

function slug(family: string, weight: number, subset: string): string {
  return `${family.toLowerCase().replace(/\s+/g, "-")}-${weight}-${subset}`;
}

/** `unicode-range` de chaque fichier, pour que Chromium sache quoi utiliser quand. */
type RangeIndex = Record<string, string>;

const RANGES_FILE = "unicode-ranges.json";

interface GoogleBlock {
  subset: string;
  weight: number;
  url: string;
  unicodeRange: string;
}

/** Découpe la réponse Google Fonts en blocs `@font-face` annotés par sous-ensemble. */
function parseGoogleCss(css: string): GoogleBlock[] {
  const blocks: GoogleBlock[] = [];
  const pattern = /\/\* (\S+) \*\/\s*@font-face \{([^}]*)\}/g;

  for (const match of css.matchAll(pattern)) {
    const subset = match[1];
    const body = match[2];
    if (!subset || !body || !SUBSETS.includes(subset)) continue;

    const weight = /font-weight:\s*(\d+)/.exec(body)?.[1];
    const url = /url\((https:[^)]+\.woff2)\)/.exec(body)?.[1];
    const unicodeRange = /unicode-range:\s*([^;]+);/.exec(body)?.[1];
    if (!weight || !url || !unicodeRange) continue;

    blocks.push({ subset, weight: Number(weight), url, unicodeRange: unicodeRange.trim() });
  }
  return blocks;
}

async function download(spec: FaceSpec, ranges: RangeIndex): Promise<void> {
  const family = spec.family.replace(/\s+/g, "+");
  const query = spec.weights.length > 1 ? `${family}:wght@${spec.weights.join(";")}` : family;
  const response = await fetch(`https://fonts.googleapis.com/css2?family=${query}&display=swap`, {
    headers: { "user-agent": USER_AGENT },
  });
  if (!response.ok) throw new Error(`Google Fonts a répondu ${response.status} pour ${spec.family}`);

  const blocks = parseGoogleCss(await response.text());

  for (const weight of spec.weights) {
    const wanted = blocks.filter((b) => b.weight === weight);
    if (wanted.length === 0) {
      throw new Error(`Aucun woff2 ${spec.family} ${weight} dans les sous-ensembles latins`);
    }

    for (const block of wanted) {
      const name = `${slug(spec.family, weight, block.subset)}.woff2`;
      const bytes = Buffer.from(await (await fetch(block.url)).arrayBuffer());
      await writeFile(resolve(FONTS_DIR, name), bytes);
      ranges[name] = block.unicodeRange;
      console.log(`  ↓ ${spec.family} ${weight} ${block.subset} — ${(bytes.length / 1024).toFixed(1)} ko`);
    }
  }
}

async function main(): Promise<void> {
  const { values } = parseArgs({ options: { local: { type: "boolean", default: false } } });
  await mkdir(FONTS_DIR, { recursive: true });

  const rangesPath = resolve(FONTS_DIR, RANGES_FILE);
  let ranges: RangeIndex = existsSync(rangesPath)
    ? (JSON.parse(await readFile(rangesPath, "utf8")) as RangeIndex)
    : {};

  if (!values.local) {
    ranges = {};
    for (const spec of FACES) await download(spec, ranges);
    await writeFile(rangesPath, `${JSON.stringify(ranges, null, 2)}\n`);
  }

  // Comme `style.css`, ce fichier est un fragment HTML : il est concaténé
  // devant lui puis injecté verbatim dans le <head>. Deux blocs <style>
  // successifs sont parfaitement valides.
  const chunks: string[] = [
    "<style>",
    "/* Généré par backend/scripts/build-font-css.ts — ne pas éditer à la main. */",
    "/* Polices inlinées : APITemplate ne résout aucun chemin relatif, et un CDN",
    "   rendrait le rendu non reproductible hors ligne. */",
    "",
  ];

  const emit = async (file: string, family: string, weight: number): Promise<void> => {
    const path = resolve(FONTS_DIR, file);
    if (!existsSync(path)) throw new Error(`${path} manque : relance sans --local.`);
    const base64 = (await readFile(path)).toString("base64");
    const range = ranges[file];
    chunks.push(
      "@font-face {",
      `  font-family: "${family}";`,
      "  font-style: normal;",
      `  font-weight: ${weight};`,
      "  font-display: block;",
      `  src: url("data:font/woff2;base64,${base64}") format("woff2");`,
      ...(range ? [`  unicode-range: ${range};`] : []),
      "}",
      "",
    );
  };

  const generated = new Set<string>();
  for (const spec of FACES) {
    for (const weight of spec.weights) {
      for (const subset of SUBSETS) {
        const file = `${slug(spec.family, weight, subset)}.woff2`;
        if (!existsSync(resolve(FONTS_DIR, file))) continue;
        await emit(file, spec.cssFamily, weight);
        generated.add(file);
      }
    }
  }

  // Polices propriétaires déposées à la main (Hansley…) : embarquées telles
  // quelles, sans unicode-range, donc sur toute la plage.
  for (const name of (await readdir(FONTS_DIR)).sort()) {
    if (!name.endsWith(".woff2") || generated.has(name)) continue;
    const weight = Number(/-(\d{3})(?:-|\.)/.exec(name)?.[1] ?? 400);
    const family = name
      .replace(/-\d{3}.*$/, "")
      .replace(/\.woff2$/, "")
      .split("-")
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
    await emit(name, family, weight);
    console.log(`  + police propriétaire : ${family} ${weight}`);
  }

  chunks.push("</style>", "");
  const output = chunks.join("\n");
  await writeFile(OUTPUT, output);
  console.log(`✓ ${OUTPUT} — ${(Buffer.byteLength(output) / 1024).toFixed(0)} ko`);
}

await main().catch((error: unknown) => {
  console.error(`✗ ${(error as Error).message}`);
  process.exit(1);
});
