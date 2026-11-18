import { randomFillSync } from "node:crypto";
import sharp from "sharp";
import { describe, expect, it, vi } from "vitest";

import { screenPhotoKey, storeScreenThumbnail } from "./photoThumbnails.js";
import { THUMB_MAX_SIDE } from "./photoDownscale.js";

async function photoDIPhone(): Promise<Buffer> {
  // Du bruit : un aplat de 3000 × 2000 pèse quelques kilo-octets encodé, donc
  // passerait pour une vignette et ne dirait rien.
  const pixels = Buffer.alloc(3000 * 2000 * 3);
  randomFillSync(pixels);
  return sharp(pixels, { raw: { width: 3000, height: 2000, channels: 3 } })
    .jpeg({ quality: 90 })
    .toBuffer();
}

function journal() {
  return { warn: vi.fn(), info: vi.fn(), error: vi.fn() } as never;
}

describe("la clé à servir à l'écran", () => {
  it("prend la vignette quand il y en a une", () => {
    expect(screenPhotoKey({ storageKey: "photo/a.jpg", thumbStorageKey: "photo/a-mini.jpg" })).toBe(
      "photo/a-mini.jpg",
    );
  });

  it("retombe sur la photo elle-même, sans faute", () => {
    // Une photo arrivée avant le 17/11/2026, ou déjà si légère qu'une vignette
    // ne gagnerait rien : l'écran l'affiche comme avant ce ticket.
    expect(screenPhotoKey({ storageKey: "photo/a.jpg", thumbStorageKey: null })).toBe("photo/a.jpg");
    expect(screenPhotoKey({ storageKey: "photo/a.jpg" })).toBe("photo/a.jpg");
  });
});

describe("fabriquer la vignette d'une photo qui arrive", () => {
  it("la range et rend sa clé", async () => {
    const put = vi.fn().mockResolvedValue({ storageKey: "photo/mini.jpg", bytes: 20_000 });
    const storage = { put } as never;

    const key = await storeScreenThumbnail({ storage, logger: journal() }, await photoDIPhone());

    expect(key).toBe("photo/mini.jpg");
    const rangee = put.mock.calls[0] as [string, string, Buffer, string];
    expect(rangee[0]).toBe("photo");
    expect(rangee[1]).toBe("vignette.jpg");
    expect(rangee[3]).toBe("image/jpeg");
    const mesure = await sharp(rangee[2]).metadata();
    expect(mesure.width).toBe(THUMB_MAX_SIDE);
  });

  it("ne range rien pour une photo déjà légère", async () => {
    const put = vi.fn();
    const petite = await sharp({
      create: { width: 400, height: 300, channels: 3, background: "#3fa7d6" },
    })
      .jpeg()
      .toBuffer();

    expect(await storeScreenThumbnail({ storage: { put } as never, logger: journal() }, petite)).toBeNull();
    expect(put).not.toHaveBeenCalled();
  });

  /**
   * **Le test qui compte.** Cet appel est sur le chemin d'un envoi de photo :
   * s'il jetait, le souvenir de quelqu'un serait refusé pour une vignette. Le
   * récit est irremplaçable, la vignette se refabrique.
   */
  it("ne fait jamais échouer l'envoi quand le stockage refuse", async () => {
    const logger = journal();
    const storage = { put: vi.fn().mockRejectedValue(new Error("S3 muet")) } as never;

    await expect(
      storeScreenThumbnail({ storage, logger }, await photoDIPhone()),
    ).resolves.toBeNull();
    expect((logger as unknown as { warn: ReturnType<typeof vi.fn> }).warn).toHaveBeenCalled();
  });

  it("ne jette pas non plus sur des octets illisibles", async () => {
    const nImporteQuoi = Buffer.alloc(200_000);
    randomFillSync(nImporteQuoi);
    const put = vi.fn();

    await expect(
      storeScreenThumbnail({ storage: { put } as never, logger: journal() }, nImporteQuoi),
    ).resolves.toBeNull();
    expect(put).not.toHaveBeenCalled();
  });
});
