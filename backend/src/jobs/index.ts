import type { AppContext } from "../context.js";
import { JOB_NAMES } from "./queue.js";
import { redactEntry, type RedactJob } from "./redact.js";
import { renderBook, type RenderJob } from "./render.js";
import { structureRender, type StructureJob } from "./structure.js";
import { transcribeEntry, type TranscribeJob } from "./transcribe.js";

/**
 * Branche les quatre étapes du pipeline sur la file. À appeler avant
 * `queue.start()`, aussi bien dans le serveur que dans le worker dédié.
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
}

export { JOB_NAMES };
export type { RedactJob, RenderJob, StructureJob, TranscribeJob };
