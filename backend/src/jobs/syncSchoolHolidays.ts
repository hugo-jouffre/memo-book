import type { AppContext } from "../context.js";
import { syncSchoolHolidays as sync } from "../services/schoolHolidays.js";

/**
 * Recopie le calendrier scolaire du ministère — voir
 * `services/schoolHolidays.ts`. Une panne du site n'est pas une panne à
 * retenter trois fois : on garde ce qu'on a, et la passe de demain réessaiera.
 */
export type SyncSchoolHolidaysJob = Record<string, never>;

export async function syncSchoolHolidays(context: AppContext): Promise<void> {
  try {
    const periods = await sync(context);
    context.logger.info({ periods }, "Calendrier scolaire recopié.");
  } catch (cause) {
    context.logger.warn({ err: cause }, "Calendrier scolaire non recopié — on garde celui d'hier.");
  }
}
