import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import nunjucks from "nunjucks";
import type { Browser, Page, Route } from "playwright-core";
import {
  loadPrintSettings,
  loadTemplateCss,
  loadTemplateHtml,
  type PrintSettings,
} from "../lib/templates.js";

/**
 * Rendu du carnet en local : Jinja2 (via Nunjucks) puis Chromium.
 *
 * Le but n'est pas de remplacer APITemplate mais de rendre le même couple
 * `index.html` + `style.css` en quelques secondes, hors ligne, pour pouvoir
 * itérer sur la mise en page et détecter les régressions visuelles.
 */

export type RenderProfile = "print" | "preview";

/** Fond crème granulé pour l'aperçu in-app, fond blanc pour l'imprimeur. */
export const RENDER_PROFILES: readonly RenderProfile[] = ["print", "preview"];

export function isRenderProfile(value: string): value is RenderProfile {
  return (RENDER_PROFILES as readonly string[]).includes(value);
}

// ---------------------------------------------------------------------------
// Moteur de gabarit
// ---------------------------------------------------------------------------

/**
 * Le loader `null` interdit `{% include %}` / `{% extends %}` : ils sont de
 * toute façon impossibles chez APITemplate, qui ne reçoit qu'un seul fichier.
 * Mieux vaut échouer ici que découvrir la limite en production.
 */
export const NUNJUCKS_OPTIONS = {
  autoescape: true,
  throwOnUndefined: false,
  trimBlocks: false,
  lstripBlocks: false,
} as const;

export function createTemplateEnvironment(): nunjucks.Environment {
  return new nunjucks.Environment(null, { ...NUNJUCKS_OPTIONS });
}

/**
 * Jinja2 rend `None` par la chaîne littérale « None », là où Nunjucks rend une
 * chaîne vide. Un `null` qui se glisse dans le payload écrirait donc le mot
 * « None » dans le livre imprimé — sans que rien ne le signale. On refuse.
 */
export function assertNoNullValues(value: unknown, path = "payload"): void {
  if (value === null) {
    throw new Error(
      `${path} vaut null. Jinja2 l'imprimerait « None » dans le carnet : ` +
        `omets la clé plutôt que de l'envoyer à null.`,
    );
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoNullValues(item, `${path}[${index}]`));
    return;
  }
  if (typeof value === "object") {
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      assertNoNullValues(item, `${path}.${key}`);
    }
  }
}

export interface RenderHtmlOptions {
  payload: Record<string, unknown>;
  profile?: RenderProfile;
}

/** Applique le payload au gabarit et injecte la feuille de style verbatim. */
export function renderTemplateToHtml({ payload, profile = "preview" }: RenderHtmlOptions): string {
  assertNoNullValues(payload);

  const environment = createTemplateEnvironment();
  const rendered = environment.renderString(loadTemplateHtml(), {
    ...payload,
    render_profile: profile,
  });

  // `style.css` est un fragment HTML (`<meta>` + `<style>`), pas du CSS nu :
  // APITemplate l'injecte tel quel, on fait strictement pareil.
  const css = loadTemplateCss();
  return rendered.includes("</head>")
    ? rendered.replace("</head>", `${css}\n</head>`)
    : `${css}\n${rendered}`;
}

// ---------------------------------------------------------------------------
// Mode hors ligne
// ---------------------------------------------------------------------------

/**
 * Hôtes que le proxy réseau des sessions Claude Code et de la CI ne sert pas.
 * En `--offline` on les sert depuis le bundle local, sinon le rendu dépendrait
 * d'un CDN tiers et cesserait d'être reproductible.
 */
const OFFLINE_HOSTS = new Set([
  "cdn.prod.website-files.com",
  "uploads-ssl.webflow.com",
  "assets.website-files.com",
  "fonts.googleapis.com",
  "fonts.gstatic.com",
]);

export const OFFLINE_DIR = resolve(
  new URL("../../test/fixtures/offline", import.meta.url).pathname,
);

/** PNG gris 1×1, étiré par le CSS : déterministe, visible, jamais en erreur. */
const PLACEHOLDER_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

function loadOfflineManifest(): Record<string, string> {
  const path = resolve(OFFLINE_DIR, "manifest.json");
  if (!existsSync(path)) return {};
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, string>;
}

async function fulfillOffline(route: Route, manifest: Record<string, string>): Promise<void> {
  const request = route.request();

  let hostname: string;
  try {
    hostname = new URL(request.url()).hostname;
  } catch {
    return route.continue();
  }

  if (!OFFLINE_HOSTS.has(hostname)) return route.continue();

  const local = manifest[request.url()];
  if (local) {
    const path = resolve(OFFLINE_DIR, local);
    if (existsSync(path)) {
      return route.fulfill({ path, headers: { "cache-control": "no-store" } });
    }
  }

  // Toute branche doit se terminer : un handler qui ne résout pas fige le rendu.
  switch (request.resourceType()) {
    case "image":
      return route.fulfill({ status: 200, contentType: "image/png", body: PLACEHOLDER_PNG });
    case "font":
      // `abort` fait jouer la chaîne de repli CSS, de façon déterministe.
      return route.abort("failed");
    case "stylesheet":
      return route.fulfill({ status: 200, contentType: "text/css", body: "" });
    default:
      return route.abort("failed");
  }
}

// ---------------------------------------------------------------------------
// Rendu Chromium
// ---------------------------------------------------------------------------

const PT_PER_INCH = 72;

/**
 * `page.pdf()` n'accepte pas l'unité `pt` : on convertit en pouces. Avec
 * `preferCSSPageSize`, la règle `@page` de style.css fait foi de toute façon —
 * ces valeurs ne servent que de repli.
 */
function pageBox(print: PrintSettings): { width: string; height: string } {
  const bleed = print.bleedPt * 2;
  return {
    width: `${(print.widthPt + bleed) / PT_PER_INCH}in`,
    height: `${(print.heightPt + bleed) / PT_PER_INCH}in`,
  };
}

/** Points PostScript attendus dans le PDF, pour vérifier la sortie. */
export function expectedPageSizePt(print: PrintSettings): { width: number; height: number } {
  const bleed = print.bleedPt * 2;
  return { width: print.widthPt + bleed, height: print.heightPt + bleed };
}

/**
 * Attend que la page soit réellement peinte.
 *
 * Deux pièges spécifiques à ce gabarit :
 * - toutes les `<img>` portent `loading="lazy"`, donc hors viewport Chromium
 *   peut ne jamais les charger ;
 * - les polices sont en `font-display: swap`, donc le premier paint utilise la
 *   police de repli si on n'attend pas.
 */
export async function settle(page: Page): Promise<void> {
  await page.evaluate(() => {
    document.querySelectorAll<HTMLImageElement>('img[loading="lazy"]').forEach((img) => {
      img.loading = "eager";
    });
  });

  await page.evaluate(async () => {
    await document.fonts.ready;

    await Promise.all(
      Array.from(document.images).map((img) =>
        img.complete
          ? img.decode().catch(() => undefined)
          : new Promise<void>((done) => {
              img.addEventListener("load", () => done(), { once: true });
              img.addEventListener("error", () => done(), { once: true });
            }),
      ),
    );

    await new Promise<void>((done) => {
      requestAnimationFrame(() => requestAnimationFrame(() => done()));
    });
  });
}

export interface RenderPdfOptions extends RenderHtmlOptions {
  offline?: boolean;
  /** Navigateur déjà lancé, pour enchaîner plusieurs rendus (mode `--watch`). */
  browser?: Browser;
}

export interface RenderedBookPdf {
  pdf: Buffer;
  html: string;
  pageCount: number;
  print: PrintSettings;
}

export async function renderBookPdf({
  payload,
  profile = "preview",
  offline = false,
  browser: existingBrowser,
}: RenderPdfOptions): Promise<RenderedBookPdf> {
  const { chromium } = await import("playwright-core").catch(() => {
    throw new Error(
      "playwright-core est absent. Il est en devDependency : lance `npm install` " +
        "sans `--omit=dev` pour utiliser le rendu local.",
    );
  });

  const html = renderTemplateToHtml({ payload, profile });
  const print = loadPrintSettings();
  const box = pageBox(print);

  const browser =
    existingBrowser ??
    (await chromium.launch({
      args: [
        // Rendu de texte reproductible d'une machine à l'autre.
        "--font-render-hinting=none",
        "--disable-lcd-text",
        "--disable-font-subpixel-positioning",
        "--force-color-profile=srgb",
        "--hide-scrollbars",
      ],
    }));

  const context = await browser.newContext({
    deviceScaleFactor: 1,
    locale: "fr-FR",
    timezoneId: "UTC",
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  context.setDefaultTimeout(30_000);

  try {
    if (offline) {
      const manifest = loadOfflineManifest();
      await context.route("**/*", (route) => fulfillOffline(route, manifest));
    }

    const page = await context.newPage();
    // Avant `setContent` : on veut le layout d'impression dès le premier calcul.
    await page.emulateMedia({ media: "print" });
    await page.setContent(html, { waitUntil: "load" });
    await settle(page);

    const pageCount = await page.locator(".page").count();

    const pdf = await page.pdf({
      width: box.width,
      height: box.height,
      margin: {
        top: `${print.marginPt.top / PT_PER_INCH}in`,
        right: `${print.marginPt.right / PT_PER_INCH}in`,
        bottom: `${print.marginPt.bottom / PT_PER_INCH}in`,
        left: `${print.marginPt.left / PT_PER_INCH}in`,
      },
      // Sans `printBackground`, ni fond crème, ni grain, ni encadrés blancs.
      printBackground: print.printBackground,
      preferCSSPageSize: print.preferCSSPageSize,
      scale: print.scale,
      displayHeaderFooter: false,
      tagged: false,
      outline: false,
    });

    return { pdf, html, pageCount, print };
  } finally {
    await context.close();
    if (!existingBrowser) await browser.close();
  }
}
