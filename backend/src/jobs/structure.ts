import type { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import { validatePayload } from "../services/payloadValidator.js";
import type { StructuringEntry } from "../services/structuring.js";
import { JOB_NAMES } from "./queue.js";
import type { RenderJob } from "./render.js";

export interface StructureJob {
  renderId: string;
}

/**
 * Étape 2 : les transcriptions deviennent un payload de carnet conforme au
 * schéma de `templates/travel-journal/`. Le payload est validé ici, avant
 * d'atteindre APITemplate — un payload hors limites produit un PDF qui déborde
 * de la page, ce qui ne se voit qu'à l'impression.
 */
export async function structureRender(
  context: AppContext,
  { renderId }: StructureJob,
): Promise<void> {
  const { prisma, structurer, publisher, queue, logger } = context;

  const render = await prisma.render.findUnique({
    where: { id: renderId },
    include: {
      memo: {
        include: {
          entries: {
            orderBy: { capturedAt: "asc" },
            include: { media: true },
          },
        },
      },
    },
  });

  if (!render) {
    logger.warn({ renderId }, "Rendu introuvable, job de structuration ignoré");
    return;
  }

  await prisma.render.update({
    where: { id: renderId },
    data: { status: "processing", error: null },
  });

  try {
    const { memo } = render;

    // Les photos doivent être publiques avant le rendu : APITemplate les
    // télécharge lui-même au moment de composer la page.
    const structuringEntries: StructuringEntry[] = [];
    for (const entry of memo.entries) {
      let photoUrl: string | null = null;

      if (entry.kind === "photo" && entry.media) {
        if (entry.media.cdnUrl) {
          photoUrl = entry.media.cdnUrl;
        } else {
          const filename = entry.media.storageKey.split("/").pop() ?? "photo.jpg";
          const sourceUrl = await context.storage.signedReadUrl(entry.media.storageKey);
          const published = await publisher.publish(filename, sourceUrl);
          await prisma.mediaAsset.update({
            where: { id: entry.media.id },
            data: { cdnUrl: published.cdnUrl },
          });
          photoUrl = published.cdnUrl;
        }
      }

      structuringEntries.push({
        kind: entry.kind,
        transcript: entry.transcript,
        capturedAt: entry.capturedAt,
        placeLabel: entry.placeLabel,
        photoUrl,
      });
    }

    if (structuringEntries.length === 0) {
      throw new Error(
        "Ce carnet ne contient encore aucune entrée : enregistre au moins un souvenir avant de le générer.",
      );
    }

    const payload = await structurer.structure({
      title: memo.title,
      subtitle: memo.subtitle,
      authors: memo.authors,
      theme: memo.theme,
      coverPhotoUrl: memo.coverPhotoUrl,
      entries: structuringEntries,
    });

    const validation = validatePayload(payload);
    if (!validation.valid) {
      const details = validation.errors
        .map((issue) => `${issue.path || "(racine)"}: ${issue.message}`)
        .join(" ; ");
      throw new Error(`Le carnet généré ne respecte pas le format attendu — ${details}`);
    }

    for (const warning of validation.warnings) {
      logger.warn({ renderId, ...warning }, "Écart aux bonnes pratiques éditoriales");
    }

    await prisma.render.update({
      where: { id: renderId },
      // `BookPayload` est un `Record<string, unknown>` : Prisma attend son
      // propre type d'entrée JSON, que la validation ci-dessus garantit.
      data: { payload: payload as Prisma.InputJsonObject },
    });

    await queue.publish<RenderJob>(JOB_NAMES.render, { renderId });
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    throw cause;
  }
}
