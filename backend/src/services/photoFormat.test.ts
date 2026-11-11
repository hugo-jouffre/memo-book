import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { Jimp } from "jimp";

import { isRenderableImage, sniffImageFormat, toRenderablePhoto } from "./photoFormat.js";
import { measurePhoto } from "./photoOrientation.js";

/**
 * Un vrai HEIC codé en HEVC, comme en sort la photothèque d'un iPhone — fait
 * par `sips -s format heic`. 536 octets : c'est un conteneur complet, pas un
 * en-tête bricolé, et c'est ce qui compte ici puisque tout le test porte sur
 * le décodage.
 */
const HEIC = readFileSync(
  resolve(new URL("../../test/fixtures/photos/heic-iphone.heic", import.meta.url).pathname),
);

const jpeg = async (width: number, height: number): Promise<Buffer> =>
  Buffer.from(await new Jimp({ width, height, color: 0xff0000ff }).getBuffer("image/jpeg"));

const png = async (width: number, height: number): Promise<Buffer> =>
  Buffer.from(await new Jimp({ width, height, color: 0x00ff00ff }).getBuffer("image/png"));

describe("sniffImageFormat", () => {
  it("reconnaît le HEIC d'un iPhone, quoi que dise le nom du fichier", () => {
    expect(sniffImageFormat(HEIC)).toBe("image/heic");
  });

  it("reconnaît le JPEG et le PNG", async () => {
    expect(sniffImageFormat(await jpeg(8, 8))).toBe("image/jpeg");
    expect(sniffImageFormat(await png(8, 8))).toBe("image/png");
  });

  it("ne reconnaît rien dans un fichier trop court", () => {
    expect(sniffImageFormat(Buffer.from([0xff, 0xd8]))).toBeNull();
  });
});

describe("isRenderableImage", () => {
  it("dit non au HEIC — c'est ce que Chromium ne peint pas", () => {
    expect(isRenderableImage(HEIC)).toBe(false);
  });

  it("dit oui au JPEG", async () => {
    expect(isRenderableImage(await jpeg(8, 8))).toBe(true);
  });
});

describe("toRenderablePhoto", () => {
  it("convertit un HEIC en JPEG, et corrige l'extension", async () => {
    const photo = await toRenderablePhoto(HEIC, "IMG_4242.jpg", "image/jpeg");

    expect(photo.converted).toBe(true);
    expect(photo.mimeType).toBe("image/jpeg");
    expect(photo.filename).toBe("IMG_4242.jpg");
    expect(sniffImageFormat(photo.buffer)).toBe("image/jpeg");
  });

  it("garde les pixels du HEIC — la photo convertie se mesure", async () => {
    const photo = await toRenderablePhoto(HEIC, "photo.heic", "image/heic");

    expect(photo.filename).toBe("photo.jpg");
    // 40 × 30 : la photo convertie redevient candidate à la couverture, ce
    // qu'un HEIC n'était jamais puisque `measurePhoto` ne sait pas le lire.
    await expect(measurePhoto(photo.buffer)).resolves.toEqual({
      widthPx: 40,
      heightPx: 30,
      isLandscape: true,
    });
    await expect(measurePhoto(HEIC)).resolves.toBeNull();
  });

  it("ne réencode pas un JPEG : les octets reviennent tels quels", async () => {
    const source = await jpeg(12, 10);
    const photo = await toRenderablePhoto(source, "photo.jpg", "image/jpeg");

    expect(photo.converted).toBe(false);
    expect(photo.buffer).toBe(source);
  });

  it("corrige l'extension d'un PNG envoyé sous un nom en .jpg", async () => {
    const photo = await toRenderablePhoto(await png(12, 10), "capture.jpg", "image/jpeg");

    expect(photo.converted).toBe(false);
    expect(photo.mimeType).toBe("image/png");
    expect(photo.filename).toBe("capture.png");
  });

  it("rend les octets d'origine quand le format est inconnu", async () => {
    const source = Buffer.from("ni une image ni rien du tout");
    const photo = await toRenderablePhoto(source, "photo.jpg", "image/jpeg");

    expect(photo.converted).toBe(false);
    expect(photo.buffer).toBe(source);
    expect(photo.mimeType).toBe("image/jpeg");
  });
});
