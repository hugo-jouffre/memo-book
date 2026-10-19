import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";
import { composerCarnet, stickersDuCarnet } from "../src/services/bookComposer.js";
import { PAGE_TARGET_TOLERANCE } from "../src/services/pageTarget.js";
import { photosRequired } from "../src/services/photoRatio.js";

/**
 * L'app compose son carnet avec le composeur de l'atelier (Hugo, 13/10/2026) :
 * le même récit et les mêmes photos donnent les mêmes pages dans les deux PDF.
 */
const require = createRequire(import.meta.url);
const M = require("../../MemoBook Generator/public/mise-en-page.js") as {
  composerJours: (etapes: unknown[], options: Record<string, unknown>) => Record<string, unknown>[];
  paragraphesEnHtml: (paragraphes: string[]) => string;
  TOLERANCE_PAGES_CIBLE: number;
};

const phrase = (sujet: string) => `Le matin nous sommes allés voir ${sujet} et nous y sommes restés longtemps, ravis de la plage. `;
const paragraphes = [phrase("le port").repeat(2).trim(), phrase("le marché").repeat(2).trim(), phrase("la crique").repeat(2).trim()];
const photos = Array.from({ length: 7 }, (_, i) => `https://exemple.test/${i}.jpg`);

const payload = {
  book_title: "Carnet",
  days: [
    {
      title: "Paros",
      city: "Paros",
      country: "Grèce",
      day_intro: { day_number: "01", location: "Paros, Grèce", date: "22 août 2026" },
      body_html: M.paragraphesEnHtml(paragraphes),
      photos,
      layout_collage: true,
    },
  ],
};

/** Ce qui fait une page : son layout, ses photos, son tracé, ses stickers. */
const pages = (days: Record<string, unknown>[]) =>
  days.map((jour) => ({
    layout: Object.keys(jour).find((cle) => cle.startsWith("layout_") && jour[cle] === true),
    photos: ((jour["photos"] ?? []) as ({ url: string } | string)[]).map((p) => (typeof p === "string" ? p : p.url)),
    trace: jour["trace"],
    stickers: ((jour["stickers"] ?? []) as { url: string }[]).map((s) => s.url),
    texte: jour["body_html"],
  }));

describe("composition du carnet de l'app", () => {
  for (const ratio of [25, 50, 75] as const) {
    it(`donne les mêmes pages que l'atelier, au palier ${ratio} %`, () => {
      const app = composerCarnet(payload, { ratio, funFacts: false, decorations: 2 });
      const atelier = M.composerJours(
        [
          {
            titre: "Paros",
            lieu: "Paros",
            destination: "Grèce",
            numero: "01",
            lieuComplet: "Paros, Grèce",
            dateLongue: "22 août 2026",
            paragraphes,
            recit: paragraphes.join(" "),
            photos: photos.map((src, i) => ({ id: `0-${i}`, src, groupe: false })),
            analyse: null,
          },
        ],
        {
          pagesAvant: 1,
          ratio,
          stickers: stickersDuCarnet(),
          decorations: 2,
          budgetPhotos: () => photosRequired({ body_html: payload.days[0]!.body_html }, ratio, "a5", { decorations: true }).photos,
        },
      );
      expect(pages(app)).toEqual(pages(atelier));
    });
  }

  it("garde le bandeau de l'agent sur la page qui ouvre l'étape", () => {
    const avecMeteo = { ...payload, days: [{ ...payload.days[0]!, day_intro: { ...payload.days[0]!.day_intro, weather: "sun" }, tag: "Plage" }] };
    const [premiere] = composerCarnet(avecMeteo, { ratio: 50, funFacts: false, decorations: 2 });
    expect(premiere!["day_intro"]).toMatchObject({ weather: "sun" });
    expect(premiere!["tag"]).toBe("Plage");
  });

  it("ouvre le chapitre sur la carte que l'agent a choisie", () => {
    const map = { regions: ["GR"], points: [{ label: "Paros", lat: 37.08, lon: 25.15 }] };
    const court = { ...payload.days[0]!, body_html: M.paragraphesEnHtml([paragraphes[0]!]), map, layout_chapter_map: true };
    const [premiere] = composerCarnet({ ...payload, days: [court] }, { ratio: 50, funFacts: false, decorations: 2 });
    expect(premiere!["layout_chapter_map"]).toBe(true);
    expect(premiere!["map"]).toEqual(map);
  });

  it("pose sur les pages de récit les photos du ratio, et le surplus sur des pages de photos (18/10/2026)", () => {
    for (const ratio of [25, 50, 75] as const) {
      const demandees = photosRequired({ body_html: payload.days[0]!.body_html }, ratio, "a5", { decorations: true }).photos;
      const composees = pages(composerCarnet(payload, { ratio, funFacts: false, decorations: 2 }));
      const surRecit = composees.filter((p) => p.layout !== "layout_photo_page").flatMap((p) => p.photos);
      const toutes = composees.flatMap((p) => p.photos);
      expect(surRecit.length, `ratio ${ratio}`).toBeLessThanOrEqual(demandees);
      // Aucune photo envoyée n'est perdue : les sept tiennent dans les six pages.
      expect(toutes.length, `ratio ${ratio}`).toBe(photos.length);
    }
  });

  it("à 0 %, ni photo du ratio ni surplus", () => {
    const composees = pages(composerCarnet(payload, { ratio: 0, funFacts: false, decorations: 2 }));
    expect(composees.flatMap((p) => p.photos)).toEqual([]);
  });

  describe("quiz", () => {
    const quiz = { question: "Qui a renversé le café ?", choices: ["Clara", "Hugo", "Le serveur"], answer: "Hugo" };
    // Une étape courte, sans photo : sa première page peut porter le quiz.
    const sansPhoto = { ...payload, days: [{ ...payload.days[0]!, photos: [], layout_collage: false, layout_story_opener: true, quiz }] };

    it("pose le quiz rédigé sur une page sans photo, au réglage allumé", () => {
      const days = composerCarnet(sansPhoto, { ratio: 50, funFacts: false, quiz: true, decorations: 2 });
      const hotes = days.filter((j) => j["quiz"]);
      expect(hotes).toHaveLength(1);
      expect(hotes[0]!["quiz"]).toEqual(quiz);
      expect(hotes[0]!["photos"]).toEqual([]);
    });

    it("n'en pose aucun au réglage coupé", () => {
      const days = composerCarnet(sansPhoto, { ratio: 50, funFacts: false, quiz: false, decorations: 2 });
      expect(days.some((j) => j["quiz"])).toBe(false);
    });

    it("ne le recopie jamais sur une page qui a des photos", () => {
      const avecPhotos = { ...payload, days: [{ ...payload.days[0]!, quiz }] };
      const days = composerCarnet(avecPhotos, { ratio: 50, funFacts: false, quiz: true, decorations: 2 });
      for (const jour of days.filter((j) => j["quiz"])) expect(jour["photos"]).toEqual([]);
    });
  });

  describe("nombre de pages cible", () => {
    // Dix étapes au récit de six paragraphes. Chacune reçoit **exactement** les
    // photos que le ratio demande (`photosDuRatio`) : la cible se lit alors sur
    // ce seul budget. Le surplus a son propre test, plus bas.
    const long = [...paragraphes, phrase("le phare").repeat(2).trim(), phrase("la chapelle").repeat(2).trim(), phrase("le moulin").repeat(2).trim()];
    const demandeesAu = (ratio: number) =>
      photosRequired({ body_html: M.paragraphesEnHtml(long) }, ratio, "a5", { decorations: true }).photos;
    const voyageAu = (ratio: number, parEtape = Math.min(demandeesAu(ratio), 12)) => ({
      ...payload,
      pages_libres: 3,
      days: Array.from({ length: 10 }, (_, e) => ({
        ...payload.days[0]!,
        title: `Étape ${e}`,
        city: `Lieu ${e}`,
        day_intro: { day_number: String(e + 1), location: `Lieu ${e}, Grèce`, date: "22 août 2026" },
        body_html: M.paragraphesEnHtml(long),
        photos: Array.from({ length: parEtape }, (_, i) => `https://exemple.test/${e}-${i}.jpg`),
      })),
    });
    const voyage = voyageAu(50);
    // Le colophon. Les pages libres de fin ne comptent plus, même demandées par
    // un ancien payload : le gabarit ne les imprime plus (15/10/2026).
    const fixes = 1;
    const photosPosees = (days: Record<string, unknown>[]) => pages(days).flatMap((p) => p.photos).sort();
    const recit = (days: Record<string, unknown>[]) => pages(days).map((p) => p.texte).join("");

    it("tolère le même écart que la règle produit (`PAGE_TARGET_TOLERANCE`)", () => {
      expect(M.TOLERANCE_PAGES_CIBLE).toBe(PAGE_TARGET_TOLERANCE);
    });

    // À 100 %, les planches font déjà 44 pages : la cible est plus haute.
    for (const [ratio, cible] of [[50, 40], [75, 40], [100, 60]] as const) {
      it(`fait tenir un carnet à cible ${cible} entre ${cible - 5} et ${cible + 5} pages, au palier ${ratio} %`, () => {
        const voyage = voyageAu(ratio);
        const sans = composerCarnet(voyage, { ratio, funFacts: false, decorations: 2 });
        expect(sans.length + fixes).toBeLessThan(cible - 5);
        const days = composerCarnet(voyage, { ratio, funFacts: false, decorations: 2, pagesCible: cible });
        expect(days.length + fixes).toBeGreaterThanOrEqual(cible - 5);
        expect(days.length + fixes).toBeLessThanOrEqual(cible + 5);
        // Exactement les photos que `photosRequired` a dites : le ratio tient.
        expect(photosPosees(days)).toEqual(photosPosees(sans));
        for (let e = 0; e < 10; e += 1) {
          expect(photosPosees(days).filter((url) => url.includes(`/${e}-`)).length).toBe(Math.min(demandeesAu(ratio), 12));
        }
        expect(recit(days)).toBe(recit(sans));
      });
    }

    it("ne force rien quand le ratio ne laisse pas assez de photos, et le dit", () => {
      const voyage = voyageAu(25);
      const sans = composerCarnet(voyage, { ratio: 25, funFacts: false, decorations: 2 });
      const journal: string[] = [];
      const days = composerCarnet(voyage, { ratio: 25, funFacts: false, decorations: 2, pagesCible: 40, journal: (t) => journal.push(t) });
      expect(pages(days)).toEqual(pages(sans));
      expect(journal.filter((t) => t.startsWith("pages cible"))).toEqual([expect.stringMatching(/hors d'atteinte.*pas assez de photos/)]);
    });

    it("donne les mêmes pages que l'atelier", () => {
      const app = composerCarnet(voyage, { ratio: 50, funFacts: false, decorations: 2, pagesCible: 40 });
      const atelier = M.composerJours(
        voyage.days.map((jour, e) => ({
          titre: jour.title,
          lieu: jour.city,
          destination: "Grèce",
          numero: jour.day_intro.day_number,
          lieuComplet: jour.day_intro.location,
          dateLongue: jour.day_intro.date,
          paragraphes: long,
          recit: long.join(" "),
          photos: jour.photos.map((src, i) => ({ id: `${e}-${i}`, src, groupe: false })),
          analyse: null,
        })),
        {
          pagesAvant: 1,
          pagesFixes: fixes,
          pagesCible: 40,
          ratio: 50,
          stickers: stickersDuCarnet(),
          decorations: 2,
          budgetPhotos: () => photosRequired({ body_html: M.paragraphesEnHtml(long) }, 50, "a5", { decorations: true }).photos,
        },
      );
      expect(pages(app)).toEqual(pages(atelier));
    });

    it("les photos envoyées au-delà du ratio — celles que la cible a demandées — portent le carnet à 25 %", () => {
      // À 25 %, le ratio seul laisse le carnet sous sa cible (test d'avant). Le
      // chat a demandé trois photos de plus par page de photos manquante
      // (`photosForTarget`) : avec elles, la cible tient.
      const avecSurplus = voyageAu(25, demandeesAu(25) + 6);
      const days = composerCarnet(avecSurplus, { ratio: 25, funFacts: false, decorations: 2, pagesCible: 40 });
      expect(days.length + fixes).toBeGreaterThanOrEqual(35);
      expect(days.length + fixes).toBeLessThanOrEqual(45);
      // Toutes les photos sont imprimées, et le récit n'a pas bougé.
      expect(photosPosees(days).length).toBe(10 * (demandeesAu(25) + 6));
      expect(recit(days)).toBe(recit(composerCarnet(voyageAu(25), { ratio: 25, funFacts: false, decorations: 2 })));
    });
  });
});
