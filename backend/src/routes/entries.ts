import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type TranscribeJob } from "../jobs/index.js";
import { HttpError } from "../lib/httpError.js";
import { deviceIdOf } from "../plugins/auth.js";
import { loadOwnedMemo } from "./memos.js";
import { serializeEntry } from "./serializers.js";

const memoIdParams = z.object({ id: z.string().uuid() });
const entryIdParams = z.object({ id: z.string().uuid() });

const textEntryBody = z.object({
  kind: z.literal("text"),
  transcript: z.string().min(1, "le texte est requis").max(20_000),
  capturedAt: z.coerce.date().optional(),
  placeLabel: z.string().max(200).optional(),
});

/** Taille maximale d'un média. ~25 Mo couvre un vocal long et une photo pleine résolution. */
const MAX_MEDIA_BYTES = 25 * 1024 * 1024;

const AUDIO_MIME_PREFIX = "audio/";
const IMAGE_MIME_PREFIX = "image/";

export function registerEntryRoutes(app: FastifyInstance, context: AppContext): void {
  /**
   * Deux formats acceptés sur la même route :
   * - `application/json` pour une note écrite ;
   * - `multipart/form-data` pour un vocal ou une photo.
   *
   * L'app enfile l'entrée dès la fin de l'enregistrement ; la transcription se
   * fait en tâche de fond et l'app suit le `status`.
   */
  app.post("/v1/memos/:id/entries", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    await loadOwnedMemo(context, request, memoId);

    if (!request.isMultipart()) {
      const body = textEntryBody.parse(request.body ?? {});
      const entry = await context.prisma.entry.create({
        data: {
          memoId,
          kind: "text",
          status: "ready",
          transcript: body.transcript,
          capturedAt: body.capturedAt ?? new Date(),
          placeLabel: body.placeLabel ?? null,
        },
      });
      return reply.code(201).send(serializeEntry(entry));
    }

    const file = await request.file({ limits: { fileSize: MAX_MEDIA_BYTES } });
    if (!file) throw HttpError.badRequest("Aucun fichier reçu.");

    const buffer = await file.toBuffer();
    if (buffer.byteLength === 0) throw HttpError.badRequest("Le fichier reçu est vide.");

    const mimeType = file.mimetype;
    const isAudio = mimeType.startsWith(AUDIO_MIME_PREFIX);
    const isImage = mimeType.startsWith(IMAGE_MIME_PREFIX);

    if (!isAudio && !isImage) {
      throw HttpError.badRequest(
        `Type de média non supporté : ${mimeType}. Attendu : audio/* ou image/*.`,
      );
    }

    // Les champs texte du multipart arrivent à côté du fichier.
    const fields = file.fields as Record<string, { value?: unknown } | undefined>;
    const rawCapturedAt = fields["capturedAt"]?.value;
    const rawPlaceLabel = fields["placeLabel"]?.value;

    const capturedAt =
      typeof rawCapturedAt === "string" && rawCapturedAt.length > 0
        ? new Date(rawCapturedAt)
        : new Date();

    if (Number.isNaN(capturedAt.getTime())) {
      throw HttpError.badRequest("`capturedAt` n'est pas une date ISO 8601 valide.");
    }

    const stored = await context.storage.put(
      isAudio ? "audio" : "photo",
      file.filename,
      buffer,
      mimeType,
    );

    const entry = await context.prisma.entry.create({
      data: {
        memo: { connect: { id: memoId } },
        kind: isAudio ? "audio" : "photo",
        status: isAudio ? "pending" : "ready",
        capturedAt,
        placeLabel: typeof rawPlaceLabel === "string" ? rawPlaceLabel : null,
        media: {
          create: {
            storageKey: stored.storageKey,
            mimeType: stored.mimeType,
            bytes: stored.bytes,
          },
        },
      },
      include: { media: true },
    });

    if (isAudio) {
      await context.queue.publish<TranscribeJob>(JOB_NAMES.transcribe, {
        entryId: entry.id,
      });
    }

    return reply.code(201).send(serializeEntry(entry));
  });

  app.get("/v1/entries/:id", async (request) => {
    const { id } = entryIdParams.parse(request.params);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: { deviceId: deviceIdOf(request) } },
      include: { media: true },
    });

    if (!entry) throw HttpError.notFound("Entrée introuvable.");
    return serializeEntry(entry);
  });

  app.delete("/v1/entries/:id", async (request, reply) => {
    const { id } = entryIdParams.parse(request.params);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: { deviceId: deviceIdOf(request) } },
      select: { id: true },
    });

    if (!entry) throw HttpError.notFound("Entrée introuvable.");

    await context.prisma.entry.delete({ where: { id } });
    return reply.code(204).send();
  });
}
