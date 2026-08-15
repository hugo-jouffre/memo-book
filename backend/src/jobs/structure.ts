import type { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import { validatePayload } from "../services/payloadValidator.js";
import type { StructuringEntry } from "../services/structuring.js";
import { JOB_NAMES } from "./queue.js";
import { finalTextOf } from "./redact.js";
import type { RenderJob } from "./render.js";

export interface StructureJob {
  renderId: string;
}

/**
 * Étape 3 : les textes validés deviennent un payload de carnet conforme au
 * schéma de `templates/travel-journal/`. Le payload est validé ici, avant
 * d'atteindre APITemplate — un payload hors limites produit un PDF qui déborde
 * de la page, ce qui ne se voit qu'à l'impression.
 *
 * Cette étape ne réécrit rien : elle arrange. Le texte lui arrive fini de
 * l'étape de rédaction, éventuellement corrigé à la main par le voyageur.
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
        // `finalTextOf` fait la hiérarchie : correction manuelle, puis texte
        // rédigé, puis transcription brute en dernier recours (rédaction
        // échouée — mieux vaut un carnet au texte imparfait qu'un carnet vide).
        transcript: finalTextOf(entry),
        editedByUser: entry.editedText !== null,
        title: entry.suggestedTitle,
        funFact: entry.funFact,
        funFactTitle: entry.funFactTitle,
        weatherKey: entry.weatherKey,
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

    // Un souvenir encore en cours de rédaction entrerait dans le PDF avec sa
    // transcription brute — hésitations comprises. L'app empêche déjà ce cas ;
    // le job le revérifie parce qu'un worker peut reprendre un job enfilé
    // avant qu'une nouvelle entrée n'arrive.
    const pending = memo.entries.filter(
      (entry) =>
        entry.kind !== "photo" &&
        (entry.redactionStatus === "pending" || entry.redactionStatus === "processing"),
    );

    if (pending.length > 0) {
      throw new Error(
        `${pending.length} souvenir(s) sont encore en cours de rédaction. ` +
          "Attends qu'ils soient prêts avant de générer le carnet.",
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
