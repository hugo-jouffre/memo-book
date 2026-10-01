import type { AppContext } from "../context.js";
import { pushSnapshotToSheet } from "../services/statsExport.js";

/**
 * Le job qui pousse le relevé du jour dans la feuille de bord (T72).
 *
 * Sans charge utile, comme le ménage des abonnements : il relève, il envoie.
 * Voir `services/statsExport.ts` pour ce qui part, et
 * `scripts/apps-script/StatsSheet.gs` pour ce qui le reçoit.
 */
export type ExportStatsJob = Record<string, never>;

export async function exportStats(context: AppContext): Promise<void> {
  const snapshot = await pushSnapshotToSheet(context);
  context.logger.info(
    {
      accounts: snapshot.accounts.total,
      ongoingTrips: snapshot.trips.ongoing,
      ordersInProgress: snapshot.orders.inProgress,
      deliveries: snapshot.deliveries.length,
    },
    "Relevé du jour envoyé à la feuille de bord.",
  );
}
