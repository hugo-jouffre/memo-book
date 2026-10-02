import type { AppContext } from "../context.js";
import { sendDueNotifications } from "../services/notifications.js";

/**
 * La passe horaire des notifications — voir `services/notifications.ts`.
 *
 * Sans charge utile, comme le ménage des abonnements : elle balaie les
 * comptes chez qui il est l'heure, elle ne traite pas un objet précis.
 */
export type SendNotificationsJob = Record<string, never>;

export async function sendNotifications(context: AppContext): Promise<void> {
  const report = await sendDueNotifications(context);
  if (report.sent > 0) {
    context.logger.info(report, "Passe des notifications terminée.");
  }
}
