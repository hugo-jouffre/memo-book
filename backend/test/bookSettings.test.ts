import { describe, expect, it } from "vitest";
import { applyBookSettings, keepsPhotos } from "../src/services/bookSettings.js";
import { renderTemplateToHtml } from "../src/services/bookPdf.js";

/**
 * Les réglages de personnalisation appliqués au payload du carnet de l'app
 * (`services/bookSettings.ts`) — les mêmes que l'atelier applique au sien.
 */
const reglages = { photoTextRatio: 50, rulesEnabled: true, decorationQuota: 2 };
const photo = "https://exemple.test/a.jpg";
const payload = {
  book_title: "Carnet",
  days: [
    { title: "Jour 1", day_intro: { day_number: "01" }, body_html: "<p>Récit.</p>", photos: [photo, photo], layout_split_left: true },
    { title: "", body_html: "", photos: [photo, photo, photo], layout_photo_page: true },
    { title: "", body_html: "<p>Suite.</p>", photos: [photo, photo, photo], layout_trio_portrait: true },
    { title: "Jour 2", day_intro: { day_number: "02" }, body_html: "<p>Carte.</p>", photos: [photo, photo], layout_chapter_map: true },
  ],
};

describe("réglages du carnet de l'app", () => {
  it("dit au gabarit les pointillés et le quota de décorations", () => {
    expect(applyBookSettings(payload, reglages)).toMatchObject({ rules_enabled: true, decoration_quota: 2 });
    expect(applyBookSettings(payload, { ...reglages, rulesEnabled: false, decorationQuota: 0 })).toMatchObject({
      rules_enabled: false,
      decoration_quota: 0,
    });
  });

  it("garde les photos tant que le ratio n'est pas à 0 %", () => {
    expect(keepsPhotos({ photoTextRatio: 25 })).toBe(true);
    expect(applyBookSettings(payload, reglages)["days"]).toEqual(payload.days);
  });

  it("n'imprime aucune photo à 0 % : ni planche, ni bande, et la page retombe sur le récit seul", () => {
    expect(keepsPhotos({ photoTextRatio: 0 })).toBe(false);
    const days = applyBookSettings(payload, { ...reglages, photoTextRatio: 0 })["days"] as Record<string, unknown>[];
    expect(days).toHaveLength(3);
    expect(days.flatMap((d) => d["photos"] as string[])).toEqual([]);
    expect(days.map((d) => Object.keys(d).filter((k) => k.startsWith("layout_") && d[k] === true))).toEqual([
      ["layout_story_facts"],
      ["layout_story_facts"],
      // La carte de chapitre reste : elle n'est pas une photo.
      ["layout_chapter_map"],
    ]);
  });

  it("se lit dans le gabarit : la réglure et les décors s'effacent", () => {
    const corps = (p: Record<string, unknown>) =>
      /<body class="([^"]*)"/.exec(renderTemplateToHtml({ payload: p, profile: "print" }))?.[1] ?? "";
    expect(corps(applyBookSettings(payload, reglages))).not.toMatch(/sans-reglure|sans-decor/);
    expect(corps(applyBookSettings(payload, { ...reglages, rulesEnabled: false }))).toContain("sans-reglure");
    expect(corps(applyBookSettings(payload, { ...reglages, decorationQuota: 0 }))).toContain("sans-decor");
  });
});
