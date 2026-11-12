import { describe, expect, it } from "vitest";
import sharp from "sharp";
import { refineCorners } from "../src/services/stickerEdges.js";
import { stickerArea, type StickerCorners, type StickerShape } from "../src/services/stickerCut.js";

/**
 * **Où est vraiment le billet** (Hugo, 12/11/2026).
 *
 * Ces cas tiennent la division du travail : le modèle reconnaît, les pixels
 * cadrent. Ils partent tous d'une indication **volontairement mauvaise** —
 * celle que le vrai modèle a rendue sur la carte d'embarquement d'essai, une
 * boîte ronde et centrée — et vérifient que la mesure la corrige, ou qu'elle
 * renonce proprement.
 */

/** L'indication du modèle : une boîte générique, qui déborde de partout. */
const BOITE_MOLLE: StickerCorners = [
  { x: 0.1, y: 0.15 },
  { x: 0.9, y: 0.15 },
  { x: 0.9, y: 0.85 },
  { x: 0.1, y: 0.85 },
];

/** Un objet clair posé sur une surface unie, éventuellement de travers. */
async function objetSurTable({
  angle = 0,
  largeur = 240,
  hauteur = 150,
  fond = { r: 90, g: 92, b: 96 },
  bicolore = false,
  degrade = false,
}): Promise<Buffer> {
  const objet = await sharp({
    create: { width: largeur, height: hauteur, channels: 4, background: { r: 245, g: 244, b: 238, alpha: 1 } },
  })
    .png()
    .toBuffer();
  const penche = await sharp(objet)
    .rotate(angle, { background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .toBuffer();
  const taille = await sharp(penche).metadata();

  // Un fond **bicolore** : une table sombre et une nappe claire, chacune sur
  // la moitié de la photo. Les quatre coins ne disent alors pas la même
  // chose, et il n'y a pas de « couleur du fond » à soustraire.
  // ⚠️ Un seul `composite` : un second appel **remplace** le premier dans
  // sharp, il ne s'y ajoute pas.
  const couches = [
    // Une table qui s'assombrit vers le bas : la lumière d'une fenêtre, ou un
    // flash. C'est ce qui laissait une bande de table collée sous le billet.
    ...(degrade
      ? [
          {
            input: Buffer.from(
              `<svg width="600" height="450"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">` +
                `<stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.45"/>` +
                `</linearGradient></defs><rect width="600" height="450" fill="url(#g)"/></svg>`,
            ),
          },
        ]
      : []),
    ...(bicolore
      ? [
          {
            input: Buffer.from(
              `<svg width="600" height="450"><rect x="300" y="0" width="300" height="450" fill="#e8e2d4"/></svg>`,
            ),
          },
        ]
      : []),
    { input: penche, left: Math.round((600 - taille.width) / 2), top: Math.round((450 - taille.height) / 2) },
  ];

  return sharp({ create: { width: 600, height: 450, channels: 3, background: fond } })
    .composite(couches)
    .jpeg({ quality: 95 })
    .toBuffer();
}

/** La boîte englobante d'une forme, en fractions. */
function boite(corners: StickerShape) {
  const xs = corners.map((point) => point.x);
  const ys = corners.map((point) => point.y);
  return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
}

describe("resserrer les coins sur l'objet", () => {
  it("colle au bord d'un objet droit, là où le modèle donnait une boîte molle", async () => {
    const photo = await objetSurTable({});
    const coins = await refineCorners(photo, BOITE_MOLLE);
    expect(coins).not.toBeNull();

    // L'objet fait 240 × 150 au milieu d'une photo de 600 × 450 : il occupe
    // donc x de 0,30 à 0,70 et y de 0,33 à 0,67. À deux points de pourcentage.
    const trouve = boite(coins!);
    expect(trouve.x0).toBeCloseTo(0.3, 1);
    expect(trouve.x1).toBeCloseTo(0.7, 1);
    expect(trouve.y0).toBeCloseTo(0.333, 1);
    expect(trouve.y1).toBeCloseTo(0.667, 1);

    // Et c'est bien plus serré que ce que le modèle proposait.
    expect(stickerArea(coins!)).toBeLessThan(stickerArea(BOITE_MOLLE));
  });

  /**
   * Le cas qui justifie tout le fichier : un rectangle **penché** dont une
   * boîte droite emporterait les quatre coins de table.
   */
  it("suit un objet de travers au lieu de l'encadrer droit", async () => {
    const photo = await objetSurTable({ angle: 20 });
    const coins = await refineCorners(photo, BOITE_MOLLE);
    expect(coins).not.toBeNull();

    // Le quadrilatère trouvé est nettement plus petit que sa propre boîte
    // droite : c'est la signature d'un rectangle incliné.
    const droite = boite(coins!);
    const aireDroite = (droite.x1 - droite.x0) * (droite.y1 - droite.y0);
    expect(stickerArea(coins!)).toBeLessThan(aireDroite * 0.85);

    // Et il penche vraiment : aucun de ses côtés n'est horizontal.
    const horizontaux = coins!.filter((point, i) => {
      const suivant = coins![(i + 1) % coins!.length]!;
      const pente = Math.abs(Math.atan2(suivant.y - point.y, suivant.x - point.x) * (180 / Math.PI)) % 180;
      return pente < 5 || pente > 175;
    });
    expect(horizontaux).toHaveLength(0);
  });

  /**
   * Un fond bruité ne l'arrête pas, lui : la médiane des coins le traverse, et
   * c'est tant mieux. Ce qui l'arrête, c'est un fond qui n'a pas **une**
   * couleur.
   */
  it("renonce quand le fond n'est pas uni — les coins du modèle valent mieux", async () => {
    const photo = await objetSurTable({ bicolore: true });
    expect(await refineCorners(photo, BOITE_MOLLE)).toBeNull();
  });

  /**
   * Le défaut que Hugo a vu sur sa carte d'embarquement (12/11/2026) : la
   * table s'assombrissait vers le bas, le coin sombre passait pour l'objet, et
   * le sticker gardait une bande de table collée dessous. Le fond est
   * désormais interpolé entre les quatre coins.
   */
  it("traverse un fond qui s'assombrit, sans emporter la table avec", async () => {
    const photo = await objetSurTable({ degrade: true });
    const coins = await refineCorners(photo, BOITE_MOLLE);
    expect(coins).not.toBeNull();

    const trouve = boite(coins!);
    // L'objet, et rien que lui : pas de bande jusqu'au bas de la photo.
    expect(trouve.y1).toBeLessThan(0.72);
    expect(trouve.x0).toBeCloseTo(0.3, 1);
    expect(trouve.x1).toBeCloseTo(0.7, 1);
  });

  /**
   * **Une silhouette, et non un rectangle englobant.** Un objet trapézoïdal —
   * un billet vu de biais — laisse de la table dans les coins d'un rectangle ;
   * la forme, elle, n'en contient pas.
   */
  it("suit un objet trapézoïdal au lieu de l'encadrer", async () => {
    const trapeze = Buffer.from(
      `<svg width="600" height="450"><polygon points="180,140 430,120 460,330 150,310" fill="#f5f4ee"/></svg>`,
    );
    const photo = await sharp({
      create: { width: 600, height: 450, channels: 3, background: { r: 90, g: 92, b: 96 } },
    })
      .composite([{ input: trapeze }])
      .jpeg({ quality: 95 })
      .toBuffer();

    const coins = await refineCorners(photo, BOITE_MOLLE);
    expect(coins).not.toBeNull();
    // Peu de points — la forme décide, et un trapèze en demande quatre ou
    // cinq —, et une aire franchement plus petite que la boîte droite qui les
    // contient : c'est la signature d'un trapèze suivi de près.
    expect(coins!.length).toBeLessThanOrEqual(6);
    const droite = boite(coins!);
    const aireDroite = (droite.x1 - droite.x0) * (droite.y1 - droite.y0);
    expect(stickerArea(coins!)).toBeLessThan(aireDroite * 0.95);
  });

  it("renonce sur une photo sans objet : il n'y a rien à resserrer", async () => {
    const uni = await sharp({
      create: { width: 600, height: 450, channels: 3, background: { r: 90, g: 92, b: 96 } },
    })
      .jpeg()
      .toBuffer();
    expect(await refineCorners(uni, BOITE_MOLLE)).toBeNull();
  });

  it("ne lève jamais : une photo illisible rend simplement « rien »", async () => {
    expect(await refineCorners(Buffer.from("pas une photo"), BOITE_MOLLE)).toBeNull();
  });
});
