import type { AppContext } from "../context.js";
import { endSubscriptions, type EndSubscriptionsJob } from "./endSubscriptions.js";
import { JOB_NAMES } from "./queue.js";
import { redactEntry, type RedactJob } from "./redact.js";
import { renderBook, type RenderJob } from "./render.js";
import { structureRender, type StructureJob } from "./structure.js";
import { transcribeEntry, type TranscribeJob } from "./transcribe.js";

/**
 * L'heure du ménage des abonnements : 3 h 10 UTC, tous les jours.
 *
 * Tôt, parce qu'un voyage se termine à minuit et que l'abonnement ne doit pas
 * survivre à la journée qui suit ; et **pas à une heure ronde**, où tout le
 * monde programme ses tâches.
 */
export const END_SUBSCRIPTIONS_CRON = "10 3 * * *";

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
  context.queue.register<StructureJob>(JOB_NAMES.structure, (payload) =>
    structureRender(context, payload),
  );
  context.queue.register<RenderJob>(JOB_NAMES.render, (payload) =>
    renderBook(context, payload),
  );
  context.queue.register<EndSubscriptionsJob>(JOB_NAMES.endSubscriptions, () =>
    endSubscriptions(context),
  );

  // L'horaire est demandé ici et posé au démarrage de la file. Idempotent :
  // relancer le serveur ne crée pas un second passage quotidien.
  void context.queue.schedule(JOB_NAMES.endSubscriptions, END_SUBSCRIPTIONS_CRON);
}

export { JOB_NAMES };
export type { EndSubscriptionsJob, RedactJob, RenderJob, StructureJob, TranscribeJob };
