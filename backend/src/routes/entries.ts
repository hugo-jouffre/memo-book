import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type RedactJob, type TranscribeJob } from "../jobs/index.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { lockThread } from "../services/conversationThread.js";
import { calendarColumn } from "../services/localCalendar.js";
import {
  CORRECTION_FREE_CHARACTERS,
  chargeDailyCredit,
  correctionCharacters,
  countCharacters,
  exceedsDailyCredit,
  loadSpeaker,
  measureVoiceMs,
  readDailyCredit,
  refuseForDailyCredit,
  withDailyCredit,
} from "../services/dailyCredit.js";
import { finalTextOf, strandedBefore } from "../jobs/redact.js";
import { deleteEntryAndMedia } from "../services/deletion.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { refreshTripFactsQuietly } from "../services/tripFacts.js";
import { isRenderableImage, toRenderablePhoto } from "../services/photoFormat.js";
import { measurePhoto } from "../services/photoOrientation.js";
import { storeScreenThumbnail } from "../services/photoThumbnails.js";
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
  /**
   * **Garder la transcription littérale** plutôt que le texte rédigé (Hugo,
   * 28/10/2026). Ce n'est pas une correction au clavier : ça ne coûte ni
   * caractères offerts ni crédit du jour — voir `entries.prefersTranscript`.
   */
  prefersTranscript: z.boolean().optional(),

  /**
   * **Les jours que ce récit raconte, fixés à la main** (T288) — « changer les
   * dates » de l'appui long sur la fiche. Un jour civil (`2026-11-14`), ou
   * `null` pour **revenir aux dates déduites** : la lecture de la rédaction
   * n'a pas été écrasée, elle reprend la parole.
   *
   * `livedTo` ne vaut que pour une période, et seul `livedFrom` décide : une
   * main qui dit « le 12 seulement » efface la fin que le modèle avait mise.
   */
  livedFrom: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Attendu : AAAA-MM-JJ.")
    .nullable()
    .optional(),
  livedTo: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Attendu : AAAA-MM-JJ.")
    .nullable()
    .optional(),

  /**
   * **Le nom du lieu, écrit à la main** (T288). `null` rend la parole au lieu
   * que les récits de l'étape nomment.
   *
   * Il renomme l'étape sans rien regrouper — voir `entries.pinnedPlaceName`.
   */
  placeName: z.string().max(200).nullable().optional(),
});

/** Le corps d'une correction, tel que la route le lit. */
type UpdateEntryBody = z.infer<typeof updateEntryBody>;

/**
 * **Ce que la main fixe**, prêt pour Prisma (T288).
 *
 * `livedFrom` commande la paire entière : un jour seul efface la fin que la
 * rédaction avait mise, et `null` efface les deux — « revenir aux dates
 * déduites ». Une fin antérieure au départ n'est pas une période : elle tombe.
 */
export function handWrittenFields(body: UpdateEntryBody): {
  pinnedLivedFromDay?: Date | null;
  pinnedLivedToDay?: Date | null;
  pinnedPlaceName?: string | null;
} {
  const fields: {
    pinnedLivedFromDay?: Date | null;
    pinnedLivedToDay?: Date | null;
    pinnedPlaceName?: string | null;
  } = {};

  if (body.livedFrom !== undefined) {
    const from = body.livedFrom ? calendarColumn(body.livedFrom) : null;
    const to = from && body.livedTo ? calendarColumn(body.livedTo) : null;
    fields.pinnedLivedFromDay = from;
    fields.pinnedLivedToDay = to && to > from! ? to : null;
  } else if (body.livedTo !== undefined) {
    // Une fin sans départ ne dit rien : la paire se fixe ensemble.
    fields.pinnedLivedToDay = null;
  }

  if (body.placeName !== undefined) {
    const name = body.placeName?.trim();
    fields.pinnedPlaceName = name ? name : null;
  }

  return fields;
}

/**
 * La correction touche-t-elle au découpage du voyage (T288) ?
 *
 * Les jours et le lieu, oui : c'est `refreshTripFacts` qui les remonte sur
 * l'étape, et c'est l'étape que la fiche affiche. Un texte corrigé, non.
 */
export function changesTripFacts(body: UpdateEntryBody): boolean {
  return body.livedFrom !== undefined || body.livedTo !== undefined || body.placeName !== undefined;
}

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
   * elle aurait été la porte de derrière des 2 minutes. Pas d'identifiant
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
    // Le lieu que la photo porte elle-même, géocodé sur le téléphone (T280).
    // Cette route-ci n'envoie qu'un fichier : un champ simple suffit, là où le
    // fil en reçoit plusieurs et passe par `photos` (`routes/chat.ts`).
    const rawCapturedPlaceName = fields["capturedPlaceName"]?.value;
    const capturedPlaceName =
      typeof rawCapturedPlaceName === "string" && rawCapturedPlaceName.trim()
        ? rawCapturedPlaceName.trim().slice(0, 120)
        : null;

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

    // Une photo entre dans un format que le moteur de PDF sait peindre — le
    // HEIC de la photothèque d'un iPhone n'en est pas un, et il arrive sous un
    // nom en `.jpg` (`services/photoFormat.ts`).
    const photo = isImage ? await toRenderablePhoto(buffer, file.filename, mimeType) : null;
    if (photo && !photo.converted && !isRenderableImage(photo.buffer)) {
      request.log.warn(
        { memoId, mimeType },
        "Photo dans un format que le moteur de PDF ne peint pas, et non convertible",
      );
    }

    const stored = await context.storage.put(
      isAudio ? "audio" : "photo",
      photo?.filename ?? file.filename,
      photo?.buffer ?? buffer,
      photo?.mimeType ?? mimeType,
    );

    // **La mesure de la photo**, sur les octets encore en mémoire : ses
    // dimensions, son sens, sa netteté (T263 pour le sens, T265 pour la
    // netteté). Cette route ne mesurait rien du tout — une photo envoyée par
    // elle n'était donc jamais couverture de voyage, et n'aurait pas eu de
    // rang dans le choix des photos du carnet. `chat.ts` le faisait déjà.
    const measure = photo ? await measurePhoto(photo.buffer) : null;

    // La vignette de l'écran des couvertures, sur les octets encore en
    // mémoire (T260) — voir `services/photoThumbnails.ts`.
    const thumbStorageKey = photo
      ? await storeScreenThumbnail(context, photo.buffer)
      : null;

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
            capturedPlaceName,
            ...(measure
              ? {
                  photoWidthPx: measure.widthPx,
                  photoHeightPx: measure.heightPx,
                  photoIsLandscape: measure.isLandscape,
                  photoSharpness: measure.sharpness,
                  photoVerdict: measure.verdict,
                  photoBlur: measure.blur,
                }
              : {}),
            media: {
              create: {
                storageKey: stored.storageKey,
                mimeType: stored.mimeType,
                bytes: stored.bytes,
                durationSeconds: durationMs === null ? null : durationMs / 1000,
                thumbStorageKey,
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
    } else {
      // Une photo compte tout de suite (T227) ; un vocal, à la fin de sa
      // rédaction — c'est elle qui dit où il se passe.
      await refreshTripFactsQuietly(context, memoId);
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
   * **Ce qu'une correction modifie se mesure** (Hugo, 19/10/2026, QA D8) :
   * les caractères du nouveau texte qui n'étaient pas dans celui que la fiche
   * montrait (`correctionCharacters`) — un nom propre corrigé, un mot
   * remplacé, une phrase retournée. Raccourcir et revenir à la version
   * proposée ne coûtent rien.
   *
   * **Les 200 premiers sont offerts**, par fiche et cumulés
   * (`CORRECTION_FREE_CHARACTERS`, `entries.correctionFreeCharacters`) : pot
   * vide, on corrige encore la fiche que le dernier vocal vient de remplir.
   * Au-delà, la correction paie comme un texte (75 ms par caractère) ; pot
   * vide, elle est refusée en entier — « au-delà de 200 caractères modifiés,
   * la correction passe par l’illimité ». Sinon le clavier contournerait les
   * 2 minutes. Un abonné ne compte rien, et n'entame pas les 200 de ses
   * co-voyageurs.
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
        const changed = current ? correctionCharacters(finalTextOf(current) ?? "", body.editedText ?? "") : 0;
        // Les 200 offerts d'abord — jamais à un abonné, qui ne compte rien.
        const offered =
          current && speaker && !speaker.isUnlimited
            ? Math.min(changed, Math.max(0, CORRECTION_FREE_CHARACTERS - current.correctionFreeCharacters))
            : 0;
        const paid = changed - offered;
        const saved = await tx.entry.update({
          where: { id },
          data: {
            ...(hasNewText ? { editedText: body.editedText, editedAt: now } : {}),
            ...(offered > 0 ? { correctionFreeCharacters: { increment: offered } } : {}),
            ...(clearsEdit ? { editedText: null, editedAt: null } : {}),
            ...(body.prefersTranscript !== undefined
              ? { prefersTranscript: body.prefersTranscript }
              : {}),
            ...(body.placeLabel !== undefined ? { placeLabel: body.placeLabel } : {}),
            // **Ce que la main fixe** (T288), à côté de ce que la rédaction a
            // compris et jamais à sa place. Gratuit : ce n'est ni un texte ni
            // des caractères, c'est une date et un nom — comme
            // `prefersTranscript`, ça ne coûte rien au crédit du jour.
            ...handWrittenFields(body),
            ...(body.suggestedTitle !== undefined ? { suggestedTitle: body.suggestedTitle } : {}),
            ...(body.weatherKey !== undefined ? { weatherKey: body.weatherKey } : {}),
          },
          include: { media: true },
        });
        if (speaker && paid > 0) {
          await chargeDailyCredit(tx, {
            memoId: entry.memoId,
            ...speaker,
            charge: { kind: "text", characters: paid, correction: true },
            now,
          });
        }
        return saved;
      }),
    );

    // **L'étape suit la main** (T288) : c'est `refreshTripFacts` qui remonte
    // les jours et le lieu du souvenir sur son étape, et c'est l'étape que la
    // fiche affiche. Sans ce passage, la correction serait écrite et
    // invisible.
    if (changesTripFacts(body)) await refreshTripFactsQuietly(context, entry.memoId);

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
  /**
   * **La pleine définition d'une photo déjà posée** (T309, 26/11/2026).
   *
   * La conversation reçoit d'abord un **aperçu léger** — 1 200 px, ~230 ko —
   * pour que la bulle arrive en quelques secondes : mesuré le 26/11, six
   * photos en pleine définition font 7,3 Mo, soit 58 s à 1 Mb/s, c'est-à-dire
   * le délai d'abandon du client, qui renvoie alors le tour dans la file
   * (T295). Les mêmes six en léger font 1,4 Mo. Le téléphone garde les vraies
   * octets et les monte ensuite, une photo à la fois, par cette route.
   *
   * Ce qu'elle fait, dans cet ordre : convertir si besoin, ranger le nouveau
   * fichier, **remesurer** (c'est seulement ici que la netteté et le verdict
   * se décident — le laplacien dépend de la définition, et le barème est
   * calibré sur 2400 px), refaire la vignette d'écran, puis effacer l'aperçu.
   *
   * Les copies dérivées tombent avec l'ancien fichier : la copie de rendu et
   * la publication au CDN montraient l'aperçu, et la prochaine composition
   * les refera (même règle que `services/renderPhotos.ts`).
   *
   * Rejouable : une photo déjà en pleine définition accepte un nouvel envoi —
   * le téléphone peut avoir perdu le reçu. Elle n'appartient qu'à qui voit le
   * voyage, comme tout le reste d'un souvenir.
   */
  app.put("/v1/entries/:id/photo", async (request) => {
    const { id } = entryIdParams.parse(request.params);
    const accountId = accountIdOf(request);

    const entry = await context.prisma.entry.findFirst({
      where: { id, memo: visibleToAccount(accountId) },
      include: { media: true },
    });
    if (!entry) throw HttpError.notFound("Entrée introuvable.");
    if (entry.kind !== "photo" || !entry.media) {
      throw HttpError.badRequest("Ce souvenir n'est pas une photo.");
    }

    if (!request.isMultipart()) {
      throw HttpError.badRequest("La pleine définition s'envoie en multipart/form-data.");
    }
    const file = await request.file({ limits: { fileSize: MAX_MEDIA_BYTES } });
    if (!file) throw HttpError.badRequest("Aucun fichier reçu.");
    const buffer = await file.toBuffer();
    const mimeType = file.mimetype || "application/octet-stream";
    if (!mimeType.startsWith(IMAGE_MIME_PREFIX)) {
      throw HttpError.badRequest(`Type de média non supporté : ${mimeType}. Attendu : image/*.`);
    }

    const photo = await toRenderablePhoto(buffer, file.filename, mimeType);
    const stored = await context.storage.put("photo", photo.filename, photo.buffer, photo.mimeType);
    const measure = await measurePhoto(photo.buffer);
    const thumbStorageKey = await storeScreenThumbnail(context, photo.buffer);
    const replaced = entry.media.storageKey;

    const updated = await context.prisma.$transaction(async (tx) => {
      await tx.mediaAsset.update({
        where: { id: entry.media!.id },
        data: {
          storageKey: stored.storageKey,
          mimeType: stored.mimeType,
          bytes: stored.bytes,
          isLightweight: false,
          cdnUrl: null,
          cdnAssetId: null,
          renderStorageKey: null,
          thumbStorageKey,
        },
      });
      return tx.entry.update({
        where: { id: entry.id },
        data: measure
          ? {
              photoWidthPx: measure.widthPx,
              photoHeightPx: measure.heightPx,
              photoIsLandscape: measure.isLandscape,
              photoSharpness: measure.sharpness,
              photoVerdict: measure.verdict,
              photoBlur: measure.blur,
            }
          : {},
      });
    });

    // **Après** la transaction : un fichier effacé ne revient pas, et on ne
    // l'efface qu'une fois la base d'accord. Jamais bloquant — un aperçu qui
    // survit ne coûte que sa place.
    if (replaced !== stored.storageKey) {
      await context.storage.remove([replaced]).catch((cause: unknown) => {
        request.log.warn({ err: cause, storageKey: replaced }, "Aperçu léger non effacé");
      });
    }

    request.log.info(
      { entryId: entry.id, bytes: stored.bytes, verdict: measure?.verdict ?? null },
      "Photo remplacée par sa pleine définition",
    );

    return serializeEntry(updated);
  });

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
    //
    // **Et le choix de garder la littérale tombe** (28/10/2026) : redemander
    // une rédaction, c'est vouloir la lire. Sans ça, la nouvelle version
    // arrivait dans une fiche qui continuait d'afficher — et d'imprimer — le
    // brut, sans que rien ne le dise.
    //
    // **Une épave se reprend quand même** (04/11/2026) : passé
    // `REDACTION_STRANDED_AFTER_MS`, une entrée restée `pending` ou
    // `processing` n'a plus de job derrière elle, et cette garde l'enfermait
    // — elle rendait 200 sans rien faire, si bien que l'app croyait avoir
    // relancé. Trente et une entrées y étaient prises, et avec elles la
    // composition de leurs carnets.
    const claimed = await context.prisma.entry.updateMany({
      where: {
        id,
        OR: [
          { redactionStatus: { in: ["ready", "failed"] } },
          { redactionStatus: { in: ["pending", "processing"] }, updatedAt: { lt: strandedBefore() } },
        ],
      },
      data: { redactionStatus: "pending", redactionError: null, prefersTranscript: false },
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
      select: { id: true, memoId: true },
    });

    if (!entry) throw HttpError.notFound("Entrée introuvable.");

    // Le souvenir **et son fichier** — le vocal, la photo (QA D12) : la ligne
    // du média dans la transaction, le fichier après elle, sans faire
    // échouer la suppression (`services/deletion.ts`).
    await deleteEntryAndMedia(context, id);
    // Les chiffres du voyage reculent, et une étape vidée de son dernier
    // souvenir disparaît (T235, T227) — avant la réponse : l'app relit le
    // voyage aussitôt après la croix.
    await refreshTripFactsQuietly(context, entry.memoId);
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
