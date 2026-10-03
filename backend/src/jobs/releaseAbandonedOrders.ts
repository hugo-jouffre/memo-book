import type { AppContext } from "../context.js";
import { releaseAbandonedOrders as release } from "../services/orderPayments.js";

/**
 * Le ménage des commandes jamais payées : chaque heure, les brouillons de plus
 * de 24 h annulent leur intention et rendent leur part de cagnotte. Sans charge
 * utile, comme `exportStats`. Voir `services/orderPayments.ts`.
 */
export type ReleaseAbandonedOrdersJob = Record<string, never>;

export async function releaseAbandonedOrders(context: AppContext): Promise<void> {
  const released = await release(context);
  if (released > 0) {
    context.logger.info({ released }, "Commandes non payées fermées, réservations rendues.");
  }
}
