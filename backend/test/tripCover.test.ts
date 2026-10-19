import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { Jimp } from "jimp";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **La couverture d'un voyage** (Hugo, 15/10/2026).
 *
 * La règle : celle qu'on a choisie, sinon la plus récente des photos
 * **paysage** de la conversation, et le motif de la marque s'il n'y en a
 * aucune. Cette couverture-là est **la carte du voyage**, large : un portrait
 * s'y recadre en une bande prise au milieu. ⚠️ La couverture *imprimée* du
 * carnet est verticale et ne suit pas cette règle (`routes/covers.ts`).
 *
 * Elle vit dans une requête (`tripInclude`, `routes/home.ts`) et non dans une
 * fonction : c'est le filtre, le tri et le `take: 1` qui la portent, pour ne
 * pas balayer toutes les photos d'un voyage à chaque ouverture de l'accueil.
 * D'où des tests sur la vraie base plutôt que sur une fonction pure.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

async function createTrip(authorization: string): Promise<string> {
  const response = await harness.app.inject({
    method: "POST",
    url: "/v1/trips",
    headers: { authorization },
    payload: { title: "Italie 2026", startDate: "2026-01-05", endDate: "2026-01-12" },
  });
  expect(response.statusCode).toBeLessThan(300);
  return response.json<{ trip: { id: string } }>().trip.id;
}

/** La couverture que l'accueil annonce pour ce voyage. */
async function coverOf(authorization: string, memoId: string): Promise<string | null> {
  const response = await harness.app.inject({ method: "GET", url: "/v1/home", headers: { authorization } });
  expect(response.statusCode).toBe(200);
  const trip = response
    .json<{ trips: { id: string; coverPhotoUrl: string | null }[] }>()
    .trips.find((candidate) => candidate.id === memoId);
  return trip?.coverPhotoUrl ?? null;
}

async function jpeg(width: number, height: number): Promise<Buffer> {
  return Buffer.from(await new Jimp({ width, height, color: 0x3fa7d6ff }).getBuffer("image/jpeg"));
}

/**
 * Une photo déposée dans la conversation, par la vraie route : c'est elle qui
 * mesure le sens de l'image, et c'est ce chemin-là qu'on veut vérifier.
 */
async function sendPhoto(
  authorization: string,
  memoId: string,
  size: { width: number; height: number },
  capturedAt: string,
): Promise<void> {
  const boundary = `----memobook${Math.random().toString(16).slice(2)}`;
  const content = await jpeg(size.width, size.height);
  const payload = Buffer.concat([
    Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="id"\r\n\r\n${crypto.randomUUID()}\r\n` +
        `--${boundary}\r\nContent-Disposition: form-data; name="capturedAt"\r\n\r\n${capturedAt}\r\n` +
        `--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="photo.jpg"\r\n` +
        `Content-Type: image/jpeg\r\n\r\n`,
    ),
    content,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ]);

  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization, "content-type": `multipart/form-data; boundary=${boundary}` },
    payload,
  });
  expect(response.statusCode).toBe(201);
}

describe("la couverture d'un voyage", () => {
  it("prend la photo paysage envoyée dans la conversation", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);

    expect(await coverOf(authorization, memoId)).toBeNull();

    await sendPhoto(authorization, memoId, { width: 1200, height: 900 }, "2026-01-06T09:00:00.000Z");

    expect(await coverOf(authorization, memoId)).toBeTruthy();
  });

  // Le cœur de la demande : plutôt pas de couverture qu'une couverture coupée.
  it("faute de paysage, prend le plus récent des portraits (18/10/2026)", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);

    await sendPhoto(authorization, memoId, { width: 900, height: 1200 }, "2026-01-06T09:00:00.000Z");
    const premier = await coverOf(authorization, memoId);
    expect(premier).not.toBeNull();
    await sendPhoto(authorization, memoId, { width: 900, height: 1600 }, "2026-01-07T09:00:00.000Z");

    const second = await coverOf(authorization, memoId);
    expect(second).not.toBeNull();
    expect(second).not.toBe(premier);
  });

  it("préfère la plus récente des paysages, et ignore un portrait plus récent", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);

    await sendPhoto(authorization, memoId, { width: 1200, height: 900 }, "2026-01-06T09:00:00.000Z");
    const ancienne = await coverOf(authorization, memoId);

    await sendPhoto(authorization, memoId, { width: 1100, height: 880 }, "2026-01-08T09:00:00.000Z");
    const recente = await coverOf(authorization, memoId);
    expect(recente).not.toBe(ancienne);

    // Un portrait arrivé après ne reprend pas la place.
    await sendPhoto(authorization, memoId, { width: 900, height: 1200 }, "2026-01-09T09:00:00.000Z");
    expect(await coverOf(authorization, memoId)).toBe(recente);
  });

  /**
   * Six photos d'un même message partagent leur `capturedAt` à la
   * milliseconde. Sans `createdAt` puis `id` pour départager, Postgres
   * choisissait librement et la couverture changeait d'une requête à l'autre.
   */
  it("choisit la même photo à chaque lecture quand les dates sont identiques", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);

    const capturedAt = new Date("2026-01-06T09:00:00.000Z");
    for (let index = 0; index < 6; index += 1) {
      const media = await harness.prisma.mediaAsset.create({
        data: { storageKey: `photo/${crypto.randomUUID()}.jpg`, mimeType: "image/jpeg", bytes: 1024 },
      });
      await harness.prisma.entry.create({
        data: {
          memoId,
          mediaId: media.id,
          kind: "photo",
          status: "ready",
          capturedAt,
          photoWidthPx: 1200,
          photoHeightPx: 900,
          photoIsLandscape: true,
        },
      });
    }

    const lectures = await Promise.all(
      Array.from({ length: 5 }, () => coverOf(authorization, memoId)),
    );
    expect(lectures[0]).toBeTruthy();
    expect(new Set(lectures).size).toBe(1);
  });

  it("laisse toujours gagner la couverture choisie à la main", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);

    await sendPhoto(authorization, memoId, { width: 1200, height: 900 }, "2026-01-06T09:00:00.000Z");

    const choisie = "https://cdn.example.test/choisie.jpg";
    await harness.prisma.memo.update({ where: { id: memoId }, data: { coverPhotoUrl: choisie } });

    expect(await coverOf(authorization, memoId)).toBe(choisie);
  });
});
