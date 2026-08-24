import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { PNG } from "pngjs";
import { describe, expect, it } from "vitest";
import { renderBookPdf } from "../src/services/bookPdf.js";

/**
 * Ce que le PDF a le droit de contenir.
 *
 * Deux défauts successifs ont motivé ce fichier, tous deux invisibles à
 * l'écran et visibles seulement une fois le carnet exporté.
 *
 * 1. La réglure était une image de fond CSS. **Chromium rastérise les images
 *    de fond quand il produit un PDF** : elle sortait cuite dans un bitmap de
 *    861 × 1219 px — 148 dpi pour une page A5 — période dérivée à 6,24 pt au
 *    lieu de 6,00. Gros et flou à l'impression.
 *
 * 2. La correction — un dégradé horizontal à arrêts `transparent` — a rendu la
 *    géométrie exacte mais a coûté cher : Chromium écrit ce dégradé en shading
 *    enfermé dans un motif de pavage, avec masque de transparence. Le PDF est
 *    passé de 13 à 74 masques et de 0 à 122 shadings. Chez un lecteur qui
 *    n'applique pas les masques, les pointillés disparaissaient et les masques
 *    s'affichaient en aplats gris derrière les images.
 *
 * D'où deux garde-fous : la géométrie de la réglure, et le **budget de
 * transparence** du fichier. Un carnet de texte pur ne doit contenir aucune
 * image, aucun shading, aucun masque — rien qu'un lecteur puisse rater.
 */

/** Le pas de la réglure, en points. */
const LINE = 15.6;

/** Tolérance : un pixel à 300 dpi vaut 0,24 pt. On accepte deux pixels. */
const TOLERANCE = 0.5;

const DPI = 300;

/**
 * Un carnet sans photo, sans fun fact et sans étiquette : donc sans la moindre
 * ombre portée. Une ombre est un flou, elle n'est pas exprimable en vectoriel
 * et Chromium la rastérise à raison — l'exclure du décor permet d'exiger zéro.
 */
const TEXT_ONLY = {
  book_title: "Réglure",
  authors: "Test",
  date_range: "2026",
  days: [
    {
      title: "Une journée de texte",
      layout_story_opener: true,
      body_html:
        "<p>Un récit assez long pour que la réglure se déploie sur plusieurs " +
        "interlignes et qu'on puisse en mesurer le pas sans ambiguïté.</p>" +
        "<p>Un deuxième paragraphe, pour la même raison, avec de quoi " +
        "remplir deux ou trois lignes de plus.</p>" +
        "<p>Et un troisième, pour être tranquille.</p>",
    },
  ],
};

/**
 * Le test demande poppler (`pdftoppm`) en plus du navigateur. Sans l'un ou
 * l'autre il se saute, comme la suite visuelle : mieux vaut une vérification
 * absente qu'une vérification qui ment.
 */
async function available(): Promise<boolean> {
  try {
    execFileSync("pdftoppm", ["-v"], { stdio: "ignore" });
    const { chromium } = await import("playwright-core");
    return existsSync(chromium.executablePath());
  } catch {
    return false;
  }
}

/** Chromium n'utilise pas de flux d'objets : les dictionnaires sont en clair. */
function census(pdf: Buffer): { images: number; shadings: number; masks: number } {
  const raw = pdf.toString("latin1");
  const count = (needle: string): number => raw.split(needle).length - 1;
  return {
    images: count("/Subtype /Image"),
    shadings: count("/PatternType 2"),
    // `/SMask /None` désactive un masque : ce n'en est pas un.
    masks: count("/SMask ") - count("/SMask /None"),
  };
}

/** Lignes de réglure trouvées dans une page rendue, et longueurs des tirets. */
function ruling(png: PNG): { rows: number[]; dashes: number[]; gaps: number[] } {
  const perPoint = DPI / 72;
  const isRule = (i: number): boolean =>
    Math.abs(png.data[i]! - 0xb6) +
      Math.abs(png.data[i + 1]! - 0xad) +
      Math.abs(png.data[i + 2]! - 0xa1) <
    90;

  const rows: number[] = [];
  const dashes: number[] = [];
  const gaps: number[] = [];

  for (let y = 0; y < png.height; y += 1) {
    let hits = 0;
    for (let x = 0; x < png.width; x += 1) if (isRule((y * png.width + x) * 4)) hits += 1;
    if (hits < png.width * 0.1) continue;

    rows.push(y / perPoint);

    let run = 0;
    let gap = 0;
    for (let x = 0; x < png.width; x += 1) {
      if (isRule((y * png.width + x) * 4)) {
        if (gap > 1) gaps.push(gap / perPoint);
        gap = 0;
        run += 1;
      } else {
        if (run > 1) dashes.push(run / perPoint);
        run = 0;
        gap += 1;
      }
    }
  }
  return { rows, dashes, gaps };
}

const median = (xs: number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)] ?? 0;
};

describe.runIf(await available())("PDF du carnet", () => {
  it("garde une réglure vectorielle, au bon pas et bien pointillée", async () => {
    const { pdf } = await renderBookPdf({
      payload: TEXT_ONLY,
      profile: "print",
      offline: true,
    });

    // --- 1. Budget de transparence ------------------------------------------
    const { shadings, masks } = census(pdf);
    const explain =
      "Chromium écrit les dégradés à arrêts `transparent` en shading enfermé " +
      "dans un motif de pavage, masque de transparence à l'appui. Un lecteur " +
      "qui n'applique pas les masques perd alors le décor et affiche les " +
      "masques en aplats gris. Voir le commentaire de `.mb-note__rules`.";

    // Rien dans ce carnet n'a besoin d'un dégradé : zéro, sans discussion.
    // La réglure en dégradé en avait créé 122.
    expect(shadings, `${shadings} shading(s) dans le PDF. ${explain}`).toBe(0);

    // Quelques masques restent légitimes : une ombre portée est un flou, elle
    // n'est pas exprimable en vectoriel. Le budget est là pour attraper une
    // décoration qui en fabriquerait par pleines pages — la réglure en dégradé
    // faisait passer le carnet complet de 13 à 74.
    expect(
      masks,
      `${masks} masques de transparence, budget dépassé. ${explain}`,
    ).toBeLessThanOrEqual(6);

    // --- 2. Géométrie de la réglure -----------------------------------------
    const dir = mkdtempSync(join(tmpdir(), "mb-rule-"));
    writeFileSync(resolve(dir, "c.pdf"), pdf);
    // La page 3 porte l'unique journée (couverture, colophon, journée).
    execFileSync("pdftoppm", [
      "-f", "3", "-l", "3", "-r", String(DPI), "-png",
      resolve(dir, "c.pdf"), resolve(dir, "p"),
    ]);

    const png = PNG.sync.read(readFileSync(resolve(dir, "p-3.png")));
    const { rows, dashes, gaps } = ruling(png);

    expect(rows.length, "aucune réglure trouvée dans le PDF").toBeGreaterThan(4);

    const starts = rows.filter((y, i) => i === 0 || y - rows[i - 1]! > 1);
    const pitch = median(starts.slice(1).map((y, i) => y - starts[i]!));
    expect(
      Math.abs(pitch - LINE),
      `pas de la réglure ${pitch.toFixed(2)} pt au lieu de ${LINE} pt`,
    ).toBeLessThan(TOLERANCE);

    // Elle doit être pointillée, pas pleine : des trous, et plus de trait que
    // de trou. Le motif exact est celui du navigateur, on ne le fige pas.
    expect(gaps.length, "la réglure est un trait plein, pas un pointillé").toBeGreaterThan(0);
    expect(median(dashes)).toBeGreaterThan(median(gaps));
    expect(median(dashes) + median(gaps)).toBeLessThan(8);
  }, 60_000);
});
