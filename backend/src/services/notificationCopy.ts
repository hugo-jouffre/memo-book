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
 * « Chaque semaine payée est déduite du prix du carnet » — **en pause** depuis
 * le 02/10/2026 (Hugo), comme la carte « Tes abonnements sont déduits ! » du
 * paywall (`PaywallCopy.deductedSubscriptions`, côté app) : rien ne crédite
 * encore la cagnotte des semaines payées chez Apple, et `printPricing.ts` ne
 * déduit que la cagnotte. Les deux textes qui le promettaient se taisent tant
 * que ce drapeau est faux ; il se rallume avec la carte.
 */
const SUBSCRIPTION_WEEKS_DEDUCTED = false;

/**
 * **Fin des 3 étapes offertes** — le lendemain de la dernière. Ton
 * pédagogique, et — quand la déduction reviendra — le rappel que les semaines
 * payées sont déduites du carnet.
 *
 * Des **étapes**, jamais des jours : c'est ce que l'app offre, et ce que
 * l'accueil compte (Clara, 02/10/2026). Le prix vient du catalogue.
 */
export function trialEndText(offeredSteps: number): NotificationText {
  return {
    title: `Tes ${offeredSteps} étapes offertes sont racontées`,
    body:
      `Ton carnet ne fait que commencer : pour continuer à le raconter, l’abonnement est à ` +
      `${formatEuros(SUBSCRIPTION_WEEKLY_CENTS)}/semaine.` +
      (SUBSCRIPTION_WEEKS_DEDUCTED ? ` Et chaque semaine payée est déduite du prix de ton carnet.` : ""),
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
    if (SUBSCRIPTION_WEEKS_DEDUCTED && input.paidCents > 0) {
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
 * Une notification qui **se prolonge dans le fil du voyage** : MEMO y pose une
 * bulle qui reprend ses mots, pour qu'en touchant la notification on retrouve
 * dans la conversation ce qu'on vient de lire (Clara, 02/10/2026).
 *
 * Le fil est **commun** aux co-voyageurs (`ChatCopy.privacyNote`) : la bulle
 * est écrite pour tous ceux qui le lisent — l'auteur du récit compris —, la
 * notification pour celui qui la reçoit.
 */
export interface ThreadedNotificationText extends NotificationText {
  chat: string;
}

/** « un souvenir », « 3 photos ». */
function countOf(count: number, noun: "souvenir" | "photo"): string {
  if (count === 1) return noun === "photo" ? "une photo" : "un souvenir";
  return `${count} ${noun}s`;
}

/** « 2 souvenirs et 5 photos », « un souvenir », « une photo ». */
function captureOf(stories: number, photos: number): string {
  if (stories > 0 && photos > 0) return `${countOf(stories, "souvenir")} et ${countOf(photos, "photo")}`;
  return stories > 0 ? countOf(stories, "souvenir") : countOf(photos, "photo");
}

/** « capturés », accordé à ce qu'il qualifie — le masculin l'emporte. */
function capturedOf(stories: number, photos: number): string {
  const plural = stories + photos > 1 ? "s" : "";
  return stories > 0 ? `capturé${plural}` : `capturée${plural}`;
}

/** « Clara », « Clara et Paul », « Clara et 2 autres co-voyageurs ». */
function authorsOf(names: string[]): { who: string; plural: boolean } {
  const known = names.map((name) => name.trim()).filter(Boolean);
  if (known.length === 0) return { who: "Un co-voyageur", plural: false };
  if (known.length === 1) return { who: known[0]!, plural: false };
  if (known.length === 2) return { who: `${known[0]} et ${known[1]}`, plural: true };
  return { who: `${known[0]} et ${known.length - 1} autres co-voyageurs`, plural: true };
}

/** « à Rome », sinon « dans « Notre tour du monde » ». */
function inPlace(trip: { city: string | null; title: string }): string {
  return trip.city?.trim() ? `à ${trip.city.trim()}` : `dans « ${trip.title.trim()} »`;
}

function upperFirst(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * **Nouveau récit** — un co-voyageur a alimenté le carnet. `names` : les
 * prénoms de ceux qui ont raconté depuis la dernière fois, sans le
 * destinataire.
 */
export function newStoryText(input: {
  trip: { city: string | null; title: string };
  names: string[];
  stories: number;
  photos: number;
}): ThreadedNotificationText {
  const { who, plural } = authorsOf(input.names);
  const added = `${who} ${plural ? "ont" : "a"} ajouté ${captureOf(input.stories, input.photos)}`;
  return {
    title: `Nouveau récit ${inPlace(input.trip)}`,
    body: `${added} au carnet. Viens voir, et raconte la suite à ton tour.`,
    chat: `Nouveau récit dans le carnet : ${added}. Qui raconte la suite ?`,
  };
}

/**
 * **Résumé hebdomadaire** — le point sur ce que le voyage a capturé en sept
 * jours, tous les co-voyageurs confondus. `shared` : un voyage à plusieurs,
 * dont le carnet est « votre » carnet.
 */
export function weeklyDigestText(input: {
  trip: { city: string | null; title: string };
  stories: number;
  photos: number;
  shared: boolean;
}): ThreadedNotificationText {
  const captured = `${captureOf(input.stories, input.photos)} ${capturedOf(input.stories, input.photos)} cette semaine`;
  return {
    title: `Le point de la semaine ${inPlace(input.trip)}`,
    body: `${upperFirst(captured)}. ${input.shared ? "Votre" : "Ton"} carnet prend forme : viens voir où il en est.`,
    chat: `Le point de la semaine : ${captured}. Le carnet prend forme ! On continue ?`,
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

/** **Vacances scolaires** — J-7 et le jour J. */
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
