import type { AppContext } from "../context.js";
import type { BookPayload } from "../services/structuring.js";

export interface RenderJob {
  renderId: string;
}

/**
 * Étape 3 : le payload part chez APITemplate.io, qui compose le PDF avec le
 * template HTML/CSS de `MemoBook Generator/templates/travel-journal/`. On stocke l'URL du PDF et
 * la référence de transaction, seule trace exploitable en cas de litige avec
 * le fournisseur.
 */
export async function renderBook(
  context: AppContext,
  { renderId }: RenderJob,
): Promise<void> {
  const { prisma, renderer, logger } = context;

  const render = await prisma.render.findUnique({ where: { id: renderId } });

  if (!render) {
    logger.warn({ renderId }, "Rendu introuvable, job d'impression ignoré");
    return;
  }

  if (!render.payload) {
    const message = "Le rendu n'a pas de payload : l'étape de structuration a échoué.";
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    logger.error({ renderId }, message);
    return;
  }

  try {
    const result = await renderer.render(render.payload as BookPayload);
    const pageCount = composedPageCount(render.payload);

    await prisma.render.update({
      where: { id: renderId },
      data: {
        status: "ready",
        pdfUrl: result.pdfUrl,
        apitemplateTransactionId: result.transactionId,
        pageCount,
        error: null,
      },
    });

    // **Le carnet existe, il s'imprime** (T228) : `isPrintable` n'était écrit
    // que par le jeu d'essai, si bien que l'imprimante des voyages passés de
    // l'accueil n'apparaissait jamais sur un vrai voyage. Et ses pages, que
    // l'accueil et le prix lisent (`billablePages`) — seulement si aucun rendu
    // plus récent n'a déjà parlé.
    const newer = await prisma.render.count({
      where: { memoId: render.memoId, status: "ready", createdAt: { gt: render.createdAt } },
    });
    await prisma.memo.update({
      where: { id: render.memoId },
      data: { isPrintable: true, ...(newer === 0 && pageCount !== null ? { pageCount } : {}) },
    });

    logger.info({ renderId, pdfUrl: result.pdfUrl, pageCount }, "Carnet généré");
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    // Pas de nouvel essai automatique : voir `jobs/structure.ts`.
    logger.error({ err: cause, renderId }, "Composition du PDF échouée");
  }
}

/**
 * Les pages du carnet composé : une par entrée de `days[]` — c'est l'unité de
 * page du gabarit (`services/structuring.ts`). `null` pour un payload qui n'en
 * a pas.
 */
export function composedPageCount(payload: unknown): number | null {
  const days = (payload as { days?: unknown } | null)?.days;
  return Array.isArray(days) ? days.length : null;
}
