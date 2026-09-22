import type { ChatDisposition } from "@prisma/client";
import {
  AFTER_TRANSCRIPT,
  ANSWERS,
  LONG_MESSAGE,
  MISSING_DATE,
  MISSING_PLACE,
  NEGATIVE_MOOD,
  OPENING_TEXT,
  POSITIVE_MOOD,
  REFUSAL,
  ROSE_EPINE_GRAINE,
  ROTATION,
  SUGGESTION_SETS,
  TOO_SHORT,
  TRANSCRIPT_UNAVAILABLE,
  fallbackPrompt,
  figure,
  foundPlace,
  heard,
  knownPerson,
  newPerson,
  photosReceived,
  type SuggestionId,
  type SuggestionSet,
} from "./conversationCopy.js";
import {
  composeBeats,
  firstSentence,
  scriptedReply,
  validateReply,
  type ConversationInput,
  type ConversationReply,
  type MemoResponder,
} from "./conversation.js";

/**
 * MEMO sans modèle — le portage de `MemoBookCore/ChatAnalysis.swift` et de
 * `LocalMemoResponder.swift`, phrase pour phrase, pour que le repli côté
 * serveur réponde exactement ce que l'app répondait seule.
 *
 * **Des marqueurs, pas un dictionnaire.** On ne cherche pas à comprendre le
 * français, on cherche des indices sûrs — une préposition devant un mot
 * capitalisé, une unité derrière un nombre, un point d'interrogation final.
 * Un indice manquant ne coûte qu'une relance moins précise ; un indice faux
 * fait dire une bêtise, et c'est ça qu'on évite.
 *
 * **Une priorité stricte, pas une addition de scores.** Le premier signal qui
 * se déclenche choisit la famille de réponse. **Aucun état, aucun aléatoire,
 * aucune horloge** : la mémoire du moteur est l'historique du fil — il écarte
 * toute phrase déjà dite et descend d'un cran plutôt que de se répéter.
 */

// ---------------------------------------------------------------------------
// Les signaux
// ---------------------------------------------------------------------------

export type Length = "tooShort" | "brief" | "substantial" | "long";
export type Mood = "positive" | "negative" | "neutral";
export type Subject = "book" | "subscription" | "photos" | "corrections" | "pace";

export interface ChatSignals {
  length: Length;
  sentenceCount: number;
  hasWhen: boolean;
  /** Verbatim, dans l'ordre d'apparition. MEMO les répète, il ne les complète pas. */
  places: string[];
  people: string[];
  isQuestion: boolean;
  subject: Subject | null;
  mood: Mood;
  /** Gagne sur tout : « ne jamais insister ». */
  isRefusal: boolean;
  /** « 12 km », « 35 € » — recopiés, jamais convertis. */
  figures: string[];
}

interface Token {
  /** Tel qu'écrit : c'est lui qui repart dans une réponse. */
  text: string;
  /** Sans accents ni majuscules, apostrophe droite. Pour comparer seulement. */
  folded: string;
  /** Ouvre une phrase : la majuscule y est grammaticale et ne dit rien. */
  opensSentence: boolean;
}

/** Sans accents, en minuscules, apostrophes droites, ligatures dépliées. */
export function fold(text: string): string {
  return text
    .replace(/’/g, "'")
    .replace(/œ/g, "oe")
    .replace(/Œ/g, "OE")
    .replace(/æ/g, "ae")
    .replace(/Æ/g, "AE")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();
}

const TERMINATORS = new Set([".", "!", "?", "…", "\n"]);
const WORD_CHARACTER = /[\p{L}\p{N}]/u;

function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  let current = "";
  let opensSentence = true;

  const flush = () => {
    if (current.length === 0) return;
    tokens.push({ text: current, folded: fold(current), opensSentence });
    current = "";
    opensSentence = false;
  };

  for (const character of text) {
    if (WORD_CHARACTER.test(character)) {
      current += character;
    } else {
      flush();
      if (TERMINATORS.has(character)) opensSentence = true;
    }
  }
  flush();
  return tokens;
}

function isCapitalized(token: Token): boolean {
  const first = token.text.charAt(0);
  return first !== first.toLowerCase() && first === first.toUpperCase();
}

function lengthOf(text: string): Length {
  const count = [...text].length;
  if (count < 25) return "tooShort";
  if (count < 141) return "brief";
  if (count < 401) return "substantial";
  return "long";
}

/** Lit un message. C'est **le** point d'entrée de l'analyse. */
export function readSignals(text: string): ChatSignals {
  const trimmed = text.trim();
  const tokens = tokenize(trimmed);
  const folded = fold(trimmed);

  // Les personnes d'abord : « avec Mila » est un signal bien plus sûr que
  // « de Testaccio ». Un mot déjà retenu comme quelqu'un ne peut plus être un lieu.
  const people = peopleIn(tokens, new Set());
  const places = placesIn(tokens, new Set(people));
  const length = lengthOf(trimmed);

  return {
    length,
    sentenceCount: sentenceCountOf(trimmed),
    hasWhen:
      [...Lexicon.timeMarkers].some((marker) => folded.includes(marker)) ||
      hasClockTime(tokens) ||
      hasCalendarDate(tokens),
    places,
    people,
    isQuestion: isQuestion(trimmed, folded),
    subject: subjectOf(folded),
    mood: moodOf(folded),
    isRefusal: isRefusal(folded, length),
    figures: figuresIn(tokens),
  };
}

function sentenceCountOf(text: string): number {
  const sentences = text.split(/[.!?…]/).filter((part) => part.trim().length > 0);
  return Math.max(1, sentences.length);
}

function pushUnique(list: string[], value: string): void {
  if (!list.includes(value)) list.push(value);
}

/**
 * Un mot capitalisé précédé d'une préposition de lieu, ou un nom de lieu
 * générique derrière un déterminant. « de » ne compte que derrière un lieu
 * générique : « le marché de Testaccio » est un lieu, « l'appartement de
 * Camille » est quelqu'un.
 */
function placesIn(tokens: Token[], people: Set<string>): string[] {
  const found: string[] = [];

  tokens.forEach((token, index) => {
    if (Lexicon.commonPlaces.has(token.folded)) {
      // « le marché » est un endroit, « on a marché » est un verbe.
      if (index > 0 && Lexicon.determiners.has(tokens[index - 1]!.folded)) {
        pushUnique(found, token.text.toLowerCase());
      }
      return;
    }

    if (!isCapitalized(token) || Lexicon.stopWords.has(token.folded) || people.has(token.text)) {
      return;
    }
    if (index === 0) return;

    const previous = tokens[index - 1]!.folded;
    if (Lexicon.placePrepositions.has(previous)) {
      pushUnique(found, token.text);
    } else if (Lexicon.weakPlacePrepositions.has(previous) && followsAGenericPlace(index, tokens)) {
      pushUnique(found, token.text);
    }
  });

  return found;
}

/** Un nom de lieu générique dans les trois mots qui précèdent. */
function followsAGenericPlace(index: number, tokens: Token[]): boolean {
  const start = Math.max(0, index - 4);
  return tokens.slice(start, index).some((token) => Lexicon.commonPlaces.has(token.folded));
}

/**
 * Un mot capitalisé qui **n'ouvre pas** la phrase, précédé d'un possessif ou
 * d'un « avec ». « et » ne compte qu'après une première personne trouvée.
 */
function peopleIn(tokens: Token[], places: Set<string>): string[] {
  const found: string[] = [];

  tokens.forEach((token, index) => {
    if (!isCapitalized(token) || token.opensSentence) return;
    if (Lexicon.stopWords.has(token.folded) || places.has(token.text)) return;
    if (index === 0) return;

    const previous = tokens[index - 1]!.folded;
    const isIntroduced =
      Lexicon.personPrepositions.has(previous) || (previous === "et" && found.length > 0);
    if (isIntroduced) pushUnique(found, token.text);
  });

  return found;
}

/** « 18h », « 18 h 30 ». */
function hasClockTime(tokens: Token[]): boolean {
  return tokens.some((token, index) => {
    if (/^\d/.test(token.folded) && token.folded.includes("h")) return true;
    const hour = Number.parseInt(token.folded, 10);
    if (!Number.isInteger(hour) || String(hour) !== token.folded || hour <= 0 || hour > 23) {
      return false;
    }
    return tokens[index + 1]?.folded === "h";
  });
}

/** « 26 août ». */
function hasCalendarDate(tokens: Token[]): boolean {
  return tokens.some((token, index) => {
    const day = Number.parseInt(token.folded, 10);
    if (!Number.isInteger(day) || String(day) !== token.folded || day < 1 || day > 31) return false;
    const next = tokens[index + 1];
    return next !== undefined && Lexicon.months.has(next.folded);
  });
}

function isQuestion(text: string, folded: string): boolean {
  if (text.endsWith("?")) return true;
  return [...Lexicon.questionOpeners].some((opener) => folded.startsWith(opener));
}

/** L'ordre compte : « corriger mon carnet » parle de correction, pas de carnet. */
function subjectOf(folded: string): Subject | null {
  const has = (words: Set<string>) => [...words].some((word) => folded.includes(word));
  if (has(Lexicon.correctionWords)) return "corrections";
  if (has(Lexicon.subscriptionWords)) return "subscription";
  if (has(Lexicon.paceWords)) return "pace";
  if (has(Lexicon.photoWords)) return "photos";
  if (has(Lexicon.bookWords)) return "book";
  return null;
}

/** Les intensifieurs comptent **double** du côté déjà majoritaire. */
function moodOf(folded: string): Mood {
  const count = (words: Set<string>) => [...words].filter((word) => folded.includes(word)).length;
  const positive = count(Lexicon.positiveWords);
  const negative = count(Lexicon.negativeWords);
  if (positive === negative) return "neutral";

  const intensity = count(Lexicon.intensifiers);
  const positiveScore = positive + (positive > negative ? intensity : 0);
  const negativeScore = negative + (negative > positive ? intensity : 0);
  return positiveScore > negativeScore ? "positive" : "negative";
}

/** Un refus franc suffit ; « demain » seul ne compte que dans un message très court. */
function isRefusal(folded: string, length: Length): boolean {
  if ([...Lexicon.refusals].some((word) => folded.includes(word))) return true;
  if (length !== "tooShort") return false;
  return [...Lexicon.softRefusals].some((word) => folded.includes(word));
}

/** Un nombre collé à son unité (« 12km ») ou séparé (« 12 km »), rendu sur une espace. */
function figuresIn(tokens: Token[]): string[] {
  const found: string[] = [];

  tokens.forEach((token, index) => {
    const split = splitNumberAndUnit(token.folded);
    if (split) {
      pushUnique(found, `${split.number} ${Lexicon.units.get(split.unit) ?? split.unit}`);
      return;
    }

    const numeric = token.folded.replace(",", ".");
    if (!/^\d+(\.\d+)?$/.test(numeric)) return;
    const unit = tokens[index + 1] ? Lexicon.units.get(tokens[index + 1]!.folded) : undefined;
    if (unit) pushUnique(found, `${token.text} ${unit}`);
  });

  return found;
}

function splitNumberAndUnit(folded: string): { number: string; unit: string } | null {
  const match = /^([\d,.]+)(.+)$/.exec(folded);
  if (!match) return null;
  const [, number, unit] = match;
  if (!number || !unit || !Lexicon.units.has(unit)) return null;
  return { number, unit };
}

// ---------------------------------------------------------------------------
// Les listes de mots — repliées, comme `fold` les rend
// ---------------------------------------------------------------------------

const MONTHS = [
  "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout",
  "septembre", "octobre", "novembre", "decembre",
];
const WEEKDAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"];

export const Lexicon = {
  timeMarkers: new Set([
    "hier", "avant-hier", "aujourd'hui", "ce matin", "ce midi", "ce soir", "cette nuit",
    "cet apres-midi", "l'apres-midi", "demain", "la veille", ...WEEKDAYS,
    "la semaine derniere", "le week-end",
  ]),
  months: new Set(MONTHS),
  placePrepositions: new Set([
    "a", "au", "aux", "vers", "depuis", "dans", "jusqu", "sur", "sous", "entre", "pres",
    "cote", "direction",
  ]),
  weakPlacePrepositions: new Set(["de", "du", "des", "d"]),
  determiners: new Set([
    "le", "la", "les", "l", "un", "une", "du", "des", "au", "aux", "ce", "cet", "cette",
    "ces", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos",
    "votre", "vos", "leur", "leurs",
  ]),
  personPrepositions: new Set(["avec", "chez", "mon", "ma", "mes", "notre", "nos", "sans"]),
  commonPlaces: new Set([
    "restaurant", "marche", "plage", "gare", "hotel", "musee", "col", "refuge", "village",
    "port", "ile", "quartier", "terrasse", "rue", "parc", "cafe", "montagne", "lac",
    "riviere", "sentier", "auberge", "aeroport", "cathedrale", "eglise", "chateau",
    "sommet", "vallee",
  ]),
  stopWords: new Set([
    "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "le", "la", "les",
    "un", "une", "des", "du", "de", "ce", "cet", "cette", "ca", "c", "et", "mais", "puis",
    "alors", "enfin", "bref", "donc", "or", "ni", "car", "quand", "comme", "hier", "demain",
    "aujourd", "memobook", "memo", "l", "d", "n", "s", "m", "t", "y", "apres", "avant",
    "aussi", "encore", "tres", "trop", "bien", ...MONTHS, ...WEEKDAYS,
  ]),
  questionOpeners: new Set([
    "est-ce que", "est-ce qu", "comment", "pourquoi", "qu'est-ce", "combien",
    "quand est-ce", "c'est quoi", "qui est-ce",
  ]),
  bookWords: new Set(["carnet", "imprim", "livre", "reliure", "pages", "pdf", "apercu"]),
  subscriptionWords: new Set([
    "abonnement", "prix", "coute", "tarif", "payer", "paiement", "resilier", "euros",
  ]),
  photoWords: new Set(["photo", "pellicule", "image", "cliche"]),
  correctionWords: new Set([
    "corriger", "corrige", "modifier", "modifie", "changer", "change", "retoucher",
    "retouche", "faute", "reecrire", "supprimer",
  ]),
  paceWords: new Set([
    "relance", "relancer", "rythme", "notification", "rappel", "souvent", "frequence",
  ]),
  positiveWords: new Set([
    "magnifique", "sublime", "incroyable", "genial", "adore", "coup de coeur", "dingue",
    "ravi", "heureux", "emu", "inoubliable", "parfait", "le meilleur", "fou rire", "superbe",
    "splendide", "hate", "j'ai aime", "on a aime", "content",
  ]),
  negativeWords: new Set([
    "epuise", "creve", "decu", "galere", "rate", "penible", "perdu", "malade", "annule",
    "en retard", "nul", "difficile", "dur", "peur", "complique", "fatigue", "triste",
    "stresse", "cauchemar",
  ]),
  intensifiers: new Set([
    "vraiment", "tellement", "trop", "hyper", "jamais vu", "le plus", "carrement",
    "franchement",
  ]),
  refusals: new Set([
    "pas envie", "laisse tomber", "j'arrete", "pas maintenant", "non merci", "plus tard",
    "pas ce soir", "une autre fois", "je suis fatigue de", "arrete de",
  ]),
  softRefusals: new Set(["demain", "stop", "plus tard", "non"]),
  units: new Map<string, string>([
    ["e", "€"], ["euro", "€"], ["euros", "€"],
    ["km", "km"], ["kilometre", "km"], ["kilometres", "km"],
    ["m", "m"], ["metre", "m"], ["metres", "m"],
    ["h", "h"], ["heure", "heures"], ["heures", "heures"],
    ["min", "min"], ["minute", "minutes"], ["minutes", "minutes"],
    ["jour", "jour"], ["jours", "jours"],
    ["pas", "pas"],
  ]),
};

// ---------------------------------------------------------------------------
// Le répondeur
// ---------------------------------------------------------------------------

interface Candidate {
  family: string;
  text: string;
  suggestions: SuggestionSet;
}

export class HeuristicResponder implements MemoResponder {
  static readonly MODEL = "heuristic";

  opening(): { text: string; suggestionIds: SuggestionId[] } {
    return { text: OPENING_TEXT, suggestionIds: [...SUGGESTION_SETS.opening] };
  }

  async reply(input: ConversationInput): Promise<ConversationReply> {
    const received = input.message.text ?? "";

    const command = scriptedReply(input.message.suggestionId, received);
    if (command) return command;

    const raw = (() => {
      switch (input.message.kind) {
        case "voice":
          return this.voiceReply(input);
        case "photos":
          return this.photosReply(input);
        case "text":
          return this.textReply(input);
      }
    })();

    return validateReply({ ...raw, model: HeuristicResponder.MODEL }, input);
  }

  // MARK: Un vocal — la reformulation, puis la relance

  private voiceReply(input: ConversationInput): Omit<ConversationReply, "model"> {
    const transcript = input.message.text;

    if (!transcript || input.message.transcriptFailed) {
      return {
        beats: composeBeats("", [TRANSCRIPT_UNAVAILABLE]),
        disposition: "memory",
        suggestionIds: [...SUGGESTION_SETS.withoutTranscript],
        prompt: null,
        asksRoseEpineGraine: false,
      };
    }

    return {
      beats: composeBeats(transcript, [heard(firstSentence(transcript)), AFTER_TRANSCRIPT]),
      disposition: "memory",
      suggestionIds: [...SUGGESTION_SETS.trio],
      prompt: this.promptFor(input),
      asksRoseEpineGraine: false,
    };
  }

  // MARK: Des photos — le nombre, jamais le contenu

  private photosReply(input: ConversationInput): Omit<ConversationReply, "model"> {
    return {
      beats: [
        {
          text: photosReceived(input.message.photoCount),
          pauseMilliseconds: Math.min(2_600, 800 + input.message.photoCount * 250),
        },
      ],
      disposition: "memory",
      suggestionIds: [...SUGGESTION_SETS.neutral],
      prompt: null,
      asksRoseEpineGraine: false,
    };
  }

  // MARK: Un texte — une famille, choisie par priorité

  private textReply(input: ConversationInput): Omit<ConversationReply, "model"> {
    const text = input.message.text ?? "";
    const signals = readSignals(text);
    const alreadySaid = new Set(
      input.history.filter((turn) => turn.author === "memo" && turn.text).map((turn) => turn.text),
    );

    // La rose, l'épine et la graine, quand le code l'autorise : une journée
    // close vaut mieux qu'une relance de plus.
    if (input.allows.roseEpineGraine && !signals.isRefusal && !signals.isQuestion) {
      return {
        beats: composeBeats(text, [ROSE_EPINE_GRAINE]),
        disposition: this.disposition(signals, input),
        suggestionIds: [...SUGGESTION_SETS.neutral],
        prompt: this.promptFor(input),
        asksRoseEpineGraine: true,
      };
    }

    const candidates = this.candidates(signals, input);
    const chosen = candidates.find((candidate) => !alreadySaid.has(candidate.text)) ?? candidates[0]!;

    return {
      beats: composeBeats(text, [chosen.text]),
      disposition: this.disposition(signals, input),
      suggestionIds: [...SUGGESTION_SETS[chosen.suggestions]],
      prompt: this.promptFor(input),
      asksRoseEpineGraine: false,
    };
  }

  /**
   * **La priorité.** Chaque cran est là parce que l'ignorer produit une
   * réponse à côté.
   */
  private candidates(signals: ChatSignals, input: ConversationInput): Candidate[] {
    const candidates: Candidate[] = [];

    // 1. Le refus gagne sur tout.
    if (signals.isRefusal) {
      return [{ family: "refusal", text: REFUSAL, suggestions: "afterRefusal" }];
    }

    // 2. Une question obtient une réponse. Relancer par-dessus prouve que rien n'a été lu.
    if (signals.isQuestion) {
      return [
        {
          family: "answer",
          text: ANSWERS[signals.subject ?? "unknown"],
          suggestions: "afterAnswer",
        },
      ];
    }

    // 3. Une émotion difficile s'accuse **avant** toute demande.
    if (signals.mood === "negative") {
      NEGATIVE_MOOD.forEach((text, index) =>
        candidates.push({ family: `negative-${index}`, text, suggestions: "neutral" }),
      );
    }

    // 4. Deux mots ne font pas une page : on demande **un** détail précis.
    if (signals.length === "tooShort") {
      TOO_SHORT.forEach((text, index) =>
        candidates.push({ family: `short-${index}`, text, suggestions: "neutral" }),
      );
    }

    // 5. Le lieu ancre une page ; il passe avant la date.
    const knownPlace = input.step?.placeName ?? input.memo.destinationCity;
    if (signals.places.length === 0 && !knownPlace) {
      candidates.push({ family: "missing-place", text: MISSING_PLACE, suggestions: "neutral" });
    }

    // 6. Un lieu trouvé se répète **verbatim**.
    for (const place of signals.places) {
      candidates.push({ family: "place", text: foundPlace(place), suggestions: "neutral" });
    }

    // 7. La date, une fois le lieu connu.
    if (!signals.hasWhen && (signals.places.length > 0 || knownPlace)) {
      candidates.push({ family: "missing-date", text: MISSING_DATE, suggestions: "neutral" });
    }

    // 8. Un prénom : la fiche de cohérence en a besoin, donc on le demande.
    const known = this.peopleAlreadyMentioned(input);
    for (const name of signals.people) {
      candidates.push({
        family: "person",
        text: known.has(name) ? knownPerson(name) : newPerson(name),
        suggestions: "neutral",
      });
    }

    // 9. Un chiffre se recopie.
    for (const value of signals.figures) {
      candidates.push({ family: "figure", text: figure(value), suggestions: "neutral" });
    }

    // 10. Un message très long appelle un découpage, pas plus de matière.
    if (signals.length === "long") {
      candidates.push({ family: "long", text: LONG_MESSAGE, suggestions: "split" });
    }

    // 11. Une émotion heureuse s'amplifie.
    if (signals.mood === "positive") {
      candidates.push({ family: "positive", text: POSITIVE_MOOD, suggestions: "neutral" });
    }

    // 12. La rotation neutre, démarrée à un rang qui dépend de l'historique.
    const offset = input.history.length;
    for (let step = 0; step < ROTATION.length; step += 1) {
      candidates.push({
        family: `rotation-${step}`,
        text: ROTATION[(offset + step) % ROTATION.length]!,
        suggestions: "neutral",
      });
    }

    return candidates;
  }

  /** Les prénoms déjà passés dans le fil : « qui est-ce ? » ou « et Camille ? ». */
  private peopleAlreadyMentioned(input: ConversationInput): Set<string> {
    const names = new Set<string>();
    for (const turn of input.history) {
      if (turn.author !== "traveller" || !turn.text) continue;
      for (const name of readSignals(turn.text).people) names.add(name);
    }
    return names;
  }

  /**
   * Le classement du repli : une commande pour un refus ou une question, une
   * précision pour un texte court qui complète un souvenir non validé, un
   * souvenir sinon. Le modèle fait mieux ; le repli ne fait pas pire.
   */
  private disposition(signals: ChatSignals, input: ConversationInput): ChatDisposition {
    if (signals.isRefusal || signals.isQuestion) return "command";
    const current = input.currentEntry;
    if (signals.length === "tooShort" && current && !current.validatedAt) return "context";
    return "memory";
  }

  private promptFor(input: ConversationInput): string | null {
    return fallbackPrompt(input.step?.placeName ?? input.memo.destinationCity);
  }
}
