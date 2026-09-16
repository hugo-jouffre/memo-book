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
 * ancien abonné à qui on ne l'a jamais posé) n'est pas limité ; un quota à
 * zéro ferme.
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
  if (account.remainingSteps === null || account.remainingSteps > 0) return;

  throw new HttpError(
    403,
    "Tes étapes offertes sont toutes racontées : abonne-toi pour continuer ton carnet.",
    "quota_exhausted",
  );
}
