import { describe, expect, it } from "vitest";
import { applyBookSettings, keepsPhotos } from "../src/services/bookSettings.js";
import { renderTemplateToHtml } from "../src/services/bookPdf.js";
import { PHOTO_RATIOS } from "../src/services/photoRatio.js";
import { groupSteps } from "../src/services/payloadValidator.js";

/**
 * Les réglages de personnalisation appliqués au payload du carnet de l'app
 * (`services/bookSettings.ts`) — les mêmes que l'atelier applique au sien.
 *
 * `applyBookSettings` **recompose chaque étape** avec le composeur de
 * l'atelier (`bookComposer.ts`), au nombre de photos que `photoRatio.ts`
 * demande (Hugo, 13/10/2026). Ce que ces tests gardent : le récit du voyageur
 * en sort intact, les paliers se voient, et les décors de l'atelier — tracé,
 * stickers — arrivent dans le PDF de l'app.
 */
const reglages = { photoTextRatio: 50, rulesEnabled: true, decorationQuota: 2, freeZonesEnabled: true };
const photo = "https://exemple.test/a.jpg";
const payload = {
  book_title: "Carnet",
  days: [
    {
      title: "Jour 1",
      day_intro: { day_number: "01" },
      body_html: "<p>Récit du matin, long comme une vraie étape racontée au vocal.</p>",
      photos: [photo, photo],
      layout_split_left: true,
    },
    { title: "", body_html: "", photos: [photo, photo, photo], layout_photo_page: true },
    {
      title: "",
      body_html: "<p>Suite de l'après-midi, avec ce qu'il faut de signes.</p>",
      photos: [photo, photo, photo],
      layout_trio_portrait: true,
    },
    {
      title: "Jour 2",
      day_intro: { day_number: "02" },
      body_html: "<p>Carte du chapitre et récit court.</p>",
      photos: [photo, photo],
      layout_chapter_map: true,
      map: { regions: ["GR"], points: [{ label: "Paros", lat: 37.08, lon: 25.15 }] },
    },
  ],
};

/**
 * Une étape compte un nombre de pages pair — sauf celle qui n'a pas de quoi en
 * remplir une seconde : une seule page, sans photo (le composeur le signale).
 */
const paire = (etape: { days: Record<string, unknown>[] }): boolean =>
  etape.days.length % 2 === 0 ||
  (etape.days.length === 1 && !((etape.days[0]!["photos"] as unknown[] | undefined)?.length ?? 0));

/** Le récit d'une étape, bout à bout — ce qui ne doit jamais changer. */
const recitDesEtapes = (days: Record<string, unknown>[]): string[] =>
  groupSteps(days).map((etape) =>
    etape.days.map((jour) => (typeof jour["body_html"] === "string" ? jour["body_html"] : "")).join(""),
  );

const joursDe = (ratio: number): Record<string, unknown>[] =>
  applyBookSettings(payload, { ...reglages, photoTextRatio: ratio })["days"] as Record<
    string,
    unknown
  >[];

const layoutsDe = (days: Record<string, unknown>[]): string[] =>
  days.map((jour) => Object.keys(jour).find((cle) => cle.startsWith("layout_") && jour[cle] === true) ?? "");

describe("réglages du carnet de l'app", () => {
  it("dit au gabarit les pointillés, le quota de décorations et le ratio", () => {
    expect(applyBookSettings(payload, reglages)).toMatchObject({
      rules_enabled: true,
      decoration_quota: 2,
      photo_ratio: 50,
    });
    expect(
      applyBookSettings(payload, { ...reglages, rulesEnabled: false, decorationQuota: 0 }),
    ).toMatchObject({ rules_enabled: false, decoration_quota: 0 });
  });

  it("n'ajoute plus de pages libres en fin de carnet, même « Zones libres » allumé (15/10/2026)", () => {
    expect(applyBookSettings(payload, reglages)["pages_libres"]).toBe(0);
    expect(applyBookSettings(payload, { ...reglages, freeZonesEnabled: false })["pages_libres"]).toBe(0);
    // Le gabarit ignore aussi un ancien payload qui en demandait trois.
    const html = renderTemplateToHtml({ payload: { ...applyBookSettings(payload, reglages), pages_libres: 3 }, profile: "print" });
    expect(html.match(/class="page page--libre/g)).toBeNull();
  });

  // L'ancien « garde les photos tant que le ratio n'est pas à 0 % » comparait
  // `days` au payload d'entrée. Il ne peut plus tenir : depuis le ratio, chaque
  // étape est **recomposée** sur son plan. Ce qu'il protégeait — le carnet ne
  // perd rien — est désormais couvert plus précisément par le test suivant (le
  // récit, octet pour octet) et par la montée du nombre de photos par palier.
  it("ne touche jamais au récit du voyageur, à aucun palier", () => {
    expect(keepsPhotos({ photoTextRatio: 25 })).toBe(true);
    const attendu = recitDesEtapes(payload.days);
    for (const ratio of PHOTO_RATIOS) {
      if (ratio === 100) continue; // à 100 %, le récit n'est pas imprimé : cas à part
      expect(recitDesEtapes(joursDe(ratio)), `ratio ${ratio}`).toEqual(attendu);
    }
  });

  it("n'imprime aucune photo à 0 %, et le récit prend leur place", () => {
    expect(keepsPhotos({ photoTextRatio: 0 })).toBe(false);
    const days = joursDe(0);
    expect(days.flatMap((jour) => (jour["photos"] ?? []) as string[])).toEqual([]);
    // Le récit occupe la feuille : plus de zone flottante, plus de bande.
    // La carte de chapitre reste — elle n'est pas une photo.
    const layouts = layoutsDe(days);
    expect(layouts).toContain("layout_chapter_map");
    expect(layouts.filter((l) => l !== "layout_chapter_map").every((l) => l === "layout_story_full")).toBe(true);
    // Chaque étape garde un nombre de pages pair (LAYOUT_KB § « Structure d'une étape »).
    for (const etape of groupSteps(days)) expect(paire(etape)).toBe(true);
  });

  it("n'imprime aucun récit à 100 %, et garde le bandeau sur la première page", () => {
    const days = joursDe(100);
    // `body_html` est requis par le schéma du gabarit : une planche le laisse
    // vide plutôt que de l'omettre.
    expect(days.every((jour) => jour["body_html"] === "")).toBe(true);
    expect(layoutsDe(days)[0]).toBe("layout_photo_wall_intro");
    expect(days[0]?.["day_intro"]).toEqual({ day_number: "01" });
  });

  it("monte en surface photo à mesure que le palier monte", () => {
    const photos = PHOTO_RATIOS.map((ratio) =>
      joursDe(ratio).reduce(
        (somme, jour) => somme + ((jour["photos"] as unknown[] | undefined)?.length ?? 0),
        0,
      ),
    );
    expect(photos[0]).toBe(0);
    for (let i = 1; i < photos.length; i += 1) {
      expect(photos[i]!, `palier ${PHOTO_RATIOS[i]}`).toBeGreaterThanOrEqual(photos[i - 1]!);
    }
  });

  it("ne pose jamais deux drapeaux de layout sur une page", () => {
    for (const ratio of PHOTO_RATIOS) {
      for (const jour of joursDe(ratio)) {
        const actifs = Object.keys(jour).filter((cle) => cle.startsWith("layout_") && jour[cle] === true);
        expect(actifs, `ratio ${ratio}`).toHaveLength(1);
      }
    }
  });

  it("garde un nombre de pages pair à chaque étape, et les photos seules après le récit", () => {
    for (const ratio of PHOTO_RATIOS) {
      for (const etape of groupSteps(joursDe(ratio))) {
        expect(paire(etape), `ratio ${ratio}`).toBe(true);
        const recit = etape.days.map((jour) => Boolean(jour["body_html"]));
        // Une page de récit ne vient jamais après une page sans récit.
        expect(recit.indexOf(false) < 0 || !recit.slice(recit.indexOf(false)).includes(true), `ratio ${ratio}`).toBe(true);
      }
    }
  });

  it("pose les décors de l'atelier : un tracé, et des stickers tirés du récit", () => {
    const plage = {
      book_title: "Carnet",
      days: [
        {
          title: "La plage",
          day_intro: { day_number: "01", location: "Paros" },
          body_html: "<p>Une journée entière à la plage, le sable chaud et la mer turquoise jusqu'au soir.</p>",
          photos: Array.from({ length: 6 }, (_, i) => `https://exemple.test/${i}.jpg`),
          layout_collage: true,
        },
      ],
    };
    const days = applyBookSettings(plage, { ...reglages, photoTextRatio: 75 })["days"] as Record<string, unknown>[];
    expect(days.some((jour) => typeof jour["trace"] === "string" && jour["trace"] !== "aucun")).toBe(true);
    const stickers = days.flatMap((jour) => (jour["stickers"] ?? []) as { url: string }[]);
    expect(stickers.length).toBeGreaterThan(0);
    expect(stickers[0]!.url).toMatch(/^https:\/\/raw\.githubusercontent\.com\/.+\/assets\/stickers\//);
    // Décorations à 0 : ni tracé ni sticker.
    const sans = applyBookSettings(plage, { ...reglages, photoTextRatio: 75, decorationQuota: 0 })["days"] as Record<
      string,
      unknown
    >[];
    expect(sans.flatMap((jour) => (jour["stickers"] ?? []) as unknown[])).toEqual([]);
  });

  it("se lit dans le gabarit : la réglure et les décors", () => {
    const html = (p: Record<string, unknown>) => renderTemplateToHtml({ payload: p, profile: "print" });
    const corps = (p: Record<string, unknown>) => /<body class="([^"]*)"/.exec(html(p))?.[1] ?? "";
    expect(corps(applyBookSettings(payload, reglages))).not.toMatch(/sans-reglure|sans-decor/);
    expect(corps(applyBookSettings(payload, { ...reglages, rulesEnabled: false }))).toContain(
      "sans-reglure",
    );
    expect(corps(applyBookSettings(payload, { ...reglages, decorationQuota: 0 }))).toContain(
      "sans-decor",
    );
  });

  it("n'imprime aucun quiz quand le réglage est coupé, et le pose quand il est allumé", () => {
    const quiz = { question: "Qui a renversé le café ?", choices: ["Clara", "Hugo", "Le serveur"], answer: "Hugo" };
    const sansPhoto = {
      book_title: "Carnet",
      days: [{ title: "Jour 1", day_intro: { day_number: "01" }, body_html: "<p>Un récit court, sans photo.</p>", layout_story_opener: true, quiz }],
    };
    const quizDe = (quizEnabled?: boolean) =>
      (applyBookSettings(sansPhoto, { ...reglages, ...(quizEnabled === undefined ? {} : { quizEnabled }) })["days"] as Record<string, unknown>[])
        .map((jour) => jour["quiz"])
        .filter(Boolean);
    expect(quizDe(false)).toEqual([]);
    expect(quizDe()).toEqual([quiz]);
    expect(quizDe(true)).toEqual([quiz]);
  });

  it("recale le carnet sur sa cible de pages, pages libres de fin comprises, et le journalise", () => {
    // Une étape de six paragraphes et les quatre photos que le ratio demande :
    // deux pages ; le colophon et les trois pages libres en font 6. (Des
    // photos en plus iraient sur des pages de photos, 18/10/2026.)
    const long = Array.from({ length: 6 }, (_, k) => `<p>${`Le matin nous sommes allés voir le lieu ${k} et nous y sommes restés longtemps. `.repeat(2).trim()}</p>`).join("");
    const etape = { title: "Jour 1", day_intro: { day_number: "01" }, body_html: long, photos: Array.from({ length: 4 }, (_, i) => `https://exemple.test/${i}.jpg`), layout_collage: true };
    const voyage = { book_title: "Carnet", days: [etape] };
    const sans = applyBookSettings(voyage, reglages)["days"] as unknown[];
    const journal: string[] = [];
    const avec = applyBookSettings(voyage, { ...reglages, targetPageCount: 12 }, (t) => journal.push(t))["days"] as unknown[];
    expect(sans.length + 4).toBeLessThan(7);
    expect(avec.length + 4).toBeGreaterThanOrEqual(7);
    expect(avec.length % 2).toBe(0);
    expect(recitDesEtapes(avec as Record<string, unknown>[])).toEqual(recitDesEtapes(sans as Record<string, unknown>[]));
    expect(journal.filter((t) => t.startsWith("pages cible"))).toHaveLength(1);
  });
});
