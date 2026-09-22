import type { ChatDisposition, Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import {
  dayKeyOf,
  fallbackResponder,
  nextConversationState,
  pauseBeforeTranscript,
  scriptedReply,
  type ConversationInput,
  type ConversationReply,
} from "../services/conversation.js";
import { ROSE_EPINE_GRAINE } from "../services/conversationCopy.js";
import {
  activeStepOf,
  allowsRoseEpineGraine,
  chatMessageInclude,
  conversationStateOf,
  loadCurrentEntry,
  loadHistory,
  loadRecentEntries,
  REPLY_TIMEOUT_MS,
} from "../services/conversationThread.js";
import { parseCoherenceSheet, type RedactJob } from "./redact.js";
import { JOB_NAMES } from "./queue.js";

export interface ConverseJob {
  messageId: string;
}

/** Combien de temps un tour attend qu'un tour plus ancien du même carnet soit répondu. */
const ORDERING_WAIT_MS = 20_000;
const ORDERING_STEP_MS = 1_000;

/** Le sujet posé sur une précision qui répond à la rose, l'épine et la graine. */
export const ROSE_EPINE_GRAINE_TOPIC = "rose_epine_graine";

function entryIdsOf(payload: unknown): string[] {
  const ids =
    payload && typeof payload === "object" ? (payload as { entryIds?: unknown }).entryIds : undefined;
  return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === "string") : [];
}

/**
 * Le tour de MEMO — `docs/conversation.md` § 3 et § 4.
 *
 * Le message du voyageur est déjà écrit par la route ; ce job **répond**. Il
 * relit le fil, demande au répondeur, puis écrit dans une seule transaction :
 * le classement du tour (souvenir, précision, commande), le souvenir qu'un
 * texte crée, les bulles de MEMO, la relance du voyage, et `repliedAt` — la
 * seule chose que l'app sonde.
 *
 * **MEMO n'est jamais muet.** Une panne du répondeur fait parler le moteur de
 * règles ; seule une panne d'écriture relance le job (pg-boss compte la
 * tentative et applique son backoff).
 */
export async function converseTurn(context: AppContext, { messageId }: ConverseJob): Promise<void> {
  const { prisma, responder, logger, queue } = context;

  const message = await prisma.chatMessage.findUnique({
    where: { id: messageId },
    include: { ...chatMessageInclude, memo: { include: { steps: true } } },
  });

  if (!message || message.author !== "traveller") {
    logger.warn({ messageId }, "Tour introuvable, job de conversation ignoré");
    return;
  }
  // Rejoué par pg-boss après une réponse déjà écrite : rien à refaire.
  if (message.repliedAt) return;

  await waitForOlderUnansweredTurns(context, message.memoId, message.seq);

  const now = new Date();
  const memo = message.memo;
  const state = conversationStateOf(memo);

  const [history, currentEntry, recentEntries, activeMembers] = await Promise.all([
    loadHistory(prisma, memo.id, message.seq),
    loadCurrentEntry(prisma, memo.id, message.seq),
    loadRecentEntries(prisma, memo.id),
    prisma.memoMember.count({ where: { memoId: memo.id, status: "active" } }),
  ]);

  const step =
    (message.stepId ? memo.steps.find((candidate) => candidate.id === message.stepId) : null) ??
    activeStepOf(memo.steps, now);

  const kind = message.kind === "voice" ? "voice" : message.kind === "photos" ? "photos" : "text";
  const text = kind === "voice" ? (message.entry?.transcript ?? null) : message.text;
  const transcriptFailed = kind === "voice" && message.entry?.status === "failed";

  const input: ConversationInput = {
    memo: {
      id: memo.id,
      title: memo.title,
      theme: memo.theme,
      destinationCity: memo.destinationCity,
      startDate: memo.startDate,
      endDate: memo.endDate,
      narrationPace: memo.narrationPace,
      prompt: memo.prompt,
      coherenceSheet: parseCoherenceSheet(memo.coherenceSheet),
      state,
    },
    traveller: {
      firstName: message.account?.firstName?.trim() || null,
      memberCount: 1 + activeMembers,
    },
    step: step
      ? {
          id: step.id,
          number: step.number,
          placeName: step.placeName,
          startDate: step.startDate,
          endDate: step.endDate,
        }
      : null,
    history,
    message: {
      id: message.id,
      kind,
      text,
      suggestionId: message.suggestionId,
      photoCount: kind === "photos" ? entryIdsOf(message.payload).length : 0,
      durationSeconds: message.entry?.media?.durationSeconds ?? null,
      transcriptFailed,
      sentAt: message.createdAt,
    },
    currentEntry,
    recentEntries,
    allows: { roseEpineGraine: allowsRoseEpineGraine(currentEntry, state, step, now) },
    now,
  };

  // Une commande connue se répond sans modèle. Sinon le répondeur, et le
  // repli s'il tombe : la panne se lit dans `model`, jamais dans un silence.
  let reply: ConversationReply | null = scriptedReply(message.suggestionId, text ?? "");
  if (!reply) {
    try {
      reply = await responder.reply(input);
    } catch (cause) {
      logger.warn({ messageId, err: cause }, "Le répondeur n'a pas répondu, MEMO passe au repli");
      reply = await fallbackResponder().reply(input);
    }
  }

  // Un vocal ou des photos sont toujours un souvenir, une puce toujours une
  // commande ; un texte libre suit le classement du répondeur — sauf qu'une
  // précision sans souvenir en cours est un souvenir, il n'y a rien à préciser.
  let disposition: ChatDisposition;
  if (message.suggestionId) disposition = "command";
  else if (kind !== "text") disposition = "memory";
  else if (reply.disposition === "context" && !currentEntry) disposition = "memory";
  else disposition = reply.disposition;

  const answersRoseEpineGraine =
    disposition === "context" &&
    [...history].reverse().find((turn) => turn.author === "memo")?.text === ROSE_EPINE_GRAINE;

  const redactEntryIds: string[] = [];
  const currentDay = dayKeyOf(currentEntry?.capturedAt ?? message.createdAt);

  await prisma.$transaction(async (tx) => {
    let entryId = message.entryId;

    if (disposition === "memory" && kind === "text" && !entryId) {
      // Le souvenir que ce texte crée, et sa fiche — la rédaction l'écrira.
      const entry = await tx.entry.create({
        data: {
          memoId: memo.id,
          kind: "text",
          status: "ready",
          transcript: message.text ?? "",
          capturedAt: message.createdAt,
          stepId: message.stepId,
        },
      });
      entryId = entry.id;
      await tx.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "transcript",
          entryId,
          replyToId: message.id,
          stepId: message.stepId,
          pauseMilliseconds: pauseBeforeTranscript(null),
          model: reply.model,
        },
      });
      redactEntryIds.push(entryId);
    }

    if (disposition === "context" && currentEntry) {
      // La précision doit atteindre le texte : on relance la rédaction du
      // souvenir en cours — sauf si le voyageur l'a déjà corrigé à la main
      // (ADR-007), ou si elle est encore à venir et la verra d'elle-même.
      entryId = currentEntry.id;
      const current = await tx.entry.findUnique({
        where: { id: currentEntry.id },
        select: { editedText: true, transcript: true, redactionStatus: true },
      });
      if (current && !current.editedText && current.transcript) {
        if (current.redactionStatus === "ready" || current.redactionStatus === "failed") {
          await tx.entry.update({
            where: { id: currentEntry.id },
            data: { redactionStatus: "pending", redactionError: null },
          });
          redactEntryIds.push(currentEntry.id);
        } else if (current.redactionStatus === "processing") {
          redactEntryIds.push(currentEntry.id);
        }
      }
    }

    for (const [index, beat] of reply.beats.entries()) {
      const isLast = index === reply.beats.length - 1;
      await tx.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "text",
          text: beat.text,
          replyToId: message.id,
          stepId: message.stepId,
          pauseMilliseconds: beat.pauseMilliseconds,
          model: reply.model,
          payload: isLast ? { suggestions: reply.suggestionIds } : undefined,
        },
      });
    }

    const payload: Prisma.InputJsonObject = {
      ...((message.payload as Prisma.JsonObject | null) ?? {}),
      ...(answersRoseEpineGraine ? { topic: ROSE_EPINE_GRAINE_TOPIC } : {}),
    };

    await tx.chatMessage.update({
      where: { id: message.id },
      data: { disposition, entryId, repliedAt: new Date(), payload },
    });

    await tx.memo.update({
      where: { id: memo.id },
      data: {
        ...(reply.prompt ? { prompt: reply.prompt } : {}),
        conversationState: nextConversationState(
          state,
          reply,
          currentDay,
        ) as unknown as Prisma.InputJsonObject,
      },
    });
  });

  for (const entryId of redactEntryIds) {
    await queue.publish<RedactJob>(JOB_NAMES.redact, { entryId });
  }

  logger.info(
    { messageId, memoId: memo.id, model: reply.model, disposition, beats: reply.beats.length },
    "MEMO a répondu",
  );
}

/**
 * Deux co-voyageurs qui parlent en même temps : chaque tour a son job, et la
 * file peut avoir deux consommateurs (l'API et le worker). On attend, par pas
 * d'une seconde et vingt secondes au plus, qu'un tour plus ancien du même
 * carnet soit répondu — une réponse ne passe pas avant la question qui la
 * précède. Au-delà, on répond quand même : mieux vaut un ordre discutable
 * qu'un silence.
 */
async function waitForOlderUnansweredTurns(
  context: AppContext,
  memoId: string,
  seq: number,
): Promise<void> {
  const deadline = Date.now() + ORDERING_WAIT_MS;
  const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

  while (Date.now() < deadline) {
    const older = await context.prisma.chatMessage.findFirst({
      where: {
        memoId,
        author: "traveller",
        seq: { lt: seq },
        repliedAt: null,
        createdAt: { gt: new Date(Date.now() - REPLY_TIMEOUT_MS) },
      },
      select: { id: true },
    });
    if (!older) return;
    await sleep(ORDERING_STEP_MS);
  }
}
