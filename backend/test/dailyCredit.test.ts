import { randomUUID } from "node:crypto";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { converseTurn } from "../src/jobs/converse.js";
import { JOB_NAMES } from "../src/jobs/queue.js";
import {
  FakeResponder,
  validateReply,
  type ConversationInput,
  type ConversationReply,
} from "../src/services/conversation.js";
import { DAILY_CREDIT_EXHAUSTED_MESSAGE, SUGGESTIONS } from "../src/services/conversationCopy.js";
import {
  CORRECTION_SHORT_MESSAGE,
  DAILY_CREDIT_LIMIT_MS,
  DAILY_CREDIT_REFUSAL_MESSAGE,
  DAILY_CREDIT_SHORT_MESSAGE,
  EXHAUSTION_SLACK_MS,
  SILENT_COMMAND_FREE_CHARACTERS,
  TEXT_TOO_LONG_MESSAGE,
  TRANSCRIPT_OVERRUN_FLOOR_MS,
  VOICE_TOO_LONG_LOST_MESSAGE,
  VOICE_TOO_LONG_MESSAGE,
  TEXT_MS_PER_CHARACTER,
  URGENT_REMAINING_MS,
  VOICE_TOLERANCE_MS,
  WARNING_REMAINING_MS,
  countCharacters,
  formatCreditDuration,
  isFreeChatText,
  localMidnightAfter,
  type SerializedDailyCredit,
} from "../src/services/dailyCredit.js";
import { addDays, localDate } from "../src/services/localCalendar.js";
import { FakeTranscriber } from "../src/services/transcription.js";
import { grantsUnlimitedAccess, hasUnlimitedAccess } from "../src/services/subscriptions.js";
import {
  VOICE_FIXTURES,
  createHarness,
  multipartBody,
  registerAccount,
  resetDatabase,
  type TestHarness,
} from "./helpers.js";

/**
 * **Le crédit du jour** (Hugo, 03/10/2026) — `services/dailyCredit.ts`.
 *
 * 5 minutes par jour et par voyage, partagées entre les co-voyageurs non
 * abonnés ; un vocal consomme sa durée mesurée, un texte 75 ms par caractère ;
 * un abonné ne consomme rien. Ce qui est vérifié ici, c'est ce qu'aucune app
 * ne peut contourner : la mesure, le décompte sous le verrou du voyage, le
 * refus, et la bulle « reviens demain ».
 *
 * Les deux vocaux de test sont de vrais `.m4a` (`test/fixtures/audio/`) :
 * 2 136 ms et 7 105 ms une fois mesurés.
 */

const SHORT_VOICE_MS = 2_136;
const LONG_VOICE_MS = 7_105;
const DAY = 86_400_000;
const PARIS = "Europe/Paris";

/**
 * L'app de ce lot envoie `X-Time-Zone` sur chaque appel, et garde dans sa file
 * un tour refusé faute de crédit ; un build installé avant elle n'envoie pas
 * l'en-tête, et perd le tour. Le refus ne leur dit pas la même chose
 * (`holdsRefusedTurns`).
 */
const NEW_APP = { timeZone: PARIS } as const;

interface MessageJson {
  id: string;
  author: "memo" | "traveller";
  body: { kind: string; text?: string; voice?: { duration: number } };
  callToAction?: { id: string; kind: string; label: string; eyebrow: string; dismissible: boolean };
}

interface ReceiptJson {
  messages: MessageJson[];
  dailyCredit: SerializedDailyCredit;
}

interface RefusalJson {
  error: string;
  message: string;
  dailyCredit: SerializedDailyCredit;
}

let harness: TestHarness;
let owner: { accountId: string; authorization: string };
let codes = 0;

beforeAll(async () => {
  harness = await createHarness();
});

afterAll(async () => {
  await harness.close();
});

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  owner = await registerAccount(harness.app, "hugo@memobook.app");
});

/** Un voyage **en cours** : commencé avant-hier, fini dans dix jours. */
async function tripOf(accountId: string, dates: { startDate?: Date; endDate?: Date } = {}) {
  codes += 1;
  return harness.prisma.memo.create({
    data: {
      ownerAccountId: accountId,
      title: "Rome 2026",
      accessCode: `CRD${String(codes).padStart(3, "0")}`,
      stage: "ongoing",
      startDate: dates.startDate ?? new Date(Date.now() - 2 * DAY),
      endDate: dates.endDate ?? new Date(Date.now() + 10 * DAY),
    },
  });
}

/** Le jour d'un compte sans fuseau : celui de Paris. */
function today(): string {
  return localDate(new Date(), PARIS);
}

/** Pose ce que le voyage a déjà consommé aujourd'hui. */
async function spend(memoId: string, usedMs: number, day = today()) {
  await harness.prisma.tripDailyUsage.create({
    data: { memoId, day: new Date(`${day}T00:00:00Z`), usedMs },
  });
}

async function usage(memoId: string, day = today()) {
  return harness.prisma.tripDailyUsage.findUnique({
    where: { memoId_day: { memoId, day: new Date(`${day}T00:00:00Z`) } },
  });
}

async function say(
  memoId: string,
  text: string,
  extra: { id?: string; suggestionId?: string; authorization?: string; timeZone?: string } = {},
) {
  const id = extra.id ?? randomUUID();
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: {
      authorization: extra.authorization ?? owner.authorization,
      ...(extra.timeZone ? { "x-time-zone": extra.timeZone } : {}),
    },
    payload: { id, kind: "text", text, ...(extra.suggestionId ? { suggestionId: extra.suggestionId } : {}) },
  });
  return { id, response };
}

async function speak(
  memoId: string,
  content: Buffer,
  extra: { id?: string; authorization?: string; durationSeconds?: string; timeZone?: string } = {},
) {
  const id = extra.id ?? randomUUID();
  const { payload, contentType } = multipartBody(
    { id, ...(extra.durationSeconds ? { durationSeconds: extra.durationSeconds } : {}) },
    { field: "file", filename: "vocal.m4a", contentType: "audio/mp4", content },
  );
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: {
      authorization: extra.authorization ?? owner.authorization,
      "content-type": contentType,
      ...(extra.timeZone ? { "x-time-zone": extra.timeZone } : {}),
    },
    payload,
  });
  return { id, response };
}

async function sendPhoto(memoId: string) {
  const { payload, contentType } = multipartBody(
    { id: randomUUID() },
    { field: "file", filename: "photo.jpg", contentType: "image/jpeg", content: Buffer.from("jpeg") },
  );
  return harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization, "content-type": contentType },
    payload,
  });
}

/**
 * Un vocal de `seconds` secondes **pour le serveur** : le vocal de 7 s du
 * dépôt, dont `stts` et `stsz` annoncent autant de paquets AAC qu'il en faut.
 * Le serveur ne mesure que les tables ; le transcripteur simulé ne décode
 * rien. De quoi passer les 5:03 sans commiter cinq minutes d'audio.
 */
function voiceLasting(seconds: number): { content: Buffer; durationMs: number } {
  const content = Buffer.from(VOICE_FIXTURES.long);
  const packets = Math.ceil((seconds * 22_050) / 1_024);
  // `moov` précède `mdat` dans la fixture : la première occurrence est la table.
  const stts = content.indexOf("stts", 0, "latin1") + 4;
  content.writeUInt32BE(1, stts + 4); // une seule entrée…
  content.writeUInt32BE(packets, stts + 8); // … de `packets` paquets…
  content.writeUInt32BE(1_024, stts + 12); // … de 1 024 échantillons.
  const stsz = content.indexOf("stsz", 0, "latin1") + 4;
  content.writeUInt32BE(100, stsz + 4); // une taille commune de 100 octets
  content.writeUInt32BE(packets, stsz + 8);
  return { content, durationMs: Math.round((packets * 1_024 * 1_000) / 22_050) };
}

async function subscribe(accountId: string, data: { status?: "active" | "cancelled" | "expired"; renewsAt?: Date } = {}) {
  await harness.prisma.subscription.create({
    data: {
      accountId,
      provider: "storekit",
      status: data.status ?? "active",
      priceCents: 499,
      interval: "month",
      renewsAt: data.renewsAt ?? new Date(Date.now() + 30 * DAY),
    },
  });
}

async function readThread(memoId: string, authorization = owner.authorization) {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization },
  });
  expect(response.statusCode).toBe(200);
  return response.json<{ messages: MessageJson[]; dailyCredit: SerializedDailyCredit }>();
}

function notices(messages: MessageJson[]): MessageJson[] {
  return messages.filter((message) => message.body.text === DAILY_CREDIT_EXHAUSTED_MESSAGE);
}

async function noticeCount(memoId: string): Promise<number> {
  return harness.prisma.chatMessage.count({ where: { memoId, text: DAILY_CREDIT_EXHAUSTED_MESSAGE } });
}

// ---------------------------------------------------------------------------

describe("le barème", () => {
  it("compte les caractères en scalaires Unicode, comme l'app", () => {
    // « é » précomposé vaut un, un drapeau deux scalaires — et non quatre
    // unités UTF-16.
    expect(countCharacters("été 🇫🇷")).toBe(6);
    expect(800 * TEXT_MS_PER_CHARACTER).toBe(60_000);
    expect(4_000 * TEXT_MS_PER_CHARACTER).toBe(DAILY_CREDIT_LIMIT_MS);
  });

  it("ne laisse gratuite qu'une puce envoyée telle quelle", () => {
    expect(isFreeChatText(SUGGESTIONS.later.label, "later")).toBe(true);
    expect(isFreeChatText(`${SUGGESTIONS.later.label}, mais d'abord le Colisée`, "later")).toBe(false);
    expect(isFreeChatText(SUGGESTIONS.later.label, null)).toBe(false);
    expect(isFreeChatText("J’ai retouché le texte à la main.", "transcript_edited")).toBe(true);
    expect(isFreeChatText("x".repeat(SILENT_COMMAND_FREE_CHARACTERS + 1), "transcript_edited")).toBe(false);
  });

  it("écrit une durée de crédit comme l'app", () => {
    expect(formatCreditDuration(45_900)).toBe("45 s");
    expect(formatCreditDuration(180_000)).toBe("3 min");
    expect(formatCreditDuration(65_000)).toBe("1 min 05");
    expect(formatCreditDuration(150_999)).toBe("2 min 30");
    expect(formatCreditDuration(400)).toBe("moins d’une seconde");
  });

  it("recharge à minuit chez celui qui lit, changements d'heure compris", () => {
    expect(localMidnightAfter("2026-10-03", PARIS).toISOString()).toBe("2026-10-03T22:00:00.000Z");
    expect(localMidnightAfter("2026-10-03", "Asia/Tokyo").toISOString()).toBe("2026-10-03T15:00:00.000Z");
    expect(localMidnightAfter("2026-10-03", "America/New_York").toISOString()).toBe("2026-10-04T04:00:00.000Z");
    // La nuit du passage à l'heure d'hiver : minuit est encore à l'heure d'été.
    expect(localMidnightAfter("2026-10-24", PARIS).toISOString()).toBe("2026-10-24T22:00:00.000Z");
    expect(localMidnightAfter("2026-10-25", PARIS).toISOString()).toBe("2026-10-25T23:00:00.000Z");
  });

  it("lit l'accès illimité de la même façon en base et sur une ligne chargée", async () => {
    const now = new Date();
    const cases = [
      { status: "active", renewsAt: null },
      { status: "trialing", renewsAt: null },
      { status: "past_due", renewsAt: new Date(now.getTime() - DAY) },
      // Vivant mais muet depuis une semaine : un `EXPIRED` s'est perdu.
      { status: "active", renewsAt: new Date(now.getTime() - 7 * DAY) },
      { status: "past_due", renewsAt: new Date(now.getTime() - 7 * DAY) },
      { status: "cancelled", renewsAt: new Date(now.getTime() + DAY) },
      { status: "cancelled", renewsAt: new Date(now.getTime() - DAY) },
      { status: "expired", renewsAt: new Date(now.getTime() + DAY) },
      { status: "expired", renewsAt: null },
    ] as const;

    for (const [index, entry] of cases.entries()) {
      const account = await registerAccount(harness.app, `acces-${index}@memobook.app`);
      await harness.prisma.subscription.create({
        data: { accountId: account.accountId, provider: "storekit", priceCents: 499, ...entry },
      });
      expect(await hasUnlimitedAccess(harness.prisma, account.accountId, now)).toBe(
        grantsUnlimitedAccess(entry, now),
      );
    }
  });
});

describe("un texte", () => {
  it("coûte 75 ms par caractère, et le reçu porte le crédit après le tour", async () => {
    const memo = await tripOf(owner.accountId);
    const { response } = await say(memo.id, "a".repeat(800));

    expect(response.statusCode).toBe(201);
    const day = today();
    expect(response.json<ReceiptJson>().dailyCredit).toEqual({
      isUnlimited: false,
      limitMs: 300_000,
      usedMs: 60_000,
      remainingMs: 240_000,
      textMsPerCharacter: 75,
      warningRemainingMs: WARNING_REMAINING_MS,
      urgentRemainingMs: URGENT_REMAINING_MS,
      exhaustionSlackMs: EXHAUSTION_SLACK_MS,
      day,
      resetsAt: localMidnightAfter(day, PARIS).toISOString(),
    });
    expect(await usage(memo.id)).toMatchObject({ usedMs: 60_000, textCharacters: 800, voiceMs: 0 });
  });

  it("ne coûte rien en puce envoyée telle quelle ; déguisée en puce, il paie", async () => {
    const memo = await tripOf(owner.accountId);

    const chip = await say(memo.id, SUGGESTIONS.later.label, { suggestionId: "later" });
    expect(chip.response.statusCode).toBe(201);
    expect(await usage(memo.id)).toBeNull();

    const disguised = "Plus tard, mais d'abord : on a dîné sur la terrasse.";
    const text = await say(memo.id, disguised, { suggestionId: "later" });
    expect(text.response.statusCode).toBe(201);
    expect((await usage(memo.id))?.usedMs).toBe(countCharacters(disguised) * TEXT_MS_PER_CHARACTER);
  });

  it("est refusé entier quand il dépasse le reste, avec le solde dans le corps", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 10 * TEXT_MS_PER_CHARACTER);

    const { id, response } = await say(memo.id, "onze lettre", NEW_APP);
    expect(response.statusCode).toBe(429);
    const body = response.json<RefusalJson>();
    expect(body.error).toBe("daily_credit_exhausted");
    // Il reste 750 ms : le refus ne dit pas « épuisé » (03/10/2026).
    expect(body.message).toBe(DAILY_CREDIT_SHORT_MESSAGE);
    expect(body.message).not.toContain("épuisé");
    expect(body.dailyCredit).toMatchObject({ isUnlimited: false, remainingMs: 750, limitMs: 300_000 });
    expect(body.dailyCredit.resetsAt).toBe(localMidnightAfter(today(), PARIS).toISOString());
    // Rien d'écrit, rien de compté.
    expect(await harness.prisma.chatMessage.findUnique({ where: { id } })).toBeNull();
    expect((await usage(memo.id))?.usedMs).toBe(DAILY_CREDIT_LIMIT_MS - 750);

    // Dix lettres tiennent juste.
    const exact = await say(memo.id, "dixlettres");
    expect(exact.response.statusCode).toBe(201);
    expect(exact.response.json<ReceiptJson>().dailyCredit.remainingMs).toBe(0);
  });

  it("refusé à un build installé, ne promet aucun renvoi : il dit ce qui reste", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 90_000);

    // 2 000 caractères : 2:30, quand il reste 1:30. Sans `X-Time-Zone`, la
    // file du client efface le tour refusé — « il partira demain » serait faux.
    const { response } = await say(memo.id, "l".repeat(2_000));

    expect(response.statusCode).toBe(429);
    const body = response.json<RefusalJson>();
    expect(body.error).toBe("daily_credit_exhausted");
    expect(body.message).toBe(
      "Il reste 1 min 30 aujourd’hui sur ce voyage, pas assez pour ce message : raccourcis-le, ou passe en illimité.",
    );
    expect(body.message).not.toContain("partira");
    expect(body.dailyCredit.remainingMs).toBe(90_000);

    // Le même tour, envoyé par l'app de ce lot, partira demain.
    const held = await say(memo.id, "l".repeat(2_000), NEW_APP);
    expect(held.response.json<RefusalJson>().message).toBe(DAILY_CREDIT_SHORT_MESSAGE);
  });
});

describe("un vocal", () => {
  it("se décompte de sa durée mesurée, pas de celle que l'app déclare", async () => {
    const memo = await tripOf(owner.accountId);
    const { id, response } = await speak(memo.id, VOICE_FIXTURES.short, { durationSeconds: "1" });

    expect(response.statusCode).toBe(201);
    expect(response.json<ReceiptJson>().dailyCredit.usedMs).toBe(SHORT_VOICE_MS);
    expect(await usage(memo.id)).toMatchObject({ usedMs: SHORT_VOICE_MS, voiceMs: SHORT_VOICE_MS });

    // La mesure s'écrit partout — et la transcription (12 s en simulé) ne
    // l'écrase pas.
    const entry = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id },
      include: { media: true },
    });
    expect(entry.media?.durationSeconds).toBeCloseTo(SHORT_VOICE_MS / 1000, 3);
    const voice = (await readThread(memo.id)).messages.find((message) => message.id === id);
    expect(voice?.body.voice?.duration).toBeCloseTo(SHORT_VOICE_MS / 1000, 3);
  });

  it("refuse un fichier qu'il ne sait pas lire, sans rien écrire ni compter", async () => {
    const memo = await tripOf(owner.accountId);
    const { response } = await speak(memo.id, Buffer.from("pas un vocal"));

    expect(response.statusCode).toBe(400);
    expect(response.json<{ error: string }>().error).toBe("unreadable_audio");
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
    expect(await usage(memo.id)).toBeNull();
  });

  it("passe en dernier s'il ne dépasse le reste que de la tolérance, et vide le pot", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 1_000);
    expect(SHORT_VOICE_MS).toBeLessThanOrEqual(1_000 + VOICE_TOLERANCE_MS);

    const { response } = await speak(memo.id, VOICE_FIXTURES.short);

    expect(response.statusCode).toBe(201);
    const receipt = response.json<ReceiptJson>();
    // Compté jusqu'à la limite, pas au-delà.
    expect(receipt.dailyCredit).toMatchObject({ usedMs: DAILY_CREDIT_LIMIT_MS, remainingMs: 0 });
    expect(await usage(memo.id)).toMatchObject({ usedMs: DAILY_CREDIT_LIMIT_MS, voiceMs: SHORT_VOICE_MS });
    // MEMO le dit dans le même reçu, derrière le vocal et sa fiche.
    expect(receipt.messages.map((message) => message.body.kind)).toEqual(["text", "voice", "transcript", "text"]);
    expect(notices(receipt.messages)[0]?.callToAction).toEqual({
      id: "daily_credit_subscribe",
      kind: "subscribe",
      label: "Raconter sans limite",
      eyebrow: "Crédit du jour épuisé",
      dismissible: true,
    });
  });

  it("attend demain au-delà de la tolérance : 429, rien d'écrit", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 1_000);

    const { id, response } = await speak(memo.id, VOICE_FIXTURES.long, NEW_APP);

    expect(LONG_VOICE_MS).toBeGreaterThan(1_000 + VOICE_TOLERANCE_MS);
    expect(response.statusCode).toBe(429);
    expect(response.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_exhausted",
      message: DAILY_CREDIT_SHORT_MESSAGE,
    });
    expect(response.json<RefusalJson>().dailyCredit.remainingMs).toBe(1_000);
    expect(await harness.prisma.chatMessage.findUnique({ where: { id } })).toBeNull();
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
    // Il reste une seconde : MEMO ne dit pas « tes 5 minutes sont racontées ».
    expect(await noticeCount(memo.id)).toBe(0);
    expect((await usage(memo.id))?.limitNotifiedAt).toBeNull();
  });

  it("refusé à un build installé, il ne promet pas de partir demain : ce vocal-là est effacé", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 1_000);

    const { response } = await speak(memo.id, VOICE_FIXTURES.long);

    expect(response.statusCode).toBe(429);
    expect(response.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_exhausted",
      message:
        "Il reste 1 s aujourd’hui sur ce voyage, pas assez pour ce vocal : redis-le en plus court, ou passe en illimité.",
    });
  });

  it("arrondit à zéro un reste de quelques millisecondes, et MEMO le dit", async () => {
    const memo = await tripOf(owner.accountId);
    // L'app a coupé à zéro ; le fichier mesuré finit un peu avant.
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - (SHORT_VOICE_MS + 400));

    const { response } = await speak(memo.id, VOICE_FIXTURES.short);

    expect(response.statusCode).toBe(201);
    expect(response.json<ReceiptJson>().dailyCredit).toMatchObject({
      usedMs: DAILY_CREDIT_LIMIT_MS,
      remainingMs: 0,
    });
    expect(notices(response.json<ReceiptJson>().messages)).toHaveLength(1);
  });

  it("arrondit aussi le reste d'un texte : aucun solde servi entre 0 et une seconde", async () => {
    const memo = await tripOf(owner.accountId);
    // 20 caractères (1,5 s) sur un reste de 2 s : il resterait 500 ms.
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 2_000);

    const { response } = await say(memo.id, "vingt caractères ok!");

    expect(response.statusCode).toBe(201);
    expect(response.json<ReceiptJson>().dailyCredit).toMatchObject({
      remainingMs: 0,
      exhaustionSlackMs: EXHAUSTION_SLACK_MS,
    });
  });

  it("ne passe plus à zéro — les photos, si", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS);

    const refused = (await speak(memo.id, VOICE_FIXTURES.short)).response;
    expect(refused.statusCode).toBe(429);
    // Le pot est vide : là, « épuisé » est juste.
    expect(refused.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_exhausted",
      message: DAILY_CREDIT_REFUSAL_MESSAGE,
    });
    expect((await sendPhoto(memo.id)).statusCode).toBe(201);
  });
});

describe("la bulle « reviens demain »", () => {
  it("se pose une seule fois par jour, et le reçu du tour qui vide le pot la contient", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 10 * TEXT_MS_PER_CHARACTER);

    const last = await say(memo.id, "dixlettres");
    expect(notices(last.response.json<ReceiptJson>().messages)).toHaveLength(1);

    // Les refus qui suivent ne la répètent pas.
    expect((await say(memo.id, "Encore un mot.")).response.statusCode).toBe(429);
    expect((await speak(memo.id, VOICE_FIXTURES.short)).response.statusCode).toBe(429);
    expect(await noticeCount(memo.id)).toBe(1);

    const stored = await harness.prisma.chatMessage.findFirstOrThrow({
      where: { memoId: memo.id, text: DAILY_CREDIT_EXHAUSTED_MESSAGE },
    });
    expect(stored).toMatchObject({ author: "memo", kind: "text", model: "scripted", accountId: null });
    expect(stored.payload).toEqual({
      callToAction: { id: "daily_credit_subscribe" },
      notice: `daily_credit_exhausted:${today()}`,
      audience: "limited",
    });
  });

  it("se pose aussi quand un tour est refusé et qu'elle n'y était pas encore", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS);

    expect((await say(memo.id, "Un mot de trop.")).response.statusCode).toBe(429);
    expect(await noticeCount(memo.id)).toBe(1);
    expect((await usage(memo.id))?.limitNotifiedAt).not.toBeNull();
  });

  it("ne se montre pas à un co-voyageur abonné, et sans offre", async () => {
    const memo = await tripOf(owner.accountId);
    const guest = await registerAccount(harness.app, "clara@memobook.app");
    await harness.prisma.memoMember.create({
      data: { memoId: memo.id, accountId: guest.accountId, status: "active", acceptedAt: new Date() },
    });
    await subscribe(guest.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 10 * TEXT_MS_PER_CHARACTER);
    await say(memo.id, "dixlettres");

    const mine = await readThread(memo.id);
    expect(notices(mine.messages)).toHaveLength(1);
    expect(notices(mine.messages)[0]?.callToAction?.id).toBe("daily_credit_subscribe");
    expect(mine.dailyCredit).toMatchObject({ isUnlimited: false, remainingMs: 0 });

    const theirs = await readThread(memo.id, guest.authorization);
    expect(notices(theirs.messages)).toHaveLength(0);
    // Le même pot, vu par quelqu'un qui n'en dépend pas.
    expect(theirs.dailyCredit).toMatchObject({ isUnlimited: true, usedMs: DAILY_CREDIT_LIMIT_MS });
  });
});

describe("l'abonné", () => {
  it("ne consomme rien, pot vide compris — son usage ne se lit qu'au détail", async () => {
    await subscribe(owner.accountId);
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS);

    const { response } = await say(memo.id, "Toujours là, toujours à raconter.");
    expect(response.statusCode).toBe(201);
    const receipt = response.json<ReceiptJson>();
    expect(receipt.dailyCredit.isUnlimited).toBe(true);
    expect(notices(receipt.messages)).toHaveLength(0);

    const voice = await speak(memo.id, VOICE_FIXTURES.long);
    expect(voice.response.statusCode).toBe(201);
    expect(await usage(memo.id)).toMatchObject({
      usedMs: DAILY_CREDIT_LIMIT_MS,
      voiceMs: LONG_VOICE_MS,
      textCharacters: countCharacters("Toujours là, toujours à raconter."),
    });
  });

  it("raconte sans limite jusqu'au bout du mois payé après avoir résilié, plus après", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS);

    await subscribe(owner.accountId, { status: "cancelled", renewsAt: new Date(Date.now() + 10 * DAY) });
    expect((await say(memo.id, "Encore sous le mois payé.")).response.statusCode).toBe(201);

    await harness.prisma.subscription.updateMany({
      where: { accountId: owner.accountId },
      data: { renewsAt: new Date(Date.now() - DAY) },
    });
    expect((await say(memo.id, "Le mois est fini.")).response.statusCode).toBe(429);
  });
});

describe("la concurrence", () => {
  it("deux vocaux envoyés au même instant ne dépassent pas le crédit", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 1_000);

    const results = await Promise.all([speak(memo.id, VOICE_FIXTURES.short), speak(memo.id, VOICE_FIXTURES.short)]);

    expect(results.map(({ response }) => response.statusCode).sort()).toEqual([201, 429]);
    expect(await usage(memo.id)).toMatchObject({ usedMs: DAILY_CREDIT_LIMIT_MS, voiceMs: SHORT_VOICE_MS });
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "audio" } })).toBe(1);
    expect(await noticeCount(memo.id)).toBe(1);
  });

  it("deux textes non plus, même par deux co-voyageurs", async () => {
    const memo = await tripOf(owner.accountId);
    const guest = await registerAccount(harness.app, "clara@memobook.app");
    await harness.prisma.memoMember.create({
      data: { memoId: memo.id, accountId: guest.accountId, status: "active", acceptedAt: new Date() },
    });
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 60_000);

    const text = "b".repeat(600); // 45 s chacun : un seul tient.
    const results = await Promise.all([
      say(memo.id, text),
      say(memo.id, text, { authorization: guest.authorization }),
    ]);

    expect(results.map(({ response }) => response.statusCode).sort()).toEqual([201, 429]);
    expect((await usage(memo.id))?.usedMs).toBe(DAILY_CREDIT_LIMIT_MS - 15_000);
  });
});

describe("le jour", () => {
  it("ne recule jamais : une ligne plus récente reste celle qu'on consomme", async () => {
    // Un co-voyageur à Tokyo a déjà ouvert la journée de demain.
    const memo = await tripOf(owner.accountId);
    const tomorrow = addDays(today(), 1);
    await spend(memo.id, 100_000, tomorrow);

    const { response } = await say(memo.id, "huit car");

    expect(response.statusCode).toBe(201);
    expect(response.json<ReceiptJson>().dailyCredit).toMatchObject({
      day: tomorrow,
      usedMs: 100_600,
      resetsAt: localMidnightAfter(tomorrow, PARIS).toISOString(),
    });
    expect(await usage(memo.id)).toBeNull();
    expect((await usage(memo.id, tomorrow))?.usedMs).toBe(100_600);
  });

  it("se lit au fuseau du téléphone, que l'en-tête X-Time-Zone tient à jour", async () => {
    const memo = await tripOf(owner.accountId);

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: owner.authorization, "x-time-zone": "Asia/Tokyo" },
    });
    expect(home.statusCode).toBe(200);
    expect((await harness.prisma.account.findUniqueOrThrow({ where: { id: owner.accountId } })).timeZone).toBe(
      "Asia/Tokyo",
    );

    const { response } = await say(memo.id, "konnichiwa");
    const day = localDate(new Date(), "Asia/Tokyo");
    expect(response.json<ReceiptJson>().dailyCredit).toMatchObject({
      day,
      resetsAt: localMidnightAfter(day, "Asia/Tokyo").toISOString(),
    });

    // Un fuseau inventé ne change rien.
    await harness.app.inject({
      method: "GET",
      url: "/v1/profile",
      headers: { authorization: owner.authorization, "x-time-zone": "Mars/Olympus" },
    });
    expect((await harness.prisma.account.findUniqueOrThrow({ where: { id: owner.accountId } })).timeZone).toBe(
      "Asia/Tokyo",
    );
  });
});

describe("les autres portes", () => {
  it("la route ancienne se décompte comme le chat", async () => {
    const memo = await tripOf(owner.accountId);
    const text = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/entries`,
      headers: { authorization: owner.authorization },
      payload: { kind: "text", transcript: "c".repeat(100) },
    });
    expect(text.statusCode).toBe(201);

    const { payload, contentType } = multipartBody(
      { durationSeconds: "1" },
      { field: "file", filename: "vocal.m4a", contentType: "audio/mp4", content: VOICE_FIXTURES.short },
    );
    const voice = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/entries`,
      headers: { authorization: owner.authorization, "content-type": contentType },
      payload,
    });
    expect(voice.statusCode).toBe(201);
    expect(voice.json<{ media: { durationSeconds: number } | null }>().media?.durationSeconds).toBeCloseTo(
      SHORT_VOICE_MS / 1000,
      3,
    );

    expect((await usage(memo.id))?.usedMs).toBe(100 * TEXT_MS_PER_CHARACTER + SHORT_VOICE_MS);

    // Le pot vidé (sur la journée de demain, déjà ouverte : le jour ne recule pas).
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS, addDays(today(), 1));
    const refused = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/entries`,
      headers: { authorization: owner.authorization },
      payload: { kind: "text", transcript: "Un de trop." },
    });
    expect(refused.statusCode).toBe(429);
  });

  it("une correction à la main paie ce qu'elle ajoute, rien de plus", async () => {
    const memo = await tripOf(owner.accountId);
    const entry = await harness.prisma.entry.create({
      data: { memoId: memo.id, kind: "text", status: "ready", transcript: "d".repeat(100), capturedAt: new Date() },
    });
    const patch = (editedText: string | null) =>
      harness.app.inject({
        method: "PATCH",
        url: `/v1/entries/${entry.id}`,
        headers: { authorization: owner.authorization },
        payload: { editedText },
      });

    expect((await patch("e".repeat(300))).statusCode).toBe(200);
    expect((await usage(memo.id))?.usedMs).toBe(200 * TEXT_MS_PER_CHARACTER);

    // Raccourcir, revenir à la version proposée : gratuit.
    expect((await patch("e".repeat(50))).statusCode).toBe(200);
    expect((await patch(null)).statusCode).toBe(200);
    expect((await usage(memo.id))?.usedMs).toBe(200 * TEXT_MS_PER_CHARACTER);
  });

  it("valider rend le souvenir, et plus d'étapes", async () => {
    const memo = await tripOf(owner.accountId);
    const entry = await harness.prisma.entry.create({
      data: { memoId: memo.id, kind: "text", status: "ready", transcript: "Le Colisée.", capturedAt: new Date() },
    });

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/entries/${entry.id}/validate`,
      headers: { authorization: owner.authorization },
    });

    expect(response.statusCode).toBe(200);
    expect(Object.keys(response.json<object>())).toEqual(["entry"]);
    expect(response.json<{ entry: { validatedAt: string | null } }>().entry.validatedAt).not.toBeNull();
  });
});

describe("les écrans", () => {
  it("les réglages servent le crédit du jour à la place des limites de souvenirs", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, 90_000);

    const settings = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}/settings`,
      headers: { authorization: owner.authorization },
    });
    expect(settings.statusCode).toBe(200);
    const body = settings.json<{ dailyCredit: SerializedDailyCredit; memory?: unknown }>();
    expect(body).not.toHaveProperty("memory");
    expect(body.dailyCredit).toMatchObject({ isUnlimited: false, usedMs: 90_000, remainingMs: 210_000 });

    const patched = await harness.app.inject({
      method: "PATCH",
      url: `/v1/trips/${memo.id}/settings`,
      headers: { authorization: owner.authorization },
      payload: { name: "Rome, encore" },
    });
    expect(patched.json<{ dailyCredit: SerializedDailyCredit }>().dailyCredit.usedMs).toBe(90_000);

    // La route qui étendait les limites gratuitement n'existe plus.
    const plan = await harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memo.id}/memory-plan`,
      headers: { authorization: owner.authorization },
      payload: { plan: "extended" },
    });
    expect(plan.statusCode).toBe(404);
  });

  it("un vocal en pause, pas envoyé, ne se lit consommé nulle part ; envoyé, il compte une fois (Hugo, 06/10/2026)", async () => {
    // Hugo : « un vocal enregistré, mis en pause et non envoyé ne consomme pas
    // de crédit ; paramètres du voyage > crédit du jour ne le montre pas
    // consommé ». Le serveur ne connaît que ce qu'il reçoit : tant que l'app
    // n'a rien envoyé, aucune lecture — réglages, accueil, voyage, fil — ne
    // décompte quoi que ce soit.
    const memo = await tripOf(owner.accountId);
    const headers = { authorization: owner.authorization };
    const usedEverywhere = async () => {
      const [settings, home, trip, thread] = await Promise.all([
        harness.app.inject({ method: "GET", url: `/v1/trips/${memo.id}/settings`, headers }),
        harness.app.inject({ method: "GET", url: "/v1/home", headers }),
        harness.app.inject({ method: "GET", url: `/v1/trips/${memo.id}`, headers }),
        harness.app.inject({ method: "GET", url: `/v1/trips/${memo.id}/chat`, headers }),
      ]);
      return [
        settings.json<{ dailyCredit: SerializedDailyCredit }>().dailyCredit.usedMs,
        home.json<{ trips: { id: string; dailyCredit?: SerializedDailyCredit }[] }>().trips.find((t) => t.id === memo.id)
          ?.dailyCredit?.usedMs,
        trip.json<{ trip: { dailyCredit?: SerializedDailyCredit } }>().trip.dailyCredit?.usedMs,
        thread.json<{ dailyCredit: SerializedDailyCredit }>().dailyCredit.usedMs,
      ];
    };

    expect(await usedEverywhere()).toEqual([0, 0, 0, 0]);
    expect(await usedEverywhere()).toEqual([0, 0, 0, 0]);

    // Envoyé — puis renvoyé par la file hors ligne avec le même identifiant.
    const { id } = await speak(memo.id, VOICE_FIXTURES.short);
    await speak(memo.id, VOICE_FIXTURES.short, { id });
    const spent = [SHORT_VOICE_MS, SHORT_VOICE_MS, SHORT_VOICE_MS, SHORT_VOICE_MS];
    expect(await usedEverywhere()).toEqual(spent);
    expect(await usedEverywhere()).toEqual(spent);
  });

  it("l'accueil n'a plus d'étapes, dit qui raconte sans limite, et porte le crédit du voyage en cours", async () => {
    const ongoing = await tripOf(owner.accountId);
    await tripOf(owner.accountId, {
      startDate: new Date(Date.now() - 30 * DAY),
      endDate: new Date(Date.now() - 20 * DAY),
    });
    await spend(ongoing.id, 30_000);

    type HomeJson = {
      traveller: Record<string, unknown>;
      trips: { id: string; dailyCredit?: SerializedDailyCredit }[];
    };
    const read = async () =>
      (
        await harness.app.inject({ method: "GET", url: "/v1/home", headers: { authorization: owner.authorization } })
      ).json<HomeJson>();

    let home = await read();
    expect(home.traveller).not.toHaveProperty("offeredSteps");
    expect(home.traveller).not.toHaveProperty("remainingSteps");
    expect(home.traveller).toMatchObject({ isUnlimited: false, hasSubscribedBefore: false });
    const withCredit = home.trips.filter((trip) => trip.dailyCredit);
    expect(withCredit.map((trip) => trip.id)).toEqual([ongoing.id]);
    expect(withCredit[0]?.dailyCredit).toMatchObject({ usedMs: 30_000, isUnlimited: false });

    await subscribe(owner.accountId);
    home = await read();
    expect(home.traveller).toMatchObject({ isUnlimited: true, hasSubscribedBefore: true });
    expect(home.trips.find((trip) => trip.id === ongoing.id)?.dailyCredit?.isUnlimited).toBe(true);
  });
});

/**
 * **Un tour plus long qu'une journée entière** (03/10/2026) : un vocal de plus
 * de 5:03, un texte de plus de 4 000 caractères. Un pot neuf ne le laisserait
 * pas passer non plus : son refus porte un code à lui, que la file de l'app ne
 * renvoie pas chaque nuit.
 */
describe("un tour plus long qu'une journée", () => {
  it("un vocal de plus de 5:03 est refusé par `daily_credit_too_long`, même sur un pot neuf", async () => {
    const memo = await tripOf(owner.accountId);
    const voice = voiceLasting(7 * 60);
    expect(voice.durationMs).toBeGreaterThan(DAILY_CREDIT_LIMIT_MS + VOICE_TOLERANCE_MS);

    const { id, response } = await speak(memo.id, voice.content, NEW_APP);

    expect(response.statusCode).toBe(429);
    const body = response.json<RefusalJson>();
    expect(body).toMatchObject({ error: "daily_credit_too_long", message: VOICE_TOO_LONG_MESSAGE });
    expect(body.dailyCredit).toMatchObject({ usedMs: 0, remainingMs: DAILY_CREDIT_LIMIT_MS });
    // Rien d'écrit, rien de compté — et pas de « reviens demain » : le pot est plein.
    expect(await harness.prisma.chatMessage.findUnique({ where: { id } })).toBeNull();
    expect(await usage(memo.id)).toBeNull();
    expect(await noticeCount(memo.id)).toBe(0);

    // Un build installé efface le vocal refusé : rien ne partira à l'abonnement.
    const lost = await speak(memo.id, voice.content);
    expect(lost.response.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_too_long",
      message: VOICE_TOO_LONG_LOST_MESSAGE,
    });
  });

  it("un vocal de 5:02 passe encore sur un pot neuf, et le vide", async () => {
    const memo = await tripOf(owner.accountId);
    const voice = voiceLasting(302);
    expect(voice.durationMs).toBeLessThanOrEqual(DAILY_CREDIT_LIMIT_MS + VOICE_TOLERANCE_MS);

    const { response } = await speak(memo.id, voice.content);

    expect(response.statusCode).toBe(201);
    expect(response.json<ReceiptJson>().dailyCredit).toMatchObject({ usedMs: DAILY_CREDIT_LIMIT_MS, remainingMs: 0 });
    expect(await usage(memo.id)).toMatchObject({ voiceMs: voice.durationMs });
  });

  it("un texte de plus de 4 000 caractères aussi ; 4 000 tiennent", async () => {
    const memo = await tripOf(owner.accountId);

    const tooLong = await say(memo.id, "f".repeat(4_001));
    expect(tooLong.response.statusCode).toBe(429);
    expect(tooLong.response.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_too_long",
      message: TEXT_TOO_LONG_MESSAGE,
    });
    expect(await usage(memo.id)).toBeNull();

    const exact = await say(memo.id, "f".repeat(4_000));
    expect(exact.response.statusCode).toBe(201);
    expect(exact.response.json<ReceiptJson>().dailyCredit.remainingMs).toBe(0);
  });

  it("garde son code quand le pot est vide, et MEMO dit « reviens demain »", async () => {
    const memo = await tripOf(owner.accountId);
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS);

    const { response } = await speak(memo.id, voiceLasting(6 * 60).content);

    expect(response.statusCode).toBe(429);
    expect(response.json<RefusalJson>().error).toBe("daily_credit_too_long");
    expect(await noticeCount(memo.id)).toBe(1);
  });

  it("ne concerne pas un abonné", async () => {
    await subscribe(owner.accountId);
    const memo = await tripOf(owner.accountId);

    expect((await speak(memo.id, voiceLasting(7 * 60).content)).response.statusCode).toBe(201);
    expect((await say(memo.id, "g".repeat(5_000))).response.statusCode).toBe(201);
  });

  it("la route ancienne le refuse de même, avant de stocker", async () => {
    const memo = await tripOf(owner.accountId);
    const { payload, contentType } = multipartBody(
      {},
      { field: "file", filename: "vocal.m4a", contentType: "audio/mp4", content: voiceLasting(7 * 60).content },
    );
    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/memos/${memo.id}/entries`,
      // L'app de ce lot aussi : l'écran du carnet ne garde pas le vocal refusé.
      headers: { authorization: owner.authorization, "content-type": contentType, "x-time-zone": PARIS },
      payload,
    });

    expect(response.statusCode).toBe(429);
    expect(response.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_too_long",
      message: VOICE_TOO_LONG_LOST_MESSAGE,
    });
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
  });
});

describe("une correction à la main", () => {
  async function entryOf(memoId: string, transcript: string) {
    return harness.prisma.entry.create({
      data: { memoId, kind: "text", status: "ready", transcript, capturedAt: new Date() },
    });
  }

  function patch(entryId: string, editedText: string) {
    return harness.app.inject({
      method: "PATCH",
      url: `/v1/entries/${entryId}`,
      headers: { authorization: owner.authorization },
      payload: { editedText },
    });
  }

  it("refusée faute de crédit dit ce qui reste, sans « épuisé » ni « partira demain »", async () => {
    const memo = await tripOf(owner.accountId);
    const entry = await entryOf(memo.id, "h".repeat(10));
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - 120_000);

    // 2 000 caractères ajoutés : 2:30, quand il reste 2:00.
    const response = await patch(entry.id, "h".repeat(2_010));

    expect(response.statusCode).toBe(429);
    expect(response.json<RefusalJson>()).toMatchObject({
      error: "daily_credit_exhausted",
      message: CORRECTION_SHORT_MESSAGE,
    });
    expect(response.json<RefusalJson>().dailyCredit.remainingMs).toBe(120_000);
    expect((await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } })).editedText).toBeNull();
  });

  it("envoyée deux fois au même instant ne paie qu'une fois ce qu'elle ajoute", async () => {
    const memo = await tripOf(owner.accountId);
    const entry = await entryOf(memo.id, "i".repeat(10));
    const edited = "i".repeat(1_010);

    const responses = await Promise.all([patch(entry.id, edited), patch(entry.id, edited)]);

    expect(responses.map((response) => response.statusCode)).toEqual([200, 200]);
    // La croissance se mesure sous le verrou : la seconde ne trouve plus rien à ajouter.
    expect(await usage(memo.id)).toMatchObject({ textCharacters: 1_000, usedMs: 1_000 * TEXT_MS_PER_CHARACTER });
  });
});

/**
 * **Le filet du transcripteur** (03/10/2026) : une durée de conteneur peut
 * encore mentir (trames tassées, voix accélérée) ; un texte bien plus long
 * que le vocal mesuré se décompte quand même, sans refuser le souvenir.
 */
describe("le filet du transcripteur", () => {
  const LONG_TRANSCRIPT = "j".repeat(1_000); // 75 s de crédit

  async function withTranscript<T>(text: string, run: () => Promise<T>): Promise<T> {
    const original = harness.context.transcriber;
    harness.context.transcriber = new FakeTranscriber([text]);
    try {
      return await run();
    } finally {
      harness.context.transcriber = original;
    }
  }

  it("décompte l'écart d'un texte bien plus long que le vocal mesuré", async () => {
    const memo = await tripOf(owner.accountId);

    const { response } = await withTranscript(LONG_TRANSCRIPT, () => speak(memo.id, VOICE_FIXTURES.short));

    expect(response.statusCode).toBe(201);
    // Le vocal (2,1 s) au décompte, puis l'écart : 75 s en tout, comme un texte.
    expect(await usage(memo.id)).toMatchObject({
      usedMs: 1_000 * TEXT_MS_PER_CHARACTER,
      voiceMs: SHORT_VOICE_MS,
    });
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    expect(entry).toMatchObject({ status: "ready", transcript: LONG_TRANSCRIPT });
  });

  it("laisse passer un texte vraisemblable, et ne compte rien à un abonné", async () => {
    const memo = await tripOf(owner.accountId);
    // Deux fois la durée mesurée, ou un écart sous le plancher : rien.
    const plausible = "k".repeat(Math.floor((2 * SHORT_VOICE_MS) / TEXT_MS_PER_CHARACTER));
    expect(plausible.length * TEXT_MS_PER_CHARACTER - SHORT_VOICE_MS).toBeLessThan(TRANSCRIPT_OVERRUN_FLOOR_MS);
    await withTranscript(plausible, () => speak(memo.id, VOICE_FIXTURES.short));
    expect((await usage(memo.id))?.usedMs).toBe(SHORT_VOICE_MS);

    await subscribe(owner.accountId);
    await withTranscript(LONG_TRANSCRIPT, () => speak(memo.id, VOICE_FIXTURES.short));
    expect((await usage(memo.id))?.usedMs).toBe(SHORT_VOICE_MS);
  });
});

describe("un voyage ouvert", () => {
  it("porte le crédit du jour quand il est en cours, comme l'accueil", async () => {
    const ongoing = await tripOf(owner.accountId);
    const past = await tripOf(owner.accountId, {
      startDate: new Date(Date.now() - 30 * DAY),
      endDate: new Date(Date.now() - 20 * DAY),
    });
    await spend(ongoing.id, 45_000);

    const read = async (memoId: string) =>
      (
        await harness.app.inject({
          method: "GET",
          url: `/v1/trips/${memoId}`,
          headers: { authorization: owner.authorization },
        })
      ).json<{ trip: { dailyCredit?: SerializedDailyCredit } }>();

    expect((await read(ongoing.id)).trip.dailyCredit).toMatchObject({
      isUnlimited: false,
      usedMs: 45_000,
      remainingMs: DAILY_CREDIT_LIMIT_MS - 45_000,
      day: today(),
    });
    expect((await read(past.id)).trip).not.toHaveProperty("dailyCredit");

    await subscribe(owner.accountId);
    expect((await read(ongoing.id)).trip.dailyCredit?.isUnlimited).toBe(true);
  });
});

/**
 * Le répondeur simulé qui garde ce qu'on lui donne et **propose toujours
 * l'offre** en répondant à une question : c'est le code qui dit si elle se
 * pose (`callsToActionAllowed`, puis `validateReply`).
 */
class OfferingResponder extends FakeResponder {
  inputs: ConversationInput[] = [];

  override async reply(input: ConversationInput): Promise<ConversationReply> {
    this.inputs.push(input);
    const reply = await super.reply(input);
    return validateReply({ ...reply, disposition: "command", callToActionId: "subscribe" }, input);
  }
}

/**
 * **Ce que MEMO pose sous sa réponse** (03/10/2026) — la recherche de la
 * bulle « reviens demain » et du dernier bouton dans `jobs/converse.ts`,
 * jouée de bout en bout : la route écrit le tour, le job répond (file
 * synchrone en test), et l'on lit ce que le répondeur a reçu et ce qui est
 * rangé en base.
 */
describe("le bouton sous la réponse de MEMO", () => {
  let responder: OfferingResponder;
  let original: TestHarness["context"]["responder"];

  beforeEach(() => {
    original = harness.context.responder;
    responder = new OfferingResponder();
    harness.context.responder = responder;
  });

  afterEach(() => {
    harness.context.responder = original;
  });

  /** Les bulles de MEMO qui répondent à un tour, dans l'ordre. */
  async function repliesTo(messageId: string) {
    return harness.prisma.chatMessage.findMany({
      where: { replyToId: messageId, author: "memo", kind: "text" },
      orderBy: { seq: "asc" },
    });
  }

  function callToActionOf(payload: unknown): unknown {
    return (payload as { callToAction?: unknown } | null)?.callToAction;
  }

  it("sous la bulle « reviens demain » posée par ce tour, pas de seconde offre — et MEMO l'a lue en dernier", async () => {
    const memo = await tripOf(owner.accountId);
    const question = "Combien coûte l’abonnement ?";
    // Le reste couvre exactement la question : ce tour vide le pot.
    await spend(memo.id, DAILY_CREDIT_LIMIT_MS - countCharacters(question) * TEXT_MS_PER_CHARACTER);

    const { id, response } = await say(memo.id, question);

    expect(response.statusCode).toBe(201);
    expect(notices(response.json<ReceiptJson>().messages)).toHaveLength(1);

    const input = responder.inputs.at(-1);
    expect(input?.message.id).toBe(id);
    expect(input?.allows.callsToAction).not.toContain("subscribe");
    expect(input?.history.at(-1)?.text).toBe(DAILY_CREDIT_EXHAUSTED_MESSAGE);

    const replies = await repliesTo(id);
    expect(replies.length).toBeGreaterThan(0);
    // C'est bien le répondeur qui a parlé, pas le repli.
    expect(replies.at(-1)?.model).toBe("fake");
    for (const reply of replies) expect(callToActionOf(reply.payload)).toBeUndefined();
  });

  it("ne pose pas deux fois de suite le même bouton", async () => {
    const memo = await tripOf(owner.accountId);

    const first = await say(memo.id, "Combien coûte l’abonnement ?");
    expect(first.response.statusCode).toBe(201);
    expect(responder.inputs.at(-1)?.allows.callsToAction).toContain("subscribe");
    expect(callToActionOf((await repliesTo(first.id)).at(-1)?.payload)).toEqual({ id: "subscribe" });

    const second = await say(memo.id, "Et c’est illimité pour de vrai ?");
    expect(second.response.statusCode).toBe(201);
    expect(responder.inputs.at(-1)?.allows.callsToAction).not.toContain("subscribe");
    const replies = await repliesTo(second.id);
    expect(replies.at(-1)?.model).toBe("fake");
    for (const reply of replies) expect(callToActionOf(reply.payload)).toBeUndefined();
  });

  it("ne glisse pas dans le fil d'un abonné la bulle « reviens demain » d'un tour plus récent", async () => {
    const memo = await tripOf(owner.accountId);
    const clara = await registerAccount(harness.app, "clara@memobook.app");
    await harness.prisma.memoMember.create({
      data: { memoId: memo.id, accountId: clara.accountId, status: "active", acceptedAt: new Date() },
    });
    await subscribe(clara.accountId);

    // Hugo (non abonné) puis Clara (abonnée) ont parlé ; un tour plus récent
    // de Hugo a vidé le pot, et la route a posé la bulle derrière eux deux.
    const turnOf = (accountId: string, text: string) =>
      harness.prisma.chatMessage.create({
        data: { memoId: memo.id, author: "traveller", kind: "text", accountId, text },
      });
    const hugo = await turnOf(owner.accountId, "Tu te souviens de la glace pistache place Navone ?");
    const theirs = await turnOf(clara.accountId, "Tu te souviens du resto d’hier soir ?");
    await harness.prisma.chatMessage.create({
      data: {
        memoId: memo.id,
        author: "memo",
        kind: "text",
        text: DAILY_CREDIT_EXHAUSTED_MESSAGE,
        model: "scripted",
        payload: {
          callToAction: { id: "daily_credit_subscribe" },
          notice: `daily_credit_exhausted:${today()}`,
          audience: "limited",
        },
      },
    });

    // Hugo la voit : MEMO lui répond après elle.
    await converseTurn(harness.context, { messageId: hugo.id });
    expect(responder.inputs.at(-1)?.history.at(-1)?.text).toBe(DAILY_CREDIT_EXHAUSTED_MESSAGE);

    // Clara ne la voit pas : le répondeur ne la lit pas non plus.
    await converseTurn(harness.context, { messageId: theirs.id });
    const input = responder.inputs.at(-1);
    expect(input?.message.id).toBe(theirs.id);
    expect(input?.traveller.isUnlimited).toBe(true);
    expect(input?.history.map((turn) => turn.text)).not.toContain(DAILY_CREDIT_EXHAUSTED_MESSAGE);
  });
});

describe("le tour de MEMO après un vocal", () => {
  let responder: OfferingResponder;
  let original: TestHarness["context"]["responder"];

  beforeEach(() => {
    original = harness.context.responder;
    responder = new OfferingResponder();
    harness.context.responder = responder;
  });

  afterEach(() => {
    harness.context.responder = original;
  });

  async function voiceTurn(memoId: string, entry: { transcript: string; redactionStatus?: "pending" | "ready" }) {
    const created = await harness.prisma.entry.create({
      data: {
        memoId,
        kind: "audio",
        status: "ready",
        transcript: entry.transcript,
        redactionStatus: entry.redactionStatus ?? "ready",
        capturedAt: new Date(),
      },
    });
    return harness.prisma.chatMessage.create({
      data: { memoId, author: "traveller", kind: "voice", accountId: owner.accountId, entryId: created.id },
    });
  }

  it("dit qu'il n'a rien entendu quand la transcription est vide, au lieu de se taire", async () => {
    const memo = await tripOf(owner.accountId);
    const message = await voiceTurn(memo.id, { transcript: "   " });

    await converseTurn(harness.context, { messageId: message.id });

    const input = responder.inputs.at(-1);
    expect(input?.message.id).toBe(message.id);
    expect(input?.message.transcriptFailed).toBe(true);
  });

  it("republie la rédaction restée en attente quand le tour est rejoué après sa réponse", async () => {
    // La transaction du tour est passée, la publication de la rédaction non :
    // pg-boss rejoue le job, qui trouve `repliedAt` posé.
    const memo = await tripOf(owner.accountId);
    const message = await voiceTurn(memo.id, { transcript: "Le Colisée au lever du jour.", redactionStatus: "pending" });
    await harness.prisma.chatMessage.update({ where: { id: message.id }, data: { repliedAt: new Date() } });
    const publish = vi.spyOn(harness.context.queue, "publish").mockResolvedValue();

    await converseTurn(harness.context, { messageId: message.id });

    expect(publish).toHaveBeenCalledWith(JOB_NAMES.redact, { entryId: message.entryId });
    publish.mockRestore();
  });
});
