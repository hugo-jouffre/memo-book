import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * « Valider cette étape » : confirme l'étape et déclenche en fond une nouvelle
 * génération du carnet — mais une seule fois, et jamais sur un carnet vide.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

async function createMemo(authorization: string): Promise<string> {
  const response = await harness.app.inject({
    method: "POST",
    url: "/v1/memos",
    headers: { authorization },
    payload: { title: "Rome 2026", authors: "Hugo", theme: "voyage" },
  });
  expect(response.statusCode).toBe(201);
  return response.json<{ id: string }>().id;
}

async function addTextEntry(memoId: string, authorization: string) {
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
}

/**
 * L'étape que le souvenir a fait naître : depuis T227, un souvenir range
 * lui-même le voyage en étapes (`services/tripFacts.ts`).
 */
async function stepOfTheMemory(memoId: string) {
  const steps = await harness.prisma.memoStep.findMany({ where: { memoId } });
  expect(steps).toHaveLength(1);
  return steps[0]!;
}

function validateStep(memoId: string, stepId: string, authorization: string) {
  return harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/steps/${stepId}/validate`,
    headers: { authorization },
  });
}

describe("valider une étape", () => {
  it("confirme l'étape et déclenche une génération du carnet", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createMemo(authorization);
    await addTextEntry(memoId, authorization);
    const step = await stepOfTheMemory(memoId);

    const response = await validateStep(memoId, step.id, authorization);
    expect(response.statusCode).toBe(200);

    const body = response.json<{ steps: { id: string; validatedAt: string | null }[] }>();
    expect(body.steps.find((s) => s.id === step.id)?.validatedAt).not.toBeNull();

    // File en ligne en test : la génération est terminée avant la réponse.
    expect(await harness.prisma.render.count({ where: { memoId } })).toBe(1);
  });

  it("est idempotente : un deuxième appel ne redéclenche pas de génération", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createMemo(authorization);
    await addTextEntry(memoId, authorization);
    const step = await stepOfTheMemory(memoId);

    const first = await validateStep(memoId, step.id, authorization);
    expect(first.statusCode).toBe(200);
    const second = await validateStep(memoId, step.id, authorization);
    expect(second.statusCode).toBe(200);

    expect(await harness.prisma.render.count({ where: { memoId } })).toBe(1);
  });

  it("confirme l'étape sans générer de carnet quand le voyage n'a encore aucun souvenir", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createMemo(authorization);
    const step = await harness.prisma.memoStep.create({ data: { memoId, number: 1 } });

    const response = await validateStep(memoId, step.id, authorization);
    expect(response.statusCode).toBe(200);

    const body = response.json<{ steps: { id: string; validatedAt: string | null }[] }>();
    expect(body.steps.find((s) => s.id === step.id)?.validatedAt).not.toBeNull();
    expect(await harness.prisma.render.count({ where: { memoId } })).toBe(0);
  });

  it("ne crée pas de rendu concurrent quand un rendu est déjà en cours", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createMemo(authorization);
    await addTextEntry(memoId, authorization);
    const step = await stepOfTheMemory(memoId);

    // Simule une génération déjà en cours (ex. déclenchée juste avant, par
    // `POST /renders`), sans passer par la file — la garde de
    // `ensureRenderInProgress` doit la retrouver plutôt qu'en enfiler une autre.
    await harness.prisma.render.create({ data: { memoId, status: "pending" } });

    const response = await validateStep(memoId, step.id, authorization);
    expect(response.statusCode).toBe(200);
    expect(await harness.prisma.render.count({ where: { memoId } })).toBe(1);
  });

  it("renvoie 404 pour une étape introuvable", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createMemo(authorization);

    const response = await validateStep(memoId, "00000000-0000-0000-0000-000000000000", authorization);
    expect(response.statusCode).toBe(404);
  });

  it("renvoie 404 — pas 403 — à un compte étranger au voyage", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const stranger = await registerAccount(harness.app, "inconnu@memobook.app");
    const memoId = await createMemo(owner.authorization);
    const step = await harness.prisma.memoStep.create({ data: { memoId, number: 1 } });

    const response = await validateStep(memoId, step.id, stranger.authorization);
    expect(response.statusCode).toBe(404);
  });
});

describe("l'aperçu du carnet pendant une régénération", () => {
  it("garde le PDF du dernier rendu prêt pendant qu'un nouveau compose", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createMemo(authorization);
    await addTextEntry(memoId, authorization);

    const firstRender = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memoId}/renders`,
      headers: { authorization },
    });
    const { pdfUrl } = firstRender.json<{ pdfUrl: string }>();
    expect(pdfUrl).toMatch(/^https:\/\//);

    // Une régénération en fond enfile un nouveau rendu `pending`, sans passer
    // par la file (pour figer l'état intermédiaire que l'app doit traverser).
    await harness.prisma.render.create({ data: { memoId, status: "pending" } });

    const preview = await harness.app.inject({
      method: "GET",
      url: `/v1/memos/${memoId}/preview`,
      headers: { authorization },
    });

    expect(preview.statusCode).toBe(200);
    const body = preview.json<{ status: { status: string }; pdfUrl: string | null }>();
    expect(body.status.status).toBe("composing");
    expect(body.pdfUrl).toBe(pdfUrl);
  });
});
