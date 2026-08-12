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
 * `assets/icons/manifest.json` décide de ce qui est embarqué : la librairie
 * compte plus de 140 fichiers, tous les inclure gonflerait le template pour
 * rien. Un rôle `weather-sun` devient l'identifiant `#mb-i-weather-sun`.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { TEMPLATE_DIR } from "../src/lib/templates.js";

const ICONS_DIR = resolve(import.meta.dirname, "../../assets/icons");
const TEMPLATE = resolve(TEMPLATE_DIR, "index.html");

const START = "<!-- mb:icons:start -->";
const END = "<!-- mb:icons:end -->";

interface Manifest {
  icons: Record<string, string>;
}

function manifest(): Manifest {
  const raw = readFileSync(resolve(ICONS_DIR, "manifest.json"), "utf8");
  return JSON.parse(raw) as Manifest;
}

/**
 * Extrait le contenu utile du SVG et son viewBox.
 *
 * Les exports Figma sortent en `fill="black"` : on les convertit en
 * `currentColor` plutôt que de les refuser. Exiger une retouche manuelle sur
 * chaque icône serait une friction inutile, et l'oubli se verrait seulement à
 * l'impression — une icône noire sur le disque carotte de la météo active.
 */
function toSymbol(role: string, file: string): string {
  const path = resolve(ICONS_DIR, file);
  const source = readFileSync(path, "utf8");

  const viewBox = /viewBox="([^"]+)"/.exec(source)?.[1];
  if (!viewBox) throw new Error(`${file} n'a pas de viewBox. Réexporte-le depuis Figma.`);

  let inner = source
    .replace(/^[\s\S]*?<svg[^>]*>/, "")
    .replace(/<\/svg>[\s\S]*$/, "")
    .trim()
    .replace(/(fill|stroke)="(#000000|#000|black)"/gi, '$1="currentColor"');

  const hardCoded = /(?:fill|stroke)="(#(?!fff|ffffff)[0-9a-fA-F]{3,8}|rgb\()/.exec(inner);
  if (hardCoded) {
    throw new Error(
      `${file} contient une couleur en dur (${hardCoded[1]}). ` +
        `Seuls le noir et le blanc sont convertis — voir assets/README.md.`,
    );
  }

  // Un `fill="none"` sur le <svg> racine ne survit pas à l'extraction : les
  // tracés sans fill explicite hériteraient alors du noir du contexte.
  inner = inner.replace(/<path (?![^>]*\b(fill|stroke)=)/g, '<path fill="currentColor" ');

  const indented = inner.split("\n").map((line) => `        ${line.trim()}`).join("\n");
  return `      <symbol id="mb-i-${role}" viewBox="${viewBox}">\n${indented}\n      </symbol>`;
}

function main(): void {
  const { values } = parseArgs({ options: { check: { type: "boolean", default: false } } });

  const icons = Object.entries(manifest().icons).sort(([a], [b]) => a.localeCompare(b));
  const block = [
    START,
    "      <!-- Généré par backend/scripts/build-icons.ts depuis assets/icons/manifest.json.",
    "           Ne pas éditer à la main : lance `npm run icons:build`. -->",
    ...icons.map(([role, file]) => toSymbol(role, file)),
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
    console.log(`✓ sprite à jour — ${icons.length} icônes`);
    return;
  }

  writeFileSync(TEMPLATE, next);
  console.log(`✓ ${icons.length} icônes embarquées dans index.html`);
  for (const [role, file] of icons) console.log(`  #mb-i-${role}  ←  ${file}`);
}

try {
  main();
} catch (error) {
  console.error(`✗ ${(error as Error).message}`);
  process.exit(1);
}
