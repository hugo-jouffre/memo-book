import type { AppContext } from "../context.js";
import {
  chargeTranscriptOverrun,
  countCharacters,
  loadSpeaker,
  transcriptOverrunMs,
} from "../services/dailyCredit.js";
import type { ConverseJob } from "./converse.js";
import { JOB_NAMES } from "./queue.js";
import { transcriptionHintFor, withoutHintEcho } from "../services/transcription.js";
import { parseTripContext } from "../services/tripContext.js";
import { ENTRY_FOR_REDACTION, narratorOf, parseCoherenceSheet, type RedactJob } from "./redact.js";

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
    include: { ...ENTRY_FOR_REDACTION, media: true },
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
    // Les noms que le carnet connaît déjà : la machine les épelle alors comme
    // lui, au lieu d'écrire « Famine » pour Fanny.
    const narrator = await narratorOf(context, entry);
    const sheet = parseCoherenceSheet(entry.memo.coherenceSheet);
    const hint = transcriptionHintFor({
      narrator: narrator.firstName,
      companions: [
        ...narrator.companions,
        ...(parseTripContext(entry.memo.tripContext)?.companions.map((companion) => companion.name) ?? []),
      ],
      destination: entry.memo.destinationCity ?? entry.memo.destinationName,
      people: sheet.people.map((person) => person.canonicalName),
      // Dans l'ordre d'apparition, l'étape en cours en dernier : l'indice
      // garde les plus récents quand il faut couper.
      places: [...sheet.places.map((place) => place.canonicalName), entry.step?.placeName ?? null].filter(
        (place): place is string => Boolean(place),
      ),
    });
    const result = await transcriber.transcribe({
      audio,
      filename: entry.media.storageKey.split("/").pop() ?? "memo.m4a",
      mimeType: entry.media.mimeType,
      hint,
    });

    const transcript = withoutHintEcho(result.text, hint);
    if (transcript !== result.text) {
      logger.warn({ entryId }, "Le transcripteur a recopié son indice : retiré de la transcription");
    }

    await prisma.entry.update({
      where: { id: entryId },
      data: { transcript, status: "ready", error: null },
    });

    // La durée **mesurée à l'arrivée** fait foi (`lib/mp4Duration.ts`) : c'est
    // elle qui a été décomptée du crédit du jour, et la bulle l'affiche. Le
    // transcripteur ne comble qu'un vide — un souvenir d'avant la mesure — et
    // n'écrase jamais ce qu'on a lu dans le fichier (le simulé rend 12 s pour
    // tout, Hugo, 03/10/2026).
    if (result.durationSeconds !== undefined && entry.media.durationSeconds === null) {
      await prisma.mediaAsset.update({
        where: { id: entry.media.id },
        data: { durationSeconds: result.durationSeconds },
      });
    }

    logger.info({ entryId, characters: transcript.length }, "Entrée transcrite");

    // Le filet du crédit du jour — **une fois** : un rejeu de ce job (une
    // publication ratée plus bas) trouve la transcription déjà posée, et ne
    // décompte pas l'écart une seconde fois.
    if (entry.transcript === null) await chargeTranscriptOverrunOf(context, entry, transcript);

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

/**
 * **Le filet du crédit du jour** (03/10/2026) : une transcription bien plus
 * longue que le vocal mesuré trahit un fichier dont la durée ne dit pas ce
 * qu'il contient (`lib/mp4Duration.ts` ne voit que le conteneur). L'écart se
 * décompte du voyage, sans rien refuser — le souvenir est déjà là —, et se
 * journalise : une durée forgée devient visible, et payée.
 *
 * Celui qui a parlé est l'auteur de la bulle du vocal ; un vocal posté hors
 * du chat (`POST /v1/memos/:id/entries`) n'en a pas, et l'écart n'est alors
 * que journalisé. Ne lève jamais : une panne ici ne doit pas faire rejouer la
 * transcription, qui se paie.
 */
async function chargeTranscriptOverrunOf(
  context: AppContext,
  entry: { id: string; memoId: string; media: { durationSeconds: number | null } | null },
  transcript: string,
): Promise<void> {
  const { prisma, logger } = context;
  const seconds = entry.media?.durationSeconds;
  if (seconds === null || seconds === undefined) return;

  const measuredMs = Math.round(seconds * 1000);
  const characters = countCharacters(transcript);
  const overrunMs = transcriptOverrunMs({ characters, measuredMs });
  if (overrunMs === 0) return;

  const facts = { entryId: entry.id, memoId: entry.memoId, measuredMs, characters, overrunMs };
  try {
    const voice = await prisma.chatMessage.findFirst({
      where: { entryId: entry.id, author: "traveller", kind: "voice" },
      select: { accountId: true },
    });
    if (!voice?.accountId) {
      logger.warn(facts, "Transcription bien plus longue que le vocal mesuré, sans auteur connu : rien décompté");
      return;
    }
    const speaker = await loadSpeaker(prisma, voice.accountId);
    const credit = await chargeTranscriptOverrun(prisma, { memoId: entry.memoId, ...speaker, overrunMs });
    logger.warn(
      { ...facts, accountId: voice.accountId, isUnlimited: speaker.isUnlimited, usedMs: credit?.usedMs ?? null },
      speaker.isUnlimited
        ? "Transcription bien plus longue que le vocal mesuré, d'un abonné : rien à décompter"
        : "Transcription bien plus longue que le vocal mesuré : l'écart est décompté du crédit du jour",
    );
  } catch (cause) {
    logger.error({ ...facts, err: cause }, "Transcription bien plus longue que le vocal mesuré : écart non décompté");
  }
}
