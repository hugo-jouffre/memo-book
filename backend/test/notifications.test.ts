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
