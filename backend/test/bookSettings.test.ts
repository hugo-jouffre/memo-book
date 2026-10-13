import { describe, expect, it } from "vitest";
import { applyBookSettings, keepsPhotos } from "../src/services/bookSettings.js";
import { renderTemplateToHtml } from "../src/services/bookPdf.js";
import { PHOTO_RATIOS } from "../src/services/photoRatio.js";
import { groupSteps } from "../src/services/payloadValidator.js";

/**
 * Les réglages de personnalisation appliqués au payload du carnet de l'app
 * (`services/bookSettings.ts`) — les mêmes que l'atelier applique au sien.
 *
 * Depuis le ratio texte / photo, `applyBookSettings` ne se contente plus de
 * retirer des champs : il **recompose chaque étape** sur le plan calculé par
 * `photoRatio.ts`. Ce que ces tests gardent, c'est donc surtout la règle
 * absolue : le récit du voyageur en sort identique, octet pour octet.
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

  it("ajoute trois pages libres en fin de carnet quand « Zones libres » est allumé", () => {
    expect(applyBookSettings(payload, reglages)["pages_libres"]).toBe(3);
    expect(applyBookSettings(payload, { ...reglages, freeZonesEnabled: false })["pages_libres"]).toBe(0);
    const html = renderTemplateToHtml({ payload: applyBookSettings(payload, reglages), profile: "print" });
    expect(html.match(/class="page page--libre/g)).toHaveLength(3);
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
    expect(layoutsDe(days)).toEqual(["layout_story_full", "layout_chapter_map"]);
    // Et les photos retirées libèrent des pages : deux étapes, deux pages.
    expect(days).toHaveLength(2);
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

  it("n'écrit l'échelle de bande que quand elle s'écarte de la conception", () => {
    for (const ratio of PHOTO_RATIOS) {
      for (const jour of joursDe(ratio)) {
        const echelle = jour["band_scale"];
        if (echelle === undefined) continue;
        expect(typeof echelle).toBe("number");
        expect(echelle).not.toBe(1);
      }
    }
  });

  it("se lit dans le gabarit : la réglure, les décors et l'échelle de bande", () => {
    const html = (p: Record<string, unknown>) => renderTemplateToHtml({ payload: p, profile: "print" });
    const corps = (p: Record<string, unknown>) => /<body class="([^"]*)"/.exec(html(p))?.[1] ?? "";
    expect(corps(applyBookSettings(payload, reglages))).not.toMatch(/sans-reglure|sans-decor/);
    expect(corps(applyBookSettings(payload, { ...reglages, rulesEnabled: false }))).toContain(
      "sans-reglure",
    );
    expect(corps(applyBookSettings(payload, { ...reglages, decorationQuota: 0 }))).toContain(
      "sans-decor",
    );
    // L'échelle de bande arrive dans la page par une variable CSS.
    const avecEchelle = applyBookSettings(payload, { ...reglages, photoTextRatio: 25 });
    expect(html(avecEchelle)).toContain("--mb-band:");
  });
});
