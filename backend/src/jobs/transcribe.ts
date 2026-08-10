import type { AppContext } from "../context.js";

export interface TranscribeJob {
  entryId: string;
}

/**
 * Étape 1 du pipeline : l'audio devient du texte.
 * L'entrée passe `processing` → `ready`, ou `failed` avec le message d'erreur
 * que l'app affichera.
 */
export async function transcribeEntry(
  context: AppContext,
  { entryId }: TranscribeJob,
): Promise<void> {
  const { prisma, storage, transcriber, logger } = context;

  const entry = await prisma.entry.findUnique({
    where: { id: entryId },
    include: { media: true },
  });

  if (!entry) {
    logger.warn({ entryId }, "Entrée introuvable, job de transcription ignoré");
    return;
  }

  if (entry.kind !== "audio" || !entry.media) {
    // Texte et photo n'ont rien à transcrire : ils sont exploitables tels quels.
    await prisma.entry.update({
      where: { id: entryId },
      data: { status: "ready", error: null },
    });
    return;
  }

  await prisma.entry.update({
    where: { id: entryId },
    data: { status: "processing", error: null },
  });

  try {
    const audio = await storage.get(entry.media.storageKey);
    const result = await transcriber.transcribe({
      audio,
      filename: entry.media.storageKey.split("/").pop() ?? "memo.m4a",
      mimeType: entry.media.mimeType,
    });

    await prisma.entry.update({
      where: { id: entryId },
      data: { transcript: result.text, status: "ready", error: null },
    });

    if (result.durationSeconds !== undefined) {
      await prisma.mediaAsset.update({
        where: { id: entry.media.id },
        data: { durationSeconds: result.durationSeconds },
      });
    }

    logger.info({ entryId, characters: result.text.length }, "Entrée transcrite");
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.entry.update({
      where: { id: entryId },
      data: { status: "failed", error: message },
    });
    // Relancé pour que pg-boss compte la tentative et applique son backoff.
    throw cause;
  }
}
