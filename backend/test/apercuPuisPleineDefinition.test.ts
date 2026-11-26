import { randomUUID } from "node:crypto";
import { Jimp } from "jimp";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **L'aperçu léger d'abord, la pleine définition ensuite** (T309, Hugo).
 *
 * Six photos d'iPhone font 7,3 Mo, soit 58 s à 1 Mb/s — le délai d'abandon du
 * client, qui renvoie alors le tour dans la file (T295). Le téléphone envoie
 * donc 1 200 px tout de suite (~230 ko), et monte la vraie photo ensuite, une
 * à la fois.
 */

let harness: TestHarness;
let owner: { accountId: string; authorization: string };

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
  owner = await registerAccount(harness.app);
});

afterAll(async () => {
  await harness?.close();
});

/** Une image lisible, à la taille demandée. */
async function image(side: number, tint = 0x3fa7d6ff): Promise<Buffer> {
  return Buffer.from(await new Jimp({ width: side, height: Math.round(side * 0.66), color: tint }).getBuffer("image/jpeg"));
}

async function createTrip(): Promise<string> {
  const response = await harness.app.inject({
    method: "POST",
    url: "/v1/memos",
    headers: { authorization: owner.authorization },
    payload: { title: "Porto", authors: "Maÿlis", theme: "voyage" },
  });
  expect(response.statusCode).toBe(201);
  return response.json<{ id: string }>().id;
}

/** Des photos envoyées dans le fil, en aperçu ou en pleine définition. */
async function sendPhotos(memoId: string, content: Buffer, lightweight: boolean): Promise<void> {
  const boundary = `----memobook${Date.now()}`;
  const parts: Buffer[] = [
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="id"\r\n\r\n${randomUUID()}\r\n`),
  ];
  if (lightweight) {
    parts.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="lightweight"\r\n\r\n1\r\n`));
  }
  parts.push(
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="photo.jpg"\r\n` +
        "Content-Type: image/jpeg\r\n\r\n",
    ),
    content,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  );

  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization, "content-type": `multipart/form-data; boundary=${boundary}` },
    payload: Buffer.concat(parts),
  });
  expect(response.statusCode, response.body).toBe(201);
}

/** La pleine définition, montée ensuite pour un souvenir précis. */
function replacePhoto(entryId: string, content: Buffer, authorization = owner.authorization) {
  const boundary = `----memobookfull${Date.now()}`;
  const payload = Buffer.concat([
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="photo.jpg"\r\n` +
        "Content-Type: image/jpeg\r\n\r\n",
    ),
    content,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);
  return harness.app.inject({
    method: "PUT",
    url: `/v1/entries/${entryId}/photo`,
    headers: { authorization, "content-type": `multipart/form-data; boundary=${boundary}` },
    payload,
  });
}

async function photoOf(memoId: string) {
  return harness.prisma.entry.findFirstOrThrow({ where: { memoId, kind: "photo" }, include: { media: true } });
}

describe("l'aperçu léger, puis la pleine définition", () => {
  it("se dit aperçu, et ne se fait pas juger sur sa netteté", async () => {
    const memoId = await createTrip();
    await sendPhotos(memoId, await image(1_200), true);

    const entry = await photoOf(memoId);
    expect(entry.media?.isLightweight).toBe(true);
    // Le sens se lit sur n'importe quelle taille…
    expect(entry.photoIsLandscape).toBe(true);
    expect(entry.photoWidthPx).toBe(1_200);
    // …la netteté, non : le barème est calibré sur 2400 px.
    expect(entry.photoSharpness).toBeNull();
    expect(entry.photoVerdict).toBeNull();
  });

  it("une photo envoyée en entier se juge tout de suite, comme avant", async () => {
    const memoId = await createTrip();
    await sendPhotos(memoId, await image(2_400), false);

    const entry = await photoOf(memoId);
    expect(entry.media?.isLightweight).toBe(false);
    expect(entry.photoSharpness).not.toBeNull();
  });

  it("la pleine définition remplace l'aperçu, et c'est elle qu'on juge", async () => {
    const memoId = await createTrip();
    await sendPhotos(memoId, await image(1_200), true);
    const apercu = await photoOf(memoId);
    const cleDeLApercu = apercu.media!.storageKey;

    const response = await replacePhoto(apercu.id, await image(2_400, 0xd64f3fff));
    expect(response.statusCode).toBe(200);

    const plein = await photoOf(memoId);
    expect(plein.media?.isLightweight).toBe(false);
    expect(plein.media?.storageKey).not.toBe(cleDeLApercu);
    expect(plein.photoWidthPx).toBe(2_400);
    // La netteté arrive avec la vraie photo (T265).
    expect(plein.photoSharpness).not.toBeNull();
    expect(plein.photoVerdict).not.toBeNull();
    // Et l'aperçu ne traîne pas dans le stockage.
    expect(await harness.context.storage.get(cleDeLApercu).catch(() => null)).toBeNull();
  });

  /** Le téléphone peut perdre le reçu : renvoyer ne doit rien casser. */
  it("accepte un second envoi de la pleine définition", async () => {
    const memoId = await createTrip();
    await sendPhotos(memoId, await image(1_200), true);
    const entry = await photoOf(memoId);

    expect((await replacePhoto(entry.id, await image(2_400))).statusCode).toBe(200);
    expect((await replacePhoto(entry.id, await image(2_400))).statusCode).toBe(200);
    expect((await photoOf(memoId)).media?.isLightweight).toBe(false);
  });

  it("n'appartient qu'à qui voit le voyage", async () => {
    const memoId = await createTrip();
    await sendPhotos(memoId, await image(1_200), true);
    const entry = await photoOf(memoId);

    const etranger = await registerAccount(harness.app, "quelqu-un-d-autre@memobook.app");
    const response = await replacePhoto(entry.id, await image(2_400), etranger.authorization);
    expect(response.statusCode).toBe(404);
  });

  it("refuse ce qui n'est pas une photo", async () => {
    const memoId = await createTrip();
    const texte = await harness.prisma.entry.create({
      data: { memoId, kind: "text", status: "ready", transcript: "Écrit au clavier." },
    });

    const response = await replacePhoto(texte.id, await image(2_400));
    expect(response.statusCode).toBe(400);
  });
});
