import { randomUUID } from "node:crypto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { FakeRedactor } from "../src/services/redaction.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **La manière d'être rédigé** (T292, Hugo — « choisir sa manière d'être
 * rédigé, dans la personnalisation du carnet : plusieurs façons proposées, plus
 * ses propres indications. Changer de méthode annonce que tout va être repris,
 * et c'est réservé aux abonnés illimités — sauf carnet d'une seule étape »).
 *
 * Trois choses se tiennent ici, et aucune ne se voit dans un test unitaire :
 * le **garde-fou** (402 pour qui n'est pas abonné sur un carnet de plus d'une
 * étape), la **reprise** qui part au changement et pas à l'identique, et ce
 * que la route **sert** à l'app — qui ne recalcule pas la règle.
 */

let harness: TestHarness;
let owner: { accountId: string; authorization: string };

beforeEach(async () => {
  if (!harness) harness = await createHarness({ redactor: new FakeRedactor() });
  await resetDatabase(harness.prisma);
  owner = await registerAccount(harness.app);
});

afterAll(async () => {
  await harness?.close();
});

async function createTrip(): Promise<string> {
  const response = await harness.app.inject({
    method: "POST",
    url: "/v1/memos",
    headers: { authorization: owner.authorization },
    payload: {
      title: "Grèce 2026",
      authors: "Max",
      theme: "voyage",
      startDate: "2026-08-26T00:00:00.000Z",
      endDate: "2026-09-04T00:00:00.000Z",
    },
  });
  expect(response.statusCode).toBe(201);
  return response.json<{ id: string }>().id;
}

interface SettingsJson {
  redaction: {
    manner: string | null;
    notes: string | null;
    isAvailable: boolean;
    reason: string;
  };
}

async function readSettings(memoId: string): Promise<SettingsJson> {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}/settings`,
    headers: { authorization: owner.authorization },
  });
  expect(response.statusCode, response.body).toBe(200);
  return response.json<SettingsJson>();
}

async function patch(memoId: string, payload: Record<string, unknown>) {
  return harness.app.inject({
    method: "PATCH",
    url: `/v1/trips/${memoId}/settings`,
    headers: { authorization: owner.authorization },
    payload,
  });
}

/** Un carnet de deux étapes : au-delà d'une, le garde-fou s'applique. */
async function giveTwoSteps(memoId: string): Promise<void> {
  for (const number of [1, 2]) {
    await harness.prisma.memoStep.create({
      data: { id: randomUUID(), memoId, number, placeName: `Étape ${number}` },
    });
  }
}

/** Fait de ce compte un abonné illimité, comme l'achat le fait. */
async function subscribe(): Promise<void> {
  await harness.prisma.subscription.create({
    data: {
      id: randomUUID(),
      accountId: owner.accountId,
      provider: "stripe",
      status: "active",
      priceCents: 999,
      renewsAt: new Date(Date.now() + 30 * 24 * 3600 * 1000),
    },
  });
}

describe("ce que la route sert", () => {
  it("ouvre le réglage sur un carnet neuf, sans abonnement", async () => {
    const memoId = await createTrip();

    const { redaction } = await readSettings(memoId);

    // Zéro étape : la reprise ne coûte rien, un paywall y serait posé sur rien.
    expect(redaction).toEqual({
      manner: null,
      notes: null,
      isAvailable: true,
      reason: "single_step",
    });
  });

  it("le ferme dès la deuxième étape, sans abonnement", async () => {
    const memoId = await createTrip();
    await giveTwoSteps(memoId);

    const { redaction } = await readSettings(memoId);

    expect(redaction.isAvailable).toBe(false);
    expect(redaction.reason).toBe("needs_unlimited");
  });

  it("l'ouvre à un abonné, quel que soit le carnet", async () => {
    const memoId = await createTrip();
    await giveTwoSteps(memoId);
    await subscribe();

    const { redaction } = await readSettings(memoId);

    expect(redaction.isAvailable).toBe(true);
    expect(redaction.reason).toBe("unlimited");
  });
});

describe("le garde-fou", () => {
  it("refuse la manière en 402 à qui n'est pas abonné, sur plus d'une étape", async () => {
    const memoId = await createTrip();
    await giveTwoSteps(memoId);

    const response = await patch(memoId, { redactionManner: "literary" });

    expect(response.statusCode).toBe(402);
    expect(response.json<{ code: string }>().code).toBe("redaction_manner_needs_unlimited");
    // **Rien n'est écrit** : un refus qui aurait quand même posé la colonne
    // laisserait le carnet dans une manière que son propriétaire ne peut pas
    // changer.
    const memo = await harness.prisma.memo.findUniqueOrThrow({
      where: { id: memoId },
      select: { redactionManner: true },
    });
    expect(memo.redactionManner).toBeNull();
  });

  it("refuse aussi « tout faire reprendre »", async () => {
    const memoId = await createTrip();
    await giveTwoSteps(memoId);

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memoId}/redaction/rewrite`,
      headers: { authorization: owner.authorization },
    });

    expect(response.statusCode).toBe(402);
  });

  it("laisse passer la manière sur un carnet d'une seule étape", async () => {
    const memoId = await createTrip();
    await harness.prisma.memoStep.create({
      data: { id: randomUUID(), memoId, number: 1, placeName: "Naxos" },
    });

    const response = await patch(memoId, { redactionManner: "factual" });

    expect(response.statusCode, response.body).toBe(200);
    expect(response.json<SettingsJson>().redaction.manner).toBe("factual");
  });

  it("refuse une manière qu'il ne connaît pas", async () => {
    const memoId = await createTrip();

    const response = await patch(memoId, { redactionManner: "en-alexandrins" });

    // L'énumération est close côté serveur : une clé inconnue est un refus, pas
    // un silence.
    expect(response.statusCode).toBe(400);
  });
});

describe("ce qui s'enregistre", () => {
  it("retient la manière et les indications, et les rend telles quelles", async () => {
    const memoId = await createTrip();

    await patch(memoId, { redactionManner: "literary" });
    const response = await patch(memoId, { redactionNotes: "  Appelle-moi Max.  " });

    expect(response.statusCode, response.body).toBe(200);
    const { redaction } = response.json<SettingsJson>();
    expect(redaction.manner).toBe("literary");
    expect(redaction.notes).toBe("Appelle-moi Max.");
  });

  it("efface les indications sur un `null`", async () => {
    const memoId = await createTrip();
    await patch(memoId, { redactionNotes: "Garde mes mots." });

    const response = await patch(memoId, { redactionNotes: null });

    expect(response.json<SettingsJson>().redaction.notes).toBeNull();
  });

  it("coupe des indications trop longues plutôt que de les refuser", async () => {
    const memoId = await createTrip();

    const response = await patch(memoId, { redactionNotes: "a".repeat(900) });

    // 600 est la borne du corps de requête : au-delà, c'est un refus franc, et
    // l'app compte avant d'envoyer.
    expect(response.statusCode).toBe(400);
  });

  it("remet la manière par défaut sur un `null`", async () => {
    const memoId = await createTrip();
    await patch(memoId, { redactionManner: "factual" });

    const response = await patch(memoId, { redactionManner: null });

    expect(response.statusCode, response.body).toBe(200);
    expect(response.json<SettingsJson>().redaction.manner).toBeNull();
  });
});
