import { Prisma, type Account, type ChatMessage } from "@prisma/client";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type ConverseJob, type TranscribeJob } from "../jobs/index.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { appPlatformOf, platformPayload } from "../services/appPlatform.js";
import { publicApiBaseUrl } from "../services/avatars.js";
import {
  chargeDailyCredit,
  recordVoiceCharge,
  countCharacters,
  exceedsDailyCredit,
  holdsRefusedTurns,
  isFreeChatText,
  loadSpeaker,
  measureVoiceMs,
  readDailyCredit,
  refuseForDailyCredit,
  withDailyCredit,
  type DailyCharge,
  type DailyCredit,
} from "../services/dailyCredit.js";
import { pauseBeforeTranscript, scriptedReply } from "../services/conversation.js";
import {
  FLOW_COMMANDS,
  isCommandId,
  isGapDayId,
  suggestionIdForLabel,
} from "../services/conversationCopy.js";
import {
  activeStepOf,
  chatMessageInclude,
  dailyTurnCount,
  ensureOpening,
  findTurnInFlight,
  loadCurrentEntry,
  loadPhotoSizes,
  lockThread,
  photosTargetEntryId,
  materializeEntriesWithoutMessages,
  type ChatMessageRow,
} from "../services/conversationThread.js";
import { ORAL_CORRECTION_TOPIC } from "../services/redaction.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { loadVisibleMemo } from "./memos.js";
import { refreshTripFactsQuietly } from "../services/tripFacts.js";
import { MAX_PHOTOS_PER_STEP } from "../services/photoBudget.js";
import { measurePhoto } from "../services/photoOrientation.js";
import { isRenderableImage, toRenderablePhoto } from "../services/photoFormat.js";
import { storeScreenThumbnail } from "../services/photoThumbnails.js";
import { coverPhotoInclude } from "./tripPhotos.js";
import { hasUnlimitedAccess } from "../services/subscriptions.js";
import { contextVoiceOf, isGathering, parseTripContext } from "../services/tripContext.js";
import {
  serializeChatReceipt,
  serializeChatThread,
  serializeChatUpdate,
  reactionTargetOf,
  suggestionIdsOf,
  type ChatTurnStatus,
  type MemoForChat,
  type ThreadOutlineRow,
} from "./chatSerializers.js";

/**
 * La conversation avec MEMO — `docs/conversation.md`.
 *
 * Trois routes : lire le fil, y parler, l'effacer. Le fil se lit **au champ
 * près** des modèles Swift (`chatSerializers.ts`) ; y parler écrit le message
 * du voyageur tout de suite et laisse le job `converse` répondre ; l'effacer
 * n'appartient qu'au propriétaire.
 *
 * L'accès passe par `visibleToAccount` : un co-voyageur lit et parle comme le
 * propriétaire, quelqu'un qui n'y participe pas reçoit un 404.
 */

const idParams = z.object({ id: z.string().uuid() });

const threadQuery = z.object({
  /** Le curseur du sondage : le `now` de la lecture précédente, en temps serveur. */
  since: z.string().datetime({ offset: true }).optional(),
});

/** « Déplacer dans une autre étape » : le voyage, et la bulle qui s'en va. */
const moveParams = z.object({ id: z.string().uuid(), messageId: z.string().uuid() });

/** L'étape d'arrivée. Jamais nulle : on déplace **vers** une étape. */
const moveBody = z.object({ stepId: z.string().uuid() });

/**
 * Un texte, ou une puce. `id` est **fourni par l'app** et devient l'identifiant
 * du message : la bulle optimiste et la bulle servie sont la même, et un
 * renvoi après une panne de transport tombe sur l'existant au lieu de créer
 * un doublon — c'est l'idempotence de la file hors ligne pour rien.
 */
const textTurnBody = z.object({
  id: z.string().uuid(),
  kind: z.literal("text"),
  text: z.string().max(20_000).default(""),
  stepId: z.string().uuid().nullable().optional(),
  suggestionId: z.string().max(64).nullable().optional(),
  /** Le souvenir visé par « Ça me convient ». */
  entryId: z.string().uuid().nullable().optional(),
  /**
   * **La bulle de MEMO sur laquelle le voyageur a posé un 👍** (T296) :
   * réagir vaut « Ça me convient », sans écrire.
   *
   * Le tour part donc comme la puce qu'il est — il valide le souvenir, MEMO
   * lui répond, le crédit n'est pas touché —, mais il ne se dessine pas :
   * c'est le 👍 posé sur la bulle visée qui en reste
   * (`chatSerializers.reactionTargetOf`).
   */
  reactionTo: z.string().uuid().nullable().optional(),
  /**
   * **Le moment où le voyageur a posé ce tour** (T309), et non celui où il
   * arrive : c'est lui qui range la bulle dans le fil. Absent d'une app
   * d'avant le 26/11/2026 — la bulle se range alors à son arrivée, comme
   * avant.
   */
  postedAt: z.string().datetime({ offset: true }).optional(),
});

/**
 * **L'instant que l'app annonce, tenu à distance de l'absurde** (T309).
 *
 * Il range la bulle dans le fil : une date fautive la poserait au début du
 * carnet, ou après tout le reste. On n'accepte donc qu'un instant **passé**
 * et pas plus vieux qu'un an — au-delà, c'est une horloge déréglée ou un
 * client malveillant, et l'arrivée fait foi, comme pour une app qui n'envoie
 * rien.
 */
export const POSTED_AT_FLOOR_MS = 365 * 24 * 60 * 60 * 1000;

export function postedAtFrom(raw: string | null | undefined, now: Date): Date {
  if (!raw) return now;
  const posted = new Date(raw);
  if (Number.isNaN(posted.getTime())) return now;
  if (posted.getTime() > now.getTime()) return now;
  if (posted.getTime() < now.getTime() - POSTED_AT_FLOOR_MS) return now;
  return posted;
}

/** ~25 Mo : un vocal long, une photo pleine résolution. */
const MAX_MEDIA_BYTES = 25 * 1024 * 1024;
/** Le plus que MEMO demande pour une étape — `photoBudget.ts`. */
const MAX_PHOTOS = MAX_PHOTOS_PER_STEP;
const MAX_LEVELS = 4_000;

const chatMemoInclude = {
  owner: true,
  members: {
    where: { status: "active" as const },
    include: { account: true },
    orderBy: { invitedAt: "asc" as const },
  },
  steps: { orderBy: { number: "asc" as const } },
  // **La photo du voyage, élue comme ailleurs** (Hugo, 28/10/2026 — « la photo
  // devrait se mettre dans la mini bulle en haut du chat aussi, à la place de
  // l'icône montagne »). Le fil ne rendait que la photo **choisie à la main**,
  // que presque personne ne choisit : l'en-tête montrait donc sa montagne
  // pendant que l'accueil, lui, montrait une photo du voyage.
  ...coverPhotoInclude,
} as const;

async function loadChatMemo(
  context: AppContext,
  request: FastifyRequest,
  memoId: string,
): Promise<MemoForChat> {
  const memo = await context.prisma.memo.findFirst({
    where: { id: memoId, ...visibleToAccount(accountIdOf(request)) },
    include: chatMemoInclude,
  });
  if (!memo) throw HttpError.notFound("Carnet introuvable.");
  return memo;
}

async function loadViewer(context: AppContext, accountId: string): Promise<Account> {
  return context.prisma.account.findUniqueOrThrow({ where: { id: accountId } });
}

/**
 * **Le fil dans l'ordre où il se lit** : le moment où chaque bulle a été
 * posée, et `seq` pour départager celles d'un même instant (T309).
 *
 * Pas `seq` seul : une photo choisie dans le métro arrive des jours plus
 * tard, et se rangeait alors après tout ce qui avait été dit entre-temps.
 */
async function loadMessages(context: AppContext, memoId: string): Promise<ChatMessageRow[]> {
  return context.prisma.chatMessage.findMany({
    where: { memoId },
    include: chatMessageInclude,
    orderBy: [{ postedAt: "asc" }, { seq: "asc" }],
  });
}

/** Le fil entier sans rien rattacher, et de quoi dire ce qu'un sondage doit rendre. */
interface ThreadOutline {
  rows: ThreadOutlineRow[];
  /**
   * Les messages à rendre pour un sondage depuis `since` : ceux écrits depuis,
   * et les fiches dont le souvenir a bougé — une transcription qui arrive
   * n'écrit aucun message, c'est `entries.updatedAt` qui la fait revenir.
   *
   * **Le prédicat est celui d'avant, au caractère près.** Il ne se calcule
   * plus sur le fil rattaché, mais sur cette lecture légère : c'est tout ce
   * qui change. Et il se calcule sur **les mêmes lignes** que la numérotation
   * des fiches et les puces, donc un message rendu a toujours son numéro
   * d'étape — ce qu'une seconde requête, lue à un autre instant, ne
   * garantirait pas.
   */
  changedSince(since: Date): string[];
}

/**
 * Le fil entier **sans rien rattacher** : juste de quoi numéroter les fiches
 * (``stepNumbersOf``), choisir les puces (``currentSuggestionIds``) et dire ce
 * qui a changé.
 *
 * **Trois petites lectures en parallèle plutôt qu'une grosse.** Mesuré le
 * 19/11/2026 depuis le worker de production, sur « 100 jours de miel »
 * (200 messages), un même passage :
 *
 * - tout rattacher, ce que faisait la route : **1245 ms** ;
 * - les colonnes du fil, payload compris : **1075 ms** — le payload porte la
 *   forme d'onde des vocaux (`levels`), 166 Ko à lui seul pour 17 Ko utiles ;
 * - les mêmes colonnes sans le payload : **175 ms**… et c'est le plancher :
 *   chaque aller-retour vers la base en coûte 175 (Supabase, depuis Railway).
 *
 * D'où la forme : le payload ne se lit que là où une puce peut vivre — une
 * bulle texte de MEMO —, et ce que la réponse sait des souvenirs (relu ?
 * modifié ?) se lit d'un coup sur `entries`, au lieu de rattacher un souvenir
 * à chacun des 200 messages.
 *
 * ⚠️ **Les absolus bougent beaucoup** : la même lecture « tout rattacher » a
 * donné 725, 1245, 2264 et 2814 ms sur quatre passages dans l'heure — c'est
 * tout l'historique qui passe sur le fil, et il passe quand il peut. Le
 * sondage qui ne rapporte rien, lui, a donné 350, 353 et 354 ms : il ne
 * dépend plus du poids du fil, et c'est ça qu'on est venu chercher.
 */
async function loadOutline(context: AppContext, memoId: string): Promise<ThreadOutline> {
  const [messages, withSuggestions, entries, reactions] = await Promise.all([
    context.prisma.chatMessage.findMany({
      where: { memoId },
      select: { id: true, seq: true, author: true, kind: true, entryId: true, createdAt: true },
      // Le même ordre que le fil lui-même (T309).
      orderBy: [{ postedAt: "asc" }, { seq: "asc" }],
    }),
    context.prisma.chatMessage.findMany({
      where: { memoId, author: "memo", kind: "text" },
      select: { id: true, payload: true },
    }),
    context.prisma.entry.findMany({
      where: { memoId },
      select: { id: true, validatedAt: true, updatedAt: true },
    }),
    // Les 👍 (T296). Une lecture de plus, mais minuscule et bornée : seul un
    // tour « Ça me convient » peut en porter un, et le `payload` d'un vocal —
    // qui pèse, avec ses niveaux de forme d'onde — n'est pas relu pour ça.
    context.prisma.chatMessage.findMany({
      where: { memoId, author: "traveller", suggestionId: "accept" },
      select: { id: true, payload: true },
    }),
  ]);

  const suggestions = new Map(withSuggestions.map((row) => [row.id, suggestionIdsOf(row.payload)]));
  const reactionTargets = new Map(reactions.map((row) => [row.id, reactionTargetOf(row.payload)]));
  const entryById = new Map(entries.map((entry) => [entry.id, entry]));
  // `entryId` non nul vaut « le souvenir est là » : la clé est posée
  // `SetNull`. La ligne ne manquerait que si un souvenir disparaissait entre
  // les deux lectures — il se lirait alors comme non relu, le temps d'un
  // sondage.
  const entryOf = (entryId: string | null) => (entryId !== null ? entryById.get(entryId) : undefined);

  return {
    rows: messages.map((message) => {
      const entry = entryOf(message.entryId);
      return {
        id: message.id,
        seq: message.seq,
        author: message.author,
        kind: message.kind,
        entryId: message.entryId,
        isEntryValidated: entry !== undefined && entry.validatedAt !== null,
        suggestionIds: suggestions.get(message.id) ?? [],
        reactionTo: reactionTargets.get(message.id) ?? null,
      };
    }),
    changedSince: (since) =>
      messages
        .filter((message) => {
          const entry = entryOf(message.entryId);
          return (
            message.createdAt.getTime() > since.getTime() ||
            (entry !== undefined && entry.updatedAt.getTime() > since.getTime())
          );
        })
        .map((message) => message.id),
  };
}

/**
 * **Hydrater seulement ce qui est rendu.** Les deux formes de la réponse ne
 * demandent pas les mêmes lectures : à l'ouverture, le fil rendu *est* le fil
 * entier, et une seule lecture suffit — c'est celle d'avant. En sondage, la
 * réponse ne rend presque jamais le moindre message : elle relit alors le fil
 * entier sans rien rattacher (``loadOutline``) et n'hydrate que les messages
 * changés — aucune lecture de plus quand il n'y en a pas, ce qui est le cas
 * le plus courant.
 */
type ThreadReads =
  | { kind: "thread"; messages: ChatMessageRow[] }
  | { kind: "update"; outline: readonly ThreadOutlineRow[]; changed: ChatMessageRow[] };

async function loadThreadReads(
  context: AppContext,
  memoId: string,
  since: Date | null,
): Promise<ThreadReads> {
  if (!since) return { kind: "thread", messages: await loadMessages(context, memoId) };
  const outline = await loadOutline(context, memoId);
  return {
    kind: "update",
    outline: outline.rows,
    changed: await loadRows(context, outline.changedSince(since)),
  };
}

/** Des bulles précises, rattachées pour être rendues : un reçu de `POST`, un sondage. */
async function loadRows(context: AppContext, ids: string[]): Promise<ChatMessageRow[]> {
  if (ids.length === 0) return [];
  const rows = await context.prisma.chatMessage.findMany({
    where: { id: { in: ids } },
    include: chatMessageInclude,
    orderBy: [{ postedAt: "asc" }, { seq: "asc" }],
  });
  return rows;
}

async function turnStatusOf(context: AppContext, memoId: string, now: Date): Promise<ChatTurnStatus> {
  const inFlight = await findTurnInFlight(context.prisma, memoId, now);
  return inFlight ? { status: "replying", messageId: inFlight.id } : { status: "idle" };
}

async function memoryCountOf(context: AppContext, memoId: string): Promise<number> {
  return context.prisma.entry.count({ where: { memoId, kind: { not: "photo" } } });
}

async function hasReadyRender(context: AppContext, memoId: string): Promise<boolean> {
  const render = await context.prisma.render.findFirst({
    where: { memoId, status: "ready" },
    select: { id: true },
  });
  return render !== null;
}

/** Une puce ou une commande silencieuse que le catalogue sait traiter sans modèle. */
function isCommand(suggestionId: string | null): boolean {
  if (suggestionId === null) return false;
  return (
    scriptedReply(suggestionId, "") !== null ||
    (FLOW_COMMANDS as readonly string[]).includes(suggestionId) ||
    // La journée qu'on choisit de raconter : son identifiant porte sa date,
    // le catalogue ne peut donc pas la contenir d'avance.
    isGapDayId(suggestionId)
  );
}

/**
 * Le souvenir sur lequel MEMO vient de demander « Il te convient ? », s'il
 * n'est pas encore validé. C'est lui que « Ça me convient » valide : l'app
 * envoie la fiche qu'elle croit la dernière, et s'est déjà trompée de fiche
 * (01/10/2026 — l'étape 1 validée deux fois, l'étape 2 jamais).
 */
async function pendingValidationEntryId(context: AppContext, memoId: string): Promise<string | null> {
  const question = await context.prisma.chatMessage.findFirst({
    where: { memoId, author: "memo", kind: "text", payload: { path: ["asksValidationFor"], not: Prisma.AnyNull } },
    orderBy: { seq: "desc" },
    select: { payload: true },
  });
  const entryId = (question?.payload as { asksValidationFor?: unknown } | null)?.asksValidationFor;
  if (typeof entryId !== "string") return null;
  const entry = await context.prisma.entry.findFirst({
    where: { id: entryId, memoId, validatedAt: null },
    select: { id: true },
  });
  return entry?.id ?? null;
}

/** Plus grand que tout `seq` du fil : « avant la fin » veut dire « tout le fil ». */
const END_OF_THREAD = 2_147_483_647;

/**
 * La fiche que vise une puce de validation — « J'aimerais faire des
 * modifications à l'oral » : celle dont MEMO attend la réponse, sinon le
 * dernier souvenir raconté.
 */
async function cardEntryId(context: AppContext, memoId: string): Promise<string | null> {
  return (
    (await pendingValidationEntryId(context, memoId)) ??
    (await loadCurrentEntry(context.prisma, memoId, END_OF_THREAD))?.id ??
    null
  );
}

/**
 * **Le vocal qui suit « J'aimerais faire des modifications à l'oral » corrige
 * la fiche** (Hugo, 12/10/2026) — il ne fait pas un souvenir de plus, et son
 * texte ne s'ajoute pas à la suite. C'est le cas quand le dernier tour du
 * voyageur est cette puce : elle a retenu la fiche qu'elle visait.
 *
 * @returns le souvenir à corriger, ou `null` pour un vocal ordinaire.
 */
async function oralRevisionTarget(context: AppContext, memoId: string): Promise<string | null> {
  const last = await context.prisma.chatMessage.findFirst({
    where: { memoId, author: "traveller" },
    orderBy: { seq: "desc" },
    select: { suggestionId: true, entryId: true },
  });
  if (last?.suggestionId !== "edit-voice" || !last.entryId) return null;
  const entry = await context.prisma.entry.findFirst({
    where: { id: last.entryId, memoId, kind: { not: "photo" } },
    select: { id: true },
  });
  return entry?.id ?? null;
}

function parseLevels(raw: unknown): number[] {
  if (typeof raw !== "string" || raw.length === 0) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((level): level is number => typeof level === "number" && Number.isFinite(level))
      .map((level) => Math.min(1, Math.max(0, level)))
      .slice(0, MAX_LEVELS);
  } catch {
    return [];
  }
}

/** Ce qu'une photo sait d'elle-même, lu sur l'appareil qui l'envoie. */
export interface PhotoMeta {
  /** Sa date de prise de vue, quand la photothèque la connaît. */
  capturedAt: Date | null;
  /** Où elle a été prise, nom lisible — géocodé **sur le téléphone**. */
  capturedPlaceName: string | null;
}

/** Au-delà, ce n'est pas un nom de lieu : c'est une phrase. */
const MAX_PLACE_NAME = 120;

/**
 * **Ce que chaque photo d'un envoi dit d'elle-même** (T280, 20/11/2026).
 *
 * Un envoi porte jusqu'à `MAX_PHOTOS` photos et n'avait qu'**une** date pour
 * toutes : quatre photos de quatre journées différentes arrivaient le même
 * jour, et le carnet les rangeait ensemble. Le champ `photos` les décrit une
 * par une, dans l'ordre des fichiers — un tableau JSON, parce qu'un champ
 * multipart répété se lit différemment d'une pile à l'autre.
 *
 * Relu de façon défensive, et **jamais bloquant** : un tableau illisible, trop
 * court, ou dont une entrée est fautive laisse simplement la photo sans rien,
 * et l'envoi retombe sur la date du tour. Une photo refusée pour une date mal
 * écrite serait un souvenir perdu.
 *
 * Une app d'avant ce champ n'envoie rien, et rien ne change pour elle.
 */
export function parsePhotoMetas(raw: unknown, count: number): PhotoMeta[] {
  const vide: PhotoMeta = { capturedAt: null, capturedPlaceName: null };
  const metas = Array.from({ length: count }, () => ({ ...vide }));
  if (typeof raw !== "string" || raw.length === 0) return metas;

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return metas;
  }
  if (!Array.isArray(parsed)) return metas;

  for (const [index, item] of parsed.slice(0, count).entries()) {
    if (!item || typeof item !== "object") continue;
    const { capturedAt, capturedPlaceName } = item as {
      capturedAt?: unknown;
      capturedPlaceName?: unknown;
    };
    const date = typeof capturedAt === "string" ? new Date(capturedAt) : null;
    const place = typeof capturedPlaceName === "string" ? capturedPlaceName.trim() : "";
    metas[index] = {
      capturedAt: date && !Number.isNaN(date.getTime()) ? date : null,
      capturedPlaceName: place ? place.slice(0, MAX_PLACE_NAME) : null,
    };
  }
  return metas;
}

function fieldOf(fields: Record<string, { value?: unknown } | undefined>, name: string): string | null {
  const value = fields[name]?.value;
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * La marque d'un tour **dont le job n'est jamais parti** (03/10/2026) :
 * `payload.unqueued`.
 *
 * Le tour s'écrit — et se décompte du crédit du jour — dans sa transaction ;
 * son job (`transcribe` ou `converse`) se publie ensuite, hors d'elle. Si la
 * file refuse (elle démarre encore après un déploiement, ou son pool est
 * saturé), la route rend 500, la file de l'app renvoie le même `id`… et
 * l'idempotence rendait 200 sans rien republier : le tour restait payé, sans
 * réponse de MEMO ni souvenir. La marque dit au renvoi qu'il doit republier.
 *
 * Pourquoi une marque, et pas « tout tour sans réponse » : un renvoi peut
 * arriver pendant que le job tourne encore (une réponse perdue en route), et
 * le republier ferait répondre MEMO deux fois — `converse` ne se garde que
 * d'un rejeu **après** sa réponse (`repliedAt`), pas d'un rejeu simultané.
 */
const UNQUEUED = "unqueued";

function payloadObject(payload: Prisma.JsonValue | null | undefined): Prisma.JsonObject {
  return payload !== null && typeof payload === "object" && !Array.isArray(payload) ? payload : {};
}

/** Publie le job d'un tour ; si la file refuse, marque le tour (`UNQUEUED`) avant de laisser la route rendre 500. */
async function publishTurnJob(context: AppContext, messageId: string, publish: () => Promise<void>): Promise<void> {
  try {
    await publish();
  } catch (cause) {
    try {
      const message = await context.prisma.chatMessage.findUnique({ where: { id: messageId }, select: { payload: true } });
      await context.prisma.chatMessage.update({
        where: { id: messageId },
        data: { payload: { ...payloadObject(message?.payload), [UNQUEUED]: true } },
      });
    } catch (markFailure) {
      context.logger.error(
        { messageId, err: markFailure },
        "Tour écrit sans job, et sans marque : un renvoi ne le republiera pas",
      );
    }
    throw cause;
  }
}

/**
 * Le renvoi d'un tour marqué `UNQUEUED` republie son job : la transcription
 * d'un vocal dont la fiche attend encore (`pending`), la réponse de MEMO pour
 * tout le reste. Rend `true` quand il l'a fait.
 *
 * Seul le renvoi qui lève la marque republie (`updateMany` conditionnel) :
 * deux renvois simultanés ne font pas deux jobs. Si la file refuse encore, la
 * marque revient et la route rend **503** — un 200 dirait « reçu, MEMO
 * répond » d'un tour que personne ne traitera ; la file de l'app, elle,
 * réessaiera.
 */
async function republishUnqueuedTurn(context: AppContext, existing: ChatMessage): Promise<boolean> {
  if (existing.author !== "traveller" || existing.repliedAt !== null) return false;
  const payload = payloadObject(existing.payload);
  if (payload[UNQUEUED] !== true) return false;

  const { [UNQUEUED]: _mark, ...rest } = payload;
  const { count } = await context.prisma.chatMessage.updateMany({
    where: { id: existing.id, payload: { path: [UNQUEUED], equals: true } },
    data: { payload: Object.keys(rest).length > 0 ? rest : Prisma.DbNull },
  });
  // Un autre renvoi vient de lever la marque : c'est lui qui republie.
  if (count === 0) return true;

  try {
    const entry =
      existing.kind === "voice" && existing.entryId
        ? await context.prisma.entry.findUnique({ where: { id: existing.entryId }, select: { status: true } })
        : null;
    if (entry?.status === "pending" && existing.entryId) {
      await context.queue.publish<TranscribeJob>(JOB_NAMES.transcribe, {
        entryId: existing.entryId,
        converseMessageId: existing.id,
      });
    } else {
      await context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId: existing.id });
    }
    context.logger.info({ messageId: existing.id }, "Tour renvoyé : son job, jamais parti, est republié");
    return true;
  } catch (cause) {
    context.logger.warn({ messageId: existing.id, err: cause }, "Tour renvoyé : la file refuse encore son job");
    await context.prisma.chatMessage
      .update({ where: { id: existing.id }, data: { payload: { ...payload, [UNQUEUED]: true } } })
      .catch((markFailure: unknown) =>
        context.logger.error({ messageId: existing.id, err: markFailure }, "Tour renvoyé : marque perdue"),
      );
    throw new HttpError(
      503,
      "Ton message est bien arrivé, mais MEMO ne peut pas encore le lire. Il repartira tout seul dans un instant.",
      "turn_not_queued",
    );
  }
}

export function registerChatRoutes(app: FastifyInstance, context: AppContext): void {
  const publicBaseUrl = publicApiBaseUrl(context.env);

  /**
   * Le fil. Sans `since`, tout ; avec, la suite seulement — les messages écrits
   * depuis, et les fiches dont le souvenir a bougé (une transcription qui
   * arrive n'écrit aucun message, c'est `entries.updatedAt` qui la fait revenir).
   *
   * **La reconstruction se fait ici**, à chaque lecture : tout souvenir sans
   * message devient une bulle, l'ouverture d'abord si le fil est vide. Un
   * voyage raconté depuis l'accueil retrouve ses vocaux dans son fil.
   *
   * **Et elle n'hydrate que ce qu'elle rend** — ``loadThreadReads``. La
   * réponse a besoin du fil entier pour deux choses seulement (numéroter les
   * fiches, choisir les puces) ; rattacher le souvenir, son média et le compte
   * de chaque message ne concerne que les bulles réellement rendues. Un
   * sondage, qui ne rapporte presque jamais rien, ne paie donc plus
   * l'hydratation de tout l'historique.
   */
  app.get("/v1/trips/:id/chat", async (request) => {
    const { id: memoId } = idParams.parse(request.params);
    const query = threadQuery.parse(request.query ?? {});
    const accountId = accountIdOf(request);
    const memo = await loadChatMemo(context, request, memoId);
    const now = new Date();

    await context.prisma.$transaction(async (tx) => {
      // Sérialisé par carnet : deux lectures au même instant ne
      // reconstruisent pas deux fois — voir `lockThread`.
      await lockThread(tx, memoId);
      const orphans = await tx.entry.count({
        where: {
          memoId,
          chatMessages: { none: {} },
          ...(memo.chatClearedAt ? { capturedAt: { gt: memo.chatClearedAt } } : {}),
        },
      });
      // **L'ouverture d'abord, et sans attendre un souvenir** (Hugo,
      // 28/10/2026 — « il faudrait que le message de bienvenue arrive […] en
      // remplacement du message de chat vide »). Elle n'était posée qu'au
      // premier tour du voyageur, ou en reconstruisant un fil qui avait des
      // souvenirs orphelins : un carnet neuf s'ouvrait donc sur un fil vide,
      // où l'app dessinait son propre mot d'accueil — qui disait presque la
      // même chose que la bulle d'ouverture, et la contredisait en partie
      // puisque celle-ci demande ensuite le contexte du voyage. MEMO dit
      // désormais bonjour dès qu'on ouvre la conversation, et une seule fois.
      await ensureOpening(tx, memoId, context.responder);
      if (orphans === 0) return;
      await materializeEntriesWithoutMessages(tx, memo);
    });

    const since = query.since ? new Date(query.since) : null;
    const [reads, viewer, turn, memoryCount, readyRender, isUnlimited, photoSizes] = await Promise.all([
      loadThreadReads(context, memoId, since),
      loadViewer(context, accountId),
      turnStatusOf(context, memoId, now),
      memoryCountOf(context, memoId),
      hasReadyRender(context, memoId),
      hasUnlimitedAccess(context.prisma, accountId, now),
      // **Le format de chaque photo** (T305) : la bulle les range comme elles
      // sont, et il lui faut leurs dimensions avant que les images arrivent.
      loadPhotoSizes(context.prisma, memoId),
    ]);
    // Le crédit du jour se lit au fuseau de celui qui lit : il fallait le
    // compte d'abord.
    const dailyCredit = await readDailyCredit(context.prisma, { memoId, viewer, isUnlimited, now });

    if (reads.kind === "update") {
      return serializeChatUpdate({
        memo,
        allMessages: reads.outline,
        changed: reads.changed,
        viewer,
        memoryCount,
        hasReadyRender: readyRender,
        turn,
        publicBaseUrl,
        now,
        dailyCredit,
        photoSizes,
      });
    }

    return serializeChatThread({
      memo,
      messages: reads.messages,
      viewer,
      activeStep: activeStepOf(memo.steps, now),
      memoryCount,
      hasReadyRender: readyRender,
      turn,
      publicBaseUrl,
      now,
      dailyCredit,
      photoSizes,
    });
  });

  /**
   * Un tour de parole. Trois corps, une route — comme `POST /v1/memos/:id/entries` :
   * `application/json` pour un texte ou une puce, `multipart/form-data` pour un
   * vocal ou une à quatre photos.
   *
   * La route écrit le message du voyageur et répond **tout de suite** (201) ;
   * MEMO répond dans le job `converse`, que l'app attend en sondant le fil.
   *
   * **L'ordre des vérifications** (Hugo, 03/10/2026) : le carnet, puis
   * **l'idempotence d'abord** — un renvoi du même `id` rend 200 sans rien
   * compter ni plafonner (le plafond passait avant, et la file hors ligne
   * marquait « refusé » un tour déjà arrivé) —, puis le plafond anti-abus, la
   * mesure du vocal, et enfin la transaction qui écrit le tour **et** le
   * décompte du crédit du jour (`services/dailyCredit.ts`). Une puce envoyée
   * telle quelle et les photos ne coûtent rien ; tout le reste se décompte,
   * contexte du voyage compris.
   */
  app.post("/v1/trips/:id/chat", async (request, reply) => {
    const { id: memoId } = idParams.parse(request.params);
    const accountId = accountIdOf(request);
    const memo = await loadChatMemo(context, request, memoId);
    const now = new Date();
    // Le téléphone du tour, pour que MEMO parle de ses Réglages ou de ses
    // Paramètres — retenu sur le tour, que le job relit (`appPlatform.ts`).
    const platform = platformPayload(appPlatformOf(request));
    const showsAuthors = memo.members.length > 0;
    // Le voyageur raconte le contexte de son voyage : ce qu'il dit ne devient
    // pas un souvenir — `tripContext.ts`. Il se décompte pourtant du crédit du
    // jour comme le reste : c'est du récit, et MEMO l'écoute.
    const gatheringContext = isGathering(parseTripContext(memo.tripContext));
    // La file de l'app de ce lot garde un tour refusé faute de crédit ; celle
    // des builds installés l'efface. Le refus ne leur dit pas la même chose
    // (`holdsRefusedTurns`).
    const refusal = { holdsTurn: holdsRefusedTurns(request) };

    const receipt = async (written: ChatMessageRow[], turn: ChatTurnStatus, credit?: DailyCredit | null) =>
      serializeChatReceipt({
        written,
        viewerAccountId: accountId,
        showsAuthors,
        publicBaseUrl,
        cards: await context.prisma.chatMessage.findMany({
          where: { memoId, kind: "transcript" },
          select: { id: true, kind: true, seq: true, entryId: true },
        }),
        turn,
        now,
        dailyCredit:
          credit ??
          (await readDailyCredit(context.prisma, { memoId, viewer: await loadViewer(context, accountId), now })),
      });

    // Le plafond anti-abus : des tours par carnet et par jour. Ferme la porte
    // à un script, pas à un voyageur — abonné compris. **Après**
    // l'idempotence : un renvoi n'est pas un tour de plus.
    const assertUnderTurnCap = async () => {
      if ((await dailyTurnCount(context.prisma, memoId, now)) >= context.env.CHAT_DAILY_TURN_CAP) {
        throw new HttpError(
          429,
          "MEMO a besoin d’une pause : tu as beaucoup raconté aujourd’hui. On reprend demain.",
          "chat_daily_cap",
        );
      }
    };

    if (!request.isMultipart()) {
      const body = textTurnBody.parse(request.body ?? {});
      // **Le moment du geste**, pas celui de l'arrivée (T309) : c'est lui qui
      // range la bulle, et la réponse de MEMO se rangera avec elle.
      const postedAt = postedAtFrom(body.postedAt, now);
      const text = body.text.trim();

      // Une puce arrive avec son identifiant ; un client qui n'envoie que le
      // libellé est reconnu au caractère près.
      const suggestionId =
        body.suggestionId && isCommandId(body.suggestionId)
          ? body.suggestionId
          : suggestionIdForLabel(text);
      const command = isCommand(suggestionId);

      if (!command && text.length === 0) throw HttpError.badRequest("Le message est vide.");

      // Déjà reçu : la même bulle, rien de plus — sauf si son job n'est
      // jamais parti (`republishUnqueuedTurn`). C'est l'idempotence du renvoi.
      const existing = await context.prisma.chatMessage.findUnique({ where: { id: body.id } });
      if (existing) {
        if (existing.memoId !== memoId) throw HttpError.conflict("Ce message appartient à un autre carnet.");
        const republished = await republishUnqueuedTurn(context, existing);
        const rows = await loadRows(context, [existing.id]);
        const turn: ChatTurnStatus = republished
          ? { status: "replying", messageId: existing.id }
          : await turnStatusOf(context, memoId, now);
        return reply.code(200).send(await receipt(rows, turn));
      }

      await assertUnderTurnCap();

      // **Une réaction ne vaut que là où une validation attend** (T296, choix
      // de Hugo du 28/11/2026 : « 👍 sur la question seule »). C'est la règle
      // du menu contextuel — ce qui ne s'applique pas à une bulle n'y figure
      // pas —, et elle se tient ici : un 👍 arrivé sans « Ça me convient »,
      // ou sur une bulle du voyageur, serait une réaction décorative, et il
      // n'y en a pas.
      let reactionTo: string | null = null;
      if (body.reactionTo) {
        if (suggestionId !== "accept") {
          throw HttpError.badRequest("Une réaction vaut « Ça me convient » : la puce manque.");
        }
        const target = await context.prisma.chatMessage.findFirst({
          where: { id: body.reactionTo, memoId, author: "memo" },
          select: { id: true },
        });
        if (!target) throw HttpError.badRequest("Cette bulle n’est pas une bulle de MEMO de ce carnet.");
        reactionTo = target.id;
      }

      let validatedEntryId: string | null = null;
      if (suggestionId === "accept") {
        // « Ça me convient » valide **dans la même requête** : la fiche passe
        // validée avant même que MEMO ait accusé réception.
        const targetId = (await pendingValidationEntryId(context, memoId)) ?? body.entryId;
        const entry = targetId
          ? await context.prisma.entry.findFirst({
              where: { id: targetId, memoId, kind: { not: "photo" } },
              select: { id: true },
            })
          : null;
        if (!entry) {
          throw new HttpError(
            400,
            "Dis-moi quel souvenir te convient : la fiche n’est plus là.",
            "entry_required",
          );
        }
        validatedEntryId = entry.id;
      }

      // « À l'oral » retient la fiche qu'elle vise : c'est elle que le vocal
      // suivant corrigera (`oralRevisionTarget`).
      const revisedEntryId = suggestionId === "edit-voice" ? await cardEntryId(context, memoId) : null;

      // Une puce envoyée telle quelle ne coûte rien ; un texte, 75 ms par
      // caractère — même déguisé en puce (`isFreeChatText`).
      const characters = isFreeChatText(text, suggestionId) ? 0 : countCharacters(text);
      const charge: DailyCharge | null = characters > 0 ? { kind: "text", characters } : null;
      const speaker = charge ? await loadSpeaker(context.prisma, accountId, now) : null;

      const written = await withDailyCredit(context.prisma, memoId, refusal, () =>
        context.prisma.$transaction(async (tx) => {
          await lockThread(tx, memoId);
          const ids: string[] = [];
          const opening = await ensureOpening(tx, memoId, context.responder, postedAt);
          if (opening) ids.push(opening.id);

          if (validatedEntryId) {
            // Idempotent : valider deux fois ne pose la date qu'une fois.
            await tx.entry.updateMany({
              where: { id: validatedEntryId, validatedAt: null },
              data: { validatedAt: now },
            });
          }

          const message = await tx.chatMessage.create({
            data: {
              id: body.id,
              memoId,
              author: "traveller",
              kind: "text",
              accountId,
              postedAt,
              text: command ? (text.length > 0 ? text : null) : text,
              suggestionId,
              entryId: validatedEntryId ?? revisedEntryId ?? body.entryId ?? null,
              disposition: command ? "command" : null,
              stepId: body.stepId ?? null,
              ...(platform.platform || reactionTo
                ? { payload: { ...platform, ...(reactionTo ? { reactionTo } : {}) } }
                : {}),
            },
          });
          ids.push(message.id);

          const charged =
            charge && speaker
              ? await chargeDailyCredit(tx, { memoId, ...speaker, charge, now, postedAt })
              : null;
          if (charged?.notice) ids.push(charged.notice.id);
          return { ids, credit: charged?.credit ?? null };
        }),
      );

      await publishTurnJob(context, body.id, () =>
        context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId: body.id }),
      );

      const rows = await loadRows(context, written.ids);
      return reply
        .code(201)
        .send(await receipt(rows, { status: "replying", messageId: body.id }, written.credit));
    }

    // --- Multipart : un vocal, ou des photos -------------------------------

    const files: { filename: string; mimeType: string; buffer: Buffer }[] = [];
    let fields: Record<string, { value?: unknown } | undefined> = {};

    for await (const part of request.files({ limits: { fileSize: MAX_MEDIA_BYTES, files: MAX_PHOTOS + 1 } })) {
      const buffer = await part.toBuffer();
      if (buffer.byteLength === 0) throw HttpError.badRequest("Le fichier reçu est vide.");
      files.push({ filename: part.filename, mimeType: part.mimetype, buffer });
      fields = part.fields as Record<string, { value?: unknown } | undefined>;
    }
    if (files.length === 0) throw HttpError.badRequest("Aucun fichier reçu.");

    const messageId = fieldOf(fields, "id");
    if (!messageId || !z.string().uuid().safeParse(messageId).success) {
      throw HttpError.badRequest("`id` est requis : l’identifiant du message, un UUID.");
    }

    const existing = await context.prisma.chatMessage.findUnique({ where: { id: messageId } });
    if (existing) {
      if (existing.memoId !== memoId) throw HttpError.conflict("Ce message appartient à un autre carnet.");
      const ids = [existing.id];
      const card = await context.prisma.chatMessage.findFirst({
        where: { replyToId: existing.id, kind: "transcript" },
        select: { id: true },
      });
      if (card) ids.push(card.id);
      const republished = await republishUnqueuedTurn(context, existing);
      const turn: ChatTurnStatus = republished
        ? { status: "replying", messageId: existing.id }
        : await turnStatusOf(context, memoId, now);
      return reply.code(200).send(await receipt(await loadRows(context, ids), turn));
    }

    await assertUnderTurnCap();

    const isAudio = files.every((file) => file.mimeType.startsWith("audio/"));
    const isImages = files.every((file) => file.mimeType.startsWith("image/"));
    if (!isAudio && !isImages) {
      throw HttpError.badRequest(
        `Type de média non supporté : ${files.map((file) => file.mimeType).join(", ")}. Attendu : audio/* ou image/*.`,
      );
    }
    if (isAudio && files.length > 1) throw HttpError.badRequest("Un seul vocal par message.");
    // Le chiffre suit `photoBudget.ts` : une étape à 100 % de photos en demande
    // plus que les six de l'ancienne table, et un message figé mentirait.
    if (isImages && files.length > MAX_PHOTOS) {
      throw HttpError.badRequest(`${MAX_PHOTOS} photos au plus par message.`);
    }

    const postedAt = postedAtFrom(fieldOf(fields, "postedAt"), now);
    // **Ce ne sont que des aperçus** (T309) : 1 200 px, montés tout de suite
    // pour que la bulle arrive ; le téléphone enverra la pleine définition
    // ensuite, photo par photo (`PUT /v1/entries/:id/photo`).
    const lightweight = fieldOf(fields, "lightweight") === "1";
    const rawCapturedAt = fieldOf(fields, "capturedAt");
    const capturedAt = rawCapturedAt ? new Date(rawCapturedAt) : now;
    if (Number.isNaN(capturedAt.getTime())) {
      throw HttpError.badRequest("`capturedAt` n'est pas une date ISO 8601 valide.");
    }

    // La durée se **mesure** dans le fichier (`lib/mp4Duration.ts`) ; le champ
    // `durationSeconds` que l'app envoie encore n'est plus lu (Hugo,
    // 03/10/2026). C'est la mesure qui se décompte, s'écrit dans
    // `media_assets` et s'affiche dans la bulle.
    const durationMs = isAudio ? measureVoiceMs(files[0]!.buffer) : null;
    const duration = durationMs === null ? null : durationMs / 1000;
    const placeLabel = fieldOf(fields, "placeLabel");
    // Ce que chaque photo dit d'elle-même, aligné sur l'ordre des fichiers.
    const photoMetas = parsePhotoMetas(fields["photos"]?.value, files.length);
    const rawStepId = fieldOf(fields, "stepId");
    const stepId = rawStepId && z.string().uuid().safeParse(rawStepId).success ? rawStepId : null;
    const levels = parseLevels(fields["levels"]?.value);

    // Un vocal se décompte, contexte du voyage compris ; des photos, jamais.
    const charge: DailyCharge | null = durationMs === null ? null : { kind: "voice", durationMs };
    const speaker = charge ? await loadSpeaker(context.prisma, accountId, now) : null;
    if (charge && speaker) {
      // Un vocal refusé ne se stocke pas : le refus certain se voit **avant**
      // l'envoi au stockage. La transaction redécompte de toute façon — c'est
      // elle qui tranche si un co-voyageur a raconté entre-temps.
      const before = await readDailyCredit(context.prisma, {
        memoId,
        viewer: speaker.account,
        isUnlimited: speaker.isUnlimited,
        now,
      });
      if (exceedsDailyCredit(before, charge)) {
        await refuseForDailyCredit(context.prisma, memoId, before, charge, { ...refusal, now });
      }
    }

    // Un vocal du contexte du voyage : pas de souvenir, pas de fiche. Des
    // photos restent des souvenirs, contexte ou non.
    const contextVoice = isAudio && gatheringContext;
    // Un vocal qui corrige une fiche : pas de souvenir non plus — son texte
    // ira réécrire celui de la fiche.
    const revisedEntryId = isAudio && !gatheringContext ? await oralRevisionTarget(context, memoId) : null;
    // Des photos : le récit qu'elles illustrent, quand MEMO les a demandées.
    const illustratedEntryId = isImages ? await photosTargetEntryId(context.prisma, memoId) : null;

    // **Une photo entre dans un format que le PDF sait peindre** (Hugo,
    // 11/11/2026) : la photothèque d'un iPhone donne du HEIC, que l'app
    // envoie sous un nom en `.jpg` et un type `image/jpeg`. iOS le décode, le
    // Chromium qui compose le carnet non — la photo s'affichait dans l'app et
    // manquait au livre. On regarde donc les octets, et on convertit avant
    // d'écrire (`services/photoFormat.ts`).
    const photos = isImages
      ? await Promise.all(files.map((file) => toRenderablePhoto(file.buffer, file.filename, file.mimeType)))
      : [];
    for (const [index, photo] of photos.entries()) {
      if (photo.converted) continue;
      if (isRenderableImage(photo.buffer)) continue;
      // Le souvenir part quand même : le récit est irremplaçable, la photo
      // non. Mais ça se lit dans les journaux, au lieu de se découvrir sur un
      // carnet imprimé.
      request.log.warn(
        { memoId, mimeType: files[index]!.mimeType },
        "Photo dans un format que le moteur de PDF ne peint pas, et non convertible",
      );
    }

    const stored = await Promise.all(
      files.map((file, index) => {
        const photo = photos[index];
        return photo
          ? context.storage.put("photo", photo.filename, photo.buffer, photo.mimeType)
          : context.storage.put(isAudio ? "audio" : "photo", file.filename, file.buffer, file.mimeType);
      }),
    );

    // **Le sens de chaque photo, mesuré à l'arrivée** (Hugo, 15/10/2026) : la
    // couverture du voyage est la plus récente de ses photos paysage, et ce
    // sont ces trois champs qui le disent. Ici et pas plus tard — le fichier
    // est déjà en mémoire, le relire depuis S3 coûterait un aller-retour par
    // photo. Une mesure impossible (HEIC) laisse les champs à `null` : la
    // photo ne sera pas couverture, et c'est tout.
    // Sur les octets **convertis** : `measurePhoto` ne sait pas lire un HEIC,
    // et une photo de photothèque n'était donc jamais couverture de voyage.
    const measures = await Promise.all(photos.map((photo) => measurePhoto(photo.buffer)));

    // **La vignette que l'écran des couvertures affichera** (T260) : ici, sur
    // les octets encore en mémoire, et non à l'ouverture de l'écran — qui
    // aurait eu à en fabriquer quatre-vingt-huit d'un coup. Un échec ne
    // retient pas la photo : l'app lira l'originale, comme avant.
    const thumbnails = await Promise.all(
      photos.map((photo) => storeScreenThumbnail(context, photo.buffer)),
    );

    if (contextVoice || revisedEntryId) {
      const [object] = stored;
      if (!object) throw new Error("Aucun vocal enregistré.");
      const written = await withDailyCredit(context.prisma, memoId, refusal, () =>
        context.prisma.$transaction(async (tx) => {
          await lockThread(tx, memoId);
          const ids: string[] = [];
          const opening = await ensureOpening(tx, memoId, context.responder, postedAt);
          if (opening) ids.push(opening.id);
          const message = await tx.chatMessage.create({
            data: {
              id: messageId,
              memoId,
              author: "traveller",
              kind: "voice",
              accountId,
              postedAt,
              // Une correction est une précision de la fiche qu'elle vise :
              // c'est ainsi que la rédaction la relit.
              disposition: revisedEntryId ? "context" : "trip_context",
              entryId: revisedEntryId,
              stepId,
              payload: {
                levels,
                // Le fichier pend au message dans les deux cas : il n'a pas
                // de souvenir à lui (`contextVoiceOf`).
                contextVoice: {
                  storageKey: object.storageKey,
                  mimeType: object.mimeType,
                  durationSeconds: duration,
                },
                ...(revisedEntryId ? { revises: revisedEntryId, topic: ORAL_CORRECTION_TOPIC } : {}),
                ...platform,
              },
            },
          });
          ids.push(message.id);
          const charged =
            charge && speaker ? await chargeDailyCredit(tx, { memoId, ...speaker, charge, now, postedAt }) : null;
          if (charged?.notice) ids.push(charged.notice.id);
          // Ce que ce vocal a pris : rendu s'il se révèle muet (QA D9).
          if (charged) await recordVoiceCharge(tx, message, charged.charged);
          return { ids, credit: charged?.credit ?? null };
        }),
      );
      // Le job écoute lui-même : pas de souvenir à transcrire, donc pas de
      // job `transcribe`.
      await publishTurnJob(context, messageId, () =>
        context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId }),
      );
      return reply
        .code(201)
        .send(await receipt(await loadRows(context, written.ids), { status: "replying", messageId }, written.credit));
    }

    let entryIdForTranscription: string | null = null;

    const written = await withDailyCredit(context.prisma, memoId, refusal, () =>
      context.prisma.$transaction(async (tx) => {
        await lockThread(tx, memoId);
        const ids: string[] = [];
        const opening = await ensureOpening(tx, memoId, context.responder, postedAt);
        if (opening) ids.push(opening.id);

        const entries = await Promise.all(
          stored.map((object, index) =>
            tx.entry.create({
              data: {
                memo: { connect: { id: memoId } },
                kind: isAudio ? "audio" : "photo",
                status: isAudio ? "pending" : "ready",
                // La date de la photo l'emporte sur celle du tour : quatre
                // photos de quatre journées arrivent dans le même envoi, et
                // c'est leur jour de prise de vue qui les range (T280).
                capturedAt: photoMetas[index]?.capturedAt ?? capturedAt,
                placeLabel,
                capturedPlaceName: photoMetas[index]?.capturedPlaceName ?? null,
                ...(measures[index]
                  ? {
                      photoWidthPx: measures[index].widthPx,
                      photoHeightPx: measures[index].heightPx,
                      photoIsLandscape: measures[index].isLandscape,
                      // La netteté, tirée du même décodage (T265) : c'est
                      // elle qui décidera quelles photos le carnet montre
                      // quand l'étape en porte plus qu'il n'en dessine.
                      //
                      // ⚠️ **Jamais sur un aperçu** (T309) : le laplacien
                      // dépend de la définition, et le barème est calibré sur
                      // 2400 px — un aperçu de 1 200 px se ferait juger sur
                      // une échelle qui n'est pas la sienne. Les deux champs
                      // arrivent avec la pleine définition. Le sens, lui, se
                      // lit sur n'importe quelle taille : un rapport de côtés
                      // ne change pas en réduisant.
                      ...(lightweight
                        ? {}
                        : {
                            photoSharpness: measures[index].sharpness,
                            photoVerdict: measures[index].verdict,
                          }),
                    }
                  : {}),
                ...(stepId ? { step: { connect: { id: stepId } } } : {}),
                media: {
                  create: {
                    storageKey: object.storageKey,
                    mimeType: object.mimeType,
                    bytes: object.bytes,
                    durationSeconds: isAudio ? duration : null,
                    thumbStorageKey: thumbnails[index] ?? null,
                    // Un vocal ne connaît pas d'aperçu : seules les photos.
                    isLightweight: lightweight && !isAudio,
                  },
                },
              },
            }),
          ),
        );
        const [first] = entries;
        if (!first) throw new Error("Aucun souvenir créé.");

        const payload: Prisma.InputJsonObject = isAudio
          ? { levels, ...platform }
          : {
              entryIds: entries.map((entry) => entry.id),
              ...(illustratedEntryId ? { forEntryId: illustratedEntryId } : {}),
              ...platform,
            };

        const message = await tx.chatMessage.create({
          data: {
            id: messageId,
            memoId,
            author: "traveller",
            kind: isAudio ? "voice" : "photos",
            accountId,
            postedAt,
            entryId: first.id,
            disposition: "memory",
            stepId,
            payload,
          },
        });
        ids.push(message.id);

        if (isAudio) {
          // La fiche tombe **tout de suite**, sans texte : on ne cache pas une
          // information réelle (date, lieu, durée) derrière une attente.
          const card = await tx.chatMessage.create({
            data: {
              memoId,
              author: "memo",
              kind: "transcript",
              entryId: first.id,
              replyToId: message.id,
              // La fiche se range avec le vocal qu'elle transcrit (T309).
              postedAt,
              stepId,
              pauseMilliseconds: pauseBeforeTranscript(duration),
              model: "scripted",
            },
          });
          ids.push(card.id);
          entryIdForTranscription = first.id;
        }

        // Le décompte **après** les bulles du tour : la bulle « reviens
        // demain », s'il la faut, vient derrière elles dans le fil.
        const charged =
          charge && speaker ? await chargeDailyCredit(tx, { memoId, ...speaker, charge, now, postedAt }) : null;
        if (charged?.notice) ids.push(charged.notice.id);
        // Ce que ce vocal a pris : rendu s'il se révèle muet (QA D9).
        if (charged && isAudio) await recordVoiceCharge(tx, message, charged.charged);
        return { ids, credit: charged?.credit ?? null };
      }),
    );

    const transcribeEntryId: string | null = entryIdForTranscription;
    // Des photos comptent tout de suite (T227) ; un vocal, à la fin de sa
    // rédaction.
    if (!isAudio) await refreshTripFactsQuietly(context, memoId);
    await publishTurnJob(context, messageId, () =>
      isAudio && transcribeEntryId
        ? context.queue.publish<TranscribeJob>(JOB_NAMES.transcribe, {
            entryId: transcribeEntryId,
            converseMessageId: messageId,
          })
        : context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId }),
    );

    return reply
      .code(201)
      .send(await receipt(await loadRows(context, written.ids), { status: "replying", messageId }, written.credit));
  });

  /**
   * Le fichier d'un vocal du contexte du voyage — le pendant de
   * `GET /v1/entries/:id/media` pour un vocal qui n'est pas un souvenir. Mêmes
   * règles : visible par qui voit le voyage, cache privé et long.
   */
  app.get("/v1/chat-messages/:id/media", async (request, reply) => {
    const { id } = idParams.parse(request.params);
    const message = await context.prisma.chatMessage.findFirst({
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
      select: { payload: true },
    });
    const voice = message ? contextVoiceOf(message.payload) : null;
    if (!voice) throw HttpError.notFound("Média introuvable.");

    let body: Buffer;
    try {
      body = await context.storage.get(voice.storageKey);
    } catch {
      throw HttpError.notFound("Média introuvable.");
    }
    return reply
      .header("Cache-Control", "private, max-age=2592000, immutable")
      .type(voice.mimeType)
      .send(body);
  });

  /**
   * « Supprimer la conversation » — `docs/conversation.md` § 7. Le propriétaire
   * seul ; un co-voyageur reçoit **403** et non 404 : il voit le voyage, lui
   * dire qu'il n'est plus sur son compte serait faux.
   *
   * Supprimer garde la bulle d'ouverture, et les souvenirs d'avant ne
   * reviennent pas dans le fil (`chatClearedAt`) — ils restent dans le carnet.
   */
  app.delete("/v1/trips/:id/chat", async (request, reply) => {
    const { id: memoId } = idParams.parse(request.params);
    const accountId = accountIdOf(request);
    const memo = await loadChatMemo(context, request, memoId);

    if (memo.ownerAccountId !== accountId) {
      throw new HttpError(
        403,
        "Seul le propriétaire du voyage peut supprimer la conversation.",
        "owner_only",
      );
    }

    await context.prisma.$transaction(async (tx) => {
      await lockThread(tx, memoId);
      await tx.chatMessage.deleteMany({ where: { memoId } });
      await tx.memo.update({
        where: { id: memoId },
        data: { chatClearedAt: new Date(), conversationState: Prisma.DbNull },
      });
      await ensureOpening(tx, memoId, context.responder);
    });

    return reply.code(204).send();
  });

  /**
   * **« Déplacer dans une autre étape »** — l'appui long sur une bulle (T270).
   *
   * Le sujet est **la bulle**, pas la photo : six photos envoyées ensemble
   * partagent un message, et c'est ce message qui porte l'étape choisie. On
   * appuie sur une bulle, elle part entière.
   *
   * **Deux épingles, parce qu'il y a deux façons d'appartenir à une étape** :
   *
   * - une **photo** suit l'étape de sa bulle (`chat_messages.stepId`), que
   *   `pinnedSteps` fait déjà passer devant le découpage ;
   * - un **récit** reçoit `entries.pinnedStepId` (19/11/2026). Sans cette
   *   colonne, écrire `entries.stepId` à la main se déferait au prochain
   *   recalcul **sans rien dire** : l'étape d'un récit se *calcule* — sa date,
   *   son lieu, le récit qu'il prolonge (`services/tripFacts.ts`). La main
   *   l'emporte sur la machine, comme `separatedByTraveller` sur
   *   `continuesPreviousStep`.
   *
   * Ce qui n'est pas un souvenir ne se déplace pas : une bulle de MEMO, une
   * puce, une précision n'ont pas d'étape à eux.
   *
   * Un co-voyageur déplace comme le propriétaire : il raconte comme lui.
   */
  app.post("/v1/trips/:id/chat/:messageId/step", async (request, reply) => {
    const { id: memoId, messageId } = moveParams.parse(request.params);
    const { stepId } = moveBody.parse(request.body ?? {});
    // La visibilité du carnet d'abord : quelqu'un qui n'y participe pas
    // reçoit un 404 sans qu'on lui dise si ce message existe. `loadVisibleMemo`
    // et non `loadChatMemo` : ce geste n'a besoin ni des membres, ni des
    // étapes, ni de la photo élue.
    await loadVisibleMemo(context, request, memoId);

    const message = await context.prisma.chatMessage.findFirst({
      where: { id: messageId, memoId },
      select: { id: true, author: true, kind: true, entryId: true, payload: true, disposition: true },
    });
    if (!message) throw HttpError.notFound("Message introuvable.");
    const isPhotos = message.kind === "photos";
    // Un récit : la bulle du voyageur qui porte son souvenir. Une précision,
    // une puce, un vocal du contexte du voyage n'en portent pas.
    // Un récit : la bulle porte **son** souvenir. `disposition` nulle compte
    // comme un récit — un texte libre n'en reçoit une qu'une fois classé par
    // le job (`chat.ts`, création de la bulle) —, mais une précision, une
    // puce ou le contexte du voyage sont nommément écartés : ils pointent
    // vers la fiche d'un autre souvenir sans en être un.
    const isStory =
      (message.kind === "voice" || message.kind === "text") &&
      message.entryId !== null &&
      message.disposition !== "context" &&
      message.disposition !== "command" &&
      message.disposition !== "trip_context" &&
      contextVoiceOf(message.payload) === null;
    if (message.author !== "traveller" || !(isPhotos || isStory)) {
      throw HttpError.badRequest("Seul un souvenir se déplace d'une étape à l'autre.");
    }

    const step = await context.prisma.memoStep.findFirst({
      where: { id: stepId, memoId },
      select: { id: true },
    });
    if (!step) throw HttpError.notFound("Étape introuvable.");

    // Une bulle de photos porte la première par `entryId`, les autres par
    // `payload.entryIds` — voir `materializeEntriesWithoutMessages`.
    const ids = new Set<string>();
    if (message.entryId) ids.add(message.entryId);
    const payload = message.payload as { entryIds?: unknown } | null;
    if (payload && Array.isArray(payload.entryIds)) {
      for (const id of payload.entryIds) if (typeof id === "string") ids.add(id);
    }

    await context.prisma.$transaction(async (tx) => {
      await lockThread(tx, memoId);
      // L'épingle d'une photo : l'étape de sa bulle.
      await tx.chatMessage.update({ where: { id: message.id }, data: { stepId } });
      if (ids.size > 0) {
        await tx.entry.updateMany({
          where: { id: { in: [...ids] }, memoId },
          data: {
            // L'étape du souvenir, pour que la réponse suivante le range au
            // bon endroit sans attendre le recalcul…
            stepId,
            // …et, pour un récit, l'épingle qui tiendra **au** recalcul.
            ...(isStory ? { pinnedStepId: stepId } : {}),
          },
        });
      }
    });

    // Le découpage se refait derrière : l'étape qui perd sa dernière photo
    // disparaît (T235), les numéros suivent.
    await refreshTripFactsQuietly(context, memoId);

    return reply.code(204).send();
  });
}
