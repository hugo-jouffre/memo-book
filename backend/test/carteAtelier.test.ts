import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { renderMapSvg } from "../src/services/mapSvg.js";

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
    rings: [number, number][][];
  };
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
});
