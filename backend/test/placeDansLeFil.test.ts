import { randomUUID } from "node:crypto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **Une bulle garde la place où elle a été posée** (T309, Hugo — « elles
 * restent en bas du fil et remontent au mauvais endroit à l'envoi, alors
 * qu'elles devraient garder leur place dans la chronologie, envoyées ou
 * non »).
 *
 * Les photos de Maÿlis attendent le réseau pendant des jours. Rangées à leur
 * **arrivée** — ce que faisait `seq` seul —, elles tombaient sous tout ce qui
 * avait été dit entre-temps. L'app envoie donc l'instant du geste, et le fil
 * s'ordonne dessus.
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

/** Un texte dit dans le fil, posé à l'instant qu'on veut — ou une puce. */
async function say(
  memoId: string,
  text: string,
  postedAt?: string,
  suggestionId?: string,
): Promise<string> {
  const id = randomUUID();
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization },
    payload: {
      id,
      kind: "text",
      text,
      ...(postedAt ? { postedAt } : {}),
      ...(suggestionId ? { suggestionId } : {}),
    },
  });
  expect(response.statusCode).toBe(201);
  return id;
}

interface ThreadJson {
  messages: { id: string; author: string; postedAt: string; seq: number; body: { kind: string } }[];
}

async function readThread(memoId: string): Promise<ThreadJson["messages"]> {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization },
  });
  expect(response.statusCode).toBe(200);
  return response.json<ThreadJson>().messages;
}

describe("la place d'une bulle dans le fil", () => {
  it("est celle où le voyageur l'a posée, pas celle de son arrivée", async () => {
    const memoId = await createTrip();

    // Dit aujourd'hui, et arrivé tout de suite.
    const aujourdhui = await say(memoId, "On a marché jusqu'au phare ce matin.");
    // Posé avant-hier dans le métro, arrivé maintenant : il se range **avant**.
    const avantHier = await say(memoId, "Le marché de Bolhão, et ses poissons.", "2026-11-24T09:30:00.000Z");

    const messages = await readThread(memoId);
    const place = (id: string) => messages.findIndex((message) => message.id === id);

    expect(place(avantHier)).toBeGreaterThanOrEqual(0);
    expect(place(avantHier)).toBeLessThan(place(aujourdhui));
    // Et le rang d'arrivée dit, lui, l'inverse : c'est bien l'instant du
    // geste qui range, pas `seq`.
    expect(messages[place(avantHier)]!.seq).toBeGreaterThan(messages[place(aujourdhui)]!.seq);
  });

  /**
   * Et la réponse de MEMO ne reste pas seule au bas du fil : elle se range
   * avec la question, sinon l'échange se lirait coupé en deux.
   */
  it("emporte la réponse de MEMO avec la question", async () => {
    const memoId = await createTrip();
    await say(memoId, "Ce que je dis maintenant.");
    // Une puce, et non un texte libre : depuis T296, un souvenir comme une
    // précision ne reçoit **aucune bulle** — c'est la pastille qui répond, et
    // il n'y aurait donc plus de réponse à ranger. « Plus tard » en reçoit
    // une, et c'est elle qui doit suivre sa question.
    const avantHier = await say(memoId, "Plus tard", "2026-11-24T09:30:00.000Z", "later");

    const messages = await readThread(memoId);
    const question = messages.findIndex((message) => message.id === avantHier);
    const reponse = messages.findIndex(
      (message, index) => index > question && message.author === "memo",
    );

    // La réponse suit immédiatement sa question, et toutes deux restent avant
    // ce qui a été dit aujourd'hui.
    expect(reponse).toBe(question + 1);
    expect(messages[reponse]!.postedAt).toBe(messages[question]!.postedAt);
  });

  it("ne bouge plus une fois le tour arrivé", async () => {
    const memoId = await createTrip();
    const posteHier = await say(memoId, "Posé hier, arrivé maintenant.", "2026-11-25T20:00:00.000Z");

    const avant = (await readThread(memoId)).findIndex((message) => message.id === posteHier);
    // Une autre bulle arrive après : la première ne se déplace pas.
    await say(memoId, "Et maintenant je raconte autre chose.");
    const apres = (await readThread(memoId)).findIndex((message) => message.id === posteHier);

    expect(apres).toBe(avant);
  });

  /** Une app d'avant le 26/11/2026 n'envoie rien : le fil se range comme avant. */
  it("retombe sur l'ordre d'arrivée quand l'app ne dit rien", async () => {
    const memoId = await createTrip();
    const premier = await say(memoId, "D'abord.");
    const second = await say(memoId, "Ensuite.");

    const messages = await readThread(memoId);
    const place = (id: string) => messages.findIndex((message) => message.id === id);
    expect(place(premier)).toBeLessThan(place(second));
  });
});
