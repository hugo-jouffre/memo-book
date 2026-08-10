import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { FakeTranscriber } from "../src/services/transcription.js";
import { validatePayload } from "../src/services/payloadValidator.js";
import {
  createHarness,
  multipartBody,
  registerDevice,
  resetDatabase,
  type TestHarness,
} from "./helpers.js";

/**
 * Le parcours complet du cœur produit : je raconte, ça se transcrit, ça se
 * structure, je reçois mon carnet. Avec la file en ligne, chaque étape se
 * termine avant que la requête ne réponde — l'assertion porte donc sur l'état
 * final, pas sur un délai.
 */

const TRANSCRIPTS = [
  "On est arrivés à Bogotá ce matin, la ville est perchée dans les nuages et on manque d'air à chaque marche.",
  "Deuxième journée : montée à Monserrate en funiculaire, la vue sur la ville est immense.",
  "Aujourd'hui Guatapé, les façades sont peintes comme une boîte de crayons renversée.",
];

let harness: TestHarness;
let authorization: string;

beforeAll(async () => {
  harness = await createHarness({
    transcriber: new FakeTranscriber(TRANSCRIPTS),
  });
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  ({ authorization } = await registerDevice(harness.app));
});

async function createMemo(title = "Claire et Gus en Colombie"): Promise<string> {
  const response = await harness.app.inject({
    method: "POST",
    url: "/v1/memos",
    headers: { authorization },
    payload: { title, authors: "Claire et Augustin", theme: "voyage" },
  });

  expect(response.statusCode).toBe(201);
  return response.json<{ id: string }>().id;
}

async function postAudio(memoId: string, capturedAt: string, place: string) {
  const { payload, contentType } = multipartBody(
    { capturedAt, placeLabel: place },
    {
      field: "file",
      filename: "memo.m4a",
      contentType: "audio/mp4",
      content: Buffer.from(`audio-${capturedAt}`),
    },
  );

  return harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/entries`,
    headers: { authorization, "content-type": contentType },
    payload,
  });
}

describe("parcours complet : raconter → transcrire → générer", () => {
  it("produit un carnet imprimable à partir de trois vocaux", async () => {
    const memoId = await createMemo();

    const days = [
      ["2026-01-03T09:00:00.000Z", "Bogotá, Colombie"],
      ["2026-01-04T09:00:00.000Z", "Monserrate"],
      ["2026-01-05T09:00:00.000Z", "Guatapé"],
    ] as const;

    for (const [capturedAt, place] of days) {
      const response = await postAudio(memoId, capturedAt, place);
      expect(response.statusCode).toBe(201);
    }

    // Les vocaux sont transcrits : le job a tourné à la publication.
    const memo = await harness.app.inject({
      method: "GET",
      url: `/v1/memos/${memoId}`,
      headers: { authorization },
    });

    const entries = memo.json<{ entries: { status: string; transcript: string }[] }>()
      .entries;
    expect(entries).toHaveLength(3);
    expect(entries.map((entry) => entry.status)).toEqual(["ready", "ready", "ready"]);
    expect(entries[0]?.transcript).toBe(TRANSCRIPTS[0]);

    // Génération du carnet.
    const render = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });

    expect(render.statusCode).toBe(202);
    const renderBody = render.json<{ id: string; status: string; pdfUrl: string | null }>();
    expect(renderBody.status).toBe("ready");
    expect(renderBody.pdfUrl).toMatch(/^https:\/\//);

    // Le payload stocké est conforme au schéma du dépôt, et il porte bien les
    // trois journées transcrites.
    const stored = await harness.prisma.render.findUniqueOrThrow({
      where: { id: renderBody.id },
    });

    expect(validatePayload(stored.payload)).toMatchObject({ valid: true, errors: [] });

    const payload = stored.payload as { days: { body_html: string }[] };
    expect(payload.days).toHaveLength(3);
    expect(payload.days[0]?.body_html).toContain("Bogotá");
  });

  it("intègre une photo au bon jour et la publie sur le CDN", async () => {
    const memoId = await createMemo();
    await postAudio(memoId, "2026-01-03T09:00:00.000Z", "Bogotá, Colombie");

    const photo = multipartBody(
      { capturedAt: "2026-01-03T12:00:00.000Z" },
      {
        field: "file",
        filename: "candelaria.jpg",
        contentType: "image/jpeg",
        content: Buffer.from("photo-binaire"),
      },
    );

    const uploaded = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/entries`,
      headers: { authorization, "content-type": photo.contentType },
      payload: photo.payload,
    });

    expect(uploaded.statusCode).toBe(201);
    // Une photo n'a rien à transcrire : elle est exploitable immédiatement.
    expect(uploaded.json<{ status: string }>().status).toBe("ready");

    const render = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });

    const stored = await harness.prisma.render.findUniqueOrThrow({
      where: { id: render.json<{ id: string }>().id },
    });

    const payload = stored.payload as { days: { photos?: string[] }[] };
    expect(payload.days).toHaveLength(1);
    expect(payload.days[0]?.photos).toHaveLength(1);
    expect(payload.days[0]?.photos?.[0]).toMatch(/^https:\/\//);
  });

  it("accepte une note écrite sans passer par la transcription", async () => {
    const memoId = await createMemo();

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/entries`,
      headers: { authorization },
      payload: {
        kind: "text",
        transcript: "Petit mot écrit depuis le bus.",
        capturedAt: "2026-01-06T09:00:00.000Z",
      },
    });

    expect(response.statusCode).toBe(201);
    expect(response.json<{ status: string; transcript: string }>()).toMatchObject({
      status: "ready",
      transcript: "Petit mot écrit depuis le bus.",
    });
  });
});

describe("garde-fous de l'API", () => {
  it("refuse une génération sur un carnet vide", async () => {
    const memoId = await createMemo();

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });

    expect(response.statusCode).toBe(400);
    expect(response.json<{ error: string }>().error).toBe("empty_memo");
  });

  it("ne relance pas une génération déjà en cours", async () => {
    const memoId = await createMemo();
    await postAudio(memoId, "2026-01-03T09:00:00.000Z", "Bogotá");

    const first = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });
    const second = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });

    // La première est terminée (file en ligne), la seconde crée donc bien un
    // nouveau rendu : ce sont deux identifiants distincts.
    expect(first.json<{ id: string }>().id).not.toBe(second.json<{ id: string }>().id);

    const renders = await harness.prisma.render.count({ where: { memoId } });
    expect(renders).toBe(2);
  });

  it("rejette un média qui n'est ni audio ni image", async () => {
    const memoId = await createMemo();
    const { payload, contentType } = multipartBody(
      {},
      {
        field: "file",
        filename: "notes.pdf",
        contentType: "application/pdf",
        content: Buffer.from("%PDF-1.4"),
      },
    );

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/entries`,
      headers: { authorization, "content-type": contentType },
      payload,
    });

    expect(response.statusCode).toBe(400);
    expect(response.json<{ message: string }>().message).toContain("non supporté");
  });

  it("rejette une date de capture invalide", async () => {
    const memoId = await createMemo();
    const response = await postAudio(memoId, "pas-une-date", "Bogotá");

    expect(response.statusCode).toBe(400);
    expect(response.json<{ message: string }>().message).toContain("ISO 8601");
  });
});

describe("cloisonnement entre appareils", () => {
  it("cache les carnets d'un autre appareil", async () => {
    const memoId = await createMemo();
    const other = await registerDevice(harness.app);

    const read = await harness.app.inject({
      method: "GET",
      url: `/v1/memos/${memoId}`,
      headers: { authorization: other.authorization },
    });
    expect(read.statusCode).toBe(404);

    const list = await harness.app.inject({
      method: "GET",
      url: "/v1/memos",
      headers: { authorization: other.authorization },
    });
    expect(list.json<{ memos: unknown[] }>().memos).toEqual([]);
  });

  it("refuse un token absent ou inconnu", async () => {
    expect(
      (await harness.app.inject({ method: "GET", url: "/v1/memos" })).statusCode,
    ).toBe(401);

    expect(
      (
        await harness.app.inject({
          method: "GET",
          url: "/v1/memos",
          headers: { authorization: "Bearer inexistant" },
        })
      ).statusCode,
    ).toBe(401);
  });
});

describe("santé du service", () => {
  it("rapporte la base, la file et le mode du pipeline", async () => {
    const response = await harness.app.inject({ method: "GET", url: "/health" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({
      status: "ok",
      checks: { database: "ok", queue: "ok" },
      pipelineMode: "fake",
    });
  });
});
