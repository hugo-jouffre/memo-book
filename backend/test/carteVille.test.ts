import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { gunzipSync } from "node:zlib";
import { describe, expect, it, vi } from "vitest";
import {
  CADRE_MIN_VILLE,
  cleDeVue,
  expandMaps,
  renderFramedMapSvg,
  requeteOverpass,
  ruesDOverpass,
  voyageFrame,
  vueDeVille,
  vuesDesVilles,
  type Cadre,
} from "../src/services/mapSvg.js";
import { CityStreetSource } from "../src/services/osmCity.js";
import { InMemoryPublicAssetStore } from "../src/services/storage.js";

/**
 * Les cartes de ville prennent leurs rues et leurs cours d'eau dans
 * OpenStreetMap. Aucun appel réseau ici : la réponse d'Overpass pour Paris est
 * enregistrée (`scripts/record-overpass-fixture.ts`).
 */
const reponseParis = JSON.parse(
  gunzipSync(readFileSync(resolve(import.meta.dirname, "fixtures/osm/overpass-paris.json.gz"))).toString("utf8"),
) as { elements: unknown[] };

const point = (label: string, lat: number, lon: number) => ({ label, lat, lon });
const EIFFEL = point("Tour Eiffel", 48.8584, 2.2945);
const LOUVRE = point("Louvre", 48.8606, 2.3376);
/** Un séjour à Paris : le pays d'abord, puis la ville, avec la tour Eiffel et le Louvre. */
const sejourAParis = {
  days: [
    { map: { regions: ["FR"], points: [point("Paris", 48.8566, 2.3522)] } },
    { map: { regions: ["FR"], points: [EIFFEL, LOUVRE] } },
    { map: { regions: ["FR"], points: [point("Montmartre", 48.8867, 2.3431)] } },
  ],
};
const VUE_PARIS: Cadre = [2.28, 48.83, 2.37, 48.91];

const svgDe = (day: unknown) =>
  Buffer.from(String((day as Record<string, unknown>)["map_svg"]).split(",")[1]!, "base64").toString("utf8");
const MENTION = /© les contributeurs d.OpenStreetMap/;

/** Une réponse `fetch` minimale. */
const repondre = (corps: unknown, status = 200) =>
  ({ ok: status < 400, status, json: async () => corps }) as unknown as Response;

describe("rues des cartes de ville", () => {
  it("demande à Overpass la zone que la carte de ville montre, une fois par carnet", () => {
    expect(vuesDesVilles(sejourAParis)).toEqual([VUE_PARIS]);
    expect(cleDeVue(VUE_PARIS)).toBe("48.83_2.28_48.91_2.37");
    const requete = requeteOverpass(VUE_PARIS);
    expect(requete).toContain("[bbox:48.83,2.28,48.91,2.37]");
    expect(requete).toContain("primary|secondary");
    // Une agglomération entière : les grands axes seulement.
    expect(requeteOverpass([2.0, 48.6, 2.7, 49.1])).toContain('"^(motorway|trunk|primary)$"');
  });

  it("garde la Seine et les grands axes de la réponse d'Overpass", () => {
    const rues = ruesDOverpass(reponseParis, VUE_PARIS);
    expect(rues.coursDEau.filter((c) => !c.canal).length).toBeGreaterThan(10);
    expect(new Set(rues.routes.map((r) => r.rang))).toEqual(new Set([0, 1, 2]));
    // Le cache ne garde que des coordonnées au mètre près, dans la vue (et sa marge).
    for (const { trace } of rues.routes) {
      expect(trace.some(([lon, lat]) => lon >= 2.271 && lon <= 2.379 && lat >= 48.822 && lat <= 48.918)).toBe(true);
    }
    expect(ruesDOverpass({ remark: "rien" }, VUE_PARIS)).toEqual({ routes: [], coursDEau: [], plansDEau: [] });
  });

  it("dessine Paris avec la Seine, les grands axes et la mention d'OpenStreetMap", () => {
    const rues = new Map([[cleDeVue(VUE_PARIS), ruesDOverpass(reponseParis, VUE_PARIS)]]);
    const [pays, ville, suite] = (expandMaps(sejourAParis, rues)["days"] as unknown[]).map(svgDe);
    // La carte du pays reste sur Natural Earth : ni rue ni mention.
    expect(pays).not.toMatch(MENTION);
    expect(pays).not.toMatch(/stroke="#fbf8f4" stroke-width="[\d.]+"\/>/);
    // La ville : le ruban de la Seine (couleur papier entre deux rives), les axes, la mention.
    expect(ville).toMatch(/<path d="M[^"]+" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke="#fbf8f4" stroke-width="[\d.]+"\/>/);
    expect(ville).toMatch(/stroke="#19532b" stroke-width="0.9" stroke-opacity="0.38"/);
    expect(ville).toMatch(MENTION);
    expect(suite).toMatch(MENTION);
    // Les rues passent sous le fondu des bords, le trajet et les épingles au-dessus.
    expect(ville!.indexOf("stroke-opacity=\"0.38\"")).toBeLessThan(ville!.indexOf("</g></g>"));
    expect(ville!.indexOf(">Louvre<")).toBeGreaterThan(ville!.indexOf("</g></g>"));
  });

  it("met la tour Eiffel sur la rive gauche de la Seine", () => {
    const rues = new Map([[cleDeVue(VUE_PARIS), ruesDOverpass(reponseParis, VUE_PARIS)]]);
    const ville = svgDe((expandMaps(sejourAParis, rues)["days"] as unknown[])[1]);
    // Les pointes des deux épingles : une coordonnée exacte chacune.
    const pointes = [...ville.matchAll(/<path d="M([\d.]+) ([\d.]+) c-3\.4/g)].map((m) => [Number(m[1]), Number(m[2])]);
    expect(pointes).toHaveLength(2);
    const [eiffel, louvre] = pointes as [[number, number], [number, number]];
    // La projection de la carte, retrouvée à partir de ces deux épingles
    // (Mercator : x suit la longitude, y suit ln tan(π/4 + φ/2)).
    const my = (lat: number) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
    const k = (louvre[0] - eiffel[0]) / (LOUVRE.lon - EIFFEL.lon);
    const projeter = (lat: number, lon: number): [number, number] => [
      eiffel[0] + (lon - EIFFEL.lon) * k,
      eiffel[1] - ((my(lat) - my(EIFFEL.lat)) * k * 180) / Math.PI,
    ];
    expect(projeter(LOUVRE.lat, LOUVRE.lon)[1]).toBeCloseTo(louvre[1], 0);

    // La ligne médiane de la Seine, telle que la carte la dessine.
    const ruban = ville.match(/<path d="([^"]+)" fill="none" stroke-linecap="round" stroke-linejoin="round" stroke="#fbf8f4"/)![1]!;
    const segments: [number, number, number, number][] = [];
    for (const morceau of ruban.split("M").filter(Boolean)) {
      const pts = morceau.split("L").map((p) => p.trim().split(" ").map(Number) as [number, number]);
      for (let i = 1; i < pts.length; i += 1) segments.push([...pts[i - 1]!, ...pts[i]!]);
    }
    const coupe = ([ax, ay]: [number, number], [bx, by]: [number, number]) =>
      segments.some(([cx, cy, dx, dy]) => {
        const cote = (px: number, py: number, qx: number, qy: number, rx: number, ry: number) =>
          Math.sign((qx - px) * (ry - py) - (qy - py) * (rx - px));
        return cote(ax, ay, bx, by, cx, cy) !== cote(ax, ay, bx, by, dx, dy) &&
          cote(cx, cy, dx, dy, ax, ay) !== cote(cx, cy, dx, dy, bx, by);
      });
    // Du Champ-de-Mars à la tour : même rive. Du Trocadéro à la tour : la Seine entre les deux.
    expect(coupe(eiffel, projeter(48.8556, 2.2986))).toBe(false);
    expect(coupe(eiffel, projeter(48.862, 2.2876))).toBe(true);
    // Le Louvre, rive droite : la Seine le sépare de la tour.
    expect(coupe(eiffel, louvre)).toBe(true);
  });

  it("reste sobre, sans mention, quand les rues manquent", () => {
    const [, ville] = (expandMaps(sejourAParis)["days"] as unknown[]).map(svgDe);
    expect(ville).toContain(">Louvre<");
    expect(ville).not.toMatch(MENTION);
    expect(ville).not.toMatch(/stroke="#fbf8f4" stroke-width="[\d.]+"\/>/);
  });
});

describe("Overpass et son cache", () => {
  it("ne demande chaque zone qu'une fois : la suivante sort du bucket public", async () => {
    const store = new InMemoryPublicAssetStore();
    const fetcher = vi.fn(async () => repondre(reponseParis));
    const source = new CityStreetSource({ store, url: "https://overpass.example/api/interpreter", fetcher });

    const premiere = await source.forPayload(sejourAParis);
    expect(fetcher).toHaveBeenCalledTimes(1);
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, { body: URLSearchParams }];
    expect(url).toBe("https://overpass.example/api/interpreter");
    expect(init.body.toString()).toContain(encodeURIComponent("[bbox:48.83,2.28,48.91,2.37]"));
    expect([...store.objects.keys()]).toEqual(["osm/v1/48.83_2.28_48.91_2.37.json"]);

    const seconde = await new CityStreetSource({ store, url: "https://ailleurs.example", fetcher }).forPayload(sejourAParis);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(seconde).toEqual(premiere);
    expect(svgDe((expandMaps(sejourAParis, seconde)["days"] as unknown[])[1])).toMatch(MENTION);
  });

  it("retombe sur la carte sobre si Overpass échoue, dépasse le délai ou répond à moitié", async () => {
    const warn = vi.fn();
    const essais = [
      async () => repondre({ elements: [] }, 504),
      async () => {
        throw new TypeError("fetch failed");
      },
      // Délai dépassé : le signal coupe une réponse qui ne vient jamais.
      (_url: string, init?: RequestInit) =>
        new Promise<Response>((_, rejeter) => init?.signal?.addEventListener("abort", () => rejeter(new Error(String(init.signal!.reason))))),
      async () => repondre({ remark: "runtime error: Query timed out in \"query\"", elements: reponseParis.elements.slice(0, 5) }),
    ];
    for (const essai of essais) {
      const store = new InMemoryPublicAssetStore();
      const source = new CityStreetSource({ store, url: "https://overpass.example", fetcher: essai as typeof fetch, timeoutMs: 20, warn });
      const rues = await source.forPayload(sejourAParis);
      expect(rues.size).toBe(0);
      // Rien en cache : la prochaine génération réessaiera.
      expect(store.objects.size).toBe(0);
      const ville = svgDe((expandMaps(sejourAParis, rues)["days"] as unknown[])[1]);
      expect(ville).toContain(">Louvre<");
      expect(ville).not.toMatch(MENTION);
    }
    expect(warn).toHaveBeenCalledTimes(essais.length);
  });

  it("ne demande rien pour un voyage sans carte de ville", async () => {
    const fetcher = vi.fn();
    const source = new CityStreetSource({ store: new InMemoryPublicAssetStore(), url: "https://x.example", fetcher });
    const tour = { days: [{ map: { regions: ["GR"], points: [point("Athènes", 37.98, 23.73), point("Paros", 37.08, 25.15)] } }] };
    expect((await source.forPayload(tour)).size).toBe(0);
    expect(fetcher).not.toHaveBeenCalled();
  });
});

describe("rues des cartes de ville, côté atelier", () => {
  const require = createRequire(import.meta.url);
  const carte = require("../../MemoBook Generator/public/carte.js") as {
    renderCarteCadree: (detail: unknown, request: unknown) => string;
    vueDeVille: (cadre: Cadre, w?: number, h?: number) => Cadre;
    cleDeVue: (vue: Cadre) => string;
    requeteOverpass: (vue: Cadre) => string;
    ruesDOverpass: (reponse: unknown, vue: Cadre) => unknown;
  };

  it("demande, lit et dessine les rues exactement comme le back-end", () => {
    const cadre = voyageFrame([EIFFEL, LOUVRE, point("Paris", 48.8566, 2.3522)], "FR", CADRE_MIN_VILLE)!;
    expect(carte.vueDeVille(cadre)).toEqual(vueDeVille(cadre));
    expect(carte.vueDeVille(cadre, 180, 240)).toEqual(vueDeVille(cadre, 180, 240));
    expect(carte.cleDeVue(VUE_PARIS)).toBe(cleDeVue(VUE_PARIS));
    expect(carte.requeteOverpass(VUE_PARIS)).toBe(requeteOverpass(VUE_PARIS));
    const rues = ruesDOverpass(reponseParis, VUE_PARIS);
    expect(carte.ruesDOverpass(reponseParis, VUE_PARIS)).toEqual(rues);

    const FR = JSON.parse(readFileSync(resolve(import.meta.dirname, "../../assets/maps/detail/FR.json"), "utf8")) as never;
    const request = {
      cadre,
      points: [{ ...EIFFEL, secondaire: true }, LOUVRE],
      ville: true,
      titre: "Paris",
      rues,
    };
    const svg = renderFramedMapSvg({ FR }, request);
    expect(svg).toMatch(MENTION);
    expect(carte.renderCarteCadree({ FR }, request)).toBe(svg);
  });
});
