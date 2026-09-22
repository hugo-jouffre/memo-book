import type { PrismaClient } from "@prisma/client";
import { HttpError } from "../lib/httpError.js";

/**
 * Les statuts d'abonnement qui ouvrent l'app : les mêmes que ceux que le profil
 * montre (`routes/profile.ts`). Un abonnement en retard de paiement
 * (`past_due`) laisse encore raconter — c'est le fournisseur qui tranchera.
 */
const LIVING_SUBSCRIPTION = ["active", "trialing", "past_due"] as const;

/**
 * Les statuts d'un abonnement **terminé mais encore payé**.
 *
 * Une semaine commencée est une semaine réglée : résilier le lundi ne rend pas
 * les six jours suivants, donc il ne ferme pas le micro non plus (Hugo,
 * 16/09/2026). Le sursis court jusqu'à `renewsAt`, la fin de la période payée —
 * c'est la même date que l'app annonce sur les deux dernières feuilles de
 * résiliation (`Subscription.paidThrough`).
 *
 * `expired` en fait partie autant que `cancelled` : un abonnement éteint par la
 * fin du voyage (`endSubscriptionsWithoutRunningTrip`) a été payé jusqu'au même
 * jour, et couper l'accès plus tôt parce que personne n'a cliqué serait plus
 * sévère qu'une résiliation volontaire.
 */
const PAID_THROUGH_SUBSCRIPTION = ["cancelled", "expired"] as const;

/**
 * Le compte a-t-il encore le droit de raconter ?
 *
 * **C'est le vrai verrou.** L'app grise son micro et ouvre le paywall quand les
 * étapes offertes sont épuisées, mais un écran se contourne — un vieux build,
 * un vocal resté dans la file hors ligne, une requête faite à la main. Le
 * serveur, lui, refuse : sans abonnement vivant et avec un quota à zéro, aucun
 * souvenir n'entre. Hugo, 14/09/2026 : « le user ne doit jamais pouvoir
 * continuer à enregistrer quand il est à court des 3 crédits initiaux ».
 *
 * Trois cas, dans cet ordre : un abonnement vivant ouvre tout ; un compte
 * **sans quota** (`remainingSteps: null` — les comptes d'avant le quota, ou un
 * ancien abonné à qui on ne l'a jamais posé) n'est pas limité ; un quota
 * épuisé ferme.
 *
 * **Une étape = un souvenir, réservée à la création et confirmée à la
 * validation** (Hugo, 22/09/2026 — `docs/conversation.md` § 6). Un souvenir
 * non validé compte donc déjà comme une étape prise : avec trois offertes, le
 * quatrième souvenir est refusé même si aucun n'a été validé. Sans cette
 * réserve, quelqu'un qui ne tape jamais « Ça me convient » raconterait sans
 * fin sur un compte gratuit. `validateEntry` confirme, et décrémente.
 */
export async function assertCanRecord(prisma: PrismaClient, accountId: string): Promise<void> {
  const account = await prisma.account.findUniqueOrThrow({
    where: { id: accountId },
    select: {
      remainingSteps: true,
      subscriptions: {
        where: {
          OR: [
            { status: { in: [...LIVING_SUBSCRIPTION] } },
            // Le sursis de la semaine payée — voir `PAID_THROUGH_SUBSCRIPTION`.
            {
              status: { in: [...PAID_THROUGH_SUBSCRIPTION] },
              renewsAt: { gt: new Date() },
            },
          ],
        },
        select: { id: true },
        take: 1,
      },
    },
  });

  if (account.subscriptions.length > 0) return;
  if (account.remainingSteps === null) return;

  const reserved = await countReservedSteps(prisma, accountId);
  if (account.remainingSteps - reserved > 0) return;

  throw new HttpError(
    403,
    "Tes étapes offertes sont toutes racontées : abonne-toi pour continuer ton carnet.",
    "quota_exhausted",
  );
}

/**
 * Les souvenirs non validés qui **réservent** une étape de ce compte : ceux
 * qu'il a racontés dans le chat — la bulle retient qui a parlé, le souvenir
 * non (`docs/conversation.md` § 2). Une photo n'est pas une étape.
 *
 * Un souvenir arrivé hors du chat (le seed, un vocal de l'accueil d'avant
 * que celui-ci passe par le fil) ne réserve rien : il a déjà franchi ce
 * verrou à sa création, et compter après coup ce que personne n'a pu valider
 * fermerait les comptes existants d'un jour à l'autre.
 */
export async function countReservedSteps(prisma: PrismaClient, accountId: string): Promise<number> {
  return prisma.entry.count({
    where: {
      validatedAt: null,
      kind: { not: "photo" },
      chatMessages: { some: { accountId, disposition: "memory" } },
    },
  });
}

/**
 * « Ça me convient » : le souvenir est relu et gardé tel quel, et l'étape
 * qu'il réservait est confirmée — décomptée du compte **qui valide**, comme
 * `assertCanRecord` est par compte.
 *
 * Idempotent : valider deux fois ne décompte qu'une fois. Un compte sans
 * quota (`remainingSteps: null`) n'a rien à décompter.
 */
export async function validateEntry(
  prisma: PrismaClient,
  entryId: string,
  accountId: string,
): Promise<{ offeredSteps: number | null; remainingSteps: number | null }> {
  return prisma.$transaction(async (tx) => {
    const { count } = await tx.entry.updateMany({
      where: { id: entryId, validatedAt: null },
      data: { validatedAt: new Date() },
    });

    if (count > 0) {
      await tx.account.updateMany({
        where: { id: accountId, remainingSteps: { gt: 0 } },
        data: { remainingSteps: { decrement: 1 } },
      });
    }

    return tx.account.findUniqueOrThrow({
      where: { id: accountId },
      select: { offeredSteps: true, remainingSteps: true },
    });
  });
}
