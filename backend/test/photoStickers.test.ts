import { beforeEach, describe, expect, it } from "vitest";
import sharp from "sharp";
import {
  photoStickerUrl,
  photoStickersOf,
  settlePhotoStickers,
  STICKERS_PER_TRIP,
  STICKER_PREFIX,
} from "../src/services/photoStickers.js";
import { acceptableSpots, STICKER_MIN_SCORE, type StickerSpot } from "../src/services/stickerVision.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **Les stickers découpés dans les vraies photos** (Hugo, 10/11/2026) —
 * « stickers découpés depuis tes vraies photos de billets et tampons ».
 *
 * Ce que ces cas tiennent : on ne regarde une photo qu'une fois, on ne
 * découpe que ce que l'œil retient, le carnet n'en porte jamais plus que son
 * compte, et **rien de tout ça ne peut faire échouer une composition**.
 */

let harness: TestHarness;
let codes = 0;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

/** Un œil qui rend ce qu'on lui dit, et retient ce qu'on lui a montré. */
function oeil(reponse: (ids: string[]) => StickerSpot[]) {
  const vues: string[][] = [];
  return {
    vues,
    spotter: {
      async spot(photos: { id: string }[]) {
        const ids = photos.map((photo) => photo.id);
        vues.push(ids);
        return reponse(ids);
      },
    },
  };
}

/** Les quatre coins d'un objet qui occupe le milieu de la photo. */
const COINS = [
  { x: 0.2, y: 0.2 },
  { x: 0.8, y: 0.2 },
  { x: 0.8, y: 0.8 },
  { x: 0.2, y: 0.8 },
] as StickerSpot["corners"];

async function photoJpeg(): Promise<Buffer> {
  return sharp({
    create: { width: 300, height: 200, channels: 3, background: { r: 200, g: 180, b: 90 } },
  })
    .jpeg()
    .toBuffer();
}

/** Un voyage, et `combien` photos dedans. */
async function voyageAvecPhotos(combien: number) {
  const account = await registerAccount(harness.app, `stk${(codes += 1)}@memobook.app`);
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: account.accountId,
      title: "Rome",
      accessCode: `STK${String(codes).padStart(3, "0")}`,
      stage: "ongoing",
    },
  });

  const entryIds: string[] = [];
  for (let index = 0; index < combien; index += 1) {
    const { storageKey, bytes, mimeType } = await harness.context.storage.put(
      "photo",
      "photo.jpg",
      await photoJpeg(),
      "image/jpeg",
    );
    const media = await harness.prisma.mediaAsset.create({ data: { storageKey, bytes, mimeType } });
    const entry = await harness.prisma.entry.create({
      data: {
        memoId: memo.id,
        kind: "photo",
        status: "ready",
        mediaId: media.id,
        placeLabel: "Rome",
        capturedAt: new Date(Date.now() + index * 1_000),
      },
    });
    entryIds.push(entry.id);
  }
  return { memo, entryIds };
}

function depsAvec(spotter: unknown) {
  return { ...harness.context, stickerSpotter: spotter as never };
}

describe("ce que l'œil a le droit de répondre", () => {
  const connues = new Set(["photo-1", "photo-2"]);
  const bon = { photo_id: "photo-1", label: "billet de train", score: 90, corners: COINS };

  it("accepte un repérage complet", () => {
    expect(acceptableSpots({ stickers: [bon] }, connues)).toEqual([
      { photoId: "photo-1", label: "billet de train", score: 90, corners: COINS },
    ]);
  });

  it("écarte une photo qu'on n'a pas montrée — un modèle en invente", () => {
    expect(acceptableSpots({ stickers: [{ ...bon, photo_id: "photo-9" }] }, connues)).toEqual([]);
  });

  it("écarte un score trop bas pour valoir le découpage", () => {
    const tiede = { ...bon, score: STICKER_MIN_SCORE - 1 };
    expect(acceptableSpots({ stickers: [tiede] }, connues)).toEqual([]);
  });

  it("écarte des coins impossibles, et garde le reste de la réponse", () => {
    const faux = { ...bon, photo_id: "photo-2", corners: [{ x: 0, y: 0 }] };
    const spots = acceptableSpots({ stickers: [faux, bon] }, connues);
    expect(spots.map((spot) => spot.photoId)).toEqual(["photo-1"]);
  });

  it("ne garde qu'un sticker par photo", () => {
    const spots = acceptableSpots({ stickers: [bon, { ...bon, label: "autre chose" }] }, connues);
    expect(spots).toHaveLength(1);
    expect(spots[0]?.label).toBe("billet de train");
  });

  it("une réponse vide, ou illisible, ne donne rien", () => {
    expect(acceptableSpots({ stickers: [] }, connues)).toEqual([]);
    expect(acceptableSpots({}, connues)).toEqual([]);
    expect(acceptableSpots(null, connues)).toEqual([]);
  });
});

describe("découper les photos d'un voyage", () => {
  it("découpe ce que l'œil retient, et range le PNG", async () => {
    const { memo, entryIds } = await voyageAvecPhotos(2);
    const { spotter, vues } = oeil((ids) => [
      { photoId: ids[0]!, label: "billet de train", score: 88, corners: COINS },
    ]);

    expect(await settlePhotoStickers(depsAvec(spotter), memo.id)).toBe(1);

    // L'œil a bien vu les deux photos, et une seule a donné un sticker.
    expect(vues).toEqual([entryIds]);
    const stickers = await harness.prisma.photoSticker.findMany({ where: { memoId: memo.id } });
    expect(stickers).toHaveLength(1);
    expect(stickers[0]?.label).toBe("billet de train");
    expect(stickers[0]?.entryId).toBe(entryIds[0]);
    expect(stickers[0]?.storageKey.startsWith(`${STICKER_PREFIX}/`)).toBe(true);

    // Le PNG existe, il est transparent, et il mesure ce que la ligne annonce.
    const png = await harness.context.storage.get(stickers[0]!.storageKey);
    const meta = await sharp(png).metadata();
    expect(meta.format).toBe("png");
    expect(meta.hasAlpha).toBe(true);
    expect(meta.width).toBe(stickers[0]?.widthPx);
  });

  it("ne regarde jamais deux fois la même photo", async () => {
    const { memo } = await voyageAvecPhotos(2);
    const { spotter, vues } = oeil(() => []);

    await settlePhotoStickers(depsAvec(spotter), memo.id);
    await settlePhotoStickers(depsAvec(spotter), memo.id);

    // Deux photos vues au premier passage, aucune au second : la date est
    // posée même quand rien n'est découpé.
    expect(vues).toHaveLength(1);
    const vuesEnBase = await harness.prisma.entry.count({
      where: { memoId: memo.id, stickerCheckedAt: { not: null } },
    });
    expect(vuesEnBase).toBe(2);
  });

  it("s'arrête au compte du carnet, en gardant les meilleurs", async () => {
    const { memo } = await voyageAvecPhotos(STICKERS_PER_TRIP + 2);
    // L'œil retient tout, avec un score croissant : les derniers sont les
    // meilleurs, et ce sont eux qui doivent rester.
    const { spotter } = oeil((ids) =>
      ids.map((id, rang) => ({ photoId: id, label: `objet ${rang}`, score: 60 + rang, corners: COINS })),
    );

    expect(await settlePhotoStickers(depsAvec(spotter), memo.id)).toBe(STICKERS_PER_TRIP);

    const stickers = await harness.prisma.photoSticker.findMany({
      where: { memoId: memo.id },
      orderBy: { score: "desc" },
    });
    expect(stickers).toHaveLength(STICKERS_PER_TRIP);
    expect(stickers[0]?.score).toBe(60 + STICKERS_PER_TRIP + 1);
    // Et une composition de plus n'en ajoute pas un cinquième.
    expect(await settlePhotoStickers(depsAvec(spotter), memo.id)).toBe(0);
  });

  /**
   * C'est de la décoration : une panne du modèle laisse le carnet sortir, et
   * les photos **non marquées**, pour que la composition suivante réessaie.
   */
  it("un œil en panne ne fait pas échouer la composition", async () => {
    const { memo } = await voyageAvecPhotos(1);
    const casse = {
      async spot() {
        throw new Error("modèle indisponible");
      },
    };

    await expect(settlePhotoStickers(depsAvec(casse), memo.id)).resolves.toBe(0);
    expect(await harness.prisma.photoSticker.count({ where: { memoId: memo.id } })).toBe(0);
    const jamaisVues = await harness.prisma.entry.count({
      where: { memoId: memo.id, stickerCheckedAt: null },
    });
    expect(jamaisVues).toBe(1);
  });

  it("une photo illisible est écartée, pas re-regardée à chaque carnet", async () => {
    const { memo } = await voyageAvecPhotos(1);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    const media = await harness.prisma.mediaAsset.findFirstOrThrow();
    await harness.context.storage.put("photo", "casse.jpg", Buffer.from("pas une photo"), "image/jpeg");
    await harness.prisma.mediaAsset.update({
      where: { id: media.id },
      data: { storageKey: "photo/inexistante.jpg" },
    });
    const { spotter, vues } = oeil(() => []);

    expect(await settlePhotoStickers(depsAvec(spotter), memo.id)).toBe(0);

    // Le modèle n'est même pas appelé — rien à lui montrer —, et la photo est
    // quand même marquée vue : la relire donnerait le même échec.
    expect(vues).toEqual([]);
    const apres = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(apres.stickerCheckedAt).toBeInstanceOf(Date);
  });
});

describe("les donner au composeur", () => {
  it("rend une adresse publique, et le souvenir d'où il sort", async () => {
    const { memo, entryIds } = await voyageAvecPhotos(1);
    const { spotter } = oeil((ids) => [
      { photoId: ids[0]!, label: "tampon de passeport", score: 75, corners: COINS },
    ]);
    await settlePhotoStickers(depsAvec(spotter), memo.id);

    const [sticker] = await photoStickersOf(harness.context, memo.id);
    expect(sticker?.entryId).toBe(entryIds[0]);
    expect(sticker?.label).toBe("tampon de passeport");
    expect(sticker?.url).toMatch(/\/v1\/trip-stickers\/[0-9a-f-]{36}\.png$/);
    expect(sticker?.width).toBeGreaterThan(0);

    // Et l'adresse se sert vraiment.
    const reponse = await harness.app.inject({
      method: "GET",
      url: new URL(sticker!.url).pathname,
    });
    expect(reponse.statusCode).toBe(200);
    expect(reponse.headers["content-type"]).toBe("image/png");
  });

  it("refuse de servir autre chose qu'un sticker", async () => {
    expect(photoStickerUrl("https://api.test", "photo/abc.jpg")).toBeNull();
    expect(photoStickerUrl("https://api.test", "sticker/pas-un-uuid.png")).toBeNull();
    const reponse = await harness.app.inject({ method: "GET", url: "/v1/trip-stickers/../secret" });
    expect(reponse.statusCode).toBe(404);
  });
});
