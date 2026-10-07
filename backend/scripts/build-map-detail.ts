#!/usr/bin/env tsx
/**
 * Contours détaillés des pays, pour les cartes de chapitre cadrées sur le
 * voyage (`MemoBook Generator/public/carte.js`).
 *
 * `assets/maps/countries.json` (Natural Earth 110 m) suffit à dessiner un pays
 * entier, mais il n'a pas les petites îles : les Cyclades n'y existent pas, et
 * une carte cadrée sur Paros, Naxos et Ios n'y montrerait que la mer. Ce
 * script tire de Natural Earth 10 m (domaine public) un fichier par pays,
 * chargé seulement quand une carte en a besoin :
 *
 * - `assets/maps/detail/<ISO2>.json` : `{ name, bbox, rings }` ;
 * - `assets/maps/detail/index.json` : `{ <ISO2>: { name, bbox } }`, pour savoir
 *   quels pays touchent le cadre d'une carte sans tous les charger.
 *
 * Simplification Douglas-Peucker à ~250 m, coordonnées au millième de degré
 * (~100 m) : le trait d'une carte de 200 pt couvrant 150 km fait ~700 m.
 * Les îlots de moins de ~0,2 km² sont écartés.
 *
 *   curl -L -o /tmp/ne10.geojson \
 *     https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson
 *   npx tsx scripts/build-map-detail.ts /tmp/ne10.geojson
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

type Point = [number, number];
interface Feature {
  properties: Record<string, unknown>;
  geometry: { type: "Polygon" | "MultiPolygon"; coordinates: Point[][] | Point[][][] } | null;
}

const TOLERANCE = 0.0025;
const AIRE_MIN = 0.00002;
const SORTIE = resolve(import.meta.dirname, "../../assets/maps/detail");

function distanceAuSegment([x, y]: Point, [x1, y1]: Point, [x2, y2]: Point): number {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const l2 = dx * dx + dy * dy;
  const t = l2 ? Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / l2)) : 0;
  return Math.hypot(x - (x1 + t * dx), y - (y1 + t * dy));
}

function simplifier(points: Point[]): Point[] {
  if (points.length < 3) return points;
  const garder = new Uint8Array(points.length);
  garder[0] = 1;
  garder[points.length - 1] = 1;
  const pile: [number, number][] = [[0, points.length - 1]];
  while (pile.length) {
    const [a, b] = pile.pop()!;
    let max = 0;
    let index = -1;
    for (let i = a + 1; i < b; i += 1) {
      const d = distanceAuSegment(points[i]!, points[a]!, points[b]!);
      if (d > max) {
        max = d;
        index = i;
      }
    }
    if (max > TOLERANCE && index > 0) {
      garder[index] = 1;
      pile.push([a, index], [index, b]);
    }
  }
  return points.filter((_, i) => garder[i]);
}

const aire = (ring: Point[]) =>
  Math.abs(ring.reduce((s, [x, y], i) => {
    const [x2, y2] = ring[(i + 1) % ring.length]!;
    return s + x * y2 - x2 * y;
  }, 0)) / 2;

const arrondi = (v: number) => Math.round(v * 1000) / 1000;

const source = process.argv[2];
if (!source) throw new Error("Usage : build-map-detail.ts <ne_10m_admin_0_countries.geojson>");
const { features } = JSON.parse(readFileSync(source, "utf8")) as { features: Feature[] };

mkdirSync(SORTIE, { recursive: true });
const index: Record<string, { name: string; bbox: [number, number, number, number] }> = {};
let total = 0;

for (const feature of features) {
  const props = feature.properties;
  const code = [props["ISO_A2_EH"], props["ISO_A2"]].find((c) => typeof c === "string" && /^[A-Z]{2}$/.test(c)) as
    | string
    | undefined;
  if (!code || !feature.geometry) continue;
  const polygones = (
    feature.geometry.type === "Polygon" ? [feature.geometry.coordinates] : feature.geometry.coordinates
  ) as Point[][][];

  const rings: Point[][] = [];
  for (const polygone of polygones) {
    const exterieur = polygone[0];
    if (!exterieur || aire(exterieur) < AIRE_MIN) continue;
    const ring = simplifier(exterieur).map(([lon, lat]) => [arrondi(lon), arrondi(lat)] as Point);
    // Fermé par la carte elle-même : le dernier point répète le premier.
    if (ring.length > 1 && ring[0]![0] === ring.at(-1)![0] && ring[0]![1] === ring.at(-1)![1]) ring.pop();
    if (ring.length >= 4) rings.push(ring);
  }
  if (!rings.length) continue;

  const lons = rings.flat().map((p) => p[0]);
  const lats = rings.flat().map((p) => p[1]);
  const bbox: [number, number, number, number] = [
    Math.min(...lons),
    Math.min(...lats),
    Math.max(...lons),
    Math.max(...lats),
  ];
  const name = [props["NAME"], props["ADMIN"]].find((n): n is string => typeof n === "string") ?? code;
  // Deux entités pour un code (rare) : on fusionne.
  const fichier = resolve(SORTIE, `${code}.json`);
  const deja = index[code];
  const tous = deja
    ? [...(JSON.parse(readFileSync(fichier, "utf8")) as { rings: Point[][] }).rings, ...rings]
    : rings;
  const cadre: [number, number, number, number] = deja
    ? [Math.min(deja.bbox[0], bbox[0]), Math.min(deja.bbox[1], bbox[1]), Math.max(deja.bbox[2], bbox[2]), Math.max(deja.bbox[3], bbox[3])]
    : bbox;
  const contenu = JSON.stringify({ name: deja?.name ?? name, bbox: cadre, rings: tous });
  writeFileSync(fichier, contenu);
  index[code] = { name: deja?.name ?? name, bbox: cadre };
  total += contenu.length;
}

writeFileSync(resolve(SORTIE, "index.json"), JSON.stringify(index));
console.log(`${Object.keys(index).length} pays, ${(total / 1024 / 1024).toFixed(1)} Mo`);
