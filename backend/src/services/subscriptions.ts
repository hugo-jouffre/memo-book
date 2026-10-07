import type { Prisma, PrismaClient } from "@prisma/client";

/**
 * L'abonnement, vu du serveur : **qui raconte sans limite**.
 *
 * Il ne s'arrête plus avec le voyage (Hugo, 03/10/2026). L'ancien ménage
 * quotidien éteignait les abonnements hors App Store dès qu'aucun voyage ne
 * courait ; l'abonnement mensuel, lui, court jusqu'à ce qu'on le résilie, et
 * l'illimité reste ouvert jusqu'au bout du mois payé. Ce qui reste de la fin
 * de voyage, c'est un **rappel** : l'accueil propose de couper le
 * renouvellement (`subscriptionOutlivesTrip`, `appSerializers.ts`) et les
 * notifications le redisent.
 */

/**
 * Les statuts d'un abonnement **vivant** : il ouvre l'illimité. Un abonnement
 * en retard de paiement (`past_due`) aussi — c'est Apple qui accorde le délai
 * de grâce, et qui tranchera.
 */
export const LIVING_SUBSCRIPTION_STATUSES = ["active", "trialing", "past_due"] as const;

/**
 * Combien de temps un abonnement **vivant** reste ouvert après sa date de
 * renouvellement sans nouvelles du fournisseur. Le renouvellement ou
 * l'expiration arrivent d'ordinaire dans l'heure ; trois jours couvrent une
 * panne de webhook. Au-delà, un `EXPIRED` s'est perdu en route, et la ligne
 * aurait ouvert l'illimité à vie. Un abonné réellement renouvelé le
 * retrouve dès que l'app renvoie sa transaction (`Transaction.updates`).
 */
export const LIVING_SUBSCRIPTION_SLACK_MS = 3 * 24 * 60 * 60 * 1000;

/**
 * Les statuts d'un abonnement **terminé mais encore payé** : résilié le 3, un
 * mois réglé le 1er reste illimité jusqu'au 31 (Hugo, 03/10/2026 — c'était
 * déjà la règle de la semaine payée). Le sursis court jusqu'à `renewsAt`.
 */
export const PAID_THROUGH_SUBSCRIPTION_STATUSES = ["cancelled", "expired"] as const;

/**
 * La condition Prisma « cet abonnement ouvre l'illimité aujourd'hui ».
 *
 * **La seule**, et c'est voulu : le profil, l'accueil, le crédit du jour et
 * les notifications en avaient chacun leur copie, et trois copies d'une règle
 * d'argent finissent toujours par dire trois choses.
 */
export function unlimitedAccessWhere(now: Date = new Date()): Prisma.SubscriptionWhereInput {
  return {
    OR: [
      {
        status: { in: [...LIVING_SUBSCRIPTION_STATUSES] },
        OR: [{ renewsAt: null }, { renewsAt: { gt: new Date(now.getTime() - LIVING_SUBSCRIPTION_SLACK_MS) } }],
      },
      { status: { in: [...PAID_THROUGH_SUBSCRIPTION_STATUSES] }, renewsAt: { gt: now } },
    ],
  };
}

/**
 * La même règle, sur une ligne déjà chargée — pour l'accueil et le profil, qui
 * lisent les abonnements avec le compte et n'ont pas à refaire une requête.
 * **Doit dire exactement ce que dit `unlimitedAccessWhere`** : un test les
 * confronte (`test/dailyCredit.test.ts`).
 */
export function grantsUnlimitedAccess(
  subscription: { status: string; renewsAt: Date | null },
  now: Date = new Date(),
): boolean {
  if ((LIVING_SUBSCRIPTION_STATUSES as readonly string[]).includes(subscription.status)) {
    return (
      subscription.renewsAt === null ||
      subscription.renewsAt.getTime() > now.getTime() - LIVING_SUBSCRIPTION_SLACK_MS
    );
  }
  return (
    (PAID_THROUGH_SUBSCRIPTION_STATUSES as readonly string[]).includes(subscription.status) &&
    subscription.renewsAt !== null &&
    subscription.renewsAt.getTime() > now.getTime()
  );
}

type SubscriptionReader = Pick<PrismaClient, "subscription"> | Prisma.TransactionClient;

/** Ce compte raconte-t-il sans limite ? */
export async function hasUnlimitedAccess(
  prisma: SubscriptionReader,
  accountId: string,
  now: Date = new Date(),
): Promise<boolean> {
  const found = await prisma.subscription.findFirst({
    where: { accountId, ...unlimitedAccessWhere(now) },
    select: { id: true },
  });
  return found !== null;
}

// ---------------------------------------------------------------------------
// L'état d'un abonnement, en un mot (07/10/2026)
// ---------------------------------------------------------------------------

/**
 * **Ce que l'app dit de l'abonnement**, partout où elle le dit (Hugo,
 * 06/10/2026 — « quand quelqu'un se désabonne, tous les endroits qui
 * indiquaient « abonné » ne doivent plus l'indiquer »).
 *
 * Le statut en base ne suffisait pas : chaque écran le relisait à sa façon.
 * Un renouvellement coupé (`cancelled`) restait « abonné » ici et pas là ; un
 * `EXPIRED` perdu en route laissait la ligne `active` pour toujours, et le
 * profil disait « abonné » à quelqu'un dont l'illimité s'était refermé. Un mot,
 * calculé ici, et tous les champs en dérivent :
 *
 * | État | Ce que c'est | Illimité | « Abonné » |
 * |---|---|---|---|
 * | `active` | renouvellement armé | oui | oui |
 * | `grace` | prélèvement en échec, Apple garde l'accès le temps de réessayer | oui | oui |
 * | `ending` | renouvellement coupé (ou résilié) : la période payée court encore | jusqu'à `endsAt` | non |
 * | `ended` | plus rien ne court : expiré, remboursé, révoqué — ou sans nouvelles d'Apple trois jours après l'échéance | non | non |
 * | `none` | jamais abonné | non | non |
 *
 * La règle d'accès reste `grantsUnlimitedAccess` : `active`, `grace` et
 * `ending` sont exactement les abonnements qu'elle laisse passer.
 */
export type SubscriptionState = "none" | "active" | "ending" | "grace" | "ended";

type StatefulSubscription = { status: string; renewsAt: Date | null; autoRenews: boolean | null };

/** L'état d'**un** abonnement, aujourd'hui. */
export function subscriptionStateOf(
  subscription: StatefulSubscription,
  now: Date = new Date(),
): Exclude<SubscriptionState, "none"> {
  if (!grantsUnlimitedAccess(subscription, now)) return "ended";
  if (subscription.status === "past_due") return "grace";
  if ((LIVING_SUBSCRIPTION_STATUSES as readonly string[]).includes(subscription.status)) {
    return subscription.autoRenews === false ? "ending" : "active";
  }
  return "ending";
}

/** Du plus au moins abonné : c'est l'ordre dans lequel un compte se lit. */
const STATE_RANK: Record<Exclude<SubscriptionState, "none">, number> = { active: 0, grace: 1, ending: 2, ended: 3 };

export interface AccountSubscription<S> {
  state: SubscriptionState;
  /** L'abonnement qui donne cet état ; le plus récent quand tout est fini. */
  subscription: S | null;
  /** Le prochain prélèvement est-il armé ? */
  autoRenews: boolean;
  /** Le prochain prélèvement — rempli pour `active` seulement. */
  renewsAt: Date | null;
  /**
   * La fin de l'accès : la période payée pour `ending`, le délai de grâce pour
   * `grace`, le jour où il s'est arrêté pour `ended`. Nul pour `active`.
   */
  endsAt: Date | null;
}

/**
 * L'état **d'un compte** : son abonnement le plus vivant. `subscriptions` dans
 * n'importe quel ordre ; à égalité, le plus récent (`startedAt`) l'emporte.
 */
export function accountSubscriptionOf<S extends StatefulSubscription & { startedAt?: Date }>(
  subscriptions: readonly S[],
  now: Date = new Date(),
): AccountSubscription<S> {
  let best: { subscription: S; state: Exclude<SubscriptionState, "none"> } | null = null;
  for (const subscription of subscriptions) {
    const state = subscriptionStateOf(subscription, now);
    if (
      !best ||
      STATE_RANK[state] < STATE_RANK[best.state] ||
      (STATE_RANK[state] === STATE_RANK[best.state] &&
        (subscription.startedAt?.getTime() ?? 0) > (best.subscription.startedAt?.getTime() ?? 0))
    ) {
      best = { subscription, state };
    }
  }

  if (!best) return { state: "none", subscription: null, autoRenews: false, renewsAt: null, endsAt: null };

  const { subscription, state } = best;
  return {
    state,
    subscription,
    autoRenews: state === "active" || (state === "grace" && subscription.autoRenews !== false),
    renewsAt: state === "active" ? subscription.renewsAt : null,
    endsAt: state === "active" ? null : subscription.renewsAt,
  };
}
