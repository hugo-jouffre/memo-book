import { Prisma, type ChatMessage, type Entry, type MediaAsset, type Memo, type MemoStep, type PrismaClient } from "@prisma/client";
import { finalTextOf } from "../jobs/redact.js";
import {
  HISTORY_LIMIT,
  HISTORY_TEXT_LIMIT,
  dayKeyOf,
  pauseBeforeSaying,
  parseConversationState,
  pauseBeforeTranscript,
  type ConversationHistoryTurn,
  type ConversationState,
  type CurrentEntry,
  type MemoResponder,
} from "./conversation.js";
import {
  OPENING_PAUSE_MS,
  REDACTION_UNWRITTEN,
  SUGGESTION_SETS,
  photosWanted,
  redactionKept,
  nameQuestionFor,
  placeQuestionFor,
  splitQuestionFor,
  validationQuestion,
} from "./conversationCopy.js";
import { localDate } from "./localCalendar.js";
import { forTargetOf, photoRequestFor } from "./photoRequest.js";
import type { RedactedNeighbour } from "./redaction.js";
import { contextVoiceOf } from "./tripContext.js";

/**
 * Le fil d'un carnet, vu du serveur : ce que les routes et le job `converse`
 * ont en commun et qui n'est ni une réponse ni une sérialisation.
 */

/** Le client d'une transaction, ou le client tout court : les deux lisent et écrivent pareil. */
export type Db = PrismaClient | Prisma.TransactionClient;

export type EntryWithMedia = Entry & {
  media: MediaAsset | null;
  /**
   * **L'étape qui porte ce souvenir**, pour ce que sa fiche affiche : le lieu
   * compris et les jours racontés (T308). Absente d'un souvenir qu'aucun
   * recalcul n'a encore rangé — la fiche se contente alors de ce que le
   * souvenir sait de lui-même, c'est-à-dire souvent rien, et n'affiche pas de
   * ligne de date.
   */
  step?: { placeName: string | null; livedFromDay: Date | null; livedToDay: Date | null } | null;
};

/** Un message avec ce qu'il faut pour le dessiner : son souvenir, et qui l'a dit. */
export type ChatMessageRow = ChatMessage & {
  entry: EntryWithMedia | null;
  account: {
    firstName: string | null;
    lastName: string | null;
    avatarStorageKey: string | null;
    avatarUrl: string | null;
  } | null;
};

export const chatMessageInclude = {
  entry: {
    include: {
      media: true,
      // La fiche montre le lieu et les dates de **l'étape**, pas l'écho que
      // l'app avait envoyé avec le vocal (T308) : trois colonnes, et une
      // jointure que toutes les lectures du fil partagent.
      step: { select: { placeName: true, livedFromDay: true, livedToDay: true } },
    },
  },
  // La photo et le nom de celui qui a parlé : la bulle d'un vocal porte son
  // portrait, ou ses initiales (Clara, 26/09/2026).
  account: { select: { firstName: true, lastName: true, avatarStorageKey: true, avatarUrl: true } },
} as const;

/** Le `kind` d'une bulle du voyageur pour un souvenir donné. */
export function messageKindFor(entryKind: Entry["kind"]): "voice" | "text" | "photos" {
  switch (entryKind) {
    case "audio":
      return "voice";
    case "text":
      return "text";
    case "photo":
      return "photos";
  }
}

// ---------------------------------------------------------------------------
// L'ouverture
// ---------------------------------------------------------------------------

/**
 * Sérialise les écritures du fil d'un carnet : un verrou de ligne sur
 * `memos`, tenu jusqu'à la fin de la transaction.
 *
 * Sans lui, deux lectures simultanées — l'app relit le fil en revenant des
 * réglages, et le sondage passe au même instant — voyaient toutes deux un
 * souvenir sans message et le matérialisaient **deux fois** (22/09/2026).
 * Même chose pour la bulle d'ouverture, que deux premiers tours pouvaient poser
 * en double. À appeler en tête de toute transaction qui écrit dans le fil.
 */
export async function lockThread(tx: Prisma.TransactionClient, memoId: string): Promise<void> {
  await tx.$executeRaw`SELECT id FROM memos WHERE id = ${memoId} FOR UPDATE`;
}

/**
 * Pose la bulle d'ouverture si le fil est vide. À appeler **dans une
 * transaction verrouillée** (``lockThread``) : c'est le verrou qui rend
 * l'opération idempotente face à deux premiers tours simultanés.
 */
export async function ensureOpening(
  db: Db,
  memoId: string,
  responder: MemoResponder,
  /**
   * **L'instant du tour qu'elle précède** (T309) : l'ouverture se range avec
   * lui, et `seq` la met devant — elle est écrite la première. Sans ça, elle
   * prenait l'instant de son insertion, postérieur de quelques millisecondes
   * à celui que l'app annonce, et MEMO disait bonjour **après** la première
   * phrase du voyageur. Absent : l'instant de l'écriture, comme avant.
   */
  postedAt?: Date,
): Promise<ChatMessage | null> {
  const existing = await db.chatMessage.findFirst({ where: { memoId }, select: { id: true } });
  if (existing) return null;

  const opening = responder.opening();
  return db.chatMessage.create({
    data: {
      memoId,
      author: "memo",
      kind: "text",
      ...(postedAt ? { postedAt } : {}),
      text: opening.text,
      pauseMilliseconds: OPENING_PAUSE_MS,
      model: "scripted",
      payload: { suggestions: opening.suggestionIds },
    },
  });
}

// ---------------------------------------------------------------------------
// La reconstruction depuis les souvenirs
// ---------------------------------------------------------------------------

/**
 * Tout souvenir **sans message** devient une bulle du voyageur suivie de sa
 * fiche — les vocaux racontés depuis l'accueil, les comptes du seed, un
 * souvenir posté par `POST /v1/memos/:id/entries`. Le voyageur les retrouve
 * dans son fil au lieu de croire qu'il les a perdus (`docs/conversation.md`
 * § 2). Un souvenir antérieur à `chatClearedAt` ne revient pas : on a effacé
 * ce qu'on s'est dit, pas fait comme si on ne s'était jamais parlé.
 *
 * Idempotent : un souvenir déjà porté par un message n'est pas retouché. À
 * appeler dans une transaction, après ``ensureOpening``.
 *
 * @returns le nombre de souvenirs matérialisés.
 */
export async function materializeEntriesWithoutMessages(
  db: Db,
  memo: Pick<Memo, "id" | "chatClearedAt">,
): Promise<number> {
  const orphans = await db.entry.findMany({
    where: {
      memoId: memo.id,
      chatMessages: { none: {} },
      ...(memo.chatClearedAt ? { capturedAt: { gt: memo.chatClearedAt } } : {}),
    },
    include: { media: true },
    orderBy: { capturedAt: "asc" },
  });

  // Plusieurs photos envoyées ensemble partagent **une** bulle : seule la
  // première y est rattachée par `entryId`, les autres par `payload.entryIds`.
  // Sans ce filtre, chaque relecture du fil leur fabriquait une bulle de plus.
  const grouped = new Set<string>();
  if (orphans.some((entry) => entry.kind === "photo")) {
    const photoMessages = await db.chatMessage.findMany({
      where: { memoId: memo.id, kind: "photos" },
      select: { payload: true },
    });
    for (const { payload } of photoMessages) {
      const ids = payload && typeof payload === "object" ? (payload as { entryIds?: unknown }).entryIds : undefined;
      if (Array.isArray(ids)) for (const id of ids) if (typeof id === "string") grouped.add(id);
    }
  }

  const toMaterialize = orphans.filter((candidate) => !grouped.has(candidate.id));
  for (const entry of toMaterialize) {
    const kind = messageKindFor(entry.kind);
    const bubble = await db.chatMessage.create({
      data: {
        memoId: memo.id,
        author: "traveller",
        kind,
        text: kind === "text" ? entry.transcript : null,
        entryId: entry.id,
        disposition: "memory",
        stepId: entry.stepId,
        // Un souvenir d'avant le fil n'attend aucune réponse : le tour est clos.
        repliedAt: entry.capturedAt,
        payload: kind === "photos" ? { entryIds: [entry.id] } : undefined,
      },
    });

    if (kind !== "photos") {
      await db.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "transcript",
          entryId: entry.id,
          replyToId: bubble.id,
          stepId: entry.stepId,
          pauseMilliseconds: pauseBeforeTranscript(entry.media?.durationSeconds ?? null),
          model: "scripted",
        },
      });
    }
  }

  return toMaterialize.length;
}

// ---------------------------------------------------------------------------
// Ce que le répondeur relit
// ---------------------------------------------------------------------------

/** Le prénom seul : c'est ainsi que MEMO nomme quelqu'un, et ce que la bulle affiche. */
export function firstNameOf(
  account: { firstName: string | null; lastName: string | null } | null,
): string | null {
  const first = account?.firstName?.trim();
  if (first) return first;
  const last = account?.lastName?.trim();
  return last || null;
}

function truncateForHistory(text: string | null): string | null {
  if (!text) return null;
  return text.length > HISTORY_TEXT_LIMIT ? `${text.slice(0, HISTORY_TEXT_LIMIT - 1)}…` : text;
}

/** Ce qu'un message dit, pour l'historique : son texte, ou le texte de son souvenir. */
export function historyTextOf(message: ChatMessageRow): string | null {
  if (message.kind === "photos") return null;
  if (message.kind === "text") return message.text;
  // Un vocal du contexte du voyage n'a pas de souvenir, et une correction
  // dictée vise celui d'une fiche sans en être un : leur transcription est
  // gardée sur le message lui-même.
  if (contextVoiceOf(message.payload)) return message.text;
  return message.entry ? finalTextOf(message.entry) : message.text;
}

/** Les vingt tours qui précèdent `beforeSeq`, du plus ancien au plus récent. */
export async function loadHistory(
  db: Db,
  memoId: string,
  beforeSeq: number,
): Promise<ConversationHistoryTurn[]> {
  const rows = await db.chatMessage.findMany({
    where: { memoId, seq: { lt: beforeSeq } },
    include: chatMessageInclude,
    orderBy: { seq: "desc" },
    take: HISTORY_LIMIT,
  });

  return rows.reverse().map((row) => ({
    author: row.author,
    authorName: row.author === "traveller" ? firstNameOf(row.account) : null,
    kind: row.kind,
    text: truncateForHistory(historyTextOf(row)),
    disposition: row.disposition,
    sentAt: row.createdAt,
  }));
}

/**
 * Le souvenir en cours : celui du dernier tour `memory` **non photo** avant
 * `beforeSeq`. C'est lui qu'une précision enrichit, et lui dont la validation
 * autorise la rose, l'épine et la graine.
 */
export async function loadCurrentEntry(
  db: Db,
  memoId: string,
  beforeSeq: number,
): Promise<CurrentEntry | null> {
  const row = await db.chatMessage.findFirst({
    where: {
      memoId,
      seq: { lt: beforeSeq },
      author: "traveller",
      disposition: "memory",
      kind: { not: "photos" },
      entryId: { not: null },
    },
    include: { entry: true },
    orderBy: { seq: "desc" },
  });

  const entry = row?.entry;
  if (!entry) return null;

  return {
    id: entry.id,
    text: finalTextOf(entry),
    redactionStatus: entry.redactionStatus,
    validatedAt: entry.validatedAt,
    capturedAt: entry.capturedAt,
    placeLabel: entry.placeLabel,
  };
}

/**
 * Le récit que des photos viennent illustrer : celui dont MEMO a demandé les
 * photos en dernier (`payload.asksPhotosFor`). C'est ce qui les range dans la
 * bonne étape — même quand MEMO est revenu à une étape laissée en plan
 * (`services/tripFacts.ts`).
 */
export async function photosTargetEntryId(db: Db, memoId: string): Promise<string | null> {
  const question = await db.chatMessage.findFirst({
    where: { memoId, author: "memo", kind: "text", payload: { path: ["asksPhotosFor"], not: Prisma.AnyNull } },
    orderBy: { seq: "desc" },
    select: { payload: true },
  });
  const entryId = (question?.payload as { asksPhotosFor?: unknown } | null)?.asksPhotosFor;
  if (typeof entryId !== "string") return null;
  const entry = await db.entry.findFirst({
    where: { id: entryId, memoId, kind: { not: "photo" } },
    select: { id: true },
  });
  return entry?.id ?? null;
}

/** Les trois derniers souvenirs rédigés — exactement ce que reçoit la rédaction. */
export async function loadRecentEntries(db: Db, memoId: string): Promise<RedactedNeighbour[]> {
  const rows = await db.entry.findMany({
    where: {
      memoId,
      kind: { not: "photo" },
      OR: [{ editedText: { not: null } }, { redactedText: { not: null } }],
    },
    orderBy: { capturedAt: "desc" },
    take: 3,
  });

  return rows.reverse().flatMap((row) => {
    const text = row.editedText ?? row.redactedText;
    if (!text) return [];
    return [{ capturedAt: row.capturedAt, placeLabel: row.placeLabel, title: row.suggestedTitle, text }];
  });
}

// ---------------------------------------------------------------------------
// L'étape active, le plafond, la rose/épine/graine
// ---------------------------------------------------------------------------

/** L'étape dont les dates contiennent `now`, sinon la dernière par numéro, sinon rien. */
export function activeStepOf(steps: MemoStep[], now: Date): MemoStep | null {
  const current = steps.find(
    (step) =>
      step.startDate !== null &&
      step.endDate !== null &&
      step.startDate.getTime() <= now.getTime() &&
      now.getTime() <= step.endDate.getTime() + 86_400_000,
  );
  if (current) return current;
  return [...steps].sort((a, b) => b.number - a.number)[0] ?? null;
}

/** Les tours du voyageur depuis minuit UTC — ce que le plafond quotidien compte. */
export async function dailyTurnCount(db: Db, memoId: string, now: Date): Promise<number> {
  const startOfDay = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  return db.chatMessage.count({
    where: { memoId, author: "traveller", createdAt: { gte: startOfDay } },
  });
}

/** Un tour du voyageur encore sans réponse, et pas trop vieux pour qu'on l'attende encore. */
export const REPLY_TIMEOUT_MS = 2 * 60_000;

export async function findTurnInFlight(
  db: Db,
  memoId: string,
  now: Date,
): Promise<{ id: string } | null> {
  return db.chatMessage.findFirst({
    where: {
      memoId,
      author: "traveller",
      repliedAt: null,
      createdAt: { gt: new Date(now.getTime() - REPLY_TIMEOUT_MS) },
    },
    select: { id: true },
    orderBy: { seq: "desc" },
  });
}

/**
 * La rose, l'épine et la graine se posent quand le souvenir en cours est
 * validé, que sa journée n'a pas encore été close, et qu'on est en fin de
 * journée — 17 h heure de Paris, faute de connaître le fuseau du voyageur —
 * ou que l'étape se termine.
 */
export function allowsRoseEpineGraine(
  current: CurrentEntry | null,
  state: ConversationState,
  step: MemoStep | null,
  now: Date,
): boolean {
  if (!current?.validatedAt) return false;
  if (state.roseEpineGraineAskedFor.includes(dayKeyOf(current.capturedAt))) return false;

  const lateInTheDay = now.getUTCHours() >= 15;
  const stepEndsToday =
    step?.endDate !== null && step?.endDate !== undefined && dayKeyOf(step.endDate) === dayKeyOf(now);
  return lateInTheDay || stepEndsToday;
}

export function conversationStateOf(memo: Pick<Memo, "conversationState">): ConversationState {
  return parseConversationState(memo.conversationState);
}

/**
 * « Il te convient ? » — la seule question qui suit un souvenir, posée quand
 * son texte est prêt (rédigé, ou brut si la rédaction a échoué). Appelée par le
 * job de rédaction, qui sait seul quand le texte est là.
 *
 * Rien à demander pour un souvenir sans fiche dans le fil (raconté depuis
 * l'accueil), ni pour un souvenir déjà validé. Et jamais deux fois de suite :
 * si la dernière bulle de MEMO pose déjà la question pour ce souvenir — une
 * rédaction rejouée après un échec —, on ne la repose pas. Une précision qui
 * fait réécrire le texte, elle, la fait revenir : le texte a changé.
 *
 * ⚠️ **La bulle ne cite plus les passages incompris** (Hugo, 16/11/2026).
 * L'écrivain continue de ne rien imprimer qu'il n'ait compris — c'est ce qui
 * empêche le carnet de mentir —, mais le dire à chaque souvenir sonnait comme
 * un refus. Le passage reste lisible dans « Mot pour mot ». Voir
 * ``redactionKept``.
 */
/**
 * **« J'ai entendu plusieurs moments : je les sépare ? »** (Hugo,
 * 28/10/2026).
 *
 * Posée à la place de « Il te convient ? » quand l'écrivain a trouvé où
 * couper : si l'on sépare, les textes changent entièrement, et valider
 * d'abord ne servirait à rien. La question **nomme** les moments — c'est ce
 * qui dit où la coupe tombe.
 *
 * Elle mène aux mêmes puces que la question de la longueur
 * (``LONG_MESSAGE``), et donc au même effet : le découpage a lieu dans le job
 * de conversation, à la réponse.
 *
 * - Returns: `true` quand la question a été posée — l'appelant ne demande
 *   alors pas la validation.
 */
export async function askToSplit(
  db: Db,
  entryId: string,
  moments: readonly { title: string }[],
): Promise<boolean> {
  if (moments.length < 2) return false;

  const card = await db.chatMessage.findFirst({
    where: { entryId, author: "memo", kind: "transcript" },
    include: { entry: { select: { validatedAt: true } } },
    orderBy: { seq: "desc" },
  });
  // Un souvenir déjà validé ne se redécoupe pas : on ne revient pas sur ce
  // qui est réglé.
  if (!card || card.entry?.validatedAt) return false;

  const question = splitQuestionFor(moments.map((moment) => moment.title));
  await db.chatMessage.create({
    data: {
      memoId: card.memoId,
      author: "memo",
      kind: "text",
      text: question,
      replyToId: card.replyToId,
      stepId: card.stepId,
      pauseMilliseconds: pauseBeforeSaying(question),
      model: "scripted",
      // `asksSplitFor` : c'est lui qui dit **quel** souvenir la réponse
      // découpe, quand elle arrivera.
      payload: { suggestions: [...SUGGESTION_SETS.split], asksSplitFor: entryId },
    },
  });
  return true;
}

/**
 * **« Ça s'écrit comment ? »** (T282, 20/11/2026).
 *
 * Posée à la place de la bulle « Voilà ton texte » quand l'écrivain a entendu
 * un nom propre sans pouvoir l'écrire (``RedactionResult/namesToConfirm``).
 * Le voyageur répond son orthographe ; elle arrive comme une **précision**
 * ordinaire, la rédaction repasse avec, et la fiche de cohérence fige enfin
 * la bonne graphie pour tout le carnet.
 *
 * **Un seul nom**, le premier : deux questions dans une bulle, c'est un
 * formulaire. Et aucune puce — une orthographe ne se choisit pas dans une
 * liste.
 *
 * - Returns: `true` quand la question a été posée ; l'appelant ne confirme
 *   alors pas la rédaction, exactement comme pour le découpage.
 */
export async function askToConfirmName(
  db: Db,
  entryId: string,
  names: readonly string[],
): Promise<boolean> {
  const name = names[0]?.trim();
  if (!name) return false;

  const card = await db.chatMessage.findFirst({
    where: { entryId, author: "memo", kind: "transcript" },
    include: { entry: { select: { validatedAt: true } } },
    orderBy: { seq: "desc" },
  });
  // Un souvenir déjà validé ne se rouvre pas pour une orthographe : on ne
  // revient pas sur ce qui est réglé.
  if (!card || card.entry?.validatedAt) return false;

  const question = nameQuestionFor(name);
  await db.chatMessage.create({
    data: {
      memoId: card.memoId,
      author: "memo",
      kind: "text",
      text: question,
      replyToId: card.replyToId,
      stepId: card.stepId,
      pauseMilliseconds: pauseBeforeSaying(question),
      model: "scripted",
    },
  });
  return true;
}

/**
 * **« Ton carnet fait maintenant 84 pages »** (T265, 24/11/2026).
 *
 * Dit après une composition qui change le **prix** du carnet — pas à chaque
 * changement de pagination, qui arrive à toutes les compositions et que
 * l'accueil affiche déjà. Le raisonnement est dans
 * `services/pageCountChange.ts`.
 *
 * **Une bulle, pas une question** : rien à décider, rien à répondre. Elle ne
 * porte donc aucune puce et ne remplace aucune autre bulle — elle arrive
 * après, quand le carnet s'est recomposé, souvent longtemps après le dernier
 * message.
 *
 * - Returns: `true` quand la bulle a été posée.
 */
export async function tellPageCountChanged(db: Db, memoId: string, texte: string): Promise<boolean> {
  // Le même changement ne se dit pas deux fois : deux compositions de suite
  // peuvent franchir le même palier dans les deux sens, et le fil n'a pas à
  // compter les allers-retours. On ne regarde que la dernière bulle du genre.
  const deja = await db.chatMessage.findFirst({
    where: {
      memoId,
      author: "memo",
      kind: "text",
      payload: { path: ["tellsPageCount"], not: Prisma.AnyNull },
    },
    orderBy: { seq: "desc" },
    select: { text: true },
  });
  if (deja?.text === texte) return false;

  await db.chatMessage.create({
    data: {
      memoId,
      author: "memo",
      kind: "text",
      text: texte,
      pauseMilliseconds: pauseBeforeSaying(texte),
      model: "scripted",
      payload: { tellsPageCount: true },
    },
  });
  return true;
}

/**
 * **« On était où ? »** (T267, 23/11/2026).
 *
 * Posée quand l'étape de ce souvenir n'a **aucun lieu** : ni son récit, ni
 * ceux qui l'accompagnent, ni la position d'une de ses photos. Le carnet
 * imprimerait alors un en-tête avec sa date seule — ce que Hugo a vu revenir
 * du Japon.
 *
 * ⚠️ **Elle suppose les étapes à jour** : c'est le recalcul des faits qui
 * vient de ranger ce souvenir dans une étape et de lui donner son lieu
 * (`services/tripFacts.ts`), et `jobs/redact.ts` l'appelle désormais avant
 * ses questions pour cette seule raison. Demandée avant lui, elle demanderait
 * un lieu que le texte qu'on vient d'écrire est peut-être en train de donner.
 *
 * **Elle est un barreau de la chaîne**, posée à la place de la bulle qui garde
 * le texte — comme le découpage et le prénom. Ce n'est pas un détail d'ordre :
 * cette bulle **valide** le souvenir, et un souvenir validé n'accepte plus de
 * précision. Posée après elle, la question n'aurait eu nulle part où ranger la
 * réponse.
 *
 * **Une fois par étape, et jamais deux** (`payload.asksPlaceFor`) : une étape
 * muette reçoit dix souvenirs, elle ne reçoit pas dix questions. Si le
 * voyageur ne répond pas, le carnet s'imprime avec sa date — c'est ce que la
 * question annonce, et c'est une réponse comme une autre.
 *
 * - Returns: `true` quand la question a été posée.
 */
export async function askForPlace(db: Db, entryId: string): Promise<boolean> {
  const entry = await db.entry.findUnique({
    where: { id: entryId },
    select: { memoId: true, stepId: true, capturedAt: true },
  });
  // Sans étape, il n'y a pas encore d'en-tête à nommer : le prochain passage
  // des faits en ouvrira une, et c'est lui qui demandera s'il le faut.
  if (!entry?.stepId) return false;

  const step = await db.memoStep.findUnique({
    where: { id: entry.stepId },
    select: { placeName: true },
  });
  if (!step || (step.placeName ?? "").trim() !== "") return false;

  // **Une question par journée, et non par étape.** Un jour sans lieu n'a rien
  // qui tienne ses souvenirs ensemble : sans lieu commun et sans continuité,
  // chacun ouvre son étape (`groupIntoSteps`), et demander par étape
  // reviendrait à demander à chaque souvenir. La journée, elle, ne bouge pas
  // d'un recalcul à l'autre — et c'est elle que le carnet imprime en en-tête,
  // c'est elle que le ticket compte.
  const jour = localDate(entry.capturedAt);
  const dejaDemande = await db.chatMessage.findFirst({
    where: {
      memoId: entry.memoId,
      author: "memo",
      kind: "text",
      payload: { path: ["asksPlaceFor"], equals: jour },
    },
    select: { id: true },
  });
  if (dejaDemande) return false;


  const card = await db.chatMessage.findFirst({
    where: { entryId, author: "memo", kind: "transcript" },
    orderBy: { seq: "desc" },
    select: { memoId: true, replyToId: true },
  });
  if (!card) return false;

  const question = placeQuestionFor();
  await db.chatMessage.create({
    data: {
      memoId: card.memoId,
      author: "memo",
      kind: "text",
      text: question,
      replyToId: card.replyToId,
      stepId: entry.stepId,
      pauseMilliseconds: pauseBeforeSaying(question),
      model: "scripted",
      payload: { asksPlaceFor: jour },
    },
  });
  return true;
}

/**
 * **Le texte rédigé est gardé d'office** (Hugo, 03/11/2026 : « on veut que ce
 * soit bon du premier coup et qu'on n'ait pas d'action supplémentaire à
 * rajouter »).
 *
 * La rédaction finie, le souvenir est validé, MEMO le dit, et il enchaîne sur
 * les photos qu'il lui faut — ce que « Ça me convient » faisait avant en un
 * appui de plus. Retoucher reste sous la bulle, à la main ou à l'oral.
 *
 * `asksPhotosFor` part avec la bulle : c'est lui qui rangera les photos qui
 * suivent dans l'étape de **ce** récit (`photosTargetEntryId`).
 *
 * **Elle parle aussi quand la rédaction a échoué** : le mot-pour-mot part
 * dans le carnet, le souvenir compte, et MEMO le dit — mais sans prétendre
 * l'avoir écrit (``REDACTION_UNWRITTEN``).
 *
 * Rend `false` quand il n'y a rien à dire — pas de fiche, ou un souvenir déjà
 * validé —, exactement comme la question qu'elle remplace.
 */
export async function confirmRedaction(db: Db, entryId: string): Promise<boolean> {
  const card = await db.chatMessage.findFirst({
    where: { entryId, author: "memo", kind: "transcript" },
    include: { entry: true },
    orderBy: { seq: "desc" },
  });
  if (!card?.entry || card.entry.validatedAt) return false;

  // Idempotent : deux rédactions pour un même souvenir ne le valident qu'une
  // fois, et la seconde ne reparle pas.
  const { count } = await db.entry.updateMany({
    where: { id: entryId, validatedAt: null },
    data: { validatedAt: new Date() },
  });
  if (count === 0) return false;

  // ⚠️ **La bulle ne doit pas démentir la fiche** (17/11/2026). Appelée aussi
  // depuis le `catch` de la rédaction (`jobs/redact.ts`), elle disait « Voilà
  // ton texte pour le carnet » au-dessus d'une fiche qui venait d'annoncer
  // qu'elle n'avait pas réussi à l'écrire — et c'est la bulle qu'on lit en
  // dernier. Voir ``REDACTION_UNWRITTEN`` : deux semaines de rédactions
  // tombées faute de crédit ont été annoncées comme des succès.
  //
  // L'état se **lit** ici, plutôt que de se passer en paramètre : les deux
  // appels viennent du même job, à une ligne d'écart, et un drapeau qu'on
  // oublie de passer rendrait le mensonge silencieux. Le `catch` écrit
  // `failed` avant d'appeler, et le chemin heureux `ready` : la fiche relue
  // juste au-dessus porte déjà le bon état.
  const kept = card.entry.redactionStatus === "failed" ? REDACTION_UNWRITTEN : redactionKept();
  const written = finalTextOf(card.entry)?.trim() ?? "";
  const budget = written ? await photoRequestFor(db, card.memoId, written) : null;
  // À 0 % de photos, le carnet n'en porte aucune : on ne réclame pas au
  // voyageur des images que le gabarit jettera.
  const asksPhotos = budget !== null && budget.photos > 0;

  const beats = asksPhotos
    ? [kept, photosWanted(budget.photos, budget.pages, forTargetOf(budget))]
    : [kept];

  for (const [index, text] of beats.entries()) {
    const isLast = index === beats.length - 1;
    await db.chatMessage.create({
      data: {
        memoId: card.memoId,
        author: "memo",
        kind: "text",
        text,
        replyToId: card.replyToId,
        stepId: card.stepId,
        pauseMilliseconds: pauseBeforeSaying(text),
        model: "scripted",
        payload: isLast
          ? {
              suggestions: [
                ...(asksPhotos
                  ? SUGGESTION_SETS.afterRedaction
                  : SUGGESTION_SETS.afterRedactionWithoutPhotos),
              ],
              ...(asksPhotos ? { asksPhotosFor: entryId, photosAsked: budget.photos } : {}),
            }
          : undefined,
      },
    });
  }
  return true;
}

/**
 * La question d'avant — « Il te convient ? ». Elle ne se pose plus dans le
 * déroulé (voir ``confirmRedaction``), et reste pour l'étape sautée à
 * laquelle MEMO revient : celle-là n'a jamais été validée, et c'est bien une
 * question qu'on lui pose.
 */
export async function askValidation(db: Db, entryId: string): Promise<boolean> {
  const card = await db.chatMessage.findFirst({
    where: { entryId, author: "memo", kind: "transcript" },
    include: { entry: { select: { validatedAt: true } } },
    orderBy: { seq: "desc" },
  });
  if (!card || card.entry?.validatedAt) return false;

  const lastMemo = await db.chatMessage.findFirst({
    where: { memoId: card.memoId, author: "memo", kind: "text" },
    orderBy: { seq: "desc" },
    select: { payload: true, seq: true },
  });
  const lastAsked =
    lastMemo?.payload && typeof lastMemo.payload === "object"
      ? (lastMemo.payload as { asksValidationFor?: unknown }).asksValidationFor
      : undefined;
  if (lastAsked === entryId) {
    // Déjà posée, et aucun tour du voyageur depuis : rien de neuf à demander.
    const since = await db.chatMessage.count({
      where: { memoId: card.memoId, author: "traveller", seq: { gt: lastMemo!.seq } },
    });
    if (since === 0) return false;
  }

  const question = validationQuestion();
  await db.chatMessage.create({
    data: {
      memoId: card.memoId,
      author: "memo",
      kind: "text",
      text: question,
      replyToId: card.replyToId,
      stepId: card.stepId,
      pauseMilliseconds: pauseBeforeSaying(question),
      model: "scripted",
      payload: { suggestions: [...SUGGESTION_SETS.trio], asksValidationFor: entryId },
    },
  });
  return true;
}
