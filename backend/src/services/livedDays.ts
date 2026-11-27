/**
 * **Les jours qu'un souvenir raconte** — ceux que la rédaction a compris, ou
 * ceux que le voyageur a fixés lui-même (T288).
 *
 * Deux paires de colonnes vivent côte à côte sur `entries` : `livedFromDay` et
 * `livedToDay`, remplis par la rédaction quand le récit dit un jour (T308), et
 * `pinnedLivedFromDay` / `pinnedLivedToDay`, écrits à la main depuis la fiche.
 * La main gagne, et `null` rend la parole au modèle — c'est tout ce que fait
 * cette fonction, et c'est pour qu'elle soit **le seul** endroit où la règle
 * s'écrit.
 *
 * ⚠️ La paire est indivisible : une main qui dit « le 12 seulement » doit
 * effacer la fin que le modèle avait mise, sans quoi on lirait « du 12 au 15 »
 * en ayant corrigé le départ. C'est donc `pinnedLivedFromDay` seul qui décide
 * de laquelle des deux paires on lit.
 */
export interface LivedDaysSource {
  livedFromDay: Date | null;
  livedToDay: Date | null;
  pinnedLivedFromDay?: Date | null;
  pinnedLivedToDay?: Date | null;
}

export function livedDaysOf(entry: LivedDaysSource): { from: Date | null; to: Date | null } {
  if (entry.pinnedLivedFromDay) {
    return { from: entry.pinnedLivedFromDay, to: entry.pinnedLivedToDay ?? null };
  }
  return { from: entry.livedFromDay, to: entry.livedToDay };
}
