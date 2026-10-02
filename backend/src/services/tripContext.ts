/**
 * Le contexte du voyage — `docs/conversation.md` § 2 bis.
 *
 * Avant la première étape, MEMO demande au voyageur de poser le décor : d'où
 * il part, à combien, avec qui, quand, et quel genre de voyage c'est. C'est ce
 * qui permet à l'écrivain d'écrire « Clara » et non « une amie » à la page 2,
 * et à MEMO de ne pas demander « qui est Léo ? » à la dixième étape.
 *
 * **Le code tient la liste, le modèle écoute.** Ce qui est obligatoire, dans
 * quel ordre on le demande et avec quelle phrase, tout est ici : le modèle ne
 * fait qu'extraire ce que le voyageur a dit (`AnthropicResponder.gatherContext`),
 * et quand il se tait, les règles de ce fichier prennent le relais — la
 * réponse à une question précise va au champ que la question visait.
 *
 * Forme au champ près de `MemoBookCore/TripContext.swift`.
 */

import { escapeHtml } from "../lib/html.js";
import { EDITORIAL_LIMITS } from "./payloadValidator.js";

// ---------------------------------------------------------------------------
// La forme
// ---------------------------------------------------------------------------

export type TripContextStatus = "gathering" | "complete" | "skipped";

export type NarrationMoment = "before" | "during" | "after";

export interface TripCompanion {
  /** Le prénom, tel que le voyageur le dit — jamais complété, jamais corrigé. */
  name: string;
  /** « ma femme », « un ami d'enfance » — ce qui dit à l'écrivain qui il est. */
  relation: string | null;
}

/** Les cinq lignes sans lesquelles le contexte n'est pas posé. */
export const REQUIRED_FIELDS = [
  "departureCountry",
  "travellerCount",
  "companions",
  "dates",
  "tripType",
] as const;

export type RequiredField = (typeof REQUIRED_FIELDS)[number];

export interface TripContext {
  status: TripContextStatus;
  /** Le pays d'où l'on part — « France ». Pas la ville : c'est le pays qui dit le dépaysement. */
  departureCountry: string | null;
  /** Combien de voyageurs, **narrateur compris**. 1 = en solo. */
  travellerCount: number | null;
  /** Les compagnons, narrateur exclu. Vide en solo. */
  companions: TripCompanion[];
  /** Les dates telles que dites — « du 12 au 26 septembre ». Du texte : on ne convertit pas. */
  dates: string | null;
  /** « road trip en van », « trek », « city trip ». */
  tripType: string | null;

  // Facultatif — ce qui aide à comprendre sans empêcher de commencer.

  /** Les lieux prévus, dans l'ordre : « Kuala Lumpur, Penang, Langkawi ». */
  itinerary: string | null;
  /** « lune de miel », « les 30 ans de Clara ». */
  occasion: string | null;
  /** Le voyageur raconte avant de partir, pendant, ou après être rentré. */
  narrationMoment: NarrationMoment | null;
  /** Ce qu'il a dit d'autre et qui éclaire le récit, en une ou deux phrases. */
  notes: string | null;

  /** La ligne que MEMO vient de demander : la réponse suivante y va d'abord. */
  awaiting: RequiredField | null;
}

export const EMPTY_TRIP_CONTEXT: TripContext = {
  status: "gathering",
  departureCountry: null,
  travellerCount: null,
  companions: [],
  dates: null,
  tripType: null,
  itinerary: null,
  occasion: null,
  narrationMoment: null,
  notes: null,
  awaiting: null,
};

/** Au-delà, ce n'est plus un voyage entre proches, c'est un groupe : on ne demande pas vingt prénoms. */
export const MAX_NAMED_COMPANIONS = 12;

const TEXT_LIMIT = 160;
const NOTES_LIMIT = 400;

// ---------------------------------------------------------------------------
// Relire ce qui est en base
// ---------------------------------------------------------------------------

function cleanText(value: unknown, limit = TEXT_LIMIT): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ");
  if (trimmed.length === 0) return null;
  return trimmed.length > limit ? `${trimmed.slice(0, limit - 1).trimEnd()}…` : trimmed;
}

function cleanCount(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value)) return null;
  return value >= 1 && value <= 99 ? value : null;
}

function cleanCompanions(value: unknown): TripCompanion[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const companions: TripCompanion[] = [];
  for (const candidate of value) {
    if (!candidate || typeof candidate !== "object") continue;
    const name = cleanText((candidate as { name?: unknown }).name, 40);
    if (!name) continue;
    const key = name.toLocaleLowerCase("fr");
    if (seen.has(key)) continue;
    seen.add(key);
    companions.push({ name, relation: cleanText((candidate as { relation?: unknown }).relation, 60) });
    if (companions.length === MAX_NAMED_COMPANIONS) break;
  }
  return companions;
}

function isRequiredField(value: unknown): value is RequiredField {
  return typeof value === "string" && (REQUIRED_FIELDS as readonly string[]).includes(value);
}

/**
 * `null` quand le voyageur n'a jamais commencé à raconter son contexte — la
 * différence compte : c'est elle qui propose la puce d'ouverture.
 */
export function parseTripContext(value: unknown): TripContext | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  const status: TripContextStatus =
    raw.status === "complete" || raw.status === "skipped" ? raw.status : "gathering";
  const moment = raw.narrationMoment;
  return {
    status,
    departureCountry: cleanText(raw.departureCountry, 60),
    travellerCount: cleanCount(raw.travellerCount),
    companions: cleanCompanions(raw.companions),
    dates: cleanText(raw.dates, 80),
    tripType: cleanText(raw.tripType, 80),
    itinerary: cleanText(raw.itinerary),
    occasion: cleanText(raw.occasion, 80),
    narrationMoment: moment === "before" || moment === "during" || moment === "after" ? moment : null,
    notes: cleanText(raw.notes, NOTES_LIMIT),
    awaiting: isRequiredField(raw.awaiting) ? raw.awaiting : null,
  };
}

/** Le voyageur est en train de raconter son contexte : chaque tour y va. */
export function isGathering(context: TripContext | null): boolean {
  return context?.status === "gathering";
}

// ---------------------------------------------------------------------------
// Ce qui manque
// ---------------------------------------------------------------------------

/**
 * Les lignes encore vides, dans l'ordre où MEMO les demande. Les compagnons ne
 * sont complets que quand il y a **un prénom par compagnon** : « on est
 * quatre » avec deux prénoms, c'est encore deux questions.
 */
export function missingFields(context: TripContext): RequiredField[] {
  const missing: RequiredField[] = [];
  if (!context.departureCountry) missing.push("departureCountry");
  if (context.travellerCount === null) missing.push("travellerCount");
  if (companionsMissing(context)) missing.push("companions");
  if (!context.dates) missing.push("dates");
  if (!context.tripType) missing.push("tripType");
  return missing;
}

function companionsMissing(context: TripContext): boolean {
  if (context.travellerCount === null) return context.companions.length === 0;
  const expected = Math.min(context.travellerCount - 1, MAX_NAMED_COMPANIONS);
  return context.companions.length < expected;
}

export function isComplete(context: TripContext): boolean {
  return missingFields(context).length === 0;
}

// ---------------------------------------------------------------------------
// Ce que MEMO dit
// ---------------------------------------------------------------------------

/** La réponse à la puce : l'invitation, qui dit tout ce qu'on attend, sans poser deux questions. */
export const CONTEXT_INVITATION =
  "Avec plaisir ! Raconte-moi ton voyage comme à un ami : d’où tu pars, à combien vous " +
  "êtes et leurs prénoms, les dates, et quel genre de voyage c’est. À l’oral ou au " +
  "clavier, comme tu préfères.";

/** Le contexte est posé. */
export const CONTEXT_COMPLETE =
  "J’ai tout ce qu’il me faut pour que ton carnet reste cohérent du début à la fin. " +
  "Raconte-moi ta première journée quand tu veux.";

/** « Je compléterai plus tard » : on n'insiste pas, jamais. */
export const CONTEXT_SKIPPED =
  "Pas de souci, on commence comme ça. Tu pourras compléter en me le disant au fil du récit.";

/** L'accusé du repli, quand le modèle ne reformule pas. */
export const CONTEXT_NOTED = "C’est noté.";

/**
 * **La** question, une par tour, sur la première ligne qui manque. Écrite par
 * le code et non par le modèle : c'est elle qui garantit qu'on ne pose jamais
 * deux questions, et qu'on ne redemande pas ce qui est déjà su.
 */
export function questionFor(field: RequiredField, context: TripContext): string {
  switch (field) {
    case "departureCountry":
      return "De quel pays pars-tu ?";
    case "travellerCount":
      return "Vous êtes combien sur ce voyage, toi compris ?";
    case "companions": {
      const named = context.companions.length;
      const expected = context.travellerCount !== null ? context.travellerCount - 1 : null;
      if (expected === 1) return "Comment s’appelle ton compagnon de route ?";
      if (named > 0 && expected !== null) {
        const left = expected - named;
        return left === 1
          ? "Il me manque un prénom : qui est le dernier compagnon de route ?"
          : `Il me manque ${left} prénoms : qui sont les autres compagnons de route ?`;
      }
      return "Tu me donnes le prénom de chacun de tes compagnons de route ?";
    }
    case "dates":
      return "Le voyage se déroule à quelles dates ?";
    case "tripType":
      return "Et c’est quel genre de voyage : road trip, city trip, randonnée, farniente ?";
  }
}

// ---------------------------------------------------------------------------
// Fondre ce qui vient d'être dit
// ---------------------------------------------------------------------------

/** Ce qu'un tour a appris. Un champ absent ou `null` ne remplace rien. */
export interface TripContextUpdate {
  departureCountry?: string | null;
  travellerCount?: number | null;
  companions?: TripCompanion[] | null;
  dates?: string | null;
  tripType?: string | null;
  itinerary?: string | null;
  occasion?: string | null;
  narrationMoment?: NarrationMoment | null;
  notes?: string | null;
}

/**
 * Pose ce qu'un tour a appris sur ce qu'on savait. On **complète**, on ne
 * vide jamais : un « on est trois » dit après les prénoms ne les efface pas.
 * Les compagnons s'ajoutent — un prénom déjà connu reçoit la relation qui lui
 * manquait. Les notes se cumulent.
 */
export function mergeTripContext(context: TripContext, update: TripContextUpdate): TripContext {
  const merged: TripContext = { ...context, companions: [...context.companions] };

  const departure = cleanText(update.departureCountry, 60);
  if (departure) merged.departureCountry = departure;
  const count = cleanCount(update.travellerCount);
  if (count !== null) merged.travellerCount = count;
  const dates = cleanText(update.dates, 80);
  if (dates) merged.dates = dates;
  const tripType = cleanText(update.tripType, 80);
  if (tripType) merged.tripType = tripType;
  const itinerary = cleanText(update.itinerary);
  if (itinerary) merged.itinerary = itinerary;
  const occasion = cleanText(update.occasion, 80);
  if (occasion) merged.occasion = occasion;
  if (update.narrationMoment) merged.narrationMoment = update.narrationMoment;

  const notes = cleanText(update.notes, NOTES_LIMIT);
  if (notes && !(merged.notes ?? "").includes(notes)) {
    merged.notes = cleanText([merged.notes, notes].filter(Boolean).join(" "), NOTES_LIMIT);
  }

  for (const companion of cleanCompanions(update.companions ?? [])) {
    const known = merged.companions.find(
      (candidate) => candidate.name.toLocaleLowerCase("fr") === companion.name.toLocaleLowerCase("fr"),
    );
    if (known) {
      known.relation ??= companion.relation;
    } else if (merged.companions.length < MAX_NAMED_COMPANIONS) {
      merged.companions.push(companion);
    }
  }

  // Des prénoms sans compte : le compte s'en déduit. L'inverse — plus de
  // prénoms que de voyageurs — dit que le compte était faux.
  if (merged.companions.length > 0) {
    const atLeast = merged.companions.length + 1;
    if (merged.travellerCount === null || merged.travellerCount < atLeast) {
      merged.travellerCount = atLeast;
    }
  }

  return merged;
}

/** Le contexte après un tour : ce qui manque encore décide de la suite. */
export function advance(context: TripContext): TripContext {
  const missing = missingFields(context);
  return missing.length === 0
    ? { ...context, status: "complete", awaiting: null }
    : { ...context, status: "gathering", awaiting: missing[0]! };
}

// ---------------------------------------------------------------------------
// Le repli, sans modèle
// ---------------------------------------------------------------------------

const NUMBER_WORDS: Record<string, number> = {
  un: 1, une: 1, deux: 2, trois: 3, quatre: 4, cinq: 5, six: 6, sept: 7, huit: 8, neuf: 9,
  dix: 10, onze: 11, douze: 12,
};

/** « seul », « à deux », « on est 4 », « quatre ». */
export function travellerCountIn(text: string): number | null {
  const lower = text.toLocaleLowerCase("fr");
  if (/\b(seule?|solo|tout seul|toute seule)\b/.test(lower)) return 1;
  if (/\ben couple\b|\bà deux\b|\bavec (ma|mon) (femme|mari|copine|copain|compagne|compagnon|chérie?)\b/.test(lower)) {
    return 2;
  }
  const digits = lower.match(/\b(\d{1,2})\b/);
  if (digits) {
    const value = Number.parseInt(digits[1]!, 10);
    if (value >= 1 && value <= 99) return value;
  }
  for (const [word, value] of Object.entries(NUMBER_WORDS)) {
    if (new RegExp(`\\b${word}\\b`).test(lower)) return value;
  }
  return null;
}

/**
 * Les prénoms d'une réponse à « qui sont tes compagnons ? » : les mots qui
 * commencent par une majuscule, séparés par des virgules ou « et ». Le
 * narrateur n'y est pas s'il se nomme — on connaît son prénom.
 */
export function companionNamesIn(text: string, travellerFirstName: string | null): TripCompanion[] {
  const self = travellerFirstName?.toLocaleLowerCase("fr") ?? null;
  const stop = new Set(["Avec", "Et", "Moi", "On", "Nous", "Il", "Elle", "Ils", "Elles", "Mon", "Ma", "Mes", "Je", "C'est", "Ce"]);
  const names = text
    .split(/,|;|\bet\b|&|\n|\+/)
    .map((part) => part.trim())
    .map((part) => part.match(/\p{Lu}[\p{L}'’-]+/u)?.[0] ?? null)
    .filter((name): name is string => name !== null && !stop.has(name))
    .filter((name) => name.toLocaleLowerCase("fr") !== self);
  return names.map((name) => ({ name, relation: null }));
}

/**
 * Ce que le moteur de règles tire d'un tour : la réponse va au champ que MEMO
 * venait de demander. C'est modeste, et c'est voulu — le repli ne doit rien
 * inventer, il range.
 */
export function updateByRules(
  context: TripContext,
  text: string,
  travellerFirstName: string | null,
): TripContextUpdate {
  const answer = text.trim();
  if (answer.length === 0) return {};
  const update: TripContextUpdate = {};

  const count = travellerCountIn(answer);
  if (count === 1) {
    update.travellerCount = 1;
  }

  switch (context.awaiting) {
    case "departureCountry":
      update.departureCountry = answer
        .replace(/^(je pars|on part|nous partons|depuis|de la|du|de l’|de l'|d’|d'|de)\s+/i, "")
        .replace(/[.!]+$/, "");
      break;
    case "travellerCount":
      if (count !== null) update.travellerCount = count;
      break;
    case "companions":
      update.companions = companionNamesIn(answer, travellerFirstName);
      break;
    case "dates":
      update.dates = answer.replace(/[.!]+$/, "");
      break;
    case "tripType":
      update.tripType = answer.replace(/[.!]+$/, "");
      break;
    case null:
      // La première description, sans question posée : le repli ne sait pas
      // la découper. Il la garde pour l'écrivain, et MEMO demandera ligne à
      // ligne ce qui manque.
      update.notes = answer;
      if (count !== null) update.travellerCount = count;
      break;
  }
  return update;
}

/**
 * Le fichier d'un vocal du **contexte du voyage** : il ne devient pas un
 * souvenir, il n'a donc pas d'`Entry` où pendre — il est gardé sur le message.
 */
export interface ContextVoice {
  storageKey: string;
  mimeType: string;
  durationSeconds: number | null;
}

export function contextVoiceOf(payload: unknown): ContextVoice | null {
  if (!payload || typeof payload !== "object") return null;
  const voice = (payload as { contextVoice?: unknown }).contextVoice;
  if (!voice || typeof voice !== "object") return null;
  const { storageKey, mimeType, durationSeconds } = voice as Record<string, unknown>;
  if (typeof storageKey !== "string" || typeof mimeType !== "string") return null;
  return {
    storageKey,
    mimeType,
    durationSeconds: typeof durationSeconds === "number" ? durationSeconds : null,
  };
}

// ---------------------------------------------------------------------------
// Pour les autres lecteurs : MEMO, l'écrivain, l'app
// ---------------------------------------------------------------------------

const MOMENT_LABELS: Record<NarrationMoment, string> = {
  before: "avant de partir",
  during: "pendant le voyage",
  after: "au retour",
};

/**
 * Le contexte en quelques lignes de Markdown, pour les prompts de MEMO et de
 * l'écrivain. Vide quand il n'y a rien à dire.
 */
export function describeTripContext(context: TripContext | null, travellerFirstName?: string | null): string[] {
  if (!context) return [];
  const lines: string[] = [];
  if (context.departureCountry) lines.push(`Pays de départ : ${context.departureCountry}`);
  if (context.travellerCount !== null) {
    lines.push(
      context.travellerCount === 1
        ? `Voyageurs : ${travellerFirstName ?? "le narrateur"}, en solo`
        : `Voyageurs : ${context.travellerCount}, narrateur compris`,
    );
  }
  if (context.companions.length > 0) {
    lines.push(
      `Compagnons : ${context.companions
        .map((companion) => (companion.relation ? `${companion.name} (${companion.relation})` : companion.name))
        .join(", ")}`,
    );
  }
  if (context.dates) lines.push(`Dates : ${context.dates}`);
  if (context.tripType) lines.push(`Genre de voyage : ${context.tripType}`);
  if (context.itinerary) lines.push(`Itinéraire prévu : ${context.itinerary}`);
  if (context.occasion) lines.push(`Occasion : ${context.occasion}`);
  if (context.narrationMoment) lines.push(`Le voyageur raconte ${MOMENT_LABELS[context.narrationMoment]}`);
  if (context.notes) lines.push(`Ce qu'il a ajouté : ${context.notes}`);
  return lines;
}

// ---------------------------------------------------------------------------
// L'intro du carnet, sans appel modèle
// ---------------------------------------------------------------------------

function capitalize(text: string): string {
  return text.length === 0 ? text : text[0]!.toLocaleUpperCase("fr") + text.slice(1);
}

/**
 * Le titre de la page d'intro, quand c'est le structureur déterministe qui la
 * compose (mode `fake`, tests, ou filet de sécurité du structureur par
 * modèle). Jamais vide : un contexte incomplet garde un titre générique
 * plutôt que d'inventer.
 */
export function introTitleFor(context: TripContext | null): string {
  if (context?.tripType) return capitalize(context.tripType);
  if (context?.occasion) return capitalize(context.occasion);
  return "Avant de commencer";
}

function travellersSentence(context: TripContext): string | null {
  const from = context.departureCountry ? ` depuis ${context.departureCountry}` : "";
  if (context.travellerCount === 1) return `Départ en solo${from}.`;
  if (context.travellerCount === null) return context.departureCountry ? `Départ${from}.` : null;

  const names = context.companions.map((companion) => companion.name);
  const withNames = names.length > 0 ? `, avec ${names.join(", ")}` : "";
  return `Départ${from} à ${context.travellerCount}${withNames}.`;
}

/**
 * L'intro du carnet, assemblée directement depuis le contexte — sans appel
 * modèle. C'est le repli du structureur déterministe (`HeuristicStructurer`)
 * et le filet de sécurité du structureur par modèle en cas d'échec. `""`
 * quand il n'y a rien à dire, pour que l'appelant omette la clé plutôt que de
 * poser un `<p>` vide.
 */
export function introTextFor(context: TripContext | null): string {
  if (!context) return "";

  const sentences: string[] = [];
  const travellers = travellersSentence(context);
  if (travellers) sentences.push(travellers);
  if (context.dates) sentences.push(`Le voyage se déroule ${context.dates}.`);
  if (context.tripType) sentences.push(`Au programme : ${context.tripType}.`);
  if (context.occasion) sentences.push(`L'occasion : ${context.occasion}.`);

  if (sentences.length === 0) return "";

  const text = sentences.slice(0, 4).join(" ");
  const limit = EDITORIAL_LIMITS.introTextCharsPerParagraph;
  const trimmed = text.length > limit ? `${text.slice(0, limit - 1).trimEnd()}…` : text;
  return `<p>${escapeHtml(trimmed)}</p>`;
}

/**
 * Ce que l'app affiche : la pastille « Contexte du voyage 3/5 » et sa fiche.
 * Les libellés sont écrits ici pour qu'une ligne ajoutée n'attende pas une
 * version de l'app.
 */
export function serializeTripContext(context: TripContext | null) {
  if (!context) return null;
  const missing = new Set(missingFields(context));
  const companionsValue =
    context.travellerCount === 1
      ? "En solo"
      : context.companions.length > 0
        ? context.companions
            .map((companion) => (companion.relation ? `${companion.name} (${companion.relation})` : companion.name))
            .join(", ")
        : null;

  const required = [
    { key: "departureCountry", label: "Pays de départ", value: context.departureCountry },
    {
      key: "travellerCount",
      label: "Voyageurs",
      value:
        context.travellerCount === null
          ? null
          : context.travellerCount === 1
            ? "1, toi"
            : `${context.travellerCount}, toi compris`,
    },
    { key: "companions", label: "Compagnons de route", value: companionsValue },
    { key: "dates", label: "Dates", value: context.dates },
    { key: "tripType", label: "Genre de voyage", value: context.tripType },
  ].map((item) => ({ ...item, isRequired: true, isFilled: !missing.has(item.key as RequiredField) }));

  const optional = [
    { key: "itinerary", label: "Itinéraire", value: context.itinerary },
    { key: "occasion", label: "Occasion", value: context.occasion },
    {
      key: "narrationMoment",
      label: "Tu racontes",
      value: context.narrationMoment ? MOMENT_LABELS[context.narrationMoment] : null,
    },
  ]
    .filter((item) => item.value !== null)
    .map((item) => ({ ...item, isRequired: false, isFilled: true }));

  return {
    status: context.status,
    filledCount: required.filter((item) => item.isFilled).length,
    requiredCount: required.length,
    items: [...required, ...optional],
  };
}
