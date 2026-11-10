import { beforeEach, describe, expect, it } from "vitest";
import {
  TRASH_RETENTION_DAYS,
  TRASH_RETENTION_MS,
  purgeDeletedMemos,
  softDeleteMemo,
} from "../src/services/trash.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * **La corbeille de trente jours** (Hugo, 10/11/2026) — « j'ai toujours peur
 * qu'un voyage soit supprimé par inadvertance ».
 *
 * Ce que ces cas tiennent : un voyage jeté disparaît **de partout** sans être
 * effacé, son propriétaire le retrouve au bas de l'accueil, il revient entier,
 * et il s'efface pour de bon au trente-et-unième jour.
 */

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

interface HomeJson {
  trips: { id: string }[];
  deletedTrips: { id: string; title: string; deletedAt: string; purgeAt: string }[];
}

async function owner(email = "proprio@memobook.app") {
  return registerAccount(harness.app, email);
}

let codes = 0;

/**
 * Un voyage posé en base, comme les autres suites : la route de création a sa
 * propre forme de corps, et ce n'est pas elle qu'on vérifie ici.
 */
async function tripOf(accountId: string, title = "Rome") {
  codes += 1;
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title,
      accessCode: `TRA${String(codes).padStart(3, "0")}`,
      stage: "ongoing",
    },
  });
  return { trip: { id: memo.id }, accessCode: memo.accessCode };
}

async function home(authorization: string) {
  const response = await harness.app.inject({ method: "GET", url: "/v1/home", headers: { authorization } });
  expect(response.statusCode).toBe(200);
  return response.json<HomeJson>();
}

async function throwAway(authorization: string, id: string) {
  return harness.app.inject({ method: "DELETE", url: `/v1/memos/${id}`, headers: { authorization } });
}

async function restore(authorization: string, id: string) {
  return harness.app.inject({
    method: "POST",
    url: `/v1/memos/${id}/restore`,
    headers: { authorization },
  });
}

/** Recule la date de mise à la corbeille, pour ne pas attendre trente jours. */
async function thrownDaysAgo(memoId: string, days: number) {
  const deletedAt = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  await harness.prisma.memo.update({ where: { id: memoId }, data: { deletedAt } });
  return deletedAt;
}

describe("jeter un voyage", () => {
  it("le sort de l'accueil sans l'effacer, et le pose dans la corbeille", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);

    expect(await throwAway(hugo.authorization, trip.id)).toMatchObject({ statusCode: 204 });

    const feed = await home(hugo.authorization);
    expect(feed.trips.map((t) => t.id)).not.toContain(trip.id);
    expect(feed.deletedTrips.map((t) => t.id)).toEqual([trip.id]);
    expect(feed.deletedTrips[0]?.title).toBe("Rome");

    // Rien n'est effacé : la ligne est là, datée.
    const row = await harness.prisma.memo.findUnique({ where: { id: trip.id } });
    expect(row?.deletedAt).toBeInstanceOf(Date);
  });

  it("annonce le jour où il s'effacera : trente jours après", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);
    await throwAway(hugo.authorization, trip.id);

    const [jete] = (await home(hugo.authorization)).deletedTrips;
    const ecart = Date.parse(jete!.purgeAt) - Date.parse(jete!.deletedAt);
    expect(ecart).toBe(TRASH_RETENTION_MS);
  });

  it("le cache aussi à ses co-voyageurs : pour eux, il a disparu", async () => {
    const hugo = await owner();
    const { trip, accessCode } = await tripOf(hugo.accountId);
    const fanny = await owner("fanny@memobook.app");
    const joined = await harness.app.inject({
      method: "POST",
      url: "/v1/trips/join",
      headers: { authorization: fanny.authorization },
      payload: { code: accessCode },
    });
    expect(joined.statusCode).toBe(200);
    expect((await home(fanny.authorization)).trips.map((t) => t.id)).toContain(trip.id);

    await throwAway(hugo.authorization, trip.id);

    const sienne = await home(fanny.authorization);
    expect(sienne.trips.map((t) => t.id)).not.toContain(trip.id);
    // Et il n'est pas dans **sa** corbeille : il n'a pas pu l'y mettre.
    expect(sienne.deletedTrips).toEqual([]);
  });

  it("une seconde fois ne le trouve plus, et ne repousse pas sa purge", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);

    await throwAway(hugo.authorization, trip.id);
    const premier = (await home(hugo.authorization)).deletedTrips[0]?.deletedAt;

    // Il n'est plus là pour être jeté : `ownedByAccount` exige `deletedAt: null`.
    expect(await throwAway(hugo.authorization, trip.id)).toMatchObject({ statusCode: 404 });

    const second = (await home(hugo.authorization)).deletedTrips[0]?.deletedAt;
    expect(second).toBe(premier);
  });

  /**
   * Le filet sous le filet : deux appels concurrents passent le garde de la
   * route avant que le premier n'écrive. `softDeleteMemo` garde alors la
   * première date — sans quoi la purge reculerait de trente jours.
   */
  it("jeté deux fois dans la même seconde, il garde la date du premier", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);

    const avant = new Date(Date.now() - 60_000);
    await softDeleteMemo(harness.context, trip.id, avant);
    await softDeleteMemo(harness.context, trip.id, new Date());

    const row = await harness.prisma.memo.findUnique({ where: { id: trip.id } });
    expect(row?.deletedAt?.toISOString()).toBe(avant.toISOString());
  });
});

describe("restaurer un voyage", () => {
  it("le remet où il était, entier", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);
    await throwAway(hugo.authorization, trip.id);

    expect(await restore(hugo.authorization, trip.id)).toMatchObject({ statusCode: 204 });

    const feed = await home(hugo.authorization);
    expect(feed.trips.map((t) => t.id)).toContain(trip.id);
    expect(feed.deletedTrips).toEqual([]);
  });

  it("refuse un voyage qui n'est pas dans la corbeille", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);

    expect(await restore(hugo.authorization, trip.id)).toMatchObject({ statusCode: 404 });
  });

  it("refuse la corbeille d'un autre", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);
    await throwAway(hugo.authorization, trip.id);

    const fanny = await owner("fanny@memobook.app");
    expect(await restore(fanny.authorization, trip.id)).toMatchObject({ statusCode: 404 });
  });
});

describe("la purge", () => {
  it("efface ce qui a passé trente jours, et garde le reste", async () => {
    const hugo = await owner();
    const vieux = (await tripOf(hugo.accountId, "Vieux")).trip;
    const recent = (await tripOf(hugo.accountId, "Récent")).trip;

    await throwAway(hugo.authorization, vieux.id);
    await throwAway(hugo.authorization, recent.id);
    await thrownDaysAgo(vieux.id, TRASH_RETENTION_DAYS + 1);
    await thrownDaysAgo(recent.id, TRASH_RETENTION_DAYS - 1);

    const report = await purgeDeletedMemos(harness.context);

    expect(report.memos).toBe(1);
    expect(await harness.prisma.memo.findUnique({ where: { id: vieux.id } })).toBeNull();
    expect(await harness.prisma.memo.findUnique({ where: { id: recent.id } })).not.toBeNull();
    expect((await home(hugo.authorization)).deletedTrips.map((t) => t.id)).toEqual([recent.id]);
  });

  it("ne touche pas aux voyages vivants", async () => {
    const hugo = await owner();
    const { trip } = await tripOf(hugo.accountId);

    const report = await purgeDeletedMemos(harness.context);

    expect(report.memos).toBe(0);
    expect(await harness.prisma.memo.findUnique({ where: { id: trip.id } })).not.toBeNull();
  });
});
