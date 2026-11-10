import type { AppContext } from "../context.js";
import { purgeDeletedMemos } from "../services/trash.js";

/**
 * **Le vidage de la corbeille** : chaque nuit, les voyages jetés il y a plus
 * de trente jours s'effacent pour de bon — souvenirs, fichiers, commandes et
 * traces chez les prestataires (`services/trash.ts`).
 *
 * Sans charge utile, comme `exportStats` et `releaseAbandonedOrders`. La nuit
 * plutôt qu'à l'heure : rien ne presse à la minute près, et la suppression
 * touche S3 et les prestataires — autant la poser quand personne ne raconte.
 */
export type PurgeTrashJob = Record<string, never>;

export async function purgeTrash(context: AppContext): Promise<void> {
  const report = await purgeDeletedMemos(context);
  if (report.memos > 0) {
    context.logger.info({ ...report }, "Corbeille vidée.");
  }
}
