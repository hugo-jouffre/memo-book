import type { AppContext } from "../context.js";
import { redactEntry } from "./redact.js";

export interface RewriteTripJob {
  memoId: string;
}

/**
 * Réécrit les étapes déjà écrites d'un voyage à sa cible de pages en cours —
 * le « Étoffer » / « Condenser » qui suit un changement de cible
 * (`services/pageTarget.ts`).
 *
 * **Une à une, dans l'ordre du récit**, et non un job par souvenir : chaque
 * rédaction lit puis réécrit la fiche de cohérence, et lit les étapes d'avant.
 * En parallèle, elles se marcheraient dessus. Un souvenir corrigé à la main
 * n'est pas sélectionné — et `redactEntry` le laisserait de toute façon.
 *
 * Un souvenir qui échoue reste sur son ancien texte (`redactEntry` le marque
 * `failed`) ; les suivants passent quand même.
 */
export async function rewriteTrip(context: AppContext, { memoId }: RewriteTripJob): Promise<void> {
  const { prisma, logger } = context;
  const entries = await prisma.entry.findMany({
    where: {
      memoId,
      kind: { not: "photo" },
      transcript: { not: null },
      editedText: null,
      redactedText: { not: null },
      redactionStatus: { in: ["ready", "failed"] },
    },
    orderBy: { capturedAt: "asc" },
    select: { id: true },
  });

  let failed = 0;
  for (const { id } of entries) {
    try {
      await redactEntry(context, { entryId: id, rewrite: true });
    } catch (cause) {
      failed += 1;
      logger.warn({ memoId, entryId: id, err: cause }, "Réécriture d'une étape échouée");
    }
  }
  logger.info({ memoId, rewritten: entries.length - failed, failed }, "Étapes réécrites à la nouvelle cible");
}
