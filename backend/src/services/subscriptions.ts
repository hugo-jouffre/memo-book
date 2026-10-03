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
