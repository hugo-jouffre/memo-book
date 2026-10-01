import { SUBSCRIPTION_WEEKLY_CENTS } from "./subscriptionCatalog.js";

/**
 * Les mots des notifications — **ici et nulle part ailleurs**, comme
 * `mailTemplates.ts` pour les e-mails : le planificateur décide *quand*, ce
 * fichier dit *quoi*.
 *
 * Les règles de l'app s'appliquent : on tutoie (R9), apostrophe typographique
 * (R8). Une notification se lit en deux secondes sur un écran verrouillé : un
 * titre qui dit de quoi il s'agit, une phrase qui dit quoi faire.
 *
 * ⚠️ **Aucun de ces textes ne vient d'une maquette** : la feuille ne les écrit
 * pas, elle en donne l'objectif et le ton. Ils sont à relire par Clara.
 */

export interface NotificationText {
  title: string;
  body: string;
}

const euroFormatter = new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" });

/** « 1,99 € ». */
export function formatEuros(cents: number): string {
  return euroFormatter.format(cents / 100);
}

/** « Rome », sinon le nom du voyage — « Notre tour du monde ». */
function placeOf(trip: { city: string | null; title: string }): string {
  return trip.city?.trim() || trip.title.trim();
}

/**
 * « à Rome » — mais « pour Notre tour du monde » quand on n'a qu'un titre :
 * « à Notre tour du monde » ne se dit pas.
 */
function atPlace(trip: { city: string | null; title: string }): string {
  return trip.city?.trim() ? `à ${trip.city.trim()}` : `« ${trip.title.trim()} »`;
}

/**
 * **Fin des 3 jours offerts** — J+3 après le premier voyage. Ton pédagogique,
 * et le rappel que les semaines payées sont déduites du carnet.
 *
 * Le texte ne dit pas « ton essai est fini » : l'app offre aujourd'hui trois
 * **étapes**, pas trois jours, et quelqu'un qui n'a raconté qu'une étape en
 * trois jours en a encore deux. Il dit ce qui est vrai dans les deux cas — la
 * suite passe par l'abonnement. Voir `docs/notifications.md` § Points ouverts.
 */
export function trialEndText(): NotificationText {
  return {
    title: "Ton carnet ne fait que commencer",
    body:
      `Pour continuer à raconter ton voyage à voix haute, l’abonnement est à ` +
      `${formatEuros(SUBSCRIPTION_WEEKLY_CENTS)}/semaine. Et chaque semaine payée ` +
      `est déduite du prix de ton carnet.`,
  };
}

/** Où en est l'abonnement le jour où le voyage se termine. */
export type SubscriptionAtTripEnd =
  /** Pas d'abonnement : rien à arrêter. */
  | "none"
  /** Un abonnement que **le serveur** arrête — tout ce qui n'est pas Apple. */
  | "stops_automatically"
  /**
   * Un abonnement App Store dont le renouvellement est armé. Apple ne laisse
   * aucune app résilier à la place de son client : on ne peut pas écrire
   * « arrêté automatiquement », on l'invite à le couper — l'accueil le
   * propose en un geste (`subscriptionOutlivesTrip`).
   */
  | "renews_at_apple";

/**
 * **Fin du voyage** — le jour de la date de fin. L'abonnement, ce qui est déjà
 * versé, l'estimation du carnet ; le toucher ouvre la cagnotte du voyage, qui
 * porte les mêmes chiffres.
 */
export function tripEndText(input: {
  trip: { city: string | null; title: string };
  subscription: SubscriptionAtTripEnd;
  paidCents: number;
  estimateCents: number;
  /** Un carnet vide n'a ni estimation à donner, ni commande à proposer. */
  hasStories: boolean;
}): NotificationText {
  const sentences: string[] = [];

  if (input.subscription === "stops_automatically") {
    sentences.push("Ton abonnement s’arrête automatiquement.");
  } else if (input.subscription === "renews_at_apple") {
    sentences.push("Ton abonnement n’a plus de raison de courir : coupe-le en un geste depuis l’accueil.");
  }

  if (input.hasStories) {
    if (input.paidCents > 0) {
      sentences.push(
        `Tu as déjà versé ${formatEuros(input.paidCents)}, déduits de ton carnet estimé à ` +
          `${formatEuros(input.estimateCents)}.`,
      );
    } else {
      sentences.push(`Ton carnet est estimé à ${formatEuros(input.estimateCents)}.`);
    }
    sentences.push("Il n’attend plus que ta commande.");
  }

  return {
    title: `Ton voyage ${atPlace(input.trip)} se termine aujourd’hui`,
    body: sentences.join(" "),
  };
}

/**
 * **Relance d'écriture** — le carnet d'un voyage en cours se tait. La relance
 * du voyage (`memos.prompt`, « Comment ça se passe à Trastevere ? ») quand
 * elle existe : elle est écrite à partir de ce qui a déjà été raconté.
 */
export function writingReminderText(input: {
  trip: { city: string | null; title: string };
  prompt: string | null;
  hasStories: boolean;
}): NotificationText {
  const place = placeOf(input.trip);
  return {
    title: input.hasStories ? `Et la suite, ${atPlace(input.trip)} ?` : `Ton carnet ${atPlace(input.trip)} t’attend`,
    body:
      input.prompt?.trim() ||
      (input.hasStories
        ? `Raconte à MEMO ce que tu as vécu depuis : un vocal de deux minutes suffit pour ne rien oublier de ${place}.`
        : "Raconte à MEMO ta première journée : un vocal de deux minutes, et ton carnet commence."),
  };
}

/** **Carnet terminé mais pas commandé** — quelques jours après la fin. */
export function unorderedBookText(trip: { city: string | null; title: string }): NotificationText {
  return {
    title: `Ton carnet ${atPlace(trip)} t’attend`,
    body: "Tes souvenirs sont prêts à devenir un vrai livre. Feuillette l’aperçu et commande-le quand tu veux.",
  };
}

/**
 * « vacances de la Toussaint », « vacances d’été » — le libellé du ministère,
 * mis en minuscule pour entrer dans une phrase.
 */
export function holidayName(label: string): string {
  const cleaned = label
    .replace(/^Début des\s+/i, "")
    .replace(/'/g, "’")
    // Les saisons sont des noms communs ; la Toussaint et Noël, non.
    .replace("Été", "été")
    .replace("Hiver", "hiver")
    .replace("Printemps", "printemps");
  return cleaned.charAt(0).toLowerCase() + cleaned.slice(1);
}

/** **Vacances scolaires** — J-7, J-3, jour J. */
export function schoolHolidaysText(label: string, daysBefore: number): NotificationText {
  const name = holidayName(label);
  const capitalised = name.charAt(0).toUpperCase() + name.slice(1);

  if (daysBefore === 0) {
    return {
      title: `C’est le début des ${name} !`,
      body: "Tu pars ? Crée ton voyage, et raconte-le à MEMO au fil des jours.",
    };
  }
  return {
    title: daysBefore === 7 ? `${capitalised} dans une semaine` : `${capitalised} dans ${daysBefore} jours`,
    body: "Un voyage en vue ? Crée-le dès maintenant : MEMO t’aidera à garder chaque souvenir.",
  };
}

/** **Comportement appris** — la période d'un voyage passé revient. */
export function learnedPeriodText(input: {
  trip: { city: string | null; title: string };
  yearsAgo: number;
}): NotificationText {
  const when = input.yearsAgo === 1 ? "L’an dernier" : `Il y a ${input.yearsAgo} ans`;
  return {
    title: `${when} à la même époque, tu partais ${atPlace(input.trip)}`,
    body: "Un nouveau voyage en vue cette année ? Crée-le, MEMO s’occupe du carnet.",
  };
}

/** **Anniversaire** — quelques jours avant. */
export function birthdayText(): NotificationText {
  return {
    title: "Ton anniversaire approche 🎂",
    body: "Et si tu le fêtais en voyage ? Crée ton prochain carnet, MEMO le racontera avec toi.",
  };
}
