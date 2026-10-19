/**
 * **Les journées qui manquent au récit** — le trou qu'on raconte le 25 puis le
 * 27, et qui n'existera jamais dans le carnet imprimé.
 *
 * Tout est **pur et déterministe** ici : rien ne touche la base, aucun modèle
 * n'est appelé. Le modèle de conversation ne détecte pas les trous, ne les
 * nomme pas et ne peut pas choisir le bouton qui les comble
 * (`allowedForModel: false` dans `callsToAction.ts`) — un trou inventé serait
 * pire que pas de trou du tout.
 *
 * **Un trou est une suite de journées sans récit, encadrée des deux côtés par
 * une journée racontée.** L'encadrement est tout l'intérêt : il distingue un
 * oubli — on est passé à la suite — de la journée d'aujourd'hui qu'on n'a pas
 * encore eu le temps de raconter. Celle-là appartient à la notification de
 * relance (`docs/notifications.md`), pas au fil.
 *
 * Le reste de ce fichier n'est que de la retenue : cinq conditions avant de
 * déranger quelqu'un, et un registre qui s'arrête de lui-même.
 */

import {
  type LocalDate,
  addDays,
  daysBetween,
  localDate,
  tripDate,
  DEFAULT_TIME_ZONE,
} from "./localCalendar.js";
import { localNoonOn } from "./dailyCredit.js";
import { normalizeNarrationPace } from "./narrationPace.js";
import { effectiveStage } from "./tripStage.js";
import type { ConversationState } from "./conversation.js";

/** Une suite de journées sans récit, encadrée par deux journées racontées. */
export interface Gap {
  days: LocalDate[];
}

/** Ce qu'il faut d'un carnet pour chercher ses trous. */
export type MemoForGaps = {
  startDate: Date | null;
  endDate: Date | null;
  stage: string;
  narrationPace: string | null;
};

/**
 * Au-delà de deux jours, ce n'est plus un oubli : c'est une façon de raconter.
 * Relever une semaine blanche serait reprocher au voyageur de ne pas avoir
 * assez parlé — exactement ce que l'app ne fait jamais.
 */
export const MAX_GAP_DAYS = 2;

/** On ne relève pas un trou au deuxième jour du voyage. */
export const MIN_TOLD_DAYS = 3;

/** Deux propositions restées sans suite, et on n'en parle plus pour ce voyage. */
export const GAP_DECLINE_CAP = 2;

/** Au plus une proposition toutes les 48 heures, même sur un voyage très troué. */
export const GAP_COOLDOWN_MS = 48 * 60 * 60 * 1000;

/**
 * Le mode « je te raconte cette journée-là » ne survit pas à une demi-heure.
 * Un état caché qui daterait un souvenir d'il y a une semaine serait pire que
 * pas de fonctionnalité du tout.
 */
export const TELLING_DAY_TTL_MS = 30 * 60 * 1000;

/** On accepte encore de combler un trou une semaine après la fin du voyage. */
const GRACE_DAYS_AFTER_TRIP = 7;

// ---------------------------------------------------------------------------
// La détection
// ---------------------------------------------------------------------------

/**
 * Les trous d'un voyage, du plus ancien au plus récent.
 *
 * `told` porte les `capturedAt` des souvenirs **racontés** — ni les photos, ni
 * rien d'autre : une photo du 26 illustre le plus souvent l'étape du 25, elle
 * ne dit pas que le 26 a été raconté.
 *
 * Sans `startDate`, on rend `[]` : il n'y a pas de trou sans fenêtre, seulement
 * des jours sans récit. Même dégradé que `dayCountOf`.
 */
export function missingDays(
  memo: Pick<MemoForGaps, "startDate" | "endDate">,
  told: Date[],
  now: Date,
  timeZone: string = DEFAULT_TIME_ZONE,
): Gap[] {
  if (!memo.startDate) return [];

  const today = localDate(now, timeZone);
  const first = tripDate(memo.startDate);
  const last = memo.endDate && tripDate(memo.endDate) < today ? tripDate(memo.endDate) : today;
  if (daysBetween(first, last) < 2) return [];

  const toldDays = new Set(
    told.map((instant) => localDate(instant, timeZone)).filter((day) => day >= first && day <= last),
  );
  if (toldDays.size < 2) return [];

  // Les bornes du récit, et non celles du voyage : c'est entre elles qu'un
  // trou est refermé.
  const sorted = [...toldDays].sort();
  const opening = sorted[0]!;
  const closing = sorted[sorted.length - 1]!;

  const gaps: Gap[] = [];
  let run: LocalDate[] = [];

  for (let day = addDays(opening, 1); day < closing; day = addDays(day, 1)) {
    if (toldDays.has(day)) {
      if (run.length > 0) {
        gaps.push({ days: run });
        run = [];
      }
      continue;
    }
    run.push(day);
  }
  // La dernière suite se ferme sur `closing`, qui est raconté par
  // construction : la boucle s'arrête avant lui, c'est donc ici qu'elle entre.
  if (run.length > 0) gaps.push({ days: run });

  return gaps.filter((gap) => gap.days.length <= MAX_GAP_DAYS);
}

/**
 * Le trou qu'on propose de combler maintenant — `null` neuf fois sur dix, et
 * c'est le but.
 *
 * Cinq conditions, dans l'ordre du moins cher au plus cher :
 *
 * 1. le registre : jamais deux propositions en vol, jamais plus de deux refus,
 *    jamais deux fois en moins de 48 heures ;
 * 2. **le rythme du récit** — le garde-fou le plus efficace du lot. Quelqu'un
 *    qui a réglé « toutes les semaines » a dit qu'il racontait quand il peut :
 *    lui signaler un trou, c'est lui reprocher son propre réglage ;
 * 3. un voyage en cours, ou terminé depuis moins d'une semaine — un voyage
 *    passé importé est troué par construction ;
 * 4. au moins trois journées racontées ;
 * 5. un trou encadré, jamais encore proposé, le plus ancien d'abord : c'est
 *    celui qui risque de se perdre.
 */
export function shouldOfferGap(
  memo: MemoForGaps,
  state: ConversationState,
  told: Date[],
  now: Date,
  timeZone: string = DEFAULT_TIME_ZONE,
): Gap | null {
  if (state.gapOffered) return null;
  if (state.gapDeclines >= GAP_DECLINE_CAP) return null;

  if (state.gapLastAskedAt) {
    const asked = Date.parse(state.gapLastAskedAt);
    if (Number.isFinite(asked) && now.getTime() - asked < GAP_COOLDOWN_MS) return null;
  }

  if (!acceptsGapsAtPace(memo.narrationPace)) return null;
  if (!isWithinReach(memo, now, timeZone)) return null;

  const toldDays = new Set(told.map((instant) => localDate(instant, timeZone)));
  if (toldDays.size < MIN_TOLD_DAYS) return null;

  const asked = new Set(state.gapAskedFor);
  const pace = normalizeNarrationPace(memo.narrationPace);

  for (const gap of missingDays(memo, told, now, timeZone)) {
    if (gap.days.some((day) => asked.has(day))) continue;
    // « Tous les 2 jours » : une journée sautée est le rythme annoncé, deux
    // sont un oubli. « Tous les jours » : les deux cas sont des oublis.
    if (pace === "every_two_days" && gap.days.length > 1) continue;
    return gap;
  }

  return null;
}

/**
 * Les deux journées racontées qui encadrent un trou — ce que la phrase de
 * MEMO cite pour situer le manque (« entre ton récit du mardi 25 et celui du
 * jeudi 27 »). Toujours trouvées : un trou n'existe que s'il est encadré.
 */
export function gapBorders(
  gap: Gap,
  told: Date[],
  timeZone: string = DEFAULT_TIME_ZONE,
): { before: LocalDate; after: LocalDate } | null {
  const days = new Set(told.map((instant) => localDate(instant, timeZone)));
  let before = addDays(gap.days[0]!, -1);
  while (!days.has(before)) {
    if (daysBetween(before, gap.days[0]!) > 400) return null;
    before = addDays(before, -1);
  }
  let after = addDays(gap.days[gap.days.length - 1]!, 1);
  while (!days.has(after)) {
    if (daysBetween(gap.days[0]!, after) > 400) return null;
    after = addDays(after, 1);
  }
  return { before, after };
}

/** Les rythmes où un trou d'un jour veut dire quelque chose. */
function acceptsGapsAtPace(narrationPace: string | null): boolean {
  const pace = normalizeNarrationPace(narrationPace);
  return pace === "daily" || pace === "every_two_days";
}

/** Un voyage en cours, ou fini depuis moins d'une semaine. */
function isWithinReach(memo: MemoForGaps, now: Date, timeZone: string): boolean {
  const stage = effectiveStage(memo, now);
  if (stage === "ongoing") return true;
  if (stage !== "past" || !memo.endDate) return false;
  return daysBetween(tripDate(memo.endDate), localDate(now, timeZone)) <= GRACE_DAYS_AFTER_TRIP;
}

// ---------------------------------------------------------------------------
// Le registre — ce qui empêche la carte de revenir
// ---------------------------------------------------------------------------

/**
 * Le refus se lit dans le **silence**.
 *
 * Une proposition en vol que ce tour-ci n'accepte pas est une proposition
 * refusée : qu'on ait touché « Ignorer » ou simplement continué à raconter,
 * c'est le même non. L'app n'a donc rien à remonter — pas de route, pas de cas
 * hors ligne, pas de divergence entre co-voyageurs — et la journée n'est
 * jamais reproposée.
 */
export function withGapDeclined(state: ConversationState): ConversationState {
  if (!state.gapOffered) return state;
  return {
    ...state,
    gapAskedFor: mergeDays(state.gapAskedFor, state.gapOffered.days),
    gapOffered: null,
    gapDeclines: state.gapDeclines + 1,
  };
}

/** La proposition part : on la retient, et l'horloge des 48 heures démarre. */
export function withGapOffered(state: ConversationState, gap: Gap, now: Date): ConversationState {
  return {
    ...state,
    gapOffered: { days: gap.days, askedAt: now.toISOString() },
    gapLastAskedAt: now.toISOString(),
  };
}

/**
 * La proposition est acceptée : la journée entre dans le registre — une fois
 * proposée, jamais reproposée, même comblée — et le mode s'ouvre.
 */
export function withGapAccepted(
  state: ConversationState,
  days: LocalDate[],
  day: LocalDate,
  now: Date,
): ConversationState {
  return {
    ...state,
    gapAskedFor: mergeDays(state.gapAskedFor, days),
    gapOffered: null,
    tellingDay: { day, askedAt: now.toISOString() },
  };
}

function mergeDays(known: LocalDate[], added: LocalDate[]): LocalDate[] {
  return [...new Set([...known, ...added])].sort();
}

// ---------------------------------------------------------------------------
// La journée que le prochain récit datera
// ---------------------------------------------------------------------------

/**
 * La journée du mode, si elle tient encore debout : pas périmée, dans la
 * fenêtre du voyage, et pas dans le futur. `null` partout ailleurs — un doute
 * sur la date, et le souvenir reprend celle de son envoi.
 */
export function tellingDayOf(
  memo: Pick<MemoForGaps, "startDate" | "endDate">,
  state: ConversationState,
  now: Date,
  timeZone: string = DEFAULT_TIME_ZONE,
): LocalDate | null {
  const telling = state.tellingDay;
  if (!telling) return null;

  const askedAt = Date.parse(telling.askedAt);
  if (!Number.isFinite(askedAt) || now.getTime() - askedAt > TELLING_DAY_TTL_MS) return null;

  const today = localDate(now, timeZone);
  if (telling.day > today) return null;
  if (memo.startDate && telling.day < tripDate(memo.startDate)) return null;
  if (memo.endDate && telling.day > tripDate(memo.endDate)) return null;

  return telling.day;
}

/**
 * L'horodatage d'un souvenir raconté après coup : **midi** de la journée dans
 * le fuseau du voyage — voir `localNoonOn`, qui porte le seul calcul de
 * décalage du dépôt.
 */
export function capturedAtFor(day: LocalDate, timeZone: string = DEFAULT_TIME_ZONE): Date {
  return localNoonOn(day, timeZone);
}
