import { existsSync } from "node:fs";
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

/** Sans navigateur installé, la mesure se saute, comme `pdfVector.test.ts`. */
async function chromiumDisponible(): Promise<boolean> {
  try {
    const { chromium } = await import("playwright-core");
    return existsSync(chromium.executablePath());
  } catch {
    return false;
  }
}
const avecChromium = await chromiumDisponible();

describe("gabarit — fond perdu de la version imprimeur", () => {
  const payload = (fond: boolean) => ({
    book_title: "Carnet",
    sans_couvertures: true,
    pages_libres_avant: 0,
    days: [
      jour("01"),
      { title: "", body_html: "", photos: [photo], layout_photo_page: true, pleine_page: true },
    ],
    ...(fond ? { fond_perdu: true } : {}),
  });

  it("n'agrandit la feuille que sur demande", () => {
    const avec = renderTemplateToHtml({ payload: payload(true), profile: "print" });
    expect(avec).toMatch(/<body class="[^"]*\bfond-perdu\b/);
    expect(avec).toContain("@page { size: 437.01pt 612.01pt");
    const sans = renderTemplateToHtml({ payload: payload(false), profile: "print" });
    expect(sans).not.toMatch(/<body class="[^"]*\bfond-perdu\b/);
    expect(sans).not.toContain("437.01pt");
  });

  it.runIf(avecChromium)("mesure sous Chromium : 3 mm autour de la page finie, colonne inchangée, pleine page bord à bord", async () => {
    const { chromium } = await import("playwright-core");
    const browser = await chromium.launch();
    try {
      const mesurer = async (fond: boolean) => {
        const page = await browser.newPage();
        await page.emulateMedia({ media: "print" });
        await page.setContent(renderTemplateToHtml({ payload: payload(fond), profile: "print" }));
        const mesure = await page.evaluate(`Array.from(document.querySelectorAll(".page--day")).map(function (p) {
          var r = p.getBoundingClientRect();
          var note = p.querySelector(".mb-note");
          var pleine = p.querySelector(".mb-pleine-page");
          return {
            largeur: r.width * 0.75,
            hauteur: r.height * 0.75,
            colonne: note ? [(note.getBoundingClientRect().left - r.left) * 0.75, note.getBoundingClientRect().width * 0.75] : null,
            pleine: pleine ? [pleine.getBoundingClientRect().width * 0.75, pleine.getBoundingClientRect().height * 0.75] : null
          };
        })`);
        await page.close();
        return mesure as { largeur: number; hauteur: number; colonne: [number, number] | null; pleine: [number, number] | null }[];
      };
      const [apercu, imprimeur] = [await mesurer(false), await mesurer(true)];
      const bleed = 8.504;
      // La page grandit de 2 × 3 mm, moins le jeu de 1,5 pt qui la fait tenir dans sa feuille.
      expect(imprimeur[0]!.largeur).toBeCloseTo(420 + 2 * bleed - 1.5, 0);
      expect(imprimeur[0]!.hauteur).toBeCloseTo(595 + 2 * bleed - 1.5, 0);
      // La colonne garde sa largeur et se décale de 3 mm.
      expect(imprimeur[0]!.colonne![1]).toBeCloseTo(apercu[0]!.colonne![1], 1);
      expect(imprimeur[0]!.colonne![0]).toBeCloseTo(apercu[0]!.colonne![0] + bleed, 0);
      // La photo en pleine page couvre toute la feuille, fond perdu compris.
      expect(imprimeur[1]!.pleine![0]).toBeCloseTo(imprimeur[1]!.largeur, 0);
      expect(imprimeur[1]!.pleine![1]).toBeCloseTo(imprimeur[1]!.hauteur, 0);
    } finally {
      await browser.close();
    }
  }, 60_000);
});

describe("gabarit — retouches du 13/10/2026", () => {
  /** Le corps seul : la feuille de style, en tête, nomme toutes les classes. */
  const html = (days: Record<string, unknown>[]) => {
    const rendu = renderTemplateToHtml({ payload: { book_title: "Carnet", sans_couvertures: true, pages_libres_avant: 0, days }, profile: "print" });
    return rendu.slice(rendu.indexOf("<body"));
  };
  const photos = (n: number) => Array.from({ length: n }, (_, i) => `https://exemple.test/${i}.jpg`);
  const planche = (extra: Record<string, unknown>) => ({ title: "", body_html: "", layout_photo_page: true, ...extra });

  it("entoure chaque photo d'un contour dessiné, sauf la pleine page", () => {
    const rendu = html([jour("01"), planche({ photos: photos(3) })]);
    const cadres = rendu.match(/class="mb-photo__cadre mb-photo__cadre--[abc]"/g) ?? [];
    const photosRendues = rendu.match(/<div class="mb-photo mb-photo--/g) ?? [];
    expect(cadres.length).toBe(photosRendues.length);
    expect(cadres.length).toBe(4);
    const pleine = html([planche({ photos: photos(1), pleine_page: true })]);
    expect(pleine).toContain("mb-photo--pleine-page");
    expect(pleine).not.toContain('class="mb-photo__cadre');
  });

  it("donne au contour d'une photo réduite la taille du tirage", () => {
    const rendu = html([planche({ photos: [{ url: photos(1)[0], fit: "contain", tirage: [100, 62] }, ...photos(2)] })]);
    expect(rendu).toMatch(/<span class="mb-photo__tirage" style="width: 100%; height: 62%"><img[^>]*\/><svg class="mb-photo__cadre/);
  });

  it("rend la planche de cinq photos en colonnes quand on la demande", () => {
    const colonnes = html([planche({ photos: photos(5), planche_colonnes: true })]);
    expect(colonnes).toContain("mb-photowall--colonnes");
    expect(colonnes.match(/mb-photo--colonne-[ab]/g)).toHaveLength(5);
    const rangees = html([planche({ photos: photos(5) })]);
    expect(rangees).not.toContain("mb-photowall--colonnes");
  });

  it("pose une photo seule au-dessus de la carte de chapitre, deux en bande", () => {
    const chapitre = (n: number) =>
      html([{ ...jour("01"), layout_story_opener: false, layout_chapter_map: true, map_svg: "data:image/svg+xml;base64,", photos: photos(n) }]);
    const une = chapitre(1);
    expect(une).toMatch(/class="mb-chapter__aside">\s*<div class="mb-photo mb-photo--chapitre/);
    expect(une).not.toContain('class="mb-gallery"');
    const deux = chapitre(2);
    expect(deux).not.toContain("mb-photo--chapitre");
    expect(deux).toContain('class="mb-gallery"');
  });
});

describe("gabarit — fun facts sur les photos (13/10/2026)", () => {
  const corps = (days: Record<string, unknown>[]) => {
    const rendu = renderTemplateToHtml({ payload: { book_title: "Carnet", sans_couvertures: true, pages_libres_avant: 0, days }, profile: "print" });
    return rendu.slice(rendu.indexOf("<body"));
  };
  const photos = (n: number) => Array.from({ length: n }, (_, i) => `https://exemple.test/${i}.jpg`);
  const fait = { fun_facts: ["Un fait sûr, tiré du récit."], fun_facts_title: "Infos" };

  it("pose le post-it sur une planche, une page d'album et une planche en colonnes", () => {
    expect(corps([{ title: "", body_html: "", layout_photo_page: true, photos: photos(4), ...fait }])).toContain("mb-card--postit-planche");
    expect(corps([{ title: "", body_html: "", layout_photo_page: true, photos: photos(2), ...fait }])).toContain("mb-card--postit-album");
    expect(
      corps([{ title: "", body_html: "", layout_photo_page: true, planche_colonnes: true, photos: photos(5), ...fait }]),
    ).toContain("mb-card--postit-planche");
    // Jamais sur la pleine page.
    expect(corps([{ title: "", body_html: "", layout_photo_page: true, pleine_page: true, photos: photos(1), ...fait }])).not.toContain(
      "mb-card--postit",
    );
  });

  it("pose le post-it sur la bande d'une page de récit, sans rétrécir la colonne", () => {
    const bande = corps([{ ...jour("01"), layout_story_opener: false, layout_split_left: true, photos: photos(2), ...fait, postit_bande: true }]);
    expect(bande).toContain("mb-card--postit-bande");
    expect(bande).not.toContain("mb-split__aside");
    // Sans `postit_bande`, la carte reste dans sa colonne, comme avant.
    const colonne = corps([{ ...jour("01"), layout_story_opener: false, layout_split_left: true, photos: photos(2), ...fait }]);
    expect(colonne).toContain("mb-split__aside");
    expect(colonne).not.toContain("mb-card--postit-bande");
  });
});
