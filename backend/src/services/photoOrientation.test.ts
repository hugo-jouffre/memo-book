import { describe, expect, it } from "vitest";
import { Jimp } from "jimp";

import { measurePhoto } from "./photoOrientation.js";

/**
 * Un JPEG de `width` × `height` pixels, avec l'orientation EXIF demandée.
 *
 * Le bloc APP1 est écrit à la main : il n'y a qu'un tag à poser, et une
 * bibliothèque EXIF pour un entier serait plus de code que ces dix lignes.
 * ⚠️ La valeur d'une entrée TIFF vit à l'octet 8 de l'entrée, pas au 6 — la
 * poser au mauvais endroit donne un bloc qu'aucun lecteur ne voit, et fait
 * croire que personne n'applique l'orientation.
 */
async function jpeg(width: number, height: number, orientation?: number): Promise<Buffer> {
  const base = Buffer.from(
    await new Jimp({ width, height, color: 0xff0000ff }).getBuffer("image/jpeg"),
  );
  if (orientation === undefined) return base;

  const tiff = Buffer.alloc(26);
  tiff.write("II", 0, "ascii");
  tiff.writeUInt16LE(0x2a, 2);
  tiff.writeUInt32LE(8, 4); // l'IFD0 suit l'en-tête
  tiff.writeUInt16LE(1, 8); // une entrée
  tiff.writeUInt16LE(0x0112, 10); // Orientation
  tiff.writeUInt16LE(3, 12); // SHORT
  tiff.writeUInt32LE(1, 14);
  tiff.writeUInt16LE(orientation, 18); // la valeur tient dans l'entrée
  tiff.writeUInt32LE(0, 22); // pas d'IFD suivant

  const payload = Buffer.concat([Buffer.from("Exif\0\0", "binary"), tiff]);
  const header = Buffer.alloc(4);
  header.writeUInt16BE(0xffe1, 0);
  header.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([base.subarray(0, 2), header, payload, base.subarray(2)]);
}

describe("measurePhoto", () => {
  it("dit paysage une photo large sans drapeau", async () => {
    expect(await measurePhoto(await jpeg(120, 60))).toMatchObject({
      widthPx: 120,
      heightPx: 60,
      isLandscape: true,
    });
  });

  it("dit portrait une photo haute sans drapeau", async () => {
    expect(await measurePhoto(await jpeg(60, 120))).toMatchObject({
      widthPx: 60,
      heightPx: 120,
      isLandscape: false,
    });
  });

  // Un carré posé sur une carte large perd ses bords, jamais son sujet.
  it("compte un carré comme paysage", async () => {
    expect(await measurePhoto(await jpeg(80, 80))).toMatchObject({ isLandscape: true });
  });

  it("rend null sur ce qu'elle ne sait pas décoder", async () => {
    expect(await measurePhoto(Buffer.from("ni JPEG ni PNG"))).toBeNull();
  });

  /**
   * **Le cas de l'iPhone, et la raison d'être de ce service.**
   *
   * Ces trois-là épinglent un comportement de `jimp` que rien ne rappelle à
   * l'appel : il applique le drapeau EXIF au décodage. S'ils tombent après une
   * montée de version, c'est que `jimp` a cessé de le faire — il faut alors
   * lire l'orientation et échanger les côtés dans `measurePhoto`, et surtout
   * pas « corriger » ces attentes, qui disent ce que l'œil voit.
   */
  describe("quand l'EXIF contredit les pixels", () => {
    it("dit portrait une photo aux pixels larges que le drapeau redresse", async () => {
      expect(await measurePhoto(await jpeg(120, 60, 6))).toMatchObject({
        widthPx: 60,
        heightPx: 120,
        isLandscape: false,
      });
    });

    it("dit paysage une photo aux pixels hauts que le drapeau couche", async () => {
      expect(await measurePhoto(await jpeg(60, 120, 8))).toMatchObject({
        widthPx: 120,
        heightPx: 60,
        isLandscape: true,
      });
    });

    // Un demi-tour ne change pas les côtés : la photo reste dans son sens.
    it("laisse les côtés d'une photo retournée d'un demi-tour", async () => {
      expect(await measurePhoto(await jpeg(120, 60, 3))).toMatchObject({
        widthPx: 120,
        heightPx: 60,
        isLandscape: true,
      });
    });
  });
});

/**
 * **T265** — la mesure rend aussi la netteté, tirée du même décodage. C'est
 * elle qui départage les photos d'une étape quand la page n'en dessine
 * qu'une partie (`services/photoPicking.ts`).
 */
describe("la netteté, mesurée en même temps", () => {
  it("rend un chiffre et un verdict, sans second décodage", async () => {
    const mesure = await measurePhoto(await jpeg(120, 60));
    expect(typeof mesure?.sharpness).toBe("number");
    expect(["ok", "upscale", "downgrade", "reject"]).toContain(mesure?.verdict);
  });

  it("refuse un aplat, et pas une photo qui a du détail", async () => {
    // Un aplat rouge n'a aucune variance : c'est le cas que le verdict
    // `reject` vise — une photo dont il n'y a rien à montrer.
    const aplat = await measurePhoto(await jpeg(120, 120));
    expect(aplat?.verdict).toBe("reject");
    expect(aplat?.sharpness).toBe(0);

    // Du bruit : beaucoup de détail, donc un verdict franc dans l'autre sens.
    const pixels = Buffer.alloc(120 * 120 * 4);
    for (let i = 0; i < pixels.length; i += 4) {
      const v = (i * 2654435761) % 256;
      pixels[i] = v;
      pixels[i + 1] = (v * 7) % 256;
      pixels[i + 2] = (v * 13) % 256;
      pixels[i + 3] = 255;
    }
    const bruit = Buffer.from(
      await new Jimp({ data: pixels, width: 120, height: 120 }).getBuffer("image/jpeg"),
    );
    const mesure = await measurePhoto(bruit);
    expect(mesure?.verdict).toBe("ok");
    expect(mesure!.sharpness).toBeGreaterThan(aplat!.sharpness);
  });
});
