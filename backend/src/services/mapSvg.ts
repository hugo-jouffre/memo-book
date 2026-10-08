import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Cartes de chapitre.
 *
 * Le carnet ouvre chaque chapitre sur une carte de la région traversée, avec un
 * point par étape. Trois contraintes commandent la conception :
 *
 * 1. **N'importe quelle région du monde.** Une illustration dessinée à la main
 *    ne couvre qu'un pays ; il en faudrait deux cents. On part donc d'un jeu de
 *    contours (Natural Earth 110 m, simplifié dans `assets/maps/countries.json`,
 *    et 10 m par pays dans `assets/maps/detail/` pour les cartes cadrées sur
 *    le voyage) et on projette.
 * 2. **Les points doivent tomber juste.** Placer une pastille « à peu près là »
 *    sur une image se voit immédiatement quand on connaît le pays. La même
 *    projection sert au tracé du pays et aux points : ils ne peuvent pas
 *    diverger.
 * 3. **Aucun appel réseau au rendu.** Le moteur PDF ne reçoit que deux chaînes.
 *    La carte est donc un SVG produit ici puis inséré en `data:` dans le
 *    payload, avant l'appel au rendu.
 */

export interface MapPoint {
  label: string;
  lat: number;
  lon: number;
  /** Une étape déjà parcourue : petit point sans nom, relié par le trajet. */
  secondaire?: boolean;
  /**
   * Comment le voyageur est arrivé à ce point depuis le précédent : avion
   * (courbe en pointillés), bateau (droite en pointillés), terre (droite
   * pleine). Sans lui, une droite en pointillés.
   */
  mode?: TransportMode | null;
}

export interface MapRequest {
  /**
   * Codes ISO 3166-1 alpha-2. Le premier est le pays du chapitre : la vue se
   * cadre sur les points de toutes les cartes du carnet dans ce pays
   * (`expandMaps`). Sans contour détaillé, il cadre le pays entier.
   */
  regions: string[];
  points?: MapPoint[];
  widthPt?: number;
  heightPt?: number;
}

interface Country {
  name: string;
  rings: [number, number][][];
}

const DATA = resolve(import.meta.dirname, "../../../assets/maps/countries.json");

let cache: Record<string, Country> | undefined;

function countries(): Record<string, Country> {
  cache ??= JSON.parse(readFileSync(DATA, "utf8")) as Record<string, Country>;
  return cache;
}

export function knownRegions(): string[] {
  return Object.keys(countries()).sort();
}

// ---------------------------------------------------------------------------
// Projection
// ---------------------------------------------------------------------------

/**
 * Mercator sphérique. C'est la projection que tout le monde a en tête quand il
 * regarde une carte, et elle reste honnête à l'échelle d'un pays. Elle diverge
 * près des pôles : au-delà de 84° de latitude on borne, faute de quoi la
 * projection part à l'infini et le tracé disparaît.
 */
const MAX_LAT = 84;

/**
 * Les deux axes doivent être dans la même unité, sinon le pays est aplati : la
 * longitude passe donc en radians, comme l'ordonnée.
 */
function mercatorX(lon: number): number {
  return (lon * Math.PI) / 180;
}

function mercatorY(lat: number): number {
  const clamped = Math.max(-MAX_LAT, Math.min(MAX_LAT, lat));
  const rad = (clamped * Math.PI) / 180;
  return Math.log(Math.tan(Math.PI / 4 + rad / 2));
}

interface Frame {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
  scale: number;
  width: number;
  height: number;
  padding: number;
}

function buildFrame(rings: [number, number][][], width: number, height: number): Frame {
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;

  for (const ring of rings) {
    for (const [lon, lat] of ring) {
      const x = mercatorX(lon);
      const y = mercatorY(lat);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  const padding = 10;
  const usableW = width - padding * 2;
  const usableH = height - padding * 2;
  // Une seule échelle pour les deux axes : sinon le pays est étiré, et un pays
  // étiré se reconnaît au premier coup d'œil.
  const scale = Math.min(usableW / (maxX - minX || 1), usableH / (maxY - minY || 1));

  return { minX, maxX, minY, maxY, scale, width, height, padding };
}

function project(frame: Frame, lon: number, lat: number): [number, number] {
  const spanX = (frame.maxX - frame.minX) * frame.scale;
  const spanY = (frame.maxY - frame.minY) * frame.scale;
  const offsetX = (frame.width - spanX) / 2;
  const offsetY = (frame.height - spanY) / 2;

  const x = offsetX + (mercatorX(lon) - frame.minX) * frame.scale;
  // L'axe SVG descend, la latitude monte : on inverse.
  const y = offsetY + (frame.maxY - mercatorY(lat)) * frame.scale;
  return [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
}

// ---------------------------------------------------------------------------
// Rendu
// ---------------------------------------------------------------------------

const OUTLINE = "#19532b"; // Forest Green, palette MemoBook
const FILL = "rgba(25, 83, 43, 0.05)"; // à peine posé, pour donner du corps
const PIN = "#f86015"; // Carrot
/** Un halo couleur papier sous les noms : le trajet pointillé passe dessous sans les barrer. */
const HALO = 'stroke="#fbf8f4" stroke-width="2.2" stroke-opacity="0.9" stroke-linejoin="round" paint-order="stroke"';

/**
 * Adoucit le contour.
 *
 * Natural Earth est une polyligne : tracée telle quelle, elle donne des côtes
 * en dents de scie qui trahissent la donnée brute. On la relit en courbes de
 * Bézier (Catmull-Rom converti), ce qui rend le trait rond, proche d'un
 * contour tracé à la main — et ne déplace aucun sommet : les points d'origine
 * restent sur la courbe, donc les épingles restent justes.
 */
const TENSION = 0.22;

function smoothPath(points: [number, number][]): string {
  const n = points.length;
  const at = (i: number): [number, number] => points[((i % n) + n) % n]!;
  const round = (v: number): number => Math.round(v * 10) / 10;

  const start = at(0);
  let d = `M${start[0]} ${start[1]}`;

  for (let i = 0; i < n; i += 1) {
    const p0 = at(i - 1);
    const p1 = at(i);
    const p2 = at(i + 1);
    const p3 = at(i + 2);

    const c1x = p1[0] + (p2[0] - p0[0]) * TENSION;
    const c1y = p1[1] + (p2[1] - p0[1]) * TENSION;
    const c2x = p2[0] - (p3[0] - p1[0]) * TENSION;
    const c2y = p2[1] - (p3[1] - p1[1]) * TENSION;

    d += ` C${round(c1x)} ${round(c1y)} ${round(c2x)} ${round(c2y)} ${round(p2[0])} ${round(p2[1])}`;
  }
  return `${d}Z`;
}

/** Le moyen de transport qui mène à un point : il décide du trait du trajet. */
export type TransportMode = "avion" | "bateau" | "terre";

interface Segment {
  mode: TransportMode | null;
  a: [number, number];
  b: [number, number];
  c: [number, number] | null;
}

/**
 * Les segments du trajet, chacun dessiné selon le moyen de transport qui mène
 * à son point d'arrivée (`mode`) : avion, une courbe en pointillés bombée vers
 * le haut ; bateau, une ligne droite en pointillés ; terre, une ligne droite
 * pleine ; inconnu, une ligne droite en pointillés (`defaut` le remplace —
 * terre sur une carte de ville). Recopie de `segmentsDuTrajet` (`carte.js`).
 */
function segmentsDuTrajet(
  points: { x: number; y: number; mode?: TransportMode | null }[],
  defaut: TransportMode | null = null,
): Segment[] {
  const r = (v: number): number => Math.round(v * 10) / 10;
  const segments: Segment[] = [];
  for (let i = 1; i < points.length; i += 1) {
    const a: [number, number] = [points[i - 1]!.x, points[i - 1]!.y];
    const b: [number, number] = [points[i]!.x, points[i]!.y];
    const mode = points[i]!.mode || defaut;
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    if (l < 0.5) continue;
    let c: [number, number] | null = null;
    if (mode === "avion") {
      let nx = -(b[1] - a[1]) / l;
      let ny = (b[0] - a[0]) / l;
      if (ny > 0 || (ny === 0 && nx > 0)) {
        nx = -nx;
        ny = -ny;
      }
      c = [r((a[0] + b[0]) / 2 + nx * l * 0.22), r((a[1] + b[1]) / 2 + ny * l * 0.22)];
    }
    segments.push({ mode, a, b, c });
  }
  return segments;
}

/** Le trajet en SVG : un `<path>` par segment, au style de son moyen de transport. */
function trajetSvg(segments: Segment[], couleur: string, epaisseur = 0.9): string {
  return segments
    .map(({ mode, a, b, c }) => {
      const d = c ? `M${a[0]} ${a[1]}Q${c[0]} ${c[1]} ${b[0]} ${b[1]}` : `M${a[0]} ${a[1]}L${b[0]} ${b[1]}`;
      const pointilles = mode === "terre" ? "" : ` stroke-dasharray="${mode === "avion" ? "1.4 1.8" : "2 2"}"`;
      return `<path d="${d}" fill="none" stroke="${couleur}" stroke-width="${epaisseur}"${pointilles} stroke-linecap="round"/>`;
    })
    .join("");
}

const escapeXml = (value: string): string =>
  value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

export class UnknownRegionError extends Error {
  constructor(code: string) {
    super(
      `Région « ${code} » inconnue. Utilise un code ISO 3166-1 alpha-2 ` +
        `(FR, PH, CO…) présent dans assets/maps/countries.json.`,
    );
    this.name = "UnknownRegionError";
  }
}

/** Produit le SVG de la carte, prêt à être inséré en data URI. */
export function renderMapSvg(request: MapRequest): string {
  const { regions, points = [], widthPt = 200, heightPt = 260 } = request;

  if (regions.length === 0) throw new Error("Une carte demande au moins une région.");

  const all = countries();
  const shapes: { code: string; rings: [number, number][][] }[] = [];

  for (const code of regions) {
    const country = all[code.toUpperCase()];
    if (!country) throw new UnknownRegionError(code);
    shapes.push({ code, rings: country.rings });
  }

  // Le cadrage suit la première région : c'est elle le sujet du chapitre, les
  // suivantes ne sont là que pour le contexte.
  const first = shapes[0];
  if (!first) throw new Error("Une carte demande au moins une région.");
  const frame = buildFrame(first.rings, widthPt, heightPt);

  const paths = shapes
    .map(({ rings }) =>
      rings
        .map((ring) => {
          const points = ring.map(([lon, lat]) => project(frame, lon, lat));
          // Une île réduite à trois points après simplification ne se lisse pas.
          if (points.length < 4) return "";
          return (
            `<path d="${smoothPath(points)}" fill="${FILL}" stroke="${OUTLINE}" ` +
            `stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round" ` +
            `stroke-dasharray="3.2 2.6"/>`
          );
        })
        .join(""),
    )
    .join("");

  const pins = points
    .map((point) => {
      const [x, y] = project(frame, point.lon, point.lat);
      // Goutte inversée : le sommet touche la coordonnée exacte, comme une
      // épingle plantée. Un cercle centré décalerait le point de son rayon.
      const pin =
        `<path d="M${x} ${y} c-3.4 -4.6 -5.2 -6.8 -5.2 -9.4 a5.2 5.2 0 1 1 10.4 0 ` +
        `c0 2.6 -1.8 4.8 -5.2 9.4Z" fill="${PIN}"/>` +
        `<circle cx="${x}" cy="${y - 9.4}" r="1.9" fill="#fff"/>`;
      const label =
        `<text x="${x}" y="${y + 9}" text-anchor="middle" fill="${PIN}" ` +
        `font-family="Playfair Display, serif" font-weight="900" font-size="7.5">` +
        `${escapeXml(point.label)}</text>`;
      return pin + label;
    })
    .join("");

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${widthPt} ${heightPt}" ` +
    `width="${widthPt}" height="${heightPt}">${paths}${pins}</svg>`
  );
}

const enDataUri = (svg: string): string =>
  `data:image/svg+xml;base64,${Buffer.from(svg, "utf8").toString("base64")}`;

/** Le SVG encodé en data URI, tel qu'il part dans le payload. */
export function renderMapDataUri(request: MapRequest): string {
  return enDataUri(renderMapSvg(request));
}

// ---------------------------------------------------------------------------
// Carte cadrée sur le voyage
// ---------------------------------------------------------------------------

/**
 * Cadrer sur le pays entier ne marche pas pour un voyage qui n'en parcourt
 * qu'un coin : un voyage aux Cyclades donnait le continent grec et la Crète,
 * avec les épingles en pleine mer — 110 m n'a même pas les Cyclades. La carte
 * se cadre donc sur la zone que le voyage parcourt (`voyageFrame`), et se
 * dessine avec les contours de Natural Earth 10 m (`assets/maps/detail/`, un
 * fichier par pays, `scripts/build-map-detail.ts`).
 *
 * **Recopie de `MemoBook Generator/public/carte.js`** (`renderCarteCadree`) et
 * de `mise-en-page.js` (`cadreDuVoyage`) : l'atelier dessine ses cartes
 * lui-même. `test/carteAtelier.test.ts` garde les deux identiques.
 */

/** `[ouest, sud, est, nord]`, en degrés. */
export type Cadre = [number, number, number, number];

interface DetailCountry {
  name: string;
  bbox: Cadre;
  rings: [number, number][][];
}

const DETAIL = resolve(import.meta.dirname, "../../../assets/maps/detail");
let detailIndexCache: Record<string, { name: string; bbox: Cadre }> | null | undefined;
const detailCache = new Map<string, DetailCountry>();

function detailIndex(): Record<string, { name: string; bbox: Cadre }> | null {
  if (detailIndexCache === undefined) {
    try {
      detailIndexCache = JSON.parse(readFileSync(resolve(DETAIL, "index.json"), "utf8")) as Record<
        string,
        { name: string; bbox: Cadre }
      >;
    } catch {
      detailIndexCache = null;
    }
  }
  return detailIndexCache;
}

function detailOf(code: string): DetailCountry {
  let country = detailCache.get(code);
  if (!country) {
    country = JSON.parse(readFileSync(resolve(DETAIL, `${code}.json`), "utf8")) as DetailCountry;
    detailCache.set(code, country);
  }
  return country;
}

/** Un degré au moins de côté (~110 km) : en deçà, la carte ne montre plus où l'on est. */
const CADRE_MIN_DEGRES = 1;
/** La marge autour des lieux, de part et d'autre : 20 % de leur étendue. */
const MARGE_CADRE = 0.2;

/**
 * La zone que le voyage parcourt dans un pays : tous ses lieux, 20 % de marge
 * de chaque côté, un degré de côté au moins, jamais plus grand que le pays (un
 * tour de la Grèce retrouve la carte de la Grèce). `null` sans lieu.
 */
export function voyageFrame(
  places: { lat: number; lon: number }[],
  region: string,
  minimum = CADRE_MIN_DEGRES,
): Cadre | null {
  if (!places.length) return null;
  let o = Math.min(...places.map((l) => l.lon));
  let e = Math.max(...places.map((l) => l.lon));
  let s = Math.min(...places.map((l) => l.lat));
  let n = Math.max(...places.map((l) => l.lat));
  // Un degré de longitude rétrécit avec la latitude : le minimum se compte en
  // distance, pas en degrés bruts.
  const cosLat = Math.max(0.2, Math.cos((((s + n) / 2) * Math.PI) / 180));
  const elargir = (a: number, b: number, min: number): [number, number] => {
    const c = (a + b) / 2;
    const demi = Math.max(((b - a) * (1 + 2 * MARGE_CADRE)) / 2, min / 2);
    return [c - demi, c + demi];
  };
  [s, n] = elargir(s, n, minimum);
  [o, e] = elargir(o, e, minimum / cosLat);

  const rings = countries()[region.toUpperCase()]?.rings;
  if (rings?.length) {
    const lons = rings.flat().map((p) => p[0]);
    const lats = rings.flat().map((p) => p[1]);
    const marge = 0.3;
    o = Math.max(o, Math.min(...lons) - marge);
    e = Math.min(e, Math.max(...lons) + marge);
    s = Math.max(s, Math.min(...lats) - marge);
    n = Math.min(n, Math.max(...lats) + marge);
  }
  const arrondi = (v: number): number => Math.round(v * 1000) / 1000;
  return [arrondi(o), arrondi(s), arrondi(e), arrondi(n)];
}

/**
 * Un séjour en un seul lieu — une ville, une île : tous les lieux du carnet
 * dans le pays tiennent dans ~30 km. Sa première carte montre le pays et y
 * situe la ville ; les suivantes zooment sur la ville et y tracent les
 * déplacements.
 */
const ETENDUE_SEJOUR = 0.3;
/** Trois kilomètres de côté au moins pour une carte de ville. */
export const CADRE_MIN_VILLE = 0.03;
/** Lieux nommés sur une carte de ville : au-delà, les noms se chevauchent. */
const MAX_NOUVEAUX_VILLE = 3;
/** Six points au plus sur une carte. */
const MAX_POINTS_CARTE = 6;

export function isSingleStay(places: { lat: number; lon: number }[]): boolean {
  if (!places.length) return false;
  const lats = places.map((l) => l.lat);
  const lons = places.map((l) => l.lon);
  const cosLat = Math.max(0.2, Math.cos((((Math.min(...lats) + Math.max(...lats)) / 2) * Math.PI) / 180));
  return (
    Math.max(...lats) - Math.min(...lats) <= ETENDUE_SEJOUR &&
    (Math.max(...lons) - Math.min(...lons)) * cosLat <= ETENDUE_SEJOUR
  );
}

/**
 * Le pays entier, avec la même marge que le plafond de `voyageFrame` — mais
 * le pays tel qu'on le reconnaît : son plus grand territoire et les terres à
 * moins de deux degrés (la Corse), pas l'outre-mer (la boîte de la France va
 * jusqu'à la Guyane). Le lieu du séjour y est toujours.
 */
export function countryFrame(region: string, place: { lat: number; lon: number } | null = null): Cadre | null {
  const tous = countries()[region.toUpperCase()]?.rings;
  if (!tous?.length) return null;
  const boite = (ring: [number, number][]): Cadre => [
    Math.min(...ring.map((p) => p[0])),
    Math.min(...ring.map((p) => p[1])),
    Math.max(...ring.map((p) => p[0])),
    Math.max(...ring.map((p) => p[1])),
  ];
  const aire = (b: Cadre): number => (b[2] - b[0]) * (b[3] - b[1]);
  const boites = tous.map(boite);
  const principal = boites.reduce((a, b) => (aire(b) > aire(a) ? b : a));
  const proches = boites.filter(
    (b) => b[0] <= principal[2] + 2 && principal[0] - 2 <= b[2] && b[1] <= principal[3] + 2 && principal[1] - 2 <= b[3],
  );
  const lons = proches.flatMap((b) => [b[0], b[2]]).concat(place ? [place.lon] : []);
  const lats = proches.flatMap((b) => [b[1], b[3]]).concat(place ? [place.lat] : []);
  const marge = 0.3;
  const arrondi = (v: number): number => Math.round(v * 1000) / 1000;
  return [
    arrondi(Math.min(...lons) - marge),
    arrondi(Math.min(...lats) - marge),
    arrondi(Math.max(...lons) + marge),
    arrondi(Math.max(...lats) + marge),
  ];
}

/** Simplification Douglas-Peucker, en points de page : le trait ne garde que ce qui se voit. */
function simplifier(points: [number, number][], tolerance: number): [number, number][] {
  if (points.length < 4) return points;
  const garder = new Uint8Array(points.length);
  garder[0] = 1;
  garder[points.length - 1] = 1;
  const pile: [number, number][] = [[0, points.length - 1]];
  while (pile.length) {
    const [a, b] = pile.pop()!;
    const [x1, y1] = points[a]!;
    const [x2, y2] = points[b]!;
    const dx = x2 - x1;
    const dy = y2 - y1;
    const l2 = dx * dx + dy * dy;
    let max = 0;
    let index = -1;
    for (let i = a + 1; i < b; i += 1) {
      const [x, y] = points[i]!;
      const t = l2 ? Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / l2)) : 0;
      const d = Math.hypot(x - (x1 + t * dx), y - (y1 + t * dy));
      if (d > max) {
        max = d;
        index = i;
      }
    }
    if (max > tolerance && index > 0) {
      garder[index] = 1;
      pile.push([a, index], [index, b]);
    }
  }
  return points.filter((_, i) => garder[i]);
}

/**
 * Coupe un contour au rectangle `[x0, y0, x1, y1]` (Sutherland-Hodgman). Ce
 * qui sort de la carte n'a pas à peser dans le payload.
 */
function couper(points: [number, number][], [x0, y0, x1, y1]: Cadre): [number, number][] {
  type Pt = [number, number];
  const bords: [(p: Pt) => boolean, (a: Pt, b: Pt) => Pt][] = [
    [(p) => p[0] >= x0, (a, b) => [x0, a[1] + ((b[1] - a[1]) * (x0 - a[0])) / (b[0] - a[0])]],
    [(p) => p[0] <= x1, (a, b) => [x1, a[1] + ((b[1] - a[1]) * (x1 - a[0])) / (b[0] - a[0])]],
    [(p) => p[1] >= y0, (a, b) => [a[0] + ((b[0] - a[0]) * (y0 - a[1])) / (b[1] - a[1]), y0]],
    [(p) => p[1] <= y1, (a, b) => [a[0] + ((b[0] - a[0]) * (y1 - a[1])) / (b[1] - a[1]), y1]],
  ];
  let sortie: Pt[] = points;
  for (const [dedans, croisement] of bords) {
    const entree = sortie;
    sortie = [];
    for (let i = 0; i < entree.length; i += 1) {
      const a = entree[(i + entree.length - 1) % entree.length]!;
      const b = entree[i]!;
      if (dedans(b)) {
        if (!dedans(a)) sortie.push(croisement(a, b));
        sortie.push(b);
      } else if (dedans(a)) sortie.push(croisement(a, b));
    }
    if (!sortie.length) break;
  }
  return sortie.map(([x, y]) => [Math.round(x * 10) / 10, Math.round(y * 10) / 10]);
}

const seCroisent = (a: Cadre, b: Cadre): boolean => a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];
const boiteDe = (ring: [number, number][]): Cadre => {
  let o = Infinity;
  let s = Infinity;
  let e = -Infinity;
  let n = -Infinity;
  for (const [lon, lat] of ring) {
    if (lon < o) o = lon;
    if (lon > e) e = lon;
    if (lat < s) s = lat;
    if (lat > n) n = lat;
  }
  return [o, s, e, n];
};

export interface FramedMapRequest {
  cadre: Cadre;
  points?: MapPoint[];
  widthPt?: number;
  heightPt?: number;
  /**
   * Carte de ville : le trajet relie les points dans l'ordre, une barre
   * d'échelle dit les distances, les lieux déjà passés gardent leur nom.
   */
  ville?: boolean;
  /** Le nom de la ville, écrit en tête. */
  titre?: string;
}

/**
 * La carte cadrée sur `request.cadre`, élargi au format de la carte. Tous les
 * pays de `detail` se dessinent — une côte voisine aide à se situer —, coupés
 * au bord, et effacés en fondu sur les bords.
 */
export function renderFramedMapSvg(detail: Record<string, DetailCountry>, request: FramedMapRequest): string {
  const { cadre, points = [], widthPt = 200, heightPt = 260, ville = false, titre = "" } = request;
  const padding = 10;
  // Le cadre en Mercator, élargi au format de la carte, centré.
  let minX = mercatorX(cadre[0]);
  let maxX = mercatorX(cadre[2]);
  let minY = mercatorY(cadre[1]);
  let maxY = mercatorY(cadre[3]);
  const largeurUtile = widthPt - padding * 2;
  const hauteurUtile = heightPt - padding * 2;
  const scale = Math.min(largeurUtile / (maxX - minX || 1e-6), hauteurUtile / (maxY - minY || 1e-6));
  const manqueX = (largeurUtile / scale - (maxX - minX)) / 2;
  const manqueY = (hauteurUtile / scale - (maxY - minY)) / 2;
  minX -= manqueX;
  maxX += manqueX;
  minY -= manqueY;
  maxY += manqueY;
  const frame: Frame = { minX, maxX, minY, maxY, scale, width: widthPt, height: heightPt, padding };
  const vue: Cadre = [
    (minX * 180) / Math.PI - 0.5,
    ((2 * Math.atan(Math.exp(minY)) - Math.PI / 2) * 180) / Math.PI - 0.5,
    (maxX * 180) / Math.PI + 0.5,
    ((2 * Math.atan(Math.exp(maxY)) - Math.PI / 2) * 180) / Math.PI + 0.5,
  ];

  let paths = "";
  for (const pays of Object.values(detail)) {
    if (!pays.rings || (pays.bbox && !seCroisent(pays.bbox, vue))) continue;
    for (const ring of pays.rings) {
      if (!seCroisent(boiteDe(ring), vue)) continue;
      // Coupé à 12 pt hors de la carte : le bord de coupe, droit, reste
      // invisible, et le lissage n'y fait pas de vague dans le cadre.
      const pts = simplifier(
        couper(
          ring.map(([lon, lat]) => project(frame, lon, lat)),
          [-12, -12, widthPt + 12, heightPt + 12],
        ),
        0.45,
      );
      // Un îlot de moins de deux points de large ne se lit pas.
      const [o, s, e, n] = boiteDe(pts);
      if (pts.length < 3 || (e - o < 2 && n - s < 2)) continue;
      paths +=
        `<path d="${smoothPath(pts)}" fill="${FILL}" stroke="${OUTLINE}" ` +
        `stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round" ` +
        `stroke-dasharray="3.2 2.6"/>`;
    }
  }

  const trajet =
    ville || points.some((p) => p.secondaire || p.mode)
      ? trajetSvg(
          segmentsDuTrajet(
            points.map((p) => {
              const [x, y] = project(frame, p.lon, p.lat);
              return { x, y, mode: p.mode };
            }),
            ville ? "terre" : null,
          ),
          PIN,
        )
      : "";
  // Sur une carte de ville, sans rue pour se repérer, les lieux déjà passés
  // gardent leur nom, en petit : à droite du point, à gauche s'il y chevauche
  // un autre nom, sinon tu.
  const r = (v: number): number => Math.round(v * 10) / 10;
  const occupes: Cadre[] = points
    .filter((p) => !p.secondaire)
    .map((p) => {
      const [x, y] = project(frame, p.lon, p.lat);
      const l = String(p.label).length * 4.1;
      return [x - l / 2, y - 15, x + l / 2, y + 11];
    });
  if (titre) occupes.push([padding, padding, padding + 4 + String(titre).length * 7.5, padding + 12]);
  const libre = (b: Cadre): boolean => !occupes.some((o) => b[0] < o[2] && o[0] < b[2] && b[1] < o[3] && o[1] < b[3]);
  const pins = points
    .map((point) => {
      const [x, y] = project(frame, point.lon, point.lat);
      if (point.secondaire) {
        const rond = `<circle cx="${x}" cy="${y}" r="2.2" fill="#fff" stroke="${PIN}" stroke-width="1.1"/>`;
        if (!ville) return rond;
        const l = String(point.label).length * 2.9;
        const droite: Cadre = [x + 4, y - 4, x + 4 + l, y + 3];
        const gauche: Cadre = [x - 4 - l, y - 4, x - 4, y + 3];
        const place: [string, number, Cadre] | null = libre(droite)
          ? ["start", droite[0], droite]
          : libre(gauche)
            ? ["end", gauche[2], gauche]
            : null;
        if (!place) return rond;
        occupes.push(place[2]);
        return (
          rond +
          `<text x="${r(place[1])}" y="${r(y + 2)}" text-anchor="${place[0]}" fill="${OUTLINE}" ` +
          `font-family="Playfair Display, serif" font-size="5.5" ${HALO}>${escapeXml(point.label)}</text>`
        );
      }
      return (
        `<path d="M${x} ${y} c-3.4 -4.6 -5.2 -6.8 -5.2 -9.4 a5.2 5.2 0 1 1 10.4 0 ` +
        `c0 2.6 -1.8 4.8 -5.2 9.4Z" fill="${PIN}"/>` +
        `<circle cx="${x}" cy="${y - 9.4}" r="1.9" fill="#fff"/>` +
        `<text x="${x}" y="${y + 9}" text-anchor="middle" fill="${PIN}" ` +
        `font-family="Playfair Display, serif" font-weight="900" font-size="7.5" ${HALO}>` +
        `${escapeXml(point.label)}</text>`
      );
    })
    .join("");
  // Le nom de la ville, en tête : c'est lui qui dit où l'on est.
  const enTete = titre
    ? `<text x="${padding + 2}" y="${padding + 9}" fill="${OUTLINE}" font-family="Playfair Display, serif" ` +
      `font-weight="900" font-size="9" letter-spacing="1.6">${escapeXml(String(titre).toUpperCase())}</text>`
    : "";

  // Barre d'échelle, en bas à gauche : la plus longue longueur ronde qui
  // tienne dans 60 pt. Un degré de longitude vaut R·cos(φ) : l'échelle se lit
  // au centre du cadre.
  let echelle = "";
  if (ville) {
    const latCentre = (((cadre[1] + cadre[3]) / 2) * Math.PI) / 180;
    const ptParKm = scale / (6371.0088 * Math.cos(latCentre));
    const km = [100, 50, 20, 10, 5, 2, 1, 0.5, 0.25, 0.2, 0.1].find((k) => k * ptParKm <= 60) ?? 0.1;
    const l = Math.round(km * ptParKm * 10) / 10;
    const x0 = padding + 2;
    const y0 = heightPt - padding - 4;
    const texte = km < 1 ? `${Math.round(km * 1000)} m` : `${km} km`;
    echelle =
      `<path d="M${x0} ${y0 - 3}v3h${l}v-3" fill="none" stroke="${OUTLINE}" stroke-width="0.9" stroke-linejoin="round"/>` +
      `<text x="${x0 + l / 2}" y="${y0 - 5}" text-anchor="middle" fill="${OUTLINE}" ` +
      `font-family="Playfair Display, serif" font-size="6.5">${texte}</text>`;
  }

  // Les côtes coupées par le cadre s'effacent en fondu sur les bords : un
  // trait tranché net au bord de la carte se lit comme une erreur.
  const fondu = (id: string, x2: number, y2: number): string =>
    `<linearGradient id="${id}" x1="0" y1="0" x2="${x2}" y2="${y2}">` +
    `<stop offset="0" stop-color="#000"/><stop offset="0.09" stop-color="#fff"/>` +
    `<stop offset="0.91" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient>`;
  const defs =
    `<defs>${fondu("fh", 1, 0)}${fondu("fv", 0, 1)}` +
    `<mask id="mh"><rect width="${widthPt}" height="${heightPt}" fill="url(#fh)"/></mask>` +
    `<mask id="mv"><rect width="${widthPt}" height="${heightPt}" fill="url(#fv)"/></mask></defs>`;

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${widthPt} ${heightPt}" ` +
    `width="${widthPt}" height="${heightPt}">${defs}` +
    `<g mask="url(#mh)"><g mask="url(#mv)">${paths}</g></g>${enTete}${echelle}${trajet}${pins}</svg>`
  );
}

/**
 * Les contours détaillés des pays qui touchent un cadre (élargi d'un degré :
 * la carte s'élargit au format de la page). `null` si le pays du chapitre n'a
 * pas de contour détaillé : la carte retombe alors sur le pays entier.
 */
function detailAround(region: string, cadre: Cadre): Record<string, DetailCountry> | null {
  const index = detailIndex();
  if (!index?.[region]) return null;
  const elargi: Cadre = [cadre[0] - 1, cadre[1] - 1, cadre[2] + 1, cadre[3] + 1];
  const detail: Record<string, DetailCountry> = {};
  for (const [code, { bbox }] of Object.entries(index)) {
    if (seCroisent(bbox, elargi)) detail[code] = detailOf(code);
  }
  return detail;
}

/**
 * Complète le payload : chaque chapitre portant un objet `map` reçoit un
 * `map_svg` prêt à afficher.
 *
 * L'agent décrit la carte (« Philippines, avec Manille et les Visayas »), il ne
 * la dessine pas. La géométrie est un travail déterministe, elle n'a rien à
 * faire dans un prompt.
 */
export function expandMaps(payload: Record<string, unknown>): Record<string, unknown> {
  const days = payload["days"];
  if (!Array.isArray(days)) return payload;

  const maps = days
    .map((day) => (day as Record<string, unknown>)["map"] as MapRequest | undefined)
    .filter((map): map is MapRequest => Boolean(map && Array.isArray(map.regions) && map.regions.length > 0));

  // Le cadre d'un pays : tous les lieux que les cartes du carnet y pointent —
  // ceux où les récits emmènent le voyageur. Le même pour chaque chapitre du
  // pays : d'une carte à l'autre, on voit le trajet avancer.
  const cadres = new Map<string, Cadre | null>();
  const cadreDe = (region: string): Cadre | null => {
    if (!cadres.has(region)) {
      const places = maps
        .filter((map) => map.regions[0]!.toUpperCase() === region)
        .flatMap((map) => map.points ?? [])
        .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
      cadres.set(region, voyageFrame(places, region));
    }
    return cadres.get(region) ?? null;
  };

  // Séjour en un seul lieu (une ville, une île) : la première carte du pays
  // montre le pays et y situe la ville ; les suivantes zooment sur la ville,
  // nomment les lieux du chapitre, gardent ceux des chapitres précédents en
  // petits points et tracent le parcours qui les relie.
  const sejours = new Map<string, { ville: string; titre: string; parcours: MapPoint[]; passes: Set<string> }>();
  const pointsDe = (map: MapRequest) => (map.points ?? []).filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  const enSejour = (region: string) =>
    isSingleStay(maps.filter((m) => m.regions[0]!.toUpperCase() === region).flatMap(pointsDe));
  const cle = (p: MapPoint) => p.label.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

  const expanded = days.map((day) => {
    const entry = day as Record<string, unknown>;
    const map = entry["map"] as MapRequest | undefined;
    if (!map || !Array.isArray(map.regions) || map.regions.length === 0) return entry;
    const region = map.regions[0]!.toUpperCase();
    const taille = { widthPt: map.widthPt, heightPt: map.heightPt };

    let request: FramedMapRequest | null = null;
    if (enSejour(region)) {
      const sejour = sejours.get(region);
      if (!sejour) {
        // La ville est le premier point de la première carte ; les autres
        // points de cette carte entrent dans le parcours.
        const [ville, ...autres] = pointsDe(map);
        const cadre = ville ? countryFrame(region, ville) : null;
        if (ville && cadre) request = { ...taille, cadre, points: [{ ...ville, secondaire: false }] };
        sejours.set(region, {
          ville: ville ? cle(ville) : "",
          titre: ville?.label ?? "",
          parcours: autres,
          passes: new Set(autres.map(cle)),
        });
      } else {
        const places = maps.filter((m) => m.regions[0]!.toUpperCase() === region).flatMap(pointsDe);
        const cadre = voyageFrame(places, region, CADRE_MIN_VILLE);
        const vus = new Set([sejour.ville]);
        const nouveaux = pointsDe(map).filter((p) => {
          const k = cle(p);
          if (!k || vus.has(k) || sejour.passes.has(k)) return false;
          vus.add(k);
          return true;
        });
        const montres = nouveaux.slice(0, MAX_NOUVEAUX_VILLE).map((p) => ({ ...p, secondaire: false }));
        const passes = sejour.parcours.slice(-(MAX_POINTS_CARTE - montres.length));
        if (cadre) {
          request = {
            ...taille,
            cadre,
            points: [...passes.map((p) => ({ ...p, secondaire: true })), ...montres],
            ville: true,
            titre: sejour.titre,
          };
        }
        for (const p of nouveaux) {
          sejour.parcours.push(p);
          sejour.passes.add(cle(p));
        }
      }
    } else {
      const cadre = cadreDe(region);
      if (cadre) request = { ...taille, cadre, points: map.points ?? [] };
    }

    const detail = request ? detailAround(region, request.cadre) : null;
    const svg = request && detail ? enDataUri(renderFramedMapSvg(detail, request)) : renderMapDataUri(map);
    return { ...entry, map_svg: svg };
  });

  return { ...payload, days: expanded };
}
