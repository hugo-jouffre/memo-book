import { describe, expect, it } from "vitest";
import { renderTemplateToHtml } from "../src/services/bookPdf.js";

/**
 * Les pages du gabarit et leur côté dans le livre relié (décisions du
 * 12/10/2026) : marges miroir, corps ajusté, pages libres de fin de carnet.
 */
const photo = "https://exemple.test/a.jpg";
const jour = (n: string) => ({
  title: `Jour ${n}`,
  day_intro: { day_number: n },
  body_html: "<p>Récit.</p>",
  photos: [photo],
  layout_story_opener: true,
});

/** Les classes des pages intérieures, dans l'ordre, sans la couverture. */
const pages = (payload: Record<string, unknown>) =>
  [...renderTemplateToHtml({ payload: { sans_couvertures: true, ...payload }, profile: "print" }).matchAll(/<div class="(page [^"]*)"/g)].map(
    (m) => m[1] as string,
  );
const cote = (classes: string) => (classes.includes("page--gauche") ? "G" : classes.includes("page--droite") ? "D" : "?");

describe("gabarit — pages du livre relié", () => {
  it("pose des marges miroir : le colophon à droite, puis gauche et droite en alternance", () => {
    const sansIntro = pages({ book_title: "Carnet", pages_libres_avant: 0, days: [jour("01"), jour("02"), jour("03")] });
    expect(sansIntro.map(cote).join("")).toBe("DGDG");
    // Une introduction et une page libre : la première étape reste à gauche.
    const avecIntro = pages({
      book_title: "Carnet",
      intro_text: "<p>Intro.</p>",
      pages_libres_avant: 1,
      days: [jour("01"), jour("02")],
    });
    expect(avecIntro.map(cote).join("")).toBe("DGDGD");
    expect(avecIntro[3]).toContain("page--day");
    expect(avecIntro[3]).toContain("page--gauche");
  });

  it("ajoute les pages libres de fin après la dernière étape, du bon côté", () => {
    const liste = pages({ book_title: "Carnet", days: [jour("01"), jour("02")], pages_libres: 3 });
    const libres = liste.slice(-3);
    expect(libres.every((c) => c.includes("page--libre"))).toBe(true);
    // Colophon (D), deux étapes (G, D), puis G, D, G.
    expect(libres.map(cote).join("")).toBe("GDG");
  });

  it("donne au récit le corps demandé par `taille_texte`", () => {
    const liste = pages({
      book_title: "Carnet",
      days: [
        { ...jour("01"), taille_texte: "serre" },
        { ...jour("02"), taille_texte: "ample" },
        { ...jour("03"), taille_texte: "énorme" },
      ],
    });
    expect(liste[1]).toContain("page--serre");
    expect(liste[2]).toContain("page--ample");
    expect(liste[3]).not.toContain("page--énorme");
  });
});
