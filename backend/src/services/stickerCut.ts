/**
 * **Découper un sticker dans une vraie photo** (Hugo, 10/11/2026 — « stickers
 * découpés depuis tes vraies photos de billets et tampons »).
 *
 * Ce fichier ne sait rien des modèles ni de la base : il reçoit une photo et
 * quatre coins, il rend un PNG détouré, bordé de blanc et ombré. C'est le
 * geste d'une paire de ciseaux, et il se teste sans réseau.
 *
 * ### Pourquoi découper, et non faire redessiner
 *
 * La spec d'origine (`docs/sticker-generation.yaml`) confiait le sticker à un
 * modèle d'images. Un modèle d'images **repeint** : un billet de train en
 * ressort avec des dates et un nom de gare inventés. Pour un carnet de
 * voyage, c'est le contraire du but — on imprime un souvenir, pas une
 * illustration de souvenir. Le billet découpé reste le billet (Hugo,
 * 12/11/2026).
 *
 * ### Quatre coins, pas une boîte
 *
 * Un billet posé sur une table est **de travers**. Un rectangle droit autour
 * de lui emporterait la nappe avec ; les quatre coins suivent l'objet, et ce
 * qu'il y a autour s'en va. On ne redresse pas pour autant : un sticker penché
 * est un sticker collé.
 */
import sharp from "sharp";
import type { OutputInfo } from "sharp";

/** Un point de la photo, en fractions de sa largeur et de sa hauteur. */
export interface StickerPoint {
  x: number;
  y: number;
}

/** Les quatre coins de l'objet à découper, dans le sens des aiguilles. */
export type StickerCorners = [StickerPoint, StickerPoint, StickerPoint, StickerPoint];

/**
 * Le plus grand côté d'un sticker fini, en pixels. 900 : à la largeur
 * imprimée d'un sticker (90 pt, soit 3,2 cm) ça laisse plus de 700 dpi — on
 * ne perdra rien à l'impression, et le fichier reste petit.
 */
export const STICKER_MAX_SIDE = 900;

/**
 * La plus petite surface acceptable, en part de la photo. Sous 2 %, le billet
 * est si loin qu'il n'en reste que quelques dizaines de pixels : le sticker
 * serait flou, et personne ne reconnaîtrait ce qu'il montre.
 */
export const STICKER_MIN_AREA = 0.02;

/** La bordure blanche, en part du petit côté du découpage. */
const BORDURE = 0.045;

/** L'ombre portée : son décalage et son flou, en part du petit côté. */
const OMBRE_DECALAGE = 0.025;
const OMBRE_FLOU = 0.03;

/** Le noir de l'ombre. Doux : le carnet est un papier crème, pas un écran. */
const OMBRE_OPACITE = 0.3;

const TRANSPARENT = { r: 0, g: 0, b: 0, alpha: 0 } as const;

/** Un découpage impossible : la photo est illisible, ou les coins ne tiennent pas. */
export class StickerCutError extends Error {}

const borne = (valeur: number, min: number, max: number): number =>
  Math.min(Math.max(valeur, min), max);

/**
 * L'aire d'un quadrilatère, en part de la photo — la formule du lacet. Elle
 * vaut pour un quadrilatère croisé aussi, et c'est voulu : un modèle qui rend
 * des coins dans le désordre produit une aire plus petite, donc un refus.
 */
export function stickerArea(corners: StickerCorners): number {
  let somme = 0;
  for (let i = 0; i < 4; i += 1) {
    const a = corners[i]!;
    const b = corners[(i + 1) % 4]!;
    somme += a.x * b.y - b.x * a.y;
  }
  return Math.abs(somme) / 2;
}

/**
 * Les coins sont-ils utilisables ? Quatre points dans la photo, et un objet
 * qui occupe assez de place pour qu'on le reconnaisse.
 *
 * Séparé du découpage pour que le garde-fou du modèle (`stickerVision.ts`) et
 * les ciseaux lisent **la même règle**.
 */
export function acceptableCorners(corners: unknown): StickerCorners | null {
  if (!Array.isArray(corners) || corners.length !== 4) return null;
  const points: StickerPoint[] = [];
  for (const brut of corners) {
    const point = brut as Record<string, unknown> | null;
    const x = point?.["x"];
    const y = point?.["y"];
    if (typeof x !== "number" || typeof y !== "number") return null;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
    // Un modèle déborde parfois d'un cheveu : on ramène dans la photo plutôt
    // que de jeter un découpage juste pour un 1,02.
    if (x < -0.05 || x > 1.05 || y < -0.05 || y > 1.05) return null;
    points.push({ x: borne(x, 0, 1), y: borne(y, 0, 1) });
  }
  const quadrilatere = points as StickerCorners;
  return stickerArea(quadrilatere) >= STICKER_MIN_AREA ? quadrilatere : null;
}

/** Le PNG d'un sticker, et ce qu'il mesure — le composeur a besoin des deux. */
export interface CutSticker {
  png: Buffer;
  width: number;
  height: number;
}

function polygone(points: StickerPoint[]): string {
  return points.map((p) => `${p.x.toFixed(2)},${p.y.toFixed(2)}`).join(" ");
}

function svg(width: number, height: number, contenu: string): Buffer {
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${contenu}</svg>`,
  );
}

/**
 * **Découpe le sticker.** Rend un PNG à fond transparent : l'objet détouré,
 * une bordure blanche régulière autour, et une ombre douce décalée dessous.
 *
 * Lève une ``StickerCutError`` quand la photo est illisible ou le découpage
 * trop petit — jamais autre chose : l'appelant range l'échec et continue, un
 * sticker manquant n'a jamais empêché un carnet de sortir.
 */
export async function cutSticker(photo: Buffer, corners: StickerCorners): Promise<CutSticker> {
  // `rotate()` sans argument applique l'orientation EXIF. Sans elle, une photo
  // d'iPhone prise à l'horizontale est lue couchée, et les coins tombent à
  // côté — l'erreur silencieuse par excellence.
  let droite: { data: Buffer; info: OutputInfo };
  try {
    droite = await sharp(photo).rotate().toBuffer({ resolveWithObject: true });
  } catch (cause) {
    throw new StickerCutError(`Photo illisible : ${cause instanceof Error ? cause.message : String(cause)}`);
  }

  const { width: largeurPhoto, height: hauteurPhoto } = droite.info;
  const pixels = corners.map((point) => ({
    x: borne(point.x * largeurPhoto, 0, largeurPhoto),
    y: borne(point.y * hauteurPhoto, 0, hauteurPhoto),
  }));

  const gauche = Math.floor(Math.min(...pixels.map((p) => p.x)));
  const haut = Math.floor(Math.min(...pixels.map((p) => p.y)));
  const largeur = Math.ceil(Math.max(...pixels.map((p) => p.x))) - gauche;
  const hauteur = Math.ceil(Math.max(...pixels.map((p) => p.y))) - haut;
  if (largeur < 2 || hauteur < 2) throw new StickerCutError("Découpage vide.");

  const petitCote = Math.min(largeur, hauteur);
  const bordure = Math.max(2, Math.round(petitCote * BORDURE));
  const decalage = Math.max(1, Math.round(petitCote * OMBRE_DECALAGE));
  const flou = Math.max(1, petitCote * OMBRE_FLOU);
  // La marge tient la bordure, l'ombre décalée, et de quoi laisser le flou
  // s'éteindre : une ombre coupée net au bord du PNG se voit.
  const marge = bordure + decalage + Math.ceil(flou * 3);

  const toile = { width: largeur + 2 * marge, height: hauteur + 2 * marge };
  const locaux = pixels.map((p) => ({ x: p.x - gauche + marge, y: p.y - haut + marge }));

  // 1. La photo, recadrée sur la boîte des quatre coins, posée au centre de la
  //    toile — le reste transparent.
  const recadre = await sharp(droite.data)
    .extract({ left: gauche, top: haut, width: largeur, height: hauteur })
    .toBuffer();
  const pose = await sharp({
    create: { ...toile, channels: 4, background: TRANSPARENT },
  })
    .composite([{ input: recadre, left: marge, top: marge }])
    .png()
    .toBuffer();

  // 2. Le détourage : tout ce qui est hors du quadrilatère s'en va. `dest-in`
  //    garde la photo **là où le masque est opaque**.
  const masque = svg(toile.width, toile.height, `<polygon points="${polygone(locaux)}" fill="#fff"/>`);
  const detoure = await sharp(pose)
    .composite([{ input: await sharp(masque).png().toBuffer(), blend: "dest-in" }])
    .png()
    .toBuffer();

  // 3. La bordure blanche : le même quadrilatère, peint en blanc et **tracé**
  //    par-dessus pour déborder de la moitié de l'épaisseur du trait de chaque
  //    côté. Les coins arrondis évitent les pointes d'un angle aigu.
  const blanc = svg(
    toile.width,
    toile.height,
    `<polygon points="${polygone(locaux)}" fill="#fff" stroke="#fff" stroke-width="${bordure * 2}" stroke-linejoin="round"/>`,
  );
  const carte = await sharp(blanc).png().toBuffer();

  // 4. L'ombre : la même forme, en noir, décalée et floutée.
  const ombreForme = svg(
    toile.width,
    toile.height,
    `<polygon points="${polygone(locaux.map((p) => ({ x: p.x + decalage, y: p.y + decalage })))}" fill="#000" fill-opacity="${OMBRE_OPACITE}" stroke="#000" stroke-opacity="${OMBRE_OPACITE}" stroke-width="${bordure * 2}" stroke-linejoin="round"/>`,
  );
  const ombre = await sharp(ombreForme).blur(flou).png().toBuffer();

  // 5. Les trois couches, dans l'ordre où on les regarde.
  const sticker = sharp({ create: { ...toile, channels: 4, background: TRANSPARENT } })
    .composite([{ input: ombre }, { input: carte }, { input: detoure }])
    .png({ compressionLevel: 9 });

  const fini = await (toile.width > STICKER_MAX_SIDE || toile.height > STICKER_MAX_SIDE
    ? sharp(await sticker.toBuffer())
        .resize({ width: STICKER_MAX_SIDE, height: STICKER_MAX_SIDE, fit: "inside" })
        .png({ compressionLevel: 9 })
    : sticker
  ).toBuffer({ resolveWithObject: true });

  return { png: fini.data, width: fini.info.width, height: fini.info.height };
}
