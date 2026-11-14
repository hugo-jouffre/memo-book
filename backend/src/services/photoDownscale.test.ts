import { randomFillSync } from "node:crypto";
import sharp from "sharp";
import { describe, expect, it } from "vitest";

import { downscaleForRender, RENDER_MAX_BYTES, RENDER_MAX_SIDE } from "./photoDownscale.js";

/**
 * **Une photo lourde**, comme celles qui sortent d'un iPhone.
 *
 * Du bruit, et non un aplat : un aplat de 3000 × 2000 pèse quelques
 * kilo-octets une fois encodé, donc passerait sous `RENDER_MAX_BYTES` et ne
 * dirait rien de ce qu'on veut vérifier.
 */
async function grosJpeg(width: number, height: number, orientation?: number): Promise<Buffer> {
  const pixels = Buffer.alloc(width * height * 3);
  randomFillSync(pixels);
  const base = await sharp(pixels, { raw: { width, height, channels: 3 } })
    .jpeg({ quality: 90 })
    .toBuffer();

  if (orientation === undefined) return base;

  // Le même bloc APP1 écrit à la main que dans `photoOrientation.test.ts` :
  // un seul tag à poser, et la valeur vit à l'octet 8 de l'entrée TIFF.
  const tiff = Buffer.alloc(26);
  tiff.write("II", 0, "ascii");
  tiff.writeUInt16LE(0x2a, 2);
  tiff.writeUInt32LE(8, 4);
  tiff.writeUInt16LE(1, 8);
  tiff.writeUInt16LE(0x0112, 10);
  tiff.writeUInt16LE(3, 12);
  tiff.writeUInt32LE(1, 14);
  tiff.writeUInt16LE(orientation, 18);
  tiff.writeUInt32LE(0, 22);

  const payload = Buffer.concat([Buffer.from("Exif\0\0", "binary"), tiff]);
  const header = Buffer.alloc(4);
  header.writeUInt16BE(0xffe1, 0);
  header.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([base.subarray(0, 2), header, payload, base.subarray(2)]);
}

describe("downscaleForRender", () => {
  it("laisse tranquille une photo déjà légère", async () => {
    const legere = await sharp({
      create: { width: 800, height: 600, channels: 3, background: "#3fa7d6" },
    })
      .jpeg()
      .toBuffer();

    expect(legere.byteLength).toBeLessThan(RENDER_MAX_BYTES);
    expect(await downscaleForRender(legere)).toBeNull();
  });

  it("ramène une photo d'iPhone sous le grand côté voulu, et bien plus légère", async () => {
    const lourde = await grosJpeg(3000, 2000);
    expect(lourde.byteLength).toBeGreaterThan(RENDER_MAX_BYTES);

    const copie = await downscaleForRender(lourde);

    expect(copie).not.toBeNull();
    expect(copie?.widthPx).toBe(RENDER_MAX_SIDE);
    expect(copie?.heightPx).toBe(1600);
    expect(copie?.mimeType).toBe("image/jpeg");
    expect(copie!.buffer.byteLength).toBeLessThan(lourde.byteLength);
  });

  /**
   * Le test qui compte. sharp n'applique pas le drapeau EXIF de lui-même et
   * **efface** les métadonnées en sortie : sans `rotate()`, la copie partirait
   * couchée dans le carnet — et l'original, lui, s'affichait droit. Un bug
   * qu'on n'aurait vu qu'à l'impression.
   */
  it("grave la rotation EXIF dans les pixels au lieu de la perdre", async () => {
    // 3000 × 2000 en pixels, « tourner d'un quart » en EXIF : la photo se
    // regarde donc en portrait, 2000 × 3000.
    const portrait = await grosJpeg(3000, 2000, 6);

    const copie = await downscaleForRender(portrait);

    expect(copie?.widthPx).toBe(1600);
    expect(copie?.heightPx).toBe(RENDER_MAX_SIDE);
  });

  it("rend null sur des octets illisibles, sans jeter", async () => {
    const nImporteQuoi = Buffer.alloc(RENDER_MAX_BYTES + 1);
    randomFillSync(nImporteQuoi);

    expect(await downscaleForRender(nImporteQuoi)).toBeNull();
  });
});
