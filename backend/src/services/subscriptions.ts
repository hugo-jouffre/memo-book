import type { AppContext } from "../context.js";

/**
 * L'abonnement s'arrête quand il n'y a plus de voyage à raconter.
 *
 * **C'est une promesse de l'offre, pas une optimisation.** Le troisième argument
 * du paywall dit « Arrêt automatique de l'abonnement — parce que tu n'as pas
 * besoin de notre application en dehors de tes voyages », et c'est ce qui rend
 * acceptable de se réabonner au voyage suivant. Une promesse tenue par un
 * humain qui pense à résilier n'est pas une promesse.
 *
 * **Ce qui compte, c'est la date, pas le `stage`.** `memos.stage` est figé à la
 * création et à chaque modification (`stageFromDates`) : un voyage dont la date
 * de fin est passée hier reste `ongoing` tant que personne ne l'a rouvert. On
 * lit donc les **dates**, qui, elles, ne mentent pas.
 *
 * ⚠️ **Rien n'est annulé chez Apple.** L'abonnement passe par StoreKit, qui
 * n'est pas encore branché : ce qui s'éteint ici, c'est la ligne
 * `subscriptions` — ce que l'app lit pour savoir s'il faut remontrer l'offre.
 * Le jour où StoreKit sera là, la vraie annulation reste **un geste de
 * l'utilisateur** dans les réglages iOS : Apple ne laisse aucune app résilier à
 * la place de son client. C'est alors le webhook App Store qui fermera cette
 * ligne, et cette fonction deviendra le filet plutôt que la règle.
 */
export async function endSubscriptionsWithoutRunningTrip(
  context: AppContext,
  accountId: string,
): Promise<number> {
  const running = await countRunningTrips(context, accountId);
  if (running > 0) return 0;

  const { count } = await context.prisma.subscription.updateMany({
    where: { accountId, status: { in: ["active", "trialing"] } },
    // `expired` et non `cancelled` : personne n'a résilié, c'est le voyage qui
    // s'est terminé. La distinction se lit dans l'historique, et elle dira un
    // jour pourquoi quelqu'un est parti.
    data: { status: "expired", cancelledAt: new Date() },
  });

  return count;
}

/**
 * Le même ménage, pour **tous** les comptes qui portent un abonnement en cours.
 *
 * Appelé par la tâche quotidienne : un voyage se termine par le calendrier, pas
 * par un geste, et personne n'ouvre l'app le jour où sa date de fin passe.
 * Sans cette passe, l'abonnement d'un compte inactif durerait indéfiniment.
 *
 * Les comptes sont traités un par un plutôt qu'en une requête : décider demande
 * de compter les voyages **encore en cours** de chacun, et un `updateMany`
 * global ne sait pas poser cette condition. Ils se comptent en dizaines, pas en
 * millions.
 */
export async function sweepEndedSubscriptions(context: AppContext): Promise<number> {
  const accounts = await context.prisma.subscription.findMany({
    where: { status: { in: ["active", "trialing"] } },
    select: { accountId: true },
    distinct: ["accountId"],
  });

  let ended = 0;
  for (const { accountId } of accounts) {
    ended += await endSubscriptionsWithoutRunningTrip(context, accountId);
  }

  return ended;
}

/**
 * Combien de voyages de ce compte **ne sont pas finis**.
 *
 * Un voyage sans date de fin compte comme en cours : c'est le cas de quelqu'un
 * qui part sans savoir quand il rentre, et lui couper son abonnement pour ça
 * serait exactement le contraire du service rendu.
 *
 * Les voyages où l'on est **co-voyageur** comptent aussi : on y raconte, donc
 * on s'en sert. `visibleToAccount` n'est pas réemployé ici parce qu'il faut
 * croiser l'appartenance avec les dates, et que la condition se lit mieux
 * écrite en entier.
 */
async function countRunningTrips(context: AppContext, accountId: string): Promise<number> {
  const now = new Date();

  return context.prisma.memo.count({
    where: {
      OR: [
        { ownerAccountId: accountId },
        { members: { some: { accountId, status: "active" } } },
      ],
      AND: [{ OR: [{ endDate: null }, { endDate: { gte: now } }] }],
    },
  });
}
