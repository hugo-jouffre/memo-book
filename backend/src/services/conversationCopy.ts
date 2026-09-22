/**
 * Ce que MEMO dit, et les puces qu'il propose — `docs/conversation.md`.
 *
 * **C'est la vérité livrée.** L'app porte la même copie dans
 * `MemoBookCore/ChatCopy.swift` pour ses aperçus Xcode et ses tests, mais ce
 * qui s'affiche dans un vrai fil vient d'ici : une phrase changée dans ce
 * fichier change dans l'app sans livrer une version. Les deux emplacements se
 * citent l'un l'autre ; le jour où ils divergent, c'est celui-ci qui gagne.
 *
 * Tout est tutoyé (ADR-006), sans ponctuation finale sur les puces, et aucune
 * phrase ne pose deux questions : `agents/agent-conversation.md` interdit le
 * formulaire déguisé.
 */

// ---------------------------------------------------------------------------
// L'accueil et l'ouverture
// ---------------------------------------------------------------------------

/** « Nouveau voyage à Rome ! » — le drapeau vient de la destination, jamais d'ici. */
export function greetingTitle(place: string | null, flag: string | null): string {
  if (!place) return "Nouveau carnet de voyage !";
  const title = `Nouveau voyage à ${place} !`;
  return flag ? `${title} ${flag}` : title;
}

export const GREETING_MESSAGE =
  "Je suis là pour transformer tes anecdotes, photos et enregistrements vocaux en un " +
  "magnifique récit structuré. Comment souhaites-tu commencer aujourd’hui ?";

/**
 * La première bulle blanche, celle que la maquette dessine en entier — et
 * **elle seule** : elle se termine déjà sur une question, rien ne vient la
 * recouvrir (§ 26 de `docs/ui-development.md`).
 */
export const OPENING_TEXT =
  "Bonjour 👋\n" +
  "Je suis MEMO, ton assistant pour t’aider à construire ton carnet de voyage.\n\n" +
  "Je suis là pour transformer ce que tu me racontes en un récit fluide.\n\n" +
  "Je m’adapte à ton style : tu peux me dicter ta journée, ta semaine, ton expérience " +
  "à l’oral ou l’écrire, comme tu préfères.\n\n" +
  "Avant de commencer pourrais-tu me faire un contexte global de ton voyage ? Cela " +
  "m’aidera à garder de la cohérence tout le long du récit.";

export const OPENING_PAUSE_MS = 700;

/** La réponse à « Commencer mon carnet » : une invitation, sans reproposer l'ouverture. */
export const OPENING_WITHOUT_PROMPT =
  "Raconte-moi ta journée, à l’oral ou au clavier. Je m’occupe du reste.";

// ---------------------------------------------------------------------------
// La fiche de retranscription
// ---------------------------------------------------------------------------

export const TRANSCRIPT_TITLE = "Retranscription du contexte";

/** La mention « généré par IA » qu'exige `docs/reglages-utilisateur.md`. */
export const TRANSCRIPT_FOOTNOTE = "Texte proposé par MEMO — tu peux le corriger.";

/** La relance qui suit une fiche remplie. */
export const AFTER_TRANSCRIPT =
  "Voilà ce que j’ai compris de ton vocal. Je le garde tel quel pour ton carnet, ou tu " +
  "veux le retoucher ?";

export const TRANSCRIPT_UNAVAILABLE =
  "Je n’ai pas réussi à écouter ce vocal. Tu peux me le réécrire ici, ou le " +
  "réenregistrer.";

// ---------------------------------------------------------------------------
// Les réponses de MEMO, par famille
// ---------------------------------------------------------------------------

/** Le voyageur ne veut plus répondre. « Ne jamais insister » est la règle la plus dure. */
export const REFUSAL =
  "Très bien, on s’arrête là. Ce que tu m’as raconté est gardé, tu reprendras quand tu " +
  "voudras.";

export const ACKNOWLEDGED = "C’est enregistré. Ton carnet compte une étape de plus.";

export const HANDING_OVER =
  "Je te laisse la main. Ta version fait autorité sur la mienne, je n’y retouche plus.";

export const LISTENING = "Je t’écoute. Reprends-le comme tu le dirais à quelqu’un.";

/** Ce que MEMO dit d'une correction faite au clavier, une fois enregistrée. */
export const EDITED_BY_HAND =
  "C’est ta version qui est dans le carnet maintenant. Je n’y retouche plus.";

export const ANSWERS = {
  book:
    "Ton carnet se met en page tout seul à partir de ce que tu racontes. Tu le relis en " +
    "aperçu, et rien ne part à l’impression sans que tu l’aies validé.",
  subscription:
    "Tu retrouves le prix et l’état de ton abonnement dans ton profil, à la ligne « Mon " +
    "abonnement ».",
  photos: "Ajoute tes photos quand tu veux : je les range avec le souvenir du jour.",
  corrections:
    "Tout se corrige. Tu relis chaque texte avant l’impression, et ta version fait " +
    "autorité sur la mienne.",
  pace:
    "Je te relance au rythme réglé pour ce voyage. Tu le changes dans les paramètres du " +
    "voyage.",
  unknown:
    "Je ne sais pas répondre à ça pour l’instant. Ce que je sais faire, c’est écouter ton " +
    "voyage et en tirer ton carnet — tu me racontes la suite ?",
} as const;

export const NEGATIVE_MOOD = [
  "Ça n’a pas dû être simple. Si tu veux le garder dans le carnet, raconte-moi ce qui t’a " +
    "remis d’aplomb.",
  "Je note la journée telle qu’elle a été, sans l’enjoliver. Tu veux qu’on s’arrête là " +
    "pour aujourd’hui ?",
] as const;

export const POSITIVE_MOOD =
  "On sent que tu y étais. Donne-moi le détail qui rendra bien à l’impression : une " +
  "odeur, un bruit, une phrase que quelqu’un a dite.";

export const TOO_SHORT = [
  "Je prends. Un détail de plus et j’en tire une page : c’était où, exactement ?",
  "D’accord. Qui était avec toi à ce moment-là ?",
] as const;

export const MISSING_PLACE =
  "Tu me dis où ça se passait ? Un quartier ou un nom de rue me suffit.";

/** Le lieu est recopié **verbatim** : MEMO ne complète pas un nom propre, il le répète. */
export function foundPlace(place: string): string {
  return `${place}, je note. Qu’est-ce qui t’a marqué là-bas ?`;
}

export const MISSING_DATE =
  "Ça date de quand ? Si c’était hier, je le range à la bonne journée du carnet.";

/** Tournure sans genre : le moteur ne sait pas si Camille est une femme ou un homme. */
export function newPerson(name: string): string {
  return `${name} apparaît pour la première fois dans ton carnet. Tu me dis en deux mots qui c’est ?`;
}

export function knownPerson(name: string): string {
  return `Et ${name} ? Raconte-moi ce que vous avez fait ensemble.`;
}

/** Le chiffre est recopié tel quel. Jamais converti, jamais additionné. */
export function figure(value: string): string {
  return `${value}, c’est noté : ça ira dans les compteurs du voyage. Ça t’a pris combien de temps ?`;
}

/** MEMO recompte ce qu'il a reçu ; il n'a pas regardé les images, et ne prétend pas le contraire. */
export function photosReceived(count: number): string {
  return count === 1
    ? "Une photo, je la range avec le souvenir du jour. Qu’est-ce qu’on y voit ?"
    : `${count} photos, je les range avec le souvenir du jour. Qu’est-ce qu’on y voit ?`;
}

/** La reformulation du repli : les mots du voyageur, entre guillemets, jamais les siens. */
export function heard(fragment: string): string {
  return `Tu me racontes que « ${fragment} ».`;
}

export const LONG_MESSAGE =
  "Il y a de quoi faire deux pages là-dedans. Je découpe en deux étapes, ou tu préfères " +
  "que ça reste d’un seul tenant ?";

/**
 * La rotation neutre, quand aucun signal ne ressort. Dix, parce que c'est le
 * nombre de soirs ternes qu'un voyage peut compter : une liste plus courte
 * force MEMO à se répéter avant la fin de la semaine.
 */
export const ROTATION = [
  "Le meilleur moment de ta journée, c’était lequel ?",
  "Et ce qui t’a agacé aujourd’hui, tu veux qu’on le garde ou qu’on le laisse de côté ?",
  "Qu’est-ce que tu attends le plus, pour demain ?",
  "Tu as une photo de ce moment-là, ou on en cherche une qui lui ressemble dans ta pellicule ?",
  "On regroupe ce souvenir avec la journée d’avant, ou il mérite sa propre page ?",
  "Qu’est-ce que tu as mangé, et où ? Ça donne toujours de bonnes pages.",
  "Tu as croisé quelqu’un dont tu te souviendras ?",
  "Si tu devais donner un titre à cette journée, ce serait quoi ?",
  "Qu’est-ce qui t’a surpris, par rapport à ce que tu imaginais ?",
  "Il te reste quelque chose à raconter sur aujourd’hui, ou on s’arrête là ?",
] as const;

/**
 * La rose, l'épine et la graine, en **une seule** bulle : le meilleur moment,
 * le pire, et ce qu'on retient. Posée une fois par journée racontée, jamais
 * avant que le souvenir en cours soit validé (`docs/conversation.md` § 3).
 */
export const ROSE_EPINE_GRAINE =
  "Pour clore la journée : la rose, l’épine et la graine — le meilleur moment, le pire, et " +
  "ce que tu en retiens. Dis-les-moi dans l’ordre que tu veux.";

/** La relance du voyage, écrite sans modèle : le lieu suffit à la rendre vraie. */
export function fallbackPrompt(placeName: string | null): string | null {
  return placeName ? `Comment ça se passe à ${placeName} ?` : null;
}

// ---------------------------------------------------------------------------
// Les puces
// ---------------------------------------------------------------------------

/**
 * Ce qu'une puce fait dans l'app une fois envoyée. Au nom près de
 * `ChatSuggestion.Intent` côté Swift, en `snake_case` — une valeur inconnue y
 * retombe sur `send`.
 */
export type SuggestionIntent =
  | "send"
  | "send_then_write"
  | "send_then_edit_transcript"
  | "send_then_speak"
  | "import_photos";

export interface Suggestion {
  id: string;
  /** Au caractère près : c'est lui qui part comme message. */
  label: string;
  /** L'emoji, séparé du libellé pour ne partir ni dans le message ni dans VoiceOver. */
  symbol: string | null;
  intent: SuggestionIntent;
}

/**
 * Le catalogue. Une puce n'est pas un raccourci d'interface : c'est une phrase
 * que le voyageur envoie, posée en bulle bleue. Le modèle et le repli ne
 * choisissent que des **identifiants** dans cette liste, jamais un libellé.
 */
export const SUGGESTIONS = {
  accept: { id: "accept", label: "Ça me convient", symbol: "👌", intent: "send" },
  "edit-hand": {
    id: "edit-hand",
    label: "J’aimerais faire des modifications à la main",
    symbol: "✍️",
    intent: "send_then_edit_transcript",
  },
  "edit-voice": {
    id: "edit-voice",
    label: "J’aimerais faire des modifications à l’oral",
    symbol: "🎙",
    intent: "send_then_speak",
  },
  rewrite: { id: "rewrite", label: "Je te le réécris ici", symbol: "✍️", intent: "send_then_write" },
  "record-again": {
    id: "record-again",
    label: "Je réenregistre",
    symbol: "🎙",
    intent: "send_then_speak",
  },
  start: { id: "start", label: "Commencer mon carnet", symbol: "🚀", intent: "send_then_speak" },
  photos: { id: "photos", label: "Importer des photos", symbol: "📷", intent: "import_photos" },
  dictate: { id: "dictate", label: "Raconter à l’oral", symbol: "🎙", intent: "send_then_speak" },
  voice: { id: "voice", label: "Je te raconte à l’oral", symbol: "🎙", intent: "send_then_speak" },
  write: { id: "write", label: "Je préfère écrire", symbol: "✍️", intent: "send_then_write" },
  later: { id: "later", label: "Plus tard", symbol: "⏰", intent: "send" },
  tomorrow: { id: "tomorrow", label: "On en reparle demain", symbol: "🌙", intent: "send" },
  else: { id: "else", label: "Je te raconte autre chose", symbol: "💬", intent: "send_then_speak" },
  clear: { id: "clear", label: "C’est clair, merci", symbol: "👍", intent: "send" },
  another: {
    id: "another",
    label: "J’ai une autre question",
    symbol: "❓",
    intent: "send_then_write",
  },
  resume: { id: "resume", label: "Je reprends mon récit", symbol: "📖", intent: "send_then_speak" },
  split: { id: "split", label: "Découpe en deux étapes", symbol: "✂️", intent: "send" },
  keep: { id: "keep", label: "Garde d’un seul tenant", symbol: "🧩", intent: "send" },
} as const satisfies Record<string, Suggestion>;

export type SuggestionId = keyof typeof SUGGESTIONS;

export const SUGGESTION_IDS = Object.keys(SUGGESTIONS) as SuggestionId[];

export function isSuggestionId(value: string): value is SuggestionId {
  return Object.prototype.hasOwnProperty.call(SUGGESTIONS, value);
}

/** Retrouve une puce par son libellé exact — un client qui n'envoie pas l'identifiant. */
export function suggestionIdForLabel(label: string): SuggestionId | null {
  const trimmed = label.trim();
  for (const id of SUGGESTION_IDS) {
    if (SUGGESTIONS[id].label === trimmed) return id;
  }
  return null;
}

/** Des identifiants vers les objets, en écartant ceux que le catalogue ne connaît pas. */
export function suggestionsFor(ids: readonly string[]): Suggestion[] {
  const seen = new Set<string>();
  const result: Suggestion[] = [];
  for (const id of ids) {
    if (!isSuggestionId(id) || seen.has(id)) continue;
    seen.add(id);
    result.push(SUGGESTIONS[id]);
    if (result.length === 3) break;
  }
  return result;
}

/**
 * Les jeux, un par situation. Le trio de validation ne suit qu'une fiche qui
 * porte du **vrai** texte : « Ça me convient » sous une question ouverte ne
 * répond à rien, et ça se voit immédiatement.
 */
export const SUGGESTION_SETS = {
  trio: ["accept", "edit-hand", "edit-voice"],
  withoutTranscript: ["rewrite", "record-again", "later"],
  opening: ["start", "photos", "dictate"],
  neutral: ["voice", "write", "later"],
  afterAnswer: ["clear", "another", "resume"],
  afterRefusal: ["tomorrow", "else"],
  afterAccept: ["dictate", "photos", "later"],
  split: ["split", "keep"],
  none: [],
} as const satisfies Record<string, readonly SuggestionId[]>;

export type SuggestionSet = keyof typeof SUGGESTION_SETS;

/**
 * Ce que MEMO répond à ses propres puces, **sans modèle** : une commande
 * connue n'a pas besoin qu'on la comprenne. Absente d'ici, une puce est
 * traitée comme un texte libre.
 */
export const SCRIPTED_ANSWERS: Partial<
  Record<SuggestionId, { text: string; suggestions: SuggestionSet }>
> = {
  accept: { text: ACKNOWLEDGED, suggestions: "afterAccept" },
  "edit-hand": { text: HANDING_OVER, suggestions: "none" },
  rewrite: { text: HANDING_OVER, suggestions: "none" },
  "edit-voice": { text: LISTENING, suggestions: "none" },
  "record-again": { text: LISTENING, suggestions: "none" },
  write: { text: HANDING_OVER, suggestions: "none" },
  voice: { text: LISTENING, suggestions: "none" },
  later: { text: REFUSAL, suggestions: "afterRefusal" },
  tomorrow: { text: REFUSAL, suggestions: "afterRefusal" },
  // Pas `opening` : reproposer « Commencer mon carnet » à quelqu'un qui vient
  // de commencer son carnet est le détail qui dit qu'il n'y a personne en face.
  start: { text: OPENING_WITHOUT_PROMPT, suggestions: "afterAccept" },
  dictate: { text: LISTENING, suggestions: "none" },
};

/**
 * Les commandes que l'app fabrique elle-même, sans puce visible : l'accusé
 * d'une correction au clavier. Elles passent par `suggestionId` comme les
 * puces, pour la même raison — répondre sans modèle et sans compter un souvenir.
 */
export const SILENT_COMMANDS = {
  transcript_edited: { text: EDITED_BY_HAND, suggestions: "afterAccept" },
} as const satisfies Record<string, { text: string; suggestions: SuggestionSet }>;

export type SilentCommandId = keyof typeof SILENT_COMMANDS;

export function isSilentCommand(value: string): value is SilentCommandId {
  return Object.prototype.hasOwnProperty.call(SILENT_COMMANDS, value);
}
