/**
 * Enregistre la réponse Overpass qui sert aux tests des cartes de ville
 * (`test/fixtures/osm/overpass-paris.json.gz`) : les tests n'appellent jamais
 * le réseau, ils relisent cette réponse. Elle garde la forme d'une réponse
 * Overpass, allégée des étiquettes que `ruesDOverpass` ne lit pas (noms,
 * vitesses, revêtements… : 2,3 Mo au lieu de quelques centaines de Ko).
 *
 *   npx tsx scripts/record-overpass-fixture.ts
 *
 * La zone est celle de la carte de ville d'un séjour à Paris — le centre, la
 * tour Eiffel, le Louvre, Montmartre —, calculée comme `expandMaps` la calcule.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { dirname, resolve } from "node:path";
import { CADRE_MIN_VILLE, requeteOverpass, vueDeVille, voyageFrame } from "../src/services/mapSvg.js";

export const LIEUX_DE_PARIS = [
  { label: "Paris", lat: 48.8566, lon: 2.3522 },
  { label: "Tour Eiffel", lat: 48.8584, lon: 2.2945 },
  { label: "Louvre", lat: 48.8606, lon: 2.3376 },
  { label: "Montmartre", lat: 48.8867, lon: 2.3431 },
];

const url = process.env.OVERPASS_URL || "https://overpass-api.de/api/interpreter";
const vue = vueDeVille(voyageFrame(LIEUX_DE_PARIS, "FR", CADRE_MIN_VILLE)!);
const reponse = await fetch(url, {
  method: "POST",
  headers: {
    "content-type": "application/x-www-form-urlencoded",
    "user-agent": "MemoBook/1.0 (https://memo-book.com ; cartes de chapitre)",
  },
  body: new URLSearchParams({ data: requeteOverpass(vue) }),
});
if (!reponse.ok) throw new Error(`Overpass : HTTP ${reponse.status}`);
const json = (await reponse.json()) as {
  elements: { type: string; tags?: Record<string, string>; geometry?: unknown }[];
};
const LUES = ["highway", "waterway", "natural"];
const elements = json.elements.map(({ type, tags = {}, geometry }) => ({
  type,
  tags: Object.fromEntries(Object.entries(tags).filter(([k]) => LUES.includes(k))),
  geometry,
}));
const sortie = resolve(import.meta.dirname, "../test/fixtures/osm/overpass-paris.json.gz");
mkdirSync(dirname(sortie), { recursive: true });
writeFileSync(sortie, gzipSync(JSON.stringify({ elements }), { level: 9 }));
console.log(`${vue.join(", ")} : ${elements.length} éléments → ${sortie}`);
