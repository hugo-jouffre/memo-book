/**
 * Le rythme du récit — « tous les 2 jours » —, sous la clé que l'app lit.
 *
 * **Une clé, jamais un libellé.** L'app décode `narrationPace` en énumération
 * (`NarrationPace`, côté iOS) : `daily`, `every_two_days`, `every_three_days`,
 * `weekly`, `custom`, `by_place`. Jusqu'au 17/09/2026 l'écran de création
 * écrivait pourtant le rythme dans ses propres mots — « Tous les jours »,
 * « Toutes les semaines » — quand la feuille des réglages écrivait déjà la
 * clé ; la feuille « Rythme du récit » relisait alors un rythme inconnu et ne
 * cochait rien (Hugo, 18/09/2026). Tout ce qui entre passe donc par ici, et
 * la migration `20260918150000_rythme_du_recit_en_cles` a réécrit les
 * rangées existantes.
 *
 * Un libellé qu'on ne reconnaît pas est gardé tel quel : la colonne est libre
 * et l'app sait afficher un rythme inconnu sous son nom brut. Le refuser
 * casserait une création pour une valeur que personne n'a à taper.
 */

/** Les clés que l'app connaît, dans l'ordre de sa feuille. */
export const NARRATION_PACES = [
  "daily",
  "every_two_days",
  "every_three_days",
  "weekly",
  "custom",
  "by_place",
] as const;

export type NarrationPaceKey = (typeof NARRATION_PACES)[number];

/**
 * Les anciens libellés, et ceux que l'app affiche — au cas où l'un d'eux
 * reviendrait par un client qui les renvoie tels qu'il les a lus. En
 * minuscules, sans espaces autour : c'est ainsi qu'on compare.
 */
const LEGACY_LABELS: Record<string, NarrationPaceKey> = {
  "tous les jours": "daily",
  "tous les 2 jours": "every_two_days",
  "tous les deux jours": "every_two_days",
  "tous les 3 jours": "every_three_days",
  "tous les trois jours": "every_three_days",
  "toutes les semaines": "weekly",
  "une fois par semaine": "weekly",
  personnalisé: "custom",
  "à chaque lieu": "by_place",
};

/** La clé d'un rythme, quel que soit le mot par lequel il est arrivé. */
export function normalizeNarrationPace(raw: string | null | undefined): string | null {
  if (raw === null || raw === undefined) return null;
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const folded = trimmed.toLowerCase();
  if ((NARRATION_PACES as readonly string[]).includes(folded)) return folded;
  return LEGACY_LABELS[folded] ?? trimmed;
}
