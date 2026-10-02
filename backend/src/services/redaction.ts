import Anthropic from "@anthropic-ai/sdk";
import type { Env } from "../env.js";
import { loadWritingRules } from "../lib/templates.js";
import { EDITORIAL_LIMITS, STEP_SIZES } from "./payloadValidator.js";

/**
 * Passe de rédaction — étape 2 du pipeline, entre la transcription et la mise
 * en page.
 *
 * Elle existe séparément parce que les deux passes n'ont ni le même moment, ni
 * la même matière, ni les mêmes règles :
 *
 * - **Rédiger** se fait souvenir par souvenir, juste après l'enregistrement,
 *   pendant que l'utilisateur est là pour relire et corriger. Le contrat est
 *   `agents/agent-transcription.md`.
 * - **Mettre en page** se fait à la prévisualisation, sur l'ensemble du carnet,
 *   à partir de textes déjà validés. Le contrat est `LAYOUT_KB.md`.
 *
 * Les mélanger reviendrait à réécrire, à chaque aperçu PDF, un texte que
 * l'utilisateur a corrigé à la main.
 */

/** Ce que la rédaction sait déjà du carnet quand elle écrit une étape. */
export interface CoherenceSheet {
  people: { canonicalName: string; notes: string }[];
  places: { canonicalName: string; notes: string }[];
  lexicon: { term: string; notes: string }[];
  narration: { person: string; tense: string };
  /** Chiffres déjà annoncés dans le carnet, pour ne pas se contredire. */
  figures: { label: string; value: string }[];
  /**
   * Le portrait du narrateur — ses mots, son registre, son humour —, affiné
   * d'étape en étape. C'est ce qui fait reconnaître sa voix à la vingtième
   * page, quand les premières sont sorties du contexte. Absent des fiches
   * écrites avant le 02/10/2026 : relu comme une liste vide.
   */
  voice: string[];
}

export const EMPTY_COHERENCE_SHEET: CoherenceSheet = {
  people: [],
  places: [],
  lexicon: [],
  narration: { person: "", tense: "" },
  figures: [],
  voice: [],
};

/** Une étape déjà rédigée et validée, donnée en contexte à la suivante. */
export interface RedactedNeighbour {
  capturedAt: Date;
  placeLabel: string | null;
  title: string | null;
  text: string;
}

/**
 * Une précision donnée dans la conversation à propos de ce souvenir — la
 * réponse à une question de MEMO. `topic` nomme la question quand elle a un
 * sens pour la rédaction : `rose_epine_graine` (`docs/conversation.md` § 3).
 */
export interface RedactionPrecision {
  text: string;
  topic: string | null;
}

export interface RedactionInput {
  memo: {
    title: string;
    subtitle: string | null;
    authors: string | null;
    theme: string | null;
    styleKey: string | null;
    /**
     * Le contexte du voyage en lignes lisibles (`describeTripContext`) : qui
     * voyage avec qui, d'où, quand, et quel genre de voyage. Vide s'il n'a pas
     * été raconté. C'est ce qui fait écrire « Clara » et non « une amie ».
     */
    tripContext?: string[];
    /** Les jours du voyage, tels que l'app les affiche. */
    startDate?: Date | null;
    endDate?: Date | null;
    /** « Naxos », « Cyclades, Grèce » — ce que le carnet sait de la destination. */
    destination?: string | null;
    /** La clé du rythme de récit (`narrationPace.ts`) : `daily`, `by_place`… */
    narrationPace?: string | null;
  };
  /**
   * Qui raconte. Sans lui, l'écrivain prend le voyageur qui parle de lui à la
   * troisième personne — « sieste bien méritée pour Max » — pour un compagnon,
   * et la fiche de cohérence le consacre (Grèce, 01/10/2026).
   */
  narrator?: {
    /** Le prénom de celui qui a enregistré le vocal. */
    firstName: string | null;
    /** Les autres membres du carnet, par leur prénom. */
    companions: string[];
  };
  entry: {
    transcript: string;
    /**
     * Quand le vocal a été **envoyé** — pas forcément le jour qu'il raconte :
     * on raconte le soir, le lendemain, ou de retour chez soi.
     */
    capturedAt: Date;
    placeLabel: string | null;
    /** Dans l'ordre où elles ont été dites. Vide pour un souvenir raconté hors du chat. */
    precisions?: RedactionPrecision[];
    /** L'étape du voyage à laquelle le souvenir est rattaché, s'il l'est. */
    step?: {
      number: number;
      placeName: string | null;
      startDate: Date | null;
      endDate: Date | null;
    } | null;
  };
  coherenceSheet: CoherenceSheet;
  /** Étapes précédentes, de la plus ancienne à la plus récente. */
  previous: RedactedNeighbour[];
  /**
   * Ce que le carnet entier a déjà employé, au-delà des trois dernières
   * étapes : sans eux, « jamais deux fois le même encart » est une règle que
   * l'écrivain n'a aucun moyen de tenir.
   */
  earlier?: { titles: string[]; funFacts: string[] };
}

/**
 * Les moyens de transport que la rédaction sait nommer. Fermée, parce que
 * l'app en écrit le libellé et l'accord — « 2 trains », « scooter » — et
 * qu'une valeur libre ne se compte pas d'un souvenir à l'autre.
 *
 * Plus large que `TripTransport` (ce qu'on déclare entre deux étapes) : un
 * récit parle aussi de métro, de taxi et de scooter, et c'est précisément ce
 * que le profil veut compter.
 */
export const TRANSPORT_KINDS = [
  "plane",
  "train",
  "bus",
  "car",
  "boat",
  "bike",
  "walk",
  "scooter",
  "motorbike",
  "metro",
  "taxi",
] as const;

export type TransportKind = (typeof TRANSPORT_KINDS)[number];

/**
 * Ce que la rédaction **relève** dans un souvenir pour les statistiques du
 * profil. Un relevé par étape, additionné à la lecture par
 * `travelStatistics.ts` ; rien ici n'est un total.
 *
 * Tout est nullable ou vide par défaut, et c'est le contrat : un chiffre que
 * le récit ne donne pas ne s'invente pas. « On a pris le train » compte un
 * train ; « on a passé la semaine en scooter » compte un scooter **sans
 * nombre** (`count: null`) — l'app l'écrit alors sans chiffre, comme la
 * maquette.
 */
export interface EntryInsights {
  /** Pays cités comme visités, en ISO 3166-1 alpha-2 et avec leur nom français. */
  countries: { code: string; name: string }[];
  /** Régions, provinces ou îles traversées — « Toscane », « Latium ». */
  regions: string[];
  /** Villes et villages où le voyageur a été. */
  cities: string[];
  /** Combien de personnes rencontrées — nommées ou comptées dans le récit. */
  peopleMet: number;
  /** Kilomètres parcourus **dans cette étape**, quand le récit permet de les estimer. */
  distanceKilometres: number | null;
  /** Les moyens de transport employés, avec le nombre de trajets quand il est dit. */
  transports: { kind: TransportKind; count: number | null }[];
  /** Où le voyageur se trouve en racontant — la ville, telle qu'on la dirait. */
  currentPlace: string | null;
}

export const EMPTY_INSIGHTS: EntryInsights = {
  countries: [],
  regions: [],
  cities: [],
  peopleMet: 0,
  distanceKilometres: null,
  transports: [],
  currentPlace: null,
};

const TRANSPORT_KIND_SET: ReadonlySet<string> = new Set(TRANSPORT_KINDS);

function cleanStrings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const trimmed = item.trim();
    if (!trimmed || seen.has(trimmed.toLowerCase())) continue;
    seen.add(trimmed.toLowerCase());
    out.push(trimmed);
  }
  return out;
}

function finiteOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null;
}

/**
 * Le relevé, relu de façon défensive — modèle comme base : un champ absent ou
 * d'une forme inattendue devient sa valeur vide, jamais une exception. Un
 * relevé raté ne doit pas faire échouer un souvenir dont le texte est bon,
 * et une colonne écrite par une version plus ancienne du schéma doit se lire
 * encore.
 *
 * Les doublons et les transports inconnus sont écartés ici, une fois, plutôt
 * que dans chaque lecteur.
 */
export function parseInsights(value: unknown): EntryInsights {
  if (!value || typeof value !== "object") return EMPTY_INSIGHTS;
  const candidate = value as Record<string, unknown>;

  const countries: EntryInsights["countries"] = [];
  const seenCodes = new Set<string>();
  if (Array.isArray(candidate["countries"])) {
    for (const item of candidate["countries"]) {
      if (!item || typeof item !== "object") continue;
      const { code, name } = item as Record<string, unknown>;
      if (typeof code !== "string" || typeof name !== "string") continue;
      const upper = code.trim().toUpperCase();
      if (!/^[A-Z]{2}$/.test(upper) || seenCodes.has(upper)) continue;
      seenCodes.add(upper);
      countries.push({ code: upper, name: name.trim() || upper });
    }
  }

  const transports: EntryInsights["transports"] = [];
  const seenKinds = new Set<string>();
  if (Array.isArray(candidate["transports"])) {
    for (const item of candidate["transports"]) {
      if (!item || typeof item !== "object") continue;
      const { kind, count } = item as Record<string, unknown>;
      if (typeof kind !== "string" || !TRANSPORT_KIND_SET.has(kind) || seenKinds.has(kind)) continue;
      seenKinds.add(kind);
      const rides = finiteOrNull(count);
      transports.push({
        kind: kind as TransportKind,
        count: rides === null ? null : Math.round(rides),
      });
    }
  }

  const peopleMet = finiteOrNull(candidate["peopleMet"]);
  const currentPlace =
    typeof candidate["currentPlace"] === "string" && candidate["currentPlace"].trim()
      ? candidate["currentPlace"].trim()
      : null;

  return {
    countries,
    regions: cleanStrings(candidate["regions"]),
    cities: cleanStrings(candidate["cities"]),
    peopleMet: peopleMet === null ? 0 : Math.round(peopleMet),
    distanceKilometres: finiteOrNull(candidate["distanceKilometres"]),
    transports,
    currentPlace,
  };
}

/**
 * Ce que l'écrivain a compris du vocal **avant** d'écrire — le § 1 de
 * `agents/agent-transcription.md`. Demandée en premier dans le schéma, elle
 * oblige le modèle à lire avant de rédiger, et elle dit, au banc, pourquoi un
 * texte a pris la forme qu'il a.
 */
export interface RedactionUnderstanding {
  /** Le cœur de l'étape : ce que le voyageur raconterait en premier. */
  heart: string;
  /** Le ton, et ce qu'il voulait faire ressentir. */
  tone: string;
  /** Les passages qui ne se lisaient pas tels quels, et ce qu'ils voulaient dire. */
  readings: { heard: string; meaning: string }[];
}

export interface RedactionResult {
  understanding: RedactionUnderstanding;
  title: string;
  text: string;
  weatherKey: "sun" | "sun-wind" | "cloud" | "rain" | "snow";
  funFact: string | null;
  funFactTitle: string | null;
  coherenceSheet: CoherenceSheet;
  /** Le relevé pour les statistiques — voir `EntryInsights`. */
  insights: EntryInsights;
  /**
   * Les passages que l'écrivain n'a pas compris, cités tels que transcrits.
   * Il ne les a ni imprimés, ni devinés : MEMO les signale au voyageur en lui
   * proposant le texte (`askValidation`), et sa précision relance la
   * rédaction. Vide le plus souvent.
   */
  doubts: string[];
  /** Modèle qui a produit le texte, tracé sur l'entrée. */
  model: string;
}

/** Au-delà, un doute n'est plus un passage, c'est une phrase : MEMO le cite, il doit tenir dans une bulle. */
export const DOUBT_MAX_CHARS = 40;

/**
 * Les doutes, relus de façon défensive : ce qui n'est pas une chaîne saute,
 * les guillemets que le modèle aurait ajoutés tombent — MEMO met les siens —
 * et un passage trop long se coupe plutôt que d'envahir la bulle.
 */
export function parseDoubts(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const doubts: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const clean = item.trim().replace(/^[«"“\s]+|[»"”\s]+$/g, "").replace(/\s+/g, " ");
    if (!clean || doubts.includes(clean)) continue;
    doubts.push(clean.length > DOUBT_MAX_CHARS ? `${clean.slice(0, DOUBT_MAX_CHARS - 1).trimEnd()}…` : clean);
  }
  return doubts;
}

export interface Redactor {
  redact(input: RedactionInput): Promise<RedactionResult>;
}

const DATE_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

const DAY_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

const HALF_DAY_MS = 12 * 60 * 60 * 1000;

/**
 * Un jour du calendrier, tel que l'app l'affiche. Les dates de voyage et
 * d'étape sont des minuits **locaux** stockés en UTC — le 26 août à Paris
 * arrive en base le 25 à 22 h — : on les ramène au minuit UTC le plus proche
 * avant de les écrire, sans quoi le carnet commencerait la veille.
 */
function calendarDay(date: Date): string {
  return DAY_FORMATTER.format(new Date(date.getTime() + HALF_DAY_MS)).replace(/^1 /, "1er ");
}

function dayRange(start: Date | null | undefined, end: Date | null | undefined): string | null {
  if (start && end) return `du ${calendarDay(start)} au ${calendarDay(end)}`;
  if (start) return `à partir du ${calendarDay(start)}`;
  if (end) return `jusqu'au ${calendarDay(end)}`;
  return null;
}

/** Les rythmes de récit, dits comme l'écrivain doit les entendre. */
const PACE_LABELS: Record<string, string> = {
  daily: "un récit par jour",
  every_two_days: "un récit tous les deux jours",
  every_three_days: "un récit tous les trois jours",
  weekly: "un récit par semaine",
  by_place: "un récit à chaque lieu",
};

/**
 * Le schéma de sortie. Les contraintes de longueur du gabarit
 * (`LAYOUT_KB.md` § Contraintes de longueur) sont rappelées ici *et* dans le
 * prompt : le schéma ne sait pas compter les caractères, mais il empêche au
 * moins les champs manquants et les clés inventées.
 */
const COHERENCE_ENTRY_SCHEMA = {
  type: "object",
  properties: {
    canonicalName: { type: "string", description: "La graphie retenue, à réutiliser telle quelle." },
    notes: { type: "string", description: "Ce qu'il faut savoir : lien, rôle, prononciation." },
  },
  required: ["canonicalName", "notes"],
  additionalProperties: false,
} as const;

const REDACTION_SCHEMA = {
  type: "object",
  properties: {
    understanding: {
      type: "object",
      description:
        "Ta lecture du vocal, établie AVANT d'écrire (§ 1 des règles). C'est elle qui décide de la page.",
      properties: {
        heart: {
          type: "string",
          description: "Le cœur de l'étape, en une phrase : ce que le voyageur raconterait en premier.",
        },
        tone: {
          type: "string",
          description: "Le ton du voyageur et ce qu'il veut faire ressentir : humour, fatigue heureuse, tendresse…",
        },
        readings: {
          type: "array",
          description:
            "Les passages qui ne se lisent pas tels quels — oral elliptique, correction à voix haute, " +
            "blague, mot mal transcrit — et ce qu'ils veulent dire.",
          items: {
            type: "object",
            properties: {
              heard: { type: "string", description: "Le passage, tel que transcrit." },
              meaning: { type: "string", description: "Ce que le voyageur voulait dire." },
            },
            required: ["heard", "meaning"],
            additionalProperties: false,
          },
        },
      },
      required: ["heart", "tone", "readings"],
      additionalProperties: false,
    },
    title: {
      type: "string",
      description:
        "Titre manuscrit de l'étape : trois à six mots, qui disent le cœur de l'étape. " +
        "Même registre que les titres déjà employés dans le carnet, et jamais l'un d'eux.",
    },
    text: {
      type: "string",
      description:
        "Le récit rédigé, à la première personne, écrit à partir de ta lecture. Paragraphes séparés " +
        `par une ligne vide. Taille S, M, L ou XL du barème ; ${STEP_SIZES.S.max} caractères maximum par paragraphe.`,
    },
    weatherKey: {
      type: "string",
      enum: ["sun", "sun-wind", "cloud", "rain", "snow"],
      description:
        "Temps dominant de l'étape. Si le récit n'en dit rien, se fier au lieu et à la saison. " +
        "En cas d'hésitation entre deux valeurs : sun-wind.",
    },
    funFact: {
      anyOf: [{ type: "string" }, { type: "null" }],
      description:
        "Encart de culture générale sur un lieu réellement visité, 140 caractères maximum. " +
        "null si rien de sûr et de pertinent — une étape sur deux au maximum en porte un.",
    },
    funFactTitle: {
      anyOf: [
        { type: "string", enum: ["Fun fact", "Infos", "Culture générale", "Chiffres clés"] },
        { type: "null" },
      ],
      description: "Titre de l'encart. null quand funFact est null.",
    },
    coherenceSheet: {
      type: "object",
      description:
        "La fiche de cohérence mise à jour : l'ancienne, plus ce que cette étape ajoute. " +
        "Ne jamais retirer une entrée existante ni changer une graphie déjà fixée.",
      properties: {
        people: { type: "array", items: COHERENCE_ENTRY_SCHEMA },
        places: { type: "array", items: COHERENCE_ENTRY_SCHEMA },
        lexicon: {
          type: "array",
          items: {
            type: "object",
            properties: {
              term: { type: "string" },
              notes: { type: "string" },
            },
            required: ["term", "notes"],
            additionalProperties: false,
          },
        },
        narration: {
          type: "object",
          properties: {
            person: { type: "string", description: "« je », « on » ou « nous » — le même pour tout le carnet." },
            tense: { type: "string", description: "Le système de temps retenu." },
          },
          required: ["person", "tense"],
          additionalProperties: false,
        },
        figures: {
          type: "array",
          description: "Chiffres déjà annoncés dans le carnet, pour ne pas se contredire.",
          items: {
            type: "object",
            properties: {
              label: { type: "string" },
              value: { type: "string" },
            },
            required: ["label", "value"],
            additionalProperties: false,
          },
        },
        voice: {
          type: "array",
          description:
            "Le portrait du narrateur en trois à six lignes courtes : ses mots signature, son registre, " +
            "son humour, la longueur de ses phrases. Affine-le d'étape en étape. Jamais un mot que tu n'as pas compris.",
          items: { type: "string" },
        },
      },
      required: ["people", "places", "lexicon", "narration", "figures", "voice"],
      additionalProperties: false,
    },
    insights: {
      type: "object",
      description:
        "Ce que ce souvenir apporte aux statistiques du voyage. Un relevé de CETTE étape seulement, " +
        "jamais un total du carnet. Ne rien inventer : ce que le récit ne dit pas reste vide ou null.",
      properties: {
        countries: {
          type: "array",
          description: "Les pays où le voyageur a été pendant cette étape.",
          items: {
            type: "object",
            properties: {
              code: { type: "string", description: "Code ISO 3166-1 alpha-2, en majuscules : IT, FR." },
              name: { type: "string", description: "Le nom du pays en français : Italie, France." },
            },
            required: ["code", "name"],
            additionalProperties: false,
          },
        },
        regions: {
          type: "array",
          description: "Régions, provinces ou îles traversées, en français : Toscane, Latium, Sicile.",
          items: { type: "string" },
        },
        cities: {
          type: "array",
          description: "Villes et villages où le voyageur a été. Pas les quartiers ni les monuments.",
          items: { type: "string" },
        },
        peopleMet: {
          type: "integer",
          description:
            "Combien de personnes le voyageur a rencontrées dans cette étape : nommées, ou comptées " +
            "(« un couple d'Australiens » = 2). 0 si le récit n'en parle pas. Jamais les compagnons de voyage.",
        },
        distanceKilometres: {
          anyOf: [{ type: "number" }, { type: "null" }],
          description:
            "Kilomètres parcourus pendant cette étape, si le récit permet de les estimer (une distance dite, " +
            "un trajet entre deux villes connues). null sinon. Arrondir : au km sous 100, à la dizaine au-delà.",
        },
        transports: {
          type: "array",
          description: "Les moyens de transport employés dans cette étape.",
          items: {
            type: "object",
            properties: {
              kind: { type: "string", enum: [...TRANSPORT_KINDS] },
              count: {
                anyOf: [{ type: "integer" }, { type: "null" }],
                description:
                  "Le nombre de trajets, quand le récit le dit (« deux trains » = 2, « on a pris l'avion » = 1). " +
                  "null quand le moyen est utilisé sans se compter (« la semaine en scooter »).",
              },
            },
            required: ["kind", "count"],
            additionalProperties: false,
          },
        },
        currentPlace: {
          anyOf: [{ type: "string" }, { type: "null" }],
          description:
            "La ville où le voyageur se trouve en racontant — telle qu'on la dirait : « Rome ». " +
            "null si le récit ne permet pas de le dire.",
        },
      },
      required: [
        "countries",
        "regions",
        "cities",
        "peopleMet",
        "distanceKilometres",
        "transports",
        "currentPlace",
      ],
      additionalProperties: false,
    },
    doubts: {
      type: "array",
      description:
        "Les passages de la transcription que tu n'as pas compris avec certitude, cités tels que transcrits " +
        `(${DOUBT_MAX_CHARS} caractères au plus chacun) : tu ne les as ni imprimés, ni devinés. ` +
        "Vide le plus souvent — un mot que le contexte rend certain se corrige sans doute.",
      items: { type: "string" },
    },
  },
  required: [
    "understanding",
    "title",
    "text",
    "weatherKey",
    "funFact",
    "funFactTitle",
    "coherenceSheet",
    "insights",
    "doubts",
  ],
  additionalProperties: false,
} as const;

/**
 * Un encart trop long fait échouer la validation du carnet entier
 * (`payloadValidator.ts`), et le schéma ne sait pas compter les caractères.
 * L'encart est facultatif : trop long, il saute — le couper ferait imprimer
 * une phrase tronquée.
 */
export function withinFunFactLimit(result: Pick<RedactionResult, "funFact" | "funFactTitle">): {
  funFact: string | null;
  funFactTitle: RedactionResult["funFactTitle"];
} {
  const funFact = result.funFact?.trim() || null;
  return funFact && funFact.length <= EDITORIAL_LIMITS.funFactChars
    ? { funFact, funFactTitle: result.funFactTitle ?? "Fun fact" }
    : { funFact: null, funFactTitle: null };
}

/** « jeudi 1er octobre 2026 » — l'ordinal que `Intl` ne met pas. */
function longDate(date: Date): string {
  return DATE_FORMATTER.format(date).replace(/^(\S+) 1 /, "$1 1er ");
}

/** Le barème, en une ligne, tiré de `STEP_SIZES` : la rédaction et la validation comptent la même chose. */
function sizeScale(): string {
  return (Object.entries(STEP_SIZES) as [string, { min: number; max: number; paragraphes: number }][])
    .map(([name, size]) => `${name} ${size.min}–${size.max} (${size.paragraphes} paragraphe${size.paragraphes > 1 ? "s" : ""})`)
    .join(", ");
}

/**
 * Le message de la rédaction : tout ce que l'écrivain doit savoir pour
 * **comprendre** une étape avant de l'écrire — qui raconte, quand, où, ce que
 * le carnet a déjà dit et comment —, puis la transcription.
 *
 * Exporté pour être testé : une ligne de contexte qui disparaît ne fait
 * échouer aucun appel, elle fait seulement écrire plus mal.
 */
export function buildRedactionPrompt(input: RedactionInput): string {
  const { memo, narrator, entry, coherenceSheet, previous, earlier } = input;

  const lines: string[] = ["## Le carnet", `Titre : ${memo.title}`];
  if (memo.subtitle) lines.push(`Sous-titre : ${memo.subtitle}`);
  if (memo.authors) lines.push(`Voyageurs : ${memo.authors}`);
  if (memo.theme) lines.push(`Thème : ${memo.theme}`);
  if (memo.styleKey) lines.push(`Style de carnet : ${memo.styleKey}`);
  if (memo.destination) lines.push(`Destination : ${memo.destination}`);
  const tripDays = dayRange(memo.startDate, memo.endDate);
  if (tripDays) lines.push(`Dates du voyage : ${tripDays}`);
  const pace = memo.narrationPace ? (PACE_LABELS[memo.narrationPace] ?? memo.narrationPace) : null;
  if (pace) lines.push(`Rythme de récit choisi : ${pace}`);

  lines.push("", "## Qui raconte");
  if (narrator?.firstName) {
    lines.push(
      `Le narrateur : ${narrator.firstName}. C'est lui qui a enregistré ce vocal : s'il parle de ` +
        `« ${narrator.firstName} » à la troisième personne, c'est de lui-même (§ 1.3).`,
    );
  } else {
    lines.push("Le narrateur : prénom inconnu.");
  }
  if (narrator && narrator.companions.length > 0) {
    lines.push(`Avec lui sur le carnet : ${narrator.companions.join(", ")}`);
  }

  if (memo.tripContext && memo.tripContext.length > 0) {
    lines.push(
      "",
      "## Le contexte du voyage",
      "_Raconté par le voyageur avant la première étape. Les prénoms s'écrivent comme ici._",
      ...memo.tripContext,
    );
  }

  lines.push(
    "",
    "## Fiche de cohérence",
    previous.length === 0
      ? "Première étape du carnet : la fiche est vide, c'est toi qui l'ouvres. " +
          "Les choix que tu fais ici (personne, temps, appellations) engagent tout le carnet."
      : "Relis-la avant d'écrire, complète-la après. Ne change aucune graphie déjà fixée.",
    "```json",
    JSON.stringify(coherenceSheet, null, 2),
    "```",
  );

  const titles = earlier?.titles.filter(Boolean) ?? [];
  const funFacts = earlier?.funFacts.filter(Boolean) ?? [];
  if (titles.length > 0 || funFacts.length > 0) {
    lines.push("", "## Ce que le carnet a déjà employé");
    if (titles.length > 0) {
      lines.push(`Titres, dans l'ordre : ${titles.map((title) => `« ${title} »`).join(" · ")}`);
    }
    if (funFacts.length > 0) {
      lines.push("Encarts déjà écrits — aucun ne se répète, aucun registre ne revient à la suite :");
      lines.push(...funFacts.map((funFact) => `- ${funFact}`));
    }
  }

  if (previous.length > 0) {
    // Les trois dernières suffisent : au-delà, la fiche de cohérence porte
    // ce qui doit rester stable, et le contexte coûterait plus qu'il
    // n'apporte.
    const recent = previous.slice(-3);
    lines.push(
      "",
      `## Les ${recent.length} étapes précédentes, déjà écrites`,
      "Elles donnent le ton, le rythme et la voix à tenir, et les fils qui restent ouverts.",
      "Ne les résume pas, ne les reprends pas : enchaîne. La dernière phrase de la dernière",
      "étape et la première phrase de la tienne ne doivent pas se recouvrir.",
    );
    for (const neighbour of recent) {
      lines.push(
        "",
        `### ${neighbour.title ?? "(sans titre)"}${neighbour.placeLabel ? ` — ${neighbour.placeLabel}` : ""}`,
        neighbour.text,
      );
    }
  }

  lines.push("", "## L'étape à rédiger");
  if (entry.step) {
    const stepDays = dayRange(entry.step.startDate, entry.step.endDate);
    lines.push(
      `Étape n°${entry.step.number} du voyage` +
        (entry.step.placeName ? ` — ${entry.step.placeName}` : "") +
        (stepDays ? `, ${stepDays}` : ""),
    );
  }
  lines.push(
    entry.placeLabel ? `Lieu : ${entry.placeLabel}` : "Lieu : non précisé par le voyageur",
    `Vocal envoyé le ${longDate(entry.capturedAt)}. Le jour raconté est celui que dit le voyageur : ` +
      "souvent le jour même ou la veille, parfois bien avant — on raconte aussi après coup.",
    "",
    "Transcription brute, faite par une machine qui entend mal les noms propres et l'argot (§ 1.2) :",
    "```",
    entry.transcript,
    "```",
  );

  const precisions = entry.precisions ?? [];
  if (precisions.length > 0) {
    // Les réponses aux questions de MEMO, et aux doutes de l'écrivain. Elles
    // ne sont pas un second récit à côté du premier : elles complètent
    // celui-ci, à leur place.
    lines.push(
      "",
      "## Précisions données par le voyageur dans la conversation",
      "Elles font partie du récit au même titre que la transcription, et lèvent tes doutes",
      "quand elles y répondent (§ 1.6).",
    );
    for (const precision of precisions) {
      lines.push(`- ${precision.topic ? `[${precision.topic}] ` : ""}${precision.text}`);
    }
  }

  lines.push(
    "",
    "## Rappels",
    "- Lis d'abord, écris ensuite : `understanding` se remplit avant `text`, et c'est lui qui décide",
    "  de la page — son cœur, son ton, ce que veut dire chaque passage (§ 1).",
    `- \`text\` : une taille du barème — ${sizeScale()} —, et **${STEP_SIZES.S.max} caractères au plus`,
    "  par paragraphe**, séparés par une ligne vide. Un dépassement fait échouer la génération du carnet.",
    "- Texte nu dans `text` : ni HTML, ni Markdown, ni emoji.",
    "- Tout ce que tu écris dans `text` se retrouve dans la transcription ou les précisions. La",
    "  culture générale va dans `funFact` (140 caractères, ou `null`), jamais dans le récit.",
    "- Un mot que tu n'as pas compris ne s'imprime pas et n'entre pas dans la fiche : il va dans",
    "  `doubts`, que tu laisses vide quand tout est clair.",
    "- `insights` : ce que **cette étape** apporte aux statistiques du profil. Un relevé, pas un",
    "  total : ne reprends rien des étapes précédentes, et n'invente aucun chiffre.",
  );

  return lines.join("\n");
}

/**
 * Rédaction réelle, par Claude.
 *
 * Le prompt système est **le fichier de règles lui-même**, pas une
 * paraphrase : quand l'équipe édite `agents/agent-transcription.md`, le
 * comportement change au redémarrage suivant, sans toucher au code. C'est le
 * même contrat que `templates/` a déjà avec la mise en page.
 */
export class AnthropicRedactor implements Redactor {
  constructor(
    private readonly client: Anthropic,
    private readonly model: string,
  ) {}

  private buildSystemPrompt(): Anthropic.TextBlockParam[] {
    return [
      {
        type: "text",
        text: [
          "Tu es l'écrivain de MemoBook. D'un souvenir raconté à l'oral, tu fais la page de",
          "carnet de voyage que le voyageur aurait écrite lui-même : tu comprends d'abord ce",
          "qu'il a vécu et ce qu'il voulait en dire, puis tu l'écris.",
          "",
          "Les règles ci-dessous font autorité et s'appliquent intégralement, sans exception.",
          "Elles priment sur tes habitudes de rédaction. En cas de conflit entre deux règles,",
          "la hiérarchie des quatre principes tranche.",
          "",
          "Tu réponds uniquement par l'objet JSON demandé.",
          "",
          "---",
          "",
          loadWritingRules(),
        ].join("\n"),
        // Les règles sont identiques d'un souvenir à l'autre : mises en cache,
        // elles ne sont facturées plein tarif qu'au premier appel de la série.
        cache_control: { type: "ephemeral" },
      },
    ];
  }

  async redact(input: RedactionInput): Promise<RedactionResult> {
    const response = await this.client.messages.create({
      model: this.model,
      // Large : la réflexion et la lecture du vocal comptent dans ce plafond,
      // et un texte tronqué au milieu d'une phrase est pire qu'une erreur
      // franche.
      max_tokens: 16_000,
      thinking: { type: "adaptive" },
      output_config: {
        effort: "high",
        format: { type: "json_schema", schema: REDACTION_SCHEMA },
      },
      system: this.buildSystemPrompt(),
      messages: [{ role: "user", content: buildRedactionPrompt(input) }],
    });

    // À vérifier avant de lire `content` : un refus renvoie un 200 avec un
    // tableau vide, et `content[0]` planterait sur un souvenir parfaitement
    // anodin mais mal classé.
    if (response.stop_reason === "refusal") {
      throw new Error(
        "Le modèle a refusé de rédiger ce souvenir. Le texte brut reste disponible : " +
          "corrige-le à la main dans l'app, ou relance la rédaction.",
      );
    }

    if (response.stop_reason === "max_tokens") {
      throw new Error(
        "La rédaction s'est arrêtée avant la fin. Relance-la : si ça se reproduit, " +
          "le souvenir est probablement trop long pour une seule étape.",
      );
    }

    const text = response.content.find((block) => block.type === "text")?.text;
    if (!text) {
      throw new Error("Le modèle n'a produit aucun texte exploitable.");
    }

    const parsed = JSON.parse(text) as Omit<RedactionResult, "model">;
    return { ...parsed, ...withinFunFactLimit(parsed), doubts: parseDoubts(parsed.doubts), model: this.model };
  }
}

/**
 * Rédaction déterministe, sans réseau ni clé — tests, smoke et boucle de
 * travail sur la mise en page.
 *
 * Elle nettoie ce qu'un vrai passage nettoierait (hésitations, tics) sans rien
 * inventer : le texte produit reste reconnaissable, ce qui rend les tests de
 * bout en bout lisibles.
 */
export class FakeRedactor implements Redactor {
  private static readonly ORAL_TICS =
    /\b(euh+|ben|bah|du coup|en fait|genre|voilà quoi|tu vois|quoi)\b[,.]?\s*/gi;

  async redact(input: RedactionInput): Promise<RedactionResult> {
    const cleaned = input.entry.transcript
      .replace(FakeRedactor.ORAL_TICS, "")
      .replace(/\s{2,}/g, " ")
      .trim();

    const body = cleaned.length > 0 ? cleaned : "Souvenir sans récit exploitable.";
    const capitalized = body.charAt(0).toUpperCase() + body.slice(1);

    const firstSentence = capitalized.split(/(?<=[.!?…])\s+/)[0] ?? capitalized;

    // Les précisions de la conversation arrivent **dans** le texte, pour que
    // le test de bout en bout les voie atteindre le carnet.
    const precisions = (input.entry.precisions ?? []).map((precision) => precision.text.trim());
    const withPrecisions = [capitalized, ...precisions].filter(Boolean).join(" ");

    return {
      understanding: { heart: firstSentence, tone: "", readings: [] },
      title: firstSentence.slice(0, 60).replace(/[.!?…]+$/, ""),
      text: withPrecisions.slice(0, 420),
      weatherKey: "sun-wind",
      funFact: null,
      funFactTitle: null,
      // La fiche est propagée telle quelle : le faux rédacteur ne prétend pas
      // tenir une cohérence, mais il ne la détruit pas non plus.
      coherenceSheet: input.coherenceSheet,
      insights: FakeRedactor.insightsFrom(input.entry),
      doubts: [],
      model: "fake-redactor",
    };
  }

  /**
   * Un relevé **sans modèle**, tiré de ce que l'app a déclaré : le lieu du
   * souvenir. « Trastevere, Rome » donne la ville Rome ; les kilomètres, les
   * rencontres et les transports restent vides, parce que rien ne les lit.
   *
   * C'est ce qui fait vivre les statistiques en développement — le profil
   * voit une ville apparaître à chaque souvenir — sans prétendre à ce que
   * seule la vraie rédaction sait relever.
   */
  static insightsFrom(entry: { placeLabel: string | null }): EntryInsights {
    const parts = (entry.placeLabel ?? "")
      .split(",")
      .map((part) => part.trim())
      .filter(Boolean);
    const city = parts.length > 1 ? (parts[parts.length - 1] ?? null) : null;

    return {
      ...EMPTY_INSIGHTS,
      cities: city ? [city] : [],
      currentPlace: city,
    };
  }
}

export function createRedactor(env: Env): Redactor {
  if (!env.live || env.ANTHROPIC_API_KEY === "") return new FakeRedactor();
  return new AnthropicRedactor(
    new Anthropic({ apiKey: env.ANTHROPIC_API_KEY }),
    env.ANTHROPIC_REDACTION_MODEL,
  );
}
