import { describe, expect, it } from "vitest";
import { composedChapters } from "./render.js";

/**
 * **T285** (Hugo, 05/11/2026) : « au partage d'un PDF, pouvoir choisir ce
 * qu'on envoie ».
 *
 * L'index étape → pages ne se calcule pas, il se **dérive** : une page par
 * entrée de `days[]`, `groupSteps` pour les regrouper, `pagesAvantEtapes`
 * pour le décalage de tête.
 */
describe("les chapitres d'un carnet composé", () => {
  /** Une journée ; `intro` en fait le début d'un chapitre. */
  const jour = (titre?: string) => (titre ? { day_intro: { location: titre }, title: titre } : {});

  it("donne à chaque étape son titre et ses pages", () => {
    const payload = {
      intro_text: "Notre aventure commence ici",
      days: [jour("Jour 1 – Bogotá"), {}, jour("Jour 2 – Monserrate"), {}, jour("Jour 3 – Guatapé")],
    };

    // Le colophon (1) + l'introduction (1) = 2 pages avant les étapes.
    expect(composedChapters(payload)).toEqual([
      { title: "Jour 1 – Bogotá", firstPage: 3, pageCount: 2 },
      { title: "Jour 2 – Monserrate", firstPage: 5, pageCount: 2 },
      { title: "Jour 3 – Guatapé", firstPage: 7, pageCount: 1 },
    ]);
  });

  it("compte les pages blanches d'avant", () => {
    const payload = { pages_libres_avant: 1, days: [jour("Une étape")] };
    // Colophon + une page blanche : l'étape commence en 3.
    expect(composedChapters(payload)[0]?.firstPage).toBe(3);
  });

  it("nomme une étape que rien ne nomme : une ligne vide ne se coche pas", () => {
    const payload = { days: [{}, {}] };
    expect(composedChapters(payload)).toEqual([{ title: "Étape 1", firstPage: 2, pageCount: 2 }]);
  });

  it("retombe sur le lieu, puis sur la ville, quand le titre manque", () => {
    const payload = { days: [{ day_intro: { location: "Kyoto" } }, { day_intro: {}, city: "Nara" }] };
    expect(composedChapters(payload).map((c) => c.title)).toEqual(["Kyoto", "Nara"]);
  });

  it("rend une liste vide sans journée : il n'y a rien à choisir", () => {
    expect(composedChapters({ days: [] })).toEqual([]);
    expect(composedChapters({})).toEqual([]);
    expect(composedChapters(null)).toEqual([]);
  });
});
