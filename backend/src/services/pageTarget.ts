/**
 * Le nombre de pages cible : ce que la rédaction en fait, et combien de fois
 * on peut le changer.
 *
 * **La cible règle la densité du récit, pas la mise en page.** Le texte d'une
 * étape est écrit une fois, à la rédaction ; c'est donc là que la cible doit
 * peser. Un récit « Compact » prend des tailles d'étape plus courtes, un récit
 * « Détaillé » des plus longues — toujours dans le barème S / M / L / XL et
 * jamais au-delà de ce que le vocal raconte (§ 9 de
 * `agents/agent-transcription.md` : on ne gonfle pas). Le carnet visé tient
 * dans la cible à ± 5 pages (`PAGE_TARGET_TOLERANCE`).
 *
 * **Deux changements par voyage** (Hugo, 15/10/2026). Chaque changement ouvre
 * le droit de réécrire les étapes déjà rédigées à la nouvelle densité — tout
 * le carnet repasse par l'IA, ce qui coûte. Un changement ne compte qu'à partir
 * du moment où une étape est écrite : avant, il n'y a rien à homogénéiser, et
 * régler sa cible le premier soir n'est pas un changement.
 */

import type { PrismaClient } from "@prisma/client";

export const PAGE_TARGET_CHANGE_LIMIT = 2;

/** L'écart toléré entre le carnet composé et sa cible, dans chaque sens. */
export const PAGE_TARGET_TOLERANCE = 5;

/** Sans durée connue — pas de date de fin —, le palier « Par défaut » vise 60 pages. */
const DEFAULT_STANDARD_PAGES = 60;

const DAY_MS = 24 * 60 * 60 * 1000;

const roundedToTen = (value: number) => Math.round(value / 10) * 10;

/**
 * Les pages du palier « Par défaut » pour un voyage de `days` jours. Recopie
 * de `BookPageTarget.standardPageCount` (app) : une page par jour, à la
 * dizaine, entre 30 et 180.
 */
export function standardPageCount(days: number | null): number {
  if (!days || days <= 0) return DEFAULT_STANDARD_PAGES;
  return Math.min(Math.max(roundedToTen(days), 30), 180);
}

/** Les jours du voyage, bornes comprises. `null` sans date de fin : on ne sait pas encore. */
export function tripDays(startDate: Date | null, endDate: Date | null): number | null {
  if (!startDate || !endDate) return null;
  return Math.max(1, Math.round((endDate.getTime() - startDate.getTime()) / DAY_MS) + 1);
}

export type PageDensity = "compact" | "standard" | "detailed";

/**
 * La densité que la cible demande, lue par rapport au palier « Par défaut »
 * du voyage. Les paliers de l'app sont à ×2/3 et ×4/3 ; une cible
 * personnalisée tombe dans le plus proche.
 */
export function pageDensity(targetPageCount: number, days: number | null): PageDensity {
  const ratio = targetPageCount / standardPageCount(days);
  if (ratio <= 5 / 6) return "compact";
  if (ratio >= 7 / 6) return "detailed";
  return "standard";
}

/** Ce que la rédaction lit de la cible, en une ligne de consigne. */
export function pageDensityInstruction(targetPageCount: number, days: number | null): string {
  const lo = Math.max(16, targetPageCount - PAGE_TARGET_TOLERANCE);
  const hi = targetPageCount + PAGE_TARGET_TOLERANCE;
  const cible = `Nombre de pages cible du carnet : ${targetPageCount} (entre ${lo} et ${hi})`;
  switch (pageDensity(targetPageCount, days)) {
    case "compact":
      return `${cible} — récit **compact** : prends la plus petite taille qui garde le cœur de l'étape (S ou M le plus souvent, L pour une étape qui porte le voyage, jamais XL). Garde le cœur, laisse les détails secondaires.`;
    case "detailed":
      return `${cible} — récit **détaillé** : quand le vocal a la matière, prends la taille au-dessus (L ou XL) et garde les détails, les noms, les petites scènes. Sans matière, reste court : on ne gonfle jamais.`;
    default:
      return `${cible} — récit **par défaut** : la taille que la matière du vocal demande, sans tirer vers le court ni vers le long.`;
  }
}

/** Une étape au moins est rédigée : un changement de cible compte, et la réécriture a un sens. */
export async function hasWrittenStory(prisma: PrismaClient, memoId: string): Promise<boolean> {
  const written = await prisma.entry.findFirst({
    where: { memoId, kind: { not: "photo" }, redactedText: { not: null } },
    select: { id: true },
  });
  return written !== null;
}

/** Ce que l'app lit pour annoncer, avant de changer, combien de changements restent. */
export function pageTargetChangesLeft(changes: number): number {
  return Math.max(0, PAGE_TARGET_CHANGE_LIMIT - changes);
}
