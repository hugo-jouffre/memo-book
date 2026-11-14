import type { AppContext } from "../context.js";
import { isSheetConfigured, pushSnapshotToSheet, statsScopeFromEnv } from "../services/statsExport.js";

/**
 * Le job qui pousse le relevé du jour dans la feuille de bord (T72).
 *
 * Sans charge utile, comme le ménage des abonnements : il relève, il envoie.
 * Voir `services/statsExport.ts` pour ce qui part, et
 * `scripts/apps-script/StatsSheet.gs` pour ce qui le reçoit.
 */
export type ExportStatsJob = Record<string, never>;

export async function exportStats(context: AppContext): Promise<void> {
  // Une instance sans adresse de feuille (un serveur de dev branché sur la
  // base partagée, un second service Railway) peut prendre le job avant la
  // bonne : il finissait « réussi » sans rien envoyer, et la feuille sautait
  // un jour (06/11 et 13/11/2026). Échouer laisse pg-boss le reproposer.
  if (!isSheetConfigured(context.env)) {
    throw new Error("STATS_SHEET_WEBHOOK_URL vide sur cette instance : relevé non envoyé, job reproposé.");
  }
  const scope = statsScopeFromEnv(context.env);
  const snapshot = await pushSnapshotToSheet(context);
  context.logger.info(
    {
      countFrom: scope.countFrom?.toISOString() ?? null,
      includedAccounts: scope.includedAccountIds.length,
      accounts: snapshot.accounts.total,
      ongoingTrips: snapshot.trips.ongoing,
      ordersInProgress: snapshot.orders.inProgress,
      deliveries: snapshot.deliveries.length,
    },
    "Relevé du jour envoyé à la feuille de bord.",
  );
}
