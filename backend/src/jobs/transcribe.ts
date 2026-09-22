import type { AppContext } from "../context.js";
import type { ConverseJob } from "./converse.js";
import { JOB_NAMES } from "./queue.js";
import type { RedactJob } from "./redact.js";

export interface TranscribeJob {
  entryId: string;
  /**
   * Le tour de conversation qui attend cette transcription pour que MEMO
   * réponde. Absent pour un vocal posté hors du chat.
   */
  converseMessageId?: string;
}

/**
 * Étape 1 du pipeline : l'audio devient du texte brut, puis la rédaction est
 * enfilée derrière.
 *
 * L'entrée passe `processing` → `ready`, ou `failed` avec le message d'erreur
 * que l'app affichera. Le `ready` de `status` ne veut dire que « transcrit » :
 * l'app attend en plus `redactionStatus` pour afficher le texte du carnet.
 */
export async function transcribeEntry(
  context: AppContext,
  { entryId, converseMessageId }: TranscribeJob,
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
    // Texte et photo n'ont rien à transcrire : ils sont exploitables tels
    // quels. Une note écrite passe quand même par la rédaction — elle a droit
    // aux mêmes règles de français et à la même cohérence qu'un vocal.
    await prisma.entry.update({
      where: { id: entryId },
      data: { status: "ready", error: null },
    });
    await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId });
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

    await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId });
    // MEMO répond sur la transcription brute, pendant que la rédaction écrit.
    if (converseMessageId) {
      await context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId: converseMessageId });
    }
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.entry.update({
      where: { id: entryId },
      data: { status: "failed", error: message },
    });
    // Un vocal inintelligible fait quand même parler MEMO : il le dit, au
    // lieu de laisser une fiche attendre pour rien.
    if (converseMessageId) {
      await context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId: converseMessageId });
    }
    // Relancé pour que pg-boss compte la tentative et applique son backoff.
    throw cause;
  }
}
