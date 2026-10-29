import { Prisma } from "@prisma/client";
import type { AppContext } from "../context.js";
import {
  EMPTY_COHERENCE_SHEET,
  parseInsights,
  type CoherenceSheet,
  type QuizHistory,
  type RedactedNeighbour,
  type RedactionInput,
  type RedactionPrecision,
} from "../services/redaction.js";

import { describeTripContext, parseTripContext } from "../services/tripContext.js";
import { askValidation, firstNameOf } from "../services/conversationThread.js";
import { refreshTripFactsQuietly } from "../services/tripFacts.js";

export interface RedactJob {
  entryId: string;
  /**
   * Une réécriture après un changement de cible (`jobs/rewriteTrip.ts`) : le
   * souvenir a déjà été validé, MEMO ne le repropose pas dans le fil.
   */
  rewrite?: boolean;
}

/**
 * **Le texte qui fait foi pour un souvenir** — celui que le carnet imprime,
 * celui que la fiche du fil montre, celui que MEMO relit.
 *
 * Trois états, dans cet ordre :
 *
 * 1. la **correction au clavier** (`editedText`), toujours devant : ce sont
 *    les mots de quelqu'un, et la mise en page les reprend au mot près ;
 * 2. ce que le voyageur a **choisi de garder** (`prefersTranscript`, Hugo,
 *    28/10/2026) : la transcription littérale plutôt que le texte rédigé ;
 * 3. sinon le texte rédigé, et la transcription brute en dernier recours —
 *    une rédaction échouée vaut mieux qu'un carnet vide.
 *
 * `prefersTranscript` est **obligatoire dans le type**, et c'est voulu : la
 * hiérarchie était recopiée à quatre endroits, et un champ qu'on oublie de
 * lire rendrait au carnet un texte que le voyageur n'a pas choisi. Le
 * compilateur réclame donc la colonne à chaque appelant.
 */
export function finalTextOf(entry: {
  editedText: string | null;
  redactedText: string | null;
  transcript: string | null;
  prefersTranscript: boolean;
}): string | null {
  if (entry.editedText !== null) return entry.editedText;
  if (entry.prefersTranscript && entry.transcript !== null) return entry.transcript;
  return entry.redactedText ?? entry.transcript;
}

/**
 * La fiche de cohérence stockée est du JSON libre côté base : elle est relue
 * ici de façon défensive. Une fiche corrompue par une ancienne version du
 * schéma ne doit pas bloquer la rédaction — on repart d'une fiche vide plutôt
 * que de faire échouer le souvenir.
 */
export function parseCoherenceSheet(value: unknown): CoherenceSheet {
  if (!value || typeof value !== "object") return EMPTY_COHERENCE_SHEET;
  const candidate = value as Partial<CoherenceSheet>;

  return {
    people: Array.isArray(candidate.people) ? candidate.people : [],
    places: Array.isArray(candidate.places) ? candidate.places : [],
    lexicon: Array.isArray(candidate.lexicon) ? candidate.lexicon : [],
    narration:
      candidate.narration && typeof candidate.narration === "object"
        ? candidate.narration
        : EMPTY_COHERENCE_SHEET.narration,
    figures: Array.isArray(candidate.figures) ? candidate.figures : [],
    voice: Array.isArray(candidate.voice)
      ? candidate.voice.filter((line): line is string => typeof line === "string")
      : [],
  };
}

/**
 * Ce que la rédaction lit d'une entrée : son carnet, avec de quoi savoir qui
 * raconte et avec qui, et l'étape du voyage à laquelle elle appartient.
 */
export const ENTRY_FOR_REDACTION = {
  memo: {
    include: {
      owner: { select: { firstName: true, lastName: true } },
      members: {
        where: { status: "active" },
        select: { accountId: true, displayName: true, account: { select: { firstName: true, lastName: true } } },
      },
    },
  },
  step: true,
} satisfies Prisma.EntryInclude;

export type EntryForRedaction = Prisma.EntryGetPayload<{ include: typeof ENTRY_FOR_REDACTION }>;

/**
 * Étape 2 : la transcription brute devient un texte de carnet.
 *
 * Le job est **sérialisé par carnet** de fait : il lit la fiche de cohérence,
 * rédige, puis la réécrit. Deux souvenirs enregistrés coup sur coup partent
 * donc l'un après l'autre dans la file — c'est voulu, la cohérence dépend de
 * l'ordre. C'est aussi pour ça que le job ne se contente pas de la
 * transcription : il reçoit les étapes déjà validées, qui portent la voix.
 */
export async function redactEntry(
  context: AppContext,
  { entryId, rewrite = false }: RedactJob,
): Promise<void> {
  const { prisma, redactor, logger } = context;

  const entry = await prisma.entry.findUnique({
    where: { id: entryId },
    include: ENTRY_FOR_REDACTION,
  });

  if (!entry) {
    logger.warn({ entryId }, "Entrée introuvable, job de rédaction ignoré");
    return;
  }

  // Une photo seule n'a rien à rédiger, et un texte déjà corrigé à la main ne
  // doit surtout pas être réécrit par-dessus.
  if (entry.kind === "photo" || !entry.transcript || entry.editedText) {
    await prisma.entry.update({
      where: { id: entryId },
      data: { redactionStatus: "ready", redactionError: null },
    });
    return;
  }

  await prisma.entry.update({
    where: { id: entryId },
    data: { redactionStatus: "processing", redactionError: null },
  });

  const started = Date.now();
  try {
    // Trois lectures indépendantes, lancées ensemble : elles précédaient
    // l'appel au modèle l'une après l'autre (Hugo, 18/10/2026 — « la
    // retranscription des étapes est un peu trop longue »).
    const [earlier, precisionRows, narrator] = await Promise.all([
      // Les voisines : uniquement celles qui ont un texte abouti. Une étape en
      // cours de transcription n'apprend rien sur la voix du voyageur.
      prisma.entry.findMany({
        where: {
          memoId: entry.memoId,
          kind: { not: "photo" },
          capturedAt: { lt: entry.capturedAt },
        },
        orderBy: { capturedAt: "asc" },
      }),
      // Les précisions données dans la conversation — « c'était avec Clara, le
      // mardi » — font partie du récit au même titre que la transcription. Le
      // job `converse` les rattache au souvenir en cours (`disposition:
      // context`) et relance cette rédaction pour qu'elles atteignent le texte.
      prisma.chatMessage.findMany({
        where: { entryId, author: "traveller", disposition: "context", text: { not: null } },
        orderBy: { seq: "asc" },
        select: { text: true, payload: true },
      }),
      narratorOf(context, entry),
    ]);

    const previous: RedactedNeighbour[] = earlier.flatMap((neighbour) => {
      const text = neighbour.editedText ?? neighbour.redactedText;
      if (!text) return [];
      return [
        {
          capturedAt: neighbour.capturedAt,
          placeLabel: neighbour.placeLabel,
          title: neighbour.suggestedTitle,
          text,
        },
      ];
    });

    const precisions: RedactionPrecision[] = precisionRows.flatMap((row) => {
      if (!row.text) return [];
      const rawTopic =
        row.payload && typeof row.payload === "object" && "topic" in row.payload
          ? (row.payload as { topic?: unknown }).topic
          : undefined;
      return [{ text: row.text, topic: typeof rawTopic === "string" && rawTopic ? rawTopic : null }];
    });

    const quizzes = quizHistoryOf(earlier, entry);
    const memo = entry.memo;
    const modelStarted = Date.now();
    const result = await redactor.redact({
      memo: {
        title: memo.title,
        subtitle: memo.subtitle,
        authors: memo.authors,
        theme: memo.theme,
        styleKey: memo.styleKey,
        tripContext: describeTripContext(parseTripContext(memo.tripContext), narrator.firstName),
        startDate: memo.startDate,
        endDate: memo.endDate,
        destination: [...new Set([memo.destinationCity, memo.destinationName].filter(Boolean))].join(", ") || null,
        narrationPace: memo.narrationPace,
        // La cible du moment : un changement en cours de voyage vaut pour les
        // étapes suivantes, et pour celles qu'on réécrit (`rewriteTrip.ts`).
        targetPageCount: memo.targetPageCount,
        photoTextRatio: memo.photoTextRatio,
      },
      narrator,
      entry: {
        transcript: entry.transcript,
        capturedAt: entry.capturedAt,
        placeLabel: entry.placeLabel,
        precisions,
        step: entry.step
          ? {
              number: entry.step.number,
              placeName: entry.step.placeName,
              startDate: entry.step.startDate,
              endDate: entry.step.endDate,
            }
          : null,
      },
      coherenceSheet: parseCoherenceSheet(memo.coherenceSheet),
      previous,
      // Tout le carnet, pas seulement les trois dernières étapes : un encart
      // ne se répète pas à dix étapes d'écart non plus.
      earlier: {
        titles: earlier.flatMap((neighbour) => (neighbour.suggestedTitle ? [neighbour.suggestedTitle] : [])),
        funFacts: earlier.flatMap((neighbour) => (neighbour.funFact ? [neighbour.funFact] : [])),
      },
      quizzes,
    });
    // Un seul quiz par étape : la règle ne dépend pas de l'écrivain.
    const quiz = quizzes.thisStepHasOne ? null : result.quiz;

    // La fiche et le texte sont écrits ensemble : une fiche mise à jour pour
    // un texte qui n'a pas été enregistré ferait dériver toutes les étapes
    // suivantes.
    await prisma.$transaction([
      prisma.entry.update({
        where: { id: entryId },
        data: {
          redactedText: result.text,
          suggestedTitle: result.title,
          weatherKey: result.weatherKey,
          funFact: result.funFact,
          funFactTitle: result.funFactTitle,
          // Écrit même quand le réglage Quiz est coupé, comme le fun fact :
          // c'est la composition qui l'écarte (`structure.ts`).
          quizQuestion: quiz?.question ?? null,
          quizAnswers: quiz ? quiz.choices : Prisma.DbNull,
          quizAnswerIndex: quiz?.answerIndex ?? null,
          // Le relevé part avec le texte : c'est lui que le profil additionne,
          // et c'est à cet instant que les statistiques bougent.
          insights: parseInsights(result.insights) as unknown as Prisma.InputJsonObject,
          redactionStatus: "ready",
          redactionModel: result.model,
          redactedAt: new Date(),
          redactionError: null,
        },
      }),
      prisma.memo.update({
        where: { id: entry.memoId },
        data: { coherenceSheet: result.coherenceSheet as unknown as Prisma.InputJsonObject },
      }),
    ]);

    logger.info(
      {
        entryId,
        model: result.model,
        characters: result.text.length,
        modelMs: Date.now() - modelStarted,
        totalMs: Date.now() - started,
      },
      "Souvenir rédigé",
    );
    // « Il te convient ? » d'abord : c'est la bulle que le voyageur attend.
    // Les étapes et les chiffres du voyage (T227) se recalculent ensuite — une
    // transaction verrouillée qui la retardait sans rien lui apporter ; la
    // fiche de l'étape se met à jour au tour de relecture suivant de l'app.
    if (!rewrite) await askValidation(prisma, entryId, result.doubts);
    await refreshTripFactsQuietly(context, entry.memoId);
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    await prisma.entry.update({
      where: { id: entryId },
      data: { redactionStatus: "failed", redactionError: message },
    });
    // Sans relevé, le souvenir compte quand même (T227).
    await refreshTripFactsQuietly(context, entry.memoId);
    // La fiche garde le texte brut : il se valide quand même.
    if (!rewrite) await askValidation(prisma, entryId).catch(() => false);
    throw cause;
  }
}

/**
 * Où en est le carnet de ses quiz, vu du souvenir à rédiger : les questions
 * déjà posées, et combien d'étapes le séparent du dernier quiz — environ un
 * toutes les trois étapes (Hugo, 15/10/2026).
 *
 * Une étape se reconnaît à son `stepId` ; un souvenir hors étape compte pour
 * une étape à lui seul. Seuls comptent les souvenirs enregistrés avant
 * celui-ci : une rédaction relancée ne se compte pas elle-même.
 */
export function quizHistoryOf(
  earlier: { id: string; stepId: string | null; quizQuestion: string | null }[],
  entry: { id: string; stepId: string | null },
): QuizHistory {
  const stepOf = (row: { id: string; stepId: string | null }) => row.stepId ?? row.id;
  const steps = [...new Set([...earlier.map(stepOf), stepOf(entry)])];
  const withQuiz = earlier.filter((row) => row.quizQuestion);
  const last = withQuiz[withQuiz.length - 1];
  const current = stepOf(entry);
  return {
    asked: withQuiz.map((row) => row.quizQuestion as string),
    stepsSinceLast: last ? steps.indexOf(current) - steps.indexOf(stepOf(last)) : null,
    thisStepHasOne: withQuiz.some((row) => stepOf(row) === current),
  };
}

/**
 * Qui raconte : le compte qui a envoyé le vocal — la bulle du voyageur qui
 * porte ce souvenir —, à défaut le propriétaire du carnet. Les autres membres
 * du carnet sont ses compagnons, sous le nom qu'ils y portent.
 */
export async function narratorOf(
  context: AppContext,
  entry: EntryForRedaction,
): Promise<NonNullable<RedactionInput["narrator"]>> {
  const { memo } = entry;
  const message = await context.prisma.chatMessage.findFirst({
    where: { entryId: entry.id, author: "traveller", accountId: { not: null } },
    orderBy: { seq: "asc" },
    select: { accountId: true, account: { select: { firstName: true, lastName: true } } },
  });
  const narratorAccountId = message?.accountId ?? memo.ownerAccountId;
  const firstName = message?.account ? firstNameOf(message.account) : firstNameOf(memo.owner);

  const others = [
    narratorAccountId === memo.ownerAccountId ? null : firstNameOf(memo.owner),
    ...memo.members
      .filter((member) => member.accountId !== narratorAccountId)
      .map((member) => member.displayName?.trim() || firstNameOf(member.account)),
  ];
  const companions = [...new Set(others)].filter(
    (name): name is string => Boolean(name) && name !== firstName,
  );
  return { firstName, companions };
}
