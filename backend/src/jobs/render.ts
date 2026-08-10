import type { AppContext } from "../context.js";
import type { BookPayload } from "../services/structuring.js";

export interface RenderJob {
  renderId: string;
}

/**
 * Étape 3 : le payload part chez APITemplate.io, qui compose le PDF avec le
 * template HTML/CSS de `templates/travel-journal/`. On stocke l'URL du PDF et
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
    throw new Error(message);
  }

  try {
    const result = await renderer.render(render.payload as BookPayload);

    await prisma.render.update({
      where: { id: renderId },
      data: {
        status: "ready",
        pdfUrl: result.pdfUrl,
        apitemplateTransactionId: result.transactionId,
        error: null,
      },
    });

    logger.info({ renderId, pdfUrl: result.pdfUrl }, "Carnet généré");
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    throw cause;
  }
}
