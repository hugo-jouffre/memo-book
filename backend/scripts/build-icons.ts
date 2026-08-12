#!/usr/bin/env tsx
/**
 * Embarque la bibliothèque d'icônes dans le gabarit.
 *
 * Le moteur PDF ne reçoit que deux chaînes, sans fichier joint : une icône
 * référencée par un chemin ne s'afficherait jamais. Chaque SVG de
 * `assets/icons/` devient donc un `<symbol>` inscrit directement dans
 * `index.html`, entre les marqueurs `mb:icons`.
 *
 *   npm run icons:build          régénère le sprite
 *   npm run icons:build -- --check   échoue si le sprite est périmé (CI)
 *
 * Convention de nommage : `weather/sun.svg` → `#mb-i-weather-sun`.
 */
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve, sep } from "node:path";
import { parseArgs } from "node:util";
import { TEMPLATE_DIR } from "../src/lib/templates.js";

const ICONS_DIR = resolve(import.meta.dirname, "../../assets/icons");
const TEMPLATE = resolve(TEMPLATE_DIR, "index.html");

const START = "<!-- mb:icons:start -->";
const END = "<!-- mb:icons:end -->";

function listSvgs(dir: string, found: string[] = []): string[] {
  for (const name of readdirSync(dir).sort()) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) listSvgs(path, found);
    else if (name.endsWith(".svg")) found.push(path);
  }
  return found;
}

/** `weather/sun.svg` → `mb-i-weather-sun` */
function symbolId(path: string): string {
  return `mb-i-${relative(ICONS_DIR, path).replace(/\.svg$/, "").split(sep).join("-")}`;
}

/** Extrait le contenu utile du SVG et son viewBox. */
function toSymbol(path: string): string {
  const source = readFileSync(path, "utf8");

  const viewBox = /viewBox="([^"]+)"/.exec(source)?.[1];
  if (!viewBox) throw new Error(`${path} n'a pas de viewBox. Réexporte-le depuis Figma.`);

  const inner = source
    .replace(/^[\s\S]*?<svg[^>]*>/, "")
    .replace(/<\/svg>[\s\S]*$/, "")
    .trim();

  // Une couleur en dur rend l'icône aveugle au contexte : elle resterait noire
  // sur le disque carotte de la météo active. Mieux vaut refuser tout de suite.
  const hardCoded = /(?:stroke|fill)="(#[0-9a-fA-F]{3,8}|rgb\()/.exec(inner);
  if (hardCoded) {
    throw new Error(
      `${path} contient une couleur en dur (${hardCoded[1]}). ` +
        `Remplace-la par currentColor — voir assets/README.md.`,
    );
  }

  const indented = inner.split("\n").map((line) => `        ${line.trim()}`).join("\n");
  return `      <symbol id="${symbolId(path)}" viewBox="${viewBox}">\n${indented}\n      </symbol>`;
}

function main(): void {
  const { values } = parseArgs({ options: { check: { type: "boolean", default: false } } });

  const files = listSvgs(ICONS_DIR);
  const block = [
    START,
    "      <!-- Généré par backend/scripts/build-icons.ts depuis assets/icons/.",
    "           Ne pas éditer à la main : lance `npm run icons:build`. -->",
    ...files.map(toSymbol),
    `      ${END}`,
  ].join("\n");

  const html = readFileSync(TEMPLATE, "utf8");
  const from = html.indexOf(START);
  const to = html.indexOf(END);

  if (from === -1 || to === -1) {
    throw new Error(`Les marqueurs ${START} / ${END} sont absents de index.html.`);
  }

  const next = html.slice(0, from) + block + html.slice(to + END.length);

  if (values.check) {
    if (next !== html) {
      console.error(
        "✗ Le sprite d'icônes est périmé par rapport à assets/icons/. " +
          "Lance `npm run icons:build` et committe le résultat.",
      );
      process.exit(1);
    }
    console.log(`✓ sprite à jour — ${files.length} icônes`);
    return;
  }

  writeFileSync(TEMPLATE, next);
  console.log(`✓ ${files.length} icônes embarquées dans index.html`);
  for (const file of files) console.log(`  #${symbolId(file)}`);
}

try {
  main();
} catch (error) {
  console.error(`✗ ${(error as Error).message}`);
  process.exit(1);
}
