import type { AppContext } from "../context.js";
import { sweepEndedSubscriptions } from "../services/subscriptions.js";

/**
 * Le job qui éteint les abonnements dont le voyage est fini.
 *
 * **Il n'a pas de charge utile**, et c'est ce qui le distingue des quatre
 * autres : ceux-là traitent un souvenir ou un rendu précis, celui-ci balaie.
 * pg-boss lui en passe une vide ; on l'ignore.
 *
 * Voir `services/subscriptions.ts` pour la règle, et pour ce qui reste à faire
 * le jour où StoreKit sera branché.
 */
export type EndSubscriptionsJob = Record<string, never>;

export async function endSubscriptions(context: AppContext): Promise<void> {
  const ended = await sweepEndedSubscriptions(context);
  if (ended > 0) {
    context.logger.info({ ended }, "Abonnements arrêtés faute de voyage en cours.");
  }
}
