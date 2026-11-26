import { randomUUID } from "node:crypto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { FakeRedactor, type RedactionInput, type RedactionResult } from "../src/services/redaction.js";
import { refreshTripFacts } from "../src/services/tripFacts.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **La date et le lieu d'une étape ne s'affichent qu'une fois compris** (T308).
 *
 * L'étape montrait le jour de l'**enregistrement** et l'écho du lieu que l'app
 * renvoyait avec le vocal — deux choses que personne n'avait dites. Un vocal
 * du dimanche qui raconte vendredi affichait dimanche ; le premier vocal d'une
 * nouvelle ville portait le nom de la précédente.
 *
 * Ce qui s'affiche maintenant : le jour que le récit raconte, le lieu que
 * l'étape a compris, et rien quand on ne sait pas.
 */

/** Un écrivain qui situe ce qu'il raconte, sur commande. */
class DatingRedactor extends FakeRedactor {
  livedFrom: string | null = null;
  livedTo: string | null = null;
  place: string | null = null;

  override async redact(input: RedactionInput): Promise<RedactionResult> {
    const base = await super.redact(input);
    return {
      ...base,
      livedFrom: this.livedFrom,
      livedTo: this.livedTo,
      insights: this.place
        ? { ...base.insights, currentPlace: this.place, cities: [this.place] }
        : base.insights,
    };
  }
}

let harness: TestHarness;
let redactor: DatingRedactor;
let owner: { accountId: string; authorization: string };

beforeEach(async () => {
  if (!harness) {
    redactor = new DatingRedactor();
    harness = await createHarness({ redactor });
  }
  await resetDatabase(harness.prisma);
  redactor.livedFrom = null;
  redactor.livedTo = null;
  redactor.place = null;
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

/**
 * Un récit écrit dans le fil : il crée le souvenir, et sa fiche.
 *
 * ⚠️ **Il est horodaté par le serveur**, à l'instant de l'envoi — un message
 * texte ne porte pas de `capturedAt` (seuls un vocal et des photos en
 * envoient un, `routes/chat.ts`). C'est très bien pour ce qu'on vérifie ici :
 * l'enregistrement est d'aujourd'hui, le récit raconte le mois d'août, et les
 * deux dates ne peuvent pas se confondre par accident.
 */
async function tell(memoId: string, text: string): Promise<void> {
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization },
    payload: { id: randomUUID(), kind: "text", text },
  });
  expect(response.statusCode).toBe(201);
}

interface TripJson {
  steps: { id: string; placeName: string | null; startDate: string | null; endDate: string | null }[];
}

async function readTrip(memoId: string): Promise<TripJson> {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}`,
    headers: { authorization: owner.authorization },
  });
  expect(response.statusCode).toBe(200);
  return response.json<TripJson>();
}

interface ThreadJson {
  messages: {
    body:
      | { kind: "transcript"; transcript: { placeName: string | null; livedFrom: string | null; livedTo: string | null; capturedAt: string } }
      | { kind: string };
  }[];
}

async function readCard(memoId: string) {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization },
  });
  expect(response.statusCode).toBe(200);
  const thread = response.json<ThreadJson>();
  const card = thread.messages.find((message) => message.body.kind === "transcript");
  expect(card).toBeDefined();
  return card!.body as Extract<ThreadJson["messages"][number]["body"], { kind: "transcript" }>;
}

describe("la date d'une étape", () => {
  it("est celle que le récit raconte, et non celle de l'enregistrement", async () => {
    redactor.livedFrom = "2026-08-28";
    const memoId = await createTrip();
    const avantEnvoi = Date.now();
    await tell(memoId, "Hier on a marché jusqu'au phare, et on s'est baignés en rentrant.");

    const trip = await readTrip(memoId);
    expect(trip.steps).toHaveLength(1);
    // Une journée : les deux dates tombent le même jour, et l'app affiche une
    // date précise.
    expect(trip.steps[0]?.startDate).toBe("2026-08-28T00:00:00.000Z");
    expect(trip.steps[0]?.endDate).toBe("2026-08-28T00:00:00.000Z");

    // Les dates d'enregistrement restent en base : elles ordonnent le carnet
    // et datent le relevé météo. Elles sont d'aujourd'hui — le récit, lui,
    // raconte le mois d'août, et c'est tout l'objet du ticket.
    const step = await harness.prisma.memoStep.findFirstOrThrow({ where: { memoId } });
    expect(step.startDate!.getTime()).toBeGreaterThanOrEqual(avantEnvoi);
    expect(step.livedFromDay?.toISOString()).toBe("2026-08-28T00:00:00.000Z");
  });

  it("devient une tranche quand le récit couvre une période", async () => {
    redactor.livedFrom = "2026-08-28";
    redactor.livedTo = "2026-08-30";
    const memoId = await createTrip();
    await tell(memoId, "On a passé trois jours à Naxos, à ne rien faire d'autre que nager.");

    const trip = await readTrip(memoId);
    expect(trip.steps[0]?.startDate).toBe("2026-08-28T00:00:00.000Z");
    expect(trip.steps[0]?.endDate).toBe("2026-08-30T00:00:00.000Z");
  });

  /**
   * Le cas le plus fréquent : un voyageur qui raconte sa journée ne la date
   * pas. L'étape n'affiche alors aucune date — avant T308, elle affichait le
   * jour de l'enregistrement comme si c'était celui qu'on avait vécu.
   */
  it("n'existe pas quand le récit ne s'est pas situé", async () => {
    const memoId = await createTrip();
    await tell(memoId, "On a marché jusqu'au phare, et on s'est baignés en rentrant.");

    const trip = await readTrip(memoId);
    expect(trip.steps[0]?.startDate).toBeNull();
    expect(trip.steps[0]?.endDate).toBeNull();
  });

  /** « Une étape se raconte en plusieurs fois » : deux séances, une tranche. */
  it("s'élargit quand une seconde séance raconte un autre jour de la même étape", async () => {
    const memoId = await createTrip();
    redactor.livedFrom = "2026-08-28";
    await tell(memoId, "Hier, la montée au monastère sous un soleil de plomb.");
    redactor.livedFrom = "2026-08-29";
    await tell(memoId, "Et le lendemain, la plage de galets au bout du chemin.");

    // Les deux récits font deux étapes (`continuesPrevious` est faux chez le
    // rédacteur simulé) : chacune porte le jour qu'elle raconte.
    const trip = await readTrip(memoId);
    expect(trip.steps.map((step) => step.startDate)).toEqual([
      "2026-08-28T00:00:00.000Z",
      "2026-08-29T00:00:00.000Z",
    ]);

    // Réunies à la main dans la même étape, elles en font une tranche.
    const [first, second] = await harness.prisma.memoStep.findMany({ where: { memoId }, orderBy: { number: "asc" } });
    await harness.prisma.entry.updateMany({
      where: { memoId, stepId: second!.id },
      data: { stepId: first!.id, continuesPreviousStep: true },
    });
    await refreshTripFacts(harness.prisma, memoId);

    const reunited = await readTrip(memoId);
    expect(reunited.steps).toHaveLength(1);
    expect(reunited.steps[0]?.startDate).toBe("2026-08-28T00:00:00.000Z");
    expect(reunited.steps[0]?.endDate).toBe("2026-08-29T00:00:00.000Z");
  });
});

describe("la fiche du fil", () => {
  it("montre le jour raconté et le lieu de l'étape", async () => {
    redactor.livedFrom = "2026-08-28";
    redactor.place = "Naxos";
    const memoId = await createTrip();
    const avantEnvoi = Date.now();
    await tell(memoId, "Hier on a marché jusqu'au phare de Naxos.");

    const card = await readCard(memoId);
    expect(card.transcript.livedFrom).toBe("2026-08-28T00:00:00.000Z");
    expect(card.transcript.livedTo).toBeNull();
    expect(card.transcript.placeName).toBe("Naxos");
    // La date d'envoi reste servie — elle dit quand on a parlé, et la fiche ne
    // l'affiche plus comme la date de l'étape. C'est aujourd'hui, pas le jour
    // raconté : les deux ne se confondent pas.
    expect(Date.parse(card.transcript.capturedAt)).toBeGreaterThanOrEqual(avantEnvoi);
  });

  /**
   * ⚠️ L'écho (`entries.placeLabel`) ne sort plus : l'app renvoie le lieu que
   * le carnet lui avait donné, donc celui de l'étape **d'avant** le jour où
   * l'on change de ville.
   */
  it("ne montre plus l'écho du lieu envoyé par l'app", async () => {
    const memoId = await createTrip();
    await tell(memoId, "On a changé d'île ce matin, le bateau était bondé.");
    await harness.prisma.entry.updateMany({ where: { memoId }, data: { placeLabel: "Paros" } });

    const card = await readCard(memoId);
    expect(JSON.stringify(card)).not.toContain("Paros");
    expect(card.transcript.placeName).toBeNull();
  });

  it("se tait sur la date quand personne ne l'a dite", async () => {
    const memoId = await createTrip();
    await tell(memoId, "On a marché jusqu'au phare, et on s'est baignés en rentrant.");

    const card = await readCard(memoId);
    expect(card.transcript.livedFrom).toBeNull();
    expect(card.transcript.livedTo).toBeNull();
  });
});
