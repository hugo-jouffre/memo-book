import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { PNG } from "pngjs";
import { describe, expect, it } from "vitest";
import { renderBookPdf } from "../src/services/bookPdf.js";

/**
 * Géométrie de la réglure dans le PDF.
 *
 * Ce test existe à cause d'un défaut que rien ne voyait. La réglure du papier
 * était une image de fond CSS ; à l'écran elle était juste, mais **Chromium
 * rastérise les images de fond quand il produit un PDF**. Elle sortait cuite
 * dans un bitmap de 861 × 1219 px — 148 dpi pour une page A5 — avec une
 * période dérivée à 6,24 pt au lieu de 6,00 et un rapport tiret/espace tombé
 * à 50/50. Gros et flou à l'impression, impeccable à l'écran.
 *
 * La suite visuelle ne pouvait pas l'attraper : elle compare des captures
 * d'éléments, jamais la sortie PDF. C'est le chemin qui part chez l'imprimeur
 * qui n'était pas surveillé — le seul qui compte vraiment.
 *
 * On mesure donc la réglure là où elle est imprimée, sur le PDF rastérisé.
 */

/** Le pas de la réglure et le motif du pointillé, en points. */
const LINE = 15.6;
const PERIOD = 6;

/** Tolérance : un pixel à 300 dpi vaut 0,24 pt. On accepte deux pixels. */
const TOLERANCE = 0.5;

const DPI = 300;

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

/** Ordonnées (en points) des lignes de réglure trouvées dans une page rendue. */
function rulingRows(png: PNG): { rows: number[]; dashes: number[]; gaps: number[] } {
  const perPoint = DPI / 72;
  const isRule = (i: number): boolean => {
    // Gris chaud de la réglure (#b6ada1) sur papier blanc, profil « print ».
    const [r, g, b] = [png.data[i]!, png.data[i + 1]!, png.data[i + 2]!];
    return Math.abs(r - 0xb6) + Math.abs(g - 0xad) + Math.abs(b - 0xa1) < 90;
  };

  const rows: number[] = [];
  const dashes: number[] = [];
  const gaps: number[] = [];

  for (let y = 0; y < png.height; y += 1) {
    let hits = 0;
    for (let x = 0; x < png.width; x += 1) if (isRule((y * png.width + x) * 4)) hits += 1;
    if (hits < png.width * 0.1) continue;

    rows.push(y / perPoint);

    // Longueurs des tirets et des intervalles sur cette ligne.
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

describe.runIf(await available())("réglure du PDF", () => {
  it("garde son pas et son pointillé une fois imprimée", async () => {
    const { pdf } = await renderBookPdf({
      payload: TEXT_ONLY,
      profile: "print",
      offline: true,
    });

    const dir = mkdtempSync(join(tmpdir(), "mb-rule-"));
    writeFileSync(resolve(dir, "c.pdf"), pdf);
    // La page 4 porte l'unique journée (couverture, colophon, journée, dos).
    execFileSync("pdftoppm", [
      "-f", "3", "-l", "3", "-r", String(DPI), "-png",
      resolve(dir, "c.pdf"), resolve(dir, "p"),
    ]);

    const png = PNG.sync.read(readFileSync(resolve(dir, "p-3.png")));
    const { rows, dashes, gaps } = rulingRows(png);

    expect(rows.length, "aucune réglure trouvée dans le PDF").toBeGreaterThan(4);

    // Le pas : l'écart entre deux lignes consécutives, groupes de pixels mis à part.
    const starts = rows.filter((y, i) => i === 0 || y - rows[i - 1]! > 1);
    const pitches = starts.slice(1).map((y, i) => y - starts[i]!);

    expect(median(pitches)).toBeCloseTo(LINE, 0);
    expect(Math.abs(median(pitches) - LINE)).toBeLessThan(TOLERANCE);

    // Le pointillé : c'est lui qui partait en vrille quand la réglure était
    // rastérisée — tirets et intervalles ramenés à parts égales.
    const period = median(dashes) + median(gaps);
    expect(
      Math.abs(period - PERIOD),
      `période du pointillé ${period.toFixed(2)} pt au lieu de ${PERIOD} pt. ` +
        `Une décoration a probablement été rastérisée : Chromium cuit les images ` +
        `de fond CSS et les <pattern> SVG en bitmap à l'export PDF. Voir le ` +
        `commentaire de \`.mb-note__rules\` dans style.css.`,
    ).toBeLessThan(TOLERANCE);

    expect(median(dashes)).toBeGreaterThan(median(gaps));
  }, 60_000);
});
