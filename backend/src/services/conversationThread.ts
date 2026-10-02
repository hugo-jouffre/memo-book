import type { ChatMessage, Entry, MediaAsset, Memo, MemoStep, Prisma, PrismaClient } from "@prisma/client";
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
import { OPENING_PAUSE_MS, SUGGESTION_SETS, VALIDATION_QUESTION } from "./conversationCopy.js";
import type { RedactedNeighbour } from "./redaction.js";

/**
 * Le fil d'un carnet, vu du serveur : ce que les routes et le job `converse`
 * ont en commun et qui n'est ni une réponse ni une sérialisation.
 */

/** Le client d'une transaction, ou le client tout court : les deux lisent et écrivent pareil. */
export type Db = PrismaClient | Prisma.TransactionClient;

export type EntryWithMedia = Entry & { media: MediaAsset | null };

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
  entry: { include: { media: true } },
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
): Promise<ChatMessage | null> {
  const existing = await db.chatMessage.findFirst({ where: { memoId }, select: { id: true } });
  if (existing) return null;

  const opening = responder.opening();
  return db.chatMessage.create({
    data: {
      memoId,
      author: "memo",
      kind: "text",
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
  // Un vocal du contexte du voyage n'a pas de souvenir : sa transcription est
  // gardée sur le message lui-même.
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

  await db.chatMessage.create({
    data: {
      memoId: card.memoId,
      author: "memo",
      kind: "text",
      text: VALIDATION_QUESTION,
      replyToId: card.replyToId,
      stepId: card.stepId,
      pauseMilliseconds: pauseBeforeSaying(VALIDATION_QUESTION),
      model: "scripted",
      payload: { suggestions: [...SUGGESTION_SETS.trio], asksValidationFor: entryId },
    },
  });
  return true;
}
