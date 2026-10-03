import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type RedactJob, type TranscribeJob } from "../jobs/index.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { lockThread } from "../services/conversationThread.js";
import {
  chargeDailyCredit,
  countCharacters,
  exceedsDailyCredit,
  loadSpeaker,
  measureVoiceMs,
  readDailyCredit,
  refuseForDailyCredit,
  withDailyCredit,
} from "../services/dailyCredit.js";
import { finalTextOf } from "../jobs/redact.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { loadVisibleMemo } from "./memos.js";
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
   *
   * **La route ancienne** — l'écran d'un carnet hors du chat l'appelle encore.
   * Elle se décompte du crédit du jour comme le chat (Hugo, 03/10/2026) : un
   * texte ses caractères, un vocal sa durée mesurée, une photo rien. Sans ça,
   * elle aurait été la porte de derrière des 5 minutes. Pas d'identifiant
   * client ici, donc pas d'idempotence : un envoi rejoué compte deux fois,
   * comme il écrit deux souvenirs.
   *
   * **Aucun client ne garde ici un tour refusé** : l'écran du carnet affiche
   * le message et lâche l'enregistrement, et aucune file ne passe par cette
   * route. Son refus ne promet donc jamais « il partira demain »
   * (`holdsTurn: false`), même avec `X-Time-Zone`.
   */
  app.post("/v1/memos/:id/entries", async (request, reply) => {
    const { id: memoId } = memoIdParams.parse(request.params);
    const accountId = accountIdOf(request);
    await loadVisibleMemo(context, request, memoId);
    const now = new Date();
    const refusal = { holdsTurn: false };

    if (!request.isMultipart()) {
      const body = textEntryBody.parse(request.body ?? {});
      const speaker = await loadSpeaker(context.prisma, accountId, now);

      // Le décompte dans la transaction qui écrit le souvenir, sous le verrou
      // du voyage — voir `services/dailyCredit.ts`.
      const entry = await withDailyCredit(context.prisma, memoId, refusal, () =>
        context.prisma.$transaction(async (tx) => {
          await lockThread(tx, memoId);
          const created = await tx.entry.create({
            data: {
              memoId,
              kind: "text",
              status: "ready",
              transcript: body.transcript,
              capturedAt: body.capturedAt ?? now,
              placeLabel: body.placeLabel ?? null,
            },
          });
          await chargeDailyCredit(tx, {
            memoId,
            ...speaker,
            charge: { kind: "text", characters: countCharacters(body.transcript) },
            now,
          });
          return created;
        }),
      );

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

    // La durée **mesurée** dans le fichier, jamais celle que l'app déclare
    // (`durationSeconds` n'est plus lu) : c'est elle qui se décompte et qui
    // s'affiche. Une photo ne consomme rien.
    const durationMs = isAudio ? measureVoiceMs(buffer) : null;
    const speaker = durationMs === null ? null : await loadSpeaker(context.prisma, accountId, now);
    if (durationMs !== null && speaker) {
      // Un vocal refusé ne se stocke pas.
      const before = await readDailyCredit(context.prisma, {
        memoId,
        viewer: speaker.account,
        isUnlimited: speaker.isUnlimited,
        now,
      });
      const charge = { kind: "voice" as const, durationMs };
      if (exceedsDailyCredit(before, charge)) {
        await refuseForDailyCredit(context.prisma, memoId, before, charge, { ...refusal, now });
      }
    }

    const stored = await context.storage.put(
      isAudio ? "audio" : "photo",
      file.filename,
      buffer,
      mimeType,
    );

    const entry = await withDailyCredit(context.prisma, memoId, refusal, () =>
      context.prisma.$transaction(async (tx) => {
        await lockThread(tx, memoId);
        const created = await tx.entry.create({
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
                durationSeconds: durationMs === null ? null : durationMs / 1000,
              },
            },
          },
          include: { media: true },
        });
        if (durationMs !== null && speaker) {
          await chargeDailyCredit(tx, { memoId, ...speaker, charge: { kind: "voice", durationMs }, now });
        }
        return created;
      }),
    );

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
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
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
   *
   * **Ce qu'une correction ajoute se décompte** du crédit du jour (Hugo,
   * 03/10/2026) : `max(0, nouveau − ancien)` caractères, l'ancien étant le
   * texte que la fiche montrait. Corriger, raccourcir, revenir à la version
   * proposée ne coûtent rien ; récrire un récit deux fois plus long au clavier,
   * si — sinon le clavier contournerait les 5 minutes.
   */
  app.patch("/v1/entries/:id", async (request) => {
    const { id } = entryIdParams.parse(request.params);
    const body = updateEntryBody.parse(request.body ?? {});
    const accountId = accountIdOf(request);
    const now = new Date();

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: visibleToAccount(accountId) },
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
    // Le compte qui corrige se lit **avant** la transaction, dès qu'un texte
    // arrive : on ne sait pas encore s'il grandit — ça se tranche sous le
    // verrou.
    const speaker = hasNewText ? await loadSpeaker(context.prisma, accountId, now) : null;

    // Une correction a ses propres phrases, qui ne promettent aucun renvoi :
    // aucune file ne la garde.
    const updated = await withDailyCredit(context.prisma, entry.memoId, { holdsTurn: false }, () =>
      context.prisma.$transaction(async (tx) => {
        await lockThread(tx, entry.memoId);
        // **La croissance se mesure sous le verrou du voyage** (03/10/2026),
        // contre le texte tel qu'il est maintenant : deux corrections envoyées
        // au même instant (deux appareils, un renvoi après un délai réseau) ne
        // paient plus chacune contre le même ancien texte. La seconde ne paie
        // que ce qu'elle ajoute à la première — rien, si c'est la même.
        const current = hasNewText ? await tx.entry.findUniqueOrThrow({ where: { id } }) : null;
        const growth = current
          ? Math.max(0, countCharacters(body.editedText ?? "") - countCharacters(finalTextOf(current) ?? ""))
          : 0;
        const saved = await tx.entry.update({
          where: { id },
          data: {
            ...(hasNewText ? { editedText: body.editedText, editedAt: now } : {}),
            ...(clearsEdit ? { editedText: null, editedAt: null } : {}),
            ...(body.placeLabel !== undefined ? { placeLabel: body.placeLabel } : {}),
            ...(body.suggestedTitle !== undefined ? { suggestedTitle: body.suggestedTitle } : {}),
            ...(body.weatherKey !== undefined ? { weatherKey: body.weatherKey } : {}),
          },
          include: { media: true },
        });
        if (speaker && growth > 0) {
          await chargeDailyCredit(tx, {
            memoId: entry.memoId,
            ...speaker,
            charge: { kind: "text", characters: growth, correction: true },
            now,
          });
        }
        return saved;
      }),
    );

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
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
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

    // Une rédaction déjà en file ou en cours ne se relance pas : chaque
    // relance est un appel d'IA payé, et dix touches rapides en mettaient dix
    // en file. La bascule est atomique — deux requêtes simultanées n'en
    // lancent qu'une.
    const claimed = await context.prisma.entry.updateMany({
      where: { id, redactionStatus: { in: ["ready", "failed"] } },
      data: { redactionStatus: "pending", redactionError: null },
    });
    if (claimed.count === 0) {
      return reply.code(200).send(serializeEntry(entry));
    }

    const queued = await context.prisma.entry.findUniqueOrThrow({
      where: { id },
      include: { media: true },
    });

    await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId: id });

    return reply.code(202).send(serializeEntry(queued));
  });

  app.delete("/v1/entries/:id", async (request, reply) => {
    const { id } = entryIdParams.parse(request.params);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
      select: { id: true },
    });

    if (!entry) throw HttpError.notFound("Entrée introuvable.");

    await context.prisma.entry.delete({ where: { id } });
    return reply.code(204).send();
  });

  /**
   * « Ça me convient » — `docs/conversation.md` § 6. Le souvenir est relu et
   * gardé tel quel. Idempotent : valider deux fois ne pose la date qu'une fois.
   *
   * La route du chat l'appelle elle-même quand la puce arrive en message ; elle
   * existe aussi seule pour que l'aperçu du carnet puisse valider une fiche.
   */
  app.post("/v1/entries/:id/validate", async (request) => {
    const { id } = entryIdParams.parse(request.params);
    const accountId = accountIdOf(request);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: visibleToAccount(accountId) },
      select: { id: true, kind: true },
    });
    if (!entry) throw HttpError.notFound("Entrée introuvable.");
    if (entry.kind === "photo") throw HttpError.badRequest("Une photo n'a rien à valider.");

    await context.prisma.entry.updateMany({
      where: { id, validatedAt: null },
      data: { validatedAt: new Date() },
    });
    const validated = await context.prisma.entry.findUniqueOrThrow({
      where: { id },
      include: { media: true },
    });

    return { entry: serializeEntry(validated) };
  });

  /**
   * Le fichier d'un souvenir — le vocal à réécouter depuis un autre appareil,
   * la photo d'une bulle. Servi **avec la session**, à ceux qui voient le
   * carnet : l'app le télécharge par son client, pas par une URL nue. Mise en
   * cache privée et longue : un média ne change jamais sous sa clé.
   */
  app.get("/v1/entries/:id/media", async (request, reply) => {
    const { id } = entryIdParams.parse(request.params);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: visibleToAccount(accountIdOf(request)) },
      include: { media: true },
    });
    if (!entry?.media) throw HttpError.notFound("Média introuvable.");

    let body: Buffer;
    try {
      body = await context.storage.get(entry.media.storageKey);
    } catch {
      throw HttpError.notFound("Média introuvable.");
    }

    return reply
      .header("Cache-Control", "private, max-age=2592000, immutable")
      .type(entry.media.mimeType)
      .send(body);
  });
}
