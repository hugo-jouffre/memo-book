import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Jimp } from "jimp";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { FakeResponder } from "../src/services/conversation.js";
import { refreshTripFacts } from "../src/services/tripFacts.js";
import {
  LISTENING_FOR_REVISION,
  OPENING_TEXT,
  PHOTOS_VALIDATED_BEFORE_RETURN,
  REDACTION_UNWRITTEN,
  redactionKept,
  returnForPhotos,
  SPLIT_NOT_FOUND,
  SPLIT_REFUSED,
  splitAccepted,
  SUGGESTION_SETS,
  SUGGESTIONS,
  tooShort,
  PHOTOS_VALIDATED,
  photosKept,
  photosWanted,
} from "../src/services/conversationCopy.js";
import {
  FakeRedactor,
  ORAL_CORRECTION_TOPIC,
  type RedactionInput,
  type RedactionResult,
} from "../src/services/redaction.js";
import { photoBudgetFor } from "../src/services/photoBudget.js";
import { COVER_AFTER_STEPS } from "../src/routes/chatSerializers.js";
import {
  CONTEXT_COMPLETE,
  CONTEXT_INVITATION,
  CONTEXT_NOTED,
  CONTEXT_SKIPPED,
  questionFor,
  EMPTY_TRIP_CONTEXT,
} from "../src/services/tripContext.js";
import { FakeTranscriber } from "../src/services/transcription.js";
import { DAILY_CREDIT_LIMIT_MS, TEXT_MS_PER_CHARACTER } from "../src/services/dailyCredit.js";
import { localDate } from "../src/services/localCalendar.js";
import { parseConversationState } from "../src/services/conversation.js";
import { longDay, missingDayListening } from "../src/services/conversationCopy.js";
import {
  VOICE_FIXTURES,
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
  /** La pastille de MEMO (T296) — absente d'une bulle qui n'en porte pas. */
  reaction?: { emoji: string; label: string };
  body:
    | { kind: "text"; text: string }
    | { kind: "voice"; voice: { id: string; duration: number; levels: number[]; remoteUrl: string | null } }
    | {
        kind: "photos";
        photos: { id: string; remoteUrl: string; isStepCover: boolean; isTripCover: boolean }[];
      }
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
  entryId: string | null;
  disposition: string | null;
  pauseMilliseconds: number | null;
  callToAction?: { id: string; kind: string; label: string } | null;
}

interface ChatThreadJson {
  id: string;
  title: string;
  greeting: { title: string; message: string };
  preview: { memoryCount: number; pageCount: number; isOpenable: boolean } | null;
  context: {
    tripId: string;
    stepId: string | null;
    travellerFirstName: string | null;
    travellerInitials: string | null;
    travellerAvatarUrl: string | null;
    memberCount: number;
    prompt: string | null;
    /** Les étapes du voyage, pour « Déplacer dans une autre étape » (T270). */
    steps: { id: string; number: number; placeName: string | null }[];
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
  /** Les noms propres dont l'écrivain doute, sur commande (T282). */
  namesToConfirm: string[] = [];
  /**
   * Le lieu que le **récit** nomme, sur commande (T267). `null` : le vocal ne
   * dit pas où on est — le cas de 15 journées sur 35 d'un vrai carnet.
   */
  place: string | null = null;
  inputs: RedactionInput[] = [];
  /**
   * **La panne de l'écrivain, sur commande.** Le crédit Anthropic épuisé
   * (26/10–08/11/2026) et le plafond de jetons atteint (17/11/2026)
   * remontent ici de la même façon : une exception, et une fiche `failed`.
   */
  fails: string | null = null;

  override async redact(input: RedactionInput): Promise<RedactionResult> {
    this.inputs.push(input);
    if (this.fails) throw new Error(this.fails);
    const base = await super.redact(input);
    return {
      ...base,
      doubts: this.doubts,
      namesToConfirm: this.namesToConfirm,
      insights: this.place
        ? { ...base.insights, currentPlace: this.place, cities: [this.place] }
        : base.insights,
    };
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
  responder.inputs = [];
  redactor.doubts = [];
  redactor.namesToConfirm = [];
  // **Le cas courant : le récit dit où on est.** Un vocal de voyage nomme
  // presque toujours sa ville, et l'écrivain la relève (`insights`). Les
  // tests qui veulent une journée muette — celle qui fait demander le lieu
  // (T267) — posent `place = null` eux-mêmes.
  redactor.place = "Rome";
  redactor.inputs = [];
  redactor.fails = null;
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
  extra: {
    id?: string;
    suggestionId?: string;
    entryId?: string;
    authorization?: string;
    platform?: string;
    reactionTo?: string;
  } = {},
) {
  const id = extra.id ?? randomUUID();
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: {
      authorization: extra.authorization ?? owner.authorization,
      ...(extra.platform ? { "x-app-platform": extra.platform } : {}),
    },
    payload: {
      id,
      kind: "text",
      text,
      ...(extra.suggestionId ? { suggestionId: extra.suggestionId } : {}),
      ...(extra.entryId ? { entryId: extra.entryId } : {}),
      ...(extra.reactionTo ? { reactionTo: extra.reactionTo } : {}),
    },
  });
  return { id, response };
}

/** Le voyage a raconté ses 2 minutes du jour (au fuseau de Paris, celui d'un compte sans fuseau). */
async function exhaustCredit(memoId: string) {
  await harness.prisma.tripDailyUsage.create({
    data: {
      memoId,
      day: new Date(`${localDate(new Date(), "Europe/Paris")}T00:00:00Z`),
      usedMs: DAILY_CREDIT_LIMIT_MS,
    },
  });
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
    // Un vrai `.m4a` : le serveur mesure la durée dans le fichier, et refuse
    // ce qu'il ne lit pas. `durationSeconds` ci-dessus n'est plus lu.
    { field: "file", filename: "memo.m4a", contentType: "audio/mp4", content: VOICE_FIXTURES.short },
  );
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization, "content-type": contentType },
    payload,
  });
  return { id, response };
}

/**
 * De **vraies** images, et non le texte `jpeg-0` qui tenait lieu de photo
 * jusqu'au 15/10/2026.
 *
 * Depuis que la couverture d'un voyage est sa photo paysage la plus récente,
 * le serveur mesure chaque photo à l'arrivée : un octet qui n'est pas une
 * image ne se mesure pas, ne vaut donc jamais couverture, et le test qui
 * vérifiait qu'une photo du fil devient la photo du voyage tombait — sur son
 * brin de ficelle, pas sur le code. Petites (120 × 90) pour rester rapides, et
 * **paysage**, qui est le cas dont ces tests parlent.
 */
async function multipartPhotos(
  id: string,
  count: number,
  content?: Buffer,
  /** Ce que chaque photo sait d'elle-même, dans l'ordre des fichiers (T280). */
  metas?: { capturedAt?: string; capturedPlaceName?: string }[],
) {
  const boundary = `----memobookphotos${Date.now()}`;
  const parts: Buffer[] = [
    Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="id"\r\n\r\n${id}\r\n`),
  ];
  if (metas) {
    parts.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="photos"\r\n\r\n${JSON.stringify(metas)}\r\n`,
      ),
    );
  }
  for (let index = 0; index < count; index += 1) {
    const image =
      content ??
      Buffer.from(
        await new Jimp({ width: 120, height: 90, color: 0x3fa7d6ff + index }).getBuffer("image/jpeg"),
      );
    parts.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="photo-${index}.jpg"\r\n` +
          `Content-Type: image/jpeg\r\n\r\n`,
      ),
      image,
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
  /**
   * **MEMO dit bonjour dès qu'on ouvre la conversation** (Hugo, 28/10/2026).
   * Sa bulle n'était posée qu'au premier tour du voyageur : un carnet neuf
   * s'ouvrait sur un fil vide, où l'app dessinait son propre mot d'accueil —
   * qui disait presque la même chose, et la contredisait en partie puisque
   * l'ouverture demande ensuite le contexte du voyage.
   */
  it("s'ouvre sur le bonjour de MEMO, avec les puces d'ouverture, et dit qui peut l'effacer", async () => {
    const memo = await seedTrip(owner.accountId);
    const thread = await readThread(memo.id);

    expect(thread.messages).toHaveLength(1);
    expect(thread.messages[0]?.author).toBe("memo");
    expect(thread.messages[0]?.body).toEqual({ kind: "text", text: OPENING_TEXT });

    // Une seule fois : rouvrir le fil ne redit pas bonjour.
    const again = await readThread(memo.id);
    expect(again.messages).toHaveLength(1);
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
    // Le petit livre est encore nu (T297) : aucune étape n'a de photo, et il
    // en faut quatre pour que la couverture paraisse.
    expect(thread.preview).toEqual({
      memoryCount: 2,
      pageCount: 4,
      isOpenable: false,
      coverUrl: null,
      stepsBeforeCover: COVER_AFTER_STEPS,
    });

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

    // Le texte rédigé est gardé d'office (03/11/2026) : MEMO le dit, puis
    // demande ses photos — ni reformulation, ni question sur le lieu, ni
    // « Il te convient ? ».
    const replies = memoBubbles(thread).filter((message) => message.seq > (mine?.seq ?? 0));
    expect(replies.map((message) => message.body)).toEqual(await keptBubbles(memo, mine!.entryId!));
    expect(replies.every((message) => (message.pauseMilliseconds ?? 0) >= 450)).toBe(true);
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos", "edit-hand", "edit-voice"]);

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

  it("dit qu'il n'a pas compris un « ok », et n'en fait pas un souvenir", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id, response } = await say(memo.id, "ok");
    expect(response.statusCode).toBe(201);

    const thread = await readThread(memo.id);
    const mine = thread.messages.find((message) => message.id === id);
    // Le répondeur l'a classé souvenir ; le code le reprend (Hugo, 08/10/2026).
    expect(mine?.disposition).toBe("command");
    const replies = memoBubbles(thread).filter((message) => message.seq > (mine?.seq ?? 0));
    expect(replies.map((message) => message.body)).toEqual([{ kind: "text", text: tooShort("ok")[0] }]);
    expect(thread.messages.some((message) => message.body.kind === "transcript")).toBe(false);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(0);
  });

  /**
   * ⚠️ **Il ne le cite plus** (Hugo, 16/11/2026 — « le chat ne veut pas
   * ajouter certains éléments sous prétexte qu'il ne les comprend pas »).
   *
   * L'écrivain n'imprime toujours que ce qu'il a compris : c'est ce qui
   * empêche le carnet d'affirmer « des Australiens totalement je tarbé ».
   * Mais le dire à chaque souvenir sonnait comme un refus, et le passage est
   * déjà lisible dans « Mot pour mot ». La bulle est donc la même, doute ou
   * pas — et c'est ce que ce cas garde.
   */
  it("ne cite plus dans la bulle ce que l'écrivain n'a pas compris", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.doubts = ["je tarbé"];
    const { id } = await say(memo.id, "Le soir on a fini en boîte avec des Australiens totalement je tarbé.");

    const thread = await readThread(memo.id);
    const mine = thread.messages.find((message) => message.id === id);
    const replies = memoBubbles(thread).filter((message) => message.seq > (mine?.seq ?? 0));
    // La même bulle qu'un souvenir sans doute : rien n'est ajouté, et surtout
    // pas une phrase qui s'excuse.
    const bulles = replies.map((message) => message.body);
    expect(bulles).toEqual(await keptBubbles(memo, mine!.entryId!));
    expect(JSON.stringify(bulles)).not.toContain("je tarbé");

    // ⚠️ **Et il n'est pas perdu pour autant** : c'est ce qui autorise la
    // bulle à se taire. La transcription garde le passage entier, et la fiche
    // la sert dès qu'elle diffère du texte rédigé (`twoVersionsOf`) — c'est
    // la bascule « Mot pour mot ». Ce cas tient le maillon qui compte : la
    // donnée. Si un jour la transcription perdait ce que l'écrivain écarte,
    // se taire deviendrait une perte silencieuse.
    const souvenir = await harness.prisma.entry.findUniqueOrThrow({ where: { id: mine!.entryId! } });
    expect(souvenir.transcript, "la transcription garde ce que le texte écarte").toContain("je tarbé");
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos", "edit-hand", "edit-voice"]);
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
    // Le texte est gardé d'office (03/11/2026) : quand la précision arrive, le
    // souvenir est déjà validé. Le faux répondeur n'y voit donc plus de
    // souvenir en cours ; le vrai modèle, lui, lit « Déjà validé » et peut
    // encore la classer en précision. C'est ce cas qu'on rejoue.
    const fakeReply = responder.reply.bind(responder);
    const asPrecision = vi.spyOn(responder, "reply").mockImplementationOnce(async (input) => ({
      ...(await fakeReply(input)),
      disposition: "context",
    }));
    const { id, response } = await say(memo.id, "C'était avec Clara.");
    asPrecision.mockRestore();
    expect(response.statusCode).toBe(201);

    const thread = await readThread(memo.id);
    const precision = thread.messages.find((message) => message.id === id);
    expect(precision?.disposition).toBe("context");

    const entries = await harness.prisma.entry.findMany({ where: { memoId: memo.id } });
    expect(entries).toHaveLength(1);
    expect(entries[0]?.redactedText).toContain("C'était avec Clara.");

    // **Aucune bulle, une pastille** (T296) : MEMO disait « C'est noté, je
    // reprends le texte avec ça. » — un accusé que l'écran portait déjà. Le
    // texte se réécrit, et le ✅ sur la précision dit qu'elle est prise en
    // compte. Déjà gardé, il n'y a rien à redemander non plus.
    const after = await readThread(memo.id);
    const replies = memoBubbles(after).filter((message) => message.seq > (precision?.seq ?? 0));
    expect(replies).toEqual([]);
    const noted = after.messages.find((message) => message.id === id);
    expect(noted?.reaction?.emoji).toBe("✅");
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
    // La durée **mesurée dans le fichier** (2,136 s) fait foi : ni les 37 s
    // que l'app déclare, ni les 12 s du transcripteur simulé (03/10/2026).
    expect(voice?.body.kind === "voice" && voice.body.voice.duration).toBeCloseTo(2.136, 3);
    expect(voice?.sentAt).toBe("2026-09-21T09:00:00.000Z");

    const card = thread.messages.find((message) => message.body.kind === "transcript");
    expect(card?.body.kind === "transcript" && card.body.transcript.phase).toBe("ready");
    expect(card?.body.kind === "transcript" && card.body.transcript.text).toContain("Bogotá");
    // La première fiche du fil est l'étape 1, et le récit porte son titre.
    expect(card?.body.kind === "transcript" && card.body.transcript.title).toBe("Retranscription étape 1");
    // Le transcripteur a reçu les noms que le carnet connaît : qui raconte, et où.
    expect(transcriber.hints.at(-1)).toBe("Récit de voyage de Hugo (Rome).");
    expect(card?.body.kind === "transcript" && card.body.transcript.heading).toBeTruthy();
    // Gardée d'office : MEMO enchaîne sur les photos, retoucher reste à un appui.
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos", "edit-hand", "edit-voice"]);
  });

  it("reçoit des photos : un souvenir par image, une seule bulle", async () => {
    const memo = await seedTrip(owner.accountId);
    const id = randomUUID();
    const { payload, contentType } = await multipartPhotos(id, 2);
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
    // **L'envoi vaut validation** (Hugo, 03/11/2026) : MEMO dit ce qu'il en
    // fait, sans rien demander, et les photos sont déjà dans le carnet.
    expect(memoBubbles(thread).at(-1)?.body).toEqual({ kind: "text", text: photosKept(2) });
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual([
      "photos-more",
      "preview",
      "dictate",
    ]);
    expect(
      await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "photo", validatedAt: null } }),
    ).toBe(0);
    expect(await harness.prisma.render.count({ where: { memoId: memo.id } })).toBe(1);

    // La puce d'avant reste comprise : une app plus ancienne l'envoie encore.
    const { response: validation } = await say(memo.id, SUGGESTIONS["photos-ok"].label, {
      suggestionId: "photos-ok",
    });
    expect(validation.statusCode).toBe(201);
    const after = await readThread(memo.id);
    expect(memoBubbles(after).at(-1)?.body).toEqual({ kind: "text", text: PHOTOS_VALIDATED });
    // **Raconter d'abord** (T307) : « prévisualiser » n'ouvre plus le trio.
    // La page de l'étape se compose encore quand cette bulle s'affiche.
    expect(after.suggestions.map((suggestion) => suggestion.id)).toEqual(["dictate", "write", "preview"]);
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

async function sendPhotos(
  memoId: string,
  count: number,
  content?: Buffer,
  metas?: { capturedAt?: string; capturedPlaceName?: string }[],
) {
  const id = randomUUID();
  const { payload, contentType } = await multipartPhotos(id, count, content, metas);
  const response = await harness.app.inject({
    method: "POST",
    url: `/v1/trips/${memoId}/chat`,
    headers: { authorization: owner.authorization, "content-type": contentType },
    payload,
  });
  expect(response.statusCode).toBe(201);
  return id;
}

/**
 * Ce que MEMO dit quand la rédaction est **gardée d'office** (Hugo,
 * 03/11/2026, `confirmRedaction`) : le texte est gardé, puis il demande les
 * photos du récit, au nombre que le ratio du carnet appelle.
 */
async function keptBubbles(memo: { photoTextRatio?: number | null }, entryId: string) {
  const entry = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entryId } });
  const budget = photoBudgetFor((entry.editedText ?? entry.redactedText ?? "").trim(), memo);
  return [
    { kind: "text", text: redactionKept() },
    { kind: "text", text: photosWanted(budget.photos, budget.pages) },
  ];
}

async function readSteps(memoId: string) {
  const response = await harness.app.inject({
    method: "GET",
    url: `/v1/trips/${memoId}`,
    headers: { authorization: owner.authorization },
  });
  expect(response.statusCode).toBe(200);
  return response.json<{
    steps: { id: string; number: number; entryIds: string[]; photoUrl: string | null; storyCount: number }[];
  }>().steps;
}

/**
 * ⚠️ **Une panne qui s'annonce comme un succès ne se répare pas** — personne
 * ne la voit.
 *
 * Du 26/10 au 08/11/2026, huit rédactions du carnet de Hugo sont tombées
 * faute de crédit Anthropic. La fiche le disait pourtant (phase `unwritten`),
 * mais la bulle juste en dessous répondait « Voilà ton texte pour le carnet :
 * je le garde tel quel » — et c'est la dernière qu'on lit. Deux semaines ont
 * passé sur « une journée vide alors que le chat m'a dit que tout avait été
 * renseigné » (Hugo, 16/11/2026).
 *
 * La file **en ligne** des tests remonte l'exception de la rédaction jusqu'à
 * la route, qui rend une erreur : en production c'est un job pg-boss à part,
 * et le tour du voyageur ne la voit pas. Tout ce qui est vérifié ici est
 * écrit **avant** qu'elle ne remonte — c'est bien ce que le voyageur trouve
 * dans son fil.
 */
describe("la rédaction qui échoue ne s'annonce plus comme un succès (17/11/2026)", () => {
  const PANNE = "Your credit balance is too low to access the Anthropic API.";
  const RECIT =
    "Ce matin on est partis tôt pour éviter la chaleur, on a marché jusqu'au marché de Testaccio.";

  /** Les bulles de MEMO venues après le tour du voyageur, dans l'ordre. */
  function saidAfter(thread: ChatThreadJson, afterId: string): string[] {
    const mine = thread.messages.find((message) => message.id === afterId);
    return memoBubbles(thread)
      .filter((message) => message.seq > (mine?.seq ?? 0))
      .map((message) => (message.body.kind === "text" ? message.body.text : ""));
  }

  it("dit qu'il n'a pas réussi à l'écrire, et la fiche ne le démentit plus", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.fails = PANNE;

    const { id } = await say(memo.id, RECIT);
    const thread = await readThread(memo.id);
    const said = saidAfter(thread, id);

    expect(said[0]).toBe(REDACTION_UNWRITTEN);
    // Le mensonge, nommément : plus aucune bulle ne prétend qu'un texte a été
    // écrit. C'est l'assertion qui garde la correction.
    expect(said.some((text) => text.includes("Voilà ton texte pour le carnet"))).toBe(false);

    // La fiche disait déjà la vérité — les deux concordent enfin.
    const card = thread.messages.find((message) => message.body.kind === "transcript");
    expect(card?.body.kind === "transcript" && card.body.transcript.phase).toBe("unwritten");

    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    expect(entry.redactionStatus).toBe("failed");
    expect(entry.redactionError).toContain("credit balance");
  });

  it("compte le souvenir quand même, et demande ses photos sur le mot-pour-mot", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.fails = PANNE;

    const { id } = await say(memo.id, RECIT);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });

    // Rien n'est perdu : le souvenir est validé, et son mot-pour-mot part
    // dans le carnet (`finalTextOf`). C'est donc sur lui que le nombre de
    // photos se calcule, et non sur un texte rédigé qui n'existe pas.
    expect(entry.validatedAt).not.toBeNull();
    const budget = photoBudgetFor((entry.transcript ?? "").trim(), memo);
    expect(budget.photos).toBeGreaterThan(0);

    const said = saidAfter(await readThread(memo.id), id);
    expect(said).toEqual([REDACTION_UNWRITTEN, photosWanted(budget.photos, budget.pages)]);
  });
});

describe("le téléphone du tour (lot B5, 22/10/2026)", () => {
  it("retient Android sur le tour, et le job le dit à MEMO", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id } = await say(memo.id, "On a pris le train de nuit jusqu'à Naples, couchettes à six.", {
      platform: "android",
    });

    const message = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
    expect(message.payload).toMatchObject({ platform: "android" });
    expect(responder.inputs.at(-1)?.message.id).toBe(id);
    expect(responder.inputs.at(-1)?.traveller.platform).toBe("android");
  });

  it("sans l'en-tête, c'est un iPhone, et le tour reste tel qu'il était", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id } = await say(memo.id, "On a pris le train de nuit jusqu'à Naples, couchettes à six.");
    const unknown = await say(memo.id, "Arrivés à l'aube, café serré sur le port avant le ferry.", {
      platform: "windows-phone",
    });

    const message = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
    expect((message.payload as { platform?: unknown } | null)?.platform).toBeUndefined();
    const byId = new Map(responder.inputs.map((input) => [input.message.id, input]));
    expect(byId.get(id)?.traveller.platform).toBe("ios");
    expect(byId.get(unknown.id)?.traveller.platform).toBe("ios");
  });
});

describe("modifier à l'oral (Hugo, 12/10/2026)", () => {
  it("le vocal qui suit corrige la fiche au lieu de faire un souvenir de plus", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "On est allés au zoo avec Mathis hier après-midi, il faisait beau.");
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });

    const { response: chip } = await say(memo.id, SUGGESTIONS["edit-voice"].label, { suggestionId: "edit-voice" });
    expect(chip.statusCode).toBe(201);
    expect(memoBubbles(await readThread(memo.id)).at(-1)?.body).toEqual({
      kind: "text",
      text: LISTENING_FOR_REVISION,
    });

    const { id, response } = await sendVoice(memo.id);
    expect(response.statusCode).toBe(201);
    // Ni souvenir ni fiche de plus : la correction vise la fiche d'avant.
    const receipt = response.json<{ messages: ChatMessageJson[] }>();
    expect(receipt.messages.map((message) => message.body.kind)).toEqual(["voice"]);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);

    const thread = await readThread(memo.id);
    const correction = thread.messages.find((message) => message.id === id);
    expect(correction?.disposition).toBe("context");
    // On réécoute **son** fichier, pas celui de la fiche.
    expect(correction?.body.kind === "voice" && correction.body.voice.remoteUrl).toContain(
      `/v1/chat-messages/${id}/media`,
    );
    expect(thread.messages.filter((message) => message.body.kind === "transcript")).toHaveLength(1);

    // La rédaction a relu la correction comme telle. La correction a rouvert
    // le souvenir (`validatedAt` remis à zéro) : le texte réécrit est gardé
    // d'office à son tour, et MEMO redemande ses photos.
    const last = redactor.inputs.at(-1)!;
    const heard = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
    expect(heard.text).toBeTruthy();
    expect(last.entry.precisions).toEqual([{ text: heard.text, topic: ORAL_CORRECTION_TOPIC }]);
    const replies = memoBubbles(thread).filter((message) => message.seq > (correction?.seq ?? 0));
    // La correction entendue ne reçoit plus d'accusé (T296) : la pastille du
    // vocal le dit, et seules les bulles du texte réécrit suivent.
    expect(replies.map((message) => message.body)).toEqual(await keptBubbles(memo, entry.id));
    expect(correction?.reaction?.emoji).toBe("✅");
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos", "edit-hand", "edit-voice"]);
    const rewritten = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(rewritten.redactionStatus).toBe("ready");
  });

  it("un vocal qui ne suit pas la puce reste un souvenir de plus", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "On est allés au zoo avec Mathis hier après-midi, il faisait beau.");
    await sendVoice(memo.id);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(2);
  });
});

describe("une étape par récit (Hugo, 12/10/2026)", () => {
  it("chaque récit validé ajoute une carte d'étape, même au même endroit", async () => {
    const memo = await seedTrip(owner.accountId);
    await sendVoice(memo.id);
    const [first] = await harness.prisma.entry.findMany({ where: { memoId: memo.id } });
    await say(memo.id, SUGGESTIONS.accept.label, { suggestionId: "accept", entryId: first!.id });
    expect(await readSteps(memo.id)).toHaveLength(1);

    // L'app n'a plus d'étape « active » à joindre à ce qu'on raconte.
    expect((await readThread(memo.id)).context.stepId).toBeNull();

    await sendVoice(memo.id);
    const steps = await readSteps(memo.id);
    expect(steps.map((step) => step.number)).toEqual([1, 2]);

    // Le fil dit l'étape de chaque récit : c'est ce qui l'ouvre sur lui.
    const thread = await readThread(memo.id);
    const stories = thread.messages.filter((message) => message.body.kind === "voice");
    expect(stories.map((message) => message.stepId)).toEqual(steps.map((step) => step.id));
  });

  it("les photos rejoignent le récit dont MEMO les a demandées, et illustrent l'étape", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "On a passé la matinée au Colisée, il y avait un monde fou devant l'entrée.");
    const story = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    await say(memo.id, SUGGESTIONS.accept.label, { suggestionId: "accept", entryId: story.id });

    await sendPhotos(memo.id, 1);
    // Une seule photo : « la », pas « les » — et, MEMO en ayant demandé plus,
    // il dit combien il en manque (18/10/2026).
    const reply = memoBubbles(await readThread(memo.id)).at(-1)?.body as { kind: string; text: string };
    expect(reply.kind).toBe("text");
    expect(reply.text).toMatch(/^J’ai bien reçu ta photo\. Il m’en faudrait encore .* avec celle-ci en attendant,/);

    const [step] = await readSteps(memo.id);
    const photo = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id, kind: "photo" } });
    expect(step?.entryIds).toEqual([story.id, photo.id]);
    // La vignette de l'étape. Sans CDN configuré — le cas du développement
    // comme celui d'un déploiement sans `WEBFLOW_API_TOKEN` —, la photo se
    // sert par l'API elle-même (11/11/2026, `services/renderPhotos.ts`) : plus
    // aucune adresse `cdn.example.test`, que rien n'aurait servie, ni dans la
    // vignette ni dans le payload du carnet.
    expect(step?.photoUrl).toMatch(/^http:\/\/localhost:3000\/v1\/trip-photos\/.+\.jpg$/);
    const home = await harness.app.inject({ method: "GET", url: "/v1/home", headers: { authorization: owner.authorization } });
    expect(home.json<{ trips: { coverPhotoUrl: string | null }[] }>().trips[0]?.coverPhotoUrl).toBe(step?.photoUrl);
  });

  /**
   * **Une photo de photothèque d'iPhone arrive en HEIC**, sous un nom en
   * `.jpg` et un type `image/jpeg` (Hugo, 11/11/2026). Elle était écrite
   * telle quelle : le carnet se composait sans elle, et `measurePhoto` ne
   * sachant pas lire le HEIC, elle ne pouvait pas non plus devenir la
   * couverture du voyage.
   */
  it("convertit une photo HEIC à l'arrivée, qui devient couverture du voyage", async () => {
    const memo = await seedTrip(owner.accountId);
    const heic = readFileSync(
      resolve(new URL("./fixtures/photos/heic-iphone.heic", import.meta.url).pathname),
    );

    await sendPhotos(memo.id, 1, heic);

    const photo = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id, kind: "photo" },
      include: { media: true },
    });
    expect(photo.media?.mimeType).toBe("image/jpeg");
    expect(photo.media?.storageKey).toMatch(/\.jpg$/);
    // 40 × 30 : mesurée, donc candidate à la couverture — ce qu'un HEIC
    // n'était jamais.
    expect(photo.photoIsLandscape).toBe(true);

    const home = await harness.app.inject({
      method: "GET",
      url: "/v1/home",
      headers: { authorization: owner.authorization },
    });
    expect(home.json<{ trips: { coverPhotoUrl: string | null }[] }>().trips[0]?.coverPhotoUrl).toMatch(
      /^http:\/\/localhost:3000\/v1\/trip-photos\/.+\.jpg$/,
    );
  });
});

/**
 * **Un message n'est pas toujours une étape** (Hugo, 28/10/2026). La
 * rédaction dit qu'un récit en prolonge un autre ; les deux ne font alors
 * qu'une étape, et le voyageur peut les séparer s'il n'est pas d'accord.
 */
describe("grouper deux récits en une étape (Hugo, 28/10/2026)", () => {
  it("les réunit, puis les sépare quand le voyageur le demande", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "On a passé la matinée au Colisée, il y avait un monde fou devant l'entrée.");
    await say(memo.id, "Et sinon le soir, on est retournés boire un verre au même endroit.");
    expect(await readSteps(memo.id)).toHaveLength(2);

    // Ce que la rédaction aurait compris : le second prolonge le premier.
    const [, second] = await harness.prisma.entry.findMany({
      where: { memoId: memo.id },
      orderBy: { createdAt: "asc" },
    });
    await harness.prisma.entry.update({
      where: { id: second!.id },
      data: { continuesPreviousStep: true },
    });
    await refreshTripFacts(harness.prisma, memo.id);

    const grouped = await readSteps(memo.id);
    expect(grouped).toHaveLength(1);
    expect(grouped[0]?.storyCount).toBe(2);

    // « Séparer ces récits » : la main l'emporte sur la machine.
    const separated = await harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memo.id}/steps/${grouped[0]!.id}/separate`,
      headers: { authorization: owner.authorization },
    });
    expect(separated.statusCode).toBe(200);

    const apart = await readSteps(memo.id);
    expect(apart.map((step) => step.number)).toEqual([1, 2]);
    expect(apart.every((step) => step.storyCount === 1)).toBe(true);

    // Et une rédaction qui repasse ne les réunira plus.
    await refreshTripFacts(harness.prisma, memo.id);
    expect(await readSteps(memo.id)).toHaveLength(2);
  });
});

/**
 * **Un message peut contenir plusieurs étapes** (Hugo, 28/10/2026).
 *
 * L'écrivain entend les moments distincts d'un même récit et les propose ;
 * MEMO pose la question dans le fil ; **rien n'est découpé avant la réponse**.
 */
describe("découper un récit en plusieurs étapes (Hugo, 28/10/2026)", () => {
  const RECIT =
    "Jeudi on a marché jusqu'au Colisée, il y avait un monde fou. " +
    "Le lendemain on a pris la route du sud, direction Naples.";

  /** Un souvenir raconté, et la proposition de découpage que l'écrivain en a faite. */
  async function toldWithSuggestion(memoId: string) {
    await say(memoId, RECIT);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId } });
    await harness.prisma.entry.update({
      where: { id: entry.id },
      data: {
        transcript: RECIT,
        splitSuggestion: [
          { title: "Le Colisée bondé", transcript: "Jeudi on a marché jusqu'au Colisée, il y avait un monde fou." },
          { title: "La route du sud", transcript: "Le lendemain on a pris la route du sud, direction Naples." },
        ],
      },
    });
    // La question de MEMO, telle que la rédaction la pose (`askToSplit`).
    await harness.prisma.chatMessage.create({
      data: {
        memoId,
        author: "memo",
        kind: "text",
        text: "Tu m'as raconté 2 moments d'un coup. Tu préfères ?",
        model: "scripted",
        payload: { suggestions: ["split", "keep"], asksSplitFor: entry.id },
      },
    });
    return entry;
  }

  it("découpe à la confirmation : deux souvenirs, deux fiches, deux étapes", async () => {
    const memo = await seedTrip(owner.accountId);
    const entry = await toldWithSuggestion(memo.id);

    await say(memo.id, SUGGESTIONS.split.label, { suggestionId: "split" });

    // Le souvenir d'origine garde la première part, et son audio.
    const after = await harness.prisma.entry.findMany({
      where: { memoId: memo.id },
      orderBy: { capturedAt: "asc" },
    });
    expect(after).toHaveLength(2);
    expect(after[0]?.id).toBe(entry.id);
    expect(after[0]?.transcript).toBe("Jeudi on a marché jusqu'au Colisée, il y avait un monde fou.");
    expect(after[1]?.transcript).toBe("Le lendemain on a pris la route du sud, direction Naples.");
    // La seconde part est du texte : l'audio ne se coupe pas en deux.
    expect(after[1]?.kind).toBe("text");
    // La proposition est consommée : la question ne se repose pas.
    expect(after[0]?.splitSuggestion).toBeNull();

    // **Chaque part a son texte**, écrit depuis elle seule. On regarde le
    // texte et non le statut : le banc exécute les jobs, donc la rédaction
    // est déjà repassée quand on arrive ici.
    const texts = after.map((row) => row.redactedText ?? row.transcript ?? "");
    expect(texts[0]).toContain("Colisée");
    expect(texts[1]).toContain("Naples");
    expect(texts[0]).not.toContain("Naples");

    // Chaque part a sa fiche dans le fil, et MEMO dit ce qu'il a fait.
    const thread = await readThread(memo.id);
    const cards = thread.messages.filter((message) => message.body.kind === "transcript");
    expect(cards).toHaveLength(2);
    // Dans le fil, pas forcément en dernier : les deux rédactions repassent
    // derrière et posent chacune son « Il te convient ? ».
    expect(memoBubbles(thread).map((message) => message.body)).toContainEqual({
      kind: "text",
      text: splitAccepted(2),
    });

    // Et deux cartes sur l'accueil du voyage.
    expect(await readSteps(memo.id)).toHaveLength(2);

    // **Et rien ne les recollera** : la rédaction des parts juge aussi si un
    // récit prolonge le précédent, et deux parts d'un même récit, elle les
    // dirait prolongées. Même si elle le dit, elles restent séparées — le
    // voyageur l'a demandé (`separatedByTraveller`).
    await harness.prisma.entry.update({
      where: { id: after[1]!.id },
      data: { continuesPreviousStep: true },
    });
    await refreshTripFacts(harness.prisma, memo.id);
    expect(await readSteps(memo.id)).toHaveLength(2);
  });

  /**
   * **T279** (Hugo, 05/11/2026) : « les souvenirs ne sont pas toujours dans
   * l'ordre chronologique et gardent l'ordre du vocal, qui peut être très
   * désordonné ».
   *
   * Ici le vocal revient en arrière : le Colisée est raconté en premier mais
   * vécu le second. Avant, les parts se décalaient d'une seconde dans l'ordre
   * du récit, et le carnet imprimait ce désordre.
   */
  it("range les parts par ce qu'elles racontent, pas par l'ordre du vocal", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, RECIT);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    await harness.prisma.entry.update({
      where: { id: entry.id },
      data: {
        transcript: RECIT,
        splitSuggestion: [
          {
            title: "Le Colisée bondé",
            transcript: "Jeudi on a marché jusqu'au Colisée, il y avait un monde fou.",
            day: "2026-04-09",
            partOfDay: null,
          },
          {
            title: "La route du sud",
            transcript: "Le lendemain on a pris la route du sud, direction Naples.",
            day: "2026-04-08",
            partOfDay: null,
          },
        ],
      },
    });
    await harness.prisma.chatMessage.create({
      data: {
        memoId: memo.id,
        author: "memo",
        kind: "text",
        text: "Tu m'as raconté 2 moments d'un coup. Tu préfères ?",
        model: "scripted",
        payload: { suggestions: ["split", "keep"], asksSplitFor: entry.id },
      },
    });

    await say(memo.id, SUGGESTIONS.split.label, { suggestionId: "split" });

    const parJour = await harness.prisma.entry.findMany({
      where: { memoId: memo.id },
      orderBy: { capturedAt: "asc" },
    });
    expect(parJour).toHaveLength(2);
    // Le 8 d'abord, bien qu'il ait été raconté en second.
    expect(parJour[0]?.transcript).toContain("Naples");
    expect(parJour[1]?.transcript).toContain("Colisée");
    expect(parJour.map((row) => row.capturedAt.toISOString().slice(0, 10))).toEqual([
      "2026-04-08",
      "2026-04-09",
    ]);
  });

  it("ne découpe rien tant qu'on n'a pas répondu", async () => {
    const memo = await seedTrip(owner.accountId);
    await toldWithSuggestion(memo.id);

    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);
  });

  /**
   * « Garde d'un seul tenant » : rien ne bouge, et il reste à valider le
   * texte. La proposition, elle, a fait son temps.
   */
  it("garde tout d'un seul tenant quand on refuse", async () => {
    const memo = await seedTrip(owner.accountId);
    await toldWithSuggestion(memo.id);

    await say(memo.id, SUGGESTIONS.keep.label, { suggestionId: "keep" });

    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);
    expect(memoBubbles(await readThread(memo.id)).at(-1)?.body).toEqual({
      kind: "text",
      text: SPLIT_REFUSED,
    });
  });

  /**
   * La question de la longueur (`LONG_MESSAGE`) ne vise aucun souvenir : on
   * ne coupe pas au jugé, et MEMO le dit plutôt que de trancher au milieu
   * d'une phrase.
   */
  it("refuse de couper quand aucune proposition ne tient", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, RECIT);

    await say(memo.id, SUGGESTIONS.split.label, { suggestionId: "split" });

    expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);
    expect(memoBubbles(await readThread(memo.id)).at(-1)?.body).toEqual({
      kind: "text",
      text: SPLIT_NOT_FOUND,
    });
  });
});

describe("revenir à l'étape sautée (Hugo, 12/10/2026)", () => {
  /**
   * Depuis que le texte est gardé d'office (03/11/2026), une étape sautée
   * n'est plus une étape à valider : c'est une étape **gardée mais jamais
   * illustrée**. MEMO y revient quand celle d'après est close, c'est-à-dire
   * à l'arrivée de ses photos.
   */
  it("à l'arrivée des photos de la seconde, MEMO revient à la première pour les siennes", async () => {
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, "On a passé la matinée au Colisée, il y avait un monde fou devant l'entrée.");
    // Le second récit, dans la foulée : le premier est gardé, mais pas illustré.
    await say(memo.id, "L'après-midi on a filé à Trastevere manger des supplì sur une petite place.");
    const [first, second] = await harness.prisma.entry.findMany({
      where: { memoId: memo.id },
      orderBy: { createdAt: "asc" },
    });
    expect(first?.validatedAt).not.toBeNull();
    expect(second?.validatedAt).not.toBeNull();

    // Les photos vont au second, le dernier dont MEMO les a demandées ; leur
    // arrivée clôt son étape, et MEMO revient à la première.
    await sendPhotos(memo.id, 2);
    const thread = await readThread(memo.id);
    const budget = photoBudgetFor((first!.editedText ?? first!.redactedText ?? "").trim(), memo);
    expect(memoBubbles(thread).slice(-2).map((message) => message.body)).toEqual([
      { kind: "text", text: PHOTOS_VALIDATED_BEFORE_RETURN },
      { kind: "text", text: returnForPhotos(1, first!.suggestedTitle, budget.photos, budget.pages) },
    ]);
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(
      expect.arrayContaining(["photos", "dictate"]),
    );

    // Ses photos vont dans **son** étape, et MEMO n'y revient pas deux fois.
    await sendPhotos(memo.id, 1);
    const steps = await readSteps(memo.id);
    expect(steps.map((step) => step.entryIds.length)).toEqual([2, 3]);
    const returns = memoBubbles(await readThread(memo.id)).filter(
      (message) => message.body.kind === "text" && message.body.text.startsWith("Revenons à"),
    );
    expect(returns).toHaveLength(1);
  });
});

describe("le contexte du voyage", () => {
  const lastMemoText = (thread: ChatThreadJson) => {
    const bubbles = memoBubbles(thread);
    const last = bubbles[bubbles.length - 1];
    return last?.body.kind === "text" ? last.body.text : null;
  };
  const chipIds = (thread: ChatThreadJson) => thread.suggestions.map((suggestion) => suggestion.id);

  it("se recueille ligne à ligne, sans créer de souvenir", async () => {
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

  it("se décompte du crédit du jour comme le reste du récit — sa puce d'entrée, non", async () => {
    // Plus d'exemption pour le contexte (Hugo, 03/10/2026) : c'est du récit,
    // et MEMO l'écoute. La puce « Je te raconte le contexte… », elle, est
    // gratuite, envoyée telle quelle.
    const memo = await seedTrip(owner.accountId);
    await say(memo.id, SUGGESTIONS.context.label, { suggestionId: "context" });
    const texts = ["Je pars seul", "Je pars de France", "En octobre", "Un trek", "Et j'adore marcher"];
    for (const text of texts) {
      const { response } = await say(memo.id, text);
      expect(response.statusCode).toBe(201);
    }
    const usage = await harness.prisma.tripDailyUsage.findFirstOrThrow({ where: { memoId: memo.id } });
    expect(usage.usedMs).toBe(texts.join("").length * TEXT_MS_PER_CHARACTER);
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
    expect(media.rawPayload.equals(VOICE_FIXTURES.short)).toBe(true);

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
  it("« Ça me convient » valide le souvenir, une seule fois, sans rien coûter", async () => {
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
    // La puce envoyée telle quelle ne prend rien au crédit : seul le vocal compte.
    const usageAfterAccept = await harness.prisma.tripDailyUsage.findFirstOrThrow({ where: { memoId: memo.id } });
    expect(usageAfterAccept.usedMs).toBe(usageAfterAccept.voiceMs);

    const thread = await readThread(memo.id);
    const card = thread.messages.find((message) => message.body.kind === "transcript");
    expect(card?.body.kind === "transcript" && card.body.transcript.isValidated).toBe(true);
    // Validé : MEMO demande le nombre exact de photos qui remplit l'étape.
    const budget = photoBudgetFor((validated.editedText ?? validated.redactedText ?? "").trim(), memo);
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
    expect(memoBubbles(withPhotos).at(-1)?.body).toEqual({ kind: "text", text: photosKept(budget.photos) });
    // Une commande se répond sans modèle.
    expect(responder.calls).toBe(callsBefore);

    // Valider deux fois ne repose pas la date.
    await say(memo.id, SUGGESTIONS.accept.label, { suggestionId: "accept", entryId: entry.id });
    const again = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(again.validatedAt).toEqual(validated.validatedAt);
  });

  it("réagir d’un 👍 vaut « Ça me convient », sans écrire une bulle de plus", async () => {
    // T296, Hugo du 28/11/2026 : « 👍 sur la question seule ». Le tour part
    // comme la puce qu'il est — il valide, MEMO répond avec des mots —, mais
    // il ne se dessine pas : seule la bulle visée porte le 👍.
    const memo = await seedTrip(owner.accountId);
    await sendVoice(memo.id);
    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    const before = await readThread(memo.id);
    const target = memoBubbles(before).at(-1)!;
    const bubblesBefore = before.messages.length;

    const { id, response } = await say(memo.id, SUGGESTIONS.accept.label, {
      suggestionId: "accept",
      entryId: entry.id,
      reactionTo: target.id,
    });
    expect(response.statusCode).toBe(201);
    // Le reçu ne rend aucune bulle pour ce tour-là : l'app n'a rien à poser.
    expect(response.json<{ messages: ChatMessageJson[] }>().messages.map((m) => m.id)).not.toContain(id);

    const validated = await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } });
    expect(validated.validatedAt).not.toBeNull();

    const after = await readThread(memo.id);
    expect(after.messages.find((message) => message.id === id)).toBeUndefined();
    expect(after.messages.find((message) => message.id === target.id)?.reaction).toEqual({
      emoji: "👍",
      label: "Tu as validé ce texte",
    });
    // Ce qui porte une information se dit toujours avec des mots : l'étape de
    // plus, et le nombre de photos (choix de Hugo, « seuls les accusés muets »).
    expect(memoBubbles(after).slice(-2)[0]?.body).toEqual({
      kind: "text",
      text: "C’est enregistré. Ton carnet compte une étape de plus.",
    });
    // Deux bulles de MEMO en plus, et pas une du voyageur.
    expect(after.messages.length).toBe(bubblesBefore + 2);
  });

  it("refuse un 👍 qui ne vaut pas « Ça me convient », ou qui vise une bulle du voyageur", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id: mine } = await say(memo.id, "On a marché jusqu’au port, il faisait doux.");
    const thread = await readThread(memo.id);
    const target = memoBubbles(thread).at(-1)!;

    // Sans la puce : une réaction décorative, et il n'y en a pas.
    const { response: sansPuce } = await say(memo.id, SUGGESTIONS.accept.label, { reactionTo: target.id });
    expect(sansPuce.statusCode).toBe(400);

    // Sur sa propre bulle : MEMO n'a rien demandé là.
    const { response: surSoi } = await say(memo.id, SUGGESTIONS.accept.label, {
      suggestionId: "accept",
      reactionTo: mine,
    });
    expect(surSoi.statusCode).toBe(400);
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

  it("« Photos de test » est une commande : gratuite, même crédit du jour épuisé", async () => {
    const memo = await seedTrip(owner.accountId);
    await exhaustCredit(memo.id);
    const { response } = await say(memo.id, SUGGESTIONS["photos-sample"].label, { suggestionId: "photos-sample" });
    expect(response.statusCode).toBe(201);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "photo" } })).toBe(1);
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: { not: "photo" } } })).toBe(0);
  });

  it("à crédit épuisé, un texte attend demain ; une puce passe toujours", async () => {
    const memo = await seedTrip(owner.accountId);
    await exhaustCredit(memo.id);

    const { response: refused } = await say(memo.id, "Un souvenir de plus, une longue journée.");
    expect(refused.statusCode).toBe(429);
    expect(refused.json<{ error: string }>().error).toBe("daily_credit_exhausted");

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

  /**
   * **Le sondage ne rattache plus tout l'historique** (19/11/2026) : il relit
   * le fil entier en version légère et n'hydrate que les messages qu'il rend.
   * Deux choses se calculent encore sur le fil entier — le numéro d'étape des
   * fiches et les puces — et ce test les tient : un sondage doit rendre
   * exactement ce qu'une ouverture rendrait au même instant.
   */
  it("sonde sans rien rattacher : mêmes puces et mêmes numéros d'étape qu'à l'ouverture", async () => {
    const memo = await seedTrip(owner.accountId);
    await tellFromHome(memo.id, "La pluie sur les pavés du Trastevere.", "2026-09-21T09:00:00.000Z");
    await readThread(memo.id);
    const repere = (await readThread(memo.id)).now;

    await new Promise((resolve) => setTimeout(resolve, 5));
    await tellFromHome(memo.id, "Le marché de Campo de' Fiori à midi.", "2026-09-22T09:00:00.000Z");

    const ouverture = await readThread(memo.id);
    const sondage = await readThread(memo.id, owner.authorization, repere);

    // La deuxième fiche est l'étape 2, et le sondage le sait aussi — c'est ce
    // que le fil entier sert à calculer.
    const titre = (thread: ChatThreadJson, index: number) => {
      const cards = thread.messages.filter((message) => message.body.kind === "transcript");
      const body = cards[index]?.body;
      return body?.kind === "transcript" ? body.transcript.title : null;
    };
    expect(titre(ouverture, 1)).toBe("Retranscription étape 2");
    expect(titre(sondage, 0)).toBe("Retranscription étape 2");

    // Les puces aussi : la fiche clôt le fil, le trio de validation suit.
    expect(ouverture.suggestions.map((suggestion) => suggestion.id)).toEqual([...SUGGESTION_SETS.trio]);
    expect(sondage.suggestions).toEqual(ouverture.suggestions);

    // Et une fois la fiche relue, les deux basculent ensemble.
    const entry = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id },
      orderBy: { capturedAt: "desc" },
    });
    const avantValidation = (await readThread(memo.id)).now;
    await new Promise((resolve) => setTimeout(resolve, 5));
    await harness.prisma.entry.update({ where: { id: entry.id }, data: { validatedAt: new Date() } });

    const relue = await readThread(memo.id);
    const sondageRelu = await readThread(memo.id, owner.authorization, avantValidation);
    expect(relue.suggestions.map((suggestion) => suggestion.id)).toEqual([...SUGGESTION_SETS.afterAccept]);
    expect(sondageRelu.suggestions).toEqual(relue.suggestions);
    // La fiche revient sans qu'aucun message n'ait été écrit : c'est
    // `entries.updatedAt` qui la ramène. Et il ramène **les deux bulles du
    // souvenir** — celle du voyageur et la fiche de MEMO —, parce que toutes
    // deux portent son `entryId` ; l'app remplace par identifiant, une bulle
    // inchangée de plus ne coûte donc rien.
    //
    // ⚠️ Ce n'est pas la lecture légère qui l'introduit : ce même test échoue
    // à l'identique sur le code d'avant (vérifié le 19/11/2026 en rejouant la
    // route de `main`). La promesse de la PR est que la réponse ne bouge pas,
    // et c'est **ça** qu'il faut tenir — d'où la paire, et son origine.
    const paire = await harness.prisma.chatMessage.findMany({
      where: { entryId: entry.id },
      orderBy: { seq: "asc" },
      select: { id: true },
    });
    expect(sondageRelu.messages.map((message) => message.body.kind)).toEqual(["text", "transcript"]);
    expect(sondageRelu.messages.map((message) => message.id)).toEqual(paire.map((row) => row.id));
  });

  /**
   * Le même garde-fou, mais pour les puces qui viennent du `payload` d'une
   * bulle de MEMO : c'est le champ que le sondage ne lit plus de la même
   * façon que l'ouverture, et celui où une divergence serait invisible.
   */
  it("sonde les mêmes puces que l'ouverture quand elles viennent d'une bulle de MEMO", async () => {
    const memo = await seedTrip(owner.accountId);
    const avant = await readThread(memo.id);
    await new Promise((resolve) => setTimeout(resolve, 5));
    await say(memo.id, "Une longue journée de marche dans les ruelles, pour commencer le voyage.");

    const ouverture = await readThread(memo.id);
    const sondage = await readThread(memo.id, owner.authorization, avant.now);
    expect(ouverture.suggestions.length).toBeGreaterThan(0);
    expect(sondage.suggestions).toEqual(ouverture.suggestions);

    // Et pendant le contexte du voyage, où les puces sont celles de la
    // dernière bulle de MEMO et rien d'autre.
    await harness.prisma.memo.update({
      where: { id: memo.id },
      data: { tripContext: { status: "gathering", awaiting: "travellerCount", companions: [] } },
    });
    const repere = (await readThread(memo.id)).now;
    await new Promise((resolve) => setTimeout(resolve, 5));
    await say(memo.id, "On est quatre, avec Fanny et les enfants.");

    const contexte = await readThread(memo.id);
    const sondageContexte = await readThread(memo.id, owner.authorization, repere);
    expect(sondageContexte.suggestions).toEqual(contexte.suggestions);
  });

  it("ferme la porte à un script, pas à un voyageur : 150 tours par jour", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id: sent } = await say(memo.id, "Le premier tour du jour.");
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

    // **L'idempotence passe avant le plafond** : la file hors ligne qui renvoie
    // un tour déjà arrivé reçoit 200, pas un refus qui le marquerait perdu.
    const { response: replay } = await say(memo.id, "Le premier tour du jour.", { id: sent });
    expect(replay.statusCode).toBe(200);
  });
});

/**
 * **Un tour dont le job n'est jamais parti** (03/10/2026) : le tour est écrit
 * et décompté, puis la file refuse sa publication (elle démarre encore après
 * un déploiement). La route rend 500, la file de l'app renvoie le même `id` —
 * et ce renvoi republie le job, au lieu d'un 200 qui laissait le tour payé
 * sans réponse ni souvenir.
 */
describe("le renvoi d'un tour dont le job n'est jamais parti", () => {
  const notStarted = () => new Error("La file de travaux n'a pas encore démarré. Réessaie dans un instant.");

  it("un texte : le renvoi republie la réponse de MEMO, une seule fois", async () => {
    const memo = await seedTrip(owner.accountId);
    const publish = vi.spyOn(harness.context.queue, "publish").mockRejectedValueOnce(notStarted());
    try {
      const text = "Une longue journée de marche dans les ruelles de Rome.";
      const { id, response } = await say(memo.id, text);
      expect(response.statusCode).toBe(500);
      const stranded = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
      expect(stranded).toMatchObject({ repliedAt: null, payload: { unqueued: true } });

      const { response: again } = await say(memo.id, text, { id });
      expect(again.statusCode).toBe(200);
      expect(again.json<{ turn: unknown }>().turn).toEqual({ status: "replying", messageId: id });
      const answered = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
      expect(answered.repliedAt).not.toBeNull();
      expect((answered.payload as Record<string, unknown> | null)?.["unqueued"]).toBeUndefined();
      expect(await harness.prisma.entry.count({ where: { memoId: memo.id } })).toBe(1);

      // La marque levée, un renvoi de plus ne republie rien.
      const calls = publish.mock.calls.length;
      expect((await say(memo.id, text, { id })).response.statusCode).toBe(200);
      expect(publish.mock.calls.length).toBe(calls);
    } finally {
      publish.mockRestore();
    }
  });

  it("un vocal : le renvoi republie sa transcription, et MEMO répond", async () => {
    const memo = await seedTrip(owner.accountId);
    const publish = vi.spyOn(harness.context.queue, "publish").mockRejectedValueOnce(notStarted());
    try {
      const { id, response } = await sendVoice(memo.id);
      expect(response.statusCode).toBe(500);
      const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id, kind: "audio" } });
      expect(entry.status).toBe("pending");

      const { response: again } = await sendVoice(memo.id, id);
      expect(again.statusCode).toBe(200);
      expect(publish.mock.calls.at(-1)?.[0]).toBe("memobook.converse");
      expect(publish.mock.calls.some(([name]) => name === "memobook.transcribe")).toBe(true);
      expect((await harness.prisma.entry.findUniqueOrThrow({ where: { id: entry.id } })).status).toBe("ready");
      expect((await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } })).repliedAt).not.toBeNull();
    } finally {
      publish.mockRestore();
    }
  });

  it("si la file refuse encore, le renvoi rend 503 et garde la marque pour le suivant", async () => {
    const memo = await seedTrip(owner.accountId);
    const publish = vi
      .spyOn(harness.context.queue, "publish")
      .mockRejectedValueOnce(notStarted())
      .mockRejectedValueOnce(notStarted());
    try {
      const text = "Une soirée sur la terrasse, à regarder les toits.";
      const { id } = await say(memo.id, text);

      const { response: refused } = await say(memo.id, text, { id });
      expect(refused.statusCode).toBe(503);
      expect(refused.json<{ error: string }>().error).toBe("turn_not_queued");
      expect((await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } })).payload).toEqual({
        unqueued: true,
      });

      expect((await say(memo.id, text, { id })).response.statusCode).toBe(200);
      expect((await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } })).repliedAt).not.toBeNull();
    } finally {
      publish.mockRestore();
    }
  });
});

describe("l'étape manquante", () => {
  /** Un voyage troué : raconté J-5, J-4 et J-2, rien le J-3. */
  async function seedHoledTrip() {
    const memo = await seedTrip(owner.accountId);
    // **Un carnet sans photos** : chaque récit gardé d'office (03/11/2026)
    // réclamerait les siennes, et à l'arrivée de la première photo MEMO
    // reviendrait d'abord à l'étape J-4 restée sans images (`stepToClose`) —
    // une relance qui passe avant la carte, jamais deux d'affilée. À 0 %,
    // aucune photo n'est demandée : il ne reste que le trou.
    await harness.prisma.memo.update({ where: { id: memo.id }, data: { photoTextRatio: 0 } });
    const day = (back: number) => {
      const date = new Date();
      date.setUTCDate(date.getUTCDate() - back);
      date.setUTCHours(10, 0, 0, 0);
      return date;
    };
    await harness.prisma.memo.update({
      where: { id: memo.id },
      data: { startDate: day(6), narrationPace: "daily" },
    });
    // Les souvenirs passent par le fil, puis on les **redate** : un souvenir
    // posé en base sans son tour laisserait un message sans réponse, que le
    // tour suivant attendrait vingt secondes (`waitForOlderUnansweredTurns`).
    for (const back of [5, 4, 2]) {
      const { id } = await say(memo.id, `Le récit du jour J-${back}, à Rome.`);
      const turn = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
      // Validés : une étape non terminée a sa propre relance (`stepToClose`),
      // et elle passe avant — jamais deux dans le même tour.
      await harness.prisma.entry.update({
        where: { id: turn.entryId! },
        data: { capturedAt: day(back), validatedAt: day(back) },
      });
    }
    return { memo, missing: localDate(day(3), "Europe/Paris") };
  }

  /**
   * **L'arrivée des photos** — le seul moment où la carte peut tomber. Elle
   * vaut validation depuis le 03/11/2026 : plus de « Je valide mes photos »
   * derrière, qui ferait un tour de plus et compterait la carte comme refusée.
   */
  async function validatePhotos(memoId: string) {
    const { payload, contentType } = await multipartPhotos(randomUUID(), 1);
    await harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memoId}/chat`,
      headers: { authorization: owner.authorization, "content-type": contentType },
      payload,
    });
  }

  const stateOf = async (memoId: string) =>
    parseConversationState(
      (await harness.prisma.memo.findUniqueOrThrow({ where: { id: memoId } })).conversationState,
    );

  it("pose la carte après les photos, sans voler les puces de la bulle d'avant", async () => {
    const { memo, missing } = await seedHoledTrip();
    await validatePhotos(memo.id);

    const thread = await readThread(memo.id);
    const last = memoBubbles(thread).at(-1);
    expect(last?.callToAction?.id).toBe("fill_missing_day");
    expect(last?.body.kind === "text" && last.body.text).toContain(longDay(missing));
    // ⚠️ Le bouton **est** la question : la bulle n'en pose aucune.
    expect(last?.body.kind === "text" && last.body.text).not.toContain("?");
    // La carte ne porte pas de puces : celles de la bulle des photos restent
    // en place, et c'est ce qui casserait en silence.
    expect(thread.suggestions.map((suggestion) => suggestion.id)).toEqual(["photos-more", "preview", "dictate"]);

    const state = await stateOf(memo.id);
    expect(state.gapOffered?.days).toEqual([missing]);
  });

  it("le bouton est une commande : aucun souvenir, et la journée s'ouvre", async () => {
    const { memo, missing } = await seedHoledTrip();
    await validatePhotos(memo.id);

    const before = await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "text" } });
    const { id } = await say(memo.id, SUGGESTIONS["fill-missing-day"].label, {
      suggestionId: "fill-missing-day",
    });

    const sent = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
    expect(sent.disposition).toBe("command");
    expect(await harness.prisma.entry.count({ where: { memoId: memo.id, kind: "text" } })).toBe(before);

    const thread = await readThread(memo.id);
    expect(memoBubbles(thread).at(-1)?.body).toEqual({ kind: "text", text: missingDayListening(missing) });

    const state = await stateOf(memo.id);
    expect(state.tellingDay?.day).toBe(missing);
    expect(state.gapOffered).toBeNull();
    expect(state.gapAskedFor).toEqual([missing]);
  });

  it("date le souvenir suivant sur la journée du trou, puis referme le mode", async () => {
    const { memo, missing } = await seedHoledTrip();
    await validatePhotos(memo.id);
    await say(memo.id, SUGGESTIONS["fill-missing-day"].label, { suggestionId: "fill-missing-day" });

    await say(memo.id, "On a passé la journée à marcher dans le Trastevere, sans plan.");

    const entry = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id, kind: "text" },
      orderBy: { createdAt: "desc" },
    });
    expect(localDate(entry.capturedAt, "Europe/Paris")).toBe(missing);
    expect((await stateOf(memo.id)).tellingDay).toBeNull();
  });

  it("compte un refus quand la proposition reste sans suite, et se tait au deuxième", async () => {
    const { memo } = await seedHoledTrip();
    await validatePhotos(memo.id);

    // Le silence vaut refus : on continue à raconter, sans toucher la carte.
    await say(memo.id, "Et le lendemain, on a pris le train pour Naples.");
    expect((await stateOf(memo.id)).gapDeclines).toBe(1);
    expect((await stateOf(memo.id)).gapOffered).toBeNull();

    // Le registre a retenu la journée : elle n'est jamais reproposée.
    await validatePhotos(memo.id);
    const thread = await readThread(memo.id);
    expect(memoBubbles(thread).at(-1)?.callToAction?.id).toBeUndefined();
  });

  it("ne dit rien quand le voyageur raconte à son rythme", async () => {
    const { memo } = await seedHoledTrip();
    await harness.prisma.memo.update({ where: { id: memo.id }, data: { narrationPace: "weekly" } });
    await validatePhotos(memo.id);

    const thread = await readThread(memo.id);
    expect(memoBubbles(thread).at(-1)?.callToAction?.id).toBeUndefined();
  });
});

/**
 * **L'appui long sur une bulle** — T270. Le menu lui-même est de l'app ;
 * côté serveur, deux gestes seulement : déplacer une bulle de photos dans une
 * autre étape, et supprimer un souvenir sans laisser sa bulle vide derrière.
 */
describe("le menu d'une bulle", () => {
  /** Le voyage, ses deux étapes (deux récits, deux jours), et une bulle de photos. */
  async function seedTwoStepTrip() {
    const memo = await seedTrip(owner.accountId);
    await tellFromHome(memo.id, "La pluie sur les pavés du Trastevere.", "2026-09-21T09:00:00.000Z");
    await tellFromHome(memo.id, "Le Panthéon, enfin, et sans la queue.", "2026-09-24T09:00:00.000Z");
    await readThread(memo.id);
    const messageId = await sendPhotos(memo.id, 2);
    await refreshTripFacts(harness.prisma, memo.id);

    const steps = await harness.prisma.memoStep.findMany({
      where: { memoId: memo.id },
      orderBy: { number: "asc" },
    });
    expect(steps.length).toBeGreaterThanOrEqual(2);
    const message = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id: messageId } });
    // L'étape d'arrivée est celle où les photos ne sont pas : c'est tout ce
    // que le test demande, et ça ne dépend donc pas du découpage.
    const target = steps.find((step) => step.id !== message.stepId);
    expect(target).toBeDefined();
    return { memo, messageId, target: target!, steps };
  }

  async function move(memoId: string, messageId: string, stepId: string, authorization = owner.authorization) {
    return harness.app.inject({
      method: "POST",
      url: `/v1/trips/${memoId}/chat/${messageId}/step`,
      headers: { authorization },
      payload: { stepId },
    });
  }

  /**
   * ⚠️ **Le vrai test est le recalcul qui suit.** Écrire l'étape sur le
   * souvenir ne suffirait pas : le découpage la reprendrait d'après la date et
   * le lieu de la photo. C'est l'épingle posée sur la **bulle** que
   * `pinnedSteps` fait passer devant — et c'est elle qu'on vérifie en
   * relançant `refreshTripFacts` après coup.
   */
  it("déplace une bulle de photos, et l'épingle tient au recalcul", async () => {
    const { memo, messageId, target } = await seedTwoStepTrip();

    const response = await move(memo.id, messageId, target.id);
    expect(response.statusCode).toBe(204);

    await refreshTripFacts(harness.prisma, memo.id);

    const moved = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id: messageId } });
    expect(moved.stepId).toBe(target.id);
    const photos = await harness.prisma.entry.findMany({ where: { memoId: memo.id, kind: "photo" } });
    expect(photos).toHaveLength(2);
    expect(photos.map((photo) => photo.stepId)).toEqual([target.id, target.id]);
  });

  /** Les deux photos d'une bulle s'en vont ensemble : on appuie sur la bulle. */
  it("emmène toutes les photos de la bulle", async () => {
    const { memo, messageId, target } = await seedTwoStepTrip();
    await move(memo.id, messageId, target.id);

    const thread = await readThread(memo.id);
    const bubble = thread.messages.find((message) => message.id === messageId);
    expect(bubble?.stepId).toBe(target.id);
    expect(bubble?.body.kind === "photos" && bubble.body.photos).toHaveLength(2);
  });

  /**
   * **Un récit se déplace aussi** (19/11/2026) — et c'est `entries.pinnedStepId`
   * qui le permet. Le test ne prouve rien tant qu'il n'a pas relancé
   * `refreshTripFacts` : sans l'épingle, le découpage rendrait le récit à son
   * étape d'origine, d'après sa date et son lieu, sans rien dire.
   */
  it("déplace un récit, et l'épingle tient au recalcul", async () => {
    const { memo, target, messageId: photosId } = await seedTwoStepTrip();

    // Le récit de la **première** étape : la bulle du voyageur que la lecture
    // du fil a reposée depuis son souvenir. Pas un texte envoyé ici — celui-là
    // serait classé « précision » et viserait la fiche d'un autre souvenir.
    const thread = await readThread(memo.id);
    const story = thread.messages.find(
      (message) => message.author === "traveller" && message.body.kind === "text" && message.id !== photosId,
    );
    expect(story).toBeDefined();
    const id = story!.id;

    const response = await move(memo.id, id, target.id);
    expect(response.statusCode).toBe(204);

    await refreshTripFacts(harness.prisma, memo.id);

    const message = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id } });
    const entry = await harness.prisma.entry.findUniqueOrThrow({
      where: { id: message.entryId ?? "" },
    });
    expect(entry.pinnedStepId).toBe(target.id);
    expect(entry.stepId).toBe(target.id);
  });

  /** Une bulle de MEMO n'est pas un souvenir : elle n'a pas d'étape à elle. */
  it("refuse de déplacer ce qui n'est pas un souvenir", async () => {
    const { memo, target } = await seedTwoStepTrip();
    const thread = await readThread(memo.id);
    const fromMemo = thread.messages.find((message) => message.author === "memo");
    expect(fromMemo).toBeDefined();

    const response = await move(memo.id, fromMemo!.id, target.id);
    expect(response.statusCode).toBe(400);
    expect(response.json<{ message: string }>().message).toContain("souvenir");
  });

  it("refuse une étape qui n'est pas celle de ce voyage", async () => {
    const { memo, messageId } = await seedTwoStepTrip();
    const ailleurs = await seedTrip(owner.accountId);
    const step = await harness.prisma.memoStep.create({
      data: { memoId: ailleurs.id, number: 1, placeName: "Naples" },
    });

    expect((await move(memo.id, messageId, step.id)).statusCode).toBe(404);
    // Et la bulle n'a pas bougé.
    const message = await harness.prisma.chatMessage.findUniqueOrThrow({ where: { id: messageId } });
    expect(message.stepId).not.toBe(step.id);
  });

  it("sert les étapes du voyage avec le fil, pour la liste du menu", async () => {
    const { memo, steps } = await seedTwoStepTrip();

    const thread = await readThread(memo.id);
    expect(thread.context.steps.map((step) => step.id)).toEqual(steps.map((step) => step.id));
    expect(thread.context.steps.map((step) => step.number)).toEqual(steps.map((step) => step.number));
  });

  /**
   * ⚠️ Sans le ménage de `forgetBubblesOf`, la bulle restait dans le fil
   * **vidée de ce qu'elle montrait** : des adresses de photos sans réponse.
   * La fiche, elle, disparaissait déjà seule — c'est ce qui masquait le reste.
   */
  it("retire d'une bulle la photo supprimée, et la bulle quand il n'en reste aucune", async () => {
    const memo = await seedTrip(owner.accountId);
    await readThread(memo.id);
    const messageId = await sendPhotos(memo.id, 3);

    const avant = await readThread(memo.id);
    const bubble = avant.messages.find((message) => message.id === messageId);
    const photos = bubble?.body.kind === "photos" ? bubble.body.photos.map((photo) => photo.id) : [];
    expect(photos).toHaveLength(3);

    const effacer = async (entryId: string) => {
      const response = await harness.app.inject({
        method: "DELETE",
        url: `/v1/entries/${entryId}`,
        headers: { authorization: owner.authorization },
      });
      expect(response.statusCode).toBe(204);
    };

    // La première part : la bulle garde les deux autres, et change de première.
    await effacer(photos[0]!);
    const apresUne = await readThread(memo.id);
    const restante = apresUne.messages.find((message) => message.id === messageId);
    expect(restante?.body.kind === "photos" && restante.body.photos.map((photo) => photo.id)).toEqual([
      photos[1],
      photos[2],
    ]);
    expect(restante?.entryId).toBe(photos[1]);

    // Les deux autres parties, la bulle n'a plus rien à montrer.
    await effacer(photos[1]!);
    await effacer(photos[2]!);
    const apresToutes = await readThread(memo.id);
    expect(apresToutes.messages.some((message) => message.id === messageId)).toBe(false);
  });

  it("efface la bulle d'un récit supprimé, et sa fiche", async () => {
    const memo = await seedTrip(owner.accountId);
    const { id: bubbleId } = await say(memo.id, "On a marché jusqu'au Janicule pour voir le coucher.");

    const entry = await harness.prisma.entry.findFirstOrThrow({ where: { memoId: memo.id } });
    const response = await harness.app.inject({
      method: "DELETE",
      url: `/v1/entries/${entry.id}`,
      headers: { authorization: owner.authorization },
    });
    expect(response.statusCode).toBe(204);

    const thread = await readThread(memo.id);
    expect(thread.messages.some((message) => message.id === bubbleId)).toBe(false);
    expect(thread.messages.some((message) => message.body.kind === "transcript")).toBe(false);
  });
});

/**
 * **Les deux photos principales** — T270, les étoiles verte et lime.
 *
 * Ce qui se teste ici n'est pas l'étoile (elle est dessinée dans l'app) mais
 * ce qu'elle change : la vignette de l'étape, la photo du voyage, et ce que le
 * fil dit de chaque photo.
 */
describe("les deux photos principales", () => {
  /** Un voyage, une étape, deux photos dont on connaît les identifiants. */
  async function seedPhotographedTrip() {
    const memo = await seedTrip(owner.accountId);
    await tellFromHome(memo.id, "La pluie sur les pavés du Trastevere.", "2026-09-21T09:00:00.000Z");
    await readThread(memo.id);
    const messageId = await sendPhotos(memo.id, 2);
    await refreshTripFacts(harness.prisma, memo.id);

    const photos = await harness.prisma.entry.findMany({
      where: { memoId: memo.id, kind: "photo" },
      orderBy: { createdAt: "asc" },
      select: { id: true, mediaId: true, stepId: true },
    });
    expect(photos).toHaveLength(2);
    // La vignette d'une étape se lit sur le CDN : sans adresse, aucune photo
    // ne peut l'être, élue ou non.
    for (const [index, photo] of photos.entries()) {
      await harness.prisma.mediaAsset.update({
        where: { id: photo.mediaId ?? "" },
        data: { cdnUrl: `https://cdn.test/photo-${index}.jpg` },
      });
    }
    const step = await harness.prisma.memoStep.findFirstOrThrow({ where: { memoId: memo.id } });
    return { memo, messageId, photos, step };
  }

  const electStep = (memoId: string, stepId: string, entryId: string | null) =>
    harness.app.inject({
      method: "PUT",
      url: `/v1/trips/${memoId}/steps/${stepId}/cover-photo`,
      headers: { authorization: owner.authorization },
      payload: { entryId },
    });

  const electTrip = (memoId: string, entryId: string | null) =>
    harness.app.inject({
      method: "PUT",
      url: `/v1/trips/${memoId}/cover-photo`,
      headers: { authorization: owner.authorization },
      payload: { entryId },
    });

  /**
   * ⚠️ Le choix se range dans `coverEntryId`, **pas** dans `photoUrl` :
   * celle-là est recalculée à chaque passage de `refreshTripFacts`. Le test
   * relance donc le calcul, sans quoi il ne prouverait rien.
   */
  it("l'étoile de l'étape décide de sa vignette, et le calcul la respecte", async () => {
    const { memo, photos, step } = await seedPhotographedTrip();
    const seconde = photos[1]!;

    const response = await electStep(memo.id, step.id, seconde.id);
    expect(response.statusCode).toBe(200);

    await refreshTripFacts(harness.prisma, memo.id);

    const after = await harness.prisma.memoStep.findUniqueOrThrow({ where: { id: step.id } });
    expect(after.coverEntryId).toBe(seconde.id);
    expect(after.photoUrl).toBe("https://cdn.test/photo-1.jpg");
  });

  it("l'étoile se défait, et l'étape reprend son élection automatique", async () => {
    const { memo, photos, step } = await seedPhotographedTrip();
    await electStep(memo.id, step.id, photos[1]!.id);
    await refreshTripFacts(harness.prisma, memo.id);

    expect((await electStep(memo.id, step.id, null)).statusCode).toBe(200);
    await refreshTripFacts(harness.prisma, memo.id);

    const after = await harness.prisma.memoStep.findUniqueOrThrow({ where: { id: step.id } });
    expect(after.coverEntryId).toBeNull();
    expect(after.photoUrl).toBe("https://cdn.test/photo-0.jpg");
  });

  it("refuse une photo qui n'est pas dans cette étape", async () => {
    const { memo, step } = await seedPhotographedTrip();
    const ailleurs = await seedTrip(owner.accountId);
    await readThread(ailleurs.id);
    await sendPhotos(ailleurs.id, 1);
    const autre = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: ailleurs.id, kind: "photo" },
    });

    // Photo d'un autre voyage : introuvable, et on ne dit pas qu'elle existe.
    expect((await electStep(memo.id, step.id, autre.id)).statusCode).toBe(404);
  });

  /**
   * La couverture composée dans l'atelier passe devant l'étoile : élire une
   * photo du fil ne doit pas effacer en silence ce qu'on a composé.
   */
  it("l'étoile du voyage donne sa photo, derrière la couverture de l'atelier", async () => {
    const { memo, photos } = await seedPhotographedTrip();

    expect((await electTrip(memo.id, photos[1]!.id)).statusCode).toBe(200);
    const elue = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}`,
      headers: { authorization: owner.authorization },
    });
    expect(elue.json<{ trip: { coverPhotoUrl: string | null } }>().trip.coverPhotoUrl).toBe(
      "https://cdn.test/photo-1.jpg",
    );

    await harness.prisma.memo.update({
      where: { id: memo.id },
      data: { coverPhotoUrl: "https://cdn.test/atelier.jpg" },
    });
    const composee = await harness.app.inject({
      method: "GET",
      url: `/v1/trips/${memo.id}`,
      headers: { authorization: owner.authorization },
    });
    expect(composee.json<{ trip: { coverPhotoUrl: string | null } }>().trip.coverPhotoUrl).toBe(
      "https://cdn.test/atelier.jpg",
    );
  });

  it("le fil dit quelle photo porte quelle étoile", async () => {
    const { memo, messageId, photos, step } = await seedPhotographedTrip();
    await electStep(memo.id, step.id, photos[0]!.id);
    await electTrip(memo.id, photos[0]!.id);

    const thread = await readThread(memo.id);
    const bubble = thread.messages.find((message) => message.id === messageId);
    expect(bubble?.body.kind).toBe("photos");
    if (bubble?.body.kind !== "photos") return;
    expect(bubble.body.photos.map((photo) => [photo.isStepCover, photo.isTripCover])).toEqual([
      [true, true],
      [false, false],
    ]);
  });
});

/**
 * **Ce qu'une photo sait d'elle-même** (T280, 20/11/2026).
 *
 * Un envoi porte jusqu'à quatre photos et n'avait qu'**une** date pour toutes.
 * Chacune porte maintenant la sienne, et le lieu lu sur elle — géocodé sur le
 * téléphone, aucune coordonnée ne sort de l'appareil.
 */
describe("le lieu et le jour que chaque photo porte", () => {
  it("garde la date de chaque photo, et non celle de l'envoi", async () => {
    const memo = await seedTrip(owner.accountId);
    await sendPhotos(memo.id, 2, undefined, [
      { capturedAt: "2026-04-08T10:00:00.000Z", capturedPlaceName: "Kanazawa" },
      { capturedAt: "2026-04-11T10:00:00.000Z", capturedPlaceName: "Takayama" },
    ]);

    const photos = await harness.prisma.entry.findMany({
      where: { memoId: memo.id, kind: "photo" },
      orderBy: { capturedAt: "asc" },
      select: { capturedAt: true, capturedPlaceName: true },
    });
    expect(photos.map((row) => row.capturedAt.toISOString().slice(0, 10))).toEqual([
      "2026-04-08",
      "2026-04-11",
    ]);
    expect(photos.map((row) => row.capturedPlaceName)).toEqual(["Kanazawa", "Takayama"]);
  });

  it("sans le champ, l'envoi date comme avant — une app plus ancienne ne casse rien", async () => {
    const memo = await seedTrip(owner.accountId);
    await sendPhotos(memo.id, 2);

    const photos = await harness.prisma.entry.findMany({
      where: { memoId: memo.id, kind: "photo" },
      select: { capturedAt: true, capturedPlaceName: true },
    });
    expect(photos).toHaveLength(2);
    expect(new Set(photos.map((row) => row.capturedAt.getTime())).size).toBe(1);
    expect(photos.every((row) => row.capturedPlaceName === null)).toBe(true);
  });

  it("une entrée fautive laisse sa photo sans rien, et les autres passent", async () => {
    const memo = await seedTrip(owner.accountId);
    await sendPhotos(memo.id, 2, undefined, [
      { capturedAt: "pas une date", capturedPlaceName: "   " },
      { capturedAt: "2026-04-11T10:00:00.000Z", capturedPlaceName: "Takayama" },
    ]);

    const photos = await harness.prisma.entry.findMany({
      where: { memoId: memo.id, kind: "photo" },
      select: { capturedPlaceName: true },
    });
    // Les deux sont créées dans la même transaction : leur ordre de retour
    // n'est pas garanti, et ce n'est pas lui que le test regarde.
    expect(photos.map((row) => row.capturedPlaceName).sort()).toEqual(["Takayama", null]);
  });
});

/**
 * **« Ça s'écrit comment ? »** (T282, Hugo, 05/11/2026 — « faire valider les
 * noms propres, surtout ceux des amis : “Kom” au lieu de “Come” »).
 *
 * Un prénom imprimé au jugé entre dans la fiche de cohérence, et le carnet le
 * répète sur soixante pages.
 */
describe("faire valider un nom propre", () => {
  const textOf = (thread: ChatThreadJson) =>
    memoBubbles(thread).map((message) => (message.body.kind === "text" ? message.body.text : ""));

  it("pose la question au lieu de garder le texte d'office", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.namesToConfirm = ["Kom"];

    await say(memo.id, "On a retrouvé Kom au port, il nous attendait depuis une heure.");

    const bulles = textOf(await readThread(memo.id));
    const question = bulles.find((text) => text.includes("Kom"));
    expect(question, `Aucune question sur le prénom : ${bulles.join(" | ")}`).toBeTruthy();
    expect(question).toContain("Tu me le réécris comme il faut ?");
    // La bulle « Voilà ton texte » ne se pose pas : on ne garde pas d'office
    // un texte dont un prénom est peut-être faux.
    expect(bulles).not.toContain(redactionKept());
  });

  it("ne demande rien quand l'écrivain ne doute d'aucun nom", async () => {
    const memo = await seedTrip(owner.accountId);

    await say(memo.id, "On a retrouvé Clairette au port.");

    const bulles = textOf(await readThread(memo.id));
    expect(bulles).toContain(redactionKept());
    expect(bulles.some((text) => text.includes("réécris"))).toBe(false);
  });

  it("la réponse du voyageur atteint le texte, comme une précision", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.namesToConfirm = ["Kom"];
    await say(memo.id, "On a retrouvé Kom au port, il nous attendait depuis une heure.");

    // Plus de doute à la relance : le nom est réglé.
    redactor.namesToConfirm = [];
    await say(memo.id, "C’est Côme, avec un accent.");

    const entry = await harness.prisma.entry.findFirstOrThrow({
      where: { memoId: memo.id, kind: "text" },
      orderBy: { createdAt: "asc" },
    });
    // Le faux rédacteur recopie les précisions dans le texte : c'est ainsi
    // qu'on voit qu'elle a bien atteint la rédaction.
    expect(entry.redactedText ?? "").toContain("Côme");
  });
});

/**
 * **« On était où ? »** (T267, Hugo, 05/11/2026 — « des en-têtes sans lieu »).
 *
 * Mesuré le 18/11 sur un vrai carnet : 15 journées sur 35 sans lieu, dont 7
 * rattrapées en retombant sur celui de l'étape (T227). Les 6 autres, personne
 * ne peut les deviner — et c'est là que MEMO doit demander, au lieu
 * d'imprimer une date seule.
 */
describe("demander où on était", () => {
  const textOf = (thread: ChatThreadJson) =>
    memoBubbles(thread).map((message) => (message.body.kind === "text" ? message.body.text : ""));
  const laQuestion = (bulles: string[]) => bulles.find((text) => text.includes("je ne sais pas où on était"));

  it("demande le lieu quand ni le récit ni les photos ne le disent", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.place = null;

    await say(memo.id, "On s’est levés tard, on a traîné au marché et on a mangé des beignets.");

    const bulles = textOf(await readThread(memo.id));
    const question = laQuestion(bulles);
    expect(question, `Aucune question sur le lieu : ${bulles.join(" | ")}`).toBeTruthy();
    expect(question).toContain("Tu me dis la ville");
    // Elle dit ce qui se passe sinon : une question sans enjeu se remet à
    // plus tard.
    expect(question).toContain("sa date seule");
    // Et la bulle « Voilà ton texte » ne se pose pas : elle **valide** le
    // souvenir, et un souvenir validé n'accepte plus de précision — la réponse
    // n'aurait alors nulle part où aller. Elle vient après, quand l'étape a un
    // nom. C'est la règle du prénom (T282), pour la même raison.
    expect(bulles).not.toContain(redactionKept());
  });

  it("ne demande rien quand le récit dit où on était", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.place = "Kanazawa";

    await say(memo.id, "Journée à flâner dans les ruelles, c’était magnifique.");

    const bulles = textOf(await readThread(memo.id));
    expect(laQuestion(bulles), `Question de trop : ${bulles.join(" | ")}`).toBeUndefined();
    const step = await harness.prisma.memoStep.findFirstOrThrow({ where: { memoId: memo.id } });
    expect(step.placeName).toBe("Kanazawa");
  });

  it("ne la pose qu’une fois, même si l’étape reçoit d’autres souvenirs", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.place = null;

    await say(memo.id, "On s’est levés tard et on a traîné au marché.");
    await say(memo.id, "Et le soir on a mangé des beignets, encore.");

    const bulles = textOf(await readThread(memo.id));
    const posees = bulles.filter((text) => text.includes("je ne sais pas où on était"));
    expect(posees.length, `Posée ${posees.length} fois : ${bulles.join(" | ")}`).toBe(1);
  });

  it("la réponse du voyageur nomme l’étape, comme une précision", async () => {
    const memo = await seedTrip(owner.accountId);
    redactor.place = null;
    await say(memo.id, "On s’est levés tard et on a traîné au marché.");
    expect(laQuestion(textOf(await readThread(memo.id)))).toBeTruthy();

    // Le voyageur répond : la rédaction repasse, et cette fois le récit sait
    // où il se passe.
    redactor.place = "Kanazawa";
    await say(memo.id, "On était à Kanazawa.");

    const steps = await harness.prisma.memoStep.findMany({ where: { memoId: memo.id } });
    expect(
      steps.some((step) => step.placeName === "Kanazawa"),
      `Aucune étape nommée : ${JSON.stringify(steps.map((step) => step.placeName))}`,
    ).toBe(true);
    // Et le souvenir est gardé, maintenant que l'étape a un nom.
    const bulles = textOf(await readThread(memo.id));
    expect(bulles).toContain(redactionKept());
  });
});
