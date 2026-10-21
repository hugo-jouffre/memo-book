import { Prisma, type ChatDisposition } from "@prisma/client";
import type { AppContext } from "../context.js";
import {
  callsToActionAllowed,
  composeBeats,
  dayKeyOf,
  fallbackResponder,
  isTooShortToKeep,
  nextConversationState,
  pauseBeforeSaying,
  pauseBeforeTranscript,
  scriptedReply,
  type ConversationHistoryTurn,
  type ConversationState,
  type ConversationInput,
  type ConversationReply,
  type MemoResponder,
} from "../services/conversation.js";
import {
  ACKNOWLEDGED,
  ACKNOWLEDGED_EARLIER,
  PHOTOS_VALIDATED_BEFORE_RETURN,
  PRECISION_NOTED,
  REVISION_NOTED,
  REVISION_UNHEARD,
  ROSE_EPINE_GRAINE,
  MISSING_DAY_WHICH,
  SUGGESTION_SETS,
  dayOfGapDayId,
  fallbackPrompt,
  gapDayId,
  isGapDayId,
  missingDayListening,
  missingDayNotice,
  photosToValidate,
  photosWanted,
  returnForPhotos,
  returnToValidate,
  tooShort,
  validationQuestionFor,
} from "../services/conversationCopy.js";
import {
  DAILY_CREDIT_CALL_TO_ACTION,
  DAILY_CREDIT_EXHAUSTED,
  timeZoneOf,
} from "../services/dailyCredit.js";
import {
  capturedAtFor,
  shouldOfferGap,
  tellingDayOf,
  withGapAccepted,
  withGapDeclined,
  withGapOffered,
  gapBorders,
  type Gap,
} from "../services/conversationGaps.js";
import { localDate } from "../services/localCalendar.js";
import { CALLS_TO_ACTION } from "../services/callsToAction.js";
import { photoBudgetFor, type PhotoBudgetSettings } from "../services/photoBudget.js";
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
  photosTargetEntryId,
  REPLY_TIMEOUT_MS,
  type Db,
} from "../services/conversationThread.js";
import { stepNumbersOf } from "../routes/chatSerializers.js";
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
 * La rédaction d'un tour déjà répondu, quand elle n'est jamais partie : la
 * fiche attend encore (`pending`), elle a un texte à rédiger, et personne ne
 * l'a corrigée à la main. Une rédaction en cours ou finie ne se relance pas.
 */
async function republishStrandedRedaction(context: AppContext, entryId: string | null): Promise<void> {
  if (!entryId) return;
  const entry = await context.prisma.entry.findUnique({
    where: { id: entryId },
    select: { kind: true, transcript: true, editedText: true, redactionStatus: true },
  });
  if (!entry || entry.redactionStatus !== "pending") return;
  if (entry.kind === "photo" || !entry.transcript || entry.editedText) return;
  await context.queue.publish<RedactJob>(JOB_NAMES.redact, { entryId });
  context.logger.warn({ entryId }, "Rédaction republiée au rejeu du tour de conversation");
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
  // Rejoué par pg-boss après une réponse déjà écrite : rien à refaire — sauf
  // la rédaction, si c'est sa publication, après la transaction, qui a fait
  // échouer le job. Sans ça, le souvenir restait « en cours » pour toujours.
  if (message.repliedAt) {
    await republishStrandedRedaction(context, message.entryId);
    return;
  }

  await waitForOlderUnansweredTurns(context, message.memoId, message.seq);

  // Le vocal qui suit « à l'oral » corrige une fiche : un tour à part, sans
  // souvenir ni modèle — `converseOralRevision`.
  const revised = revisedEntryOf(message.payload);
  if (message.kind === "voice" && revised) {
    await converseOralRevision(context, message, revised);
    return;
  }

  const now = new Date();
  const memo = message.memo;
  const state = conversationStateOf(memo);
  const tripContext = parseTripContext(memo.tripContext);
  // Le fuseau du **propriétaire**, et non du lecteur : deux co-voyageurs, l'un
  // à Paris et l'autre à Tokyo, doivent voir les mêmes journées.
  const timeZone = await tripTimeZone(context, memo.ownerAccountId);

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

  // « Compléter l'étape manquante », et la journée qu'on choisit quand il en
  // manque deux : un tour à part, sans modèle et sans souvenir.
  if (
    message.suggestionId === "fill-missing-day" ||
    (message.suggestionId !== null && isGapDayId(message.suggestionId))
  ) {
    await converseMissingDay(context, message, state, now);
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
  // Un vocal muet — un silence, ou une transcription qui n'était que l'indice
  // recopié (`withoutHintEcho`) — arrive « prêt » mais vide. MEMO le dit comme
  // une transcription ratée, au lieu de se taire devant une fiche blanche.
  const transcriptFailed =
    kind === "voice" &&
    (message.entry?.status === "failed" ||
      (message.entry?.status === "ready" && !(message.entry.transcript ?? "").trim()));

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
      ? await acceptReply(
          context,
          message.entryId,
          text ?? "",
          message.entryId !== null && currentEntry !== null && message.entryId !== currentEntry.id,
        )
      : scriptedReply(message.suggestionId, text ?? "");
  // Un vocal raconté : rien à dire tout de suite, et pas de relance non plus —
  // le lieu de cette nouvelle étape n'est pas encore lu. C'est la rédaction
  // qui la réécrira, en recalculant les étapes (`tripFacts.ts`).
  if (!reply && !message.suggestionId && kind === "voice" && !transcriptFailed) {
    reply = flowReply([], [], "memory", null);
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

  // **Trop court pour être un souvenir** (Hugo, 08/10/2026) : « ok »,
  // « super », deux lettres tapées par erreur. Le classer `memory` créait un
  // souvenir que la rédaction étoffait, puis « Il te convient ? » — MEMO
  // faisait comme s'il avait compris. Il le dit à la place, en recopiant ce
  // qu'il a reçu, et rien n'entre dans le carnet. Une précision du souvenir en
  // cours (`context`) n'est pas concernée : « avec Clara » se comprend avec
  // lui. Quel que soit le répondeur — le modèle comme le repli.
  if (!message.suggestionId && kind === "text" && disposition === "memory" && isTooShortToKeep(text ?? "")) {
    disposition = "command";
    const alreadySaid = new Set(history.filter((turn) => turn.author === "memo").map((turn) => turn.text));
    const lines = tooShort(text ?? "");
    reply = {
      ...reply,
      beats: composeBeats(text ?? "", [lines.find((line) => !alreadySaid.has(line)) ?? lines[0]!]),
      suggestionIds: [...SUGGESTION_SETS.neutral],
      asksRoseEpineGraine: false,
      callToActionId: null,
    };
  }

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

  // « Ça me convient » : les photos se demandent pour **ce** récit — c'est ce
  // qui rangera les photos qui suivent dans son étape (`photosTargetEntryId`).
  const photosFor =
    message.suggestionId === "accept" && message.entryId && reply.beats.length > 1 ? message.entryId : null;

  // « Je valide mes photos » clôt une étape : si on avait sauté celle d'avant
  // pour raconter celle-ci, MEMO y revient (Hugo, 12/10/2026).
  const closing = message.suggestionId === "photos-ok" ? await stepToClose(context, memo.id, message.seq, state) : null;

  // **L'étape manquante** (19/10/2026). Au même moment que l'étape sautée —
  // « Je valide mes photos », le seul instant vraiment au repos du déroulé —
  // et jamais dans le même tour qu'elle : deux relances d'affilée, c'est une
  // de trop. Tout le reste du contrat tombe de cet ancrage unique : jamais au
  // milieu d'un souvenir, ni sous une précision, ni après un refus.
  const found =
    message.suggestionId === "photos-ok" && !closing
      ? await gapToOffer(context, memo, state, now, timeZone)
      : null;
  // **C'est MEMO qui pose la question** (21/10/2026, Hugo) : le code a trouvé
  // le trou, le modèle demande s'il est voulu ou oublié. Un appel qui tombe,
  // ou une bulle hors contrat, laisse parler la carte fixe — le trou se dit
  // quand même, c'est seulement la question qui s'éteint.
  const offer = found
    ? { ...found, ...(await missingDayBubble(responder, found, memo, input, logger, messageId)) }
    : null;
  if (closing) {
    reply = {
      ...reply,
      beats: composeBeats(text ?? "", [
        PHOTOS_VALIDATED_BEFORE_RETURN,
        closing.reason === "validation"
          ? returnToValidate(closing.number, closing.title)
          : returnForPhotos(closing.number, closing.title, closing.budget.photos, closing.budget.pages),
      ]),
      suggestionIds: closing.reason === "validation" ? [] : [...SUGGESTION_SETS.askPhotos],
    };
  }

  const answersRoseEpineGraine =
    disposition === "context" &&
    [...history].reverse().find((turn) => turn.author === "memo")?.text === ROSE_EPINE_GRAINE;

  const redactEntryIds: string[] = [];
  const currentDay = dayKeyOf(currentEntry?.capturedAt ?? message.createdAt);

  // La journée que « Compléter l'étape manquante » a ouverte, si elle tient
  // encore debout — un mode qui traîne daterait un souvenir d'il y a une
  // semaine, et c'est précisément ce qu'on ne veut pas.
  const telling = tellingDayOf(memo, state, now, timeZone);
  const told = telling && disposition === "memory" ? capturedAtFor(telling, timeZone) : null;

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
          // Un texte raconté après coup porte la journée du trou, et non
          // l'heure de son envoi : c'est ce qui le range à sa place dans le
          // carnet (`conversationGaps.ts`).
          capturedAt: told ?? message.createdAt,
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

    // Un **vocal** raconté après coup : son souvenir existe déjà — la route
    // l'a créé à l'envoi, daté de l'envoi — et c'est ici qu'on le redate. Une
    // seule décision sur la journée, pour le texte comme pour la voix. Les
    // photos n'y passent pas : elles portent leur propre date de prise de vue.
    if (told && entryId && kind === "voice") {
      await tx.entry.update({ where: { id: entryId }, data: { capturedAt: told } });
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
      const asksPhotosFor = photosFor ?? (closing?.reason === "photos" ? closing.entryId : null);
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
                ...(asksPhotosFor ? { asksPhotosFor } : {}),
              }
            : undefined,
        },
      });
    }

    // La carte « ✦ Suggestions » de l'étape manquante : une bulle de plus,
    // **la dernière du tour**, sans puces — le sérialiseur remonte alors au
    // tour d'avant pour les siennes, qui restent celles qu'on attendait.
    if (offer) {
      await tx.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "text",
          text: offer.notice,
          replyToId: message.id,
          stepId: message.stepId,
          pauseMilliseconds: pauseBeforeSaying(offer.notice),
          model: offer.model,
          payload: { callToAction: { id: "fill_missing_day" } },
        },
      });
    }

    // L'étape sautée n'est pas validée : sa fiche revient au bas du fil, et la
    // question avec elle — c'est elle que « Ça me convient » validera.
    if (closing?.reason === "validation") {
      await tx.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "transcript",
          entryId: closing.entryId,
          replyToId: message.id,
          stepId: closing.stepId,
          pauseMilliseconds: pauseBeforeTranscript(null),
          model: "scripted",
        },
      });
      const question = validationQuestionFor([]);
      await tx.chatMessage.create({
        data: {
          memoId: memo.id,
          author: "memo",
          kind: "text",
          text: question,
          replyToId: message.id,
          stepId: closing.stepId,
          pauseMilliseconds: pauseBeforeSaying(question),
          model: "scripted",
          payload: { suggestions: [...SUGGESTION_SETS.trio], asksValidationFor: closing.entryId },
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
        conversationState: withGapState(
          withClosingAsked(nextConversationState(state, reply, currentDay), closing?.entryId ?? null),
          { offered: offer?.gap ?? null, consumesTellingDay: telling !== null, now },
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

/** Le souvenir qu'un vocal corrige — `payload.revises`, posé par la route. */
function revisedEntryOf(payload: Prisma.JsonValue | null): string | null {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
  return typeof payload.revises === "string" ? payload.revises : null;
}

/**
 * **Une correction dictée** (Hugo, 12/10/2026). Après « J'aimerais faire des
 * modifications à l'oral », le vocal suivant ne fait pas un souvenir de plus :
 * MEMO l'écoute, le range comme une précision de la fiche visée — marquée
 * `correction_orale` — et la rédaction réécrit le texte avec, en remplaçant ce
 * que la correction contredit. « Il te convient ? » revient avec le nouveau
 * texte (`askValidation`).
 *
 * Une correction l'emporte sur une version tapée à la main, si la fiche en
 * avait une : c'est le dernier mot du voyageur.
 */
async function converseOralRevision(
  context: AppContext,
  message: NonNullable<Awaited<ReturnType<typeof loadTurn>>>,
  entryId: string,
): Promise<void> {
  const { prisma, logger, queue } = context;

  let text = "";
  const voice = contextVoiceOf(message.payload);
  if (voice) {
    try {
      const audio = await context.storage.get(voice.storageKey);
      const result = await context.transcriber.transcribe({
        audio,
        filename: voice.storageKey.split("/").pop() ?? "correction.m4a",
        mimeType: voice.mimeType,
      });
      text = result.text.trim();
    } catch (cause) {
      logger.warn({ messageId: message.id, err: cause }, "Correction orale non transcrite");
    }
  }

  const entry = await prisma.entry.findUnique({
    where: { id: entryId },
    select: { id: true, transcript: true },
  });
  const heard = text.length > 0;
  const rewrites = heard && Boolean(entry?.transcript);
  const beats = composeBeats(text, [rewrites ? REVISION_NOTED : REVISION_UNHEARD]);

  await prisma.$transaction(async (tx) => {
    for (const [index, beat] of beats.entries()) {
      await tx.chatMessage.create({
        data: {
          memoId: message.memoId,
          author: "memo",
          kind: "text",
          text: beat.text,
          replyToId: message.id,
          stepId: message.stepId,
          pauseMilliseconds: beat.pauseMilliseconds,
          model: "scripted",
          payload:
            index === beats.length - 1 ? { suggestions: rewrites ? [] : ["edit-voice", "edit-hand"] } : undefined,
        },
      });
    }
    await tx.chatMessage.update({
      where: { id: message.id },
      // Sa transcription reste sur lui : c'est elle que la rédaction relit.
      data: { repliedAt: new Date(), ...(heard ? { text } : {}) },
    });
    if (rewrites) {
      await tx.entry.update({
        where: { id: entryId },
        data: {
          redactionStatus: "pending",
          redactionError: null,
          editedText: null,
          editedAt: null,
          validatedAt: null,
        },
      });
    }
  });

  if (rewrites) await queue.publish<RedactJob>(JOB_NAMES.redact, { entryId });
  logger.info({ messageId: message.id, entryId, heard }, "MEMO a écouté une correction orale");
}

/** Une étape à clore, et de quoi le dire. */
interface StepToClose {
  entryId: string;
  stepId: string | null;
  number: number;
  title: string | null;
  reason: "validation" | "photos";
  budget: ReturnType<typeof photoBudgetFor>;
}

/**
 * **L'étape qu'on a sautée** (Hugo, 12/10/2026) : on a raconté une étape, puis
 * la suivante dans la foulée — la première n'a été ni validée ni illustrée.
 * Quand « Je valide mes photos » clôt une étape, MEMO regarde le récit raconté
 * **juste avant** elle dans le fil : pas encore validé, ou validé sans que les
 * photos demandées soient jamais venues. Une fois par récit
 * (`closingAskedFor`) : on ne revient pas deux fois sur un refus.
 */
async function stepToClose(
  context: AppContext,
  memoId: string,
  beforeSeq: number,
  state: ConversationState,
): Promise<StepToClose | null> {
  const { prisma } = context;
  const closed = (await photosTargetEntryId(prisma, memoId)) ?? (await loadCurrentEntry(prisma, memoId, beforeSeq))?.id;
  if (!closed) return null;

  const stories = await prisma.chatMessage.findMany({
    where: { memoId, author: "traveller", disposition: "memory", kind: { not: "photos" }, entryId: { not: null } },
    orderBy: { seq: "asc" },
    select: { entryId: true },
  });
  const order = [...new Set(stories.map((story) => story.entryId!))];
  const index = order.indexOf(closed);
  const previousId = index > 0 ? order[index - 1]! : null;
  if (!previousId || state.closingAskedFor.includes(previousId)) return null;

  const previous = await prisma.entry.findUnique({ where: { id: previousId } });
  const text = previous ? finalTextOf(previous) : null;
  if (!previous || previous.kind === "photo" || !text?.trim()) return null;

  let reason: StepToClose["reason"];
  if (!previous.validatedAt) {
    // Le texte doit être là : une rédaction en cours posera sa question elle-même.
    if (previous.redactionStatus === "pending" || previous.redactionStatus === "processing") return null;
    reason = "validation";
  } else if (await photosAskedButMissing(prisma, memoId, previous)) {
    reason = "photos";
  } else {
    return null;
  }

  const cards = await prisma.chatMessage.findMany({
    where: { memoId, kind: "transcript" },
    select: { id: true, kind: true, seq: true, entryId: true },
  });
  const card = cards.find((candidate) => candidate.entryId === previousId);
  const number = card ? stepNumbersOf(cards).get(card.id) : undefined;
  if (!number) return null;

  return {
    entryId: previousId,
    stepId: previous.stepId,
    number,
    title: previous.suggestedTitle,
    reason,
    budget: photoBudgetFor(text.trim(), await reglagesDuCarnet(context, memoId)),
  };
}

/** MEMO a demandé les photos de ce récit, et aucune n'est venue. */
async function photosAskedButMissing(
  db: Db,
  memoId: string,
  entry: { id: string; stepId: string | null },
): Promise<boolean> {
  const asked = await db.chatMessage.findFirst({
    where: { memoId, author: "memo", payload: { path: ["asksPhotosFor"], equals: entry.id } },
    select: { id: true },
  });
  if (!asked) return false;
  const [illustrated, inStep] = await Promise.all([
    db.chatMessage.findFirst({
      where: { memoId, kind: "photos", payload: { path: ["forEntryId"], equals: entry.id } },
      select: { id: true },
    }),
    entry.stepId ? db.entry.count({ where: { stepId: entry.stepId, kind: "photo" } }) : 0,
  ]);
  return !illustrated && inStep === 0;
}

/** L'état de la conversation, avec le récit auquel MEMO vient de revenir. */
function withClosingAsked(state: ConversationState, entryId: string | null): ConversationState {
  if (!entryId || state.closingAskedFor.includes(entryId)) return state;
  return { ...state, closingAskedFor: [...state.closingAskedFor, entryId] };
}

// ---------------------------------------------------------------------------
// L'étape manquante — `services/conversationGaps.ts` porte toutes les règles
// ---------------------------------------------------------------------------

/** Le fuseau du voyage : celui du compte qui en est propriétaire. */
async function tripTimeZone(context: AppContext, ownerAccountId: string): Promise<string> {
  const owner = await context.prisma.account.findUnique({
    where: { id: ownerAccountId },
    select: { timeZone: true },
  });
  return timeZoneOf({ timeZone: owner?.timeZone ?? null });
}

/**
 * Le trou qu'on propose de combler, et les deux journées qui l'encadrent —
 * `null` neuf fois sur dix, et c'est le but. Ne lit la base que si le registre
 * laisse encore une chance à une proposition.
 */
async function gapToOffer(
  context: AppContext,
  memo: { id: string; startDate: Date | null; endDate: Date | null; stage: string; narrationPace: string | null },
  state: ConversationState,
  now: Date,
  timeZone: string,
): Promise<{
  gap: Gap;
  before: string;
  after: string;
  beforeText: string | null;
  afterText: string | null;
} | null> {
  const entries = await context.prisma.entry.findMany({
    // Les photos n'ouvrent ni ne ferment un trou : une photo du 26 illustre le
    // plus souvent l'étape du 25.
    where: { memoId: memo.id, kind: { not: "photo" } },
    // `text` sert la question de MEMO (21/10/2026) : savoir ce qui a été
    // raconté de part et d'autre, c'est la différence entre « il te manque le
    // 26 » et une question qui tombe juste.
    select: { capturedAt: true, editedText: true, redactedText: true, transcript: true },
  });
  const told = entries.map((entry) => entry.capturedAt);

  const gap = shouldOfferGap(memo, state, told, now, timeZone);
  if (!gap) return null;

  const borders = gapBorders(gap, told, timeZone);
  if (!borders) return null;

  // Le dernier récit de la journée, quand elle en porte plusieurs : c'est lui
  // qui touche le trou.
  const textOn = (day: string): string | null => {
    const ofDay = entries
      .filter((entry) => localDate(entry.capturedAt, timeZone) === day)
      // Le corrigé au clavier, sinon le rédigé, sinon le brut — l'ordre du reste
      // du serveur (`routes/serializers.ts`).
      .map((entry) => (entry.editedText ?? entry.redactedText ?? entry.transcript ?? "").trim())
      .filter((text) => text !== "");
    return ofDay.length > 0 ? ofDay[ofDay.length - 1]! : null;
  };

  return {
    gap,
    before: borders.before,
    after: borders.after,
    beforeText: textOn(borders.before),
    afterText: textOn(borders.after),
  };
}

/**
 * La bulle du trou : celle de MEMO, ou celle du code.
 *
 * Le repli n'est pas un pis-aller discret — c'est la carte fixe d'avant le
 * 21/10/2026, qui dit le trou et sa porte de sortie sans poser de question.
 * `model` le dit : le nom du modèle, ou « scripted ».
 */
async function missingDayBubble(
  responder: MemoResponder,
  found: { gap: Gap; before: string; after: string; beforeText: string | null; afterText: string | null },
  memo: { title: string; destinationCity: string | null },
  input: ConversationInput,
  logger: AppContext["logger"],
  messageId: string,
): Promise<{ notice: string; model: string }> {
  const scripted = missingDayNotice(found.gap.days, found.before, found.after);
  try {
    const asked = await responder.askMissingDay({
      memo: { title: memo.title, destinationCity: memo.destinationCity },
      travellerFirstName: input.traveller.firstName,
      days: [...found.gap.days],
      before: found.before,
      after: found.after,
      beforeText: found.beforeText,
      afterText: found.afterText,
      buttonLabel: CALLS_TO_ACTION.fill_missing_day.label,
      now: input.now,
    });
    if (asked.text) return { notice: asked.text, model: asked.model };
    return { notice: scripted, model: "scripted" };
  } catch (cause) {
    logger.warn({ messageId, err: cause }, "La question du trou n'est pas venue, la carte fixe parle");
    return { notice: scripted, model: "scripted" };
  }
}

/**
 * Le registre de l'étape manquante, en un seul endroit — l'ordre compte :
 *
 * 1. la journée qu'on vient de raconter rend le mode ;
 * 2. **le silence vaut refus** : une proposition en vol que ce tour-ci n'a pas
 *    acceptée est refusée, qu'on ait touché « Ignorer » ou simplement continué
 *    à raconter ;
 * 3. la nouvelle proposition part.
 */
function withGapState(
  state: ConversationState,
  { offered, consumesTellingDay, now }: { offered: Gap | null; consumesTellingDay: boolean; now: Date },
): ConversationState {
  let next = consumesTellingDay ? { ...state, tellingDay: null } : state;
  if (next.gapOffered) next = withGapDeclined(next);
  if (offered) next = withGapOffered(next, offered, now);
  return next;
}

/**
 * « Compléter l'étape manquante », et la journée qu'on choisit quand il en
 * manque deux.
 *
 * Une journée seule n'ouvre aucune question : MEMO la nomme et écoute — le
 * code connaît déjà la réponse, et MEMO ne pose jamais une question de plus.
 * Deux journées en posent **une**, avec ses deux puces datées.
 *
 * Sans proposition en vol (un vieux bouton rejoué, une conversation effacée
 * entre-temps), MEMO répond sans ouvrir de mode : aucune date fausse possible.
 */
async function converseMissingDay(
  context: AppContext,
  message: NonNullable<Awaited<ReturnType<typeof loadTurn>>>,
  state: ConversationState,
  now: Date,
): Promise<void> {
  const { prisma } = context;
  const offered = state.gapOffered?.days ?? [];
  const chosen = message.suggestionId ? dayOfGapDayId(message.suggestionId) : null;

  // La journée de ce tour : celle qu'on a touchée, ou la seule proposée.
  const day = chosen && offered.includes(chosen) ? chosen : offered.length === 1 ? offered[0]! : null;
  const asksWhich = day === null && offered.length > 1;

  const text = asksWhich ? MISSING_DAY_WHICH : day ? missingDayListening(day) : ACKNOWLEDGED_EARLIER;
  const suggestions = asksWhich ? offered.map((candidate) => gapDayId(candidate)) : [];

  await prisma.$transaction(async (tx) => {
    await tx.chatMessage.update({
      where: { id: message.id },
      data: { disposition: "command", repliedAt: now },
    });
    await tx.chatMessage.create({
      data: {
        memoId: message.memoId,
        author: "memo",
        kind: "text",
        text,
        replyToId: message.id,
        stepId: message.stepId,
        pauseMilliseconds: pauseBeforeSaying(text),
        model: "scripted",
        payload: { suggestions },
      },
    });

    // La question des deux journées laisse la proposition en vol : c'est la
    // puce qui l'acceptera. Une journée choisie la referme — et elle entre au
    // registre, comblée ou non : on ne la repropose jamais.
    const next = asksWhich
      ? state
      : day
        ? withGapAccepted(state, offered, day, now)
        : { ...state, gapOffered: null };

    await tx.memo.update({
      where: { id: message.memoId },
      data: { conversationState: next as unknown as Prisma.InputJsonObject },
    });
  });

  context.logger.info(
    { memoId: message.memoId, day, asksWhich },
    "MEMO revient sur une journée manquante",
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
 * Les réglages du carnet qui entrent dans le calcul du nombre de photos : le
 * ratio texte / photo, les fun facts, les décorations. Lus au moment où la
 * question se pose — le voyageur peut changer son ratio à tout moment, et
 * l'étape suivante doit en tenir compte.
 */
async function reglagesDuCarnet(
  context: AppContext,
  memoId: string,
): Promise<PhotoBudgetSettings> {
  const memo = await context.prisma.memo.findUnique({
    where: { id: memoId },
    select: { photoTextRatio: true, funFactsEnabled: true, decorationQuota: true },
  });
  return memo ?? {};
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
  isEarlierStep: boolean,
): Promise<ConversationReply> {
  const entry = entryId ? await context.prisma.entry.findUnique({ where: { id: entryId } }) : null;
  const validated = entry ? finalTextOf(entry) : null;
  // Une étape d'avant, à laquelle MEMO est revenu : elle était déjà comptée.
  const acknowledged = isEarlierStep ? ACKNOWLEDGED_EARLIER : ACKNOWLEDGED;
  if (!entry || !validated) {
    return flowReply(composeBeats(received, [acknowledged]), [...SUGGESTION_SETS.afterAccept], "command", null);
  }
  const budget = photoBudgetFor(validated.trim(), await reglagesDuCarnet(context, entry.memoId));
  // À 0 % de photos, le carnet n'en porte aucune : on ne réclame pas au
  // voyageur des images que le gabarit jettera.
  if (budget.photos === 0) {
    return flowReply(composeBeats(received, [acknowledged]), [...SUGGESTION_SETS.afterAccept], "command", null);
  }
  return flowReply(
    composeBeats(received, [acknowledged, photosWanted(budget.photos, budget.pages)]),
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

  const targetId = await photosTargetEntryId(prisma, message.memoId);
  const target = targetId ? await prisma.entry.findUnique({ where: { id: targetId } }) : null;
  const current = target ? null : await loadCurrentEntry(prisma, message.memoId, message.seq);
  const count = photoBudgetFor(
    ((target ? finalTextOf(target) : current?.text) ?? "").trim(),
    await reglagesDuCarnet(context, message.memoId),
  ).photos;
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
        payload: {
          entryIds: entries.map((entry) => entry.id),
          ...(targetId ? { forEntryId: targetId } : {}),
        },
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
