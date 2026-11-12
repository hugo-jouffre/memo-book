import sharp from "sharp";
import { acceptableCorners, stickerArea, type StickerCorners, type StickerPoint } from "./stickerCut.js";

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
  // Un coin qui s'écarte franchement de la médiane des quatre : ce n'est pas
  // une surface unie, et tout le reste du raisonnement s'écroulerait.
  const dissident = moyennes.some(
    (c) => Math.hypot(c.r - fond.r, c.g - fond.g, c.b - fond.b) > ECART_FOND * 2,
  );
  return dissident ? null : fond;
}

/** Ce qui ne ressemble pas au fond. */
function masqueDuSujet(pixels: Buffer, width: number, height: number, canaux: number): Masque | null {
  const fond = couleurDuFond(pixels, width, height, canaux);
  if (!fond) return null;
  const data = new Uint8Array(width * height);
  for (let p = 0; p < width * height; p += 1) {
    const i = p * canaux;
    const dr = pixels[i]! - fond.r;
    const dg = pixels[i + 1]! - fond.g;
    const db = pixels[i + 2]! - fond.b;
    data[p] = Math.sqrt(dr * dr + dg * dg + db * db) > ECART_FOND ? 1 : 0;
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
 * Le rectangle le plus serré autour d'une enveloppe, **de travers s'il le
 * faut** : un rectangle d'aire minimale a toujours un côté le long d'une arête
 * de l'enveloppe (compas tournant). C'est ce qui suit un billet posé en
 * biais, là où une boîte droite emporterait la table de chaque côté.
 */
function rectangleLePlusServre(hull: StickerPoint[]): StickerCorners | null {
  if (hull.length < 3) return null;
  let meilleur: { aire: number; coins: StickerCorners } | null = null;

  for (let i = 0; i < hull.length; i += 1) {
    const a = hull[i]!;
    const b = hull[(i + 1) % hull.length]!;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const longueur = Math.hypot(dx, dy);
    if (longueur < 1e-9) continue;
    const ux = dx / longueur;
    const uy = dy / longueur;

    let uMin = Infinity;
    let uMax = -Infinity;
    let vMin = Infinity;
    let vMax = -Infinity;
    for (const point of hull) {
      const u = point.x * ux + point.y * uy;
      const v = -point.x * uy + point.y * ux;
      uMin = Math.min(uMin, u);
      uMax = Math.max(uMax, u);
      vMin = Math.min(vMin, v);
      vMax = Math.max(vMax, v);
    }
    const aire = (uMax - uMin) * (vMax - vMin);
    if (meilleur && aire >= meilleur.aire) continue;

    const point = (u: number, v: number): StickerPoint => ({ x: u * ux - v * uy, y: u * uy + v * ux });
    meilleur = {
      aire,
      coins: [
        point(uMin, vMin),
        point(uMax, vMin),
        point(uMax, vMax),
        point(uMin, vMax),
      ] as StickerCorners,
    };
  }
  return meilleur?.coins ?? null;
}

/** Les coins remis dans le sens des aiguilles, en partant du plus haut à gauche. */
function dansLeSens(coins: StickerCorners): StickerCorners {
  const cx = coins.reduce((somme, point) => somme + point.x, 0) / 4;
  const cy = coins.reduce((somme, point) => somme + point.y, 0) / 4;
  const tries = [...coins].sort(
    (a, b) => Math.atan2(a.y - cy, a.x - cx) - Math.atan2(b.y - cy, b.x - cx),
  );
  // `atan2` part de l'est et tourne dans le sens des aiguilles (y vers le
  // bas) : le premier point au-dessus et à gauche du centre ouvre la marche.
  const depart = tries.findIndex((point) => point.x <= cx && point.y <= cy);
  const rang = depart >= 0 ? depart : 0;
  return [...tries.slice(rang), ...tries.slice(0, rang)] as StickerCorners;
}

/**
 * **Resserre les coins du modèle sur l'objet lui-même.** Rend `null` quand la
 * mesure ne conclut pas — l'appelant garde alors les coins du modèle.
 *
 * Ne lève jamais : c'est une amélioration, pas une étape nécessaire.
 */
export async function refineCorners(photo: Buffer, hint: StickerCorners): Promise<StickerCorners | null> {
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
    const coins = rectangleLePlusServre(enveloppe(points));
    if (!coins) return null;

    const fractions = dansLeSens(
      coins.map((point) => ({ x: point.x / info.width, y: point.y / info.height })) as StickerCorners,
    );
    const propres = acceptableCorners(fractions);
    if (!propres) return null;

    // Un rectangle qui couvre presque toute la photo n'a rien resserré : le
    // fond n'était pas uni, et les coins du modèle valent mieux.
    return stickerArea(propres) > PART_MAX ? null : propres;
  } catch {
    return null;
  }
}
