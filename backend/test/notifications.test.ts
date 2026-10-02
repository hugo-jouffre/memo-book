import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  LoggingPushSender,
  type PushDestination,
  type PushMessage,
  type PushOutcome,
  type PushSender,
} from "../src/services/apns.js";
import { sendDueNotifications } from "../src/services/notifications.js";
import { syncSchoolHolidays } from "../src/services/schoolHolidays.js";
import { createHarness, registerAccount, resetDatabase, type TestHarness } from "./helpers.js";

/**
 * Les notifications de bout en bout : le téléphone s'enregistre, la passe
 * horaire décide et envoie, le toucher revient. APNs est remplacé par un
 * double qui retient ce qu'on lui confie — tout le reste est réel, base
 * comprise : c'est elle qui tient le « une seule fois ».
 */

const TOKEN = "a".repeat(64);

/** Un double d'APNs qu'on règle envoi par envoi. */
class ScriptedPushSender implements PushSender {
  readonly enabled = true;
  readonly sent: { destination: PushDestination; message: PushMessage }[] = [];
  outcome: PushOutcome = { kind: "sent" };

  async send(destination: PushDestination, message: PushMessage): Promise<PushOutcome> {
    this.sent.push({ destination, message });
    return this.outcome;
  }

  async close(): Promise<void> {}
}

let harness: TestHarness;
let push: ScriptedPushSender;

beforeAll(async () => {
  push = new ScriptedPushSender();
  harness = await createHarness({ push });
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  push.sent.length = 0;
  push.outcome = { kind: "sent" };
});

async function registerToken(authorization: string, token = TOKEN) {
  return harness.app.inject({
    method: "POST",
    url: "/v1/push-tokens",
    headers: { authorization },
    payload: { token, environment: "sandbox", timeZone: "Europe/Paris", appVersion: "0.1.0 (8)" },
  });
}

/** Un voyage à Rome qui se termine le 12 octobre 2026, avec un souvenir raconté. */
async function tripEndingOctober12(accountId: string) {
  const memo = await harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      destinationCity: "Rome",
      accessCode: `NTF${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
      stage: "ongoing",
      // Minuit à Paris, comme l'app écrit les dates : le 1er et le 12 octobre.
      startDate: new Date("2026-09-30T22:00:00Z"),
      endDate: new Date("2026-10-11T22:00:00Z"),
      narrationPace: "every_two_days",
    },
  });
  await harness.prisma.entry.create({ data: { memoId: memo.id, kind: "text", transcript: "Le Colisée." } });
  return memo;
}

/** 10 h 35 à Paris le 12 octobre 2026 — 8 h 35 UTC, l'heure d'été court encore. */
const OCTOBER_12_MORNING = new Date("2026-10-12T08:35:00Z");

describe("POST /v1/push-tokens", () => {
  it("retient le téléphone et le fuseau du compte", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);

    const response = await registerToken(authorization);
    expect(response.statusCode).toBe(204);

    const token = await harness.prisma.pushToken.findUniqueOrThrow({ where: { token: TOKEN } });
    expect(token).toMatchObject({ accountId, environment: "sandbox", appVersion: "0.1.0 (8)" });
    const account = await harness.prisma.account.findUniqueOrThrow({ where: { id: accountId } });
    expect(account.timeZone).toBe("Europe/Paris");
  });

  it("passe le téléphone à qui s'y connecte ensuite, sans le dédoubler", async () => {
    const first = await registerAccount(harness.app, "premiere@memobook.app");
    const second = await registerAccount(harness.app, "seconde@memobook.app");

    await registerToken(first.authorization);
    await registerToken(second.authorization);

    const tokens = await harness.prisma.pushToken.findMany();
    expect(tokens).toHaveLength(1);
    expect(tokens[0]?.accountId).toBe(second.accountId);
  });

  it("refuse ce qui n'est pas un jeton APNs, et n'existe pas sans session", async () => {
    const { authorization } = await registerAccount(harness.app);
    expect((await registerToken(authorization, "pas-un-jeton")).statusCode).toBe(400);
    expect(
      (
        await harness.app.inject({
          method: "POST",
          url: "/v1/push-tokens",
          payload: { token: TOKEN, environment: "sandbox" },
        })
      ).statusCode,
    ).toBe(401);
  });

  it("part avec la session : se déconnecter oublie le téléphone", async () => {
    const { authorization } = await registerAccount(harness.app);
    await registerToken(authorization);

    await harness.app.inject({ method: "POST", url: "/v1/auth/signout", headers: { authorization } });

    expect(await harness.prisma.pushToken.count()).toBe(0);
  });
});

describe("la passe horaire", () => {
  it("envoie la fin du voyage le jour J à 10 h chez le voyageur, une seule fois", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    const memo = await tripEndingOctober12(accountId);

    // 9 h 35 à Paris : trop tôt.
    expect((await sendDueNotifications(harness.context, new Date("2026-10-12T07:35:00Z"))).sent).toBe(0);

    const report = await sendDueNotifications(harness.context, OCTOBER_12_MORNING);
    expect(report.sent).toBe(1);
    expect(push.sent).toHaveLength(1);
    expect(push.sent[0]?.destination).toEqual({ token: TOKEN, environment: "sandbox" });
    expect(push.sent[0]?.message).toMatchObject({
      title: "Ton voyage à Rome se termine aujourd’hui",
      link: `memobook://trips/${memo.id}/wallet`,
      threadId: memo.id,
    });

    const delivery = await harness.prisma.notificationDelivery.findFirstOrThrow();
    expect(delivery).toMatchObject({ accountId, memoId: memo.id, kind: "trip_end", deliveredCount: 1 });
    expect(push.sent[0]?.message.deliveryId).toBe(delivery.id);

    // L'heure suivante : déjà partie, rien ne repart.
    await sendDueNotifications(harness.context, new Date("2026-10-12T09:35:00Z"));
    expect(push.sent).toHaveLength(1);
  });

  it("retient l'ouverture, une fois, et seulement pour le compte qui l'a reçue", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);
    await sendDueNotifications(harness.context, OCTOBER_12_MORNING);
    const delivery = await harness.prisma.notificationDelivery.findFirstOrThrow();

    const stranger = await registerAccount(harness.app, "autre@memobook.app");
    await harness.app.inject({
      method: "POST",
      url: `/v1/notifications/${delivery.id}/opened`,
      headers: { authorization: stranger.authorization },
    });
    expect((await harness.prisma.notificationDelivery.findUniqueOrThrow({ where: { id: delivery.id } })).openedAt).toBeNull();

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/notifications/${delivery.id}/opened`,
      headers: { authorization },
    });
    expect(response.statusCode).toBe(204);
    expect(
      (await harness.prisma.notificationDelivery.findUniqueOrThrow({ where: { id: delivery.id } })).openedAt,
    ).not.toBeNull();
  });

  it("oublie un jeton qu'Apple ne connaît plus", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);
    push.outcome = { kind: "invalid_token", reason: "Unregistered" };

    await sendDueNotifications(harness.context, OCTOBER_12_MORNING);

    expect(await harness.prisma.pushToken.count()).toBe(0);
  });

  it("retente dans la journée ce qu'une panne passagère a empêché", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);

    push.outcome = { kind: "failed", reason: "ServiceUnavailable" };
    expect((await sendDueNotifications(harness.context, OCTOBER_12_MORNING)).sent).toBe(0);
    expect(await harness.prisma.notificationDelivery.count()).toBe(0);
    expect(await harness.prisma.pushToken.count()).toBe(1);

    push.outcome = { kind: "sent" };
    expect((await sendDueNotifications(harness.context, new Date("2026-10-12T09:35:00Z"))).sent).toBe(1);
  });

  it("ne fait rien, et ne retient rien, sans APNs configuré", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);

    const off: PushSender = {
      enabled: false,
      send: () => Promise.resolve({ kind: "failed", reason: "APNs n'est pas configuré." }),
      close: () => Promise.resolve(),
    };
    const disabled = { ...harness.context, push: off };
    expect(await sendDueNotifications(disabled, OCTOBER_12_MORNING)).toEqual({ evaluated: 0, sent: 0 });
    expect(await harness.prisma.notificationDelivery.count()).toBe(0);
  });

  it("sans clé, en développement, journalise au lieu d'envoyer", async () => {
    const logging = new LoggingPushSender(null);
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);

    await sendDueNotifications({ ...harness.context, push: logging }, OCTOBER_12_MORNING);
    expect(logging.sent.map((entry) => entry.message.title)).toEqual(["Ton voyage à Rome se termine aujourd’hui"]);
  });
});

/** Un voyage à Rome parti le 1er octobre 2026 et qui court jusqu'à la fin du mois. */
async function tripToRome(ownerAccountId: string, narrationPace: string) {
  return harness.prisma.memo.create({
    data: {
      ownerAccountId,
      title: "Rome 2026",
      destinationCity: "Rome",
      accessCode: `NTF${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
      stage: "ongoing",
      startDate: new Date("2026-09-30T22:00:00Z"),
      endDate: new Date("2026-10-30T23:00:00Z"),
      narrationPace,
    },
  });
}

/** Un souvenir raconté dans le fil par `accountId`, à l'instant donné. */
async function toldInChat(memoId: string, accountId: string, at: Date, repliedAt: Date | null = at) {
  const entry = await harness.prisma.entry.create({
    data: { memoId, kind: "text", transcript: "La fontaine de Trevi.", createdAt: at, capturedAt: at },
  });
  return harness.prisma.chatMessage.create({
    data: {
      memoId,
      author: "traveller",
      kind: "text",
      text: "La fontaine de Trevi.",
      accountId,
      entryId: entry.id,
      disposition: "memory",
      createdAt: at,
      repliedAt,
    },
  });
}

/** Les bulles que MEMO a posées pour une notification. */
async function notificationBubbles(memoId: string) {
  const messages = await harness.prisma.chatMessage.findMany({
    where: { memoId, author: "memo" },
    orderBy: { seq: "asc" },
  });
  return messages.filter((message) => (message.payload as { notification?: string } | null)?.notification);
}

describe("le nouveau récit d'un co-voyageur", () => {
  /** 10 h 35 à Paris le 4 octobre. */
  const OCTOBER_4_MORNING = new Date("2026-10-04T08:35:00Z");

  async function sharedTrip() {
    const camille = await registerAccount(harness.app, "camille@memobook.app");
    const paul = await registerAccount(harness.app, "paul@memobook.app");
    const clara = await registerAccount(harness.app, "clara@memobook.app");
    await harness.prisma.account.update({ where: { id: clara.accountId }, data: { firstName: "Clara" } });
    await registerToken(camille.authorization, "a".repeat(64));
    await registerToken(paul.authorization, "b".repeat(64));

    const memo = await tripToRome(camille.accountId, "daily");
    for (const member of [paul, clara]) {
      await harness.prisma.memoMember.create({
        data: { memoId: memo.id, accountId: member.accountId, status: "active", acceptedAt: new Date() },
      });
    }
    return { camille, paul, clara, memo };
  }

  it("prévient les autres co-voyageurs, et MEMO le redit une seule fois dans le fil commun", async () => {
    const { clara, memo } = await sharedTrip();
    const told = await toldInChat(memo.id, clara.accountId, new Date("2026-10-04T08:00:00Z"));

    const report = await sendDueNotifications(harness.context, OCTOBER_4_MORNING);

    expect(report.sent).toBe(2);
    expect(push.sent.map((sent) => sent.message.title)).toEqual(["Nouveau récit à Rome", "Nouveau récit à Rome"]);
    expect(push.sent[0]?.message).toMatchObject({
      body: "Clara a ajouté un souvenir au carnet. Viens voir, et raconte la suite à ton tour.",
      link: `memobook://trips/${memo.id}/chat`,
    });

    const bubbles = await notificationBubbles(memo.id);
    expect(bubbles).toHaveLength(1);
    expect(bubbles[0]?.text).toBe("Nouveau récit dans le carnet : Clara a ajouté un souvenir. Qui raconte la suite ?");
    expect(bubbles[0]!.seq).toBeGreaterThan(told.seq);

    // L'heure suivante : rien de neuf, rien ne repart.
    await sendDueNotifications(harness.context, new Date("2026-10-04T09:35:00Z"));
    expect(push.sent).toHaveLength(2);
    expect(await notificationBubbles(memo.id)).toHaveLength(1);
  });

  it("attend que MEMO ait répondu avant d'écrire dans le fil", async () => {
    const { clara, memo } = await sharedTrip();
    await toldInChat(memo.id, clara.accountId, new Date("2026-10-04T08:00:00Z"));
    // Un tour en vol, posé il y a trente secondes.
    await toldInChat(memo.id, clara.accountId, new Date("2026-10-04T08:34:30Z"), null);

    expect((await sendDueNotifications(harness.context, OCTOBER_4_MORNING)).sent).toBe(0);
    expect(await notificationBubbles(memo.id)).toHaveLength(0);

    expect((await sendDueNotifications(harness.context, new Date("2026-10-04T09:35:00Z"))).sent).toBe(2);
    expect(await notificationBubbles(memo.id)).toHaveLength(1);
  });
});

describe("le résumé de la semaine", () => {
  it("fait le point le soir du septième jour, et MEMO le reprend après les souvenirs du fil", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    const memo = await tripToRome(accountId, "weekly");
    // Deux souvenirs et une photo, racontés hors du fil : il ne les a pas encore.
    for (const [kind, at] of [
      ["text", "2026-10-05T10:00:00Z"],
      ["audio", "2026-10-06T10:00:00Z"],
      ["photo", "2026-10-06T11:00:00Z"],
    ] as const) {
      await harness.prisma.entry.create({
        data: { memoId: memo.id, kind, transcript: "Le Trastevere.", createdAt: new Date(at), capturedAt: new Date(at) },
      });
    }

    // 18 h 35 à Paris le 8 octobre.
    expect((await sendDueNotifications(harness.context, new Date("2026-10-08T16:35:00Z"))).sent).toBe(1);
    expect(push.sent[0]?.message).toMatchObject({
      title: "Le point de la semaine à Rome",
      body: "2 souvenirs et une photo capturés cette semaine. Ton carnet prend forme : viens voir où il en est.",
    });

    const thread = await harness.prisma.chatMessage.findMany({ where: { memoId: memo.id }, orderBy: { seq: "asc" } });
    expect(thread[0]?.author).toBe("memo"); // l'ouverture
    expect(thread.at(-1)?.text).toBe(
      "Le point de la semaine : 2 souvenirs et une photo capturés cette semaine. Le carnet prend forme ! On continue ?",
    );
    expect(thread.filter((message) => message.author === "traveller")).toHaveLength(3);
  });
});

describe("la fin des 3 étapes offertes", () => {
  it("part le lendemain de la dernière étape validée", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    const memo = await tripToRome(accountId, "daily");
    const message = await toldInChat(memo.id, accountId, new Date("2026-10-04T15:00:00Z"));
    await harness.prisma.entry.update({
      where: { id: message.entryId! },
      data: { validatedAt: new Date("2026-10-04T15:05:00Z") },
    });
    await harness.prisma.account.update({ where: { id: accountId }, data: { offeredSteps: 3, remainingSteps: 0 } });

    // Le soir même : le paywall vient de le dire.
    expect((await sendDueNotifications(harness.context, new Date("2026-10-04T17:35:00Z"))).sent).toBe(0);

    expect((await sendDueNotifications(harness.context, new Date("2026-10-05T08:35:00Z"))).sent).toBe(1);
    expect(push.sent[0]?.message).toMatchObject({
      title: "Tes 3 étapes offertes sont racontées",
      link: "memobook://paywall",
    });
  });
});

describe("le calendrier scolaire", () => {
  it("se recopie et se met à jour sans se dédoubler", async () => {
    const record = {
      description: "Vacances de la Toussaint",
      start_date: "2026-10-16T22:00:00+00:00",
      end_date: "2026-11-01T23:00:00+00:00",
      zones: "Zone B",
      annee_scolaire: "2026-2027",
    };

    expect(await syncSchoolHolidays(harness.context, async () => [record])).toBe(1);
    expect(
      await syncSchoolHolidays(harness.context, async () => [{ ...record, end_date: "2026-11-02T23:00:00+00:00" }]),
    ).toBe(1);

    const rows = await harness.prisma.schoolHoliday.findMany();
    expect(rows).toHaveLength(1);
    expect(rows[0]?.endsOn.toISOString().slice(0, 10)).toBe("2026-11-03");
  });
});
