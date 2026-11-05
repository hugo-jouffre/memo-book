import type { PrismaClient } from "@prisma/client";
import { photoBudgetFor } from "./photoBudget.js";
import { photosForTarget, tripDays } from "./pageTarget.js";

/**
 * **Combien de photos un récit validé appelle** — et ce que la cible de pages
 * y ajoute.
 *
 * Sorti de `jobs/converse.ts` le 05/11/2026 : depuis que la rédaction valide
 * elle-même le texte et demande ses photos dans la foulée
 * (`confirmRedaction`), deux appelants le lisent, et le job de conversation
 * ne peut plus en être le propriétaire — `conversationThread` l'importerait
 * en cercle.
 */

/** Ce que ce service lit de la base. */
type Db = Pick<PrismaClient, "memo">;

export interface PhotoRequest {
  /** Toutes les photos à demander. */
  photos: number;
  /** Les pages de l'étape, pages de photos de la cible comprises. */
  pages: number;
  /** Les pages de photos que la cible ajoute, et leurs photos (`photosForTarget`). */
  extraPages: number;
  extraPhotos: number;
  targetPageCount: number;
  /** Le carnet est à 0 % : aucune photo ne s'imprime. */
  zeroRatio: boolean;
}

/**
 * Le nombre de photos à demander pour un récit validé, lu au moment où la
 * question se pose — le voyageur peut changer son ratio ou sa cible à tout
 * moment, et l'étape suivante doit en tenir compte :
 *
 * 1. **le ratio** : la part de photos que le récit appelle (`photoBudget.ts`),
 *    avec les fun facts et les décorations ;
 * 2. **la cible** : les pages de photos qu'il manque pour que le carnet
 *    l'atteigne, trois photos chacune (`photosForTarget`, Hugo, 18/10/2026).
 */
export async function photoRequestFor(db: Db, memoId: string, text: string): Promise<PhotoRequest> {
  const memo = await db.memo.findUnique({
    where: { id: memoId },
    select: {
      photoTextRatio: true,
      funFactsEnabled: true,
      decorationQuota: true,
      targetPageCount: true,
      startDate: true,
      endDate: true,
      narrationPace: true,
      _count: { select: { steps: true } },
    },
  });
  const budget = photoBudgetFor(text, memo ?? {});
  const base = { photos: budget.photos, pages: budget.pages, extraPages: 0, extraPhotos: 0 };
  const targetPageCount = memo?.targetPageCount ?? 0;
  if (!memo || budget.photos === 0 || !text) return { ...base, targetPageCount, zeroRatio: budget.ratio === 0 };
  const extra = photosForTarget({
    targetPageCount,
    ratio: budget.ratio,
    days: tripDays(memo.startDate, memo.endDate),
    pace: memo.narrationPace,
    writtenSteps: memo._count.steps,
    stepPages: budget.pages,
  });
  return {
    photos: budget.photos + extra.extraPhotos,
    pages: budget.pages + extra.extraPages,
    ...extra,
    targetPageCount,
    zeroRatio: false,
  };
}

/** Ce que `photosWanted` dit de la cible, quand elle demande des photos en plus. */
export function forTargetOf(request: PhotoRequest) {
  return request.extraPhotos > 0
    ? { photos: request.extraPhotos, pages: request.extraPages, target: request.targetPageCount }
    : null;
}
