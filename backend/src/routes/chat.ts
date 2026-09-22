import { Prisma, type Account } from "@prisma/client";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import type { AppContext } from "../context.js";
import { JOB_NAMES, type ConverseJob, type TranscribeJob } from "../jobs/index.js";
import { HttpError } from "../lib/httpError.js";
import { accountIdOf } from "../plugins/auth.js";
import { publicApiBaseUrl } from "../services/avatars.js";
import { pauseBeforeTranscript, scriptedReply } from "../services/conversation.js";
import { isSilentCommand, isSuggestionId, suggestionIdForLabel } from "../services/conversationCopy.js";
import {
  activeStepOf,
  chatMessageInclude,
  dailyTurnCount,
  ensureOpening,
  findTurnInFlight,
  materializeEntriesWithoutMessages,
  type ChatMessageRow,
} from "../services/conversationThread.js";
import { visibleToAccount } from "../services/memoOwnership.js";
import { TEXT_MEMORY_COST, consumeMemory, voiceCost } from "../services/memoryAllowance.js";
import { assertCanRecord, validateEntry } from "../services/quota.js";
import {
  serializeChatReceipt,
  serializeChatThread,
  serializeChatUpdate,
  type ChatTurnStatus,
  type MemoForChat,
} from "./chatSerializers.js";

/**
 * La conversation avec MEMO — `docs/conversation.md`.
 *
 * Trois routes : lire le fil, y parler, l'effacer. Le fil se lit **au champ
 * près** des modèles Swift (`chatSerializers.ts`) ; y parler écrit le message
 * du voyageur tout de suite et laisse le job `converse` répondre ; l'effacer
 * n'appartient qu'au propriétaire.
 *
 * L'accès passe par `visibleToAccount` : un co-voyageur lit et parle comme le
 * propriétaire, quelqu'un qui n'y participe pas reçoit un 404.
 */

const idParams = z.object({ id: z.string().uuid() });

const threadQuery = z.object({
  /** Le curseur du sondage : le `now` de la lecture précédente, en temps serveur. */
  since: z.string().datetime({ offset: true }).optional(),
});

/**
 * Un texte, ou une puce. `id` est **fourni par l'app** et devient l'identifiant
 * du message : la bulle optimiste et la bulle servie sont la même, et un
 * renvoi après une panne de transport tombe sur l'existant au lieu de créer
 * un doublon — c'est l'idempotence de la file hors ligne pour rien.
 */
const textTurnBody = z.object({
  id: z.string().uuid(),
  kind: z.literal("text"),
  text: z.string().max(20_000).default(""),
  stepId: z.string().uuid().nullable().optional(),
  suggestionId: z.string().max(64).nullable().optional(),
  /** Le souvenir visé par « Ça me convient ». */
  entryId: z.string().uuid().nullable().optional(),
});

/** ~25 Mo : un vocal long, une photo pleine résolution. */
const MAX_MEDIA_BYTES = 25 * 1024 * 1024;
const MAX_PHOTOS = 4;
const MAX_LEVELS = 4_000;

const chatMemoInclude = {
  owner: true,
  members: {
    where: { status: "active" as const },
    include: { account: true },
    orderBy: { invitedAt: "asc" as const },
  },
  steps: { orderBy: { number: "asc" as const } },
} as const;

async function loadChatMemo(
  context: AppContext,
  request: FastifyRequest,
  memoId: string,
): Promise<MemoForChat> {
  const memo = await context.prisma.memo.findFirst({
    where: { id: memoId, ...visibleToAccount(accountIdOf(request)) },
    include: chatMemoInclude,
  });
  if (!memo) throw HttpError.notFound("Carnet introuvable.");
  return memo;
}

async function loadViewer(context: AppContext, accountId: string): Promise<Account> {
  return context.prisma.account.findUniqueOrThrow({ where: { id: accountId } });
}

async function loadMessages(context: AppContext, memoId: string): Promise<ChatMessageRow[]> {
  return context.prisma.chatMessage.findMany({
    where: { memoId },
    include: chatMessageInclude,
    orderBy: { seq: "asc" },
  });
}

async function loadRows(context: AppContext, ids: string[]): Promise<ChatMessageRow[]> {
  if (ids.length === 0) return [];
  const rows = await context.prisma.chatMessage.findMany({
    where: { id: { in: ids } },
    include: chatMessageInclude,
    orderBy: { seq: "asc" },
  });
  return rows;
}

async function turnStatusOf(context: AppContext, memoId: string, now: Date): Promise<ChatTurnStatus> {
  const inFlight = await findTurnInFlight(context.prisma, memoId, now);
  return inFlight ? { status: "replying", messageId: inFlight.id } : { status: "idle" };
}

async function memoryCountOf(context: AppContext, memoId: string): Promise<number> {
  return context.prisma.entry.count({ where: { memoId, kind: { not: "photo" } } });
}

async function hasReadyRender(context: AppContext, memoId: string): Promise<boolean> {
  const render = await context.prisma.render.findFirst({
    where: { memoId, status: "ready" },
    select: { id: true },
  });
  return render !== null;
}

/** Une puce ou une commande silencieuse que le catalogue sait traiter sans modèle. */
function isCommand(suggestionId: string | null): boolean {
  return suggestionId !== null && scriptedReply(suggestionId, "") !== null;
}

function parseLevels(raw: unknown): number[] {
  if (typeof raw !== "string" || raw.length === 0) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((level): level is number => typeof level === "number" && Number.isFinite(level))
      .map((level) => Math.min(1, Math.max(0, level)))
      .slice(0, MAX_LEVELS);
  } catch {
    return [];
  }
}

function fieldOf(fields: Record<string, { value?: unknown } | undefined>, name: string): string | null {
  const value = fields[name]?.value;
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function registerChatRoutes(app: FastifyInstance, context: AppContext): void {
  const publicBaseUrl = publicApiBaseUrl(context.env);

  /**
   * Le fil. Sans `since`, tout ; avec, la suite seulement — les messages écrits
   * depuis, et les fiches dont le souvenir a bougé (une transcription qui
   * arrive n'écrit aucun message, c'est `entries.updatedAt` qui la fait revenir).
   *
   * **La reconstruction se fait ici**, à chaque lecture : tout souvenir sans
   * message devient une bulle, l'ouverture d'abord si le fil est vide. Un
   * voyage raconté depuis l'accueil retrouve ses vocaux dans son fil.
   */
  app.get("/v1/trips/:id/chat", async (request) => {
    const { id: memoId } = idParams.parse(request.params);
    const query = threadQuery.parse(request.query ?? {});
    const accountId = accountIdOf(request);
    const memo = await loadChatMemo(context, request, memoId);
    const now = new Date();

    await context.prisma.$transaction(async (tx) => {
      const orphans = await tx.entry.count({
        where: {
          memoId,
          chatMessages: { none: {} },
          ...(memo.chatClearedAt ? { capturedAt: { gt: memo.chatClearedAt } } : {}),
        },
      });
      if (orphans === 0) return;
      await ensureOpening(tx, memoId, context.responder);
      await materializeEntriesWithoutMessages(tx, memo);
    });

    const [messages, viewer, turn, memoryCount, readyRender] = await Promise.all([
      loadMessages(context, memoId),
      loadViewer(context, accountId),
      turnStatusOf(context, memoId, now),
      memoryCountOf(context, memoId),
      hasReadyRender(context, memoId),
    ]);

    if (query.since) {
      const since = new Date(query.since);
      const changed = messages.filter(
        (message) =>
          message.createdAt.getTime() > since.getTime() ||
          (message.entry !== null && message.entry.updatedAt.getTime() > since.getTime()),
      );
      return serializeChatUpdate({
        memo,
        allMessages: messages,
        changed,
        viewer,
        memoryCount,
        hasReadyRender: readyRender,
        turn,
        publicBaseUrl,
        now,
      });
    }

    return serializeChatThread({
      memo,
      messages,
      viewer,
      activeStep: activeStepOf(memo.steps, now),
      memoryCount,
      hasReadyRender: readyRender,
      turn,
      publicBaseUrl,
      now,
    });
  });

  /**
   * Un tour de parole. Trois corps, une route — comme `POST /v1/memos/:id/entries` :
   * `application/json` pour un texte ou une puce, `multipart/form-data` pour un
   * vocal ou une à quatre photos.
   *
   * La route écrit le message du voyageur et répond **tout de suite** (201) ;
   * MEMO répond dans le job `converse`, que l'app attend en sondant le fil.
   * Ordre des vérifications : le carnet, le plafond du jour, les étapes
   * offertes, les limites de souvenirs, puis l'écriture. Une commande (une
   * puce du catalogue) ne coûte rien et ne réserve rien.
   */
  app.post("/v1/trips/:id/chat", async (request, reply) => {
    const { id: memoId } = idParams.parse(request.params);
    const accountId = accountIdOf(request);
    const memo = await loadChatMemo(context, request, memoId);
    const now = new Date();
    const showsAuthors = memo.members.length > 0;

    const receipt = (written: ChatMessageRow[], turn: ChatTurnStatus) =>
      serializeChatReceipt({
        written,
        viewerAccountId: accountId,
        showsAuthors,
        publicBaseUrl,
        turn,
        now,
      });

    // Le plafond anti-abus : des tours par carnet et par jour. Ferme la porte
    // à un script, pas à un voyageur.
    if ((await dailyTurnCount(context.prisma, memoId, now)) >= context.env.CHAT_DAILY_TURN_CAP) {
      throw new HttpError(
        429,
        "MEMO a besoin d’une pause : tu as beaucoup raconté aujourd’hui. On reprend demain.",
        "chat_daily_cap",
      );
    }

    if (!request.isMultipart()) {
      const body = textTurnBody.parse(request.body ?? {});
      const text = body.text.trim();

      // Une puce arrive avec son identifiant ; un client qui n'envoie que le
      // libellé est reconnu au caractère près.
      const suggestionId =
        body.suggestionId && (isSuggestionId(body.suggestionId) || isSilentCommand(body.suggestionId))
          ? body.suggestionId
          : suggestionIdForLabel(text);
      const command = isCommand(suggestionId);

      if (!command && text.length === 0) throw HttpError.badRequest("Le message est vide.");

      // Déjà reçu : la même bulle, rien de plus. C'est l'idempotence du renvoi.
      const existing = await context.prisma.chatMessage.findUnique({ where: { id: body.id } });
      if (existing) {
        if (existing.memoId !== memoId) throw HttpError.conflict("Ce message appartient à un autre carnet.");
        const rows = await loadRows(context, [existing.id]);
        return reply.code(200).send(receipt(rows, await turnStatusOf(context, memoId, now)));
      }

      let validatedEntryId: string | null = null;
      if (suggestionId === "accept") {
        // « Ça me convient » valide **dans la même requête** : la fiche passe
        // validée avant même que MEMO ait accusé réception.
        const entry = body.entryId
          ? await context.prisma.entry.findFirst({
              where: { id: body.entryId, memoId, kind: { not: "photo" } },
              select: { id: true },
            })
          : null;
        if (!entry) {
          throw new HttpError(
            400,
            "Dis-moi quel souvenir te convient : la fiche n’est plus là.",
            "entry_required",
          );
        }
        await validateEntry(context.prisma, entry.id, accountId);
        validatedEntryId = entry.id;
      }

      if (!command) {
        await assertCanRecord(context.prisma, accountId);
        await consumeMemory(context.prisma, accountId, TEXT_MEMORY_COST);
      }

      const written = await context.prisma.$transaction(async (tx) => {
        const ids: string[] = [];
        const opening = await ensureOpening(tx, memoId, context.responder);
        if (opening) ids.push(opening.id);

        const message = await tx.chatMessage.create({
          data: {
            id: body.id,
            memoId,
            author: "traveller",
            kind: "text",
            accountId,
            text: command ? (text.length > 0 ? text : null) : text,
            suggestionId,
            entryId: validatedEntryId ?? body.entryId ?? null,
            disposition: command ? "command" : null,
            stepId: body.stepId ?? null,
          },
        });
        ids.push(message.id);
        return ids;
      });

      await context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId: body.id });

      const rows = await loadRows(context, written);
      return reply
        .code(201)
        .send(receipt(rows, { status: "replying", messageId: body.id }));
    }

    // --- Multipart : un vocal, ou des photos -------------------------------

    const files: { filename: string; mimeType: string; buffer: Buffer }[] = [];
    let fields: Record<string, { value?: unknown } | undefined> = {};

    for await (const part of request.files({ limits: { fileSize: MAX_MEDIA_BYTES, files: MAX_PHOTOS + 1 } })) {
      const buffer = await part.toBuffer();
      if (buffer.byteLength === 0) throw HttpError.badRequest("Le fichier reçu est vide.");
      files.push({ filename: part.filename, mimeType: part.mimetype, buffer });
      fields = part.fields as Record<string, { value?: unknown } | undefined>;
    }
    if (files.length === 0) throw HttpError.badRequest("Aucun fichier reçu.");

    const messageId = fieldOf(fields, "id");
    if (!messageId || !z.string().uuid().safeParse(messageId).success) {
      throw HttpError.badRequest("`id` est requis : l’identifiant du message, un UUID.");
    }

    const existing = await context.prisma.chatMessage.findUnique({ where: { id: messageId } });
    if (existing) {
      if (existing.memoId !== memoId) throw HttpError.conflict("Ce message appartient à un autre carnet.");
      const ids = [existing.id];
      const card = await context.prisma.chatMessage.findFirst({
        where: { replyToId: existing.id, kind: "transcript" },
        select: { id: true },
      });
      if (card) ids.push(card.id);
      return reply.code(200).send(receipt(await loadRows(context, ids), await turnStatusOf(context, memoId, now)));
    }

    const isAudio = files.every((file) => file.mimeType.startsWith("audio/"));
    const isImages = files.every((file) => file.mimeType.startsWith("image/"));
    if (!isAudio && !isImages) {
      throw HttpError.badRequest(
        `Type de média non supporté : ${files.map((file) => file.mimeType).join(", ")}. Attendu : audio/* ou image/*.`,
      );
    }
    if (isAudio && files.length > 1) throw HttpError.badRequest("Un seul vocal par message.");
    if (isImages && files.length > MAX_PHOTOS) throw HttpError.badRequest("Quatre photos au plus par message.");

    const rawCapturedAt = fieldOf(fields, "capturedAt");
    const capturedAt = rawCapturedAt ? new Date(rawCapturedAt) : now;
    if (Number.isNaN(capturedAt.getTime())) {
      throw HttpError.badRequest("`capturedAt` n'est pas une date ISO 8601 valide.");
    }

    const rawDuration = fieldOf(fields, "durationSeconds");
    const parsedDuration = rawDuration ? Number.parseFloat(rawDuration) : Number.NaN;
    const duration = Number.isFinite(parsedDuration) && parsedDuration > 0 ? parsedDuration : null;
    const placeLabel = fieldOf(fields, "placeLabel");
    const rawStepId = fieldOf(fields, "stepId");
    const stepId = rawStepId && z.string().uuid().safeParse(rawStepId).success ? rawStepId : null;
    const levels = parseLevels(fields["levels"]?.value);

    await assertCanRecord(context.prisma, accountId);
    await consumeMemory(context.prisma, accountId, isAudio ? voiceCost(duration) : 0);

    const stored = await Promise.all(
      files.map((file) => context.storage.put(isAudio ? "audio" : "photo", file.filename, file.buffer, file.mimeType)),
    );

    let entryIdForTranscription: string | null = null;

    const written = await context.prisma.$transaction(async (tx) => {
      const ids: string[] = [];
      const opening = await ensureOpening(tx, memoId, context.responder);
      if (opening) ids.push(opening.id);

      const entries = await Promise.all(
        stored.map((object) =>
          tx.entry.create({
            data: {
              memo: { connect: { id: memoId } },
              kind: isAudio ? "audio" : "photo",
              status: isAudio ? "pending" : "ready",
              capturedAt,
              placeLabel,
              ...(stepId ? { step: { connect: { id: stepId } } } : {}),
              media: {
                create: {
                  storageKey: object.storageKey,
                  mimeType: object.mimeType,
                  bytes: object.bytes,
                  durationSeconds: isAudio ? duration : null,
                },
              },
            },
          }),
        ),
      );
      const [first] = entries;
      if (!first) throw new Error("Aucun souvenir créé.");

      const payload: Prisma.InputJsonObject = isAudio
        ? { levels }
        : { entryIds: entries.map((entry) => entry.id) };

      const message = await tx.chatMessage.create({
        data: {
          id: messageId,
          memoId,
          author: "traveller",
          kind: isAudio ? "voice" : "photos",
          accountId,
          entryId: first.id,
          disposition: "memory",
          stepId,
          payload,
        },
      });
      ids.push(message.id);

      if (isAudio) {
        // La fiche tombe **tout de suite**, sans texte : on ne cache pas une
        // information réelle (date, lieu, durée) derrière une attente.
        const card = await tx.chatMessage.create({
          data: {
            memoId,
            author: "memo",
            kind: "transcript",
            entryId: first.id,
            replyToId: message.id,
            stepId,
            pauseMilliseconds: pauseBeforeTranscript(duration),
            model: "scripted",
          },
        });
        ids.push(card.id);
        entryIdForTranscription = first.id;
      }

      return ids;
    });

    if (isAudio && entryIdForTranscription) {
      await context.queue.publish<TranscribeJob>(JOB_NAMES.transcribe, {
        entryId: entryIdForTranscription,
        converseMessageId: messageId,
      });
    } else {
      await context.queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId });
    }

    return reply
      .code(201)
      .send(receipt(await loadRows(context, written), { status: "replying", messageId }));
  });

  /**
   * « Supprimer la conversation » — `docs/conversation.md` § 7. Le propriétaire
   * seul ; un co-voyageur reçoit **403** et non 404 : il voit le voyage, lui
   * dire qu'il n'est plus sur son compte serait faux.
   *
   * Supprimer garde la bulle d'ouverture, et les souvenirs d'avant ne
   * reviennent pas dans le fil (`chatClearedAt`) — ils restent dans le carnet.
   */
  app.delete("/v1/trips/:id/chat", async (request, reply) => {
    const { id: memoId } = idParams.parse(request.params);
    const accountId = accountIdOf(request);
    const memo = await loadChatMemo(context, request, memoId);

    if (memo.ownerAccountId !== accountId) {
      throw new HttpError(
        403,
        "Seul le propriétaire du voyage peut supprimer la conversation.",
        "owner_only",
      );
    }

    await context.prisma.$transaction(async (tx) => {
      await tx.chatMessage.deleteMany({ where: { memoId } });
      await tx.memo.update({
        where: { id: memoId },
        data: { chatClearedAt: new Date(), conversationState: Prisma.DbNull },
      });
      await ensureOpening(tx, memoId, context.responder);
    });

    return reply.code(204).send();
  });
}
