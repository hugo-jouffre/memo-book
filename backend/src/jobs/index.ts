import type { AppContext } from "../context.js";
import { converseTurn, type ConverseJob } from "./converse.js";
import { exportStats, type ExportStatsJob } from "./exportStats.js";
import {
  releaseAbandonedOrders,
  type ReleaseAbandonedOrdersJob,
} from "./releaseAbandonedOrders.js";
import { JOB_NAMES } from "./queue.js";
import { sendNotifications, type SendNotificationsJob } from "./sendNotifications.js";
import { syncSchoolHolidays, type SyncSchoolHolidaysJob } from "./syncSchoolHolidays.js";
import { redactEntry, type RedactJob } from "./redact.js";
import { renderBook, type RenderJob } from "./render.js";
import { structureRender, type StructureJob } from "./structure.js";
import { transcribeEntry, type TranscribeJob } from "./transcribe.js";

/**
 * Le ménage des commandes jamais payées : à la 25e minute de chaque heure. Une
 * intention de paiement abandonnée ne doit pas rester ouverte une nuit de plus
 * qu'il ne faut.
 */
export const RELEASE_ABANDONED_ORDERS_CRON = "25 * * * *";

/**
 * L'heure de la feuille de bord : 4 h 20 UTC, tous les jours — et **pas à une
 * heure ronde**, où tout le monde programme ses tâches.
 */
export const EXPORT_STATS_CRON = "20 4 * * *";

/**
 * La passe des notifications : à la 35e minute de **chaque** heure. Chaque
 * voyageur reçoit les siennes à 10 h chez lui (19 h pour la relance
 * d'écriture), et 10 h n'arrive pas à la même heure UTC partout.
 */
export const SEND_NOTIFICATIONS_CRON = "35 * * * *";

/**
 * Le calendrier scolaire : 5 h 40 UTC, bien avant la première passe de
 * notifications de la journée en France (10 h, soit 8 h ou 9 h UTC).
 */
export const SYNC_SCHOOL_HOLIDAYS_CRON = "40 5 * * *";

/**
 * Branche les étapes du pipeline sur la file, et pose la tâche quotidienne. À
 * appeler avant `queue.start()`, aussi bien dans le serveur que dans le worker
 * dédié : c'est `start()` qui posera l'horaire une fois la file debout.
 */
export function registerJobs(context: AppContext): void {
  context.queue.register<TranscribeJob>(JOB_NAMES.transcribe, (payload) =>
    transcribeEntry(context, payload),
  );
  context.queue.register<RedactJob>(JOB_NAMES.redact, (payload) =>
    redactEntry(context, payload),
  );
  context.queue.register<ConverseJob>(JOB_NAMES.converse, (payload) =>
    converseTurn(context, payload),
  );
  context.queue.register<StructureJob>(JOB_NAMES.structure, (payload) =>
    structureRender(context, payload),
  );
  context.queue.register<RenderJob>(JOB_NAMES.render, (payload) =>
    renderBook(context, payload),
  );
  context.queue.register<ExportStatsJob>(JOB_NAMES.exportStats, () => exportStats(context));
  context.queue.register<ReleaseAbandonedOrdersJob>(JOB_NAMES.releaseAbandonedOrders, () =>
    releaseAbandonedOrders(context),
  );
  context.queue.register<SendNotificationsJob>(JOB_NAMES.sendNotifications, () =>
    sendNotifications(context),
  );
  context.queue.register<SyncSchoolHolidaysJob>(JOB_NAMES.syncSchoolHolidays, () =>
    syncSchoolHolidays(context),
  );

  // Les horaires sont demandés ici et posés au démarrage de la file.
  // Idempotents : relancer le serveur ne crée pas un second passage quotidien.
  void context.queue.schedule(JOB_NAMES.exportStats, EXPORT_STATS_CRON);
  void context.queue.schedule(JOB_NAMES.releaseAbandonedOrders, RELEASE_ABANDONED_ORDERS_CRON);
  void context.queue.schedule(JOB_NAMES.sendNotifications, SEND_NOTIFICATIONS_CRON);
  void context.queue.schedule(JOB_NAMES.syncSchoolHolidays, SYNC_SCHOOL_HOLIDAYS_CRON);
}

export { JOB_NAMES };
export type {
  ConverseJob,
  ExportStatsJob,
  RedactJob,
  ReleaseAbandonedOrdersJob,
  RenderJob,
  SendNotificationsJob,
  StructureJob,
  SyncSchoolHolidaysJob,
  TranscribeJob,
};
