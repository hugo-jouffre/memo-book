import {
  BLUR_REFERENCE_PX,
  analysePixels,
  blurOf,
  type BlurMeasurement,
  type PhotoAnalysis,
} from "./photoAnalysis.js";

/**
 * **Une photo est-elle au format paysage ?** — la mesure qui décide de la
 * couverture d'un voyage (Hugo, 15/10/2026).
 *
 * La règle produit tient en une phrase : la couverture d'un voyage est la plus
 * récente de ses photos **paysage**, et aucune s'il n'en a pas. Elle ne demande
 * qu'une chose du serveur, mais il ne faut pas se tromper dessus : savoir dans
 * quel sens une photo se regarde.
 *
 * **Paysage, parce que la couverture dont il s'agit est la carte du voyage** —
 * large, sur l'accueil comme en tête de l'écran du voyage. Une photo verticale
 * s'y recadre en une bande prise au milieu. La couverture *imprimée* du
 * carnet, elle, est verticale, et c'est bien une autre chose : elle a son
 * parcours à part, où l'on dépose ses photos exprès (`routes/covers.ts`).
 *
 * ⚠️ **Les pixels ne disent pas le sens.** Une photo prise à la verticale avec
 * un iPhone est stockée en pixels *horizontaux*, avec un drapeau EXIF qui dit
 * de la tourner à l'affichage — c'est vrai du fichier de la photothèque comme
 * de ce que `UIImage.jpegData` réécrit. Lire les dimensions sans le drapeau
 * ferait donc passer les photos portrait pour des paysages, et la couverture
 * choisirait exactement l'inverse de ce qu'on lui demande.
 *
 * **`jimp` applique le drapeau lui-même** : un JPEG de 120 × 60 pixels marqué
 * « orientation 6 » arrive en bitmap de 60 × 120 (vérifié le 15/10/2026,
 * jimp 1.6). On ne corrige donc rien par-dessus — ce serait tourner deux fois.
 * Mais c'est un comportement **implicite**, que rien dans l'appel ne rappelle
 * et qu'une montée de version peut retirer sans bruit : les tests de ce
 * fichier l'épinglent exprès, avec des JPEG dont ils écrivent l'EXIF à la
 * main. S'ils tombent après un `npm update`, c'est ici qu'il faut remettre la
 * rotation, pas dans l'appelant.
 */

export interface PhotoMeasurement {
  /** Largeur **vue**, drapeau EXIF appliqué. */
  widthPx: number;
  /** Hauteur **vue**, drapeau EXIF appliqué. */
  heightPx: number;
  /**
   * Au format paysage, donc utilisable en couverture.
   *
   * Carré compris : un 1:1 posé sur une carte large perd un peu de ses bords,
   * jamais son sujet, et le refuser priverait de couverture un voyage raconté
   * en photos d'Instagram.
   */
  isLandscape: boolean;

  /**
   * **La netteté mesurée**, et le verdict qui en découle (T265, 18/11/2026).
   *
   * Tirés du **même décodage** que les dimensions : `jimp` a déjà le bitmap
   * en main, et le calcul est une moyenne de variances sur neuf cases. Les
   * obtenir ici ne coûte donc rien de plus qu'ici — les demander plus tard
   * aurait voulu dire relire la photo depuis le stockage, une par une, au
   * moment de composer.
   *
   * Ils servent à **choisir quelles photos le carnet montre** quand une étape
   * en porte plus que sa mise en page n'en dessine
   * (`services/photoPicking.ts`). Avant, c'étaient les premières arrivées.
   */
  sharpness: number;
  verdict: "ok" | "upscale" | "downgrade" | "reject";

  /**
   * **Le flou, lui, mesuré pour de vrai** (T310, 28/11/2026) : de 0 (nette) à
   * 1 (bouillie), `null` quand la photo n'a aucun bord à juger.
   *
   * ⚠️ Ne pas confondre avec ``sharpness`` juste au-dessus, qui porte mal son
   * nom : il mesure le **contraste** et ne voit pas le flou du tout — voir
   * ``blurOf`` pour les chiffres. Les deux cohabitent le temps que ce
   * chiffre-ci soit calibré sur un vrai lot de photos ; ``verdict`` ne s'en
   * sert pas encore.
   *
   * Pris sur le bitmap **réduit à ``BLUR_REFERENCE_PX``**, parce qu'un flou se
   * mesure en pixels : sans taille fixée, deux photos ne seraient pas
   * comparables. Une photo plus petite que la référence est mesurée telle
   * quelle, jamais agrandie — elle rend alors un chiffre un peu plus
   * indulgent (0,264 à 400 px contre 0,336 à 1920 pour la même photo nette),
   * donc elle sera ratée plutôt qu'accusée à tort.
   */
  blur: number | null;
}

/**
 * Mesure une photo, ou rend `null` si on ne sait pas la lire.
 *
 * `null` n'est pas une erreur : un format que `jimp` ne décode pas — le HEIC
 * en premier — laisse simplement la photo **sans mesure**, donc hors course
 * pour la couverture. Mieux vaut un voyage qui garde son motif qu'une
 * couverture tirée au sort.
 */
export async function measurePhoto(buffer: Buffer): Promise<PhotoMeasurement | null> {
  let width: number;
  let height: number;
  let analyse: PhotoAnalysis;
  let mesureDuFlou: BlurMeasurement;
  try {
    // Import paresseux, comme `photoAnalysis` : `jimp` est lourd à charger, et
    // la plupart des requêtes n'en ont pas besoin.
    const { Jimp } = await import("jimp");
    const image = await Jimp.fromBuffer(buffer);
    width = image.bitmap.width;
    height = image.bitmap.height;
    // Le bitmap est là : la netteté se mesure dans la même passe (T265).
    analyse = analysePixels(new Uint8Array(image.bitmap.data), width, height);
    // Le flou, lui, se mesure à taille fixée (T310) : on réduit une copie, et
    // on ne l'agrandit jamais. `resize` écrit dans l'image qu'on lui donne,
    // d'où la copie — l'originale sert encore au-dessus.
    const grandCote = Math.max(width, height);
    const reduite =
      grandCote > BLUR_REFERENCE_PX
        ? image
            .clone()
            .resize(
              width >= height ? { w: BLUR_REFERENCE_PX } : { h: BLUR_REFERENCE_PX },
            )
        : image;
    mesureDuFlou = blurOf(
      new Uint8Array(reduite.bitmap.data),
      reduite.bitmap.width,
      reduite.bitmap.height,
    );
  } catch {
    return null;
  }

  if (!width || !height) return null;
  return {
    widthPx: width,
    heightPx: height,
    isLandscape: width >= height,
    sharpness: analyse.detail,
    verdict: analyse.verdict,
    blur: mesureDuFlou.blur,
  };
}
