import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { FakeResponder } from "../src/services/conversation.js";
import {
  OPENING_TEXT,
  PRECISION_NOTED,
  SUGGESTIONS,
  VALIDATION_QUESTION,
  PHOTOS_VALIDATED,
  photosToValidate,
  photosWanted,
  validationQuestionFor,
} from "../src/services/conversationCopy.js";
import { FakeRedactor, type RedactionInput, type RedactionResult } from "../src/services/redaction.js";
import { photoBudgetFor } from "../src/services/photoBudget.js";
import {
  CONTEXT_COMPLETE,
  CONTEXT_INVITATION,
  CONTEXT_NOTED,
  CONTEXT_SKIPPED,
  questionFor,
  EMPTY_TRIP_CONTEXT,
} from "../src/services/tripContext.js";
import { FakeTranscriber } from "../src/services/transcription.js";
import {
  createHarness,
  multipartBody,
  registerAccount,
  resetDatabase,
  type TestHarness,
} from "./helpers.js";

/**
 * La conversation avec MEMO, de bout en bout — `docs/conversation.md`.
 *
 * Avec la file en ligne, le job `converse` (et, pour un vocal, `transcribe`
 * puis `redact`) se termine **avant** que la requête ne réponde : les
 * assertions portent sur l'état final du fil, pas sur un délai.
 */

const TRANSCRIPT = "On est arrivés à Bogotá ce matin, la ville est perchée dans les nuages.";

interface ChatMessageJson {
  id: string;
  seq: number;
  author: "memo" | "traveller";
  authorName: string | null;
  authorInitials: string | null;
  authorAvatarUrl: string | null;
  body:
    | { kind: "text"; text: string }
    | { kind: "voice"; voice: { id: string; duration: number; levels: number[]; remoteUrl: string | null } }
    | { kind: "photos"; photos: { id: string; remoteUrl: string }[] }
    | {
        kind: "transcript";
        transcript: {
          title: string;
          heading: string | null;
          text: string | null;
          entryId: string;
          phase: string;
          isValidated: boolean;
          footnote: string | null;
        };
      };
  sentAt: string;
  stepId: string | null;
  disposition: string | null;
  pauseMilliseconds: number | null;
}

interface ChatThreadJson {
  id: string;
  title: string;
  greeting: { title: string; message: string };
  preview: { memoryCount: number; pageCount: number; isOpenable: boolean } | null;
  context: {
    tripId: string;
    travellerFirstName: string | null;
    travellerInitials: string | null;
    travellerAvatarUrl: string | null;
    memberCount: number;
    prompt: string | null;
  };
  messages: ChatMessageJson[];
  suggestions: { id: string; label: string; symbol: string | null; intent: string }[];
  turn: { status: "idle" } | { status: "replying"; messageId: string };
  canClear: boolean;
  tripContext: {
    status: string;
    filledCount: number;
    requiredCount: number;
    items: { key: string; label: string; value: string | null; isRequired: boolean; isFilled: boolean }[];
  } | null;
  now: string;
}

/**
 * Le faux écrivain, qui garde ce qu'on lui a donné et peut douter sur
 * commande : ce que le job sait de l'étape, et ce que MEMO fait d'un doute.
 */
class ScriptedRedactor extends FakeRedactor {
  doubts: string[] = [];
  inputs: RedactionInput[] = [];

  override async redact(input: RedactionInput): Promise<RedactionResult> {
    this.inputs.push(input);
    return { ...(await super.redact(input)), doubts: this.doubts };
  }
}

let harness: TestHarness;
let responder: FakeResponder;
let redactor: ScriptedRedactor;
let transcriber: FakeTranscriber;
let owner: { accountId: string; authorization: string };

beforeAll(async () => {
  responder = new FakeResponder();
  redactor = new ScriptedRedactor();
  transcriber = new FakeTranscriber([TRANSCRIPT, TRANSCRIPT, TRANSCRIPT]);
  harness = await createHarness({ transcriber, responder, redactor });
});

afterAll(async () => {
  await harness.close();
});

let accessCodeCounter = 0;

beforeEach(async () => {
  await resetDatabase(harness.prisma);
  owner = await registerAccount(harness.app, "hugo@memobook.app");
  responder.calls = 0;
  redactor.doubts = [];
  redactor.inputs = [];
});

async function seedTrip(ownerId: string) {
  accessCodeCounter += 1;
  return harness.prisma.memo.create({
    data: {
      ownerAccountId: ownerId,
      title: "Rome 2026",
      accessCode: `CHT${String(accessCodeCounter).padStart(3, "0")}`,
      stage: "ongoing",
      destinationName: "Italie",
      destinationCountryCode: "IT",
      destinationCity: "Rome",
    },
  });
}

async function readThread(memoId: string, authorization = owner.authorization, since?: string) {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}/chat${since ? `?since=${encodeURIComponent(since)}` : ""}`,
    headers: { authorization },
  });
  expect(response.statusCode).toBe(200);
  return response.json<ChatThreadJson>();
}

async function say(
  memoId: string,
  text: string,
  extra: { id?: string; suggestionId?: string; entryId?: string; authorization?: string } = {},
) {
  const id = extra.id ?? randomUUID();
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: extra.authorization ?? owner.authorization },
    payload: {
      id,
      kind: "text",
      text,
      ...(extra.suggestionId ? { suggestionId: extra.suggestionId } : {}),
      ...(extra.entryId ? { entryId: extra.entryId } : {}),
    },
  });
  return { id, response };
}

async function sendVoice(memoId: string, id = randomUUID()) {
  const { payload, contentType } = multipartBody(
    {
      id,
      capturedAt: "2026-09-21T09:00:00.000Z",
      placeLabel: "Trastevere, Rome",
      durationSeconds: "37",
      levels: JSON.stringify([0.2, 0.8, 0.5]),
    },
    { field: "file", filename: "memo.m4a", contentType: "audio/mp4", content: Buffer.from("audio") },
  );
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization, "content-type": contentType },
    payload,
  });
  return { id, response };
}

function multipartPhotos(id: string, count: number) {
  const boundary = `----memobookphotos${Date.now()}`;
  const parts: Buffer[] = [
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="id"\r\n\r\n${id}\r\n`),
  ];
  for (let index = 0; index < count; index += 1) {
    parts.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="photo-${index}.jpg"\r\n` +
          `Content-Type: image/jpeg\r\n\r\n`,
      ),
      Buffer.from(`jpeg-${index}`),
      Buffer.from("\r\n"),
    );
  }
  parts.push(Buffer.from(`--${boundary}--\r\n`));
  return { payload: Buffer.concat(parts), contentType: `multipart/form-data; boundary=${boundary}` };
}

async function tellFromHome(memoId: string, transcript: string, capturedAt: string) {
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/memos/${memoId}/entries`,
    headers: { authorization: owner.authorization },
    payload: { kind: "text", transcript, capturedAt },
  });
  expect(response.statusCode).toBe(201);
  return response.json<{ id: string }>().id;
}

const memoBubbles = (thread: ChatThreadJson) =>
  thread.messages.filter((message) => message.author === "memo" && message.body.kind === "text");

describe("lire le fil", () => {
  it("rend un fil vide avec les puces d'ouverture, et dit qui peut l'effacer", async () => {
    const memo = await seedTrip(owner.accountId);
    const thread = await readThread(memo.id);

    expect(thread.messages).toEqual([]);
    // Une seule puce : le contexte du voyage d'abord (Paul, 28/09/2026).
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["context"]);
    expect(thread.suggestions[0]?.label).toBe(SUGGESTIONS.context.label);
    expect(thread.tripContext).toBeNull();
    expect(thread.turn).toEqual({ status: "idle" });
    expect(thread.canClear).toBe(true);
    expect(thread.preview).toBeNull();
    expect(thread.greeting.title).toBe("Nouveau voyage à Rome ! 🇮🇹");
    expect(thread.context.travellerFirstName).toBe("Hugo");
    expect(thread.context.memberCount).toBe(1);
  });

  it("reconstruit les souvenirs racontés hors du chat, une seule fois", async () => {
    const memo = await seedTrip(owner.accountId);
    await tellFromHome(memo.id, "Deuxième journée à Monserrate.", "2026-09-20T09:00:00.000Z");
    await tellFromHome(memo.id, "Premier jour à Bogotá.", "2026-09-19T09:00:00.000Z");

    const thread = await readThread(memo.id);
    const kinds = thread.messages.map((message) => `${message.author}:${message.body.kind}`);
    expect(kinds).toEqual([
      "memo:text",
      "traveller:text",
      "memo:transcript",
      "traveller:text",
      "memo:transcript",
    ]);
    expect(thread.messages[0]?.body).toEqual({ kind: "text", text: OPENING_TEXT });
    // Dans l'ordre des dates, pas de l'écriture.
    expect(thread.messages[1]?.body).toEqual({ kind: "text", text: "Premier jour à Bogotá." });
    expect(thread.messages[1]?.disposition).toBe("memory");
    expect(thread.preview).toEqual({ memoryCount: 2, pageCount: 4, isOpenable: false });

    const again = await readThread(memo.id);
    expect(again.messages).toHaveLength(5);
  });

  it("reconstruit une seule fois, même sous deux lectures simultanées", async () => {
    const memo = await seedTrip(owner.accountId);
    await tellFromHome(memo.id, "Un souvenir raconté depuis l'accueil.", "2026-09-19T09:00:00.000Z");

    // L'app relit le fil en revenant des réglages pendant que le sondage
    // passe : deux lectures au même instant, un seul souvenir dans le fil.
    const [first, second] = await Promise.all([readThread(memo.id), readThread(memo.id)]);
    expect(first.messages).toHaveLength(3);
    expect(second.messages).toHaveLength(3);
    expect(await harness.prisma.chatMessage.count({ where: { memoId: memo.id } })).toBe(3);
  });
});

describe("parler à MEMO", () => {
  it("écrit le message tout de suite, puis MEMO répond et crée le souvenir", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id, response } = await say(
      memo.id,
      "Ce matin on est partis tôt pour éviter la chaleur, on a marché jusqu'au marché de Testaccio.",
    );

    expect(response.statusCode).toBe(201);
    const receipt = response.json<{ messages: ChatMessageJson[]; turn: { status: string } }>();
    expect(receipt.turn).toEqual({ status: "replying", messageId: id });
    expect(receipt.messages.map((message) => message.author)).toEqual(["memo", "traveller"]);
    expect(receipt.messages[1]?.id).toBe(id);

    const thread = await readThread(memo.id);
    const mine = thread.messages.find((message) => message.id === id);
    expect(mine?.disposition).toBe("memory");
    expect(thread.turn).toEqual({ status: "idle" });

    // Une seule bulle après un souvenir : « Il te convient ? », posée quand le
    // texte est rédigé — ni reformulation, ni question sur le lieu.
    const replies = memoBubbles(thread).filter((message) => message.seq > (mine?.seq ?? 0));
    expect(replies.map((message) => message.body)).toEqual([{ kind: "text", text: VALIDATION_QUESTION }]);
    expect(replies.every((message) => (message.pauseMilliseconds ?? 0) >= 450)).toBe(true);
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["accept", "edit-hand", "edit-voice"]);

    // Le souvenir existe, rédigé, avec sa fiche dans le fil.
    const card = thread.messages.find((message) => message.body.kind === "transcript");
    expect(card?.body.kind === "transcript" && card.body.transcript.phase).toBe("ready");
    const entries = await harness.prisma.entry.findMany({ where: { memoId: memo.id } });
    expect(entries).toHaveLength(1);
    expect(entries[0]?.redactionStatus).toBe("ready");

    // La relance du voyage est écrite.
    const updated = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memo.id } });
    expect(updated.prompt).toContain("Rome");
    expect(responder.calls).toBe(1);
  });

  it("cite dans la question ce que l'écrivain n'a pas compris", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.doubts = ["je tarbé"];
    const { id } = await say(memo.id, "Le soir on a fini en boîte avec des Australiens totalement je tarbé.");

    const thread = await readThread(memo.id);
    const mine = thread.messages.find((message) => message.id === id);
    const replies = memoBubbles(thread).filter((message) => message.seq > (mine?.seq ?? 0));
    // Toujours une seule bulle : le doute s'y dit, il n'en ajoute pas une.
    expect(replies.map((message) => message.body)).toEqual([
      { kind: "text", text: validationQuestionFor(["je tarbé"]) },
    ]);
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["accept", "edit-hand", "edit-voice"]);
  });

  it("dit à l'écrivain qui raconte, et ce que le carnet sait du voyage", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "Ce matin on est partis tôt pour éviter la chaleur et on a marché longtemps.");

    const input = redactor.inputs.at(-1);
    expect(input?.narrator).toEqual({ firstName: "Hugo", companions: [] });
    expect(input?.memo.destination).toBe("Rome, Italie");
    expect(input?.earlier).toEqual({ titles: [], funFacts: [] });
  });

  it("rattache une précision au souvenir en cours, et la rédaction la relit", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "Ce matin on est partis tôt pour éviter la chaleur et on a marché longtemps.");
    const { id, response } = await say(memo.id, "C'était avec Clara.");
    expect(response.statusCode).toBe(201);

    const thread = await readThread(memo.id);
    const precision = thread.messages.find((message) => message.id === id);
    expect(precision?.disposition).toBe("context");

    const entries = await harness.prisma.entry.findMany({ where: { memoId: memo.id } });
    expect(entries).toHaveLength(1);
    expect(entries[0]?.redactedText).toContain("C'était avec Clara.");

    // Un accusé, puis la question revient avec le texte réécrit.
    const after = await readThread(memo.id);
    const replies = memoBubbles(after).filter((message) => message.seq > (precision?.seq ?? 0));
    expect(replies.map((message) => message.body)).toEqual([
      { kind: "text", text: PRECISION_NOTED },
      { kind: "text", text: VALIDATION_QUESTION },
    ]);
  });

  it("reçoit un vocal : la fiche tombe tout de suite, puis passe prête", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id, response } = await sendVoice(memo.id);
    expect(response.statusCode).toBe(201);

    const receipt = response.json<{ messages: ChatMessageJson[] }>();
    expect(receipt.messages.map((message) => message.body.kind)).toEqual(["text", "voice", "transcript"]);

    const thread = await readThread(memo.id);
    const voice = thread.messages.find((message) => message.id === id);
    expect(voice?.body.kind === "voice" && voice.body.voice.levels).toEqual([0.2, 0.8, 0.5]);
    // La durée mesurée par la transcription (12 s pour `FakeTranscriber`) fait
    // foi sur celle que l'app déclare — comme pour `POST /v1/memos/:id/entries`.
    expect(voice?.body.kind === "voice" && voice.body.voice.duration).toBe(12);
    expect(voice?.sentAt).toBe("2026-09-21T09:00:00.000Z");

    const card = thread.messages.find((message) => message.body.kind === "transcript");
    expect(card?.body.kind === "transcript" && card.body.transcript.phase).toBe("ready");
    expect(card?.body.kind === "transcript" && card.body.transcript.text).toContain("Bogotá");
    // La première fiche du fil est l'étape 1, et le récit porte son titre.
    expect(card?.body.kind === "transcript" && card.body.transcript.title).toBe("Retranscription étape 1");
    // Le transcripteur a reçu les noms que le carnet connaît : qui raconte, et où.
    expect(transcriber.hints.at(-1)).toBe("Récit de voyage de Hugo (Rome).");
    expect(card?.body.kind === "transcript" && card.body.transcript.heading).toBeTruthy();
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["accept", "edit-hand", "edit-voice"]);
  });

  it("reçoit des photos : un souvenir par image, une seule bulle", async () => {
    const memo = await seedTrip(owner.accountId);
    const id = randomUUID();
    const { payload, contentType } = multipartPhotos(id, 2);
    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memo.id}/chat`,
      headers: { authorization: owner.authorization, "content-type": contentType },
      payload,
    });
    expect(response.statusCode).toBe(201);

    const thread = await readThread(memo.id);
    const photos = thread.messages.find((message) => message.id === id);
    expect(photos?.body.kind === "photos" && photos.body.photos).toHaveLength(2);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "photo" } })).toBe(2);
    // MEMO demande de valider les photos, et dit que ça crée la page.
    expect(memoBubbles(thread).at(-1)?.body).toEqual({ kind: "text", text: photosToValidate(2) });
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos-ok", "photos-more"]);

    // « Je valide mes photos » : les photos sont validées, le carnet se recompose.
    const { response: validation } = await say(memo.id, SUGGESTIONS["photos-ok"].label, {
      suggestionId: "photos-ok",
    });
    expect(validation.statusCode).toBe(201);
    const after = await readThread(memo.id);
    expect(memoBubbles(after).at(-1)?.body).toEqual({ kind: "text", text: PHOTOS_VALIDATED });
    expect(after.suggestions.map((suggestion) => suggestion.id)).toEqual(["preview", "dictate", "write"]);
    expect(
      await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "photo", validatedAt: null } }),
    ).toBe(0);
    expect(await harness.prisma.render.count({ where: { memoId: memo.id } })).toBe(1);
  });

  it("ne double pas un message renvoyé avec le même identifiant", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id, response } = await say(memo.id, "Une longue journée de marche dans les ruelles de Rome.");
    expect(response.statusCode).toBe(201);
    const { response: again } = await say(memo.id, "Une longue journée de marche dans les ruelles de Rome.", { id });
    expect(again.statusCode).toBe(200);

    expect(await harness.prisma.chatMessage.count({ where: { id } })).toBe(1);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);
  });

  it("refuse un message vide et un voyage qu'on ne voit pas", async () => {
    const memo = await seedTrip(owner.accountId);
    const { response } = await say(memo.id, "   ");
    expect(response.statusCode).toBe(400);

    const stranger = await registerAccount(harness.app, "inconnu@memobook.app");
    const { response: refused } = await say(memo.id, "Bonjour", { authorization: stranger.authorization });
    expect(refused.statusCode).toBe(404);
  });
});

describe("le contexte du voyage", () => {
  const lastMemoText = (thread: ChatThreadJson) => {
    const bubbles = memoBubbles(thread);
    const last = bubbles[bubbles.length - 1];
    return last?.body.kind === "text" ? last.body.text : null;
  };
  const chipIds = (thread: ChatThreadJson) => thread.suggestions.map((suggestion) => suggestion.id);

  it("se recueille ligne à ligne, sans créer de souvenir ni coûter d'étape", async () => {
    const memo = await seedTrip(owner.accountId);

    await say(memo.id, SUGGESTIONS.context.label, { suggestionId: "context" });
    let thread = await readThread(memo.id);
    expect(lastMemoText(thread)).toBe(CONTEXT_INVITATION);
    // Sous l'invitation, rien : le composeur suffit, et « Plus tard » n'y a pas sa place.
    expect(chipIds(thread)).toEqual([]);
    expect(thread.tripContext).toMatchObject({ status: "gathering", filledCount: 0, requiredCount: 5 });

    // La description libre : le repli la garde et compte les voyageurs.
    await say(memo.id, "On part à 3 en Malaisie, trois semaines.");
    thread = await readThread(memo.id);
    // Sans modèle, l'accusé et la question tiennent dans une seule bulle.
    expect(lastMemoText(thread)).toBe(`${CONTEXT_NOTED} ${questionFor("departureCountry", EMPTY_TRIP_CONTEXT)}`);
    expect(chipIds(thread)).toEqual(["context-later"]);

    await say(memo.id, "De France");
    thread = await readThread(memo.id);
    expect(lastMemoText(thread)).toBe(`${CONTEXT_NOTED} Tu me donnes le prénom de chacun de tes compagnons de route ?`);

    await say(memo.id, "Clara et Léo");
    await say(memo.id, "Du 12 au 26 septembre 2026");
    await say(memo.id, "Un road trip en van");
    thread = await readThread(memo.id);
    expect(lastMemoText(thread)).toBe(`${CONTEXT_NOTED} ${CONTEXT_COMPLETE}`);
    expect(chipIds(thread)).toEqual(["dictate", "write", "photos"]);
    expect(thread.tripContext).toMatchObject({ status: "complete", filledCount: 5 });
    expect(thread.tripContext?.items.find((item) => item.key === "companions")?.value).toBe("Clara, Léo");

    // Sept tours, aucun souvenir : le contexte n'entre pas dans le carnet.
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
    const travellerTurns = thread.messages.filter((message) => message.author === "traveller");
    expect(travellerTurns.slice(1).every((message) => message.disposition === "trip_context")).toBe(true);

    // Et ensuite, on raconte pour de vrai.
    await say(memo.id, "Premier jour à Kuala Lumpur, on a grimpé aux tours Petronas au lever du soleil.");
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);

    // MEMO et l'écrivain le relisent : il est en base, au propre.
    const stored = await harness.prisma.memo.findUniqueOrThrow({ where: { id: memo.id } });
    expect(stored.tripContext).toMatchObject({
      departureCountry: "France",
      travellerCount: 3,
      dates: "Du 12 au 26 septembre 2026",
      tripType: "Un road trip en van",
    });
  });

  it("ne consomme aucune étape offerte, même au-delà des trois", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, SUGGESTIONS.context.label, { suggestionId: "context" });
    for (const text of ["Je pars seul", "Je pars de France", "En octobre", "Un trek", "Et j'adore marcher"]) {
      const { response } = await say(memo.id, text);
      expect(response.statusCode).toBe(201);
    }
    const account = await harness.prisma.account.findUniqueOrThrow({ where: { id: owner.accountId } });
    expect(account.remainingSteps).toBe(3);
  });

  it("se referme sans insister sur « Je compléterai plus tard »", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, SUGGESTIONS.context.label, { suggestionId: "context" });
    await say(memo.id, "On est deux");
    await say(memo.id, SUGGESTIONS["context-later"].label, { suggestionId: "context-later" });

    const thread = await readThread(memo.id);
    expect(lastMemoText(thread)).toBe(CONTEXT_SKIPPED);
    expect(thread.tripContext?.status).toBe("skipped");

    await say(memo.id, "Première soirée à Penang, des nouilles au marché de nuit.");
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);
  });

  it("écoute un vocal du contexte sans en faire un souvenir, et en sert le fichier", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, SUGGESTIONS.context.label, { suggestionId: "context" });
    const { id, response } = await sendVoice(memo.id);
    expect(response.statusCode).toBe(201);
    // Ni fiche de retranscription, ni souvenir.
    expect(response.json<{ messages: ChatMessageJson[] }>().messages.map((message) => message.body.kind)).toEqual([
      "voice",
    ]);

    const thread = await readThread(memo.id);
    const voice = thread.messages.find((message) => message.id === id);
    expect(voice?.disposition).toBe("trip_context");
    expect(thread.messages.some((message) => message.body.kind === "transcript")).toBe(false);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);

    const url = voice?.body.kind === "voice" ? voice.body.voice.remoteUrl : null;
    expect(url).toContain(`/v1/chat-messages/${id}/media`);
    const media = await harness.app.inject({
      method: "GET",
      url: new URL(url!).pathname,
      headers: { authorization: owner.authorization },
    });
    expect(media.statusCode).toBe(200);
    expect(media.body).toBe("audio");

    // Ce qu'il a dit est gardé sur le message, pour l'historique de MEMO.
    const stored = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
    expect(stored.text).toBeTruthy();
  });

  it("n'est plus proposé à l'ouverture une fois posé", async () => {
    const memo = await seedTrip(owner.accountId);
    await harness.prisma.memo.update({
      where: { id: memo.id },
      data: { tripContext: { status: "complete", departureCountry: "France" } },
    });
    const thread = await readThread(memo.id);
    expect(chipIds(thread)).toEqual(["start", "photos", "dictate"]);
  });
});

describe("valider", () => {
  it("« Ça me convient » valide le souvenir et confirme une étape offerte, une seule fois", async () => {
    const memo = await seedTrip(owner.accountId);
    await sendVoice(memo.id);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    const callsBefore = responder.calls;

    const { response } = await say(memo.id, SUGGESTIONS.accept.label, {
      suggestionId: "accept",
      entryId: entry.id,
    });
    expect(response.statusCode).toBe(201);

    const validated = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(validated.validatedAt).not.toBeNull();
    let account = await harness.prisma.account.findUniqueOrThrow({ where: { id: owner.accountId } });
    expect(account.remainingSteps).toBe(2);

    const thread = await readThread(memo.id);
    const card = thread.messages.find((message) => message.body.kind === "transcript");
    expect(card?.body.kind === "transcript" && card.body.transcript.isValidated).toBe(true);
    // Validé : MEMO demande le nombre exact de photos qui remplit l'étape.
    const budget = photoBudgetFor((validated.editedText ?? validated.redactedText ?? "").trim().length);
    expect(memoBubbles(thread).slice(-2).map((message) => message.body)).toEqual([
      { kind: "text", text: "C’est enregistré. Ton carnet compte une étape de plus." },
      { kind: "text", text: photosWanted(budget.photos, budget.pages) },
    ]);
    // Hors production, « Photos de test » s'ajoute aux deux puces.
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos", "dictate", "photos-sample"]);

    // « Photos de test » joint le nombre exact demandé, et MEMO demande de les valider.
    await say(memo.id, SUGGESTIONS["photos-sample"].label, { suggestionId: "photos-sample" });
    const withPhotos = await readThread(memo.id);
    const photos = withPhotos.messages.filter((message) => message.body.kind === "photos").at(-1);
    expect(photos?.body.kind === "photos" && photos.body.photos).toHaveLength(budget.photos);
    expect(memoBubbles(withPhotos).at(-1)?.body).toEqual({ kind: "text", text: photosToValidate(budget.photos) });
    // Une commande se répond sans modèle.
    expect(responder.calls).toBe(callsBefore);

    await say(memo.id, SUGGESTIONS.accept.label, { suggestionId: "accept", entryId: entry.id });
    account = await harness.prisma.account.findUniqueOrThrow({ where: { id: owner.accountId } });
    expect(account.remainingSteps).toBe(2);
  });

  it("« Ça me convient » valide le souvenir que MEMO vient de soumettre, pas une fiche plus ancienne", async () => {
    const memo = await seedTrip(owner.accountId);
    await sendVoice(memo.id);
    const [first] = await harness.prisma.entry.findMany({ where: { memoId: memo.id }, orderBy: { createdAt: "asc" } });
    await say(memo.id, SUGGESTIONS.accept.label, { suggestionId: "accept", entryId: first!.id });
    await sendVoice(memo.id);
    const second = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id, id: { not: first!.id } },
    });

    // L'app se trompe de fiche et envoie la première : c'est la seconde qui est validée.
    await say(memo.id, SUGGESTIONS.accept.label, { suggestionId: "accept", entryId: first!.id });
    const validated = await harness.prisma.entry.findUniqueOrThrow({ where: { id: second.id } });
    expect(validated.validatedAt).not.toBeNull();
  });

  it("« Photos de test » est une commande : gratuite, même étapes offertes épuisées", async () => {
    const memo = await seedTrip(owner.accountId);
    await harness.prisma.account.update({ where: { id: owner.accountId }, data: { remainingSteps: 0 } });
    const { response } = await say(memo.id, SUGGESTIONS["photos-sample"].label, { suggestionId: "photos-sample" });
    expect(response.statusCode).toBe(201);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "photo" } })).toBe(1);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: { not: "photo" } } })).toBe(0);
  });

  it("ne décompte rien à un compte sans quota", async () => {
    await harness.prisma.account.update({
      where: { id: owner.accountId },
      data: { offeredSteps: null, remainingSteps: null },
    });
    const memo = await seedTrip(owner.accountId);
    await sendVoice(memo.id);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });

    const response = await harness.app.inject({
      method: "POST",
      url: `/v1/entries/${entry.id}/validate`,
      headers: { authorization: owner.authorization },
    });
    expect(response.statusCode).toBe(200);
    expect(response.json<{ remainingSteps: number | null }>().remainingSteps).toBeNull();
  });

  it("réserve une étape par souvenir non validé : le quatrième est refusé", async () => {
    const memo = await seedTrip(owner.accountId);
    for (const text of [
      "Premier souvenir, une longue journée à marcher dans Rome.",
      "Deuxième souvenir, une longue soirée sur une terrasse de Trastevere.",
      "Troisième souvenir, une longue matinée au marché de Testaccio.",
    ]) {
      const { response } = await say(memo.id, text);
      expect(response.statusCode).toBe(201);
    }

    const { response: refused } = await say(memo.id, "Quatrième souvenir, encore une longue journée.");
    expect(refused.statusCode).toBe(403);
    expect(refused.json<{ error: string }>().error).toBe("quota_exhausted");

    // Une commande passe toujours.
    const { response: command } = await say(memo.id, SUGGESTIONS.later.label, { suggestionId: "later" });
    expect(command.statusCode).toBe(201);
  });
});

describe("à plusieurs", () => {
  async function coTraveller(memoId: string) {
    const guest = await registerAccount(harness.app, "clara@memobook.app");
    await harness.prisma.account.update({ where: { id: guest.accountId }, data: { firstName: "Clara" } });
    await harness.prisma.memoMember.create({
      data: { memoId, accountId: guest.accountId, status: "active", acceptedAt: new Date() },
    });
    return guest;
  }

  it("partage le fil, et nomme qui parle — jamais soi-même, jamais MEMO", async () => {
    const memo = await seedTrip(owner.accountId);
    const guest = await coTraveller(memo.id);

    await say(memo.id, "Une longue journée de marche, racontée par le propriétaire du voyage.");
    await say(memo.id, "Et une longue soirée racontée par l'invitée du voyage.", {
      authorization: guest.authorization,
    });

    const seenByGuest = await readThread(memo.id, guest.authorization);
    const travellers = seenByGuest.messages.filter((message) => message.author === "traveller");
    expect(travellers.map((message) => message.authorName)).toEqual(["Hugo", null]);
    expect(seenByGuest.messages.filter((message) => message.author === "memo").every((m) => m.authorName === null)).toBe(true);
    expect(seenByGuest.context.memberCount).toBe(2);
    expect(seenByGuest.context.travellerFirstName).toBe("Clara");
    // Le portrait de chacun, sur ses bulles comme sur celles des autres — c'est
    // lui que la bulle d'un vocal montre. MEMO n'en a pas.
    expect(travellers.map((message) => message.authorInitials)).toEqual(["H", "C"]);
    expect(travellers.every((message) => message.authorAvatarUrl === null)).toBe(true);
    expect(
      seenByGuest.messages
        .filter((message) => message.author === "memo")
        .every((message) => message.authorInitials === null && message.authorAvatarUrl === null),
    ).toBe(true);
    expect(seenByGuest.context.travellerInitials).toBe("C");
    expect(seenByGuest.context.travellerAvatarUrl).toBeNull();
    expect(seenByGuest.canClear).toBe(false);

    const seenByOwner = await readThread(memo.id);
    expect(seenByOwner.messages.filter((m) => m.author === "traveller").map((m) => m.authorName)).toEqual([null, "Clara"]);
  });

  it("ne laisse que le propriétaire supprimer la conversation, qui garde l'ouverture", async () => {
    const memo = await seedTrip(owner.accountId);
    const guest = await coTraveller(memo.id);
    await say(memo.id, "Une longue journée de marche dans les ruelles, racontée pour être effacée.");

    const refused = await harness.app.inject({
      method: "DELETE",
      url: `/v1/trips/${memo.id}/chat`,
      headers: { authorization: guest.authorization },
    });
    expect(refused.statusCode).toBe(403);
    expect(refused.json<{ error: string }>().error).toBe("owner_only");

    const cleared = await harness.app.inject({
      method: "DELETE",
      url: `/v1/trips/${memo.id}/chat`,
      headers: { authorization: owner.authorization },
    });
    expect(cleared.statusCode).toBe(204);

    const thread = await readThread(memo.id);
    expect(thread.messages).toHaveLength(1);
    expect(thread.messages[0]?.body).toEqual({ kind: "text", text: OPENING_TEXT });
    // Le souvenir reste dans le carnet, et ne revient pas dans le fil.
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);
    expect((await readThread(memo.id)).messages).toHaveLength(1);
  });
});

describe("le sondage et le plafond", () => {
  it("rend la suite du fil depuis un instant, fiches modifiées comprises", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "Une longue journée de marche dans les ruelles de Rome, pour commencer.");
    const before = await readThread(memo.id);

    await new Promise((resolve) => setTimeout(resolve, 5));
    const { id } = await say(memo.id, "Une longue soirée sur une terrasse, pour continuer.");

    const update = await readThread(memo.id, owner.authorization, before.now);
    const ids = update.messages.map((message) => message.id);
    expect(ids).toContain(id);
    expect(ids).not.toContain(before.messages[0]?.id);
    expect(update.turn).toEqual({ status: "idle" });

    // Corriger le premier souvenir fait revenir sa fiche, sans nouveau message.
    const entry = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id },
      orderBy: { capturedAt: "asc" },
    });
    const checkpoint = update.now;
    await new Promise((resolve) => setTimeout(resolve, 5));
    await harness.app.inject({
      method: "PATCH",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
      payload: { editedText: "Ma version, au mot près." },
    });
    const afterEdit = await readThread(memo.id, owner.authorization, checkpoint);
    const cards = afterEdit.messages.filter((message) => message.body.kind === "transcript");
    expect(cards).toHaveLength(1);
    expect(cards[0]?.body.kind === "transcript" && cards[0].body.transcript.text).toBe("Ma version, au mot près.");
  });

  it("ferme la porte à un script, pas à un voyageur : 150 tours par jour", async () => {
    const memo = await seedTrip(owner.accountId);
    await harness.prisma.chatMessage.createMany({
      data: Array.from({ length: 150 }, () => ({
        memoId: memo.id,
        author: "traveller" as const,
        kind: "text" as const,
        accountId: owner.accountId,
        text: "…",
        disposition: "command" as const,
        repliedAt: new Date(),
      })),
    });

    const { response } = await say(memo.id, "Encore un.");
    expect(response.statusCode).toBe(429);
    expect(response.json<{ error: string }>().error).toBe("chat_daily_cap");
  });
});
