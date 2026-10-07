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
});
