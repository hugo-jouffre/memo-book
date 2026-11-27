import { randomUUID } from "node:crypto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { FakeRedactor, type RedactionInput, type RedactionResult } from "../src/services/redaction.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **Les dates et le lieu qu'on fixe à la main** (T288, Hugo — « l'appui long
 * sur un message de MEMO ouvre ses gestes à lui : […] changer les dates
 * (déduites automatiquement), changer le nom du lieu »).
 *
 * T308 a appris à l'étape à n'afficher que ce que le récit **dit** : le jour
 * raconté, le lieu nommé, et rien quand on ne sait pas. Restait le cas où la
 * rédaction comprend de travers — et là, rien ne permettait de la reprendre.
 *
 * Ce qui est écrit à la main se range **à côté** de sa lecture, jamais à sa
 * place : une relance de la rédaction la réécrit, elle, et ne touche pas à la
 * correction. « Revenir aux dates déduites » lui rend la parole.
 */

/** Un écrivain qui situe ce qu'il raconte, sur commande — comme pour T308. */
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

async function tell(memoId: string, text: string): Promise<void> {
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization },
    payload: { id: randomUUID(), kind: "text", text },
  });
  expect(response.statusCode, response.body).toBe(201);
}

interface ThreadJson {
  messages: {
    body:
      | {
          kind: "transcript";
          transcript: {
            placeName: string | null;
            livedFrom: string | null;
            livedTo: string | null;
            livedDaysByHand: boolean;
            placeByHand: boolean;
          };
        }
      | { kind: string };
  }[];
}

/** La fiche, telle que l'app la lit. */
async function readCard(memoId: string) {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization },
  });
  expect(response.statusCode).toBe(200);
  const card = response
    .json<ThreadJson>()
    .messages.find((message) => message.body.kind === "transcript");
  expect(card).toBeDefined();
  return (card!.body as Extract<ThreadJson["messages"][number]["body"], { kind: "transcript" }>)
    .transcript;
}

async function correct(entryId: string, payload: Record<string, unknown>) {
  const response = await harness.app.inject({
    method: "PATCH",
    url: `/v1/entries/${entryId}`,
    headers: { authorization: owner.authorization },
    payload,
  });
  expect(response.statusCode).toBe(200);
}

/** Le souvenir du seul récit du fil. */
async function onlyEntry(memoId: string) {
  return harness.prisma.entry.findFirstOrThrow({ where: { memoId } });
}

describe("changer les dates d'une fiche", () => {
  it("affiche le jour posé à la main, et le dit posé à la main", async () => {
    redactor.livedFrom = "2026-08-28";
    const memoId = await createTrip();
    await tell(memoId, "Hier on a marché jusqu'au phare.");
    expect((await readCard(memoId)).livedFrom).toBe("2026-08-28T00:00:00.000Z");

    const entry = await onlyEntry(memoId);
    await correct(entry.id, { livedFrom: "2026-08-30" });

    const card = await readCard(memoId);
    expect(card.livedFrom).toBe("2026-08-30T00:00:00.000Z");
    expect(card.livedDaysByHand).toBe(true);

    // **À côté, et non à la place** : la lecture de la rédaction est intacte.
    const corrected = await onlyEntry(memoId);
    expect(corrected.livedFromDay?.toISOString()).toBe("2026-08-28T00:00:00.000Z");
    expect(corrected.pinnedLivedFromDay?.toISOString()).toBe("2026-08-30T00:00:00.000Z");
  });

  /**
   * **Et l'étape suit** : c'est elle que les écrans du carnet affichent, et
   * c'est `refreshTripFacts` qui y remonte la correction. Sans ce passage, la
   * correction serait écrite et invisible partout ailleurs que sur la fiche.
   */
  it("date l'étape avec le jour de la main", async () => {
    redactor.livedFrom = "2026-08-28";
    const memoId = await createTrip();
    await tell(memoId, "Hier on a marché jusqu'au phare.");

    await correct((await onlyEntry(memoId)).id, { livedFrom: "2026-08-30" });

    const step = await harness.prisma.memoStep.findFirstOrThrow({ where: { memoId } });
    expect(step.livedFromDay?.toISOString()).toBe("2026-08-30T00:00:00.000Z");
  });

  it("accepte une période, et refuse une fin avant le départ", async () => {
    const memoId = await createTrip();
    await tell(memoId, "On est restés un moment à Naxos.");
    const entry = await onlyEntry(memoId);

    await correct(entry.id, { livedFrom: "2026-08-28", livedTo: "2026-08-30" });
    expect((await readCard(memoId)).livedTo).toBe("2026-08-30T00:00:00.000Z");

    await correct(entry.id, { livedFrom: "2026-08-28", livedTo: "2026-08-20" });
    expect((await readCard(memoId)).livedTo).toBeNull();
  });

  /** « Revenir aux dates déduites » : la rédaction reprend la parole. */
  it("rend la parole à la rédaction sur un null", async () => {
    redactor.livedFrom = "2026-08-28";
    const memoId = await createTrip();
    await tell(memoId, "Hier on a marché jusqu'au phare.");
    const entry = await onlyEntry(memoId);

    await correct(entry.id, { livedFrom: "2026-08-30" });
    await correct(entry.id, { livedFrom: null });

    const card = await readCard(memoId);
    expect(card.livedFrom).toBe("2026-08-28T00:00:00.000Z");
    expect(card.livedDaysByHand).toBe(false);
  });

  /**
   * ⚠️ **Une relance de la rédaction ne touche pas à la main.** C'est la
   * raison d'être des deux colonnes : la rédaction réécrit sa lecture, et la
   * correction tient.
   */
  it("tient quand la rédaction repasse", async () => {
    redactor.livedFrom = "2026-08-28";
    const memoId = await createTrip();
    await tell(memoId, "Hier on a marché jusqu'au phare.");
    const entry = await onlyEntry(memoId);
    await correct(entry.id, { livedFrom: "2026-08-30" });

    // Ce que fait `jobs/redact.ts` quand il relit un récit : il réécrit sa
    // lecture, et rien d'autre.
    await harness.prisma.entry.update({
      where: { id: entry.id },
      data: { livedFromDay: new Date("2026-08-29T00:00:00Z"), livedToDay: null },
    });

    expect((await readCard(memoId)).livedFrom).toBe("2026-08-30T00:00:00.000Z");
  });
});

describe("changer le nom du lieu d'une fiche", () => {
  it("renomme l'étape, et le dit écrit à la main", async () => {
    redactor.place = "Naxos";
    const memoId = await createTrip();
    await tell(memoId, "On a trouvé une taverne au bout du port.");
    expect((await readCard(memoId)).placeName).toBe("Naxos");

    await correct((await onlyEntry(memoId)).id, { placeName: "Apollonas" });

    const card = await readCard(memoId);
    expect(card.placeName).toBe("Apollonas");
    expect(card.placeByHand).toBe(true);

    const step = await harness.prisma.memoStep.findFirstOrThrow({ where: { memoId } });
    expect(step.placeName).toBe("Apollonas");
  });

  it("rend la parole au lieu deviné sur un null", async () => {
    redactor.place = "Naxos";
    const memoId = await createTrip();
    await tell(memoId, "On a trouvé une taverne au bout du port.");
    const entry = await onlyEntry(memoId);

    await correct(entry.id, { placeName: "Apollonas" });
    await correct(entry.id, { placeName: null });

    const card = await readCard(memoId);
    expect(card.placeName).toBe("Naxos");
    expect(card.placeByHand).toBe(false);
  });

  /**
   * ⚠️ **Renommer ne regroupe pas.** Deux récits renommés du même nom restent
   * deux étapes : le découpage est celui que les récits dictent, et renommer
   * une fiche ne doit pas déplacer un souvenir ailleurs sans qu'on l'ait
   * demandé.
   */
  it("ne rejoint pas deux étapes qui portent le même nom à la main", async () => {
    const memoId = await createTrip();
    redactor.place = "Naxos";
    await tell(memoId, "Premier jour, on s'installe.");
    redactor.place = "Paros";
    await tell(memoId, "On a changé d'île ce matin.");

    const entries = await harness.prisma.entry.findMany({ where: { memoId }, orderBy: { createdAt: "asc" } });
    expect(entries).toHaveLength(2);
    await correct(entries[1]!.id, { placeName: "Naxos" });

    const steps = await harness.prisma.memoStep.findMany({ where: { memoId } });
    expect(steps).toHaveLength(2);
  });
});
