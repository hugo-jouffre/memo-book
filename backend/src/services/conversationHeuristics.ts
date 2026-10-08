import type { ChatDisposition } from "@prisma/client";
import type { CallToActionId } from "./callsToAction.js";
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
  TRANSCRIPT_UNAVAILABLE,
  fallbackPrompt,
  figure,
  foundPlace,
  heard,
  knownPerson,
  newPerson,
  photosReceived,
  tooShort,
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
  type TripContextTurnInput,
  type TripContextTurnReply,
  type MemoResponder,
} from "./conversation.js";
import { updateByRules } from "./tripContext.js";

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

/**
 * Un texte court qui **précise** le souvenir en cours — « avec Clara »,
 * « mardi » —, et non un message isolé : il y a un souvenir, et il n'est pas
 * encore validé.
 */
function answersCurrentEntry(input: ConversationInput): boolean {
  const current = input.currentEntry;
  return current !== null && !current.validatedAt;
}

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
  if (talksAboutSubscription(folded)) return "subscription";
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
  /**
   * Les mots qui nomment l'offre à eux seuls, cherchés **en début de mot**
   * (`startsAWord`) : « abonnement », « s’abonner », « résilier »,
   * « illimité ». Ces listes ouvrent la porte du bouton `subscribe`
   * (`mentionsSubscription`) : elles ne visent que l'abonnement, le crédit du
   * jour, la limite du récit et le temps qui reste pour raconter — **pas le
   * prix d'un billet ni la limite de vitesse** (03/10/2026). L'app en garde
   * la copie exacte (`ChatAnalysis.swift`).
   */
  subscriptionWords: new Set(["abonn", "resili", "illimit"]),
  /**
   * Ce qui fait d'« illimité », d'« abonnement » ou d'un prix d'app une autre
   * offre que la nôtre, en mots entiers : le wifi illimité, le kilométrage
   * illimité, l'abonnement de métro, le forfait qu'on résilie (03/10/2026).
   */
  otherOffers: new Set([
    "wifi", "wi-fi", "internet", "data", "forfait", "forfaits", "telephone", "telephonique",
    "mobile", "kilometrage", "location", "metro", "transport", "transports", "navigo",
    "bus", "tram", "train", "trains", "pass", "parking", "velo", "velos", "ski", "musee",
    "musees", "buffet", "boisson", "boissons", "salle de sport", "piscine",
  ]),
  /**
   * Le crédit qui n'est pas le nôtre, en mots entiers : celui du téléphone, de
   * la carte, de la banque. « Je n’ai plus de crédit sur mon téléphone » n'est
   * pas une question sur le récit.
   */
  otherCreditWords: new Set([
    "telephone", "telephones", "telephonique", "portable", "mobile", "sim", "forfait",
    "forfaits", "carte", "cartes", "bancaire", "banque", "operateur", "distributeur",
    "retrait", "data", "internet",
  ]),
  /**
   * Recharger un téléphone, en mots entiers — sauf le crédit qui « se
   * recharge » à minuit, qui est le nôtre (`DAILY_CREDIT_EXHAUSTED_MESSAGE`).
   */
  rechargeWords: new Set(["recharger", "recharge", "recharges", "rechargement"]),
  /**
   * Le crédit du jour et la limite du récit, en locutions et en mots entiers
   * (`isAWord`), qui n'ont pas d'autre sens en voyage. « crédit » ou « limite »
   * seuls n'y sont pas : « carte de crédit » et « limite de vitesse » parlent
   * du voyage.
   */
  creditPhrases: new Set([
    "credit du jour", "credit restant", "credit quotidien", "credit de temps",
    "credit de recit", "mon credit", "ton credit", "notre credit", "votre credit",
    "combien de credit", "de credit il reste", "de credit il me reste",
    "limite du jour", "limite de recit", "limite du recit", "limite de minutes",
    "limite quotidienne", "limite par jour", "limite du credit",
    "raconter sans limite", "parler sans limite", "minutes de recit", "temps de recit",
    "raconter combien de temps", "parler combien de temps",
  ]),
  /**
   * Les locutions du temps et du crédit qui disent aussi le voyage :
   * « combien de minutes » est « à combien de minutes à pied », « limite de
   * temps » celle du Louvre, « plus de crédit » celui du téléphone. Elles ne
   * visent l'offre que **rattachées au récit** (`creditAnchors`, `appReferences`)
   * et loin d'un trajet (`travelMarkers`) — 03/10/2026.
   */
  anchoredCreditPhrases: new Set([
    "le credit", "du credit", "plus de credit", "de credit",
    "limite de temps", "sans limite de temps", "est limite", "c'est limite a",
    "suis limite", "suis limitee", "suis bloque", "suis bloquee",
    "combien de minutes", "combien de temps", "minutes par jour", "minutes aujourd",
    "minutes du jour", "minutes restantes", "temps restant",
  ]),
  /**
   * Ce qui rattache une locution au récit, cherché **en début de mot** :
   * raconter, le récit, un vocal, l'abonnement, la journée de crédit.
   */
  creditAnchors: new Set([
    "racont", "recit", "enregistr", "vocal", "vocaux", "abonn", "illimit", "aujourd",
    "par jour", "du jour", "minuit", "se recharg", "5 minutes", "cinq minutes",
  ]),
  /** Un trajet, une visite, un départ — en mots entiers : le temps qu'il faut, pas celui qui reste pour raconter. */
  travelMarkers: new Set([
    "a pied", "de marche", "marche", "marcher", "pour aller", "pour rejoindre", "pour arriver",
    "en voiture", "en taxi", "en bus", "en train", "en metro", "en avion", "en bateau",
    "embarquement", "depart", "vol", "vols", "train", "bus", "metro", "avion", "bateau",
    "ferry", "trajet", "visite", "visiter", "attente", "escale", "correspondance", "check-in",
  ]),
  /**
   * « Il me reste combien ? » — la question d'exemple du prompt
   * (`agents/agent-conversation.md`). Elle ne vise le crédit que si rien ne la
   * suit, hors `remainingObjects` puis `remainingTails` (ou un mot du récit) :
   * « de jours de voyage », « avant l’embarquement », « jusqu’à Florence »
   * parlent du voyage (`asksWhatRemains`).
   */
  remainingQuestions: [
    "il me reste combien", "il nous reste combien", "il reste combien",
    "combien il me reste", "combien il nous reste", "combien il reste",
    "combien me reste-t-il", "combien nous reste-t-il", "combien reste-t-il",
    "combien de temps il me reste", "combien de temps il nous reste", "combien de temps il reste",
    "combien de minutes il me reste", "combien de minutes il nous reste",
    "combien de minutes il reste", "temps qu'il me reste", "temps qu'il nous reste",
  ],
  remainingObjects: ["de temps", "de minutes", "de credit", "en credit"],
  remainingTails: new Set([
    "", "aujourd'hui", "pour aujourd'hui", "ce soir", "pour ce soir", "pour raconter",
    "a raconter", "pour parler", "pour enregistrer", "a enregistrer",
  ]),
  /**
   * Le prix, en mots entiers. Seul, il parle d'un billet, d'un musée ou du
   * carnet (« Combien coûte le carnet imprimé ? » va à `ANSWERS.book`) : il ne
   * vise l'offre que s'il nomme l'app (`appReferences`), ou dans une question
   * nue (`barePriceQuestions`). « euro » en mot entier : « Europe », « Eurostar ».
   */
  priceWords: new Set([
    "prix", "cout", "couts", "coute", "coutent", "couter", "coutera", "tarif", "tarifs",
    "payer", "payant", "payante", "paiement", "gratuit", "gratuite", "euro", "euros",
  ]),
  /**
   * L'app elle-même, en mots entiers : « l’app », « ton appli », « MemoBook ».
   * « une app gratuite pour le métro » en est une autre (03/10/2026).
   */
  appReferences: new Set([
    "memobook", "memo", "l'app", "l'appli", "l'application", "ton app", "ton appli",
    "ton application", "votre app", "votre appli", "votre application", "cette app",
    "cette appli", "cette application",
  ]),
  /**
   * Une question de prix ou de limite **qui est tout le message** : sans
   * objet, elle ne peut viser que l'app. « Le musée, c'est payant ? » a un
   * objet, et n'y est pas.
   */
  barePriceQuestions: new Set([
    "combien ca coute", "ca coute combien", "combien ca coute par mois",
    "ca coute combien par mois", "c'est combien", "c'est combien par mois", "combien c'est",
    "combien ca fait", "c'est payant", "c'est gratuit", "payant", "gratuit",
    "c'est quoi le prix", "quel est le prix", "quel prix", "il faut payer", "faut payer",
    "c'est quoi la limite", "quelle est la limite", "il y a une limite", "y a une limite",
    "c'est quoi la limite de temps", "quelle est la limite de temps",
    "il y a une limite de temps", "y a une limite de temps", "c'est limite",
    "c'est limite a combien", "pourquoi c'est limite", "je suis limite", "je suis limitee",
    "pourquoi je suis limite", "pourquoi je suis limitee", "je suis bloque", "je suis bloquee",
    "pourquoi je suis bloque", "pourquoi je suis bloquee",
  ]),
  /** Ce qui peut précéder une question nue sans lui donner d'objet. */
  bareQuestionOpeners: ["memo,", "et", "mais", "alors", "du coup", "sinon", "est-ce que"],
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

const LETTER = /\p{L}/u;

/**
 * `needle` commence un mot de `folded` : « coute » est dans « tu m’écoutes ? »,
 * et ce n'est pas une question de prix. `wholeWord` exige aussi qu'il le
 * finisse : « euro » est dans « Europe ». Écrit à la main plutôt qu'en
 * expression régulière pour rester le jumeau exact de
 * `Extraction.startsAWord` (`ChatAnalysis.swift`).
 */
function startsAWord(needle: string, folded: string, wholeWord = false): boolean {
  let from = 0;
  for (;;) {
    const found = folded.indexOf(needle, from);
    if (found === -1) return false;
    const end = found + needle.length;
    const startsHere = found === 0 || !LETTER.test(folded.charAt(found - 1));
    const endsHere = end === folded.length || !LETTER.test(folded.charAt(end));
    if (startsHere && (!wholeWord || endsHere)) return true;
    from = found + 1;
  }
}

function isAWord(needle: string, folded: string): boolean {
  return startsAWord(needle, folded, true);
}

/** Où finit chaque occurrence de `needle` en mot entier dans `folded` — l'endroit d'où lire la suite. */
function wholeWordEnds(needle: string, folded: string): number[] {
  const ends: number[] = [];
  let from = 0;
  for (;;) {
    const found = folded.indexOf(needle, from);
    if (found === -1) return ends;
    const end = found + needle.length;
    const startsHere = found === 0 || !LETTER.test(folded.charAt(found - 1));
    const endsHere = end === folded.length || !LETTER.test(folded.charAt(end));
    if (startsHere && endsHere) ends.push(end);
    from = found + 1;
  }
}

/**
 * Une question sans sa ponctuation finale ni son interpellation : « Ça coûte
 * combien, MEMO ? » rend « ca coute combien ». Le nom seul ne laisse rien.
 */
function questionCore(folded: string): string {
  let rest = folded.trim().replace(/[\s?!.…]+$/u, "");
  for (const name of ["memobook", "memo"]) {
    if (rest === name) return "";
    if (rest.endsWith(` ${name}`) || rest.endsWith(`,${name}`)) {
      rest = rest.slice(0, -name.length).replace(/[\s,]+$/u, "");
      break;
    }
  }
  return rest;
}

/** Le message entier, sans ses ouvertures (« et », « est-ce que »…) ni sa ponctuation finale. */
function isBarePriceQuestion(folded: string): boolean {
  let rest = questionCore(folded);
  let opened = true;
  while (opened) {
    opened = false;
    for (const opener of Lexicon.bareQuestionOpeners) {
      if (rest.startsWith(`${opener} `)) {
        rest = rest.slice(opener.length + 1).trimStart();
        opened = true;
      }
    }
  }
  return Lexicon.barePriceQuestions.has(rest);
}

const any = (words: Iterable<string>, test: (word: string) => boolean) => [...words].some(test);

/** Le texte parle du récit, de l'app ou de la journée de crédit (`creditAnchors`). */
function isAnchoredToTheStory(folded: string): boolean {
  return (
    any(Lexicon.creditAnchors, (anchor) => startsAWord(anchor, folded)) ||
    any(Lexicon.appReferences, (word) => isAWord(word, folded))
  );
}

function mentionsATrip(folded: string): boolean {
  return any(Lexicon.travelMarkers, (marker) => isAWord(marker, folded));
}

/** Le crédit du téléphone, de la carte, de la banque — pas celui du récit. */
function talksAboutAnotherCredit(folded: string): boolean {
  if (any(Lexicon.otherCreditWords, (word) => isAWord(word, folded))) return true;
  return any(Lexicon.rechargeWords, (word) => isAWord(word, folded)) && !folded.includes("se recharg");
}

/**
 * « Il me reste combien ? » vise le crédit si ce qui suit n'est rien, un objet
 * de crédit (« de temps », « de crédit ») suivi de rien, ou d'une fin admise
 * (« aujourd’hui », « pour raconter »), ou d'une suite qui parle du récit sans
 * trajet. « de jours de voyage », « avant l’embarquement » : non.
 */
function asksWhatRemains(folded: string): boolean {
  for (const question of Lexicon.remainingQuestions) {
    for (const end of wholeWordEnds(question, folded)) {
      let tail = questionCore(folded.slice(end).replace(/^[\s,]+/u, ""));
      for (const object of Lexicon.remainingObjects) {
        if (tail === object || tail.startsWith(`${object} `)) {
          tail = tail.slice(object.length).trim();
          break;
        }
      }
      if (Lexicon.remainingTails.has(tail)) return true;
      if (isAnchoredToTheStory(tail) && !mentionsATrip(tail)) return true;
    }
  }
  return false;
}

/**
 * Le cœur de `subjectOf` et de `mentionsSubscription`, sur un texte déjà
 * replié. **Jamais spontanément** (Hugo, 03/10/2026) : c'est la porte du bouton
 * `subscribe`, et du repli qui récite l'offre. Une question de voyage qui
 * frôle le vocabulaire — « à combien de minutes à pied », « le wifi
 * illimité », « plus de crédit sur mon téléphone » — ne l'ouvre pas.
 */
function talksAboutSubscription(folded: string): boolean {
  const otherOffer = any(Lexicon.otherOffers, (word) => isAWord(word, folded));
  // 1. L'offre nommée — pas le wifi illimité ni l'abonnement de métro.
  if (!otherOffer && any(Lexicon.subscriptionWords, (word) => startsAWord(word, folded))) return true;
  // 2. Le crédit du jour, la limite du récit, le temps qui reste — pas le
  //    crédit du téléphone ni le temps de trajet.
  if (!talksAboutAnotherCredit(folded)) {
    if (any(Lexicon.creditPhrases, (phrase) => isAWord(phrase, folded))) return true;
    if (
      any(Lexicon.anchoredCreditPhrases, (phrase) => isAWord(phrase, folded)) &&
      isAnchoredToTheStory(folded) &&
      !mentionsATrip(folded)
    ) {
      return true;
    }
    if (asksWhatRemains(folded)) return true;
  }
  // 3. Une question de prix ou de limite qui est tout le message.
  if (isBarePriceQuestion(folded)) return true;
  // 4. Un prix qui nomme l'app — mais « le carnet MemoBook » coûte le prix du
  //    carnet, et « une app gratuite pour le métro » en est une autre.
  return (
    !otherOffer &&
    any(Lexicon.priceWords, (word) => isAWord(word, folded)) &&
    any(Lexicon.appReferences, (word) => isAWord(word, folded)) &&
    !any(Lexicon.bookWords, (word) => folded.includes(word))
  );
}

/**
 * Le message parle-t-il de l'abonnement, du crédit du jour, de la limite du
 * récit ou du temps qui reste pour raconter ? C'est la porte du bouton
 * `subscribe` (`callsToActionAllowed`) : MEMO ne propose l'abonnement qu'à qui
 * en parle (Hugo, 03/10/2026). Le même jugement que `subjectOf`.
 */
export function mentionsSubscription(text: string): boolean {
  return talksAboutSubscription(fold(text.trim()));
}

// ---------------------------------------------------------------------------
// Le répondeur
// ---------------------------------------------------------------------------

interface Candidate {
  family: string;
  text: string;
  suggestions: SuggestionSet;
  /** Le bouton sous la bulle — `validateReply` le jette si le tour ne le permet pas. */
  callToActionId?: CallToActionId;
}

export class HeuristicResponder implements MemoResponder {
  static readonly MODEL = "heuristic";

  opening(): { text: string; suggestionIds: SuggestionId[] } {
    return { text: OPENING_TEXT, suggestionIds: [...SUGGESTION_SETS.opening] };
  }

  /** Le repli ne découpe pas une description libre : il range la réponse à la question posée. */
  async gatherContext(input: TripContextTurnInput): Promise<TripContextTurnReply> {
    return {
      update: updateByRules(input.context, input.text, input.travellerFirstName),
      acknowledgement: null,
      model: "heuristic",
    };
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
        callToActionId: null,
      };
    }

    return {
      beats: composeBeats(transcript, [heard(firstSentence(transcript)), AFTER_TRANSCRIPT]),
      disposition: "memory",
      suggestionIds: [...SUGGESTION_SETS.trio],
      prompt: this.promptFor(input),
      asksRoseEpineGraine: false,
      callToActionId: null,
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
      callToActionId: null,
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
        callToActionId: null,
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
      callToActionId: chosen.callToActionId ?? null,
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
    //    Sur le prix ou la limite : les faits, et le bouton qui mène à l'offre —
    //    sauf à un abonné, qui n'a rien à découvrir.
    if (signals.isQuestion) {
      if (signals.subject === "subscription") {
        return input.traveller.isUnlimited
          ? [{ family: "answer", text: ANSWERS.subscriptionUnlimited, suggestions: "afterAnswer" }]
          : [
              {
                family: "answer",
                text: ANSWERS.subscription,
                suggestions: "afterAnswer",
                callToActionId: "subscribe",
              },
            ];
      }
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

    // 4. Deux mots ne font pas une page — et MEMO **le dit** (Hugo,
    //    08/10/2026) au lieu d'enchaîner sur une question qu'il aurait
    //    inventée : il recopie ce qu'il a reçu, dit qu'il n'a pas compris, et
    //    demande la suite sans en choisir le sujet. Rien d'autre ne vient
    //    après : un lieu ou une date demandés sous un « ok » supposaient un
    //    récit que personne n'a fait.
    if (signals.length === "tooShort" && !answersCurrentEntry(input)) {
      return tooShort(input.message.text ?? "").map((text, index) => ({
        family: `short-${index}`,
        text,
        suggestions: "neutral" as const,
      }));
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
    // Les compagnons du contexte du voyage sont connus d'avance : « Clara
    // apparaît pour la première fois » après qu'on l'a présentée serait faux.
    const names = new Set<string>(input.memo.tripContext?.companions.map((companion) => companion.name) ?? []);
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
    if (signals.length === "tooShort" && answersCurrentEntry(input)) return "context";
    // Trop court, et rien à préciser : ce n'est pas un souvenir, c'est un
    // message que MEMO n'a pas compris — il le dit (`tooShort`), et rien
    // n'entre dans le carnet.
    if (signals.length === "tooShort") return "command";
    return "memory";
  }

  private promptFor(input: ConversationInput): string | null {
    return fallbackPrompt(input.step?.placeName ?? input.memo.destinationCity);
  }
}
