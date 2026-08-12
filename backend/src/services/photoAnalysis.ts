/**
 * Analyse des photos avant mise en page.
 *
 * Deux questions, une seule mesure : où poser le scotch sans masquer
 * l'essentiel, et sur quoi centrer le recadrage. Un scotch posé au hasard
 * finit un jour sur un visage, et `object-fit: cover` centré coupe la moitié
 * des photos verticales.
 *
 * La mesure est une **carte de détail** : on découpe l'image en cases et on
 * calcule la variance de luminance dans chacune. Une case très uniforme (ciel,
 * mur, sable) ne porte rien d'important ; une case agitée porte le sujet. Ce
 * n'est pas de la détection de visage — c'est un proxy grossier, mais il ne
 * demande aucun modèle, tourne en quelques millisecondes et se trompe dans le
 * sens inoffensif : au pire le scotch se pose sur une zone un peu moins vide.
 *
 * La vraie détection de visage (Vision côté iOS) viendra la compléter : elle
 * fournira des boîtes à préserver qui, elles, sont interdites au scotch.
 * Voir docs/photos.md.
 */

export type TapeCorner = "top-left" | "top-right" | "bottom-left" | "bottom-right" | "top";

export interface PhotoAnalysis {
  /** Coin le plus vide, où poser le scotch. */
  tapeCorner: TapeCorner;
  /** Point d'intérêt, en pourcentages, prêt pour `object-position`. */
  focus: string;
  /** Côté long / côté court, pour choisir un emplacement adapté. */
  aspectRatio: number;
  width: number;
  height: number;
  /** Résolution effective à la taille d'affichage prévue, en dpi. */
  dpi?: number;
  verdict: "ok" | "upscale" | "downgrade" | "reject";
}

const GRID = 3;

/** Seuil de netteté sous lequel une photo est refusée. Calibré à revoir. */
const MIN_DETAIL = 30;

/** Une photo imprimée sous 200 dpi pixellise à l'œil nu. */
const MIN_DPI = 200;

interface Cell {
  row: number;
  column: number;
  variance: number;
}

/** Variance de luminance par case d'une grille 3 × 3. */
function detailGrid(pixels: Uint8Array, width: number, height: number): Cell[] {
  const cells: Cell[] = [];
  const cellW = Math.max(1, Math.floor(width / GRID));
  const cellH = Math.max(1, Math.floor(height / GRID));

  for (let row = 0; row < GRID; row += 1) {
    for (let column = 0; column < GRID; column += 1) {
      let sum = 0;
      let sumSquares = 0;
      let count = 0;

      const x0 = column * cellW;
      const y0 = row * cellH;
      const x1 = column === GRID - 1 ? width : x0 + cellW;
      const y1 = row === GRID - 1 ? height : y0 + cellH;

      // Un pixel sur quatre suffit pour une variance : l'analyse doit rester
      // négligeable devant le rendu.
      for (let y = y0; y < y1; y += 2) {
        for (let x = x0; x < x1; x += 2) {
          const i = (y * width + x) * 4;
          const luma = 0.299 * pixels[i]! + 0.587 * pixels[i + 1]! + 0.114 * pixels[i + 2]!;
          sum += luma;
          sumSquares += luma * luma;
          count += 1;
        }
      }

      const mean = sum / (count || 1);
      cells.push({ row, column, variance: sumSquares / (count || 1) - mean * mean });
    }
  }
  return cells;
}

const CORNERS: { corner: TapeCorner; row: number; column: number }[] = [
  { corner: "top-left", row: 0, column: 0 },
  { corner: "top-right", row: 0, column: GRID - 1 },
  { corner: "bottom-left", row: GRID - 1, column: 0 },
  { corner: "bottom-right", row: GRID - 1, column: GRID - 1 },
];

export interface AnalyseOptions {
  /** Hauteur d'affichage prévue, en points. Sert à juger la résolution. */
  displayHeightPt?: number;
}

/** Analyse une image déjà décodée en RGBA. */
export function analysePixels(
  pixels: Uint8Array,
  width: number,
  height: number,
  options: AnalyseOptions = {},
): PhotoAnalysis {
  const cells = detailGrid(pixels, width, height);
  const cellAt = (row: number, column: number): Cell =>
    cells.find((c) => c.row === row && c.column === column)!;

  // Scotch : le coin dont la case est la plus calme.
  const quietest = CORNERS.map((c) => ({ ...c, variance: cellAt(c.row, c.column).variance })).sort(
    (a, b) => a.variance - b.variance,
  )[0]!;

  // Recadrage : la case la plus détaillée porte le sujet.
  const busiest = [...cells].sort((a, b) => b.variance - a.variance)[0]!;
  const focusX = Math.round(((busiest.column + 0.5) / GRID) * 100);
  const focusY = Math.round(((busiest.row + 0.5) / GRID) * 100);

  const overall = cells.reduce((sum, c) => sum + c.variance, 0) / cells.length;

  let verdict: PhotoAnalysis["verdict"] = "ok";
  let dpi: number | undefined;

  if (options.displayHeightPt) {
    dpi = Math.round(height / (options.displayHeightPt / 72));
    if (dpi < MIN_DPI) verdict = "upscale";
  }
  // Le flou prime : agrandir une photo floue ne fait qu'amplifier le flou.
  if (overall < MIN_DETAIL) verdict = "reject";

  return {
    tapeCorner: quietest.corner,
    focus: `${focusX}% ${focusY}%`,
    aspectRatio: Math.round((width / height) * 100) / 100,
    width,
    height,
    ...(dpi === undefined ? {} : { dpi }),
    verdict,
  };
}

/** Décode puis analyse une image. `jimp` est en pur JS : aucun binaire natif. */
export async function analyseImage(
  source: Buffer | string,
  options: AnalyseOptions = {},
): Promise<PhotoAnalysis> {
  const { Jimp } = await import("jimp");
  const image = typeof source === "string" ? await Jimp.read(source) : await Jimp.fromBuffer(source);
  const { width, height, data } = image.bitmap;
  return analysePixels(new Uint8Array(data), width, height, options);
}
