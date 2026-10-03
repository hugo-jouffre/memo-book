import { Prisma, type ChatDisposition } from "@prisma/client";
import type { AppContext } from "../context.js";
import {
  callsToActionAllowed,
  composeBeats,
  dayKeyOf,
  fallbackResponder,
  nextConversationState,
  pauseBeforeTranscript,
  scriptedReply,
  type ConversationHistoryTurn,
  type ConversationInput,
  type ConversationReply,
} from "../services/conversation.js";
import {
  ACKNOWLEDGED,
  PRECISION_NOTED,
  ROSE_EPINE_GRAINE,
  SUGGESTION_SETS,
  fallbackPrompt,
  photosToValidate,
  photosWanted,
} from "../services/conversationCopy.js";
import { DAILY_CREDIT_CALL_TO_ACTION, DAILY_CREDIT_EXHAUSTED } from "../services/dailyCredit.js";
import { photoBudgetFor } from "../services/photoBudget.js";
import { ensureRenderInProgress } from "../services/renderTrigger.js";
import { samplePhotoJpegs } from "../services/samplePhotos.js";
import { hasUnlimitedAccess } from "../services/subscriptions.js";
import {
  CONTEXT_COMPLETE,
  CONTEXT_NOTED,
  EMPTY_TRIP_CONTEXT,
  advance,
  contextVoiceOf,
  isGathering,
  mergeTripContext,
  parseTripContext,
  questionFor,
  type TripContext,
} from "../services/tripContext.js";
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
import { finalTextOf, parseCoherenceSheet, type RedactJob } from "./redact.js";
import { JOB_NAMES } from "./queue.js";

export interface ConverseJob {
  messageId: string;
}

/** Combien de temps un tour attend qu'un tour plus ancien du même carnet soit répondu. */
const ORDERING_WAIT_MS = 20_000;
const ORDERING_STEP_MS = 1_000;

/** Le sujet posé sur une précision qui répond à la rose, l'épine et la graine. */
export const ROSE_EPINE_GRAINE_TOPIC = "rose_epine_graine";

/** L'identifiant du bouton rangé sur une bulle (`payload.callToAction.id`), ou `null`. */
function callToActionIdOf(payload: Prisma.JsonValue | null): string | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
  const callToAction = payload.callToAction;
  if (!callToAction || typeof callToAction !== "object" || Array.isArray(callToAction)) return null;
  return typeof callToAction.id === "string" ? callToAction.id : null;
}

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

  const message = await loadTurn(context, messageId);

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
  const tripContext = parseTripContext(memo.tripContext);

  // Le voyageur raconte le contexte de son voyage : un tour à part, qui
  // n'écrit aucun souvenir — `services/tripContext.ts`. Les photos restent
  // des souvenirs, et une puce se répond toujours par le catalogue.
  if (isGathering(tripContext) && !message.suggestionId && message.kind !== "photos") {
    await converseTripContextTurn(context, message, tripContext!, now);
    return;
  }

  if (message.suggestionId === "photos-sample") {
    await attachSamplePhotos(context, message, now);
    return;
  }

  // L'abonnement de celui qui parle : MEMO ne décrit pas les 5 minutes du jour
  // à qui raconte sans limite, et ne lui tend pas l'offre. L'état du rendu ne
  // sert qu'au bouton de l'aperçu, qui ne se pose que sous un texte libre
  // (`callsToActionAllowed`) : on ne le lit que là.
  const freeText = message.kind === "text" && !message.suggestionId;
  const [
    history,
    currentEntry,
    recentEntries,
    activeMembers,
    authorIsUnlimited,
    renderReady,
    postedNotice,
    lastButton,
  ] = await Promise.all([
    loadHistory(prisma, memo.id, message.seq),
    loadCurrentEntry(prisma, memo.id, message.seq),
    loadRecentEntries(prisma, memo.id),
    prisma.memoMember.count({ where: { memoId: memo.id, status: "active" } }),
    // Sans auteur connu, on ne sait pas : MEMO parle comme à un non-abonné,
    // et `subscribe` reste possible — c'est le sérialiseur qui le masque à un
    // lecteur abonné.
    message.accountId ? hasUnlimitedAccess(prisma, message.accountId, now) : false,
    freeText ? hasReadyRender(context, memo.id) : false,
    // La bulle « reviens demain » que la route a posée dans ce tour, ou
    // qu'un tour plus récent a posée depuis : son `seq` suit celui du
    // message, et l'historique (`seq` plus petit) ne la voit pas.
    prisma.chatMessage.findFirst({
      where: {
        memoId: memo.id,
        author: "memo",
        seq: { gt: message.seq },
        payload: { path: ["notice"], string_starts_with: `${DAILY_CREDIT_EXHAUSTED}:` },
      },
      orderBy: { seq: "asc" },
      select: { text: true, createdAt: true },
    }),
    // La dernière bulle de MEMO qui porte un bouton, avant ce tour : on ne
    // pose pas deux fois de suite le même (`callsToActionAllowed`). Seul un
    // texte libre peut en recevoir un — inutile de la lire ailleurs.
    freeText
      ? prisma.chatMessage.findFirst({
          where: {
            memoId: memo.id,
            author: "memo",
            seq: { lt: message.seq },
            payload: { path: ["callToAction"], not: Prisma.AnyNull },
          },
          orderBy: { seq: "desc" },
          select: { payload: true },
        })
      : null,
  ]);

  // **Pas pour un abonné** (03/10/2026) : la bulle porte `audience: "limited"`,
  // il ne la voit pas dans son fil — et quand elle vient d'un tour plus récent
  // d'un co-voyageur, ce tour-là n'est pas dans l'historique : le répondeur
  // lirait un « reviens demain » qui ne suit rien, et pourrait y faire
  // allusion. Son bouton, lui, ne le concerne pas : l'offre lui est fermée.
  const creditNotice = authorIsUnlimited ? null : postedNotice;

  // Quand elle est posée, MEMO répond **après** elle, et sa carte « Raconter
  // sans limite » est juste au-dessus (03/10/2026) : c'est elle, le dernier
  // bouton du fil — `subscribe` sort des boutons permis, le modèle comme le
  // repli ne posent pas une seconde offre —, et la bulle passe dans le fil que
  // lit le répondeur, comme la dernière chose que MEMO a dite : il répond à la
  // question sans revenir à l'offre (`agents/agent-conversation.md` § 3 bis).
  const lastCallToActionId = creditNotice
    ? DAILY_CREDIT_CALL_TO_ACTION
    : callToActionIdOf(lastButton?.payload ?? null);
  const historyWithNotice: ConversationHistoryTurn[] = creditNotice
    ? [
        ...history,
        {
          author: "memo",
          authorName: null,
          kind: "text",
          text: creditNotice.text,
          disposition: null,
          sentAt: creditNotice.createdAt,
        },
      ]
    : history;

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
      tripContext,
    },
    traveller: {
      firstName: message.account?.firstName?.trim() || null,
      memberCount: 1 + activeMembers,
      isUnlimited: authorIsUnlimited,
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
    history: historyWithNotice,
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
    allows: {
      roseEpineGraine: allowsRoseEpineGraine(currentEntry, state, step, now),
      // `subscribe` seulement pour qui n'a pas l'illimité **et** parle de
      // l'abonnement, du crédit ou de la limite (Hugo, 03/10/2026) — et jamais
      // deux fois de suite le même bouton, la bulle « reviens demain » comptant
      // comme l'offre.
      callsToAction: callsToActionAllowed({
        kind,
        text,
        suggestionId: message.suggestionId,
        authorIsUnlimited,
        hasPreview: renderReady,
        lastCallToActionId,
      }),
    },
    now,
  };

  // Une commande connue se répond sans modèle. Un vocal entendu et des photos
  // aussi : le déroulé est fixe (`docs/conversation.md` § 3). Sinon le
  // répondeur, et le repli s'il tombe : la panne se lit dans `model`, jamais
  // dans un silence.
  let reply: ConversationReply | null =
    message.suggestionId === "accept"
      ? await acceptReply(context, message.entryId, text ?? "")
      : scriptedReply(message.suggestionId, text ?? "");
  if (!reply && !message.suggestionId && kind === "voice" && !transcriptFailed) {
    reply = flowReply([], [], "memory", step?.placeName ?? memo.destinationCity);
  }
  if (!reply && !message.suggestionId && kind === "photos") {
    reply = flowReply(
      composeBeats("", [photosToValidate(input.message.photoCount)]),
      [...SUGGESTION_SETS.afterPhotos],
      "memory",
      step?.placeName ?? memo.destinationCity,
    );
  }
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

  // Le déroulé d'un souvenir (Hugo, 01/10/2026) : un souvenir raconté ne
  // reçoit **aucune** bulle tout de suite — « Il te convient ? » viendra du job
  // de rédaction, quand le texte sera prêt. Une précision reçoit un accusé, et
  // la question reviendra avec le texte réécrit. Le modèle ne sert ici qu'à
  // classer le texte libre.
  //
  // Le bouton du modèle tombe avec ses bulles, **explicitement** : sinon il
  // partirait sans bulle où se poser, ou atterrirait sous « C’est noté, je
  // reprends le texte avec ça » — une offre d'abonnement sous une précision.
  if (!message.suggestionId && kind === "text" && disposition === "memory") {
    reply = { ...reply, beats: [], suggestionIds: [], asksRoseEpineGraine: false, callToActionId: null };
  } else if (!message.suggestionId && kind === "text" && disposition === "context") {
    reply = {
      ...reply,
      beats: composeBeats(text ?? "", [PRECISION_NOTED]),
      suggestionIds: [],
      asksRoseEpineGraine: false,
      callToActionId: null,
    };
  }

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

    // Les puces et le bouton vont sur la **dernière** bulle du tour : c'est
    // sous elle que l'app les dessine, et le sérialiseur résout le bouton pour
    // chaque lecteur (`resolveCallToAction` — un abonné ne voit pas l'offre).
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
          payload: isLast
            ? {
                suggestions: reply.suggestionIds,
                ...(reply.callToActionId ? { callToAction: { id: reply.callToActionId } } : {}),
              }
            : undefined,
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
        ...contextChangeFor(message.suggestionId, tripContext),
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

  if (message.suggestionId === "photos-ok") await validatePhotos(context, memo.id, now);

  logger.info(
    {
      messageId,
      memoId: memo.id,
      model: reply.model,
      disposition,
      beats: reply.beats.length,
      callToAction: reply.callToActionId,
    },
    "MEMO a répondu",
  );
}

/**
 * « Je valide mes photos » : les photos en attente sont validées, et le carnet
 * se recompose en fond pour que la page de l'étape apparaisse dans l'aperçu —
 * le même déclencheur que « Valider cette étape » (`renderTrigger.ts`). Une
 * panne du rendu ne coupe pas la parole à MEMO : elle se journalise.
 */
async function validatePhotos(context: AppContext, memoId: string, now: Date): Promise<void> {
  await context.prisma.entry.updateMany({
    where: { memoId, kind: "photo", validatedAt: null },
    data: { validatedAt: now },
  });
  try {
    await ensureRenderInProgress(context, memoId);
  } catch (cause) {
    context.logger.warn({ memoId, err: cause }, "Photos validées, mais le carnet n'a pas pu se recomposer");
  }
}

/** Une réponse écrite par le déroulé, sans modèle. */
function flowReply(
  beats: ConversationReply["beats"],
  suggestionIds: ConversationReply["suggestionIds"],
  disposition: ChatDisposition,
  placeName: string | null,
): ConversationReply {
  return {
    beats,
    disposition,
    suggestionIds,
    prompt: fallbackPrompt(placeName),
    asksRoseEpineGraine: false,
    callToActionId: null,
    model: "scripted",
  };
}

/** Un rendu prêt : sans lui, le bouton « Voir l’aperçu du carnet » ouvrirait une page vide. */
async function hasReadyRender(context: AppContext, memoId: string): Promise<boolean> {
  const render = await context.prisma.render.findFirst({
    where: { memoId, status: "ready" },
    select: { id: true },
  });
  return render !== null;
}

/**
 * « Ça me convient » : c'est enregistré, et MEMO demande le nombre **exact**
 * de photos qui remplit l'étape, calculé sur le texte validé — la correction
 * à la main si elle existe, sinon le texte rédigé (`photoBudget.ts`).
 */
async function acceptReply(
  context: AppContext,
  entryId: string | null,
  received: string,
): Promise<ConversationReply> {
  const entry = entryId ? await context.prisma.entry.findUnique({ where: { id: entryId } }) : null;
  const validated = entry ? finalTextOf(entry) : null;
  if (!validated) {
    return flowReply(composeBeats(received, [ACKNOWLEDGED]), [...SUGGESTION_SETS.afterAccept], "command", null);
  }
  const budget = photoBudgetFor(validated.trim().length);
  return flowReply(
    composeBeats(received, [ACKNOWLEDGED, photosWanted(budget.photos, budget.pages)]),
    [
      ...SUGGESTION_SETS.askPhotos,
      ...(context.env.NODE_ENV === "production" ? [] : (["photos-sample"] as const)),
    ],
    "command",
    null,
  );
}

/**
 * « Photos de test » (hors production) : joint, au nom du voyageur, le nombre
 * exact de photos que le dernier souvenir demande, puis laisse le tour de ces
 * photos suivre le chemin normal — un job `converse` qui demande de les
 * valider. La puce elle-même ne reçoit pas de bulle : les photos parlent.
 */
async function attachSamplePhotos(
  context: AppContext,
  message: NonNullable<Awaited<ReturnType<typeof loadTurn>>>,
  now: Date,
): Promise<void> {
  const { prisma, storage, queue, env } = context;
  if (env.NODE_ENV === "production") {
    await prisma.chatMessage.update({
      where: { id: message.id },
      data: { disposition: "command", repliedAt: now },
    });
    return;
  }

  const current = await loadCurrentEntry(prisma, message.memoId, message.seq);
  const count = photoBudgetFor((current?.text ?? "").trim().length).photos;
  const jpegs = await samplePhotoJpegs(count);
  const stored = await Promise.all(
    jpegs.map((jpeg, index) => storage.put("photo", `test-${index + 1}.jpg`, jpeg, "image/jpeg")),
  );

  const photosMessageId = await prisma.$transaction(async (tx) => {
    const entries = [];
    for (const object of stored) {
      entries.push(
        await tx.entry.create({
          data: {
            memo: { connect: { id: message.memoId } },
            kind: "photo",
            status: "ready",
            capturedAt: now,
            ...(message.stepId ? { step: { connect: { id: message.stepId } } } : {}),
            media: {
              create: { storageKey: object.storageKey, mimeType: object.mimeType, bytes: object.bytes },
            },
          },
        }),
      );
    }
    await tx.chatMessage.update({
      where: { id: message.id },
      data: { disposition: "command", repliedAt: now },
    });
    const photos = await tx.chatMessage.create({
      data: {
        memoId: message.memoId,
        author: "traveller",
        kind: "photos",
        accountId: message.accountId,
        entryId: entries[0]!.id,
        disposition: "memory",
        stepId: message.stepId,
        payload: { entryIds: entries.map((entry) => entry.id) },
      },
    });
    return photos.id;
  });

  await queue.publish<ConverseJob>(JOB_NAMES.converse, { messageId: photosMessageId });
  context.logger.info({ memoId: message.memoId, count }, "Photos de test jointes");
}

/**
 * Ce que les deux puces du contexte font au voyage : « Je te raconte le
 * contexte » ouvre le recueil (en gardant ce qui était déjà su), « Je
 * compléterai plus tard » le referme sans insister.
 */
function contextChangeFor(
  suggestionId: string | null,
  current: TripContext | null,
): { tripContext?: Prisma.InputJsonObject } {
  if (suggestionId === "context") {
    const opened = advance({ ...(current ?? EMPTY_TRIP_CONTEXT), status: "gathering" });
    // Rien de su encore : la première réponse est une description libre, pas
    // la réponse à une question précise.
    const reopened = { ...opened, status: "gathering" as const, awaiting: current ? opened.awaiting : null };
    return { tripContext: reopened as unknown as Prisma.InputJsonObject };
  }
  if (suggestionId === "context-later" && current) {
    return { tripContext: { ...current, status: "skipped", awaiting: null } as unknown as Prisma.InputJsonObject };
  }
  return {};
}

/**
 * Un tour du contexte du voyage. MEMO écoute (le vocal se transcrit ici : il
 * n'a pas de souvenir où le faire), le répondeur extrait, le code fond, voit
 * ce qui manque et pose **la** question suivante — ou dit que c'est posé.
 */
async function converseTripContextTurn(
  context: AppContext,
  message: NonNullable<Awaited<ReturnType<typeof loadTurn>>>,
  tripContext: TripContext,
  now: Date,
): Promise<void> {
  const { prisma, responder, logger } = context;
  const memo = message.memo;

  let text = message.text ?? "";
  let heard = true;
  const voice = message.kind === "voice" ? contextVoiceOf(message.payload) : null;
  if (voice) {
    try {
      const audio = await context.storage.get(voice.storageKey);
      const result = await context.transcriber.transcribe({
        audio,
        filename: voice.storageKey.split("/").pop() ?? "contexte.m4a",
        mimeType: voice.mimeType,
      });
      text = result.text;
    } catch (cause) {
      logger.warn({ messageId: message.id, err: cause }, "Vocal du contexte non transcrit");
      heard = false;
    }
  }

  const history = await loadHistory(prisma, memo.id, message.seq);
  const travellerFirstName = message.account?.firstName?.trim() || null;

  let merged = tripContext;
  let acknowledgement: string | null = null;
  let model = "scripted";
  if (heard && text.trim().length > 0) {
    const input = {
      context: tripContext,
      memo: { title: memo.title, destinationName: memo.destinationName, destinationCity: memo.destinationCity },
      travellerFirstName,
      history,
      text,
      now,
    };
    let reply;
    try {
      reply = await responder.gatherContext(input);
    } catch (cause) {
      logger.warn({ messageId: message.id, err: cause }, "Le répondeur n'a pas écouté le contexte, repli");
      reply = await fallbackResponder().gatherContext(input);
    }
    merged = advance(mergeTripContext(tripContext, reply.update));
    acknowledgement = reply.acknowledgement;
    model = reply.model;
  } else {
    merged = advance(tripContext);
  }

  const complete = merged.status === "complete";
  const next = complete ? CONTEXT_COMPLETE : questionFor(merged.awaiting!, merged);
  // Une reformulation du modèle mérite sa bulle ; l'accusé du code, non —
  // « C'est noté. » seul dans une bulle, cinq fois de suite, sonne comme une
  // machine. Il se pose alors devant la question, dans la même bulle.
  const texts = !heard
    ? ["Je n’ai pas réussi à écouter ce vocal.", "Tu peux me le réécrire ici ?"]
    : acknowledgement
      ? [acknowledgement, next]
      : [`${CONTEXT_NOTED} ${next}`];
  const beats = composeBeats(text, texts);
  const suggestions = complete ? SUGGESTION_SETS.afterContext : SUGGESTION_SETS.gatheringContext;

  await prisma.$transaction(async (tx) => {
    for (const [index, beat] of beats.entries()) {
      await tx.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "text",
          text: beat.text,
          replyToId: message.id,
          stepId: message.stepId,
          pauseMilliseconds: beat.pauseMilliseconds,
          model,
          payload: index === beats.length - 1 ? { suggestions: [...suggestions] } : undefined,
        },
      });
    }
    await tx.chatMessage.update({
      where: { id: message.id },
      data: {
        disposition: "trip_context",
        repliedAt: new Date(),
        // Le vocal garde sa transcription sur lui : c'est ce que relit l'historique.
        ...(voice && heard ? { text } : {}),
      },
    });
    await tx.memo.update({
      where: { id: memo.id },
      data: { tripContext: merged as unknown as Prisma.InputJsonObject },
    });
  });

  logger.info(
    { messageId: message.id, memoId: memo.id, model, complete, awaiting: merged.awaiting },
    "MEMO a écouté le contexte du voyage",
  );
}

function loadTurn(context: AppContext, messageId: string) {
  return context.prisma.chatMessage.findUnique({
    where: { id: messageId },
    include: { ...chatMessageInclude, memo: { include: { steps: true } } },
  });
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
