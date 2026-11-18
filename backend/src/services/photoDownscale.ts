import sharp from "sharp";

/**
 * **La copie allégée qu'on sert au moteur de PDF** (Hugo, 14/11/2026 — « ça a
 * galéré à créer le PDF, j'ai dû fermer l'app 4-5 fois pour que ça finisse par
 * marcher »).
 *
 * APITemplate ne reçoit pas les photos : il reçoit leurs **adresses**, et va
 * les télécharger depuis ses serveurs avant de composer. Tant que ces adresses
 * ne résolvaient pas, il échouait en quelques millisecondes et sortait un
 * carnet aux cadres vides — vite, et faux (`services/renderPhotos.ts`). Le
 * jour où elles sont devenues bonnes, il s'est mis à tirer pour de vrai : un
 * carnet de soixante-et-onze photos d'iPhone, c'est **306 Mo**, 4,4 Mo en
 * moyenne et jusqu'à 9,4 Mo pièce. Trois compositions de suite, trois
 * HTTP 504.
 *
 * D'où ce fichier : la photo part en 2400 px de grand côté, quelques centaines
 * de kilo-octets. L'original ne bouge pas — c'est une **copie**, retenue sur
 * `media_assets.renderStorageKey`, fabriquée une fois et resservie ensuite.
 *
 * Ce fichier ne sait rien du stockage ni de la base : il reçoit des octets, il
 * en rend d'autres. C'est `renderPhotos.ts` qui range la copie.
 */

/**
 * Le plus grand côté d'une photo envoyée au moteur de PDF, en pixels.
 *
 * 2400 : une photo qui occupe toute la largeur d'une page A4 (210 mm) est
 * encore tirée à 290 dpi, et à 580 dpi sur une page A5 — au-delà de ce que
 * l'imprimeur restitue. En dessous de 2000, une pleine page commencerait à se
 * voir ; au-dessus de 3000, on repaie le problème qu'on vient de régler.
 */
export const RENDER_MAX_SIDE = 2400;

/**
 * Qualité JPEG de la copie. 82 plutôt que les 90 de `photoFormat.ts` : celle-ci
 * est **réencodée depuis un JPEG déjà encodé**, et c'est le poids qui est en
 * jeu. L'écart ne se voit pas sur une photo imprimée ; il vaut un bon tiers du
 * fichier.
 */
export const RENDER_JPEG_QUALITY = 82;

/**
 * En dessous de ce poids, on sert l'original : réencoder lui ferait perdre de
 * la matière sans rien gagner sur le temps de téléchargement. 900 Ko, c'est
 * déjà moins d'une seconde de transfert, et soixante-dix photos de ce
 * calibre tiennent largement dans la fenêtre d'APITemplate.
 */
export const RENDER_MAX_BYTES = 900_000;

/**
 * Le plus grand côté d'une **vignette d'écran**, en pixels (T260).
 *
 * 900 : un plat de couverture fait 208 pt de large, soit 624 px sur une dalle
 * à 3×, et 882 px de haut. 900 couvre donc le plus grand des deux côtés du
 * plus grand usage de l'app — en dessous, une photo pleine page de plat
 * commencerait à se voir.
 *
 * ⚠️ **Ce n'est pas la copie du carnet** (`RENDER_MAX_SIDE`, 2400 px). Celle-là
 * part à l'imprimeur et doit tenir le papier ; celle-ci se regarde sur un
 * téléphone et doit arriver vite. Mesuré le 17/11/2026 : 34 Ko contre 314, et
 * 47 ms à fabriquer contre 246.
 */
export const THUMB_MAX_SIDE = 900;

/** Qualité JPEG d'une vignette. Elle se regarde à 208 pt : 78 ne se voit pas. */
export const THUMB_JPEG_QUALITY = 78;

/**
 * En dessous de ce poids, on sert l'originale : une photo de 80 Ko est déjà
 * une vignette, et la réencoder ne ferait que lui enlever de la matière.
 */
export const THUMB_MAX_BYTES = 120_000;

export interface DownscaledPhoto {
  buffer: Buffer;
  /** Le nom à donner au stockage — l'extension doit dire la vérité. */
  filename: string;
  mimeType: "image/jpeg";
  widthPx: number;
  heightPx: number;
}

/**
 * Rend une copie allégée de la photo, ou `null` quand il n'y a rien à gagner.
 *
 * `null` dans trois cas, et aucun n'est une erreur :
 * - la photo est **déjà légère** (`RENDER_MAX_BYTES`) ;
 * - la copie ne serait **pas plus petite** que l'original — une image déjà
 *   compressée au maximum, ou si petite que l'en-tête JPEG pèse le plus lourd ;
 * - les octets sont **illisibles** pour sharp. L'appelant sert alors
 *   l'original, comme avant : un carnet avec des photos lourdes vaut mieux
 *   qu'un carnet sans photos.
 *
 * ⚠️ **`rotate()` n'est pas décoratif.** Une photo prise à la verticale avec un
 * iPhone est stockée en pixels horizontaux, avec un drapeau EXIF qui dit de la
 * tourner — voir `services/photoOrientation.ts`. sharp **n'applique pas** ce
 * drapeau de lui-même et **efface** les métadonnées en sortie : sans
 * `rotate()`, la copie partirait couchée dans le carnet, et personne ne saurait
 * pourquoi. L'appeler grave la rotation dans les pixels, ce qui rend le drapeau
 * inutile.
 *
 * Les métadonnées partent avec, et c'est tant mieux : ces adresses sont
 * publiques le temps d'une composition, et les coordonnées GPS d'un souvenir
 * n'ont rien à y faire.
 */
export async function downscaleForRender(buffer: Buffer): Promise<DownscaledPhoto | null> {
  return downscale(buffer, {
    maxSide: RENDER_MAX_SIDE,
    quality: RENDER_JPEG_QUALITY,
    keepBelowBytes: RENDER_MAX_BYTES,
    filename: "photo.jpg",
  });
}

/**
 * Rend la **vignette d'écran** d'une photo, ou `null` quand il n'y a rien à
 * gagner (T260). Mêmes trois `null` que ci-dessus, et pour les mêmes raisons.
 *
 * C'est elle que l'app reçoit pour l'écran des couvertures ; l'originale reste
 * en stock, et c'est toujours elle qui part au carnet.
 */
export async function downscaleForScreen(buffer: Buffer): Promise<DownscaledPhoto | null> {
  return downscale(buffer, {
    maxSide: THUMB_MAX_SIDE,
    quality: THUMB_JPEG_QUALITY,
    keepBelowBytes: THUMB_MAX_BYTES,
    filename: "vignette.jpg",
  });
}

interface DownscaleOptions {
  maxSide: number;
  quality: number;
  /** En dessous de ce poids, l'originale fait déjà l'affaire. */
  keepBelowBytes: number;
  filename: string;
}

async function downscale(
  buffer: Buffer,
  { maxSide, quality, keepBelowBytes, filename }: DownscaleOptions,
): Promise<DownscaledPhoto | null> {
  if (buffer.byteLength <= keepBelowBytes) return null;

  try {
    const { data, info } = await sharp(buffer)
      .rotate()
      .resize({ width: maxSide, height: maxSide, fit: "inside", withoutEnlargement: true })
      .jpeg({ quality, mozjpeg: true })
      .toBuffer({ resolveWithObject: true });

    if (data.byteLength >= buffer.byteLength) return null;

    return {
      buffer: data,
      filename,
      mimeType: "image/jpeg",
      widthPx: info.width,
      heightPx: info.height,
    };
  } catch {
    return null;
  }
}
