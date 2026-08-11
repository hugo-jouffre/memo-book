#!/usr/bin/env tsx
/**
 * Rendu local du carnet MemoBook.
 *
 *   npm run render:local -- --png                 rendu + un PNG par page
 *   npm run render:local -- --offline --png       sans réseau (CI, sandbox)
 *   npm run render:local -- --profile print       fond blanc pour l'imprimeur
 *   npm run render:local -- --watch --png         re-rendu à chaque sauvegarde
 *
 * Produit le même HTML que celui envoyé à APITemplate, mais en quelques
 * secondes et sans aller-retour réseau.
 */
import { execFile } from "node:child_process";
import { existsSync, watch } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, resolve } from "node:path";
import { parseArgs } from "node:util";
import { promisify } from "node:util";
import type { Browser } from "playwright-core";
import { TEMPLATE_DIR, loadSamplePayload } from "../src/lib/templates.js";
import {
  expectedPageSizePt,
  isRenderProfile,
  renderBookPdf,
  type RenderProfile,
} from "../src/services/bookPdf.js";
import { validatePayload } from "../src/services/payloadValidator.js";

const execFileAsync = promisify(execFile);

/** Chromium arrondit au pixel CSS : ~0,7 pt d'écart sur une page A5. */
const GEOMETRY_TOLERANCE_PT = 1;

const { values } = parseArgs({
  options: {
    data: { type: "string" },
    out: { type: "string", default: ".render-out" },
    profile: { type: "string", default: "preview" },
    offline: { type: "boolean", default: false },
    png: { type: "boolean", default: false },
    dpi: { type: "string", default: "110" },
    html: { type: "boolean", default: false },
    validate: { type: "boolean", default: false },
    watch: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
  allowPositionals: false,
});

if (values.help) {
  console.log(
    [
      "Usage : npm run render:local -- [options]",
      "",
      "  --data <fichier>   payload JSON (défaut : templates/travel-journal/data.json)",
      "  --out <dossier>    dossier de sortie (défaut : .render-out)",
      "  --profile <p>      print | preview (défaut : preview)",
      "  --offline          sert les hôtes injoignables depuis le bundle local",
      "  --png [--dpi n]    rastérise chaque page via pdftoppm",
      "  --html             écrit aussi le HTML rendu (débogage de l'étape Jinja)",
      "  --validate         refuse un payload invalide au lieu de le rendre",
      "  --watch            re-rendu à chaque modification du template ou des données",
    ].join("\n"),
  );
  process.exit(0);
}

const profile = values.profile;
if (!isRenderProfile(profile)) {
  console.error(`--profile doit valoir « print » ou « preview », reçu « ${profile} ».`);
  process.exit(1);
}

const outDir = resolve(process.cwd(), values.out);
const dataPath = values.data ? resolve(process.cwd(), values.data) : undefined;

async function loadPayload(): Promise<Record<string, unknown>> {
  if (!dataPath) return loadSamplePayload();
  return JSON.parse(await readFile(dataPath, "utf8")) as Record<string, unknown>;
}

async function rasterize(pdfPath: string): Promise<number> {
  try {
    await execFileAsync("pdftoppm", [
      "-png",
      "-r",
      values.dpi,
      "-aa",
      "yes",
      "-aaVector",
      "yes",
      pdfPath,
      resolve(outDir, "page"),
    ]);
    return 0;
  } catch {
    console.warn(
      "  ⚠ pdftoppm est absent : PDF produit, pas de PNG. " +
        "Installe poppler (`brew install poppler` / `apt-get install poppler-utils`).",
    );
    return 1;
  }
}

/** Compare la géométrie annoncée par le PDF à `print.json`. */
async function checkGeometry(
  pdfPath: string,
  expected: { width: number; height: number },
  pageCount: number,
): Promise<void> {
  let stdout: string;
  try {
    ({ stdout } = await execFileAsync("pdfinfo", [pdfPath]));
  } catch {
    return;
  }

  const size = /Page size:\s+([\d.]+) x ([\d.]+) pts/.exec(stdout);
  const pages = /Pages:\s+(\d+)/.exec(stdout);

  if (size?.[1] && size[2]) {
    const width = Number(size[1]);
    const height = Number(size[2]);
    // Chromium arrondit au pixel CSS entier avant de convertir en points :
    // un écart infra-point est normal et invisible à l'impression.
    const ok =
      Math.abs(width - expected.width) <= GEOMETRY_TOLERANCE_PT &&
      Math.abs(height - expected.height) <= GEOMETRY_TOLERANCE_PT;
    console.log(
      `  ${ok ? "✓" : "✗"} format ${width} × ${height} pts ` +
        `(attendu ${expected.width} × ${expected.height}, tolérance ±${GEOMETRY_TOLERANCE_PT})`,
    );
    if (!ok) process.exitCode = 1;
  }

  if (pages?.[1] && Number(pages[1]) !== pageCount) {
    console.log(
      `  ✗ ${pages[1]} pages dans le PDF pour ${pageCount} éléments .page : ` +
        `la pagination CSS ne tombe pas juste.`,
    );
    process.exitCode = 1;
  }
}

async function renderOnce(browser?: Browser): Promise<void> {
  const started = Date.now();
  const payload = await loadPayload();

  if (values.validate) {
    const result = validatePayload(payload);
    for (const warning of result.warnings) console.warn(`  ⚠ ${warning.path} : ${warning.message}`);
    if (!result.valid) {
      for (const error of result.errors) console.error(`  ✗ ${error.path} : ${error.message}`);
      throw new Error("Payload invalide.");
    }
  }

  const options = { payload, profile: profile as RenderProfile, offline: values.offline };
  const { pdf, html, pageCount, print } = await renderBookPdf(
    browser ? { ...options, browser } : options,
  );

  await mkdir(outDir, { recursive: true });
  const pdfPath = resolve(outDir, "carnet.pdf");
  await writeFile(pdfPath, pdf);

  if (values.html) await writeFile(resolve(outDir, "carnet.html"), html);

  console.log(
    `✓ ${basename(pdfPath)} — ${pageCount} pages, profil « ${profile} »` +
      `${values.offline ? ", hors ligne" : ""}, ${Date.now() - started} ms`,
  );
  console.log(`  ${pdfPath}`);

  await checkGeometry(pdfPath, expectedPageSizePt(print), pageCount);
  if (values.png) await rasterize(pdfPath);
}

async function main(): Promise<void> {
  if (!values.watch) {
    await renderOnce();
    return;
  }

  const { chromium } = await import("playwright-core");
  const browser = await chromium.launch();
  const watched = [
    resolve(TEMPLATE_DIR, "index.html"),
    resolve(TEMPLATE_DIR, "style.css"),
    dataPath ?? resolve(TEMPLATE_DIR, "data.json"),
  ].filter((path) => existsSync(path));

  await renderOnce(browser);
  console.log(`\n👀 surveillance de ${watched.length} fichiers — Ctrl+C pour arrêter`);

  let pending: NodeJS.Timeout | undefined;
  let running = false;

  const rerender = (): void => {
    clearTimeout(pending);
    pending = setTimeout(() => {
      if (running) return;
      running = true;
      renderOnce(browser)
        .catch((error: unknown) => console.error(`✗ ${(error as Error).message}`))
        .finally(() => {
          running = false;
        });
    }, 120);
  };

  for (const path of watched) watch(path, rerender);

  process.on("SIGINT", () => {
    void browser.close().then(() => process.exit(0));
  });
}

await main().catch((error: unknown) => {
  console.error(`✗ ${(error as Error).message}`);
  process.exit(1);
});
