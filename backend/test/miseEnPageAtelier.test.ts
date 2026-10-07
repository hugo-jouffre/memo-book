import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * La mise en page de l'atelier (`MemoBook Generator/public/mise-en-page.js`) :
 * l'équivalent, en code, des règles que l'Agent Mise en page de l'app lit dans
 * LAYOUT_KB. Ces tests en gardent les règles qui se vérifient sans navigateur.
 */
const require = createRequire(import.meta.url);
type Jour = Record<string, unknown> & { photos: (string | { url: string })[]; body_html: string };
const M = require("../../MemoBook Generator/public/mise-en-page.js") as {
  composerJours: (etapes: unknown[], options?: Record<string, unknown>) => Jour[];
  composition: (plan: unknown) => string;
};
const carte = require("../../MemoBook Generator/public/carte.js") as {
  renderMapDataUri: (contours: unknown, requete: unknown) => string;
};
const contours = JSON.parse(
  readFileSync(resolve(import.meta.dirname, "../../assets/maps/countries.json"), "utf8"),
) as Record<string, unknown>;

const phrase = (sujet: string) =>
  `Le matin nous sommes allés voir ${sujet} et nous y sommes restés longtemps, ravis de la journée. `;
const paragrapheDe = (sujet: string, n = 3) => Array.from({ length: n }, () => phrase(sujet)).join("");

const photo = (id: string, format = 0.75) => ({ id, src: `https://exemple.test/${id}.jpg`, format, groupe: false });
const url = (p: string | { url: string }) => (typeof p === "string" ? p : p.url);

function etape(recit: string, photos: ReturnType<typeof photo>[], analyse: unknown = null, lieu = "Paros") {
  return {
    titre: `Étape ${lieu}`,
    lieu,
    destination: "Grèce",
    numero: "01",
    lieuComplet: `${lieu}, Grèce`,
    dateLongue: "22 août 2026",
    recit,
    photos,
    analyse,
  };
}

const texteDes = (jours: Jour[]) => jours.map((j) => j.body_html.replace(/<\/p><p>/g, " ").replace(/<[^>]+>/g, "")).join(" ");
const normal = (t: string) => t.replace(/\s+/g, " ").trim();

describe("mise en page de l'atelier", () => {
  it("met chaque photo sur la page du passage qu'elle illustre", () => {
    // Trois passages longs : la plage, puis le musée, puis le restaurant — trois pages.
    const recit = [paragrapheDe("la plage"), paragrapheDe("le musée"), paragrapheDe("le restaurant"), paragrapheDe("le port")].join(" ");
    const photos = [photo("resto"), photo("plage"), photo("musee")];
    const analyse = {
      photos: [
        { id: "resto", paragraphe: null, scene: "terrasse du port" },
        { id: "plage", paragraphe: 0, scene: "plage" },
        { id: "musee", paragraphe: 1, scene: "musée" },
      ],
    };
    // Sans paragraphe, la photo du restaurant suit son rang ; on la rattache au restaurant.
    analyse.photos[0]!.paragraphe = 2;
    const jours = M.composerJours([etape(recit, photos, analyse)]);
    const pageDe = (id: string) => jours.findIndex((j) => j.photos.some((p) => url(p).includes(`/${id}.`)));
    const texteDeLaPage = (i: number) => jours[i]!.body_html;
    expect(texteDeLaPage(pageDe("plage"))).toContain("la plage");
    expect(texteDeLaPage(pageDe("musee"))).toContain("le musée");
    expect(texteDeLaPage(pageDe("resto"))).toContain("le restaurant");
  });

  it("garde ensemble les photos prises au même endroit", () => {
    const recit = [paragrapheDe("la plage"), paragrapheDe("le musée"), paragrapheDe("le port")].join(" ");
    const photos = [photo("a"), photo("b"), photo("c")];
    const analyse = {
      photos: [
        { id: "a", paragraphe: 0, scene: "plage de sable" },
        { id: "b", paragraphe: 2, scene: "Plage de sable" },
        { id: "c", paragraphe: 1, scene: "musée" },
      ],
    };
    const jours = M.composerJours([etape(recit, photos, analyse)]);
    const pageDe = (id: string) => jours.findIndex((j) => j.photos.some((p) => url(p).includes(`/${id}.`)));
    expect(pageDe("a")).toBe(pageDe("b"));
  });

  it("ne perd aucun mot du récit", () => {
    const recit = Array.from({ length: 9 }, (_, i) => paragrapheDe(`le lieu ${i}`)).join(" ");
    const jours = M.composerJours([etape(recit, [photo("a"), photo("b"), photo("c"), photo("d")])]);
    expect(normal(texteDes(jours))).toBe(normal(recit));
  });

  it("ouvre un chapitre sur une carte à l'arrivée dans un nouveau lieu", () => {
    const situe = (nom: string, lat: number, lon: number) => ({ lieu: { nom, pays: "GR", lat, lon }, photos: [] });
    const options = {
      contours,
      dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r),
    };
    const jours = M.composerJours(
      [
        etape(paragrapheDe("Paros", 2), [], situe("Paros", 37.08, 25.15), "Paros"),
        etape(paragrapheDe("Paros encore", 2), [], situe("Paros", 37.08, 25.15), "Paros"),
        etape(paragrapheDe("Naxos", 2), [], situe("Naxos", 37.1, 25.38), "Naxos"),
      ],
      options,
    );
    expect(jours.map((j) => Boolean(j["layout_chapter_map"]))).toEqual([true, false, true]);
    expect(String(jours[2]!["map_svg"])).toMatch(/^data:image\/svg\+xml;base64,/);
  });

  it("n'ouvre pas de chapitre sans lieu situé avec certitude", () => {
    const jours = M.composerJours([etape(paragrapheDe("quelque part", 2), [], { lieu: null, photos: [] })], {
      contours,
      dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r),
    });
    expect(jours[0]!["layout_chapter_map"]).toBe(false);
  });

  it("ne laisse pas deux pages en vis-à-vis avec la même composition quand une alternative existe", () => {
    // Deux pages d'une même étape, deux photos chacune : bande de deux photos des deux côtés.
    const recit = Array.from({ length: 4 }, (_, i) => paragrapheDe(`le lieu ${i}`, 2)).join(" ");
    const photos = ["a", "b", "c", "d"].map((id) => photo(id));
    const sans = M.composerJours([etape(recit, photos)], { pagesAvant: 1 });
    const comp = (j: Jour) =>
      j["layout_hero_top"] ? "hero" : j.photos.length === 0 ? "texte" : j.photos.length === 1 ? "texte+photo" : `bande${j.photos.length}`;
    // Page 0 à gauche (pagesAvant = 1 : le colophon est la page 1), page 1 à droite.
    expect(comp(sans[0]!)).not.toBe(comp(sans[1]!));
    expect(sans.reduce((n, j) => n + j.photos.length, 0)).toBe(4);
  });

  describe("fun facts", () => {
    const encart = (texte: string, pertinence: number, registre = "histoire") => ({
      photos: [],
      funFact: { texte, titre: "Fun fact", registre, paragraphe: 0, pertinence },
    });
    // Une page par étape : un paragraphe court, sans photo.
    const etapes = (notes: [number, string?][]) =>
      notes.map(([note, registre], i) => etape(paragrapheDe(`le lieu ${i}`, 1), [], encart(`Fait n° ${i}.`, note, registre), `Lieu ${i}`));
    const encarts = (jours: Jour[]) => jours.map((j) => (j["fun_facts"] as string[])[0] ?? null);

    it("n'en met aucun quand le réglage du carnet est coupé", () => {
      expect(encarts(M.composerJours(etapes([[9], [9]]), { funFacts: false }))).toEqual([null, null]);
    });

    it("n'imprime ni un encart sous le seuil de pertinence, ni un encart trop long", () => {
      const jours = M.composerJours(
        [
          etape(paragrapheDe("la plage", 1), [], encart("Un fait sans intérêt.", 4)),
          etape(paragrapheDe("le port", 1), [], encart("x".repeat(141), 9)),
        ],
        { funFacts: true },
      );
      expect(encarts(jours)).toEqual([null, null]);
    });

    it("en met un toutes les trois pages au plus, les mieux notés d'abord", () => {
      const jours = M.composerJours(
        etapes([[7, "histoire"], [9, "vecu"], [7, "cuisine"], [7, "record"], [8, "usage-local"]]),
        { funFacts: true },
      );
      // {1, 4} (17) l'emporte sur {0, 3} (14).
      expect(encarts(jours)).toEqual([null, "Fait n° 1.", null, null, "Fait n° 4."]);
      expect(jours[1]?.["fun_facts_title"]).toBe("Fun fact");
      expect(jours[1]?.["ai_note"]).toBe("Fun fact rédigé par IA");
    });

    it("ne laisse pas deux encarts du même registre à la suite", () => {
      const jours = M.composerJours(etapes([[8, "histoire"], [7], [7], [9, "histoire"]]), { funFacts: true });
      expect(encarts(jours)).toEqual([null, null, null, "Fait n° 3."]);
    });

    it("pose l'encart à côté de la photo flottante plutôt que sous une grande photo en tête", () => {
      const jours = M.composerJours([etape(paragrapheDe("la plage", 1), [photo("p", 1.4)], encart("Fait.", 9))], {
        funFacts: true,
      });
      expect(jours[0]?.["layout_hero_top"]).toBe(false);
      expect(jours[0]?.["layout_story_opener"]).toBe(true);
      expect(encarts(jours)).toEqual(["Fait."]);
    });
  });
});
