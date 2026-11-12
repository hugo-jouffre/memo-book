import { describe, expect, it } from "vitest";
import sharp from "sharp";
import {
  acceptableCorners,
  cutSticker,
  stickerArea,
  StickerCutError,
  STICKER_MAX_SIDE,
  type StickerCorners,
} from "../src/services/stickerCut.js";

/**
 * **Les ciseaux** (Hugo, 10/11/2026) — « stickers découpés depuis tes vraies
 * photos de billets et tampons ».
 *
 * Ce que ces cas tiennent : ce qui est dans les quatre coins reste, ce qui est
 * autour s'en va, la bordure blanche existe, le fond est transparent, et une
 * photo illisible ne fait pas tomber la composition.
 */

/** Une photo d'essai : un « billet » jaune posé sur une nappe verte. */
async function photoAvecBillet(width = 400, height = 300): Promise<Buffer> {
  const billet = await sharp({
    create: { width: 200, height: 100, channels: 3, background: { r: 240, g: 220, b: 60 } },
  })
    .png()
    .toBuffer();
  return sharp({
    create: { width, height, channels: 3, background: { r: 20, g: 120, b: 40 } },
  })
    .composite([{ input: billet, left: 100, top: 100 }])
    .jpeg()
    .toBuffer();
}

/** Les coins du billet de ``photoAvecBillet``, en fractions. */
const BILLET: StickerCorners = [
  { x: 0.25, y: 1 / 3 },
  { x: 0.75, y: 1 / 3 },
  { x: 0.75, y: 2 / 3 },
  { x: 0.25, y: 2 / 3 },
];

/** La couleur d'un pixel du PNG rendu, canal alpha compris. */
async function pixel(png: Buffer, xFraction: number, yFraction: number) {
  const { data, info } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const x = Math.min(info.width - 1, Math.round(xFraction * info.width));
  const y = Math.min(info.height - 1, Math.round(yFraction * info.height));
  const i = (y * info.width + x) * info.channels;
  return { r: data[i]!, g: data[i + 1]!, b: data[i + 2]!, a: data[i + 3]! };
}

/**
 * Le premier pixel franc en descendant la colonne du milieu : la toile commence
 * par de la marge vide, puis l'ombre, et la première chose opaque est la
 * bordure.
 */
async function premierPixelFranc(png: Buffer) {
  const { data, info } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const x = Math.round(info.width / 2);
  for (let y = 0; y < info.height; y += 1) {
    const i = (y * info.width + x) * info.channels;
    if (data[i + 3]! > 250) return { r: data[i]!, g: data[i + 1]!, b: data[i + 2]!, a: data[i + 3]! };
  }
  throw new Error("Aucun pixel opaque : le sticker est vide.");
}

describe("ce qu'on accepte de découper", () => {
  it("accepte quatre coins dans la photo", () => {
    expect(acceptableCorners(BILLET)).toEqual(BILLET);
  });

  it("refuse un objet trop petit pour être reconnu", () => {
    const timbre = [
      { x: 0.5, y: 0.5 },
      { x: 0.55, y: 0.5 },
      { x: 0.55, y: 0.55 },
      { x: 0.5, y: 0.55 },
    ];
    // 0,25 % de la photo : il n'en resterait que quelques pixels.
    expect(stickerArea(timbre as StickerCorners)).toBeLessThan(0.02);
    expect(acceptableCorners(timbre)).toBeNull();
  });

  it("refuse ce qui n'est pas quatre points de la photo", () => {
    expect(acceptableCorners(null)).toBeNull();
    expect(acceptableCorners([])).toBeNull();
    expect(acceptableCorners(BILLET.slice(0, 3))).toBeNull();
    expect(acceptableCorners([...BILLET.slice(0, 3), { x: 4, y: 0.5 }])).toBeNull();
    expect(acceptableCorners([...BILLET.slice(0, 3), { x: "0.5", y: 0.5 }])).toBeNull();
  });

  /** Un modèle qui dépasse d'un cheveu est ramené dans la photo, pas jeté. */
  it("ramène un coin qui déborde d'un cheveu", () => {
    const presque = [
      { x: -0.02, y: 0 },
      { x: 1.01, y: 0 },
      { x: 1.01, y: 0.5 },
      { x: -0.02, y: 0.5 },
    ];
    expect(acceptableCorners(presque)).toEqual([
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 1, y: 0.5 },
      { x: 0, y: 0.5 },
    ]);
  });
});

describe("découper le billet", () => {
  it("garde le billet, jette la nappe, et pose une bordure blanche", async () => {
    const { png, width, height } = await cutSticker(await photoAvecBillet(), BILLET);

    // Le centre : le jaune du billet, opaque.
    const centre = await pixel(png, 0.5, 0.5);
    expect(centre.a).toBe(255);
    expect(centre.r).toBeGreaterThan(200);
    expect(centre.g).toBeGreaterThan(180);
    expect(centre.b).toBeLessThan(120);

    // Le bord : en descendant la colonne du milieu, la **première** chose
    // franche qu'on rencontre est la bordure blanche — jamais la nappe verte.
    const bord = await premierPixelFranc(png);
    expect(bord.r).toBeGreaterThan(230);
    expect(bord.g).toBeGreaterThan(230);
    expect(bord.b).toBeGreaterThan(230);

    // Le coin : rien du tout — le fond est transparent, l'ombre reste douce.
    const coin = await pixel(png, 0.005, 0.005);
    expect(coin.a).toBeLessThan(40);

    expect(width).toBeGreaterThan(200);
    expect(height).toBeGreaterThan(100);
    expect(Math.max(width, height)).toBeLessThanOrEqual(STICKER_MAX_SIDE);
  });

  /** Un tampon de travers : ce qui dépasse du quadrilatère part aussi. */
  it("suit les quatre coins, même penchés", async () => {
    const losange: StickerCorners = [
      { x: 0.5, y: 0.15 },
      { x: 0.85, y: 0.5 },
      { x: 0.5, y: 0.85 },
      { x: 0.15, y: 0.5 },
    ];
    const { png } = await cutSticker(await photoAvecBillet(600, 600), losange);

    // Le centre du losange est plein ; ses coins, hors forme, sont vides.
    expect((await pixel(png, 0.5, 0.5)).a).toBe(255);
    expect((await pixel(png, 0.02, 0.02)).a).toBeLessThan(40);
    expect((await pixel(png, 0.98, 0.98)).a).toBeLessThan(40);
  });

  it("borne la définition : un sticker n'a pas besoin de 4 000 pixels", async () => {
    const grande = await photoAvecBillet(4000, 3000);
    const { width, height } = await cutSticker(grande, BILLET);
    expect(Math.max(width, height)).toBe(STICKER_MAX_SIDE);
  });

  it("refuse une photo illisible, sans rien casser d'autre", async () => {
    await expect(cutSticker(Buffer.from("ceci n'est pas une photo"), BILLET)).rejects.toBeInstanceOf(
      StickerCutError,
    );
  });
});
