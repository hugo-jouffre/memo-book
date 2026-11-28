/**
 * **L'emoji que MEMO pose sur une bulle** — T296.
 *
 * « MEMO répond par un emoji plutôt que par un message » (Hugo, 28/11/2026).
 * Un tour du voyageur porte donc une pastille, à la manière d'une réaction
 * iMessage ou Instagram, et c'est **l'état de ce tour** qu'elle dit :
 *
 * | Pastille | Ce qu'elle dit | Qui la décide |
 * |---|---|---|
 * | ⬆️ | partira au retour du réseau | **l'app seule** — le serveur n'a jamais vu ce tour |
 * | 👀 | MEMO est en train de le lire | `repliedAt` encore nul |
 * | 🚂 ✈️ 🚘 ⛵️ … | le déplacement que le récit nomme | `entry.insights.transports` |
 * | ✅ | pris en compte | le reste |
 * | 👍 | tu as validé ce texte | une réaction du voyageur sur une bulle de MEMO |
 *
 * ⚠️ **Rien de tout ça n'est stocké.** La pastille se *calcule* à chaque
 * lecture, comme le nombre d'étapes ou la fraîcheur d'un écran : une colonne
 * de plus serait une seconde vérité à tenir d'accord avec `repliedAt` et les
 * relevés de la rédaction. La seule chose qui s'écrit est le 👍, et il s'écrit
 * là où il se lit déjà — la validation du souvenir, plus l'identifiant de la
 * bulle visée dans le `payload` du tour (voir `routes/chat.ts`).
 *
 * ⚠️ **L'emoji et son libellé partent ensemble.** Le glyphe ne se lit pas à
 * voix haute : VoiceOver annoncerait « visage avec des yeux ». Le serveur rend
 * donc les deux, comme il rend ses messages d'erreur en français — l'app
 * dessine l'un et lit l'autre, et il n'y a pas de table à tenir d'accord des
 * deux côtés (même règle que les cinq icônes météo).
 */

import type { ChatAuthor, Prisma, TripTransport } from "@prisma/client";

import { parseInsights } from "./redaction.js";
import { STEP_TRANSPORT } from "./tripFacts.js";

export interface ChatReaction {
  /** Le glyphe, tel que la bulle le dessine. */
  emoji: string;
  /** Ce que VoiceOver lit à sa place, et le texte d'accessibilité de l'app. */
  label: string;
}

/** MEMO l'a reçu et ne l'a pas encore traité. */
export const READING: ChatReaction = { emoji: "👀", label: "MEMO est en train de le lire" };

/** Traité, et rien de plus à en dire. */
export const TAKEN: ChatReaction = { emoji: "✅", label: "MEMO l’a pris en compte" };

/** Le voyageur a dit que le texte lui convenait — en réagissant, sans écrire. */
export const VALIDATED: ChatReaction = { emoji: "👍", label: "Tu as validé ce texte" };

/**
 * Le déplacement raconté, ramené aux sept d'une étape par `STEP_TRANSPORT` —
 * le métro roule sur des rails, le taxi sur la route.
 *
 * Le ticket en nommait quatre (🚘 ✈️ 🚂 ⛵️) ; les sept y sont, parce qu'un
 * trajet en bus qui s'afficherait ✅ pendant qu'un trajet en voiture
 * s'affiche 🚘 se lirait comme un bug. Les trois ajoutés se retirent en
 * trois lignes.
 */
const TRANSPORT_REACTION: Record<TripTransport, ChatReaction> = {
  plane: { emoji: "✈️", label: "MEMO a noté ton vol" },
  train: { emoji: "🚂", label: "MEMO a noté ton trajet en train" },
  bus: { emoji: "🚌", label: "MEMO a noté ton trajet en bus" },
  car: { emoji: "🚘", label: "MEMO a noté ton trajet en voiture" },
  boat: { emoji: "⛵️", label: "MEMO a noté ta traversée" },
  bike: { emoji: "🚲", label: "MEMO a noté ton trajet à vélo" },
  walk: { emoji: "🚶", label: "MEMO a noté que tu as marché" },
};

/** Ce qu'il faut d'une bulle pour en déduire sa pastille. */
export interface ReactionInput {
  author: ChatAuthor;
  /** Une puce n'est pas un message qu'on lit : elle ne reçoit pas de pastille. */
  suggestionId: string | null;
  /** L'instant où MEMO a fini de répondre — nul tant que le job n'est pas passé. */
  repliedAt: Date | null;
  /** Le souvenir de cette bulle, pour ses relevés. */
  entry: { insights: Prisma.JsonValue } | null;
}

/**
 * La pastille d'une bulle, ou `null` quand elle n'en porte pas.
 *
 * `wasReactedTo` ne vaut que pour une bulle de MEMO : c'est le 👍 que le
 * voyageur y a posé.
 *
 * ⚠️ **Le transport arrive après coup**, et c'est voulu : `repliedAt` tombe
 * dès que `converse` est passé, les relevés seulement quand la rédaction a
 * écrit le souvenir. La pastille passe donc ✅ puis 🚂, et le fil se relit
 * tout seul entre les deux. L'inverse — attendre la rédaction pour dire
 * quelque chose — laisserait 👀 une minute de trop sur un message déjà lu.
 */
export function reactionFor(message: ReactionInput, wasReactedTo = false): ChatReaction | null {
  if (message.author === "memo") return wasReactedTo ? VALIDATED : null;
  if (message.suggestionId !== null) return null;
  if (message.repliedAt === null) return READING;

  const kind = message.entry ? parseInsights(message.entry.insights).transports[0]?.kind : undefined;
  return kind ? TRANSPORT_REACTION[STEP_TRANSPORT[kind]] : TAKEN;
}
