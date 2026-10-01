import type { NotificationKind } from "@prisma/client";
import {
  birthdayText,
  learnedPeriodText,
  schoolHolidaysText,
  trialEndText,
  tripEndText,
  unorderedBookText,
  writingReminderText,
  type NotificationText,
  type SubscriptionAtTripEnd,
} from "./notificationCopy.js";
import { addDays, daysBetween, sameDayInYear, yearOf, type LocalDate } from "./localCalendar.js";
import { reminderIntervalDays, rhythmOf, type Rhythm, type RhythmTier } from "./notificationRhythm.js";
import type { SchoolHolidayPeriod, SchoolZone } from "./schoolHolidays.js";

/**
 * **Quoi envoyer, à qui, quel jour** — la feuille « Notifications » traduite
 * en règles. Voir `docs/notifications.md`.
 *
 * Tout est **pur** ici : on reçoit l'état d'un compte et la date du jour chez
 * lui, on rend des notifications. Pas de base, pas d'horloge, pas d'Apple —
 * c'est ce qui permet de tester chaque règle avec trois lignes de données, et
 * c'est `notifications.ts` qui charge, envoie et journalise.
 *
 * Deux temps :
 *
 * 1. `planNotifications` — les **candidates** : tout ce que les règles
 *    déclenchent aujourd'hui, filtré par le palier du voyageur.
 * 2. `selectNotifications` — les **règles anti-saturation** : ce qui part
 *    vraiment, à cette heure-ci, compte tenu de ce qui est déjà parti.
 */

/** Les trois familles de la feuille. */
export type NotificationFamily = "billing" | "engagement" | "holiday";

export const FAMILY_OF: Record<NotificationKind, NotificationFamily> = {
  trial_end: "billing",
  trip_end: "billing",
  writing_reminder: "engagement",
  unordered_book: "engagement",
  school_holidays: "holiday",
  learned_period: "holiday",
  birthday: "holiday",
};

/**
 * Ce que chaque palier reçoit. **L'essentiel pour tous** — fin d'essai, fin
 * de voyage —, les relances d'écriture dès le rythme modéré, et le reste au
 * rythme soutenu. Voir `notificationRhythm.ts` pour les paliers.
 */
const TIER_ALLOWS: Record<RhythmTier, ReadonlySet<NotificationKind>> = {
  light: new Set(["trial_end", "trip_end"]),
  moderate: new Set(["trial_end", "trip_end", "writing_reminder"]),
  sustained: new Set([
    "trial_end",
    "trip_end",
    "writing_reminder",
    "unordered_book",
    "school_holidays",
    "learned_period",
    "birthday",
  ]),
};

/**
 * Quand départager deux candidates du même jour, la plus pertinente gagne.
 * La facturation d'abord, toujours (feuille, § 3). Puis ce qui touche un
 * voyage réel — un carnet qui se tait, un carnet pas commandé —, puis les
 * signaux personnels avant le calendrier de tout le monde : l'an dernier à
 * la même époque dit plus qu'un anniversaire, qui dit plus que les vacances
 * scolaires d'une zone entière.
 */
const PRIORITY: Record<NotificationKind, number> = {
  trip_end: 100,
  trial_end: 90,
  writing_reminder: 50,
  unordered_book: 40,
  learned_period: 30,
  birthday: 20,
  school_holidays: 10,
};

/**
 * L'heure, chez le voyageur, à partir de laquelle une notification peut
 * partir. 10 h pour tout, sauf la relance d'écriture : elle part le soir,
 * quand on a sa journée à raconter (« Une entrée chaque soir »).
 */
const EARLIEST_HOUR: Record<NotificationKind, number> = {
  trial_end: 10,
  trip_end: 10,
  writing_reminder: 19,
  unordered_book: 10,
  school_holidays: 10,
  learned_period: 10,
  birthday: 10,
};

/** Rien ne part après 21 h chez le voyageur : ce qui n'est pas parti attend demain. */
export const LATEST_HOUR = 21;

/** La première heure où quoi que ce soit peut partir — la tâche saute les comptes avant. */
export const FIRST_SENDING_HOUR = Math.min(...Object.values(EARLIEST_HOUR));

/** « Fin des 3 jours offerts » : envoyée à J+3 du premier voyage. */
const TRIAL_LENGTH_DAYS = 3;

/** Au plus trois relances d'écriture d'affilée sur un même silence. */
const MAX_REMINDERS_PER_SILENCE = 3;

/** Le carnet pas commandé : trois jours après la fin, puis dix. */
const UNORDERED_BOOK_DAYS = [3, 10] as const;

/** Vacances scolaires : une semaine avant, trois jours avant, le jour même. */
const SCHOOL_HOLIDAY_DAYS_BEFORE = [7, 3, 0] as const;

/** Comportement appris : quinze jours avant le retour de la période. */
const LEARNED_PERIOD_DAYS_BEFORE = 14;

/** Anniversaire : une semaine avant. */
const BIRTHDAY_DAYS_BEFORE = 7;

/** « Jamais plus d'une notification vacances par semaine. » */
const HOLIDAY_COOLDOWN_DAYS = 7;

// ---------------------------------------------------------------------------
// Ce que le planificateur reçoit
// ---------------------------------------------------------------------------

export interface PlannerTrip {
  id: string;
  title: string;
  city: string | null;
  /** Les dates du voyage, dans le calendrier du voyageur. */
  startsOn: LocalDate | null;
  endsOn: LocalDate | null;
  createdOn: LocalDate;
  /** `memos.stage`, le repli d'un voyage qui n'a aucune date. */
  storedStage: "upcoming" | "ongoing" | "past";
  narrationPace: string | null;
  notificationsEnabled: boolean;
  notifyWritingReminder: boolean;
  notifyTripEnd: boolean;
  /** La relance écrite d'après le récit — « Comment ça se passe à Trastevere ? ». */
  prompt: string | null;
  /** Combien de souvenirs racontés (photos à part). */
  storyCount: number;
  /** Le dernier jour où quelqu'un a raconté quelque chose dans ce voyage. */
  lastStoryOn: LocalDate | null;
  isOwner: boolean;
  /** Une commande d'impression partie (ni brouillon, ni annulée). */
  hasOrder: boolean;
  /** Ce que **ce voyageur** a payé d'abonnement pour ce voyage, en centimes. */
  paidCents: number;
  /** Le prix estimé du carnet, en centimes. */
  estimateCents: number;
}

export interface PlannerDelivery {
  kind: NotificationKind;
  dedupeKey: string;
  sentOn: LocalDate;
  opened: boolean;
}

export interface PlannerAccount {
  id: string;
  birthDate: LocalDate | null;
  schoolZone: SchoolZone | null;
  /** Les étapes offertes qui restent ; `null` pour un compte sans quota. */
  remainingSteps: number | null;
  /** Un abonnement vivant, ou résilié dont la semaine payée court encore. */
  isSubscribed: boolean;
  /** Un abonnement App Store vivant dont le renouvellement est armé. */
  renewsAtApple: boolean;
  /** Un abonnement vivant hors App Store — le serveur l'arrête seul. */
  stopsAutomatically: boolean;
  /** A-t-il écrit à MEMO ces quatorze derniers jours ? */
  usedRecently: boolean;
  /** Ses voyages : ceux qu'il possède et ceux où il est co-voyageur. */
  trips: PlannerTrip[];
  /** Ce qu'on lui a envoyé ces soixante derniers jours. */
  deliveries: PlannerDelivery[];
}

export interface PlannedNotification extends NotificationText {
  kind: NotificationKind;
  family: NotificationFamily;
  /** Unique pour tout le serveur : « une seule fois » se lit ici. */
  dedupeKey: string;
  memoId: string | null;
  /** Le lien `memobook://` que l'app ouvre au toucher. */
  link: string;
  priority: number;
  earliestHour: number;
}

// ---------------------------------------------------------------------------
// Les liens — au chemin près de `NotificationLink` côté iOS
// ---------------------------------------------------------------------------

export const NOTIFICATION_LINKS = {
  paywall: "memobook://paywall",
  newTrip: "memobook://trips/new",
  chat: (tripId: string) => `memobook://trips/${tripId}/chat`,
  wallet: (tripId: string) => `memobook://trips/${tripId}/wallet`,
  bookPreview: (tripId: string) => `memobook://trips/${tripId}/preview`,
} as const;

// ---------------------------------------------------------------------------
// Où en est un voyage, aujourd'hui
// ---------------------------------------------------------------------------

function hasNoDates(trip: PlannerTrip): boolean {
  return trip.startsOn === null && trip.endsOn === null;
}

function isOngoing(trip: PlannerTrip, today: LocalDate): boolean {
  if (hasNoDates(trip)) return trip.storedStage === "ongoing";
  return (trip.startsOn === null || trip.startsOn <= today) && (trip.endsOn === null || trip.endsOn >= today);
}

function isPast(trip: PlannerTrip, today: LocalDate): boolean {
  if (hasNoDates(trip)) return trip.storedStage === "past";
  return trip.endsOn !== null && trip.endsOn < today;
}

/**
 * Le voyageur a-t-il déjà un voyage pendant cette période ? Les vacances,
 * l'anniversaire, la période de l'an dernier : inutile de suggérer un voyage
 * à quelqu'un qui en a déjà un sur ces dates. Un voyage en cours sans date de
 * retour couvre tout ce qui vient : on ne sait pas quand il rentre.
 */
function hasTripDuring(trips: PlannerTrip[], from: LocalDate, to: LocalDate, today: LocalDate): boolean {
  return trips.some((trip) => {
    const start = trip.startsOn ?? (isOngoing(trip, today) ? today : null);
    if (start === null) return false;
    const end = trip.endsOn ?? "9999-12-31";
    return start <= to && end >= from;
  });
}

// ---------------------------------------------------------------------------
// Les candidates
// ---------------------------------------------------------------------------

/**
 * Le rythme du compte : celui que déclare son voyage **le plus récent** — la
 * question est posée à chaque création, la dernière réponse est la plus
 * juste.
 */
export function accountRhythm(account: PlannerAccount): Rhythm {
  const latest = [...account.trips].sort((a, b) => b.createdOn.localeCompare(a.createdOn))[0];
  return rhythmFor(account, latest?.narrationPace ?? null);
}

function rhythmFor(account: PlannerAccount, declaredPace: string | null): Rhythm {
  return rhythmOf({
    declaredPace,
    deliveredCount: account.deliveries.length,
    openedCount: account.deliveries.filter((delivery) => delivery.opened).length,
    usedRecently: account.usedRecently,
  });
}

function planned(
  account: PlannerAccount,
  kind: NotificationKind,
  key: string,
  memoId: string | null,
  link: string,
  text: NotificationText,
  priorityBonus = 0,
): PlannedNotification {
  return {
    kind,
    family: FAMILY_OF[kind],
    // Le compte en tête : deux co-voyageurs reçoivent chacun la fin du voyage.
    dedupeKey: `${account.id}:${kind}:${key}`,
    memoId,
    link,
    priority: PRIORITY[kind] + priorityBonus,
    earliestHour: EARLIEST_HOUR[kind],
    ...text,
  };
}

/**
 * Tout ce que les règles déclenchent aujourd'hui pour ce compte — avant les
 * plafonds. `today` est la date **chez le voyageur**.
 */
export function planNotifications(
  account: PlannerAccount,
  holidays: SchoolHolidayPeriod[],
  today: LocalDate,
): PlannedNotification[] {
  const candidates: PlannedNotification[] = [];
  const accountTier = accountRhythm(account).tier;
  const allowed = (kind: NotificationKind, tier: RhythmTier = accountTier) => TIER_ALLOWS[tier].has(kind);

  // --- Facturation ---------------------------------------------------------

  // Fin des 3 jours offerts : J+3 du premier voyage créé. Pas pour un abonné,
  // ni pour un compte sans quota (`remainingSteps` nul) : il n'a pas d'essai.
  const ownedCreations = account.trips.filter((trip) => trip.isOwner).map((trip) => trip.createdOn).sort();
  const trialStartedOn = ownedCreations[0];
  if (
    trialStartedOn &&
    !account.isSubscribed &&
    account.remainingSteps !== null &&
    addDays(trialStartedOn, TRIAL_LENGTH_DAYS) === today
  ) {
    candidates.push(planned(account, "trial_end", "once", null, NOTIFICATION_LINKS.paywall, trialEndText()));
  }

  for (const trip of account.trips) {
    // Fin du voyage : le jour de la date de fin renseignée.
    if (trip.endsOn !== today || !trip.notificationsEnabled || !trip.notifyTripEnd) continue;

    // L'abonnement ne s'arrête que s'il n'y a plus d'autre voyage à venir ou
    // en cours — la règle même de `countRunningTrips` (`subscriptions.ts`) :
    // sinon il sert encore, et on n'en dit rien.
    const otherTripRunning = account.trips.some(
      (other) => other.id !== trip.id && (other.endsOn === null || other.endsOn > today),
    );
    const subscription: SubscriptionAtTripEnd = otherTripRunning
      ? "none"
      : account.renewsAtApple
        ? "renews_at_apple"
        : account.stopsAutomatically
          ? "stops_automatically"
          : "none";

    // Un voyage où rien n'a été raconté et sans abonnement à couper : il n'y
    // a rien à dire, ni commande à proposer.
    if (trip.storyCount === 0 && subscription === "none") continue;

    candidates.push(
      planned(
        account,
        "trip_end",
        trip.id,
        trip.id,
        NOTIFICATION_LINKS.wallet(trip.id),
        tripEndText({
          trip,
          subscription,
          paidCents: trip.paidCents,
          estimateCents: trip.estimateCents,
          hasStories: trip.storyCount > 0,
        }),
      ),
    );
  }

  // --- Rythme : les carnets qui se taisent ---------------------------------

  for (const trip of account.trips) {
    if (!isOngoing(trip, today) || !trip.notificationsEnabled || !trip.notifyWritingReminder) continue;

    // Le rythme de **ce** voyage : c'est pour lui qu'on a répondu à la question.
    const rhythm = rhythmFor(account, trip.narrationPace);
    if (!allowed("writing_reminder", rhythm.tier)) continue;

    // Le silence court depuis le dernier récit, ou depuis le départ pour un
    // carnet encore vide — « commencé », c'est d'abord parti.
    const startedOn = trip.startsOn ?? trip.createdOn;
    const lastActivity = trip.lastStoryOn && trip.lastStoryOn > startedOn ? trip.lastStoryOn : startedOn;
    const silence = daysBetween(lastActivity, today);
    const interval = reminderIntervalDays(trip.narrationPace, rhythm.openRate);
    const rank = Math.floor(silence / interval);
    if (rank < 1 || rank > MAX_REMINDERS_PER_SILENCE) continue;

    candidates.push(
      planned(
        account,
        "writing_reminder",
        `${trip.id}:${lastActivity}:${rank}`,
        trip.id,
        NOTIFICATION_LINKS.chat(trip.id),
        writingReminderText({ trip, prompt: trip.prompt, hasStories: trip.storyCount > 0 }),
      ),
    );
  }

  if (allowed("unordered_book")) {
    for (const trip of account.trips) {
      // Le propriétaire seulement : c'est lui qu'on invite à commander.
      if (!trip.isOwner || !isPast(trip, today) || trip.endsOn === null) continue;
      if (trip.storyCount === 0 || trip.hasOrder) continue;
      if (!trip.notificationsEnabled || !trip.notifyTripEnd) continue;

      const sinceEnd = daysBetween(trip.endsOn, today);
      // Une fenêtre d'une semaine par relance, et non le seul jour : une
      // passe manquée ne la perd pas. Au-delà de la dernière, plus rien.
      const step = [...UNORDERED_BOOK_DAYS].reverse().find((day) => sinceEnd >= day && sinceEnd < day + 7);
      if (step === undefined) continue;

      candidates.push(
        planned(
          account,
          "unordered_book",
          `${trip.id}:${step}`,
          trip.id,
          NOTIFICATION_LINKS.bookPreview(trip.id),
          unorderedBookText(trip),
        ),
      );
    }
  }

  // --- Vacances -----------------------------------------------------------

  if (allowed("school_holidays") && account.schoolZone) {
    for (const period of holidays) {
      if (period.zone !== account.schoolZone) continue;
      const daysBefore = SCHOOL_HOLIDAY_DAYS_BEFORE.find((days) => addDays(period.startsOn, -days) === today);
      if (daysBefore === undefined) continue;
      if (hasTripDuring(account.trips, period.startsOn, addDays(period.endsOn, -1), today)) continue;

      candidates.push(
        planned(
          account,
          "school_holidays",
          `${period.zone}:${period.schoolYear}:${period.label}:J-${daysBefore}`,
          null,
          NOTIFICATION_LINKS.newTrip,
          schoolHolidaysText(period.label, daysBefore),
          // Le jour J l'emporte sur J-3, qui l'emporte sur J-7.
          7 - daysBefore,
        ),
      );
    }
  }

  if (allowed("learned_period")) {
    // Le seuil d'historique tranché par la feuille : **un voyage** suffit.
    const thisYear = yearOf(today);
    const matches = account.trips
      .filter((trip) => trip.startsOn !== null)
      .flatMap((trip) =>
        [thisYear, thisYear + 1].map((year) => ({ trip, year, anniversary: sameDayInYear(trip.startsOn!, year) })),
      )
      .filter(({ trip, year, anniversary }) =>
        yearOf(trip.startsOn!) < year && addDays(anniversary, -LEARNED_PERIOD_DAYS_BEFORE) === today,
      )
      // L'année la plus proche d'abord : « l'an dernier » plutôt qu'« il y a 3 ans ».
      .sort((a, b) => yearOf(b.trip.startsOn!) - yearOf(a.trip.startsOn!));

    const match = matches[0];
    if (match) {
      const length = match.trip.endsOn ? Math.max(0, daysBetween(match.trip.startsOn!, match.trip.endsOn)) : 0;
      if (!hasTripDuring(account.trips, match.anniversary, addDays(match.anniversary, length), today)) {
        candidates.push(
          planned(
            account,
            "learned_period",
            match.anniversary,
            null,
            NOTIFICATION_LINKS.newTrip,
            learnedPeriodText({ trip: match.trip, yearsAgo: match.year - yearOf(match.trip.startsOn!) }),
          ),
        );
      }
    }
  }

  if (allowed("birthday") && account.birthDate) {
    const thisYear = yearOf(today);
    for (const year of [thisYear, thisYear + 1]) {
      const birthday = sameDayInYear(account.birthDate, year);
      if (addDays(birthday, -BIRTHDAY_DAYS_BEFORE) !== today) continue;
      // Pas de cumul avec un voyage déjà en cours (feuille, § 2), ni avec un
      // voyage déjà prévu pour l'anniversaire.
      if (account.trips.some((trip) => isOngoing(trip, today))) continue;
      if (hasTripDuring(account.trips, birthday, birthday, today)) continue;

      candidates.push(
        planned(account, "birthday", String(year), null, NOTIFICATION_LINKS.newTrip, birthdayText()),
      );
    }
  }

  return candidates;
}

// ---------------------------------------------------------------------------
// Les règles anti-saturation
// ---------------------------------------------------------------------------

/**
 * Ce qui part **maintenant**, parmi les candidates du jour.
 *
 * - **La facturation passe toujours**, et un jour où elle parle, rien d'autre
 *   ne part : elle reste prioritaire sur tout (feuille, § 3).
 * - **Une seule autre notification par jour**, la plus pertinente — c'est ce
 *   qui règle les déclencheurs simultanés (anniversaire et vacances la même
 *   semaine : une seule part).
 * - **Jamais plus d'une notification vacances sur sept jours glissants**, quel
 *   que soit le rythme. ⚠️ Conséquence à connaître : J-3 tombe toujours à
 *   quatre jours de J-7, donc **J-3 ne part que si J-7 n'est pas parti** —
 *   sur une même période, J-7 puis le jour J. La feuille demande les trois
 *   *et* ce plafond ; c'est le plafond qui l'emporte, voir
 *   `docs/notifications.md` § Points ouverts.
 * - Rien avant l'heure de la notification (10 h, 19 h pour la relance
 *   d'écriture), rien après 21 h, chez le voyageur.
 *
 * `hour` est l'heure chez le voyageur ; `deliveries`, ce qui est déjà parti.
 */
export function selectNotifications(
  candidates: PlannedNotification[],
  deliveries: PlannerDelivery[],
  today: LocalDate,
  hour: number,
): PlannedNotification[] {
  if (hour >= LATEST_HOUR) return [];

  const alreadySent = new Set(deliveries.map((delivery) => delivery.dedupeKey));
  const due = candidates.filter(
    (candidate) => hour >= candidate.earliestHour && !alreadySent.has(candidate.dedupeKey),
  );

  const sentToday = deliveries.filter((delivery) => delivery.sentOn === today);
  const billing = due.filter((candidate) => candidate.family === "billing");
  const billingDay = billing.length > 0 || sentToday.some((delivery) => FAMILY_OF[delivery.kind] === "billing");
  if (billingDay) return billing;

  if (sentToday.length > 0) return [];

  const holidayCooling = deliveries.some(
    (delivery) =>
      FAMILY_OF[delivery.kind] === "holiday" && daysBetween(delivery.sentOn, today) < HOLIDAY_COOLDOWN_DAYS,
  );

  const best = due
    .filter((candidate) => candidate.family !== "holiday" || !holidayCooling)
    .sort((a, b) => b.priority - a.priority)[0];

  return best ? [best] : [];
}
