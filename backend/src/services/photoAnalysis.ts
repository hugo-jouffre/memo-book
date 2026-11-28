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
  /**
   * **La netteté mesurée** : la variance de luminance moyenne des neuf cases
   * (T265, 18/11/2026). Elle décidait déjà du verdict `reject`, mais restait
   * à l'intérieur de cette fonction ; il fallait un **chiffre** pour classer
   * des photos entre elles, pas seulement un oui ou un non.
   *
   * C'est un proxy grossier et il le reste : un ciel uni est « moins net »
   * qu'un marché bondé sans être plus flou. Il ne sert donc qu'à départager
   * des photos **du même souvenir**, prises au même endroit dans la même
   * minute — là où il dit à peu près ce qu'on croit qu'il dit.
   */
  detail: number;
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
    detail: Math.round(overall * 100) / 100,
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

/**
 * **Le flou, mesuré pour de vrai** — T310 (28/11/2026).
 *
 * ⚠️ ``detail`` ci-dessus **ne mesure pas la netteté**, malgré son nom et
 * malgré ce que le schéma Prisma et ``docs/photos.md`` ont longtemps annoncé
 * (« variance du laplacien »). ``detailGrid`` calcule la variance de luminance
 * *à l'intérieur* de chaque case, c'est-à-dire le **contraste** : aucune
 * différence entre pixels voisins n'y entre, donc aucune information de
 * netteté. Mesuré le 28/11/2026 sur trois photos réelles, floutées de plus en
 * plus fort :
 *
 * | | laplacien réel | ``detail`` | verdict rendu |
 * |---|---|---|---|
 * | nette | 2 077 | 4 459 | `ok` |
 * | floutée r=2 | 16,6 | 3 462 | `ok` |
 * | floutée r=20 | 0,7 | 1 649 | `ok` |
 *
 * Une photo réduite en bouillie reste donc `ok`, 55 fois au-dessus du seuil ;
 * et un **ciel uni, parfaitement net**, mesure `0.00` et sort `reject`. La
 * mesure condamnait exactement l'inverse de ce qu'on croyait.
 *
 * ## Ce que celle-ci fait
 *
 * On compare l'énergie des bords de la photo à celle de la **même photo
 * re-floutée**. Une photo nette perd beaucoup à ce deuxième flou ; une photo
 * déjà floue n'a plus rien à perdre. Le résultat est un **rapport**, de 0
 * (parfaitement nette) à 1 (bouillie), donc le contraste s'annule : la même
 * photo à 40 % de contraste rend 0,237 au lieu de 0,238. C'était tout le
 * défaut de l'ancienne.
 *
 * Mesuré le 28/11/2026, à la taille de référence :
 *
 * | | nette | flou r=1 | r=2 | r=5 | r=10 |
 * |---|---|---|---|---|---|
 * | trois photos réelles | 0,24 à 0,34 | 0,43 à 0,52 | 0,61 à 0,67 | 0,84 à 0,86 | 0,87 |
 *
 * Et elle tient dans le noir : la même photo ramenée à 12 % de lumière rend
 * 0,271 nette contre 0,590 floutée.
 *
 * ## ⚠️ Le chiffre n'a de sens qu'à une taille fixée
 *
 * Le flou se mesure en pixels, donc il dépend de la taille à laquelle on
 * regarde. La même photo nette rend 0,264 à 400 px de haut et 0,336 à 1920 ;
 * la même floutée, 0,416 et 0,821. Un seuil posé sur des tailles natives
 * différentes ne voudrait donc rien dire, et c'est pourquoi l'appelant réduit
 * d'abord à ``BLUR_REFERENCE_PX``.
 *
 * Ce n'est pas qu'une commodité, c'est **plus juste** : ce qui compte est le
 * flou à la taille où le carnet montre la photo, pas dans ses pixels d'
 * origine. Même doctrine que les dpi (``docs/photos.md``) — « c'est le layout
 * qui fixe l'exigence, pas une valeur absolue ». Un flou de deux pixels sur
 * une photo de 4000 px ne se voit pas imprimé, et la réduction l'efface comme
 * l'impression l'effacera.
 *
 * ## Pas de seuil ici
 *
 * **Rien ne décide encore qu'une photo est trop mauvaise.** Dire « floue » au
 * voyageur demande un seuil, et un seuil demande un vrai lot de photos, dont
 * des photos franchement bougées. La mesure s'écrit en base
 * (``entries.photoBlur``) et attend là son calibrage ; ``photoVerdict`` n'y
 * touche pas.
 */
export const BLUR_REFERENCE_PX = 1200;

/** Rayon du re-flou, en pixels, à la taille de référence. */
const REBLUR_RADIUS = 4;

/** Plan de luminance, un flottant par pixel. */
function lumaPlane(pixels: Uint8Array, width: number, height: number): Float32Array {
  const plane = new Float32Array(width * height);
  for (let i = 0, j = 0; j < plane.length; i += 4, j += 1) {
    plane[j] = 0.299 * pixels[i]! + 0.587 * pixels[i + 1]! + 0.114 * pixels[i + 2]!;
  }
  return plane;
}

/** Flou séparable, horizontal puis vertical : deux passes au lieu d'une carrée. */
function blurPlane(plane: Float32Array, width: number, height: number): Float32Array {
  const pass = (source: Float32Array, horizontal: boolean) => {
    const out = new Float32Array(source.length);
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        let sum = 0;
        let count = 0;
        for (let k = -REBLUR_RADIUS; k <= REBLUR_RADIUS; k += 1) {
          const xx = horizontal ? x + k : x;
          const yy = horizontal ? y : y + k;
          if (xx < 0 || xx >= width || yy < 0 || yy >= height) continue;
          sum += source[yy * width + xx]!;
          count += 1;
        }
        out[y * width + x] = sum / count;
      }
    }
    return out;
  };
  return pass(pass(plane, true), false);
}

/**
 * Somme des variations absolues entre pixels voisins, horizontales et
 * verticales : l'énergie des bords.
 */
function edgeEnergy(plane: Float32Array, width: number, height: number): Float32Array {
  const energy = new Float32Array(plane.length);
  for (let y = 1; y < height; y += 1) {
    for (let x = 1; x < width; x += 1) {
      const i = y * width + x;
      energy[i] = Math.abs(plane[i]! - plane[i - 1]!) + Math.abs(plane[i]! - plane[i - width]!);
    }
  }
  return energy;
}

export interface BlurMeasurement {
  /**
   * De 0 (nette) à 1 (bouillie). `null` quand la photo n'a **aucun bord** à
   * juger — un ciel uni, un mur : elle est peut-être parfaitement nette, et
   * rien dans ses pixels ne permet de le dire. On se taît plutôt que
   * d'accuser.
   */
  blur: number | null;
  /**
   * L'énergie de bord moyenne par pixel, gardée pour calibrer. Repères du
   * 28/11/2026 à la taille de référence : ciel uni `0.000`, dégradé doux
   * `0.075`, photo nette de nuit `0.798`, photo nette `6.537`.
   */
  edges: number;
}

/**
 * Mesure le flou d'un bitmap **déjà réduit à ``BLUR_REFERENCE_PX``**.
 *
 * À appeler sur le bitmap que l'appelant a déjà en main : la mesure coûte
 * environ 60 ms à la taille de référence, contre 630 ms à 2400 px — et à
 * 2400 px le chiffre ne serait pas comparable d'une photo à l'autre.
 */
export function blurOf(pixels: Uint8Array, width: number, height: number): BlurMeasurement {
  const plane = lumaPlane(pixels, width, height);
  const original = edgeEnergy(plane, width, height);
  const reblurred = edgeEnergy(blurPlane(plane, width, height), width, height);

  let total = 0;
  let lost = 0;
  for (let i = 0; i < original.length; i += 1) {
    const o = original[i]!;
    total += o;
    lost += Math.max(0, o - reblurred[i]!);
  }

  const edges = Math.round((total / original.length) * 1000) / 1000;
  // Aucun bord : le rapport n'existe pas, et l'inventer accuserait un ciel.
  if (total === 0) return { blur: null, edges };
  return { blur: Math.round(((total - lost) / total) * 1000) / 1000, edges };
}
