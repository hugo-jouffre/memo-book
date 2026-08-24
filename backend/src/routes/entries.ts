import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type RedactJob, type TranscribeJob } from "../jobs/index.js";
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

const WEATHER_KEYS = ["sun", "sun-wind", "cloud", "rain", "snow"] as const;

/**
 * Correction manuelle. `editedText: null` revient explicitement au texte
 * proposé par la rédaction ; un champ absent laisse la valeur en place.
 */
const updateEntryBody = z.object({
  editedText: z.string().min(1).max(20_000).nullable().optional(),
  placeLabel: z.string().max(200).nullable().optional(),
  suggestedTitle: z.string().max(200).nullable().optional(),
  weatherKey: z.enum(WEATHER_KEYS).nullable().optional(),
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

      // Un souvenir tapé au clavier n'a pas de transcription à faire, mais il a
      // la même rédaction à subir qu'un vocal : sans cette ligne il reste à
      // `redactionStatus: "pending"` — la valeur par défaut en base — et le
      // carnet refuse d'être généré, définitivement. C'est le job de
      // transcription qui enfile la rédaction pour les vocaux ; le texte n'en
      // passant pas par là, personne ne le faisait pour lui.
      await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId: entry.id });

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

  /**
   * Correction manuelle du texte, au clavier depuis l'app.
   *
   * Le texte corrigé est stocké **à côté** du texte rédigé, jamais à sa place :
   * la version du modèle reste consultable, et « revenir à la version
   * proposée » est un simple `null`. À partir de là, la mise en page reprend
   * la correction au mot près.
   */
  app.patch("/v1/entries/:id", async (request) => {
    const { id } = entryIdParams.parse(request.params);
    const body = updateEntryBody.parse(request.body ?? {});

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: { deviceId: deviceIdOf(request) } },
    });
    if (!entry) throw HttpError.notFound("Entrée introuvable.");

    if (entry.kind === "photo") {
      throw HttpError.badRequest("Une photo n'a pas de texte à corriger.");
    }

    // `null` explicite = revenir au texte proposé. Champ absent = ne pas
    // toucher au texte. Les deux se distinguent : `exactOptionalPropertyTypes`
    // n'aiderait pas ici, c'est la sémantique JSON qui compte.
    const clearsEdit = "editedText" in body && body.editedText === null;
    const hasNewText = typeof body.editedText === "string";

    const updated = await context.prisma.entry.update({
      where: { id },
      data: {
        ...(hasNewText ? { editedText: body.editedText, editedAt: new Date() } : {}),
        ...(clearsEdit ? { editedText: null, editedAt: null } : {}),
        ...(body.placeLabel !== undefined ? { placeLabel: body.placeLabel } : {}),
        ...(body.suggestedTitle !== undefined ? { suggestedTitle: body.suggestedTitle } : {}),
        ...(body.weatherKey !== undefined ? { weatherKey: body.weatherKey } : {}),
      },
      include: { media: true },
    });

    return serializeEntry(updated);
  });

  /**
   * Relance la rédaction d'un souvenir : après un échec, ou pour redemander
   * une proposition quand le texte ne plaît pas.
   *
   * Une correction manuelle existante bloque la relance — la réécrire par
   * dessus détruirait le travail de l'utilisateur sans qu'il l'ait demandé.
   * Il doit d'abord revenir à la version proposée (`editedText: null`).
   */
  app.post("/v1/entries/:id/redaction", async (request, reply) => {
    const { id } = entryIdParams.parse(request.params);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: { deviceId: deviceIdOf(request) } },
    });
    if (!entry) throw HttpError.notFound("Entrée introuvable.");

    if (entry.editedText) {
      throw HttpError.badRequest(
        "Ce souvenir a été corrigé à la main. Reviens d'abord à la version proposée " +
          "pour relancer la rédaction.",
        "manually_edited",
      );
    }

    if (!entry.transcript) {
      throw HttpError.badRequest(
        "Ce souvenir n'a pas encore de transcription à rédiger.",
        "not_transcribed",
      );
    }

    if (entry.redactionStatus === "processing") {
      return reply.code(200).send(serializeEntry(entry));
    }

    const queued = await context.prisma.entry.update({
      where: { id },
      data: { redactionStatus: "pending", redactionError: null },
      include: { media: true },
    });

    await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId: id });

    return reply.code(202).send(serializeEntry(queued));
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
