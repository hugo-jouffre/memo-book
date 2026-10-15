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
  try {
    // Import paresseux, comme `photoAnalysis` : `jimp` est lourd à charger, et
    // la plupart des requêtes n'en ont pas besoin.
    const { Jimp } = await import("jimp");
    const image = await Jimp.fromBuffer(buffer);
    width = image.bitmap.width;
    height = image.bitmap.height;
  } catch {
    return null;
  }

  if (!width || !height) return null;
  return { widthPx: width, heightPx: height, isLandscape: width >= height };
}
