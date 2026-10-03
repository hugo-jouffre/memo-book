import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  LoggingPushSender,
  type PushDestination,
  type PushMessage,
  type PushOutcome,
  type PushSender,
} from "../src/services/apns.js";
import { APPLE_SUBSCRIPTIONS_URL, type Mailer, type SubscriptionReminderMail } from "../src/services/mailer.js";
import { renderSubscriptionReminderMail } from "../src/services/mailTemplates.js";
import { sendDueNotifications, sendTripEndEmails } from "../src/services/notifications.js";
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

/** Un expéditeur d'e-mails qui retient ce qu'on lui confie, et qu'on peut faire échouer. */
class RecordingMailer implements Mailer {
  readonly reminders: SubscriptionReminderMail[] = [];
  failing = false;

  async sendPasswordReset(): Promise<void> {}
  async sendDataExport(): Promise<void> {}
  async sendSubscriptionReminder(message: SubscriptionReminderMail): Promise<void> {
    if (this.failing) throw new Error("Resend a refusé l’envoi (503)");
    this.reminders.push(message);
  }
}

let harness: TestHarness;
let push: ScriptedPushSender;
let mailer: RecordingMailer;

beforeAll(async () => {
  push = new ScriptedPushSender();
  mailer = new RecordingMailer();
  harness = await createHarness({ push, mailer });
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  push.sent.length = 0;
  push.outcome = { kind: "sent" };
  mailer.reminders.length = 0;
  mailer.failing = false;
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

/**
 * L'abonnement mensuel pris dans l'app, renouvellement armé : Apple le
 * reconduira le jour de `renewsAt`.
 */
async function armedSubscription(accountId: string, renewsAt: Date) {
  return harness.prisma.subscription.create({
    data: {
      accountId,
      provider: "storekit",
      status: "active",
      priceCents: 499,
      interval: "month",
      productId: "com.memobook.app.subscription.monthly",
      autoRenews: true,
      renewsAt,
    },
  });
}

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

  it("rappelle à l'abonné App Store, le jour de la fin, qu'il peut couper son abonnement", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);
    await armedSubscription(accountId, new Date("2026-11-01T09:00:00Z"));

    expect((await sendDueNotifications(harness.context, OCTOBER_12_MORNING)).sent).toBe(1);
    expect(push.sent[0]?.message.title).toBe("Ton voyage à Rome se termine aujourd’hui");
    expect(push.sent[0]?.message.body).toContain(
      "Coupe-le en un geste depuis l’accueil, tu gardes l’illimité jusqu’au 1er novembre.",
    );
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

describe("le rappel avant le renouvellement", () => {
  it("part trois jours avant, quand aucun voyage ne court, une fois par période", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);
    await armedSubscription(accountId, new Date("2026-10-20T09:00:00Z"));

    // 10 h 35 à Paris le 17 octobre : J-3.
    expect((await sendDueNotifications(harness.context, new Date("2026-10-17T08:35:00Z"))).sent).toBe(1);
    expect(push.sent[0]?.message).toMatchObject({
      title: "Ton abonnement se renouvelle dans 3 jours",
      body: "Pas de voyage en cours : si tu n’en as plus besoin, coupe-le en un geste. Tu gardes l’illimité jusqu’au 20 octobre.",
      link: "memobook://subscription",
    });
    expect(await harness.prisma.notificationDelivery.findFirstOrThrow()).toMatchObject({
      kind: "renewal_reminder",
      dedupeKey: `${accountId}:renewal_reminder:2026-10-20`,
      memoId: null,
    });

    // J-2 : la même période, il ne repart pas. Une autre notification peut
    // partir ce jour-là — le carnet du voyage fini le 12 n'est pas commandé —,
    // c'est le rappel qu'on compte, pas les envois.
    await sendDueNotifications(harness.context, new Date("2026-10-18T08:35:00Z"));
    expect(
      await harness.prisma.notificationDelivery.count({ where: { kind: "renewal_reminder" } }),
    ).toBe(1);
    expect(push.sent.filter((sent) => sent.message.title.includes("renouvelle"))).toHaveLength(1);
  });

  it("se tait tant qu'un voyage court", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripToRome(accountId, "daily");
    await armedSubscription(accountId, new Date("2026-10-20T09:00:00Z"));

    expect((await sendDueNotifications(harness.context, new Date("2026-10-17T08:35:00Z"))).sent).toBe(0);
  });

  // R51 (03/10/2026) : « Rappel de fin de voyage » coupé, l'e-mail de fin de
  // voyage part quand même — le rappel ne tombe pas le même jour.
  it("se tait les jours de l'e-mail de fin de voyage, alerte de fin coupée", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    const memo = await tripEndingOctober12(accountId);
    await harness.prisma.memo.update({ where: { id: memo.id }, data: { notifyTripEnd: false } });
    // Renouvellement le 16 : J-3 le 13, le jour de l'e-mail ; J-2 le 14.
    await armedSubscription(accountId, new Date("2026-10-16T09:00:00Z"));

    const october13 = new Date("2026-10-13T08:35:00Z");
    expect((await sendTripEndEmails(harness.context, october13)).sent).toBe(1);
    await sendDueNotifications(harness.context, october13);
    await sendDueNotifications(harness.context, new Date("2026-10-14T08:35:00Z"));
    expect(await harness.prisma.notificationDelivery.count({ where: { kind: "renewal_reminder" } })).toBe(0);
  });

  // S08 (03/10/2026) : un compte entré par Apple sans adresse certifiée
  // (`email` nul) ne reçoit jamais l'e-mail de fin de voyage — le rappel J-3
  // ne doit pas se taire en comptant dessus.
  it("parle le lendemain de la fin à un compte sans adresse, alerte de fin coupée", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await harness.prisma.account.update({ where: { id: accountId }, data: { email: null } });
    const memo = await tripEndingOctober12(accountId);
    await harness.prisma.memo.update({ where: { id: memo.id }, data: { notifyTripEnd: false } });
    // Renouvellement le 16 : J-3 le 13, le lendemain de la fin.
    await armedSubscription(accountId, new Date("2026-10-16T09:00:00Z"));

    const october13 = new Date("2026-10-13T08:35:00Z");
    expect((await sendTripEndEmails(harness.context, october13)).sent).toBe(0);
    await sendDueNotifications(harness.context, october13);
    expect(await harness.prisma.notificationDelivery.findFirst({ where: { kind: "renewal_reminder" } })).toMatchObject({
      dedupeKey: `${accountId}:renewal_reminder:2026-10-16`,
    });
    expect(push.sent.map((sent) => sent.message.title)).toContain("Ton abonnement se renouvelle dans 3 jours");
  });

  // R52 (03/10/2026) : l'ancien abonnement à la semaine, encore honoré, ne
  // reçoit pas un rappel chaque semaine.
  it("n'envoie pas un rappel par semaine à l'ancien abonnement hebdomadaire", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);
    const weekly = await harness.prisma.subscription.create({
      data: {
        accountId,
        provider: "storekit",
        status: "active",
        priceCents: 299,
        interval: "week",
        productId: "com.memobook.app.subscription.weekly",
        autoRenews: true,
        renewsAt: new Date("2026-10-20T09:00:00Z"),
      },
    });

    await sendDueNotifications(harness.context, new Date("2026-10-17T08:35:00Z"));
    expect(await harness.prisma.notificationDelivery.count({ where: { kind: "renewal_reminder" } })).toBe(1);

    // Apple l'a reconduit le 20 : prochain renouvellement le 27, J-3 le 24.
    await harness.prisma.subscription.update({
      where: { id: weekly.id },
      data: { renewsAt: new Date("2026-10-27T09:00:00Z") },
    });
    await sendDueNotifications(harness.context, new Date("2026-10-24T08:35:00Z"));
    expect(await harness.prisma.notificationDelivery.count({ where: { kind: "renewal_reminder" } })).toBe(1);
  });
});

describe("l'e-mail de fin de voyage", () => {
  /** 10 h 35 à Paris le 13 octobre : le lendemain de la fin du voyage à Rome. */
  const OCTOBER_13_MORNING = new Date("2026-10-13T08:35:00Z");

  it("part le lendemain de la fin, même sans téléphone enregistré, une seule fois", async () => {
    const { accountId } = await registerAccount(harness.app);
    const memo = await tripEndingOctober12(accountId);
    const renewsAt = new Date("2026-11-01T09:00:00Z");
    await armedSubscription(accountId, renewsAt);

    // Le jour même : la notification et l'accueil viennent de le dire.
    expect((await sendTripEndEmails(harness.context, OCTOBER_12_MORNING)).sent).toBe(0);

    expect((await sendTripEndEmails(harness.context, OCTOBER_13_MORNING)).sent).toBe(1);
    expect(mailer.reminders).toHaveLength(1);
    expect(mailer.reminders[0]).toMatchObject({
      to: "voyageur@memobook.app",
      firstName: "Hugo",
      trip: { title: "Rome 2026", city: "Rome" },
      unlimitedUntil: renewsAt,
    });
    expect(mailer.reminders[0]?.bookEstimateCents).toBeGreaterThan(0);

    expect(await harness.prisma.notificationDelivery.findFirstOrThrow()).toMatchObject({
      accountId,
      memoId: memo.id,
      kind: "trip_end_email",
      dedupeKey: `${accountId}:trip_end_email:${memo.id}`,
      link: APPLE_SUBSCRIPTIONS_URL,
      deliveredCount: 1,
    });

    // L'heure suivante, le lendemain : déjà parti.
    await sendTripEndEmails(harness.context, new Date("2026-10-13T09:35:00Z"));
    await sendTripEndEmails(harness.context, new Date("2026-10-14T08:35:00Z"));
    expect(mailer.reminders).toHaveLength(1);
  });

  it("dit doucement comment couper l'abonnement, jusqu'à quand l'illimité reste ouvert, et le carnet qui attend", async () => {
    const mail = renderSubscriptionReminderMail(
      {
        to: "voyageur@memobook.app",
        firstName: "Hugo",
        trip: { title: "Rome 2026", city: "Rome" },
        unlimitedUntil: new Date("2026-11-01T09:00:00Z"),
        bookEstimateCents: 4290,
      },
      APPLE_SUBSCRIPTIONS_URL,
    );

    expect(mail.subject).toBe("Ton voyage est fini : pense à ton abonnement");
    expect(mail.text).toContain("Ton voyage à Rome est terminé");
    expect(mail.text).toContain("tu gardes l’illimité jusqu’au 1er novembre 2026.");
    expect(mail.text).toContain("Réglages ▸ ton nom ▸ Abonnements");
    expect(mail.text).toMatch(/Et ton carnet à Rome n’attend plus que ta commande : il est estimé à 42,90\s€\./);
    expect(mail.html).toContain(`href="${APPLE_SUBSCRIPTIONS_URL}"`);
  });

  it("ne part ni sans abonnement armé, ni avant 10 h, ni sans APNs pour autant", async () => {
    const { accountId } = await registerAccount(harness.app);
    await tripEndingOctober12(accountId);

    expect((await sendTripEndEmails(harness.context, OCTOBER_13_MORNING)).sent).toBe(0);

    // Résilié : le renouvellement n'est plus armé, il n'y a rien à couper.
    const subscription = await armedSubscription(accountId, new Date("2026-11-01T09:00:00Z"));
    await harness.prisma.subscription.update({
      where: { id: subscription.id },
      data: { status: "cancelled", autoRenews: false },
    });
    expect((await sendTripEndEmails(harness.context, OCTOBER_13_MORNING)).sent).toBe(0);

    await harness.prisma.subscription.update({
      where: { id: subscription.id },
      data: { status: "active", autoRenews: true },
    });
    // 9 h 35 à Paris : trop tôt.
    expect((await sendTripEndEmails(harness.context, new Date("2026-10-13T07:35:00Z"))).sent).toBe(0);

    const off: PushSender = {
      enabled: false,
      send: () => Promise.resolve({ kind: "failed", reason: "APNs n'est pas configuré." }),
      close: () => Promise.resolve(),
    };
    expect((await sendTripEndEmails({ ...harness.context, push: off }, OCTOBER_13_MORNING)).sent).toBe(1);
  });

  it("retente à la passe suivante un e-mail que l'envoi a refusé", async () => {
    const { accountId } = await registerAccount(harness.app);
    await tripEndingOctober12(accountId);
    await armedSubscription(accountId, new Date("2026-11-01T09:00:00Z"));

    mailer.failing = true;
    expect((await sendTripEndEmails(harness.context, OCTOBER_13_MORNING)).sent).toBe(0);
    expect(await harness.prisma.notificationDelivery.count()).toBe(0);

    mailer.failing = false;
    expect((await sendTripEndEmails(harness.context, new Date("2026-10-13T09:35:00Z"))).sent).toBe(1);
  });

  it("ne prend pas la place d'une notification : ni journée de facturation, ni « une par jour »", async () => {
    const { accountId, authorization } = await registerAccount(harness.app);
    await registerToken(authorization);
    await tripEndingOctober12(accountId);
    await armedSubscription(accountId, new Date("2026-11-01T09:00:00Z"));
    // Un anniversaire le 20 octobre : sa notification tombe le 13, le jour de l'e-mail.
    await harness.prisma.account.update({ where: { id: accountId }, data: { birthDate: new Date("1994-10-20") } });

    expect((await sendTripEndEmails(harness.context, OCTOBER_13_MORNING)).sent).toBe(1);
    expect((await sendDueNotifications(harness.context, new Date("2026-10-13T09:35:00Z"))).sent).toBe(1);
    expect(push.sent.map((sent) => sent.message.title)).toEqual(["Ton anniversaire approche 🎂"]);
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
