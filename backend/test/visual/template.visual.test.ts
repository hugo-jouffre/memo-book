import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import pixelmatch from "pixelmatch";
import { PNG } from "pngjs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Browser, Page } from "playwright-core";
import { loadSamplePayload } from "../../src/lib/templates.js";
import { installOfflineRouting, renderTemplateToHtml, settle } from "../../src/services/bookPdf.js";

/**
 * Non-régression visuelle du carnet.
 *
 * On compare des captures des éléments `.page`, pas la rastérisation du PDF :
 * c'est le même chemin de calcul et de peinture que l'impression, sans faire
 * entrer poppler dans l'équation. La géométrie du PDF, elle, est vérifiée par
 * `pdfinfo` dans `scripts/render-local.ts`.
 *
 *   npm run test:visual            compare aux références
 *   npm run test:visual:update     régénère les références
 */

const GOLDEN_DIR = resolve(import.meta.dirname, "__goldens__/travel-journal");
const OUTPUT_DIR = resolve(import.meta.dirname, "../../.render-out/visual");

/** Les rotations et le grain SVG produisent un anticrénelage non identique au pixel. */
const MAX_DIFF_RATIO = 0.004;

const UPDATE = process.env["UPDATE_GOLDENS"] === "1";

/**
 * Le test ne tourne que sur Linux avec un navigateur présent : le rendu du
 * texte diffère entre macOS et Linux, comparer les deux ne prouverait rien.
 * Sur un Mac la suite se saute d'elle-même, sans faire échouer `npm test`.
 */
async function browserAvailable(): Promise<boolean> {
  if (process.platform !== "linux") return false;
  try {
    const { chromium } = await import("playwright-core");
    return existsSync(chromium.executablePath());
  } catch {
    return false;
  }
}

const enabled = await browserAvailable();

describe.runIf(enabled)("rendu visuel du carnet", () => {
  let browser: Browser;
  let page: Page;
  let pageCount = 0;
  let chromiumVersion = "";

  beforeAll(async () => {
    const { chromium } = await import("playwright-core");
    browser = await chromium.launch({
      args: [
        "--font-render-hinting=none",
        "--disable-lcd-text",
        "--disable-font-subpixel-positioning",
        "--force-color-profile=srgb",
        "--hide-scrollbars",
      ],
    });
    chromiumVersion = browser.version();

    const context = await browser.newContext({
      deviceScaleFactor: 1,
      locale: "fr-FR",
      timezoneId: "UTC",
      colorScheme: "light",
      reducedMotion: "reduce",
    });
    // Indispensable : sans routage hors ligne, une machine qui atteint le CDN
    // Webflow et une machine qui ne l'atteint pas rendent des pages entièrement
    // différentes. Les références deviendraient dépendantes du réseau.
    await installOfflineRouting(context);

    page = await context.newPage();
    await page.emulateMedia({ media: "print" });

    // Profil « print » : fond blanc, donc des références légères à versionner.
    // Le profil « preview » est contrôlé à l'œil via l'artefact de CI.
    await page.setContent(
      renderTemplateToHtml({ payload: loadSamplePayload(), profile: "print" }),
      { waitUntil: "load" },
    );
    await settle(page);
    pageCount = await page.locator(".page").count();

    mkdirSync(GOLDEN_DIR, { recursive: true });
    mkdirSync(OUTPUT_DIR, { recursive: true });
  }, 60_000);

  afterAll(async () => {
    await browser?.close();
  });

  it("garde le nombre de pages attendu", () => {
    expect(pageCount).toBe(7);
  });

  it("tourne sur le Chromium de référence", () => {
    const metaPath = resolve(GOLDEN_DIR, "meta.json");

    if (UPDATE || !existsSync(metaPath)) {
      writeFileSync(metaPath, `${JSON.stringify({ chromium: chromiumVersion }, null, 2)}\n`);
      return;
    }

    const meta = JSON.parse(readFileSync(metaPath, "utf8")) as { chromium: string };
    // Un changement de Chromium modifie le rendu du texte : mieux vaut le dire
    // franchement qu'afficher un diff de pixels incompréhensible.
    expect(
      chromiumVersion,
      `Chromium a changé (${meta.chromium} → ${chromiumVersion}). ` +
        `Relis les pages puis régénère : npm run test:visual:update`,
    ).toBe(meta.chromium);
  });

  for (let index = 0; index < 7; index += 1) {
    const number = String(index + 1).padStart(2, "0");

    it(`page ${number} est conforme à sa référence`, async () => {
      const shot = await page.locator(".page").nth(index).screenshot({ animations: "disabled" });
      const goldenPath = resolve(GOLDEN_DIR, `page-${number}.png`);

      if (UPDATE || !existsSync(goldenPath)) {
        writeFileSync(goldenPath, shot);
        return;
      }

      const actual = PNG.sync.read(shot);
      const golden = PNG.sync.read(readFileSync(goldenPath));

      expect([actual.width, actual.height]).toEqual([golden.width, golden.height]);

      const diff = new PNG({ width: golden.width, height: golden.height });
      const changed = pixelmatch(golden.data, actual.data, diff.data, golden.width, golden.height, {
        threshold: 0.12,
        includeAA: false,
      });
      const ratio = changed / (golden.width * golden.height);

      if (ratio > MAX_DIFF_RATIO) {
        const diffPath = resolve(OUTPUT_DIR, `diff-page-${number}.png`);
        writeFileSync(diffPath, PNG.sync.write(diff));
        writeFileSync(resolve(OUTPUT_DIR, `actual-page-${number}.png`), shot);
        expect.fail(
          `page ${number} : ${(ratio * 100).toFixed(3)} % de pixels changés ` +
            `(seuil ${(MAX_DIFF_RATIO * 100).toFixed(1)} %). Diff : ${diffPath}`,
        );
      }
    }, 30_000);
  }
});
