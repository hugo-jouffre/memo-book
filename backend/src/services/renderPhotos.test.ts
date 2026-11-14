import { randomFillSync } from "node:crypto";
import sharp from "sharp";
import { beforeAll, describe, expect, it, vi } from "vitest";

import { renderablePhotoUrl, type RenderablePhotoMedia } from "./renderPhotos.js";
import { RENDER_MAX_BYTES } from "./photoDownscale.js";
import { SIMULATED_CDN_HOST } from "./webflow.js";

/**
 * **L'adresse qu'on donne au moteur de PDF**, vue d'assez loin pour que les
 * deux pannes du 14/11/2026 y tiennent :
 *
 * - une adresse de CDN **simulée**, écrite en base avant le 11/11 et crue sur
 *   parole, qui faisait composer des cadres vides ;
 * - une photo d'iPhone de plusieurs mégaoctets servie telle quelle, qui
 *   faisait abandonner APITemplate en HTTP 504.
 *
 * Rien ici ne touche au réseau ni à la base : des doubles, et une vraie photo
 * lourde pour que l'allègement ait quelque chose à mordre.
 */

const BASE = "https://api.memo-book.test";

/** Les premiers octets d'un JPEG : de quoi passer le contrôle de format. */
const ENTETE_JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1]);

let photoLourde: Buffer;

beforeAll(async () => {
  const pixels = Buffer.alloc(3000 * 2000 * 3);
  randomFillSync(pixels);
  photoLourde = await sharp(pixels, { raw: { width: 3000, height: 2000, channels: 3 } })
    .jpeg({ quality: 90 })
    .toBuffer();
}, 60_000);

type Deps = Parameters<typeof renderablePhotoUrl>[0];

function doubles(options: { sertDesUrlsPubliques?: boolean } = {}) {
  const update = vi.fn().mockResolvedValue({});
  const get = vi.fn().mockImplementation(() => Promise.resolve(photoLourde));
  const put = vi.fn().mockImplementation((prefix: string) =>
    Promise.resolve({
      storageKey: `${prefix}/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jpg`,
      bytes: 420_000,
      mimeType: "image/jpeg",
    }),
  );

  const deps = {
    prisma: { mediaAsset: { update } },
    storage: {
      get,
      put,
      firstBytes: vi.fn().mockResolvedValue(ENTETE_JPEG),
      signedReadUrl: vi.fn().mockResolvedValue(`${BASE}/signe`),
    },
    publisher: {
      servesPublicUrls: options.sertDesUrlsPubliques ?? false,
      publish: vi.fn(),
      unpublish: vi.fn(),
    },
    env: {
      NODE_ENV: "production",
      API_PUBLIC_BASE_URL: BASE,
      RAILWAY_PUBLIC_DOMAIN: "",
      APP_LINK_BASE_URL: "memobook://",
    },
    logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  };

  return { deps: deps as unknown as Deps, update, get, put };
}

function media(overrides: Partial<RenderablePhotoMedia> = {}): RenderablePhotoMedia {
  return {
    id: "media-1",
    storageKey: "photo/11111111-2222-3333-4444-555555555555.jpg",
    mimeType: "image/jpeg",
    bytes: 200_000,
    cdnUrl: null,
    cdnAssetId: null,
    ...overrides,
  };
}

describe("renderablePhotoUrl", () => {
  it("efface une adresse de CDN simulée et sert la photo par l'API", async () => {
    const { deps, update } = doubles();

    const url = await renderablePhotoUrl(
      deps,
      media({
        cdnUrl: `https://${SIMULATED_CDN_HOST}/memobook/abc/photo.jpg`,
        cdnAssetId: "abc",
      }),
    );

    expect(url).toBe(`${BASE}/v1/trip-photos/11111111-2222-3333-4444-555555555555.jpg`);
    expect(update).toHaveBeenCalledWith({
      where: { id: "media-1" },
      data: { cdnUrl: null, cdnAssetId: null },
    });
  });

  it("garde une adresse de CDN que quelqu'un sert vraiment", async () => {
    const { deps, update } = doubles();

    const url = await renderablePhotoUrl(
      deps,
      media({ cdnUrl: "https://cdn.memo-book.com/photo.jpg", cdnAssetId: "x" }),
    );

    expect(url).toBe("https://cdn.memo-book.com/photo.jpg");
    expect(update).not.toHaveBeenCalled();
  });

  it("ne télécharge pas une photo déjà légère", async () => {
    const { deps, get, put } = doubles();

    const url = await renderablePhotoUrl(deps, media({ bytes: RENDER_MAX_BYTES - 1 }));

    expect(url).toBe(`${BASE}/v1/trip-photos/11111111-2222-3333-4444-555555555555.jpg`);
    expect(get).not.toHaveBeenCalled();
    expect(put).not.toHaveBeenCalled();
  });

  it("sert une copie allégée d'une photo lourde, et la retient", async () => {
    const { deps, put, update } = doubles();

    const url = await renderablePhotoUrl(deps, media({ bytes: photoLourde.byteLength }));

    expect(put).toHaveBeenCalledTimes(1);
    expect(url).toBe(`${BASE}/v1/trip-photos/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jpg`);
    expect(update).toHaveBeenCalledWith({
      where: { id: "media-1" },
      data: { renderStorageKey: "photo/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jpg" },
    });
  });

  it("resert la copie allégée sans la refabriquer", async () => {
    const { deps, get, put } = doubles();

    const url = await renderablePhotoUrl(
      deps,
      media({
        bytes: photoLourde.byteLength,
        renderStorageKey: "photo/99999999-8888-7777-6666-555555555555.jpg",
      }),
    );

    expect(url).toBe(`${BASE}/v1/trip-photos/99999999-8888-7777-6666-555555555555.jpg`);
    expect(get).not.toHaveBeenCalled();
    expect(put).not.toHaveBeenCalled();
  });

  it("sert l'originale plutôt que rien quand le stockage est muet", async () => {
    const { deps, get, put } = doubles();
    get.mockRejectedValueOnce(new Error("S3 injoignable"));

    const url = await renderablePhotoUrl(deps, media({ bytes: photoLourde.byteLength }));

    expect(url).toBe(`${BASE}/v1/trip-photos/11111111-2222-3333-4444-555555555555.jpg`);
    expect(put).not.toHaveBeenCalled();
  });

  it("publie la copie allégée, pas l'originale, quand un CDN sert vraiment", async () => {
    const { deps } = doubles({ sertDesUrlsPubliques: true });
    const publier = vi
      .fn()
      .mockResolvedValue({ assetId: "web-1", cdnUrl: "https://cdn.memo-book.com/allegee.jpg" });
    (deps as unknown as { publisher: { publish: unknown } }).publisher.publish = publier;

    const url = await renderablePhotoUrl(deps, media({ bytes: photoLourde.byteLength }));

    expect(url).toBe("https://cdn.memo-book.com/allegee.jpg");
    expect(publier).toHaveBeenCalledWith("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jpg", `${BASE}/signe`);
  });
});
