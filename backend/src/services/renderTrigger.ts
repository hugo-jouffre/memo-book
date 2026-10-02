import type { Render } from "@prisma/client";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type StructureJob } from "../jobs/index.js";

export interface RenderTrigger {
  render: Render;
  /** `false` quand une génération était déjà en cours et a simplement été reprise. */
  created: boolean;
}

/**
 * Démarre une génération du carnet, ou reprend celle déjà en cours.
 *
 * Partagée par `POST /v1/memos/:id/renders` (à la demande) et la validation
 * d'une étape (en fond) : deux déclenchements rapprochés — un appui et une
 * étape validée dans la foulée — ne doivent jamais produire deux PDF facturés.
 * Un `Render` est toujours **créé**, jamais réutilisé au-delà de ce garde-fou :
 * `PrintOrder.renderId` verrouille une commande sur une génération précise
 * (`onDelete: Restrict`), qui ne doit donc jamais être modifiée après coup.
 */
export async function ensureRenderInProgress(
  context: AppContext,
  memoId: string,
): Promise<RenderTrigger> {
  const inFlight = await context.prisma.render.findFirst({
    where: { memoId, status: { in: ["pending", "processing"] } },
    orderBy: { createdAt: "desc" },
  });

  if (inFlight) {
    return { render: inFlight, created: false };
  }

  const render = await context.prisma.render.create({ data: { memoId } });

  await context.queue.publish<StructureJob>(JOB_NAMES.structure, {
    renderId: render.id,
  });

  const current = await context.prisma.render.findUniqueOrThrow({
    where: { id: render.id },
  });

  return { render: current, created: true };
}
