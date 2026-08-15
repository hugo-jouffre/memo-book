import type { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import {
  EMPTY_COHERENCE_SHEET,
  type CoherenceSheet,
  type RedactedNeighbour,
} from "../services/redaction.js";

export interface RedactJob {
  entryId: string;
}

/** Le texte qui fait foi pour une entrée : la correction de l'utilisateur d'abord. */
export function finalTextOf(entry: {
  editedText: string | null;
  redactedText: string | null;
  transcript: string | null;
}): string | null {
  return entry.editedText ?? entry.redactedText ?? entry.transcript;
}

/**
 * La fiche de cohérence stockée est du JSON libre côté base : elle est relue
 * ici de façon défensive. Une fiche corrompue par une ancienne version du
 * schéma ne doit pas bloquer la rédaction — on repart d'une fiche vide plutôt
 * que de faire échouer le souvenir.
 */
export function parseCoherenceSheet(value: unknown): CoherenceSheet {
  if (!value || typeof value !== "object") return EMPTY_COHERENCE_SHEET;
  const candidate = value as Partial<CoherenceSheet>;

  return {
    people: Array.isArray(candidate.people) ? candidate.people : [],
    places: Array.isArray(candidate.places) ? candidate.places : [],
    lexicon: Array.isArray(candidate.lexicon) ? candidate.lexicon : [],
    narration:
      candidate.narration && typeof candidate.narration === "object"
        ? candidate.narration
        : EMPTY_COHERENCE_SHEET.narration,
    figures: Array.isArray(candidate.figures) ? candidate.figures : [],
  };
}

/**
 * Étape 2 : la transcription brute devient un texte de carnet.
 *
 * Le job est **sérialisé par carnet** de fait : il lit la fiche de cohérence,
 * rédige, puis la réécrit. Deux souvenirs enregistrés coup sur coup partent
 * donc l'un après l'autre dans la file — c'est voulu, la cohérence dépend de
 * l'ordre. C'est aussi pour ça que le job ne se contente pas de la
 * transcription : il reçoit les étapes déjà validées, qui portent la voix.
 */
export async function redactEntry(
  context: AppContext,
  { entryId }: RedactJob,
): Promise<void> {
  const { prisma, redactor, logger } = context;

  const entry = await prisma.entry.findUnique({
    where: { id: entryId },
    include: { memo: true },
  });

  if (!entry) {
    logger.warn({ entryId }, "Entrée introuvable, job de rédaction ignoré");
    return;
  }

  // Une photo seule n'a rien à rédiger, et un texte déjà corrigé à la main ne
  // doit surtout pas être réécrit par-dessus.
  if (entry.kind === "photo" || !entry.transcript || entry.editedText) {
    await prisma.entry.update({
      where: { id: entryId },
      data: { redactionStatus: "ready", redactionError: null },
    });
    return;
  }

  await prisma.entry.update({
    where: { id: entryId },
    data: { redactionStatus: "processing", redactionError: null },
  });

  try {
    // Les voisines : uniquement celles qui ont un texte abouti. Une étape en
    // cours de transcription n'apprend rien sur la voix du voyageur.
    const earlier = await prisma.entry.findMany({
      where: {
        memoId: entry.memoId,
        kind: { not: "photo" },
        capturedAt: { lt: entry.capturedAt },
      },
      orderBy: { capturedAt: "asc" },
    });

    const previous: RedactedNeighbour[] = earlier.flatMap((neighbour) => {
      const text = neighbour.editedText ?? neighbour.redactedText;
      if (!text) return [];
      return [
        {
          capturedAt: neighbour.capturedAt,
          placeLabel: neighbour.placeLabel,
          title: neighbour.suggestedTitle,
          text,
        },
      ];
    });

    const result = await redactor.redact({
      memo: {
        title: entry.memo.title,
        subtitle: entry.memo.subtitle,
        authors: entry.memo.authors,
        theme: entry.memo.theme,
        styleKey: entry.memo.styleKey,
      },
      entry: {
        transcript: entry.transcript,
        capturedAt: entry.capturedAt,
        placeLabel: entry.placeLabel,
      },
      coherenceSheet: parseCoherenceSheet(entry.memo.coherenceSheet),
      previous,
    });

    // La fiche et le texte sont écrits ensemble : une fiche mise à jour pour
    // un texte qui n'a pas été enregistré ferait dériver toutes les étapes
    // suivantes.
    await prisma.$transaction([
      prisma.entry.update({
        where: { id: entryId },
        data: {
          redactedText: result.text,
          suggestedTitle: result.title,
          weatherKey: result.weatherKey,
          funFact: result.funFact,
          funFactTitle: result.funFactTitle,
          redactionStatus: "ready",
          redactionModel: result.model,
          redactedAt: new Date(),
          redactionError: null,
        },
      }),
      prisma.memo.update({
        where: { id: entry.memoId },
        data: { coherenceSheet: result.coherenceSheet as unknown as Prisma.InputJsonObject },
      }),
    ]);

    logger.info(
      { entryId, model: result.model, characters: result.text.length },
      "Souvenir rédigé",
    );
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.entry.update({
      where: { id: entryId },
      data: { redactionStatus: "failed", redactionError: message },
    });
    throw cause;
  }
}
