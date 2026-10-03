import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { verifyPassword } from "../src/lib/password.js";
import { collectStats, postToSheet } from "../src/services/statsExport.js";
import {
  createHarness,
  multipartBody,
  registerAccount,
  resetDatabase,
  type TestHarness,
} from "./helpers.js";

/**
 * Le lot du 29/09/2026 : ce que le profil sait faire de plus — changer son mot
 * de passe, retirer sa photo —, les couvertures qui tiennent enfin en base
 * (T88), l'estimation datée de la cagnotte (T127) et la feuille de bord (T72).
 */

interface ProfileBody {
  hasPassword: boolean;
  avatarUrl: string | null;
  subscription: { tripTitle: string | null };
}

interface CoversBody {
  front: { styleId: string; photoId: string | null; title: string; subtitle: string; statIds: string[] };
  back: { styleId: string; photoId: string | null; title: string; subtitle: string; statIds: string[] };
  frontStyles: { id: string }[];
  backStyles: { id: string }[];
  photos: { id: string; url: string | null }[];
  stats: { id: string; value: string; label: string }[];
}

interface WalletBody {
  estimate: Record<string, unknown> | null;
}

let harness: TestHarness;

beforeEach(async () => {
  harness ??= await createHarness();
  await resetDatabase(harness.prisma);
});

afterAll(async () => {
  await harness?.close();
});

let accessCodeCounter = 0;

async function seedTrip(accountId: string, overrides = {}) {
  accessCodeCounter += 1;
  return harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      accessCode: `CVR${String(accessCodeCounter).padStart(3, "0")}`,
      stage: "ongoing",
      destinationCity: "Rome",
      destinationCountryCode: "IT",
      startDate: new Date("2026-08-26T00:00:00Z"),
      endDate: new Date("2026-09-15T00:00:00Z"),
      memoryCount: 4,
      pageCount: 9,
      ...overrides,
    },
  });
}

describe("changer son mot de passe", () => {
  it("remplace le mot de passe, ferme les autres sessions et garde la sienne", async () => {
    const account = await registerAccount(harness.app);
    // Une seconde session, ouverte ailleurs.
    const elsewhere = await harness.app.inject({
      method: "POST",
      url: "/v1/auth/signin",
      payload: { email: "voyageur@memobook.app", password: "carnet2026" },
    });
    expect(elsewhere.statusCode).toBe(200);

    const changed = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/password",
      headers: { authorization: account.authorization },
      payload: { currentPassword: "carnet2026", newPassword: "nouveau2027" },
    });
    expect(changed.statusCode).toBe(204);

    const stored = await harness.prisma.account.findUniqueOrThrow({
      where: { id: account.accountId },
      select: { passwordHash: true },
    });
    expect(await verifyPassword("nouveau2027", stored.passwordHash!)).toBe(true);

    // La sienne tient, l'autre est partie.
    const mine = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
    });
    expect(mine.statusCode).toBe(200);
    expect(mine.json<ProfileBody>().hasPassword).toBe(true);

    const other = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: `Bearer ${elsewhere.json<{ token: string }>().token}` },
    });
    expect(other.statusCode).toBe(401);
  });

  it("refuse un mot de passe actuel faux, le même mot de passe, et un nouveau trop faible", async () => {
    const account = await registerAccount(harness.app);

    const wrong = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/password",
      headers: { authorization: account.authorization },
      payload: { currentPassword: "pasdutout1", newPassword: "nouveau2027" },
    });
    expect(wrong.statusCode).toBe(400);
    expect(wrong.json<{ error: string }>().error).toBe("wrong_password");

    const same = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/password",
      headers: { authorization: account.authorization },
      payload: { currentPassword: "carnet2026", newPassword: "carnet2026" },
    });
    expect(same.statusCode).toBe(400);
    expect(same.json<{ error: string }>().error).toBe("same_password");

    const weak = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/password",
      headers: { authorization: account.authorization },
      payload: { currentPassword: "carnet2026", newPassword: "court1" },
    });
    expect(weak.statusCode).toBe(400);
  });

  it("dit qu'un compte sans mot de passe n'en a pas à changer", async () => {
    const account = await registerAccount(harness.app);
    await harness.prisma.account.update({
      where: { id: account.accountId },
      data: { passwordHash: null },
    });

    const profile = await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: account.authorization },
    });
    expect(profile.json<ProfileBody>().hasPassword).toBe(false);

    const refused = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/password",
      headers: { authorization: account.authorization },
      payload: { currentPassword: "carnet2026", newPassword: "nouveau2027" },
    });
    expect(refused.statusCode).toBe(409);
    expect(refused.json<{ error: string }>().error).toBe("no_password");
  });
});

describe("retirer sa photo de profil", () => {
  it("efface la photo et rend le profil sans adresse", async () => {
    const account = await registerAccount(harness.app);
    const bytes = Buffer.from("fausse photo");
    const { payload, contentType } = multipartBody(
      {},
      { field: "file", filename: "moi.jpg", contentType: "image/jpeg", content: bytes },
    );
    const uploaded = await harness.app.inject({
      method: "POST",
      url: "/v1/profile/avatar",
      headers: { authorization: account.authorization, "content-type": contentType },
      payload,
    });
    expect(uploaded.json<ProfileBody>().avatarUrl).not.toBeNull();

    const removed = await harness.app.inject({
      method: "DELETE",
      url: "/v1/profile/avatar",
      headers: { authorization: account.authorization },
    });
    expect(removed.statusCode).toBe(200);
    expect(removed.json<ProfileBody>().avatarUrl).toBeNull();

    const stored = await harness.prisma.account.findUniqueOrThrow({
      where: { id: account.accountId },
      select: { avatarStorageKey: true },
    });
    expect(stored.avatarStorageKey).toBeNull();
  });
});

describe("les couvertures d'un carnet", () => {
  it("rend les deux plats, les styles, les photos et les chiffres du voyage", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId, { distanceKilometres: 2300 });

    const response = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}/covers`,
      headers: { authorization: account.authorization },
    });
    expect(response.statusCode).toBe(200);
    const body = response.json<CoversBody>();

    // Jamais réglé : les défauts, et rien d'inventé.
    expect(body.front).toEqual({ styleId: "front-photo", photoId: null, title: "", subtitle: "", statIds: [] });
    expect(body.back.styleId).toBe("back-framed");
    expect(body.frontStyles.map((style) => style.id)).toContain("front-kraft");
    expect(body.backStyles.map((style) => style.id)).toContain("back-sand");
    expect(body.photos).toEqual([]);

    // 21 jours, 2,3k km, un pays.
    expect(body.stats.find((stat) => stat.id === "stat-days")).toMatchObject({ value: "21" });
    expect(body.stats.find((stat) => stat.id === "stat-km")).toMatchObject({ value: "2,3k" });
    expect(body.stats.find((stat) => stat.id === "stat-countries")).toMatchObject({ value: "1", label: "pays\nvisité" });
  });

  it("enregistre un style, une photo importée, les textes et les chiffres — et refuse l'inconnu", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);

    const bytes = Buffer.from("fausse couverture");
    const { payload, contentType } = multipartBody(
      {},
      { field: "file", filename: "plage.jpg", contentType: "image/jpeg", content: bytes },
    );
    const uploaded = await harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memo.id}/covers/photos`,
      headers: { authorization: account.authorization, "content-type": contentType },
      payload,
    });
    expect(uploaded.statusCode).toBe(200);
    const photo = uploaded.json<{ photo: { id: string; url: string } }>().photo;
    expect(photo.url).toMatch(/\/v1\/cover-photos\/[0-9a-f-]{36}\.jpg$/);

    // La photo se lit sans session, comme une photo de profil.
    const read = await harness.app.inject({ method: "GET", url: new URL(photo.url).pathname });
    expect(read.statusCode).toBe(200);
    expect(read.rawPayload.equals(bytes)).toBe(true);

    const styled = await harness.app.inject({
      method: "PATCH",
      url: `/v1/trips/${memo.id}/covers`,
      headers: { authorization: account.authorization },
      payload: { face: "front", styleId: "front-framed", photoId: photo.id },
    });
    expect(styled.statusCode).toBe(200);
    expect(styled.json<CoversBody>().front).toMatchObject({ styleId: "front-framed", photoId: photo.id });
    expect(styled.json<CoversBody>().photos.map((entry) => entry.id)).toContain(photo.id);

    const texts = await harness.app.inject({
      method: "PATCH",
      url: `/v1/trips/${memo.id}/covers`,
      headers: { authorization: account.authorization },
      payload: { face: "back", title: "", subtitle: "Quelques jours à Rome.", statIds: ["stat-days", "stat-countries"] },
    });
    expect(texts.statusCode).toBe(200);
    expect(texts.json<CoversBody>().back).toMatchObject({
      styleId: "back-framed",
      subtitle: "Quelques jours à Rome.",
      statIds: ["stat-days", "stat-countries"],
    });
    // Le devant n'a pas bougé.
    expect(texts.json<CoversBody>().front.styleId).toBe("front-framed");

    // La photo importée devient celle du voyage sur l'accueil.
    const stored = await harness.prisma.memo.findUniqueOrThrow({
      where: { id: memo.id },
      select: { coverPhotoUrl: true },
    });
    expect(stored.coverPhotoUrl).toBe(photo.url);

    const unknownStyle = await harness.app.inject({
      method: "PATCH",
      url: `/v1/trips/${memo.id}/covers`,
      headers: { authorization: account.authorization },
      payload: { face: "front", styleId: "front-neon" },
    });
    expect(unknownStyle.statusCode).toBe(400);

    const unknownPhoto = await harness.app.inject({
      method: "PATCH",
      url: `/v1/trips/${memo.id}/covers`,
      headers: { authorization: account.authorization },
      payload: { face: "front", photoId: "photo-42" },
    });
    expect(unknownPhoto.statusCode).toBe(400);
  });

  it("ne montre pas les couvertures d'un voyage qu'on ne voit pas", async () => {
    const owner = await registerAccount(harness.app, "proprietaire@memobook.app");
    const stranger = await registerAccount(harness.app, "inconnu@memobook.app");
    const memo = await seedTrip(owner.accountId);

    const response = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}/covers`,
      headers: { authorization: stranger.authorization },
    });
    expect(response.statusCode).toBe(404);
  });
});

describe("l'estimation de la cagnotte", () => {
  it("ne porte plus les dates ni les semaines d'abonnement à déduire", async () => {
    // La feuille « Estimation » du paywall comptait les semaines du voyage pour
    // les déduire du carnet. Il n'y a plus rien à déduire (Hugo, 03/10/2026).
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);

    const response = await harness.app.inject({
      method: "GET",
      url: `/v1/wallet?tripId=${memo.id}`,
      headers: { authorization: account.authorization },
    });
    expect(response.statusCode).toBe(200);
    const estimate = response.json<WalletBody>().estimate;
    expect(estimate).toHaveProperty("pageCount");
    expect(estimate).toHaveProperty("cost");
    expect(estimate).not.toHaveProperty("weeks");
    expect(estimate).not.toHaveProperty("startDate");
  });
});

describe("la feuille de bord", () => {
  it("relève les comptes, les carnets, les commandes et les départs", async () => {
    const account = await registerAccount(harness.app);
    const memo = await seedTrip(account.accountId);
    await seedTrip(account.accountId, { startDate: new Date("2030-01-01T00:00:00Z"), endDate: null });

    await harness.prisma.subscription.createMany({
      data: [
        { accountId: account.accountId, provider: "storekit", status: "active", priceCents: 199 },
        {
          accountId: account.accountId,
          provider: "storekit",
          status: "cancelled",
          priceCents: 199,
          cancellationReason: "tooExpensive",
        },
      ],
    });

    const render = await harness.prisma.render.create({
      data: { memoId: memo.id, status: "ready" },
    });
    await harness.prisma.printOrder.create({
      data: {
        memoId: memo.id,
        renderId: render.id,
        orderedByAccountId: account.accountId,
        status: "shipped",
        copies: 2,
        pageCount: 40,
        amountCents: 6000,
        shippingName: "Hugo Jouffre",
        shippingLine1: "7 rue Simon Fryd",
        shippingPostalCode: "69007",
        shippingCity: "Lyon",
        shippingCountry: "FR",
        shippedAt: new Date("2026-09-20T00:00:00Z"),
      },
    });

    const snapshot = await collectStats(harness.prisma, new Date("2026-09-29T12:00:00Z"));

    expect(snapshot.accounts).toMatchObject({ total: 1, newLast7Days: 1, subscribed: 1 });
    expect(snapshot.trips).toMatchObject({ total: 2, past: 1, upcoming: 1, ongoing: 0, composed: 1 });
    expect(snapshot.orders).toMatchObject({ total: 1, inProgress: 1, shipped: 1, copies: 2, revenueEuros: 60 });
    expect(snapshot.subscriptions).toMatchObject({ active: 1, cancelled: 1, cancellationReasons: { tooExpensive: 1 } });
    expect(snapshot.deliveries).toHaveLength(1);
    expect(snapshot.deliveries[0]).toMatchObject({ tripTitle: "Rome 2026", city: "Lyon", status: "shipped", copies: 2 });
  });

  it("envoie au script avec le secret, et lit sa réponse", async () => {
    const calls: { url: string; body: Record<string, unknown> }[] = [];
    const fakeFetch: typeof fetch = async (input, init) => {
      const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
      const body = typeof init?.body === "string" ? init.body : "{}";
      calls.push({ url, body: JSON.parse(body) as Record<string, unknown> });
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    };

    await postToSheet(
      { STATS_SHEET_WEBHOOK_URL: "https://script.google.com/macros/s/abc/exec", STATS_SHEET_SECRET: "s3cret" },
      { type: "cancellation", at: "2026-09-29T10:00:00.000Z", account: "abcd1234", reason: "unused", hadActiveSubscription: true },
      fakeFetch,
    );
    expect(calls).toHaveLength(1);
    expect(calls[0]?.body).toMatchObject({ secret: "s3cret", type: "cancellation", reason: "unused" });

    // Sans adresse, rien ne part.
    await postToSheet(
      { STATS_SHEET_WEBHOOK_URL: "", STATS_SHEET_SECRET: "" },
      { type: "cancellation", at: "2026-09-29T10:00:00.000Z", account: "abcd1234", reason: null, hadActiveSubscription: false },
      fakeFetch,
    );
    expect(calls).toHaveLength(1);

    // Un refus du script est une erreur qu'on voit.
    const refusing: typeof fetch = async () =>
      new Response(JSON.stringify({ ok: false, error: "secret refusé" }), { status: 200 });
    await expect(
      postToSheet(
        { STATS_SHEET_WEBHOOK_URL: "https://script.google.com/macros/s/abc/exec", STATS_SHEET_SECRET: "x" },
        { type: "cancellation", at: "2026-09-29T10:00:00.000Z", account: "abcd1234", reason: null, hadActiveSubscription: false },
        refusing,
      ),
    ).rejects.toThrow(/refusé/);
  });
});
