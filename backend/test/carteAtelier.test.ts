import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  CADRE_MIN_VILLE,
  expandMaps,
  renderFramedMapSvg,
  renderMapSvg,
  voyageFrame,
} from "../src/services/mapSvg.js";

/**
 * L'atelier dessine ses cartes de chapitre lui-même (`MemoBook Generator/public/carte.js`),
 * parce qu'il envoie son payload à APITemplate sans passer par le back-end.
 * C'est une recopie de `mapSvg.ts` : ce test garde les deux identiques.
 */
const require = createRequire(import.meta.url);
const carte = require("../../MemoBook Generator/public/carte.js") as {
  renderMapSvg: (contours: unknown, request: unknown) => string;
  renderCarteCadree: (detail: unknown, request: unknown) => string;
};
const detail = (code: string) =>
  JSON.parse(readFileSync(resolve(import.meta.dirname, `../../assets/maps/detail/${code}.json`), "utf8")) as {
    name: string;
    bbox: [number, number, number, number];
    rings: [number, number][][];
  };
const miseEnPage = require("../../MemoBook Generator/public/mise-en-page.js") as {
  cadreDuVoyage: (lieux: unknown[], pays: string, contours: unknown) => number[] | null;
};
const cyclades = [
  { label: "Paros", lat: 37.08, lon: 25.15 },
  { label: "Naxos", lat: 37.1, lon: 25.38 },
  { label: "Ios", lat: 36.73, lon: 25.28 },
  { label: "Mykonos", lat: 37.45, lon: 25.33 },
];
const contours = JSON.parse(
  readFileSync(resolve(import.meta.dirname, "../../assets/maps/countries.json"), "utf8"),
) as unknown;

describe("carte de chapitre de l'atelier", () => {
  it("dessine la même carte que le back-end", () => {
    const request = {
      regions: ["GR", "TR"],
      points: [
        { label: "Paros", lat: 37.08, lon: 25.15 },
        { label: "Athènes", lat: 37.98, lon: 23.73 },
      ],
    };
    expect(carte.renderMapSvg(contours, request)).toBe(renderMapSvg(request));
  });

  it("dessine les étapes parcourues en petit, sans nom, reliées par le trajet", () => {
    const svg = carte.renderMapSvg(contours, {
      regions: ["GR"],
      points: [
        { label: "Paros", lat: 37.08, lon: 25.15, secondaire: true },
        { label: "Naxos", lat: 37.1, lon: 25.38 },
      ],
    });
    expect(svg).toContain("<polyline");
    expect(svg).not.toContain(">Paros<");
    expect(svg).toContain(">Naxos<");
  });

  it("cadre la carte sur la zone du voyage, avec les petites îles", () => {
    const request = {
      cadre: [24.9, 36.5, 25.7, 37.6],
      points: [
        { label: "Paros", lat: 37.08, lon: 25.15, secondaire: true },
        { label: "Ios", lat: 36.73, lon: 25.28 },
      ],
    };
    const svg = carte.renderCarteCadree({ GR: detail("GR"), TR: detail("TR") }, request);
    // Les Cyclades : une vingtaine d'îles là où la carte du pays n'en a aucune.
    expect((svg.match(/<path d=/g) ?? []).length).toBeGreaterThan(15);
    // L'épingle d'Ios tombe dans la carte, loin des bords.
    const [x, y] = svg.match(/<path d="M([\d.]+) ([\d.]+) c-3\.4/)!.slice(1).map(Number);
    expect(x).toBeGreaterThan(40);
    expect(x).toBeLessThan(160);
    expect(y).toBeGreaterThan(40);
    expect(y).toBeLessThan(220);
    expect(svg).toContain(">Ios<");
  });

  it("cadre et dessine la carte cadrée exactement comme le back-end", () => {
    const cadre = voyageFrame(cyclades, "GR")!;
    expect(miseEnPage.cadreDuVoyage(cyclades.map((l) => ({ ...l, pays: "GR" })), "GR", contours)).toEqual(cadre);
    const request = { cadre, points: [{ ...cyclades[0]!, secondaire: true }, cyclades[2]!] };
    const pays = { GR: detail("GR"), TR: detail("TR") };
    expect(carte.renderCarteCadree(pays, request)).toBe(renderFramedMapSvg(pays, request));
  });
});

describe("cartes de chapitre de l'app", () => {
  const svgDe = (day: Record<string, unknown>) =>
    Buffer.from(String(day["map_svg"]).split(",")[1]!, "base64").toString("utf8");

  it("se cadrent sur les lieux que le carnet pointe dans le pays, avec les petites îles", () => {
    const payload = expandMaps({
      days: [
        { layout_chapter_map: true, map: { regions: ["GR"], points: [cyclades[0], cyclades[1]] } },
        { layout_story_opener: true },
        { layout_chapter_map: true, map: { regions: ["GR"], points: [cyclades[2]] } },
      ],
    });
    const days = payload["days"] as Record<string, unknown>[];
    const premiere = svgDe(days[0]!);
    const seconde = svgDe(days[2]!);
    // Les Cyclades, pas le continent et la Crète en deux contours.
    expect((premiere.match(/<path d=/g) ?? []).length).toBeGreaterThan(15);
    expect(premiere).toContain("<mask");
    // Le même cadre d'un chapitre à l'autre : les îles sont aux mêmes endroits.
    const iles = (svg: string) => svg.split("</g></g>")[0];
    expect(iles(seconde)).toBe(iles(premiere));
    expect(days[1]?.["map_svg"]).toBeUndefined();
  });

  it("pour un séjour dans une seule ville : le pays d'abord, puis la ville et le parcours", () => {
    const point = (label: string, lat: number, lon: number) => ({ label, lat, lon });
    const payload = expandMaps({
      days: [
        { map: { regions: ["FR"], points: [point("Paris", 48.8566, 2.3522)] } },
        { map: { regions: ["FR"], points: [point("Louvre", 48.8606, 2.3376), point("Tuileries", 48.8635, 2.327)] } },
        { map: { regions: ["FR"], points: [point("Montmartre", 48.8867, 2.3431)] } },
      ],
    });
    const [pays, ville, suite] = (payload["days"] as Record<string, unknown>[]).map(svgDe);
    // Le pays : la France entière, une seule épingle, ni trajet ni échelle.
    expect(pays).toContain(">Paris<");
    expect(pays).not.toContain("<polyline");
    expect(pays).not.toMatch(/ km<| m</);
    // La ville : les lieux nommés, le trajet, l'échelle.
    expect(ville).toContain(">Louvre<");
    expect(ville).toContain("<polyline");
    expect(ville).toMatch(/>\d+ (m|km)</);
    // La suite : le parcours précédent en petits points, nommés en petit.
    expect(ville).toContain(">PARIS<");
    expect(suite).toContain(">Montmartre<");
    expect(suite).toMatch(/font-size="5.5"[^>]*>Louvre</);
    expect((suite!.match(/<circle cx="[\d.]+" cy="[\d.]+" r="2.2"/g) ?? []).length).toBe(2);
  });

  it("dessine la carte de ville exactement comme l'atelier", () => {
    const request = {
      cadre: voyageFrame([{ lat: 48.8606, lon: 2.3376 }, { lat: 48.8867, lon: 2.3431 }], "FR", CADRE_MIN_VILLE)!,
      points: [
        { label: "Louvre", lat: 48.8606, lon: 2.3376, secondaire: true },
        { label: "Montmartre", lat: 48.8867, lon: 2.3431 },
      ],
      ville: true,
      titre: "Paris",
    };
    const pays = { FR: detail("FR") };
    expect(carte.renderCarteCadree(pays, request)).toBe(renderFramedMapSvg(pays, request));
  });

  it("refuse toujours une région inconnue", () => {
    expect(() => expandMaps({ days: [{ map: { regions: ["XX"], points: [cyclades[0]] } }] })).toThrow(/inconnue/);
  });
});
