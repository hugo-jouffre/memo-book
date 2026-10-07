import type { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import { validatePayload } from "../services/payloadValidator.js";
import type { StructuringEntry } from "../services/structuring.js";
import { parseTripContext } from "../services/tripContext.js";
import { refreshTripFactsQuietly } from "../services/tripFacts.js";
import { JOB_NAMES } from "./queue.js";
import { finalTextOf } from "./redact.js";
import type { RenderJob } from "./render.js";

export interface StructureJob {
  renderId: string;
}

/**
 * Combien de temps la mise en page attend les souvenirs encore en rédaction,
 * et à quel pas elle regarde. Une variable et non une constante : les tests la
 * raccourcissent.
 *
 * **Attendre plutôt qu'échouer** (07/10/2026) : l'aperçu lance désormais une
 * composition à chaque ouverture (T224), y compris trente secondes après le
 * dernier vocal, quand MEMO n'a pas fini de l'écrire. Échouer aussitôt
 * laissait l'aperçu sur « La composition n'a pas abouti » pour un souvenir
 * qui serait prêt dans l'instant ; trois minutes couvrent une rédaction lente.
 */
export const STRUCTURE_TIMING = { redactionWaitMs: 3 * 60 * 1000, pollMs: 5_000 };

/** Les souvenirs de ce carnet que la rédaction n'a pas encore rendus. */
export function pendingRedactionCount(
  prisma: AppContext["prisma"],
  memoId: string,
): Promise<number> {
  return prisma.entry.count({
    where: { memoId, kind: { not: "photo" }, redactionStatus: { in: ["pending", "processing"] } },
  });
}

async function waitForRedactions(prisma: AppContext["prisma"], memoId: string): Promise<number> {
  const deadline = Date.now() + STRUCTURE_TIMING.redactionWaitMs;
  let pending = await pendingRedactionCount(prisma, memoId);
  while (pending > 0 && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, STRUCTURE_TIMING.pollMs));
    pending = await pendingRedactionCount(prisma, memoId);
  }
  return pending;
}

/**
 * Étape 3 : les textes validés deviennent un payload de carnet conforme au
 * schéma de `MemoBook Generator/templates/travel-journal/`. Le payload est validé ici, avant
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

  const found = await prisma.render.findUnique({ where: { id: renderId }, select: { memoId: true } });

  if (!found) {
    logger.warn({ renderId }, "Rendu introuvable, job de structuration ignoré");
    return;
  }

  await prisma.render.update({
    where: { id: renderId },
    data: { status: "processing", error: null },
  });

  try {
    // Les souvenirs encore en rédaction d'abord — voir `STRUCTURE_TIMING`.
    // Le carnet se relit **après** l'attente : ce sont leurs textes finis qu'on
    // veut.
    await waitForRedactions(prisma, found.memoId);
    // Les chiffres du dos de couverture à jour avant de composer — les jours
    // d'un voyage en cours avancent sans qu'aucun souvenir n'arrive (T227).
    await refreshTripFactsQuietly(context, found.memoId);

    const memo = await prisma.memo.findUniqueOrThrow({
      where: { id: found.memoId },
      include: {
        entries: {
          orderBy: { capturedAt: "asc" },
          include: { media: true },
        },
      },
    });

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
    // transcription brute — hésitations comprises. Après trois minutes
    // d'attente, on renonce plutôt que de l'imprimer tel quel.
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
      tripContext: parseTripContext(memo.tripContext),
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
      // `composingStartedAt` : la phase « composing » de l'aperçu commence.
      data: { payload: payload as Prisma.InputJsonObject, composingStartedAt: new Date() },
    });

    await queue.publish<RenderJob>(JOB_NAMES.render, { renderId });
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.render.update({
      where: { id: renderId },
      data: { status: "failed", error: message },
    });
    // **Pas de nouvel essai automatique** (07/10/2026) : pg-boss rejouait le
    // job trois fois, et un nouvel essai repassait le rendu de « échoué » à
    // « en cours » sous les yeux de l'aperçu — pendant que la prochaine
    // ouverture en lançait un autre, deux compositions payées pour une. C'est
    // désormais l'ouverture suivante de l'aperçu qui relance
    // (`ensureRenderInProgress`). Le journal garde l'erreur.
    logger.error({ err: cause, renderId }, "Mise en page du carnet échouée");
  }
}
