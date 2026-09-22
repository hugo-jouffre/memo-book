import type { ChatDisposition, ChatMessageKind } from "@prisma/client";
import type { Env } from "../env.js";
import type { CoherenceSheet, RedactedNeighbour } from "./redaction.js";
import Anthropic from "@anthropic-ai/sdk";
import { AnthropicResponder } from "./conversationAnthropic.js";
import { HeuristicResponder } from "./conversationHeuristics.js";
import {
  OPENING_TEXT,
  SCRIPTED_ANSWERS,
  SILENT_COMMANDS,
  SUGGESTION_SETS,
  fallbackPrompt,
  isSilentCommand,
  isSuggestionId,
  type SuggestionId,
} from "./conversationCopy.js";

/**
 * MEMO, côté serveur — `docs/conversation.md`.
 *
 * Le fil, les routes et le job ne dépendent que de ``MemoResponder``, jamais
 * d'une implémentation : c'est ce qui permet de jouer le pipeline en test avec
 * ``FakeResponder``, de répondre sans modèle avec ``HeuristicResponder`` quand
 * le modèle se tait, et de brancher Claude sans toucher au reste. Même motif
 * que `Transcriber` / `Redactor`.
 */

// ---------------------------------------------------------------------------
// Ce que MEMO retient d'un tour à l'autre
// ---------------------------------------------------------------------------

/**
 * L'état de la conversation d'un carnet, hors messages — `memos.conversationState`.
 *
 * `roseEpineGraineAskedFor` : les journées (`AAAA-MM-JJ`) pour lesquelles la
 * rose, l'épine et la graine ont déjà été demandées. Une fois par journée
 * racontée, jamais deux.
 */
export interface ConversationState {
  roseEpineGraineAskedFor: string[];
}

export const EMPTY_CONVERSATION_STATE: ConversationState = { roseEpineGraineAskedFor: [] };

/** Relecture défensive, comme `parseCoherenceSheet` : un JSON corrompu ne bloque pas un tour. */
export function parseConversationState(value: unknown): ConversationState {
  if (!value || typeof value !== "object") return EMPTY_CONVERSATION_STATE;
  const candidate = value as Partial<ConversationState>;
  return {
    roseEpineGraineAskedFor: Array.isArray(candidate.roseEpineGraineAskedFor)
      ? candidate.roseEpineGraineAskedFor.filter((day): day is string => typeof day === "string")
      : [],
  };
}

// ---------------------------------------------------------------------------
// Ce que le répondeur reçoit, et ce qu'il rend
// ---------------------------------------------------------------------------

/** Un tour du fil, tel que le répondeur le relit. Le texte est borné à ``HISTORY_TEXT_LIMIT``. */
export interface ConversationHistoryTurn {
  author: "memo" | "traveller";
  /** Le prénom de qui a parlé — `null` pour MEMO, ou quand on ne le sait pas. */
  authorName: string | null;
  kind: ChatMessageKind;
  /** Le texte d'une bulle, ou la transcription d'un vocal. `null` pour des photos. */
  text: string | null;
  disposition: ChatDisposition | null;
  sentAt: Date;
}

/** Le souvenir en cours : le dernier tour `memory` du fil, tel que la rédaction l'a laissé. */
export interface CurrentEntry {
  id: string;
  /** `editedText ?? redactedText ?? transcript`. */
  text: string | null;
  redactionStatus: "pending" | "processing" | "ready" | "failed";
  validatedAt: Date | null;
  capturedAt: Date;
  placeLabel: string | null;
}

export interface ConversationInput {
  memo: {
    id: string;
    title: string;
    theme: string | null;
    destinationCity: string | null;
    startDate: Date | null;
    endDate: Date | null;
    narrationPace: string | null;
    /** La relance en place — pour ne pas la réécrire à l'identique. */
    prompt: string | null;
    coherenceSheet: CoherenceSheet;
    state: ConversationState;
  };
  traveller: {
    firstName: string | null;
    /** Propriétaire compris. Au-delà de un, MEMO sait qu'il parle à plusieurs. */
    memberCount: number;
  };
  step: {
    id: string;
    number: number;
    placeName: string | null;
    startDate: Date | null;
    endDate: Date | null;
  } | null;
  /** Vingt tours au plus, du plus ancien au plus récent. Le message courant n'y est pas. */
  history: ConversationHistoryTurn[];
  message: {
    id: string;
    kind: "text" | "voice" | "photos";
    /** Le texte tapé, ou la transcription brute du vocal. `null` sans transcription. */
    text: string | null;
    /** La puce (ou la commande silencieuse) qui a produit ce tour, sinon `null`. */
    suggestionId: string | null;
    photoCount: number;
    durationSeconds: number | null;
    /** La transcription a échoué : MEMO doit le dire, pas faire comme si. */
    transcriptFailed: boolean;
    sentAt: Date;
  };
  currentEntry: CurrentEntry | null;
  /** Les trois derniers souvenirs rédigés — ce que reçoit déjà la rédaction. */
  recentEntries: RedactedNeighbour[];
  /** Ce que le code autorise ce tour-ci. Le modèle propose, le code dispose. */
  allows: { roseEpineGraine: boolean };
  now: Date;
}

export interface ConversationBeat {
  text: string;
  /** Le silence avant la bulle — voir ``pauseBeforeReading`` / ``pauseBeforeSaying``. */
  pauseMilliseconds: number;
}

export interface ConversationReply {
  /** Une à trois bulles, dans l'ordre. */
  beats: ConversationBeat[];
  disposition: ChatDisposition;
  /** Des identifiants du catalogue (`conversationCopy.ts`), trois au plus, jamais des libellés. */
  suggestionIds: SuggestionId[];
  /** La relance à écrire sur `memos.prompt`. `null` = ne pas y toucher. */
  prompt: string | null;
  /** MEMO vient de poser la rose, l'épine et la graine — à retenir dans l'état. */
  asksRoseEpineGraine: boolean;
  /** Qui a parlé : `claude-sonnet-5`, `heuristic`, `fake`. Tracé sur la bulle. */
  model: string;
}

export interface MemoResponder {
  /** L'ouverture : une copie fixe, sans modèle. Sur l'interface pour refléter `MemoResponder.swift`. */
  opening(): { text: string; suggestionIds: SuggestionId[] };
  reply(input: ConversationInput): Promise<ConversationReply>;
}

// ---------------------------------------------------------------------------
// Les bornes
// ---------------------------------------------------------------------------

/** Vingt tours : `ChatTurn.historyLimit` côté Swift, et ce que le modèle relit. */
export const HISTORY_LIMIT = 20;
/** Un tour long est tronqué à cette taille dans l'historique — pas dans le fil. */
export const HISTORY_TEXT_LIMIT = 800;
/** Trois bulles au plus par tour, trois phrases au plus par bulle. */
export const MAX_BEATS = 3;
export const REFORMULATION_LIMIT = 160;
export const ASIDE_LIMIT = 120;
export const PROMPT_LIMIT = 90;

/** Le plancher que l'app applique aussi : en dessous, MEMO n'a pas eu le temps de lire. */
export const MIN_PAUSE_MS = 450;

/** La pause avant la première bulle : le temps de **lire** ce qu'on vient de recevoir. */
export function pauseBeforeReading(received: string): number {
  return Math.min(2_600, 900 + received.length * 22);
}

/** La pause avant une bulle que MEMO **écrit** : plus elle est longue, plus elle met de temps. */
export function pauseBeforeSaying(text: string): number {
  return Math.min(1_800, 700 + text.length * 14);
}

/** La pause avant la fiche d'un vocal : proportionnelle à ce qu'il y a à écouter. */
export function pauseBeforeTranscript(durationSeconds: number | null): number {
  return Math.min(4_000, 1_200 + Math.round((durationSeconds ?? 0) * 45));
}

/**
 * Compose les temps d'une réponse à partir de ses phrases : la première attend
 * la lecture du message reçu, les suivantes le temps de les écrire.
 */
export function composeBeats(received: string, texts: readonly string[]): ConversationBeat[] {
  return texts
    .filter((text) => text.trim().length > 0)
    .slice(0, MAX_BEATS)
    .map((text, index) => ({
      text,
      pauseMilliseconds: Math.max(
        MIN_PAUSE_MS,
        index === 0 ? pauseBeforeReading(received) : pauseBeforeSaying(text),
      ),
    }));
}

// ---------------------------------------------------------------------------
// Ce qu'une réponse doit respecter, quel que soit son auteur
// ---------------------------------------------------------------------------

export class InvalidReplyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidReplyError";
  }
}

const QUESTION_MARKS = /[?？]/g;

/**
 * Les garde-fous du contrat, vérifiés **sur la forme** parce que la forme est
 * ce qu'on sait vérifier : une question au plus, trois bulles au plus, des
 * puces du catalogue, pas de relance quand rien ne l'autorise. Une réponse qui
 * les viole n'est pas corrigée — elle est refusée, et le repli parle.
 */
export function validateReply(reply: ConversationReply, input: ConversationInput): ConversationReply {
  if (reply.beats.length === 0) throw new InvalidReplyError("Réponse vide.");
  if (reply.beats.length > MAX_BEATS) throw new InvalidReplyError("Plus de trois bulles.");

  const questions = reply.beats.reduce(
    (count, beat) => count + (beat.text.match(QUESTION_MARKS)?.length ?? 0),
    0,
  );
  if (questions > 1) throw new InvalidReplyError("Deux questions dans un même tour.");

  for (const beat of reply.beats) {
    if (beat.text.trim().length === 0) throw new InvalidReplyError("Bulle vide.");
    if (!Number.isFinite(beat.pauseMilliseconds) || beat.pauseMilliseconds < MIN_PAUSE_MS) {
      throw new InvalidReplyError("Pause trop courte.");
    }
  }

  const suggestionIds = reply.suggestionIds.filter(isSuggestionId).slice(0, 3);
  const prompt =
    typeof reply.prompt === "string" && reply.prompt.trim().length > 0
      ? reply.prompt.trim().slice(0, PROMPT_LIMIT)
      : null;

  return {
    ...reply,
    suggestionIds,
    prompt,
    asksRoseEpineGraine: reply.asksRoseEpineGraine && input.allows.roseEpineGraine,
  };
}

/** L'état du carnet après un tour : la journée de la rose/épine/graine, si elle vient d'être posée. */
export function nextConversationState(
  state: ConversationState,
  reply: ConversationReply,
  dayKey: string,
): ConversationState {
  if (!reply.asksRoseEpineGraine || state.roseEpineGraineAskedFor.includes(dayKey)) return state;
  return { roseEpineGraineAskedFor: [...state.roseEpineGraineAskedFor, dayKey] };
}

/** `AAAA-MM-JJ`, en UTC — la clé de journée que l'état retient. */
export function dayKeyOf(date: Date): string {
  return date.toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------------
// Les commandes : une réponse écrite d'avance, sans modèle
// ---------------------------------------------------------------------------

/**
 * La réponse à une puce ou à une commande silencieuse, quand le catalogue en
 * a une. `null` : la puce n'est pas une commande (« Je te raconte autre
 * chose » relance un récit), et le tour se traite comme un texte.
 */
export function scriptedReply(
  suggestionId: string | null,
  received: string,
): ConversationReply | null {
  if (!suggestionId) return null;

  const scripted = isSilentCommand(suggestionId)
    ? SILENT_COMMANDS[suggestionId]
    : isSuggestionId(suggestionId)
      ? SCRIPTED_ANSWERS[suggestionId]
      : undefined;
  if (!scripted) return null;

  return {
    beats: composeBeats(received, [scripted.text]),
    disposition: "command",
    suggestionIds: [...SUGGESTION_SETS[scripted.suggestions]],
    prompt: null,
    asksRoseEpineGraine: false,
    model: "scripted",
  };
}

// ---------------------------------------------------------------------------
// Le répondeur simulé — tests et `PIPELINE_MODE=fake`
// ---------------------------------------------------------------------------

/**
 * Déterministe, sans réseau, et **lisible** : un test doit pouvoir prédire ce
 * que MEMO va dire. Il classe un texte par une règle simple (court et un
 * souvenir en cours → précision), reformule par la première phrase, pose
 * toujours la même question.
 *
 * `scripted` : des réponses injectées dans l'ordre, pour piloter un test —
 * même motif que `FakeTranscriber`.
 */
export class FakeResponder implements MemoResponder {
  private readonly scripted: Partial<ConversationReply>[];
  /** Combien de fois le modèle a été sollicité — ce qu'un test compte. */
  calls = 0;

  constructor(scripted: Partial<ConversationReply>[] = []) {
    this.scripted = [...scripted];
  }

  opening(): { text: string; suggestionIds: SuggestionId[] } {
    return { text: OPENING_TEXT, suggestionIds: [...SUGGESTION_SETS.opening] };
  }

  async reply(input: ConversationInput): Promise<ConversationReply> {
    this.calls += 1;

    const command = scriptedReply(input.message.suggestionId, input.message.text ?? "");
    if (command) return command;

    const received = input.message.text ?? "";
    const disposition = FakeResponder.disposition(input);
    const placeName = input.step?.placeName ?? input.memo.destinationCity;

    const texts =
      input.message.kind === "photos"
        ? [`${input.message.photoCount} photo(s), je les range avec le souvenir du jour.`, "Qu’est-ce qu’on y voit ?"]
        : input.message.transcriptFailed
          ? ["Je n’ai pas réussi à écouter ce vocal.", "Tu peux me le réécrire ici ?"]
          : [
              `Tu me racontes que « ${firstSentence(received)} ».`,
              placeName ? `Tu me dis où ça se passait, à ${placeName} ?` : "Tu me dis où ça se passait ?",
            ];

    const base: ConversationReply = {
      beats: composeBeats(received, texts),
      disposition,
      suggestionIds:
        input.message.kind === "voice"
          ? [...SUGGESTION_SETS.trio]
          : [...SUGGESTION_SETS.neutral],
      prompt: `Et ensuite, à ${placeName ?? "cette étape"} ?`,
      asksRoseEpineGraine: false,
      model: "fake",
    };

    const override = this.scripted.shift();
    return validateReply({ ...base, ...override }, input);
  }

  /** Vocal et photo = souvenir ; puce = commande ; texte court sur un souvenir en cours = précision. */
  static disposition(input: ConversationInput): ChatDisposition {
    if (input.message.suggestionId) return "command";
    if (input.message.kind !== "text") return "memory";
    const text = input.message.text ?? "";
    if (text.length < 40 && input.currentEntry && !input.currentEntry.validatedAt) return "context";
    return "memory";
  }
}

/** La première phrase, tronquée pour tenir dans une reformulation. */
export function firstSentence(text: string, limit = REFORMULATION_LIMIT - 40): string {
  const trimmed = text.trim().replace(/\s+/g, " ");
  const sentence = trimmed.split(/(?<=[.!?…])\s+/)[0] ?? trimmed;
  const cleaned = sentence.replace(/[.!?…]+$/, "");
  return cleaned.length > limit ? `${cleaned.slice(0, limit - 1).trimEnd()}…` : cleaned;
}

// ---------------------------------------------------------------------------
// Le repli, et la fabrique
// ---------------------------------------------------------------------------

/**
 * Le répondeur qu'on obtient quand rien d'autre ne répond. Exporté pour que le
 * job puisse l'appeler directement après une panne — MEMO n'est jamais muet.
 */
export function fallbackResponder(): MemoResponder {
  return new HeuristicResponder();
}

/**
 * Qui répond, selon ce dont on dispose — trois paliers, jamais un silence :
 *
 * 1. **Claude** (`AnthropicResponder`, Sonnet 5) dès qu'on est en mode réel
 *    avec une clé. C'est MEMO.
 * 2. **Le moteur de règles** (`HeuristicResponder`) en mode réel sans clé, et
 *    en repli de Claude à chaque tour qui tombe — voir `fallbackResponder`.
 * 3. **Le simulé** (`FakeResponder`) sans mode réel : `PIPELINE_MODE=fake`,
 *    la CI, les tests. Aucun appel réseau, aucune facture, des réponses
 *    prévisibles.
 *
 * Le modèle **n'entre jamais en CI** : c'est `env.live` qui l'ouvre, et la CI
 * ne l'active pas. Les tests du contrat se jouent contre un client doublé.
 */
export function createResponder(env: Env): MemoResponder {
  if (!env.live) return new FakeResponder();
  if (env.ANTHROPIC_API_KEY === "") return new HeuristicResponder();
  return new AnthropicResponder(
    new Anthropic({ apiKey: env.ANTHROPIC_API_KEY }),
    env.ANTHROPIC_CONVERSATION_MODEL,
  );
}

export { fallbackPrompt };
