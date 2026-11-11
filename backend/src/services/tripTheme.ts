import type { AppContext } from "../context.js";
import { pauseBeforeSaying, type MemoResponder } from "./conversation.js";
import { TRIP_THEME_QUESTION } from "./conversationCopy.js";

/**
 * **Le thème d'un voyage se devine tout seul** (Hugo, 10/11/2026) — « le
 * thème de l'aventure devrait être déterminé automatiquement au bout de
 * quelques étapes, et si aucun ne match, le chat devrait le demander
 * subtilement ».
 *
 * L'étape « Contexte » a quitté le parcours de création le 17/09 (décision
 * D27) : depuis, presque aucun voyage n'a de thème, et celui-ci donne
 * pourtant son ton au carnet. Plutôt que de remettre une question à
 * l'inscription — le moment où l'on a le moins à dire —, on attend d'avoir lu
 * quelque chose.
 *
 * ### Ce qui déclenche
 *
 * Trois conditions, toutes nécessaires : le voyage **n'a pas de thème**, il a
 * au moins [MEMORIES_BEFORE_GUESSING] souvenirs **écrits**, et on ne lui a
 * **jamais** demandé. La dernière est ce qui empêche la question de revenir à
 * chaque souvenir ; elle tient dans `memos.themeAskedAt`.
 *
 * ### Ce qui se passe
 *
 * Un appel court et séparé (`MemoResponder.suggestTheme`), sur le modèle de
 * la question du trou : son prompt, son schéma, et une réponse refusée si
 * elle sort du catalogue. Le modèle range le voyage, ou dit que rien ne va.
 *
 * - **Un thème** : il s'écrit, et personne n'est dérangé. C'est le cas qu'on
 *   vise — la fonctionnalité réussie est celle qui ne se voit pas.
 * - **Rien** : MEMO pose la question, une fois, sans bouton. La réponse du
 *   voyageur entre au contexte du voyage comme le reste de ce qu'il raconte ;
 *   on ne la relit pas pour en extraire un slug, parce qu'un voyage qui ne
 *   tient dans aucune case n'a pas à y entrer de force.
 *
 * ### Ce qu'on ne fait pas
 *
 * **On ne touche jamais à un thème déjà posé.** Celui que le voyageur a
 * choisi dans les réglages fait autorité, et un modèle qui le corrigerait
 * serait insupportable. Le deviner ne vaut que pour un champ vide.
 *
 * **On n'écrit jamais « autre ».** C'est le thème qui ouvre un champ libre :
 * le deviner reviendrait à ne rien dire tout en fermant la question.
 */

/**
 * Combien de souvenirs écrits avant de deviner. Trois : un seul ne dit rien
 * d'un voyage — une arrivée à l'aéroport ressemble à toutes les arrivées —,
 * et attendre davantage laisserait passer les voyages courts, qui sont
 * justement ceux d'un week-end à thème.
 */
export const MEMORIES_BEFORE_GUESSING = 3;

/** Ce qu'on montre au modèle : assez pour juger, pas tout le carnet. */
export const MEMORIES_SHOWN = 8;

/** Ce que la fonction a fait, pour le journal et pour les tests. */
export type TripThemeOutcome =
  | { kind: "skipped"; why: "already-set" | "already-asked" | "too-early" }
  | { kind: "guessed"; slug: string; model: string }
  | { kind: "asked"; model: string };

/**
 * Devine le thème du voyage, ou fait poser la question — une fois.
 *
 * Appelée après qu'un souvenir est entré au carnet. Elle ne lève jamais : un
 * thème est un agrément, et rater sa déduction ne doit pas faire échouer le
 * tour qui vient d'être raconté. Un échec du modèle laisse le voyage sans
 * thème **et sans date de question**, pour que le souvenir suivant réessaie.
 */
export async function settleTripTheme(
  context: AppContext,
  responder: MemoResponder,
  memoId: string,
  now: Date = new Date(),
): Promise<TripThemeOutcome> {
  const { prisma, logger } = context;

  const memo = await prisma.memo.findUnique({
    where: { id: memoId },
    select: {
      title: true,
      theme: true,
      themeAskedAt: true,
      destinationCity: true,
      members: {
        where: { status: "active" },
        select: { account: { select: { firstName: true } } },
      },
    },
  });
  if (!memo) return { kind: "skipped", why: "too-early" };
  if (memo.theme !== null && memo.theme.trim().length > 0) {
    return { kind: "skipped", why: "already-set" };
  }
  if (memo.themeAskedAt !== null) return { kind: "skipped", why: "already-asked" };

  // Les souvenirs **écrits** : un vocal en cours de transcription ne dit rien
  // encore, et le compter ferait deviner sur du vide.
  const written = await prisma.entry.findMany({
    where: { memoId, kind: { not: "photo" }, redactedText: { not: null } },
    orderBy: { capturedAt: "asc" },
    take: MEMORIES_SHOWN,
    select: { redactedText: true },
  });
  if (written.length < MEMORIES_BEFORE_GUESSING) return { kind: "skipped", why: "too-early" };

  const themes = await prisma.tripTheme.findMany({
    where: { slug: { not: "autre" } },
    orderBy: { position: "asc" },
    select: { slug: true, name: true },
  });
  if (themes.length === 0) return { kind: "skipped", why: "too-early" };

  let slug: string | null = null;
  let model = "none";
  try {
    const suggested = await responder.suggestTheme({
      memo: { title: memo.title, destinationCity: memo.destinationCity },
      memories: written.map((entry) => entry.redactedText ?? "").filter((text) => text.length > 0),
      companions: memo.members
        .map((member) => member.account?.firstName ?? null)
        .filter((name): name is string => Boolean(name)),
      themes,
    });
    slug = suggested.slug;
    model = suggested.model;
  } catch (cause) {
    // Le souvenir suivant réessaiera : rien n'est écrit, pas même la date.
    logger.warn({ err: cause, memoId }, "Le thème n'a pas pu être deviné.");
    return { kind: "skipped", why: "too-early" };
  }

  if (slug !== null) {
    // ⚠️ **C'est le nom qu'on écrit, pas le slug.** `memos.theme` porte le
    // libellé lisible — la feuille des réglages le compare au `name` du
    // catalogue, et la rédaction l'écrit tel quel dans son prompt
    // (« Thème : … »). Y poser `city-trips` afficherait `city-trips` au
    // voyageur et le donnerait tel quel à l'écrivain. Le modèle répond par un
    // slug parce qu'un slug ne s'invente pas ; c'est ici qu'il redevient une
    // phrase.
    const chosen = themes.find((theme) => theme.slug === slug);
    if (!chosen) return { kind: "skipped", why: "too-early" };
    await prisma.memo.update({ where: { id: memoId }, data: { theme: chosen.name } });
    logger.info({ memoId, theme: chosen.name, slug, model }, "Thème du voyage deviné.");
    return { kind: "guessed", slug, model };
  }

  // Aucun thème ne va : MEMO demande, une fois. La date part dans la même
  // transaction que la bulle — sans quoi une panne entre les deux ferait
  // reposer la question au souvenir suivant.
  await prisma.$transaction(async (tx) => {
    await tx.chatMessage.create({
      data: {
        memoId,
        author: "memo",
        kind: "text",
        text: TRIP_THEME_QUESTION,
        pauseMilliseconds: pauseBeforeSaying(TRIP_THEME_QUESTION),
        model: "scripted",
        payload: {},
      },
    });
    await tx.memo.update({ where: { id: memoId }, data: { themeAskedAt: now } });
  });
  logger.info({ memoId, model }, "Aucun thème ne va : MEMO a demandé.");
  return { kind: "asked", model };
}
