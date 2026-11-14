import type { Prisma, PrismaClient } from "@prisma/client";
import type { AppContext } from "../context.js";
import type { Env } from "../env.js";
import { stageFromDates } from "./tripStage.js";

/**
 * La feuille de bord (T72, 29/09/2026) : les chiffres de l'app, poussés chaque
 * jour dans un Google Sheet — et chaque raison de départ, au moment où elle
 * est donnée.
 *
 * **Le serveur ne parle pas à Google.** Il envoie un JSON à un script Apps
 * Script déployé en application web (`backend/scripts/apps-script/StatsSheet.gs`),
 * et c'est le script qui écrit les lignes. Deux raisons :
 *
 * - aucune clé Google, aucun compte de service à garder sur Railway — le
 *   script tourne avec le compte qui possède la feuille ;
 * - la feuille change de forme sans redéployer l'API : un onglet de plus, une
 *   colonne renommée, c'est le script qu'on modifie.
 *
 * Trois onglets : **Relevés** (un relevé par jour, une colonne par chiffre),
 * **Résiliations** (une ligne par raison de départ) et **Carnets à livrer**
 * (réécrit à chaque relevé : les commandes parties de la production et pas
 * encore livrées, avec leur adresse).
 *
 * Sans `STATS_SHEET_WEBHOOK_URL`, rien ne part et rien n'échoue.
 *
 * **Qui compte** (14/11/2026) : la base sert TestFlight, l'App Store et les
 * tests. Chaque chiffre se limite aux comptes du périmètre (`StatsScope`) :
 * ceux ouverts depuis `STATS_COUNT_FROM`, plus ceux de
 * `STATS_INCLUDED_ACCOUNT_IDS`, jamais les comptes de test automatiques.
 *
 * - Un **voyage** compte si son propriétaire compte, ou si un participant
 *   actif compte : un voyage partagé avec un compte du périmètre est lié à
 *   lui. Ses souvenirs, ses photos et ses rendus suivent le voyage.
 * - Une **commande** compte si son acheteur compte, ou si son voyage compte.
 * - Un **abonnement** suit le compte qui le paie.
 */

/** Le périmètre des comptes relevés. */
export interface StatsScope {
  /** Les comptes ouverts à partir de cette date. Null : tous, sans date. */
  countFrom: Date | null;
  /** Des comptes plus anciens qui comptent quand même. */
  includedAccountIds: string[];
}

/** Tous les comptes, sauf les comptes de test automatiques. */
export const ALL_ACCOUNTS: StatsScope = { countFrom: null, includedAccountIds: [] };

/** Les adresses des comptes créés par les scripts de test (e2e, smoke). */
const TEST_EMAIL_SUFFIXES = ["@memobook.test"];
const TEST_EMAIL_PREFIXES = ["smoke-"];

export type StatsScopeEnv = Pick<Env, "STATS_COUNT_FROM" | "STATS_INCLUDED_ACCOUNT_IDS">;

/** Lit le périmètre dans l'environnement. Une date illisible est une erreur qu'on voit. */
export function statsScopeFromEnv(env: StatsScopeEnv): StatsScope {
  const raw = env.STATS_COUNT_FROM.trim();
  let countFrom: Date | null = null;
  if (raw !== "") {
    countFrom = new Date(raw);
    if (Number.isNaN(countFrom.getTime())) {
      throw new Error(`STATS_COUNT_FROM illisible : « ${raw} ».`);
    }
  }
  const includedAccountIds = env.STATS_INCLUDED_ACCOUNT_IDS.split(",")
    .map((id) => id.trim())
    .filter((id) => id !== "");
  return { countFrom, includedAccountIds };
}

/** Le filtre Prisma des comptes du périmètre. */
export function scopedAccounts(scope: StatsScope): Prisma.AccountWhereInput {
  // `NOT` sur une colonne nullable écarte aussi les NULL en SQL : un compte
  // sans e-mail (Apple qui masque tout) doit rester, d'où le `email: null`.
  const conditions: Prisma.AccountWhereInput[] = [
    ...TEST_EMAIL_SUFFIXES.map(
      (suffix): Prisma.AccountWhereInput => ({
        OR: [{ email: null }, { NOT: { email: { endsWith: suffix, mode: "insensitive" } } }],
      }),
    ),
    ...TEST_EMAIL_PREFIXES.map(
      (prefix): Prisma.AccountWhereInput => ({
        OR: [{ email: null }, { NOT: { email: { startsWith: prefix, mode: "insensitive" } } }],
      }),
    ),
  ];
  if (scope.countFrom) {
    conditions.push({
      OR: [{ createdAt: { gte: scope.countFrom } }, { id: { in: scope.includedAccountIds } }],
    });
  }
  return { AND: conditions };
}

/** Ce compte compte-t-il ? Pour les envois à l'unité (raisons de départ). */
export async function isAccountInScope(
  prisma: PrismaClient,
  accountId: string,
  scope: StatsScope,
): Promise<boolean> {
  const count = await prisma.account.count({ where: { AND: [{ id: accountId }, scopedAccounts(scope)] } });
  return count > 0;
}

export interface StatsSnapshot {
  generatedAt: string;
  accounts: {
    total: number;
    /** Ouverts ces sept derniers jours. */
    newLast7Days: number;
    /** Avec un abonnement actif ou en essai. */
    subscribed: number;
  };
  trips: {
    total: number;
    /** Les carnets en cours d'écriture : voyage commencé et pas fini. */
    ongoing: number;
    upcoming: number;
    past: number;
    /** Composés au moins une fois : un rendu prêt existe. */
    composed: number;
  };
  orders: {
    /** Toutes les commandes passées, brouillons compris, hors annulées. */
    total: number;
    /** Commandées et pas encore livrées : soumises, en production, expédiées. */
    inProgress: number;
    draft: number;
    submitted: number;
    inProduction: number;
    shipped: number;
    delivered: number;
    cancelled: number;
    /** Exemplaires commandés, toutes commandes payées confondues. */
    copies: number;
    /** Ce que les commandes ont rapporté, en euros, hors brouillons et annulées. */
    revenueEuros: number;
  };
  subscriptions: {
    active: number;
    cancelled: number;
    expired: number;
    /** Les raisons de départ, comptées. */
    cancellationReasons: Record<string, number>;
  };
  memories: {
    /** Les souvenirs racontés, tous voyages confondus. */
    total: number;
    photos: number;
  };
  /** Les carnets à livrer, pour l'onglet dédié. */
  deliveries: DeliveryRow[];
}

export interface DeliveryRow {
  orderId: string;
  tripTitle: string;
  status: string;
  copies: number;
  pageCount: number;
  amountEuros: number | null;
  recipient: string;
  city: string;
  country: string;
  trackingUrl: string | null;
  submittedAt: string | null;
  shippedAt: string | null;
}

const DAY_MS = 24 * 60 * 60 * 1000;

function euros(cents: number | null): number | null {
  return cents === null ? null : Math.round(cents) / 100;
}

/** Relève les chiffres du moment. Une poignée de requêtes, aucune par ligne. */
export async function collectStats(
  prisma: PrismaClient,
  now: Date = new Date(),
  scope: StatsScope = ALL_ACCOUNTS,
): Promise<StatsSnapshot> {
  const weekAgo = new Date(now.getTime() - 7 * DAY_MS);
  const accounts = scopedAccounts(scope);
  const memos: Prisma.MemoWhereInput = {
    OR: [{ owner: accounts }, { members: { some: { status: "active", account: accounts } } }],
  };
  const orderWhere: Prisma.PrintOrderWhereInput = {
    OR: [{ orderedBy: accounts }, { memo: memos }],
  };

  const [
    accountsTotal,
    accountsNew,
    subscribedAccounts,
    trips,
    composedTrips,
    orders,
    subscriptions,
    memoriesTotal,
    photosTotal,
  ] = await Promise.all([
    prisma.account.count({ where: accounts }),
    prisma.account.count({ where: { AND: [accounts, { createdAt: { gte: weekAgo } }] } }),
    prisma.subscription.findMany({
      where: { status: { in: ["active", "trialing"] }, account: accounts },
      select: { accountId: true },
      distinct: ["accountId"],
    }),
    prisma.memo.findMany({ where: memos, select: { stage: true, startDate: true, endDate: true } }),
    prisma.render.findMany({
      where: { status: "ready", memo: memos },
      select: { memoId: true },
      distinct: ["memoId"],
    }),
    prisma.printOrder.findMany({
      where: orderWhere,
      select: {
        id: true,
        status: true,
        copies: true,
        pageCount: true,
        amountCents: true,
        shippingName: true,
        shippingCity: true,
        shippingCountry: true,
        trackingUrl: true,
        submittedAt: true,
        shippedAt: true,
        deliveredAt: true,
        memo: { select: { title: true } },
      },
      orderBy: { createdAt: "asc" },
    }),
    prisma.subscription.findMany({ where: { account: accounts }, select: { status: true, cancellationReason: true } }),
    prisma.entry.count({ where: { kind: { in: ["audio", "text"] }, memo: memos } }),
    prisma.entry.count({ where: { kind: "photo", memo: memos } }),
  ]);

  const stages = { ongoing: 0, upcoming: 0, past: 0 };
  for (const trip of trips) {
    const stored = trip.stage === "past" || trip.stage === "upcoming" ? trip.stage : "ongoing";
    stages[stageFromDates(trip.startDate, trip.endDate, now, stored)] += 1;
  }

  const byStatus = { draft: 0, submitted: 0, in_production: 0, shipped: 0, cancelled: 0 };
  let delivered = 0;
  let copies = 0;
  let revenueCents = 0;
  const deliveries: DeliveryRow[] = [];

  for (const order of orders) {
    byStatus[order.status] += 1;
    if (order.deliveredAt) delivered += 1;
    if (order.status !== "draft" && order.status !== "cancelled") {
      copies += order.copies;
      revenueCents += order.amountCents ?? 0;
    }
    const toDeliver =
      (order.status === "submitted" || order.status === "in_production" || order.status === "shipped") &&
      !order.deliveredAt;
    if (toDeliver) {
      deliveries.push({
        orderId: order.id,
        tripTitle: order.memo.title,
        status: order.status,
        copies: order.copies,
        pageCount: order.pageCount ?? 0,
        amountEuros: euros(order.amountCents),
        recipient: order.shippingName,
        city: order.shippingCity,
        country: order.shippingCountry,
        trackingUrl: order.trackingUrl,
        submittedAt: order.submittedAt?.toISOString() ?? null,
        shippedAt: order.shippedAt?.toISOString() ?? null,
      });
    }
  }

  const reasons: Record<string, number> = {};
  const subscriptionCounts = { active: 0, cancelled: 0, expired: 0 };
  for (const subscription of subscriptions) {
    if (subscription.status === "active" || subscription.status === "trialing") subscriptionCounts.active += 1;
    if (subscription.status === "cancelled") subscriptionCounts.cancelled += 1;
    if (subscription.status === "expired") subscriptionCounts.expired += 1;
    if (subscription.cancellationReason) {
      reasons[subscription.cancellationReason] = (reasons[subscription.cancellationReason] ?? 0) + 1;
    }
  }

  return {
    generatedAt: now.toISOString(),
    accounts: {
      total: accountsTotal,
      newLast7Days: accountsNew,
      subscribed: subscribedAccounts.length,
    },
    trips: {
      total: trips.length,
      ongoing: stages.ongoing,
      upcoming: stages.upcoming,
      past: stages.past,
      composed: composedTrips.length,
    },
    orders: {
      total: orders.length - byStatus.cancelled,
      inProgress: byStatus.submitted + byStatus.in_production + byStatus.shipped - delivered,
      draft: byStatus.draft,
      submitted: byStatus.submitted,
      inProduction: byStatus.in_production,
      shipped: byStatus.shipped,
      delivered,
      cancelled: byStatus.cancelled,
      copies,
      revenueEuros: revenueCents / 100,
    },
    subscriptions: { ...subscriptionCounts, cancellationReasons: reasons },
    memories: { total: memoriesTotal, photos: photosTotal },
    deliveries,
  };
}

/** Ce que le script reçoit : un type d'envoi, et son contenu. */
export type SheetMessage =
  | { type: "snapshot"; snapshot: StatsSnapshot }
  | {
      type: "cancellation";
      at: string;
      /** Le compte, abrégé : la feuille compte des départs, elle ne nomme personne. */
      account: string;
      reason: string | null;
      hadActiveSubscription: boolean;
    };

export type SheetEnv = Pick<Env, "STATS_SHEET_WEBHOOK_URL" | "STATS_SHEET_SECRET">;

export function isSheetConfigured(env: SheetEnv): boolean {
  return env.STATS_SHEET_WEBHOOK_URL.trim() !== "";
}

/**
 * Envoie un message au script. Apps Script répond par une redirection 302
 * vers la vraie réponse : `fetch` la suit tout seul, et c'est le corps final
 * qui dit si le script a écrit.
 */
export async function postToSheet(
  env: SheetEnv,
  message: SheetMessage,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  if (!isSheetConfigured(env)) return;

  const response = await fetchImpl(env.STATS_SHEET_WEBHOOK_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret: env.STATS_SHEET_SECRET, ...message }),
    redirect: "follow",
  });

  if (!response.ok) {
    throw new Error(`La feuille de bord a répondu ${response.status}.`);
  }
  const body = (await response.json().catch(() => ({}))) as { ok?: boolean; error?: string };
  if (body.ok === false) {
    throw new Error(`La feuille de bord a refusé l'envoi : ${body.error ?? "sans détail"}.`);
  }
}

/** Le relevé du jour, envoyé. Rend le relevé pour qui veut le lire. */
export async function pushSnapshotToSheet(context: AppContext): Promise<StatsSnapshot> {
  const snapshot = await collectStats(context.prisma, new Date(), statsScopeFromEnv(context.env));
  if (!isSheetConfigured(context.env)) {
    context.logger.info(
      { accounts: snapshot.accounts.total, trips: snapshot.trips.total, orders: snapshot.orders.total },
      "Feuille de bord non configurée (STATS_SHEET_WEBHOOK_URL) : relevé journalisé seulement.",
    );
    return snapshot;
  }
  await postToSheet(context.env, { type: "snapshot", snapshot });
  return snapshot;
}

/**
 * Une raison de départ, au moment où elle est donnée. **Ne lève jamais** :
 * une feuille qui ne répond pas n'a pas à faire échouer une résiliation.
 */
export async function pushCancellationToSheet(
  context: AppContext,
  input: { accountId: string; reason: string | null; hadActiveSubscription: boolean },
): Promise<void> {
  if (!isSheetConfigured(context.env)) return;
  try {
    // Un compte hors périmètre (démo, test) ne laisse pas de ligne.
    const inScope = await isAccountInScope(context.prisma, input.accountId, statsScopeFromEnv(context.env));
    if (!inScope) {
      context.logger.info({ accountId: input.accountId }, "Raison de départ hors périmètre : pas envoyée à la feuille de bord.");
      return;
    }
    await postToSheet(context.env, {
      type: "cancellation",
      at: new Date().toISOString(),
      account: input.accountId.slice(0, 8),
      reason: input.reason,
      hadActiveSubscription: input.hadActiveSubscription,
    });
  } catch (cause) {
    context.logger.warn({ cause }, "Raison de départ non envoyée à la feuille de bord");
  }
}
