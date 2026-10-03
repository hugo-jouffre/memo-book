import { Prisma, type NotificationKind, type SubscriptionProvider, type SubscriptionStatus } from "@prisma/client";
import type { AppContext } from "../context.js";
import type { PushSender } from "./apns.js";
import {
  ensureOpening,
  findTurnInFlight,
  firstNameOf,
  lockThread,
  materializeEntriesWithoutMessages,
} from "./conversationThread.js";
import {
  calendarDate,
  DEFAULT_TIME_ZONE,
  isValidTimeZone,
  localDate,
  localHour,
} from "./localCalendar.js";
import { APPLE_SUBSCRIPTIONS_URL, type SubscriptionReminderMail } from "./mailer.js";
import { SUBSCRIPTION_REMINDER_SUBJECT } from "./mailTemplates.js";
import { visibleToAccount } from "./memoOwnership.js";
import {
  accountRhythm,
  FIRST_SENDING_HOUR,
  LATEST_HOUR,
  planNotifications,
  planTripEndEmail,
  selectNotifications,
  TRIP_END_EMAIL_EARLIEST_HOUR,
  type NewFromOthers,
  type PlannedNotification,
  type PlannedTripEndEmail,
  type PlannerAccount,
  type PlannerTrip,
  type PushKind,
} from "./notificationPlanner.js";
import { unitPriceCents } from "./printPricing.js";
import { schoolCalendarOf, type SchoolHolidayPeriod, type SchoolZone } from "./schoolHolidays.js";
import { LIVING_SUBSCRIPTION_STATUSES } from "./subscriptions.js";

/**
 * La passe d'envoi : **charger, décider, envoyer, retenir**. Appelée toutes
 * les heures par la tâche `sendNotifications`. Les règles elles-mêmes sont
 * dans `notificationPlanner.ts`, les mots dans `notificationCopy.ts`.
 *
 * Toutes les heures et non une fois par jour : « 10 h » n'arrive pas au même
 * moment à Paris et à Montréal. Chaque passe ne regarde que les comptes chez
 * qui il est entre 10 h et 21 h, et `dedupeKey` garantit qu'une notification
 * déjà partie ne repart pas à la passe suivante.
 *
 * La même tâche envoie aussi **l'e-mail de fin de voyage** (`sendTripEndEmails`,
 * 03/10/2026) : mêmes heures, même journal, mais ni APNs ni jeton — il est
 * fait pour ceux que les notifications n'atteignent pas.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** Ce qu'on relit de l'historique : les plafonds et le taux d'ouverture. */
const HISTORY_DAYS = 60;

/** « A raconté récemment » : quatorze jours. */
const RECENT_USE_DAYS = 14;

/**
 * « Nouveau récit » regarde deux jours en arrière, pas un : un récit du matin
 * un jour où une autre notification est déjà partie doit encore pouvoir
 * s'annoncer le lendemain.
 */
const NEW_STORY_LOOKBACK_DAYS = 2;

/** Le point de la semaine compte ce qui a été capturé sur sept jours. */
const WEEK_DAYS = 7;

/** Les statuts d'une commande vraiment partie — ni brouillon, ni annulée. */
const PLACED_ORDER = ["submitted", "in_production", "shipped"] as const;

/**
 * L'abonnement App Store qui **va se renouveler** : vivant
 * (`LIVING_SUBSCRIPTION_STATUSES`, la règle de `services/subscriptions.ts`),
 * chez Apple, renouvellement armé — `autoRenews` nul veut dire qu'Apple ne
 * l'a pas encore dit, et un abonnement vivant se renouvelle par défaut. Le
 * seul dont les notifications et l'e-mail de fin de voyage parlent : plus
 * aucun abonnement ne s'arrête seul (Hugo, 03/10/2026).
 *
 * Rend le prochain renouvellement encore à venir — le plus proche s'il y en a
 * deux, nul tant qu'Apple ne l'a pas daté —, ou `null` sans abonnement armé.
 */
export function armedAppleRenewal(
  subscriptions: ReadonlyArray<{
    provider: SubscriptionProvider;
    status: SubscriptionStatus;
    autoRenews: boolean | null;
    renewsAt: Date | null;
  }>,
  now: Date,
): { renewsAt: Date | null } | null {
  const armed = subscriptions.filter(
    (subscription) =>
      subscription.provider === "storekit" &&
      (LIVING_SUBSCRIPTION_STATUSES as readonly string[]).includes(subscription.status) &&
      subscription.autoRenews !== false,
  );
  if (armed.length === 0) return null;

  const upcoming = armed
    .map((subscription) => subscription.renewsAt)
    .filter((renewsAt): renewsAt is Date => renewsAt !== null && renewsAt > now)
    .sort((a, b) => a.getTime() - b.getTime());
  return { renewsAt: upcoming[0] ?? null };
}

/** Ce que le planificateur relit de l'historique : tout, sauf l'e-mail. */
function isPushKind(kind: NotificationKind): kind is PushKind {
  return kind !== "trip_end_email";
}

export interface NotificationRunReport {
  /** Les comptes chez qui c'était l'heure. */
  evaluated: number;
  /** Les notifications parties, au moins sur un téléphone. */
  sent: number;
}

export async function sendDueNotifications(
  context: AppContext,
  now: Date = new Date(),
): Promise<NotificationRunReport> {
  const report: NotificationRunReport = { evaluated: 0, sent: 0 };

  if (!context.push.enabled) {
    context.logger.warn(
      "Notifications non envoyées : APNs n'est pas configuré (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY).",
    );
    return report;
  }

  const holidays = await loadHolidays(context, now);

  // Les comptes qu'on peut joindre : au moins un téléphone, sur une session
  // encore ouverte.
  const accounts = await context.prisma.account.findMany({
    where: { pushTokens: { some: { session: { expiresAt: { gt: now } } } } },
    select: { id: true, timeZone: true },
  });

  try {
    for (const { id, timeZone } of accounts) {
      const zone = timeZone && isValidTimeZone(timeZone) ? timeZone : DEFAULT_TIME_ZONE;
      const hour = localHour(now, zone);
      if (hour < FIRST_SENDING_HOUR || hour >= LATEST_HOUR) continue;

      report.evaluated += 1;
      try {
        const today = localDate(now, zone);
        const account = await loadPlannerAccount(context, id, zone, now);
        const candidates = planNotifications(account, holidays, today);
        const chosen = selectNotifications(candidates, account.deliveries, today, hour);

        for (const notification of chosen) {
          if (await deliver(context, id, notification, now)) report.sent += 1;
        }

        if (chosen.length > 0) {
          context.logger.info(
            {
              accountId: id,
              rhythm: accountRhythm(account),
              sent: chosen.map((notification) => notification.kind),
              skipped: candidates
                .filter((candidate) => !chosen.includes(candidate))
                .map((candidate) => candidate.kind),
            },
            "Notifications envoyées.",
          );
        }
      } catch (cause) {
        // Un compte qui casse n'arrête pas la passe des autres.
        context.logger.error({ err: cause, accountId: id }, "Notifications : compte ignoré sur erreur.");
      }
    }
  } finally {
    await context.push.close();
  }

  return report;
}

/** Les vacances qui ne sont pas encore finies. */
async function loadHolidays(context: AppContext, now: Date): Promise<SchoolHolidayPeriod[]> {
  const rows = await context.prisma.schoolHoliday.findMany({
    where: { endsOn: { gte: new Date(now.getTime() - DAY_MS) } },
    orderBy: { startsOn: "asc" },
  });
  return rows.map((row) => ({
    zone: row.zone as SchoolZone,
    label: row.label,
    schoolYear: row.schoolYear,
    startsOn: calendarDate(row.startsOn),
    endsOn: calendarDate(row.endsOn),
  }));
}

/** Tout ce que le planificateur doit savoir d'un compte, dans son calendrier. */
export async function loadPlannerAccount(
  context: AppContext,
  accountId: string,
  timeZone: string,
  now: Date,
): Promise<PlannerAccount> {
  const { prisma } = context;
  const day = (instant: Date | null) => (instant ? localDate(instant, timeZone) : null);

  const account = await prisma.account.findUniqueOrThrow({
    where: { id: accountId },
    select: {
      email: true,
      birthDate: true,
      addressPostalCode: true,
      addressCountry: true,
      subscriptions: {
        select: { provider: true, status: true, autoRenews: true, renewsAt: true },
      },
    },
  });

  const memos = await prisma.memo.findMany({
    where: visibleToAccount(accountId),
    select: {
      id: true,
      title: true,
      destinationCity: true,
      startDate: true,
      endDate: true,
      stage: true,
      createdAt: true,
      narrationPace: true,
      notificationsEnabled: true,
      notifyWritingReminder: true,
      notifyNewStory: true,
      notifyWeeklyDigest: true,
      notifyTripEnd: true,
      prompt: true,
      targetPageCount: true,
      pageCount: true,
      ownerAccountId: true,
      _count: {
        select: {
          entries: { where: { kind: { not: "photo" } } },
          members: { where: { status: "active" } },
        },
      },
      orders: { where: { status: { in: [...PLACED_ORDER] } }, select: { id: true }, take: 1 },
    },
  });
  const memoIds = memos.map((memo) => memo.id);

  const [lastEntries, lastTurns, deliveries, recentTurns, othersTold, weekEntries] = await Promise.all([
    prisma.entry.groupBy({
      by: ["memoId"],
      where: { memoId: { in: memoIds }, kind: { not: "photo" } },
      _max: { createdAt: true },
    }),
    // Ce que le voyageur a dit à MEMO compte aussi : une précision, une photo
    // commentée — le carnet n'est pas à l'arrêt.
    prisma.chatMessage.groupBy({
      by: ["memoId"],
      where: { memoId: { in: memoIds }, author: "traveller" },
      _max: { createdAt: true },
    }),
    // Les notifications seulement : l'e-mail de fin de voyage partage le
    // journal, mais il ne s'ouvre pas dans l'app — compté ici, il ferait
    // baisser le taux d'ouverture, et sa journée bloquerait les autres
    // notifications comme une facturation.
    prisma.notificationDelivery.findMany({
      where: {
        accountId,
        kind: { not: "trip_end_email" },
        sentAt: { gte: new Date(now.getTime() - HISTORY_DAYS * DAY_MS) },
      },
      select: { kind: true, memoId: true, dedupeKey: true, sentAt: true, openedAt: true },
    }),
    prisma.chatMessage.count({
      where: {
        accountId,
        author: "traveller",
        createdAt: { gte: new Date(now.getTime() - RECENT_USE_DAYS * DAY_MS) },
      },
    }),
    // « Nouveau récit » : ce que **les autres** ont raconté — un souvenir que
    // la bulle rattache à son auteur, jamais une simple précision.
    prisma.chatMessage.findMany({
      where: {
        memoId: { in: memoIds },
        author: "traveller",
        disposition: "memory",
        AND: [{ accountId: { not: null } }, { accountId: { not: accountId } }],
        createdAt: { gt: new Date(now.getTime() - NEW_STORY_LOOKBACK_DAYS * DAY_MS) },
      },
      select: {
        id: true,
        memoId: true,
        kind: true,
        payload: true,
        createdAt: true,
        account: { select: { firstName: true, lastName: true } },
      },
      orderBy: { seq: "asc" },
    }),
    // Le point de la semaine : tout ce que le voyage a capturé en sept jours.
    prisma.entry.groupBy({
      by: ["memoId", "kind"],
      where: { memoId: { in: memoIds }, createdAt: { gte: new Date(now.getTime() - WEEK_DAYS * DAY_MS) } },
      _count: { _all: true },
    }),
  ]);

  const newFromOthers = (memoId: string): NewFromOthers | null => {
    // Depuis la dernière notification « Nouveau récit » de ce voyage : on
    // n'annonce pas deux fois le même souvenir.
    const lastSent = deliveries
      .filter((delivery) => delivery.kind === "new_story" && delivery.memoId === memoId)
      .reduce<Date | null>((latest, delivery) => (!latest || delivery.sentAt > latest ? delivery.sentAt : latest), null);
    const told = othersTold.filter(
      (message) => message.memoId === memoId && (!lastSent || message.createdAt > lastSent),
    );
    const latest = told.at(-1);
    if (!latest) return null;

    const names: string[] = [];
    let stories = 0;
    let photos = 0;
    for (const message of told) {
      const name = firstNameOf(message.account);
      if (name && !names.includes(name)) names.push(name);
      if (message.kind === "photos") photos += photoCountOf(message.payload);
      else stories += 1;
    }
    return { names, stories, photos, latestMessageId: latest.id };
  };

  const weekCount = (memoId: string, photosOnly: boolean): number =>
    weekEntries
      .filter((row) => row.memoId === memoId && (row.kind === "photo") === photosOnly)
      .reduce((sum, row) => sum + row._count._all, 0);

  const latest = (memoId: string): Date | null => {
    const entry = lastEntries.find((row) => row.memoId === memoId)?._max.createdAt ?? null;
    const turn = lastTurns.find((row) => row.memoId === memoId)?._max.createdAt ?? null;
    if (!entry) return turn;
    if (!turn) return entry;
    return entry > turn ? entry : turn;
  };

  const trips: PlannerTrip[] = memos.map((memo) => ({
    id: memo.id,
    title: memo.title,
    city: memo.destinationCity,
    startsOn: day(memo.startDate),
    endsOn: day(memo.endDate),
    createdOn: localDate(memo.createdAt, timeZone),
    storedStage: memo.stage,
    narrationPace: memo.narrationPace,
    notificationsEnabled: memo.notificationsEnabled,
    notifyWritingReminder: memo.notifyWritingReminder,
    notifyNewStory: memo.notifyNewStory,
    notifyWeeklyDigest: memo.notifyWeeklyDigest,
    notifyTripEnd: memo.notifyTripEnd,
    prompt: memo.prompt,
    storyCount: memo._count.entries,
    lastStoryOn: day(latest(memo.id)),
    isOwner: memo.ownerAccountId === accountId,
    hasOrder: memo.orders.length > 0,
    // La même estimation que la cagnotte (`serializeWalletEstimate`) : celle
    // que le toucher de la notification de fin de voyage va montrer.
    estimateCents: unitPriceCents(Math.max(memo.targetPageCount, memo.pageCount)),
    memberCount: 1 + memo._count.members,
    newFromOthers: newFromOthers(memo.id),
    weekStories: weekCount(memo.id, false),
    weekPhotos: weekCount(memo.id, true),
  }));

  const renewal = armedAppleRenewal(account.subscriptions, now);

  return {
    id: accountId,
    birthDate: account.birthDate ? calendarDate(account.birthDate) : null,
    schoolCalendar: schoolCalendarOf(account.addressPostalCode, account.addressCountry),
    renewsAtApple: renewal !== null,
    renewsOn: day(renewal?.renewsAt ?? null),
    // La même condition que `sendTripEndEmails` (`!row.email`) : une adresse vide n'en est pas une.
    hasEmail: Boolean(account.email),
    usedRecently: recentTurns > 0,
    trips,
    deliveries: deliveries.flatMap((delivery) =>
      isPushKind(delivery.kind)
        ? [
            {
              kind: delivery.kind,
              dedupeKey: delivery.dedupeKey,
              sentOn: localDate(delivery.sentAt, timeZone),
              opened: delivery.openedAt !== null,
            },
          ]
        : [],
    ),
  };
}

/** Une bulle de photos en rattache plusieurs (`payload.entryIds`), une seule sinon. */
function photoCountOf(payload: unknown): number {
  const ids = payload && typeof payload === "object" ? (payload as { entryIds?: unknown }).entryIds : undefined;
  return Array.isArray(ids) && ids.length > 0 ? ids.length : 1;
}

/**
 * Envoie une notification à tous les téléphones du compte, et la retient.
 *
 * La ligne s'écrit **avant** l'envoi : c'est elle qui réserve la clé. Si deux
 * passes se chevauchaient, la seconde se heurterait à la contrainte d'unicité
 * et n'enverrait rien. Elle est retirée si **aucun** téléphone ne l'a reçue
 * pour une raison passagère — réseau, Apple saturé —, pour que la passe
 * suivante la retente dans la journée. Un jeton mort, lui, est oublié.
 *
 * Rend `true` quand au moins un téléphone l'a reçue.
 */
async function deliver(
  context: AppContext,
  accountId: string,
  notification: PlannedNotification,
  now: Date,
): Promise<boolean> {
  const { prisma } = context;
  const push: PushSender = context.push;

  // Une notification qui écrit dans le fil attend que MEMO ait fini de
  // répondre : sa bulle ne doit pas tomber entre une question et sa réponse.
  // La passe suivante la reprend.
  if (notification.chat && notification.memoId && (await findTurnInFlight(prisma, notification.memoId, now))) {
    return false;
  }

  let deliveryId: string;
  try {
    const delivery = await prisma.notificationDelivery.create({
      data: {
        accountId,
        memoId: notification.memoId,
        kind: notification.kind,
        dedupeKey: notification.dedupeKey,
        title: notification.title,
        body: notification.body,
        link: notification.link,
        sentAt: now,
      },
      select: { id: true },
    });
    deliveryId = delivery.id;
  } catch (cause) {
    if (cause instanceof Prisma.PrismaClientKnownRequestError && cause.code === "P2002") return false;
    throw cause;
  }

  const tokens = await prisma.pushToken.findMany({
    where: { accountId, session: { expiresAt: { gt: now } } },
    select: { id: true, token: true, environment: true },
  });

  // La bulle **avant** l'envoi : qui touche la notification aussitôt reçue
  // doit la trouver dans le fil. Une bulle sans notification — Apple en
  // panne — ne trompe personne ; elle ne se réécrit pas à la reprise.
  if (notification.chat && notification.memoId && tokens.length > 0) {
    try {
      await postToThread(context, notification.memoId, notification.chat);
    } catch (cause) {
      context.logger.error({ err: cause, accountId, kind: notification.kind }, "Bulle de notification non écrite.");
    }
  }

  let delivered = 0;
  let transientFailure = false;

  for (const token of tokens) {
    const outcome = await push.send(
      { token: token.token, environment: token.environment },
      {
        deliveryId,
        title: notification.title,
        body: notification.body,
        link: notification.link,
        threadId: notification.memoId ?? "memobook",
      },
    );

    if (outcome.kind === "sent") {
      delivered += 1;
    } else if (outcome.kind === "invalid_token") {
      await prisma.pushToken.delete({ where: { id: token.id } }).catch(() => {});
      context.logger.info({ accountId, reason: outcome.reason }, "Jeton APNs oublié : Apple ne le connaît plus.");
    } else {
      transientFailure = true;
      context.logger.warn(
        { accountId, kind: notification.kind, reason: outcome.reason },
        "Notification non délivrée à un téléphone.",
      );
    }
  }

  if (delivered === 0 && transientFailure) {
    await prisma.notificationDelivery.delete({ where: { id: deliveryId } });
    return false;
  }

  await prisma.notificationDelivery.update({
    where: { id: deliveryId },
    data: { deliveredCount: delivered },
  });
  return delivered > 0;
}

/**
 * La bulle de MEMO qui prolonge une notification dans le fil du voyage —
 * **une seule fois par fil**, quel que soit le nombre de co-voyageurs
 * notifiés : `payload.notification` porte la clé sans le compte.
 *
 * Le fil est d'abord remis à jour comme à sa lecture (`GET /v1/trips/:id/chat`) :
 * l'ouverture si personne ne l'a encore lu, puis les souvenirs qui n'y ont
 * pas de bulle. Sans ça, la bulle passerait avant les récits qu'elle annonce.
 */
export async function postToThread(
  context: Pick<AppContext, "prisma" | "responder">,
  memoId: string,
  chat: { key: string; text: string },
): Promise<void> {
  await context.prisma.$transaction(async (tx) => {
    await lockThread(tx, memoId);
    const already = await tx.chatMessage.findFirst({
      where: { memoId, author: "memo", payload: { path: ["notification"], equals: chat.key } },
      select: { id: true },
    });
    if (already) return;

    const memo = await tx.memo.findUniqueOrThrow({ where: { id: memoId }, select: { id: true, chatClearedAt: true } });
    await ensureOpening(tx, memoId, context.responder);
    await materializeEntriesWithoutMessages(tx, memo);
    await tx.chatMessage.create({
      data: {
        memoId,
        author: "memo",
        kind: "text",
        text: chat.text,
        model: "scripted",
        payload: { notification: chat.key },
      },
    });
  });
}

// ---------------------------------------------------------------------------
// L'e-mail de fin de voyage
// ---------------------------------------------------------------------------

export interface TripEndEmailReport {
  /** Les comptes à l'abonnement armé chez qui c'était l'heure. */
  evaluated: number;
  /** Les e-mails partis. */
  sent: number;
}

/**
 * **L'e-mail de fin de voyage** : le lendemain de la fin d'un voyage, le
 * rappel de couper l'abonnement s'il ne sert plus (Hugo, 03/10/2026). La
 * règle est dans `planTripEndEmail`, les mots dans `mailTemplates.ts`.
 *
 * Il ne passe **pas** par `sendDueNotifications` : celle-ci ne regarde que les
 * comptes qui ont un téléphone, et s'arrête sans APNs. L'e-mail est fait pour
 * les autres — ceux qui ont refusé les notifications, ou changé de téléphone.
 *
 * Seuls les comptes dont un abonnement App Store est vivant sont lus : ils se
 * comptent en dizaines, et c'est la première condition de la règle.
 */
export async function sendTripEndEmails(
  context: AppContext,
  now: Date = new Date(),
): Promise<TripEndEmailReport> {
  const report: TripEndEmailReport = { evaluated: 0, sent: 0 };

  const accounts = await context.prisma.account.findMany({
    where: {
      email: { not: null },
      subscriptions: { some: { provider: "storekit", status: { in: [...LIVING_SUBSCRIPTION_STATUSES] } } },
    },
    select: {
      id: true,
      email: true,
      firstName: true,
      timeZone: true,
      subscriptions: { select: { provider: true, status: true, autoRenews: true, renewsAt: true } },
    },
  });

  for (const row of accounts) {
    const renewal = armedAppleRenewal(row.subscriptions, now);
    if (!renewal || !row.email) continue;

    const zone = row.timeZone && isValidTimeZone(row.timeZone) ? row.timeZone : DEFAULT_TIME_ZONE;
    const hour = localHour(now, zone);
    if (hour < TRIP_END_EMAIL_EARLIEST_HOUR || hour >= LATEST_HOUR) continue;

    report.evaluated += 1;
    try {
      const account = await loadPlannerAccount(context, row.id, zone, now);
      const planned = planTripEndEmail(account, localDate(now, zone), hour);
      if (!planned) continue;

      const sent = await deliverTripEndEmail(
        context,
        { id: row.id, email: row.email, firstName: row.firstName },
        planned,
        renewal.renewsAt,
        now,
      );
      if (sent) report.sent += 1;
    } catch (cause) {
      // Un compte qui casse n'arrête pas la passe des autres.
      context.logger.error({ err: cause, accountId: row.id }, "E-mail de fin de voyage : compte ignoré sur erreur.");
    }
  }

  return report;
}

/**
 * Envoie l'e-mail, et le retient — comme `deliver` pour une notification.
 *
 * La ligne s'écrit **avant** l'envoi : c'est elle qui réserve la clé, et deux
 * passes qui se chevaucheraient n'enverraient pas deux e-mails. Elle est
 * retirée si l'envoi échoue, pour que la passe suivante le retente : un
 * e-mail qui n'est pas parti ne doit pas compter comme envoyé.
 */
async function deliverTripEndEmail(
  context: AppContext,
  recipient: { id: string; email: string; firstName: string | null },
  planned: PlannedTripEndEmail,
  unlimitedUntil: Date | null,
  now: Date,
): Promise<boolean> {
  const { prisma } = context;
  const { trip } = planned;

  let deliveryId: string;
  try {
    const delivery = await prisma.notificationDelivery.create({
      data: {
        accountId: recipient.id,
        memoId: trip.id,
        kind: planned.kind,
        dedupeKey: planned.dedupeKey,
        title: SUBSCRIPTION_REMINDER_SUBJECT,
        // Pas le corps de l'e-mail — il vit dans `mailTemplates.ts` : de quoi
        // reconnaître l'envoi en lisant le journal.
        body: `Rappel de couper l’abonnement, après « ${trip.title.trim()} ».`,
        link: APPLE_SUBSCRIPTIONS_URL,
        sentAt: now,
      },
      select: { id: true },
    });
    deliveryId = delivery.id;
  } catch (cause) {
    if (cause instanceof Prisma.PrismaClientKnownRequestError && cause.code === "P2002") return false;
    throw cause;
  }

  const message: SubscriptionReminderMail = {
    to: recipient.email,
    firstName: recipient.firstName,
    trip: { title: trip.title, city: trip.city },
    unlimitedUntil,
    bookEstimateCents: trip.storyCount > 0 && !trip.hasOrder ? trip.estimateCents : null,
  };

  try {
    await context.mailer.sendSubscriptionReminder(message);
  } catch (cause) {
    await prisma.notificationDelivery.delete({ where: { id: deliveryId } }).catch(() => {});
    context.logger.warn(
      { err: cause, accountId: recipient.id, memoId: trip.id },
      "E-mail de fin de voyage non envoyé : la passe suivante le retentera.",
    );
    return false;
  }

  await prisma.notificationDelivery.update({ where: { id: deliveryId }, data: { deliveredCount: 1 } });
  return true;
}
