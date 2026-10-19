/**
 * Le nombre de pages cible : ce que la rédaction en fait, et combien de fois
 * on peut le changer.
 *
 * **La cible règle la densité du récit, pas la mise en page.** Le texte d'une
 * étape est écrit une fois, à la rédaction ; c'est donc là que la cible doit
 * peser. Un récit « Compact » prend des tailles d'étape plus courtes, un récit
 * « Détaillé » des plus longues — toujours dans le barème S / M / L / XL et
 * jamais au-delà de ce que le vocal raconte (§ 9 de
 * `agents/agent-transcription.md` : on ne gonfle pas). Le carnet visé tient
 * dans la cible à ± 5 pages (`PAGE_TARGET_TOLERANCE`).
 *
 * **Deux changements par voyage** (Hugo, 15/10/2026). Chaque changement ouvre
 * le droit de réécrire les étapes déjà rédigées à la nouvelle densité — tout
 * le carnet repasse par l'IA, ce qui coûte. Un changement ne compte qu'à partir
 * du moment où une étape est écrite : avant, il n'y a rien à homogénéiser, et
 * régler sa cible le premier soir n'est pas un changement.
 */

import type { PrismaClient } from "@prisma/client";
import { normaliserRatio, RATIO_DEFAUT, type PhotoRatio } from "./photoRatio.js";

export const PAGE_TARGET_CHANGE_LIMIT = 2;

/**
 * L'écart toléré entre le carnet composé et sa cible, dans chaque sens. La
 * composition y recale le carnet par ses planches de photos
 * (`recalerSurLaCible`, `MemoBook Generator/public/mise-en-page.js`, qui en
 * recopie la valeur : `TOLERANCE_PAGES_CIBLE`).
 */
export const PAGE_TARGET_TOLERANCE = 5;

/** Sans durée connue — pas de date de fin —, le palier « Par défaut » vise 60 pages (à 50 %). */
const DEFAULT_STANDARD_PAGES = 60;

const DAY_MS = 24 * 60 * 60 * 1000;

const roundedToTen = (value: number) => Math.round(value / 10) * 10;

/**
 * **Les paliers dépendent aussi du ratio photo / texte** (Hugo, 18/10/2026).
 * Le palier « Par défaut » vise une page par jour à 50 % ; un carnet plus
 * écrit en vise moins, un carnet plus photographique davantage. C'est ce que
 * le carnet peut réellement atteindre : une étape fait presque toujours deux
 * pages de récit, et ce qui l'allonge, ce sont ses pages de photos — aucune à
 * 0 %, une double page de plus jusqu'à 50 %, deux à 75 % et au-delà
 * (`EXTRA_PHOTO_PAGES`). Sans date de fin : 40 / 50 / 60 / 70 / 80 pages.
 *
 * Recopié dans l'app (`BookPageTarget.ratioFactor`) et dans l'atelier
 * (`FACTEUR_RATIO_PAGES`, `app.js`) : les trois doivent rester d'accord.
 */
export const RATIO_PAGE_FACTOR: Readonly<Record<PhotoRatio, number>> = {
  0: 0.7,
  25: 0.85,
  50: 1,
  75: 1.15,
  100: 1.3,
};

/**
 * Les pages du palier « Par défaut » pour un voyage de `days` jours au ratio
 * `ratio`. Recopie de `BookPageTarget.standardPageCount` (app) : une page par
 * jour à 50 %, pondérée par le ratio, à la dizaine, entre 30 et 180.
 */
export function standardPageCount(days: number | null, ratio: number = RATIO_DEFAUT): number {
  const factor = RATIO_PAGE_FACTOR[normaliserRatio(ratio)];
  if (!days || days <= 0) return roundedToTen(DEFAULT_STANDARD_PAGES * factor);
  return Math.min(Math.max(roundedToTen(days * factor), 30), 180);
}

/** Les trois paliers de la feuille « Nombre de page » : ×2/3, ×1, ×4/3 du palier par défaut. */
export function pageTargetTiers(days: number | null, ratio: number = RATIO_DEFAUT) {
  const standard = standardPageCount(days, ratio);
  return {
    compact: roundedToTen((standard * 2) / 3),
    standard,
    detailed: roundedToTen((standard * 4) / 3),
  };
}

export type PageTargetTier = keyof ReturnType<typeof pageTargetTiers>;

/** Le palier sur lequel tombe une cible, ou `null` pour une cible personnalisée. */
export function pageTargetTierOf(target: number, days: number | null, ratio: number): PageTargetTier | null {
  const tiers = pageTargetTiers(days, ratio);
  return (Object.keys(tiers) as PageTargetTier[]).find((tier) => tiers[tier] === target) ?? null;
}

/** Les jours du voyage, bornes comprises. `null` sans date de fin : on ne sait pas encore. */
export function tripDays(startDate: Date | null, endDate: Date | null): number | null {
  if (!startDate || !endDate) return null;
  return Math.max(1, Math.round((endDate.getTime() - startDate.getTime()) / DAY_MS) + 1);
}

export type PageDensity = "compact" | "standard" | "detailed";

/**
 * La densité que la cible demande, lue par rapport au palier « Par défaut »
 * du voyage. Les paliers de l'app sont à ×2/3 et ×4/3 ; une cible
 * personnalisée tombe dans le plus proche.
 */
export function pageDensity(targetPageCount: number, days: number | null, ratio: number = RATIO_DEFAUT): PageDensity {
  const relative = targetPageCount / standardPageCount(days, ratio);
  if (relative <= 5 / 6) return "compact";
  if (relative >= 7 / 6) return "detailed";
  return "standard";
}

/* ----------------------------------------- ce que le carnet peut atteindre --- */

/**
 * Les pages hors étapes que compte la cible : colophon, introduction, page
 * blanche pour ouvrir la première étape à gauche, page blanche finale. Une
 * estimation — le carnet composé dit le vrai compte (`composedPageCount`).
 */
export const FIXED_PAGES = 4;

/** Une étape : deux pages au moins (un nombre pair), six au plus (`MAX_PAGES_ETAPE`, `mise-en-page.js`). */
export const MIN_STEP_PAGES = 2;
export const MAX_STEP_PAGES = 6;

/**
 * Les pages de photos qu'une étape peut prendre **au-delà de son ratio** pour
 * que le carnet atteigne sa cible (Hugo, 18/10/2026 : « la cible peut ajouter
 * des photos au-delà du ratio », sur des pages de photos seulement). Aucune à
 * 0 % : le carnet n'a pas de photo. Une double page jusqu'à 50 %, deux au-delà.
 */
export const EXTRA_PHOTO_PAGES: Readonly<Record<PhotoRatio, number>> = { 0: 0, 25: 2, 50: 2, 75: 4, 100: 4 };

/** Les photos d'une page de photos ajoutée pour la cible (`PHOTOS_PAR_PAGE_SURPLUS`, `mise-en-page.js`). */
export const PHOTOS_PER_EXTRA_PAGE = 3;

/**
 * La taille XXL (Hugo, 18/10/2026) : trois à quatre pages de récit pour un
 * vocal très riche, **réservée à la cible « Détaillé »**. Une étape de cible
 * détaillée peut donc compter jusqu'à quatre pages de récit.
 */
export const XXL_STEP_PAGES = 4;

/** Sans date de fin, on compte trois semaines pour estimer le nombre d'étapes. */
const DAYS_WITHOUT_END = 21;

const DAYS_PER_STEP: Readonly<Record<string, number>> = {
  daily: 1,
  every_two_days: 2,
  every_three_days: 3,
  weekly: 7,
};

/**
 * Combien d'étapes le voyage comptera, estimé sur sa durée et le rythme du
 * récit (« tous les jours », « tous les deux jours »…) — jamais moins que
 * celles déjà racontées. Un rythme libre (« à chaque lieu », personnalisé)
 * compte une étape tous les deux jours.
 */
export function expectedStepCount(days: number | null, pace: string | null, writtenSteps: number): number {
  const perStep = (pace && DAYS_PER_STEP[pace]) || 2;
  const expected = Math.max(1, Math.round((days ?? DAYS_WITHOUT_END) / perStep));
  return Math.max(writtenSteps, expected);
}

const evenUp = (pages: number) => Math.max(MIN_STEP_PAGES, pages + (pages % 2));

export interface PhotosForTarget {
  /** Les pages de photos que l'étape prend en plus, pour la cible. */
  extraPages: number;
  /** Les photos à demander en plus du ratio. */
  extraPhotos: number;
}

/**
 * **Les photos que la cible demande en plus du ratio**, pour une étape dont
 * le récit occupe `stepPages` pages (Hugo, 18/10/2026 : « il faut que le chat
 * demande plus de photos au voyageur quand sa cible l'exige »).
 *
 * La cible se répartit sur les étapes attendues : chacune vise
 * `(cible − pages fixes) / étapes`. Ce qui manque à celle-ci se comble par des
 * pages de photos — deux à la fois, l'étape restant paire —, dans la limite
 * que le ratio autorise (`EXTRA_PHOTO_PAGES`) et des six pages d'une étape.
 * Trois photos par page ajoutée. Rien quand le récit suffit, ni sans date de
 * fin.
 */
export function photosForTarget(input: {
  targetPageCount: number;
  ratio: number;
  days: number | null;
  pace: string | null;
  writtenSteps: number;
  stepPages: number;
}): PhotosForTarget {
  // **Sans date de fin, rien en plus** : on ne sait pas combien d'étapes le
  // voyage comptera, et en supposer trop peu ferait demander six photos de
  // plus à chaque étape d'un carnet qui atteindra sa cible tout seul.
  if (!input.days) return { extraPages: 0, extraPhotos: 0 };
  const ratio = normaliserRatio(input.ratio);
  const steps = expectedStepCount(input.days, input.pace, input.writtenSteps);
  const perStep = (input.targetPageCount - FIXED_PAGES) / steps;
  const pages = evenUp(input.stepPages);
  const room = Math.min(EXTRA_PHOTO_PAGES[ratio], MAX_STEP_PAGES - pages);
  const missing = Math.floor(Math.max(0, perStep - pages) / 2) * 2;
  // Plus près de la cible en arrondissant à la double page la plus proche.
  const rounded = perStep - pages - missing >= 1 ? missing + 2 : missing;
  const extraPages = Math.max(0, Math.min(room, rounded));
  return { extraPages, extraPhotos: extraPages * PHOTOS_PER_EXTRA_PAGE };
}

export interface PageRange {
  min: number;
  max: number;
}

/**
 * **Ce que le carnet peut atteindre**, avec les réglages du moment — la
 * fourchette que dit la feuille d'une cible personnalisée irréalisable (Hugo,
 * 18/10/2026). Les étapes déjà écrites comptent pour leurs vraies pages de
 * récit (`writtenStepPages`) ; celles qui restent à raconter, pour une étape
 * ordinaire de deux pages — quatre en récit détaillé, la taille XXL.
 *
 * - **au plus court** : chaque étape à son récit seul, rendu pair ;
 * - **au plus long** : chaque étape avec toutes les pages de photos que le
 *   ratio autorise (`EXTRA_PHOTO_PAGES`), dans ses six pages.
 *
 * Plus de souvenirs racontés, ou plus de photos envoyées, et la fourchette
 * bouge : elle se relit à chaque ouverture des réglages.
 */
export function reachablePageRange(input: {
  ratio: number;
  density: PageDensity;
  days: number | null;
  pace: string | null;
  writtenStepPages: readonly number[];
}): PageRange & { steps: number } {
  const ratio = normaliserRatio(input.ratio);
  const steps = expectedStepCount(input.days, input.pace, input.writtenStepPages.length);
  const remaining = steps - input.writtenStepPages.length;
  const upcoming = input.density === "detailed" ? XXL_STEP_PAGES : MIN_STEP_PAGES;
  const all = [...input.writtenStepPages.map(evenUp), ...Array.from({ length: remaining }, () => MIN_STEP_PAGES)];
  const longest = [
    ...input.writtenStepPages.map(evenUp),
    ...Array.from({ length: remaining }, () => upcoming),
  ].map((pages) => Math.min(MAX_STEP_PAGES, pages + EXTRA_PHOTO_PAGES[ratio]));
  const sum = (pages: number[]) => pages.reduce((total, n) => total + n, 0);
  return { min: FIXED_PAGES + sum(all), max: FIXED_PAGES + sum(longest), steps };
}

/** Ce que la rédaction lit de la cible, en une ligne de consigne. */
export function pageDensityInstruction(targetPageCount: number, days: number | null, ratio: number = RATIO_DEFAUT): string {
  const lo = Math.max(16, targetPageCount - PAGE_TARGET_TOLERANCE);
  const hi = targetPageCount + PAGE_TARGET_TOLERANCE;
  const cible = `Nombre de pages cible du carnet : ${targetPageCount} (entre ${lo} et ${hi})`;
  switch (pageDensity(targetPageCount, days, ratio)) {
    case "compact":
      return `${cible} — récit **compact** : prends la plus petite taille qui garde le cœur de l'étape (S ou M le plus souvent, L pour une étape qui porte le voyage, jamais XL ni XXL). Garde le cœur, laisse les détails secondaires.`;
    case "detailed":
      return `${cible} — récit **détaillé** : quand le vocal a la matière, prends la taille au-dessus (L ou XL, et **XXL** pour un vocal très riche — la seule cible qui l'autorise) et garde les détails, les noms, les petites scènes. Sans matière, reste court : on ne gonfle jamais.`;
    default:
      return `${cible} — récit **par défaut** : la taille que la matière du vocal demande, sans tirer vers le court ni vers le long, jamais XXL.`;
  }
}

/** Une étape au moins est rédigée : un changement de cible compte, et la réécriture a un sens. */
export async function hasWrittenStory(prisma: PrismaClient, memoId: string): Promise<boolean> {
  const written = await prisma.entry.findFirst({
    where: { memoId, kind: { not: "photo" }, redactedText: { not: null } },
    select: { id: true },
  });
  return written !== null;
}

/** Ce que l'app lit pour annoncer, avant de changer, combien de changements restent. */
export function pageTargetChangesLeft(changes: number): number {
  return Math.max(0, PAGE_TARGET_CHANGE_LIMIT - changes);
}
