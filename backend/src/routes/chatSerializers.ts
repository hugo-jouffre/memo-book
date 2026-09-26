import type { Account, Memo, MemoMember, MemoStep } from "@prisma/client";
import { finalTextOf } from "../jobs/redact.js";
import {
  GREETING_MESSAGE,
  SUGGESTION_SETS,
  TRANSCRIPT_FOOTNOTE,
  TRANSCRIPT_TITLE,
  greetingTitle,
  suggestionsFor,
  type Suggestion,
} from "../services/conversationCopy.js";
import { firstNameOf, type ChatMessageRow, type EntryWithMedia } from "../services/conversationThread.js";
import { avatarUrlOf } from "../services/avatars.js";

/**
 * Ce que l'écran de conversation reçoit.
 *
 * Même règle qu'`appSerializers.ts` : la forme suit **les modèles Swift** de
 * `MemoBookCore/Chat.swift` au champ près — `ChatThread`, `ChatMessage`,
 * `ChatMessageBody` (discriminée par `kind`), `TranscriptCard`, `VoiceNote`,
 * `PhotoAttachment`, `ChatSuggestion`, `ChatContext`, `ChatBookPreview`,
 * `ChatGreeting`. Un champ renommé d'un côté casse le décodage de l'autre.
 *
 * Ce qui s'ajoute par rapport au jeu d'essai de l'app — `seq`, `authorName`,
 * `pauseMilliseconds`, `disposition`, `phase`, `isValidated`, `turn`,
 * `canClear`, `now` — est **optionnel au décodage** côté Swift : un fil
 * d'aperçu qui ne les porte pas décode encore.
 */

export type ChatTurnStatus =
  | { status: "idle" }
  | { status: "replying"; messageId: string };

/** Où en est la fiche d'un souvenir : ce que la bulle dessine en trois temps. */
export type TranscriptPhase = "listening" | "writing" | "ready" | "failed";

export function transcriptPhaseOf(entry: EntryWithMedia): TranscriptPhase {
  if (entry.status === "failed" || entry.redactionStatus === "failed") return "failed";
  if (entry.status === "pending" || entry.status === "processing") return "listening";
  if (entry.redactionStatus === "pending" || entry.redactionStatus === "processing") return "writing";
  return "ready";
}

/** Le drapeau d'un code ISO 3166-1 alpha-2, ou rien : mieux vaut pas de drapeau qu'un carré blanc. */
export function flagOf(countryCode: string | null): string | null {
  if (!countryCode || !/^[A-Za-z]{2}$/.test(countryCode)) return null;
  return String.fromCodePoint(
    ...[...countryCode.toUpperCase()].map((letter) => 0x1f1e6 + letter.charCodeAt(0) - 65),
  );
}

/** L'adresse d'un média servi par l'API, avec la session — `GET /v1/entries/:id/media`. */
export function mediaUrlOf(publicBaseUrl: string, entryId: string): string {
  return `${publicBaseUrl}/v1/entries/${entryId}/media`;
}

/**
 * Une ou deux initiales, quand la photo manque — la même règle que l'app
 * (`TravellerProfile.initials`) : la première lettre des deux premiers mots du
 * nom complet.
 */
export function initialsOf(
  account: { firstName: string | null; lastName: string | null } | null,
): string | null {
  const words = [account?.firstName, account?.lastName]
    .join(" ")
    .split(/\s+/)
    .filter((word) => word.length > 0)
    .slice(0, 2);
  const initials = words.map((word) => word[0]!.toUpperCase()).join("");
  return initials.length > 0 ? initials : null;
}

function levelsOf(payload: unknown): number[] {
  if (!payload || typeof payload !== "object") return [];
  const levels = (payload as { levels?: unknown }).levels;
  if (!Array.isArray(levels)) return [];
  return levels
    .filter((level): level is number => typeof level === "number" && Number.isFinite(level))
    .map((level) => Math.min(1, Math.max(0, level)));
}

function entryIdsOf(payload: unknown, fallback: string | null): string[] {
  const ids =
    payload && typeof payload === "object" ? (payload as { entryIds?: unknown }).entryIds : undefined;
  if (Array.isArray(ids)) {
    const strings = ids.filter((id): id is string => typeof id === "string");
    if (strings.length > 0) return strings;
  }
  return fallback ? [fallback] : [];
}

export function suggestionIdsOf(payload: unknown): string[] {
  const ids =
    payload && typeof payload === "object"
      ? (payload as { suggestions?: unknown }).suggestions
      : undefined;
  return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === "string") : [];
}

// ---------------------------------------------------------------------------
// Un message
// ---------------------------------------------------------------------------

export interface SerializeMessageOptions {
  /** Le compte qui lit : ses propres bulles n'ont pas de prénom, MEMO non plus. */
  viewerAccountId: string;
  /** Le fil est-il à plusieurs ? Seul, personne n'a besoin d'une légende. */
  showsAuthors: boolean;
  publicBaseUrl: string;
}

function serializeBody(message: ChatMessageRow, publicBaseUrl: string) {
  switch (message.kind) {
    case "text":
      return { kind: "text" as const, text: message.text ?? "" };

    case "voice": {
      const entry = message.entry;
      return {
        kind: "voice" as const,
        voice: {
          id: message.id,
          duration: entry?.media?.durationSeconds ?? 0,
          levels: levelsOf(message.payload),
          remoteUrl: entry ? mediaUrlOf(publicBaseUrl, entry.id) : null,
        },
      };
    }

    case "photos":
      return {
        kind: "photos" as const,
        photos: entryIdsOf(message.payload, message.entryId).map((entryId) => ({
          id: entryId,
          remoteUrl: mediaUrlOf(publicBaseUrl, entryId),
        })),
      };

    case "transcript": {
      // La fiche se redessine depuis le souvenir à chaque lecture : elle ne
      // recopie rien, et ne peut donc pas être périmée.
      const entry = message.entry;
      if (!entry) return null;
      const phase = transcriptPhaseOf(entry);
      return {
        kind: "transcript" as const,
        transcript: {
          title: TRANSCRIPT_TITLE,
          capturedAt: entry.capturedAt.toISOString(),
          placeLabel: entry.placeLabel,
          duration: entry.media?.durationSeconds ?? null,
          text: finalTextOf(entry),
          isSimulated: false,
          entryId: entry.id,
          footnote: phase === "ready" ? TRANSCRIPT_FOOTNOTE : null,
          phase,
          isValidated: entry.validatedAt !== null,
        },
      };
    }
  }
}

/**
 * Une bulle, ou `null` pour une fiche dont le souvenir a disparu — le fil
 * reste lisible sans elle.
 *
 * `sentAt` d'une bulle du voyageur est la date **du souvenir**, pas celle de
 * l'écriture : un vocal reconstruit depuis l'accueil garde le jour où il a été
 * raconté. Les bulles de MEMO et les textes datent de leur écriture.
 */
export function serializeChatMessage(message: ChatMessageRow, options: SerializeMessageOptions) {
  const body = serializeBody(message, options.publicBaseUrl);
  if (!body) return null;

  const isOtherTraveller =
    message.author === "traveller" &&
    options.showsAuthors &&
    message.accountId !== null &&
    message.accountId !== options.viewerAccountId;

  const sentAt =
    message.author === "traveller" && message.entry && message.kind !== "text"
      ? message.entry.capturedAt
      : message.createdAt;

  return {
    id: message.id,
    seq: message.seq,
    author: message.author,
    authorName: isOtherTraveller ? firstNameOf(message.account) : null,
    // Le portrait de celui qui a parlé, **sur toutes les bulles du voyageur** —
    // les siennes comme celles des autres : c'est lui que la bulle d'un vocal
    // montre, pas un signe de la marque.
    authorInitials: message.author === "traveller" ? initialsOf(message.account) : null,
    authorAvatarUrl:
      message.author === "traveller" && message.account ? avatarUrlOf(message.account) : null,
    body,
    sentAt: sentAt.toISOString(),
    stepId: message.stepId,
    disposition: message.disposition,
    pauseMilliseconds: message.pauseMilliseconds,
  };
}

export function serializeChatSuggestions(ids: readonly string[]): Suggestion[] {
  return suggestionsFor(ids);
}

// ---------------------------------------------------------------------------
// Le fil
// ---------------------------------------------------------------------------

export type MemoForChat = Memo & {
  owner: Account;
  members: (MemoMember & { account: Account | null })[];
  steps: MemoStep[];
};

export interface SerializeThreadOptions {
  memo: MemoForChat;
  messages: ChatMessageRow[];
  viewer: Pick<Account, "id" | "firstName" | "lastName" | "avatarStorageKey" | "avatarUrl">;
  activeStep: MemoStep | null;
  /** `count(entries kind ≠ photo)` — `memos.memoryCount` n'est écrit que par le seed. */
  memoryCount: number;
  hasReadyRender: boolean;
  turn: ChatTurnStatus;
  publicBaseUrl: string;
  now: Date;
}

/**
 * Les puces à proposer : celles de la dernière bulle de MEMO ; sous une fiche
 * qui clôt le fil (un souvenir reconstruit), le trio de validation tant
 * qu'elle n'est pas relue, puis de quoi continuer ; rien pendant un tour en vol.
 */
export function currentSuggestionIds(messages: ChatMessageRow[], turn: ChatTurnStatus): string[] {
  if (turn.status === "replying") return [];
  if (messages.length === 0) return [...SUGGESTION_SETS.opening];

  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index]!;
    if (message.author === "traveller") return [...SUGGESTION_SETS.neutral];
    if (message.kind === "transcript") {
      if (!message.entry) continue;
      return message.entry.validatedAt ? [...SUGGESTION_SETS.afterAccept] : [...SUGGESTION_SETS.trio];
    }
    if (message.kind !== "text") continue;
    const ids = suggestionIdsOf(message.payload);
    if (ids.length > 0) return ids;
  }
  return [...SUGGESTION_SETS.neutral];
}

export function serializeChatThread(options: SerializeThreadOptions) {
  const { memo, viewer, activeStep } = options;
  const memberCount = 1 + memo.members.filter((member) => member.status === "active").length;
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: viewer.id,
    showsAuthors: memberCount > 1,
    publicBaseUrl: options.publicBaseUrl,
  };

  const messages = options.messages
    .map((message) => serializeChatMessage(message, messageOptions))
    .filter((message) => message !== null);

  const flag = flagOf(memo.destinationCountryCode);
  const placeName = activeStep?.placeName ?? memo.destinationCity ?? null;
  const pageCount = memo.pageCount > 0 ? memo.pageCount : options.memoryCount * 2;

  return {
    id: memo.id,
    title: memo.title,
    avatarUrl: memo.coverPhotoUrl,
    destination: memo.destinationName
      ? {
          name: memo.destinationName,
          countryCode: memo.destinationCountryCode,
          city: memo.destinationCity ?? null,
        }
      : null,
    greeting: {
      title: greetingTitle(memo.destinationCity ?? memo.destinationName, flag),
      message: GREETING_MESSAGE,
    },
    // Un voyage sans souvenir n'a pas de carnet à annoncer : la bannière reste absente.
    preview:
      options.memoryCount > 0
        ? { memoryCount: options.memoryCount, pageCount, isOpenable: options.hasReadyRender }
        : null,
    context: {
      tripId: memo.id,
      tripTitle: memo.title,
      travellerFirstName: firstNameOf(viewer),
      // Le portrait de celui qui lit, pour ses bulles qui ne sont pas encore
      // parties : elles n'ont pas de réponse du serveur où le lire.
      travellerInitials: initialsOf(viewer),
      travellerAvatarUrl: avatarUrlOf(viewer),
      placeName,
      stepNumber: activeStep?.number ?? null,
      stepId: activeStep?.id ?? null,
      prompt: memo.prompt,
      memberCount,
    },
    messages,
    suggestions: serializeChatSuggestions(currentSuggestionIds(options.messages, options.turn)),
    turn: options.turn,
    canClear: memo.ownerAccountId === viewer.id,
    now: options.now.toISOString(),
  };
}

/** La suite du fil depuis `since` — ce que l'app sonde tant qu'un tour est en vol. */
export function serializeChatUpdate(options: {
  memo: MemoForChat;
  allMessages: ChatMessageRow[];
  changed: ChatMessageRow[];
  viewer: Pick<Account, "id">;
  memoryCount: number;
  hasReadyRender: boolean;
  turn: ChatTurnStatus;
  publicBaseUrl: string;
  now: Date;
}) {
  const memberCount = 1 + options.memo.members.filter((member) => member.status === "active").length;
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: options.viewer.id,
    showsAuthors: memberCount > 1,
    publicBaseUrl: options.publicBaseUrl,
  };
  const pageCount =
    options.memo.pageCount > 0 ? options.memo.pageCount : options.memoryCount * 2;

  return {
    messages: options.changed
      .map((message) => serializeChatMessage(message, messageOptions))
      .filter((message) => message !== null),
    suggestions: serializeChatSuggestions(currentSuggestionIds(options.allMessages, options.turn)),
    preview:
      options.memoryCount > 0
        ? { memoryCount: options.memoryCount, pageCount, isOpenable: options.hasReadyRender }
        : null,
    turn: options.turn,
    now: options.now.toISOString(),
  };
}

/** Ce qu'un `POST` rend : les bulles qu'il vient d'écrire, et l'état du tour. */
export function serializeChatReceipt(options: {
  written: ChatMessageRow[];
  viewerAccountId: string;
  showsAuthors: boolean;
  publicBaseUrl: string;
  turn: ChatTurnStatus;
  now: Date;
}) {
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: options.viewerAccountId,
    showsAuthors: options.showsAuthors,
    publicBaseUrl: options.publicBaseUrl,
  };
  return {
    messages: options.written
      .map((message) => serializeChatMessage(message, messageOptions))
      .filter((message) => message !== null),
    turn: options.turn,
    now: options.now.toISOString(),
  };
}
