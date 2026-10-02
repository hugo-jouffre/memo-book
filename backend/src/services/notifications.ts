import { Prisma } from "@prisma/client";
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
import { visibleToAccount } from "./memoOwnership.js";
import {
  accountRhythm,
  FIRST_SENDING_HOUR,
  LATEST_HOUR,
  planNotifications,
  selectNotifications,
  type NewFromOthers,
  type PlannedNotification,
  type PlannerAccount,
  type PlannerTrip,
} from "./notificationPlanner.js";
import { unitPriceCents } from "./printPricing.js";
import { schoolCalendarOf, type SchoolHolidayPeriod, type SchoolZone } from "./schoolHolidays.js";

/**
 * La passe d'envoi : **charger, décider, envoyer, retenir**. Appelée toutes
 * les heures par la tâche `sendNotifications`. Les règles elles-mêmes sont
 * dans `notificationPlanner.ts`, les mots dans `notificationCopy.ts`.
 *
 * Toutes les heures et non une fois par jour : « 10 h » n'arrive pas au même
 * moment à Paris et à Montréal. Chaque passe ne regarde que les comptes chez
 * qui il est entre 10 h et 21 h, et `dedupeKey` garantit qu'une notification
 * déjà partie ne repart pas à la passe suivante.
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

const LIVING_SUBSCRIPTION = ["active", "trialing", "past_due"] as const;

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
      birthDate: true,
      addressPostalCode: true,
      addressCountry: true,
      offeredSteps: true,
      remainingSteps: true,
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

  const [lastEntries, lastTurns, payments, deliveries, recentTurns, othersTold, weekEntries, exhaustion] = await Promise.all([
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
    // Ce que **ce compte** a payé d'abonnement pour chaque voyage.
    prisma.subscriptionTransaction.groupBy({
      by: ["memoId"],
      where: { memoId: { in: memoIds }, revokedAt: null, subscription: { accountId } },
      _sum: { priceCents: true },
    }),
    prisma.notificationDelivery.findMany({
      where: { accountId, sentAt: { gte: new Date(now.getTime() - HISTORY_DAYS * DAY_MS) } },
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
    // Le jour où la dernière étape offerte a été prise : la dernière
    // validation d'un souvenir que **ce compte** a raconté — c'est elle qui
    // décompte (`validateEntry`).
    account.remainingSteps === 0
      ? prisma.entry.aggregate({
          where: {
            validatedAt: { not: null },
            kind: { not: "photo" },
            chatMessages: { some: { accountId, disposition: "memory" } },
          },
          _max: { validatedAt: true },
        })
      : null,
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
    paidCents: payments.find((row) => row.memoId === memo.id)?._sum.priceCents ?? 0,
    // La même estimation que la cagnotte (`serializeWalletEstimate`) : celle
    // que le toucher de la notification de fin de voyage va montrer.
    estimateCents: unitPriceCents(Math.max(memo.targetPageCount, memo.pageCount)),
    memberCount: 1 + memo._count.members,
    newFromOthers: newFromOthers(memo.id),
    weekStories: weekCount(memo.id, false),
    weekPhotos: weekCount(memo.id, true),
  }));

  const exhaustedAt = exhaustion?._max.validatedAt ?? null;

  const living = account.subscriptions.filter((subscription) =>
    (LIVING_SUBSCRIPTION as readonly string[]).includes(subscription.status),
  );
  // La semaine payée court encore après une résiliation — la règle de
  // `assertCanRecord` (`quota.ts`) : ce compte peut encore raconter.
  const paidThrough = account.subscriptions.some(
    (subscription) =>
      (subscription.status === "cancelled" || subscription.status === "expired") &&
      subscription.renewsAt !== null &&
      subscription.renewsAt > now,
  );

  return {
    id: accountId,
    birthDate: account.birthDate ? calendarDate(account.birthDate) : null,
    schoolCalendar: schoolCalendarOf(account.addressPostalCode, account.addressCountry),
    offeredSteps: account.offeredSteps,
    remainingSteps: account.remainingSteps,
    stepsExhaustedOn: exhaustedAt ? localDate(exhaustedAt, timeZone) : null,
    isSubscribed: living.length > 0 || paidThrough,
    renewsAtApple: living.some(
      (subscription) => subscription.provider === "storekit" && subscription.autoRenews !== false,
    ),
    stopsAutomatically: living.some(
      (subscription) =>
        subscription.provider !== "storekit" && (subscription.status === "active" || subscription.status === "trialing"),
    ),
    usedRecently: recentTurns > 0,
    trips,
    deliveries: deliveries.map((delivery) => ({
      kind: delivery.kind,
      dedupeKey: delivery.dedupeKey,
      sentOn: localDate(delivery.sentAt, timeZone),
      opened: delivery.openedAt !== null,
    })),
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
