/**
 * Où en est un voyage — **déduit de ses dates, à la lecture**, jamais lu tel
 * quel dans `memos.stage`.
 *
 * La colonne existe, et elle est écrite à la création comme à chaque
 * modification des dates ; mais un voyage se termine par le calendrier, pas
 * par un geste, et personne n'ouvre l'app le jour où sa date de fin passe.
 * Figé en base, `stage` disait donc « en cours » le 16 septembre d'un voyage
 * fini le 15 (Clara, 16/09/2026). Les dates, elles, ne mentent pas : c'est
 * d'elles qu'on lit l'état, et la colonne n'est plus qu'un repli pour un voyage
 * qui n'a aucune date.
 *
 * **Le dernier jour compte en entier.** Un voyage qui finit le 15 est en cours
 * jusqu'au 15 à minuit, pas jusqu'à l'heure où sa date a été saisie : la date
 * de fin arrive à minuit dans le fuseau de l'app, et c'est le lendemain qui
 * ferme le voyage. Même règle pour le départ — un voyage qui commence le 20
 * est en cours dès le 20, à quelque heure qu'on ouvre l'app.
 */

export type TripStage = "ongoing" | "upcoming" | "past";

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * L'état d'un voyage à l'instant `now`.
 *
 * Sans dates du tout, `fallback` — ce que la base a retenu — tranche : un
 * carnet importé ou celui de la galerie peut être « terminé » sans porter une
 * seule date. Sans repli, on suppose qu'il commence maintenant, comme
 * quelqu'un qui ouvre l'app le premier soir.
 */
export function stageFromDates(
  startDate: Date | null | undefined,
  endDate: Date | null | undefined,
  now: Date = new Date(),
  fallback: TripStage = "ongoing",
): TripStage {
  if (!startDate && !endDate) return fallback;
  if (endDate && endDate.getTime() + DAY_MS <= now.getTime()) return "past";
  if (startDate && startDate.getTime() > now.getTime()) return "upcoming";
  return "ongoing";
}

/** Ce qu'il faut d'un carnet pour dire où il en est. */
export type MemoForStage = {
  stage: string;
  startDate: Date | null;
  endDate: Date | null;
};

/** L'état d'un carnet lu en base, ses dates d'abord, sa colonne sinon. */
export function effectiveStage(memo: MemoForStage, now: Date = new Date()): TripStage {
  const stored: TripStage =
    memo.stage === "past" || memo.stage === "upcoming" ? memo.stage : "ongoing";
  return stageFromDates(memo.startDate, memo.endDate, now, stored);
}
