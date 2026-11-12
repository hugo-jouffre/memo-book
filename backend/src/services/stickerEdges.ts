import sharp from "sharp";
import {
  stickerArea,
  STICKER_MIN_AREA,
  type StickerCorners,
  type StickerPoint,
  type StickerShape,
} from "./stickerCut.js";

/**
 * **Où est vraiment le billet** (Hugo, 12/11/2026).
 *
 * Le modèle de vision dit *quelle* photo porte un souvenir plat, et à peu
 * près où. Mais « à peu près » ne suffit pas à des ciseaux : à la première
 * vraie photo essayée — une carte d'embarquement AirAsia posée sur une table
 * grise —, il a rendu `0,10 → 0,90` en x et `0,15 → 0,85` en y. Une boîte
 * ronde, centrée, générique. Le sticker en est sorti avec de la table des deux
 * côtés et les deux bouts du billet coupés.
 *
 * Ce n'est pas un mauvais modèle, c'est une mauvaise division du travail :
 * **placer un bord au pixel près n'est pas un travail de modèle de langue.**
 * Les pixels le savent, eux. Un souvenir plat est posé sur une surface unie —
 * une table, un lit, un comptoir — et c'est exactement la situation où une
 * mesure simple bat une estimation.
 *
 * Alors on partage : le modèle **reconnaît**, les pixels **cadrent**.
 *
 * ### Comment
 *
 * 1. La photo, réduite : on cherche un contour, pas un détail.
 * 2. La couleur du fond, prise sur le pourtour — l'objet est au milieu, ce
 *    qui touche les bords est la surface.
 * 3. Le masque : ce qui s'écarte assez de cette couleur.
 * 4. La **tache** : la plus grande forme d'un seul tenant, de préférence celle
 *    que le modèle désignait.
 * 5. Son **rectangle le plus serré**, de travers s'il le faut (enveloppe
 *    convexe puis compas tournant) : c'est lui qui donne les quatre coins.
 *
 * Chaque étape peut renoncer. Elle rend alors `null`, et l'appelant garde les
 * coins du modèle : approximatifs valent mieux qu'absents.
 */

/** Le côté auquel on réduit la photo pour chercher le contour. */
const ANALYSE = 360;

/**
 * L'écart de couleur, sur 255, à partir duquel un pixel n'est plus le fond.
 * 38 : au-dessous, l'ombre portée de l'objet et les reflets de la table
 * entrent dans la tache ; au-dessus, un billet blanc sur un comptoir clair en
 * sort.
 */
const ECART_FOND = 38;

/**
 * La part de la photo que la tache doit occuper pour qu'on y croie. En
 * dessous, on a trouvé une miette ; au-dessus, le masque a pris toute la
 * photo — un fond qui n'était pas uni.
 */
const PART_MIN = 0.03;
const PART_MAX = 0.92;

/**
 * **L'ombre portée n'est pas l'objet.** Un billet posé sur une table projette
 * une ombre d'un ou deux millimètres, assez sombre pour s'écarter du fond :
 * sans ce rabot, le rectangle la contient, et le sticker garde un liseré de
 * table sur deux côtés. Un pixel qui n'a pas ses quatre voisins dans la tache
 * n'en est pas — répété `tours` fois.
 */
function roder(masque: Masque, tours = 2): Masque {
  let { data } = masque;
  const { width, height } = masque;
  for (let tour = 0; tour < tours; tour += 1) {
    const suivant = new Uint8Array(data.length);
    for (let y = 1; y < height - 1; y += 1) {
      for (let x = 1; x < width - 1; x += 1) {
        const p = y * width + x;
        if (data[p] !== 1) continue;
        if (data[p - 1] && data[p + 1] && data[p - width] && data[p + width]) suivant[p] = 1;
      }
    }
    data = suivant;
  }
  return { data, width, height };
}

interface Masque {
  data: Uint8Array;
  width: number;
  height: number;
}

/**
 * La couleur du fond, prise aux **quatre coins** de la photo.
 *
 * Et non sur tout le pourtour, qui semblait plus robuste et ne l'est pas : un
 * billet cadré serré touche le haut et le bas de l'image — la carte
 * d'embarquement d'essai occupait 95 % de la hauteur —, le pourtour devenait
 * majoritairement blanc, et le masque prenait la **table** pour le sujet. Un
 * objet posé à plat n'est presque jamais dans les quatre coins à la fois.
 *
 * Les quatre coins doivent se ressembler : s'ils ne disent pas la même chose,
 * le fond n'est pas uni et la mesure renonce (`null`).
 */
function couleurDuFond(pixels: Buffer, width: number, height: number, canaux: number) {
  const cote = Math.max(3, Math.round(Math.min(width, height) * 0.08));
  const coins = [
    { x0: 0, y0: 0 },
    { x0: width - cote, y0: 0 },
    { x0: 0, y0: height - cote },
    { x0: width - cote, y0: height - cote },
  ];
  const mediane = (liste: number[]) => liste.sort((a, z) => a - z)[Math.floor(liste.length / 2)] ?? 0;

  const moyennes = coins.map(({ x0, y0 }) => {
    const r: number[] = [];
    const g: number[] = [];
    const b: number[] = [];
    for (let y = y0; y < y0 + cote; y += 1) {
      for (let x = x0; x < x0 + cote; x += 1) {
        const i = (y * width + x) * canaux;
        r.push(pixels[i]!);
        g.push(pixels[i + 1]!);
        b.push(pixels[i + 2]!);
      }
    }
    return { r: mediane(r), g: mediane(g), b: mediane(b) };
  });

  const fond = {
    r: mediane(moyennes.map((c) => c.r)),
    g: mediane(moyennes.map((c) => c.g)),
    b: mediane(moyennes.map((c) => c.b)),
  };
  // Un coin qui s'écarte **franchement** de la médiane des quatre : ce n'est
  // pas une surface, ce sont deux. Large, parce qu'un simple dégradé de
  // lumière est déjà rattrapé par l'interpolation ci-dessous.
  const dissident = moyennes.some(
    (c) => Math.hypot(c.r - fond.r, c.g - fond.g, c.b - fond.b) > ECART_FOND * 4,
  );
  return dissident ? null : moyennes;
}

/**
 * Ce qui ne ressemble pas au fond — **un fond qui varie**.
 *
 * Une couleur unique ne suffit pas : une table prise au flash ou près d'une
 * fenêtre s'assombrit d'un bout à l'autre de la photo, et le coin le plus
 * sombre s'écarte alors assez de la médiane pour passer pour l'objet. Sur la
 * carte d'embarquement d'essai, c'est ce qui laissait une bande de table
 * collée sous le billet (Hugo, 12/11/2026 : « le liseré est un défaut »).
 *
 * Le fond attendu en un point est donc l'interpolation des **quatre coins**,
 * chacun pesant d'autant plus qu'on en est proche. Le dégradé s'annule, et il
 * ne reste que ce qui n'est pas la table.
 */
function masqueDuSujet(pixels: Buffer, width: number, height: number, canaux: number): Masque | null {
  const coins = couleurDuFond(pixels, width, height, canaux);
  if (!coins) return null;
  const [hg, hd, bg, bd] = coins as [
    { r: number; g: number; b: number },
    { r: number; g: number; b: number },
    { r: number; g: number; b: number },
    { r: number; g: number; b: number },
  ];

  const data = new Uint8Array(width * height);
  for (let y = 0; y < height; y += 1) {
    const fy = height > 1 ? y / (height - 1) : 0;
    for (let x = 0; x < width; x += 1) {
      const fx = width > 1 ? x / (width - 1) : 0;
      const melange = (c: "r" | "g" | "b") =>
        hg[c] * (1 - fx) * (1 - fy) + hd[c] * fx * (1 - fy) + bg[c] * (1 - fx) * fy + bd[c] * fx * fy;
      const i = (y * width + x) * canaux;
      const dr = pixels[i]! - melange("r");
      const dg = pixels[i + 1]! - melange("g");
      const db = pixels[i + 2]! - melange("b");
      data[y * width + x] = Math.sqrt(dr * dr + dg * dg + db * db) > ECART_FOND ? 1 : 0;
    }
  }
  return { data, width, height };
}

/**
 * La plus grande tache d'un seul tenant, parmi celles qui contiennent le
 * point visé — le centre de ce que le modèle désignait. Faute de tache sous ce
 * point, la plus grande de la photo : le modèle s'est trompé de place, pas
 * d'objet.
 */
function tache(masque: Masque, vise: { x: number; y: number }): number[] | null {
  const { data, width, height } = masque;
  const labels = new Int32Array(width * height).fill(-1);
  const taches: number[][] = [];
  const file = new Int32Array(width * height);

  for (let depart = 0; depart < data.length; depart += 1) {
    if (data[depart] !== 1 || labels[depart] !== -1) continue;
    const rang = taches.length;
    const pixels: number[] = [];
    let tete = 0;
    let queue = 0;
    file[queue++] = depart;
    labels[depart] = rang;
    while (tete < queue) {
      const p = file[tete++]!;
      pixels.push(p);
      const x = p % width;
      const y = (p - x) / width;
      const voisins = [
        x > 0 ? p - 1 : -1,
        x < width - 1 ? p + 1 : -1,
        y > 0 ? p - width : -1,
        y < height - 1 ? p + width : -1,
      ];
      for (const v of voisins) {
        if (v < 0 || data[v] !== 1 || labels[v] !== -1) continue;
        labels[v] = rang;
        file[queue++] = v;
      }
    }
    taches.push(pixels);
  }

  if (taches.length === 0) return null;
  const px = Math.min(width - 1, Math.max(0, Math.round(vise.x * width)));
  const py = Math.min(height - 1, Math.max(0, Math.round(vise.y * height)));
  const sous = labels[py * width + px]!;
  if (sous >= 0) return taches[sous]!;
  return taches.reduce((a, b) => (b.length > a.length ? b : a));
}

/** L'enveloppe convexe d'un nuage de points (chaîne monotone d'Andrew). */
function enveloppe(points: StickerPoint[]): StickerPoint[] {
  const tries = [...points].sort((a, b) => a.x - b.x || a.y - b.y);
  if (tries.length < 3) return tries;
  const croix = (o: StickerPoint, a: StickerPoint, b: StickerPoint) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  const demi = (liste: StickerPoint[]) => {
    const pile: StickerPoint[] = [];
    for (const point of liste) {
      while (pile.length >= 2 && croix(pile[pile.length - 2]!, pile[pile.length - 1]!, point) <= 0) pile.pop();
      pile.push(point);
    }
    pile.pop();
    return pile;
  };
  return [...demi(tries), ...demi([...tries].reverse())];
}

/**
 * **La silhouette, débarrassée de son escalier de pixels.**
 *
 * On enlève, un par un, le sommet dont le retrait coûte le moins d'aire, tant
 * que ça reste négligeable devant la tache. L'enveloppe d'un billet droit a
 * une vingtaine de sommets — l'escalier du masque — et se réduit à ses quatre
 * vrais coins ; celle d'un tampon rond en garde une quinzaine, parce que
 * chaque retrait lui coûterait cher. C'est la forme qui décide du nombre de
 * points, pas nous.
 *
 * ⚠️ **Et surtout pas un rectangle englobant.** C'était la première version,
 * et c'est le défaut que Hugo a vu : un rectangle autour d'un objet un peu
 * trapézoïdal laisse un liseré de table sur un ou deux côtés. La silhouette,
 * elle, ne contient que l'objet.
 */
function simplifier(hull: StickerPoint[], aireTotale: number): StickerPoint[] {
  const points = [...hull];
  // 0,4 % de la tache : assez pour avaler l'escalier des pixels, trop peu
  // pour raboter un coin.
  const tolerance = aireTotale * 0.004;

  while (points.length > 4) {
    let plusPlat = -1;
    let coutMin = Infinity;
    for (let i = 0; i < points.length; i += 1) {
      const a = points[(i - 1 + points.length) % points.length]!;
      const b = points[i]!;
      const c = points[(i + 1) % points.length]!;
      const cout = Math.abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2;
      if (cout < coutMin) {
        coutMin = cout;
        plusPlat = i;
      }
    }
    if (plusPlat < 0 || coutMin > tolerance) break;
    points.splice(plusPlat, 1);
  }
  return points;
}

/**
 * **Resserre les coins du modèle sur l'objet lui-même.** Rend `null` quand la
 * mesure ne conclut pas — l'appelant garde alors les coins du modèle.
 *
 * Ne lève jamais : c'est une amélioration, pas une étape nécessaire.
 */
export async function refineCorners(photo: Buffer, hint: StickerCorners): Promise<StickerShape | null> {
  try {
    const { data, info } = await sharp(photo)
      .rotate()
      .resize({ width: ANALYSE, height: ANALYSE, fit: "inside" })
      .removeAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    const brut = masqueDuSujet(data, info.width, info.height, info.channels);
    if (!brut) return null;
    const masque = roder(brut);
    const centre = {
      x: hint.reduce((somme, point) => somme + point.x, 0) / 4,
      y: hint.reduce((somme, point) => somme + point.y, 0) / 4,
    };
    const trouvee = tache(masque, centre);
    if (!trouvee) return null;

    const part = trouvee.length / (info.width * info.height);
    if (part < PART_MIN || part > PART_MAX) return null;

    const points = trouvee.map((p) => ({ x: p % info.width, y: Math.floor(p / info.width) }));
    const hull = enveloppe(points);
    if (hull.length < 3) return null;

    const forme = simplifier(hull, trouvee.length).map((point) => ({
      x: point.x / info.width,
      y: point.y / info.height,
    }));
    if (forme.some((point) => point.x < -0.01 || point.x > 1.01 || point.y < -0.01 || point.y > 1.01)) {
      return null;
    }

    const aire = stickerArea(forme);
    // Trop petite, on a trouvé une miette ; presque toute la photo, le fond
    // n'était pas celui qu'on croyait. Dans les deux cas le modèle vaut mieux.
    if (aire < STICKER_MIN_AREA || aire > PART_MAX) return null;
    return forme;
  } catch {
    return null;
  }
}
