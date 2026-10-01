/**
 * Le rythme du voyageur : **combien** on peut lui écrire.
 *
 * La feuille « Notifications » (§ 3) le fonde sur deux choses :
 *
 * 1. **Ce qu'il a déclaré** en début de voyage — « À quelle fréquence
 *    souhaites-tu être relancé ? ». Cette question existe déjà : c'est l'étape
 *    « Notifications » de la création d'un voyage, qui écrit le **rythme du
 *    récit** (`memos.narrationPace`) — « Tous les jours », « Tous les 2 jours »,
 *    « Une fois par semaine ». On le relit ici plutôt que de poser une seconde
 *    question qui dirait la même chose. La feuille propose aussi « rarement » :
 *    la clé `rarely` est comprise, mais l'écran ne la propose pas tant que la
 *    maquette ne l'a pas dessinée.
 * 2. **Ce qu'il fait vraiment** — ouvre-t-il ce qu'on lui envoie, se sert-il
 *    de l'app ? La feuille laisse la pondération à définir ; elle vit dans
 *    `DECLARED_WEIGHT`, une ligne à changer.
 *
 * Le résultat est un **palier**, qui dit quelles notifications le voyageur
 * peut recevoir (`TIER_ALLOWS` dans `notificationPlanner.ts`) :
 *
 * - `sustained` — rythme soutenu : tout, vacances comprises ;
 * - `moderate` — rythme modéré : l'essentiel, plus les relances d'écriture
 *   qu'il a lui-même demandées en choisissant un rythme ;
 * - `light` — rythme léger : l'essentiel seulement, fin d'essai et fin de
 *   voyage.
 */

export type RhythmTier = "sustained" | "moderate" | "light";

/**
 * Ce que chaque réponse déclarée vaut, de 0 (« laisse-moi tranquille ») à 1
 * (« tous les jours »). Les clés sont celles de `narrationPace.ts`.
 */
const DECLARED_SCORE: Record<string, number> = {
  daily: 1,
  every_two_days: 0.8,
  every_three_days: 0.65,
  by_place: 0.65,
  custom: 0.5,
  weekly: 0.4,
  rarely: 0.1,
};

/**
 * Quelqu'un qui a passé la question n'a rien dit : on le range dans le
 * rythme léger, qui ne lui enverra que l'essentiel tant que son usage ne dit
 * pas le contraire.
 */
const UNANSWERED_SCORE = 0.25;

/**
 * **La pondération à trancher** (feuille, § 5) : la part de la réponse
 * déclarée face au comportement observé. 0,7 : on croit d'abord ce que le
 * voyageur a dit, et ses gestes le corrigent sans le contredire d'un coup.
 */
const DECLARED_WEIGHT = 0.7;

/**
 * En dessous de trois notifications reçues, un taux d'ouverture ne veut rien
 * dire — une sur une, c'est 100 %. On ne le lit qu'au-delà.
 */
const MIN_DELIVERIES_FOR_OPEN_RATE = 3;

/**
 * Le coup de pouce de l'usage : quelqu'un qui a raconté dans les quatorze
 * derniers jours aime l'app, on peut lui en dire un peu plus. Un bonus et
 * jamais une pénalité : celui qui se tait est précisément celui que la
 * relance doit aller chercher — le punir de son silence serait se priver de
 * la seule notification qui sert.
 */
const RECENT_USE_BONUS = 0.1;

const SUSTAINED_FROM = 0.6;
const MODERATE_FROM = 0.3;

export interface RhythmSignals {
  /** Le rythme déclaré — une clé de `narrationPace`, ou `null` si passé. */
  declaredPace: string | null;
  /** Combien de notifications envoyées ces 60 derniers jours. */
  deliveredCount: number;
  /** Combien d'entre elles ont été ouvertes. */
  openedCount: number;
  /** A-t-il raconté quelque chose ces 14 derniers jours ? */
  usedRecently: boolean;
}

export interface Rhythm {
  tier: RhythmTier;
  /** Le score, de 0 à 1 — pour les logs et les tests. */
  score: number;
  /** Le taux d'ouverture, quand il veut dire quelque chose. */
  openRate: number | null;
}

export function declaredScore(pace: string | null): number {
  if (pace === null) return UNANSWERED_SCORE;
  return DECLARED_SCORE[pace] ?? UNANSWERED_SCORE;
}

export function rhythmOf(signals: RhythmSignals): Rhythm {
  const declared = declaredScore(signals.declaredPace);
  const openRate =
    signals.deliveredCount >= MIN_DELIVERIES_FOR_OPEN_RATE
      ? signals.openedCount / signals.deliveredCount
      : null;

  const blended =
    openRate === null ? declared : DECLARED_WEIGHT * declared + (1 - DECLARED_WEIGHT) * openRate;
  const score = Math.min(1, blended + (signals.usedRecently ? RECENT_USE_BONUS : 0));

  const tier: RhythmTier =
    score >= SUSTAINED_FROM ? "sustained" : score >= MODERATE_FROM ? "moderate" : "light";

  return { tier, score: Math.round(score * 100) / 100, openRate };
}

/**
 * Tous les combien de jours de silence la relance d'écriture repart — **le
 * rythme du récit que le voyageur a choisi** (T184). « Tous les 2 jours » :
 * après deux jours sans rien raconter.
 */
const REMINDER_INTERVAL_DAYS: Record<string, number> = {
  daily: 1,
  every_two_days: 2,
  every_three_days: 3,
  by_place: 2,
  custom: 3,
  weekly: 7,
  rarely: 14,
};

const DEFAULT_REMINDER_INTERVAL_DAYS = 3;

/**
 * Le comportement réel étire le rythme : quelqu'un qui n'ouvre presque
 * jamais ses relances en reçoit deux fois moins, plutôt que d'apprendre à
 * les ignorer — ou à couper toutes les notifications de l'app.
 */
const IGNORED_BELOW_OPEN_RATE = 0.25;

export function reminderIntervalDays(pace: string | null, openRate: number | null): number {
  const base = (pace && REMINDER_INTERVAL_DAYS[pace]) || DEFAULT_REMINDER_INTERVAL_DAYS;
  return openRate !== null && openRate < IGNORED_BELOW_OPEN_RATE ? base * 2 : base;
}
