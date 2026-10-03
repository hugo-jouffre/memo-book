import type { AppContext } from "../context.js";
import { sendDueNotifications, sendTripEndEmails } from "../services/notifications.js";

/**
 * La passe horaire des notifications — voir `services/notifications.ts`.
 *
 * Sans charge utile, comme la feuille de bord : elle balaie les
 * comptes chez qui il est l'heure, elle ne traite pas un objet précis.
 *
 * Elle envoie aussi l'e-mail de fin de voyage (03/10/2026) : mêmes heures
 * chez le voyageur, même journal, et pas de tâche de plus à planifier. Les
 * deux envois sont indépendants — sans APNs, l'e-mail part quand même ; c'est
 * même pour ça qu'il existe.
 */
export type SendNotificationsJob = Record<string, never>;

export async function sendNotifications(context: AppContext): Promise<void> {
  const report = await sendDueNotifications(context);
  if (report.sent > 0) {
    context.logger.info(report, "Passe des notifications terminée.");
  }

  const emails = await sendTripEndEmails(context);
  if (emails.sent > 0) {
    context.logger.info(emails, "E-mails de fin de voyage envoyés.");
  }
}
