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
 *    contours (Natural Earth 110 m, simplifié dans `assets/maps/countries.json`)
 *    et on projette.
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
}

export interface MapRequest {
  /** Codes ISO 3166-1 alpha-2 des pays à tracer. Le premier cadre la vue. */
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

// TODO(design) — ces trois valeurs viennent de l'ancienne palette : Forest Green
// et Carrot ont été retirés de `agents/design.md`. Les changer modifie le rendu
// des carnets déjà produits, donc on attend l'arbitrage sur la palette du carnet
// (Green #28654B est le candidat évident pour le tracé, le pin reste à choisir).
const OUTLINE = "#19532b"; // ex-Forest Green
const FILL = "rgba(25, 83, 43, 0.05)"; // à peine posé, pour donner du corps
const PIN = "#f86015"; // ex-Carrot

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

/** Le SVG encodé en data URI, tel qu'il part dans le payload. */
export function renderMapDataUri(request: MapRequest): string {
  const svg = renderMapSvg(request);
  return `data:image/svg+xml;base64,${Buffer.from(svg, "utf8").toString("base64")}`;
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

  const expanded = days.map((day) => {
    const entry = day as Record<string, unknown>;
    const map = entry["map"] as MapRequest | undefined;
    if (!map || !Array.isArray(map.regions) || map.regions.length === 0) return entry;
    return { ...entry, map_svg: renderMapDataUri(map) };
  });

  return { ...payload, days: expanded };
}
