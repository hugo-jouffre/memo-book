import type { NotificationKind } from "@prisma/client";
import {
  birthdayText,
  learnedPeriodText,
  newStoryText,
  renewalReminderText,
  schoolHolidaysText,
  tripEndText,
  unorderedBookText,
  weeklyDigestText,
  writingReminderText,
  type NotificationText,
  type ThreadedNotificationText,
} from "./notificationCopy.js";
import { addDays, daysBetween, sameDayInYear, yearOf, type LocalDate } from "./localCalendar.js";
import { reminderIntervalDays, rhythmOf, type Rhythm, type RhythmTier } from "./notificationRhythm.js";
import { periodsOf, type SchoolCalendar, type SchoolHolidayPeriod } from "./schoolHolidays.js";

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

/**
 * Ce qui part **par APNs** : toutes les valeurs de `NotificationKind`, sauf
 * l'e-mail de fin de voyage. Lui n'emprunte que le journal
 * (`notification_deliveries`), pour son « une seule fois » ; il n'a ni heure
 * de notification, ni palier, ni place dans les plafonds — voir
 * `planTripEndEmail`.
 */
export type PushKind = Exclude<NotificationKind, "trip_end_email">;

export const FAMILY_OF: Record<PushKind, NotificationFamily> = {
  trip_end: "billing",
  renewal_reminder: "billing",
  writing_reminder: "engagement",
  unordered_book: "engagement",
  new_story: "engagement",
  weekly_digest: "engagement",
  school_holidays: "holiday",
  learned_period: "holiday",
  birthday: "holiday",
};

/**
 * Ce que chaque palier reçoit. **L'essentiel pour tous** — la fin du voyage
 * et le rappel avant le renouvellement de l'abonnement —, puis au rythme
 * modéré les relances d'écriture (moins souvent, `MAX_REMINDERS_PER_SILENCE`)
 * et le résumé de la semaine, et le reste au rythme soutenu. Voir
 * `notificationRhythm.ts` pour les paliers.
 *
 * « Nouveau récit » est au rythme soutenu seulement : il suit chaque récit
 * d'un co-voyageur, quand le résumé de la semaine en fait le point une fois
 * par semaine — c'est lui que reçoit le rythme modéré.
 */
const TIER_ALLOWS: Record<RhythmTier, ReadonlySet<PushKind>> = {
  light: new Set(["trip_end", "renewal_reminder"]),
  moderate: new Set(["trip_end", "renewal_reminder", "writing_reminder", "weekly_digest"]),
  sustained: new Set([
    "trip_end",
    "renewal_reminder",
    "writing_reminder",
    "new_story",
    "weekly_digest",
    "unordered_book",
    "school_holidays",
    "learned_period",
    "birthday",
  ]),
};

/**
 * Quand départager deux candidates du même jour, la plus pertinente gagne.
 * La facturation d'abord, toujours (feuille, § 3). Puis ce qui touche un
 * voyage réel — un co-voyageur qui vient de raconter, un carnet qui se tait,
 * le point de la semaine, un carnet pas commandé —, puis les
 * signaux personnels avant le calendrier de tout le monde : l'an dernier à
 * la même époque dit plus qu'un anniversaire, qui dit plus que les vacances
 * scolaires d'une zone entière.
 */
const PRIORITY: Record<PushKind, number> = {
  trip_end: 100,
  renewal_reminder: 90,
  new_story: 60,
  writing_reminder: 50,
  weekly_digest: 45,
  unordered_book: 40,
  learned_period: 30,
  birthday: 20,
  school_holidays: 10,
};

/**
 * L'heure, chez le voyageur, à partir de laquelle une notification peut
 * partir. 10 h pour tout, sauf la relance d'écriture : elle part le soir,
 * quand on a sa journée à raconter (« Une entrée chaque soir ») — et le point
 * de la semaine juste avant, en fin de journée.
 */
const EARLIEST_HOUR: Record<PushKind, number> = {
  trip_end: 10,
  renewal_reminder: 10,
  writing_reminder: 19,
  new_story: 10,
  weekly_digest: 18,
  unordered_book: 10,
  school_holidays: 10,
  learned_period: 10,
  birthday: 10,
};

/** Rien ne part après 21 h chez le voyageur : ce qui n'est pas parti attend demain. */
export const LATEST_HOUR = 21;

/** La première heure où quoi que ce soit peut partir — la tâche saute les comptes avant. */
export const FIRST_SENDING_HOUR = Math.min(...Object.values(EARLIEST_HOUR));

/**
 * Le rappel avant le renouvellement : **trois jours avant**, ou deux si la
 * passe de la veille l'a manqué. Jamais la veille : Apple demande de résilier
 * au moins vingt-quatre heures avant le renouvellement, et un rappel qui
 * arrive trop tard pour servir n'est qu'un reproche (Hugo, 03/10/2026).
 */
const RENEWAL_REMINDER_DAYS_BEFORE = [3, 2] as const;

/**
 * Le rappel avant le renouvellement se tait quand la fin d'un voyage vient
 * de le dire : « coupe-le en un geste » deux jours de suite, c'est insister.
 */
const RENEWAL_REMINDER_QUIET_AFTER_TRIP_END_DAYS = 3;

/**
 * Deux rappels avant le renouvellement sont espacés d'au moins ce nombre de
 * jours. Un abonnement mensuel n'en perd aucun — deux renouvellements sont à
 * vingt-huit jours au moins, vingt-sept quand le premier rappel a été
 * rattrapé à J-2 —, et l'ancien abonnement à la semaine, encore honoré, n'en
 * reçoit qu'un toutes les quatre semaines au lieu d'un chaque semaine, qui
 * ferait en plus taire toute autre notification ce jour-là (03/10/2026).
 */
const RENEWAL_REMINDER_MIN_GAP_DAYS = 25;

/**
 * L'e-mail de fin de voyage : le **lendemain** de la date de fin — le jour
 * même, la notification et l'accueil viennent de le dire —, ou dans les deux
 * jours qui suivent si la passe l'a manqué. Au-delà, il arriverait trop loin
 * du voyage pour qu'on comprenne pourquoi il arrive.
 */
const TRIP_END_EMAIL_DAYS_AFTER = { from: 1, to: 3 } as const;

/**
 * L'e-mail part aux heures des notifications : pas avant 10 h chez le
 * voyageur, rien après 21 h (`LATEST_HOUR`). Un rappel d'argent lu au réveil
 * ou à minuit se lit mal.
 */
export const TRIP_END_EMAIL_EARLIEST_HOUR = 10;

/**
 * Combien de relances d'écriture d'affilée sur un même silence. Le rythme
 * modéré en reçoit **moins**, pas aucune : il les a demandées en choisissant
 * un rythme (Clara, 02/10/2026). Une seule, à l'intervalle qu'il a choisi.
 */
const MAX_REMINDERS_PER_SILENCE: Record<RhythmTier, number> = { sustained: 3, moderate: 1, light: 0 };

/** Le carnet pas commandé : trois jours après la fin, puis dix. */
const UNORDERED_BOOK_DAYS = [3, 10] as const;

/**
 * Vacances scolaires : une semaine avant, puis le jour même (Clara,
 * 02/10/2026). Sept jours d'écart : c'est le plafond d'une notification
 * vacances par semaine, et rien ne tombe entre les deux.
 */
const SCHOOL_HOLIDAY_DAYS_BEFORE = [7, 0] as const;

/**
 * Le point de la semaine : tous les sept jours depuis le départ, dans une
 * fenêtre de trois jours — une passe manquée, ou un jour déjà pris par une
 * autre notification, ne le perd pas.
 */
const WEEKLY_DIGEST_EVERY_DAYS = 7;
const WEEKLY_DIGEST_WINDOW_DAYS = 3;

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
  notifyNewStory: boolean;
  notifyWeeklyDigest: boolean;
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
  /** Le prix estimé du carnet, en centimes. */
  estimateCents: number;
  /** Le propriétaire et les co-voyageurs actifs. */
  memberCount: number;
  /**
   * Ce que **les autres** ont raconté depuis la dernière notification
   * « Nouveau récit » de ce voyage — deux jours au plus. Nul s'il n'y a rien.
   */
  newFromOthers: NewFromOthers | null;
  /** Ce que le voyage a capturé ces sept derniers jours, tout le monde confondu. */
  weekStories: number;
  weekPhotos: number;
}

export interface NewFromOthers {
  /** Les prénoms de ceux qui ont raconté, dans l'ordre du fil. */
  names: string[];
  stories: number;
  photos: number;
  /** Le dernier message compté : la clé de la notification et de sa bulle. */
  latestMessageId: string;
}

export interface PlannerDelivery {
  kind: PushKind;
  dedupeKey: string;
  sentOn: LocalDate;
  opened: boolean;
}

export interface PlannerAccount {
  id: string;
  birthDate: LocalDate | null;
  /** La zone, ou les premières vacances tant qu'il n'a pas de code postal. */
  schoolCalendar: SchoolCalendar | null;
  /**
   * Un abonnement App Store vivant dont le renouvellement est armé — le seul
   * dont on parle : plus aucun abonnement ne s'arrête seul (03/10/2026).
   */
  renewsAtApple: boolean;
  /**
   * Le jour où cet abonnement se renouvelle, chez le voyageur — le plus proche
   * s'il en a deux. Nul sans abonnement armé, ou tant qu'Apple ne l'a pas dit.
   */
  renewsOn: LocalDate | null;
  /**
   * Une adresse où écrire. Sans elle — une entrée par Apple qui ne la
   * certifie pas —, l'e-mail de fin de voyage ne part pas (`sendTripEndEmails`
   * ne lit que les comptes qui en ont une), et rien ne doit compter dessus.
   */
  hasEmail: boolean;
  /** A-t-il écrit à MEMO ces quatorze derniers jours ? */
  usedRecently: boolean;
  /** Ses voyages : ceux qu'il possède et ceux où il est co-voyageur. */
  trips: PlannerTrip[];
  /** Ce qu'on lui a envoyé ces soixante derniers jours. */
  deliveries: PlannerDelivery[];
}

export interface PlannedNotification extends NotificationText {
  kind: PushKind;
  family: NotificationFamily;
  /** Unique pour tout le serveur : « une seule fois » se lit ici. */
  dedupeKey: string;
  memoId: string | null;
  /** Le lien `memobook://` que l'app ouvre au toucher. */
  link: string;
  priority: number;
  earliestHour: number;
  /**
   * La bulle que MEMO pose dans le fil du voyage quand la notification part.
   * `key` est **la même pour tous les destinataires** : le fil est commun, la
   * bulle ne s'y écrit qu'une fois.
   */
  chat?: { key: string; text: string };
}

// ---------------------------------------------------------------------------
// Les liens — au chemin près de `NotificationLink` côté iOS
// ---------------------------------------------------------------------------

export const NOTIFICATION_LINKS = {
  /** La feuille de l'abonnement, où il se coupe en un geste (03/10/2026). */
  subscription: "memobook://subscription",
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
 * Un voyage court encore ou s'annonce : l'abonnement sert, l'e-mail de fin de
 * voyage n'en dit rien. Un voyage sans date de fin court encore, sauf s'il
 * n'a aucune date et que son étape dit qu'il est passé.
 */
function hasTripStillRunning(trips: PlannerTrip[], today: LocalDate): boolean {
  return trips.some((trip) => (trip.endsOn === null ? !isPast(trip, today) : trip.endsOn >= today));
}

/**
 * Les jours où l'e-mail de fin de voyage part, est parti ou va partir : de la
 * fin d'un voyage à J+3 (`TRIP_END_EMAIL_DAYS_AFTER`), quand plus aucun voyage
 * ne court — les conditions de `planTripEndEmail`, sans l'heure ni le journal.
 * Jamais pour un compte sans adresse (03/10/2026) : l'e-mail n'y part pas, et
 * le rappel qui se tairait pour lui laisserait le voyageur sans rien.
 */
function tripEndEmailWindow(account: PlannerAccount, today: LocalDate): boolean {
  if (!account.hasEmail || !account.renewsAtApple || hasTripStillRunning(account.trips, today)) return false;
  return account.trips.some((trip) => {
    if (trip.endsOn === null) return false;
    const sinceEnd = daysBetween(trip.endsOn, today);
    return sinceEnd >= 0 && sinceEnd <= TRIP_END_EMAIL_DAYS_AFTER.to;
  });
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
  kind: PushKind,
  key: string,
  memoId: string | null,
  link: string,
  text: NotificationText | ThreadedNotificationText,
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
    title: text.title,
    body: text.body,
    // Sans le compte : une seule bulle pour tous ceux qui la reçoivent.
    ...("chat" in text ? { chat: { key: `${kind}:${key}`, text: text.chat } } : {}),
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
  const allowed = (kind: PushKind, tier: RhythmTier = accountTier) => TIER_ALLOWS[tier].has(kind);

  // --- Facturation ---------------------------------------------------------

  for (const trip of account.trips) {
    // Fin du voyage : le jour de la date de fin renseignée.
    if (trip.endsOn !== today || !trip.notificationsEnabled || !trip.notifyTripEnd) continue;

    // On ne parle de l'abonnement que s'il n'y a plus d'autre voyage à venir
    // ou en cours : sinon il sert encore, et on n'en dit rien.
    const otherTripRunning = account.trips.some(
      (other) => other.id !== trip.id && (other.endsOn === null || other.endsOn > today),
    );
    const renewal = !otherTripRunning && account.renewsAtApple ? { renewsOn: account.renewsOn } : null;

    // Un voyage où rien n'a été raconté et sans abonnement à couper : il n'y
    // a rien à dire, ni commande à proposer.
    if (trip.storyCount === 0 && renewal === null) continue;

    candidates.push(
      planned(
        account,
        "trip_end",
        trip.id,
        trip.id,
        NOTIFICATION_LINKS.wallet(trip.id),
        tripEndText({ trip, renewal, estimateCents: trip.estimateCents, hasStories: trip.storyCount > 0 }),
      ),
    );
  }

  // Avant le renouvellement : l'abonnement va repartir pour une période,
  // alors qu'aucun voyage ne court ni ne commence d'ici là — le jour du
  // renouvellement compris, puisqu'un voyage qui part ce jour-là s'en sert.
  // **Une fois par période** : la clé porte la date du renouvellement — et
  // jamais deux à moins de `RENEWAL_REMINDER_MIN_GAP_DAYS`.
  if (account.renewsAtApple && account.renewsOn) {
    const daysBefore = daysBetween(today, account.renewsOn);
    const tripEndJustSaidIt =
      account.deliveries.some(
        (delivery) =>
          delivery.kind === "trip_end" && daysBetween(delivery.sentOn, today) < RENEWAL_REMINDER_QUIET_AFTER_TRIP_END_DAYS,
      ) ||
      // L'e-mail de fin de voyage n'est pas dans `deliveries` (il fausserait
      // le taux d'ouverture et les plafonds) : on le lit sur la date de fin.
      // Il dit la même chose que ce rappel, du lendemain de la fin à J+3, et
      // il part même quand « Rappel de fin de voyage » est coupé — le rappel
      // se tait donc dans ces jours-là, notification de fin partie ou non.
      // Seulement s'il part vraiment : un compte sans adresse garde son rappel.
      tripEndEmailWindow(account, today);
    const remindedRecently = account.deliveries.some(
      (delivery) =>
        delivery.kind === "renewal_reminder" && daysBetween(delivery.sentOn, today) < RENEWAL_REMINDER_MIN_GAP_DAYS,
    );
    if (
      (RENEWAL_REMINDER_DAYS_BEFORE as readonly number[]).includes(daysBefore) &&
      !hasTripDuring(account.trips, today, account.renewsOn, today) &&
      !tripEndJustSaidIt &&
      !remindedRecently
    ) {
      candidates.push(
        planned(
          account,
          "renewal_reminder",
          account.renewsOn,
          null,
          NOTIFICATION_LINKS.subscription,
          renewalReminderText({ renewsOn: account.renewsOn, daysBefore }),
        ),
      );
    }
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
    if (rank < 1 || rank > MAX_REMINDERS_PER_SILENCE[rhythm.tier]) continue;

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

  // --- Rythme : ce que le voyage raconte --------------------------------------

  for (const trip of account.trips) {
    if (!trip.notificationsEnabled) continue;
    const rhythm = rhythmFor(account, trip.narrationPace);

    // Nouveau récit : un co-voyageur a alimenté le carnet. Le voyage peut
    // être fini — on raconte aussi en rentrant.
    const news = trip.newFromOthers;
    if (news && trip.notifyNewStory && allowed("new_story", rhythm.tier)) {
      const notification = planned(
        account,
        "new_story",
        `${trip.id}:${news.latestMessageId}`,
        trip.id,
        NOTIFICATION_LINKS.chat(trip.id),
        newStoryText({ trip, names: news.names, stories: news.stories, photos: news.photos }),
      );
      // **Une bulle par voyage et par jour.** Chaque membre a ses « autres » —
      // Clara est prévenue du récit de Paul, Paul de celui de Clara : des
      // clés par récit poseraient deux bulles à dix minutes d'écart dans un
      // fil que tous lisent. La première notification du jour écrit la bulle.
      candidates.push({
        ...notification,
        chat: notification.chat && { ...notification.chat, key: `new_story:${trip.id}:${today}` },
      });
    }

    // Le point de la semaine : tous les sept jours depuis le départ, tant
    // que le voyage est en cours et que la semaine a capturé quelque chose.
    if (!trip.notifyWeeklyDigest || !allowed("weekly_digest", rhythm.tier) || !isOngoing(trip, today)) continue;
    if (trip.weekStories + trip.weekPhotos === 0) continue;
    const sinceStart = daysBetween(trip.startsOn ?? trip.createdOn, today);
    const week = Math.floor(sinceStart / WEEKLY_DIGEST_EVERY_DAYS);
    if (week < 1 || sinceStart % WEEKLY_DIGEST_EVERY_DAYS >= WEEKLY_DIGEST_WINDOW_DAYS) continue;

    candidates.push(
      planned(
        account,
        "weekly_digest",
        `${trip.id}:week-${week}`,
        trip.id,
        NOTIFICATION_LINKS.chat(trip.id),
        weeklyDigestText({
          trip,
          stories: trip.weekStories,
          photos: trip.weekPhotos,
          shared: trip.memberCount > 1,
        }),
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

  if (allowed("school_holidays") && account.schoolCalendar) {
    for (const period of periodsOf(account.schoolCalendar, holidays)) {
      const daysBefore = SCHOOL_HOLIDAY_DAYS_BEFORE.find((days) => addDays(period.startsOn, -days) === today);
      if (daysBefore === undefined) continue;
      if (hasTripDuring(account.trips, period.startsOn, addDays(period.endsOn, -1), today)) continue;

      candidates.push(
        planned(
          account,
          "school_holidays",
          // Sans la zone : qui donne son code postal entre J-7 et le jour J ne
          // reçoit pas une seconde fois J-7, à la date de sa vraie zone.
          `${period.schoolYear}:${period.label}:J-${daysBefore}`,
          null,
          NOTIFICATION_LINKS.newTrip,
          schoolHolidaysText(period.label, daysBefore),
          // Le jour J l'emporte sur J-7.
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
// L'e-mail de fin de voyage
// ---------------------------------------------------------------------------

/** L'e-mail de fin de voyage qu'un compte doit recevoir aujourd'hui. */
export interface PlannedTripEndEmail {
  kind: "trip_end_email";
  /** Une fois par voyage, dans le même journal que les notifications. */
  dedupeKey: string;
  trip: PlannerTrip;
}

/**
 * **L'e-mail de fin de voyage** (Hugo, 03/10/2026) — le rappel de couper
 * l'abonnement, pour qui ne lit pas les notifications.
 *
 * C'est la promesse du paywall, « On te rappelle de résilier » : une
 * notification refusée ne doit pas la rompre. Il part donc aussi aux comptes
 * **sans** téléphone enregistré, et ne dépend ni des alertes du voyage ni du
 * rythme du récit — ce n'est pas une relance, c'est l'argent du voyageur.
 *
 * Le lendemain de la fin d'un voyage (jusqu'à J+3), à un compte dont
 * l'abonnement App Store va se renouveler, quand plus aucun voyage ne court
 * ni ne s'annonce — sinon l'abonnement sert encore, et on n'en dit rien,
 * comme la notification du jour de la fin. S'il y en a deux, le voyage fini
 * le plus récemment : un e-mail par jour suffit à le dire.
 *
 * `today` et `hour` sont ceux du voyageur. « Une seule fois », c'est la clé
 * unique du journal qui le tient (`sendTripEndEmails`).
 */
export function planTripEndEmail(
  account: PlannerAccount,
  today: LocalDate,
  hour: number,
): PlannedTripEndEmail | null {
  if (hour < TRIP_END_EMAIL_EARLIEST_HOUR || hour >= LATEST_HOUR) return null;
  if (!account.hasEmail || !account.renewsAtApple) return null;
  if (hasTripStillRunning(account.trips, today)) return null;

  const justEnded = account.trips
    .filter((trip) => {
      if (trip.endsOn === null) return false;
      const sinceEnd = daysBetween(trip.endsOn, today);
      return sinceEnd >= TRIP_END_EMAIL_DAYS_AFTER.from && sinceEnd <= TRIP_END_EMAIL_DAYS_AFTER.to;
    })
    .sort((a, b) => b.endsOn!.localeCompare(a.endsOn!))[0];
  if (!justEnded) return null;

  return {
    kind: "trip_end_email",
    dedupeKey: `${account.id}:trip_end_email:${justEnded.id}`,
    trip: justEnded,
  };
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
 *   que soit le rythme. C'est ce plafond qui a fait renoncer à J-3, qui
 *   tombait à quatre jours de J-7 : les vacances s'annoncent à J-7 puis le
 *   jour J, sept jours plus tard (Clara, 02/10/2026).
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
