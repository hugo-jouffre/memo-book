import type { Account, Memo, MemoMember, MemoStep } from "@prisma/client";
import { finalTextOf } from "../jobs/redact.js";
import { resolveCallToAction } from "../services/callsToAction.js";
import {
  GREETING_MESSAGE,
  SUGGESTION_SETS,
  TRANSCRIPT_FOOTNOTE,
  transcriptTitle,
  greetingTitle,
  suggestionsFor,
  type Suggestion,
} from "../services/conversationCopy.js";
import { firstNameOf, type ChatMessageRow, type EntryWithMedia } from "../services/conversationThread.js";
import { avatarUrlOf } from "../services/avatars.js";
import { LIMITED_AUDIENCE, serializeDailyCredit, type DailyCredit } from "../services/dailyCredit.js";
import {
  contextVoiceOf,
  isGathering,
  parseTripContext,
  serializeTripContext,
  type TripContext,
} from "../services/tripContext.js";

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
 * `canClear`, `now`, `callToAction`, `dailyCredit` — est **optionnel au
 * décodage** côté Swift : un fil d'aperçu qui ne les porte pas décode encore,
 * et une app installée qui ne les connaît pas les ignore.
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

/** Un champ du payload d'une bulle, sans faire confiance à sa forme. */
function payloadField(payload: unknown, key: string): unknown {
  return payload && typeof payload === "object" ? (payload as Record<string, unknown>)[key] : undefined;
}

/**
 * Cette bulle est-elle pour ce lecteur ? Une bulle `audience: "limited"` — la
 * bulle « reviens demain » du crédit du jour — ne parle qu'à ceux qui
 * comptent leur crédit : un abonné n'a pas à lire « reviens demain » dans un
 * fil qu'il partage avec ses co-voyageurs (Hugo, 03/10/2026).
 */
export function isVisibleTo(message: Pick<ChatMessageRow, "author" | "payload">, viewerIsUnlimited: boolean): boolean {
  if (message.author !== "memo") return true;
  return !(viewerIsUnlimited && payloadField(message.payload, "audience") === LIMITED_AUDIENCE);
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
  /** Le numéro d'étape de chaque fiche, par identifiant de message — ``stepNumbersOf``. */
  stepNumbers?: ReadonlyMap<string, number>;
  /**
   * Celui qui lit raconte-t-il sans limite ? Il décide de ce qu'il voit : ni
   * la bulle « reviens demain » (`isVisibleTo`), ni une offre d'abonnement
   * (`resolveCallToAction`).
   */
  viewerIsUnlimited: boolean;
}

/**
 * « Retranscription étape N » : une fiche par souvenir, une étape par
 * souvenir — la N-ième fiche du fil est l'étape N. Calculé sur le fil entier,
 * jamais sur une page de messages.
 */
export function stepNumbersOf(messages: readonly Pick<ChatMessageRow, "id" | "kind" | "seq">[]): Map<string, number> {
  const cards = messages.filter((message) => message.kind === "transcript").sort((a, b) => a.seq - b.seq);
  return new Map(cards.map((card, index) => [card.id, index + 1]));
}

function serializeBody(message: ChatMessageRow, publicBaseUrl: string, stepNumbers?: ReadonlyMap<string, number>) {
  switch (message.kind) {
    case "text":
      return { kind: "text" as const, text: message.text ?? "" };

    case "voice": {
      const entry = message.entry;
      return {
        kind: "voice" as const,
        voice: {
          id: message.id,
          duration: entry?.media?.durationSeconds ?? contextVoiceOf(message.payload)?.durationSeconds ?? 0,
          levels: levelsOf(message.payload),
          // Un vocal du contexte du voyage n'a pas de souvenir : son fichier
          // pend au message (`contextVoiceOf`).
          remoteUrl: entry
            ? mediaUrlOf(publicBaseUrl, entry.id)
            : contextVoiceOf(message.payload)
              ? `${publicBaseUrl}/v1/chat-messages/${message.id}/media`
              : null,
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
          title: transcriptTitle(stepNumbers?.get(message.id) ?? null),
          // Le titre que la rédaction a donné au récit — celui de l'étape dans le carnet.
          heading: phase === "ready" || phase === "failed" ? entry.suggestedTitle : null,
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
 * reste lisible sans elle — et pour une bulle qui ne s'adresse pas à ce
 * lecteur (`isVisibleTo`).
 *
 * `sentAt` d'une bulle du voyageur est la date **du souvenir**, pas celle de
 * l'écriture : un vocal reconstruit depuis l'accueil garde le jour où il a été
 * raconté. Les bulles de MEMO et les textes datent de leur écriture.
 */
export function serializeChatMessage(message: ChatMessageRow, options: SerializeMessageOptions) {
  if (!isVisibleTo(message, options.viewerIsUnlimited)) return null;
  const body = serializeBody(message, options.publicBaseUrl, options.stepNumbers);
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

  // Le bouton sous une bulle de MEMO, résolu **à la lecture** et pour ce
  // lecteur : le payload ne garde que son identifiant (`callsToAction.ts`).
  // Absent plutôt que nul : la clé est neuve, et la plupart des bulles n'en
  // ont pas.
  const callToAction =
    message.author === "memo" && message.kind === "text"
      ? resolveCallToAction(payloadField(message.payload, "callToAction"), {
          isUnlimited: options.viewerIsUnlimited,
        })
      : null;

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
    ...(callToAction ? { callToAction } : {}),
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
  /**
   * `count(entries kind ≠ photo)`, compté à la lecture : `memos.memoryCount`
   * (`services/tripFacts.ts`) n'avance qu'à la fin de la rédaction, et le fil
   * veut le souvenir qu'on vient d'envoyer.
   */
  memoryCount: number;
  hasReadyRender: boolean;
  turn: ChatTurnStatus;
  publicBaseUrl: string;
  now: Date;
  /** Le crédit du jour du voyage, vu par celui qui lit. */
  dailyCredit: DailyCredit;
}

/**
 * Les puces à proposer : celles de la dernière bulle de MEMO ; sous une fiche
 * qui clôt le fil (un souvenir reconstruit), le trio de validation tant
 * qu'elle n'est pas relue, puis de quoi continuer ; rien pendant un tour en vol.
 */
export function currentSuggestionIds(
  messages: ChatMessageRow[],
  turn: ChatTurnStatus,
  tripContext: TripContext | null,
): string[] {
  if (turn.status === "replying") return [];
  // Rien encore dit par le voyageur : l'ouverture, décidée **à la lecture**
  // et non figée dans la bulle — un voyage ouvert avant le contexte du voyage
  // doit proposer lui aussi de le raconter, et un contexte déjà posé (après
  // « Supprimer la conversation ») ne se redemande pas.
  if (!messages.some((message) => message.author === "traveller")) {
    return tripContext && tripContext.status !== "gathering"
      ? [...SUGGESTION_SETS.openingWithContext]
      : [...SUGGESTION_SETS.opening];
  }
  // Pendant le contexte, les puces sont celles que MEMO a posées sous sa
  // dernière bulle — aucune sous l'invitation. Remonter plus haut ferait
  // ressortir « Plus tard », qui ne referme pas le contexte.
  if (isGathering(tripContext)) {
    const last = [...messages].reverse().find((message) => message.author === "memo" && message.kind === "text");
    return last ? suggestionIdsOf(last.payload) : [];
  }

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
    stepNumbers: stepNumbersOf(options.messages),
    viewerIsUnlimited: options.dailyCredit.isUnlimited,
  };

  const messages = options.messages
    .map((message) => serializeChatMessage(message, messageOptions))
    .filter((message) => message !== null);

  const tripContext = parseTripContext(memo.tripContext);
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
    suggestions: serializeChatSuggestions(currentSuggestionIds(options.messages, options.turn, tripContext)),
    tripContext: serializeTripContext(tripContext),
    turn: options.turn,
    canClear: memo.ownerAccountId === viewer.id,
    // Ce que la barre d'enregistrement compte pendant qu'on parle : le reste,
    // les seuils et le barème, sans appel de plus.
    dailyCredit: serializeDailyCredit(options.dailyCredit),
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
  dailyCredit: DailyCredit;
}) {
  const memberCount = 1 + options.memo.members.filter((member) => member.status === "active").length;
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: options.viewer.id,
    showsAuthors: memberCount > 1,
    publicBaseUrl: options.publicBaseUrl,
    stepNumbers: stepNumbersOf(options.allMessages),
    viewerIsUnlimited: options.dailyCredit.isUnlimited,
  };
  const pageCount =
    options.memo.pageCount > 0 ? options.memo.pageCount : options.memoryCount * 2;
  const tripContext = parseTripContext(options.memo.tripContext);

  return {
    messages: options.changed
      .map((message) => serializeChatMessage(message, messageOptions))
      .filter((message) => message !== null),
    suggestions: serializeChatSuggestions(
      currentSuggestionIds(options.allMessages, options.turn, tripContext),
    ),
    // Toujours rendu, pas seulement quand il change : il est petit, et la
    // pastille se remplit sous les yeux à chaque réponse.
    tripContext: serializeTripContext(tripContext),
    preview:
      options.memoryCount > 0
        ? { memoryCount: options.memoryCount, pageCount, isOpenable: options.hasReadyRender }
        : null,
    turn: options.turn,
    // Rendu à chaque sondage : un co-voyageur raconte peut-être en même temps,
    // et c'est le même pot.
    dailyCredit: serializeDailyCredit(options.dailyCredit),
    now: options.now.toISOString(),
  };
}

/**
 * Ce qu'un `POST` rend : les bulles qu'il vient d'écrire — la bulle « reviens
 * demain » comprise quand ce tour a vidé le pot —, l'état du tour, et le
 * crédit du jour **après** ce tour.
 */
export function serializeChatReceipt(options: {
  written: ChatMessageRow[];
  viewerAccountId: string;
  showsAuthors: boolean;
  publicBaseUrl: string;
  /** Les fiches du fil entier (`id`, `kind`, `seq`), pour numéroter celles du reçu. */
  cards: Pick<ChatMessageRow, "id" | "kind" | "seq">[];
  turn: ChatTurnStatus;
  now: Date;
  dailyCredit: DailyCredit;
}) {
  const messageOptions: SerializeMessageOptions = {
    viewerAccountId: options.viewerAccountId,
    showsAuthors: options.showsAuthors,
    publicBaseUrl: options.publicBaseUrl,
    stepNumbers: stepNumbersOf(options.cards),
    viewerIsUnlimited: options.dailyCredit.isUnlimited,
  };
  return {
    messages: options.written
      .map((message) => serializeChatMessage(message, messageOptions))
      .filter((message) => message !== null),
    turn: options.turn,
    dailyCredit: serializeDailyCredit(options.dailyCredit),
    now: options.now.toISOString(),
  };
}
