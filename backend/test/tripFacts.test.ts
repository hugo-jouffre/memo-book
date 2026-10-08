import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { dayCountOf, refreshTripFacts } from "../src/services/tripFacts.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Les étapes et les chiffres d'un vrai voyage (T227), et les souvenirs que
 * porte chaque étape (T235) : tout se déduit des souvenirs, à chaque souvenir
 * traité.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

type Step = {
  id: string;
  number: number;
  placeName: string | null;
  destination: { name: string; countryCode: string | null } | null;
  transport: string | null;
  entryIds: string[];
};
type TripBody = {
  trip: {
    destination: { name: string; countryCode: string | null; city: string | null } | null;
    stats: { dayCount: number | null; distanceKilometres: number | null; photoCount: number | null };
    progress: { memoryCount: number } | null;
  };
  steps: Step[];
};

async function createTrip(authorization: string, startDate = "2026-01-05"): Promise<string> {
  const response = await harness.app.inject({
    method: "POST",
    url: "/v1/trips",
    headers: { authorization },
    payload: { title: "Italie 2026", startDate, endDate: "2026-01-12" },
  });
  expect(response.statusCode).toBeLessThan(300);
  return response.json<{ trip: { id: string } }>().trip.id;
}

/** Un souvenir tapé ; la rédaction simulée lit sa ville dans « lieu, ville ». */
async function tell(authorization: string, memoId: string, placeLabel: string, capturedAt: string) {
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/entries`,
    headers: { authorization },
    payload: { kind: "text", transcript: "On a marché jusqu'au soir.", placeLabel, capturedAt },
  });
  expect(response.statusCode).toBe(201);
  return response.json<{ id: string }>().id;
}

async function readTrip(authorization: string, memoId: string): Promise<TripBody> {
  const response = await harness.app.inject({ method: "GET", url: `/v1/trips/${memoId}`, headers: { authorization } });
  expect(response.statusCode).toBe(200);
  return response.json<TripBody>();
}

describe("les étapes d'un voyage", () => {
  it("naissent des souvenirs, une par lieu successif, avec leurs souvenirs (T227, T235)", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);

    const colisee = await tell(authorization, memoId, "Colisée, Rome", "2026-01-05T10:00:00.000Z");
    const trastevere = await tell(authorization, memoId, "Trastevere, Rome", "2026-01-06T10:00:00.000Z");
    const duomo = await tell(authorization, memoId, "Duomo, Florence", "2026-01-08T10:00:00.000Z");

    const { steps, trip } = await readTrip(authorization, memoId);
    expect(steps.map((step) => [step.number, step.placeName, step.entryIds])).toEqual([
      [1, "Rome", [colisee, trastevere]],
      [2, "Florence", [duomo]],
    ]);
    expect(trip.progress?.memoryCount).toBe(3);
  });

  it("disparaît quand la croix a effacé son dernier souvenir, et les chiffres reculent", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);
    await tell(authorization, memoId, "Colisée, Rome", "2026-01-05T10:00:00.000Z");
    const duomo = await tell(authorization, memoId, "Duomo, Florence", "2026-01-08T10:00:00.000Z");

    const before = await readTrip(authorization, memoId);
    const rome = before.steps[0]!;
    await harness.prisma.memoStep.update({ where: { id: rome.id }, data: { validatedAt: new Date() } });

    const deleted = await harness.app.inject({
      method: "DELETE",
      url: `/v1/entries/${duomo}`,
      headers: { authorization },
    });
    expect(deleted.statusCode).toBe(204);

    const after = await readTrip(authorization, memoId);
    expect(after.steps.map((step) => step.id)).toEqual([rome.id]);
    expect(after.trip.progress?.memoryCount).toBe(1);
    // L'étape qui reste garde ce qui y était attaché.
    const kept = await harness.prisma.memoStep.findUniqueOrThrow({ where: { id: rome.id } });
    expect(kept.validatedAt).not.toBeNull();
  });

  it("garde un souvenir raconté depuis une étape sur cette étape-là", async () => {
    const { authorization, accountId } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);
    await tell(authorization, memoId, "Colisée, Rome", "2026-01-05T10:00:00.000Z");
    const later = await tell(authorization, memoId, "Duomo, Florence", "2026-01-08T10:00:00.000Z");
    const [rome] = (await readTrip(authorization, memoId)).steps;

    // « Raconter » sur la carte de Rome : l'app a envoyé l'étape avec le message.
    await harness.prisma.chatMessage.create({
      data: { memoId, author: "traveller", kind: "text", accountId, entryId: later, stepId: rome!.id, seq: 1_000 },
    });
    await refreshTripFacts(harness.prisma, memoId);

    const { steps } = await readTrip(authorization, memoId);
    expect(steps.map((step) => [step.placeName, step.entryIds.length])).toEqual([["Rome", 2]]);
  });
});

describe("les chiffres d'un voyage", () => {
  it("déduisent la destination, les km, le transport, sans écraser une destination posée", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);
    const first = await tell(authorization, memoId, "Colisée, Rome", "2026-01-05T10:00:00.000Z");
    const second = await tell(authorization, memoId, "Duomo, Florence", "2026-01-08T10:00:00.000Z");

    const italy = { code: "IT", name: "Italie" };
    await harness.prisma.entry.update({
      where: { id: first },
      data: { insights: { countries: [italy], cities: ["Rome"], currentPlace: "Rome", distanceKilometres: 12.5, transports: [] } },
    });
    await harness.prisma.entry.update({
      where: { id: second },
      data: {
        insights: {
          countries: [italy],
          cities: ["Florence"],
          currentPlace: "Florence",
          distanceKilometres: 280,
          transports: [{ kind: "metro", count: 1 }],
        },
      },
    });
    await refreshTripFacts(harness.prisma, memoId, new Date("2026-01-08T18:00:00.000Z"));

    const memo = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memoId } });
    expect(memo).toMatchObject({
      destinationName: "Italie",
      destinationCountryCode: "IT",
      destinationCity: "Rome",
      destinationInferred: true,
      distanceKilometres: 292.5,
      dayCount: 4,
      memoryCount: 2,
      photoCount: 0,
    });
    const { steps } = await readTrip(authorization, memoId);
    expect(steps[1]).toMatchObject({ placeName: "Florence", transport: "train", destination: { countryCode: "IT" } });

    // Une destination posée par quelqu'un ne bouge plus.
    await harness.prisma.memo.update({
      where: { id: memoId },
      data: { destinationName: "Toscane", destinationCountryCode: "IT", destinationCity: null, destinationInferred: false },
    });
    await refreshTripFacts(harness.prisma, memoId);
    expect(await harness.prisma.memo.findUniqueOrThrow({ where: { id: memoId } })).toMatchObject({
      destinationName: "Toscane",
      destinationInferred: false,
    });
  });

  it("n'écrit rien quand rien n'a changé", async () => {
    const { authorization } = await registerAccount(harness.app);
    const memoId = await createTrip(authorization);
    await tell(authorization, memoId, "Colisée, Rome", "2026-01-05T10:00:00.000Z");
    const now = new Date("2026-01-06T12:00:00.000Z");
    await refreshTripFacts(harness.prisma, memoId, now);

    const stamp = async () => {
      const memo = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memoId }, include: { steps: true, entries: true } });
      return [memo.updatedAt, ...memo.steps.map((s) => s.updatedAt), ...memo.entries.map((e) => e.updatedAt)].map((d) =>
        d.getTime(),
      );
    };
    const before = await stamp();
    await refreshTripFacts(harness.prisma, memoId, now);
    expect(await stamp()).toEqual(before);
  });

  it("comptent les jours jusqu'à aujourd'hui pendant le voyage", () => {
    const trip = { startDate: new Date("2026-01-05"), endDate: new Date("2026-01-12") };
    expect(dayCountOf(trip, [], new Date("2026-01-07T09:00:00Z"))).toBe(3);
    expect(dayCountOf(trip, [], new Date("2026-02-01T09:00:00Z"))).toBe(8);
    expect(dayCountOf(trip, [], new Date("2026-01-01T09:00:00Z"))).toBeNull();
    expect(
      dayCountOf({ startDate: null, endDate: null }, [new Date("2026-01-05T10:00Z"), new Date("2026-01-05T18:00Z")], new Date()),
    ).toBe(1);
  });
});
