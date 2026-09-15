/**
 * Le prix du carnet imprimé, au même endroit pour tout le monde.
 *
 * **Une constante, deux lecteurs.** La cagnotte affiche une estimation avant la
 * commande (`serializeWalletEstimate`), et le paiement encaisse un montant au
 * moment de la commande. Chacun de son côté, les deux finiraient par diverger —
 * et l'écart se verrait au pire moment : l'utilisateur a lu « 107,88 € » sur la
 * carte de cagnotte et voit un autre chiffre dans la feuille de paiement.
 */

/**
 * Ce que coûte une page imprimée, en centimes.
 *
 * **Une constante et non une colonne** : c'est un prix catalogue, le même pour
 * tout le monde, et il n'a rien à faire dupliqué sur chaque carnet. Le jour où
 * il varie — par format, par pays — il deviendra une table de tarifs, pas une
 * colonne de `memos`.
 *
 * 89,90 € pour les 50 pages de la maquette, soit 1,798 € la page.
 *
 * ⚠️ **Les frais fixes de fabrication et de port sont dedans**, ce qui est faux
 * dès qu'on s'éloigne de cinquante pages : un carnet de dix pages ne coûte pas
 * un cinquième d'un carnet de cinquante. C'était signalé comme « à trancher
 * avec l'imprimeur avant d'encaisser quoi que ce soit » — et l'encaissement
 * existe maintenant. Tant que ce n'est pas tranché, le montant débité est celui
 * de cette formule, exactement comme l'estimation affichée.
 *
 * Le jour où on la corrige : une part fixe + une part par page, et la livraison
 * sortie du prix du carnet pour devenir une ligne à elle.
 */
export const CENTS_PER_PAGE = 179.8;

/**
 * Le nombre de pages **facturées**.
 *
 * ⚠️ **Ce n'est pas le nombre de pages du PDF, et on ne peut pas le connaître
 * ici.** `LAYOUT_KB.md` est explicite : « une entrée de `days[]` est une étape,
 * pas une page ». Seul le moteur qui compose la mise en page sait combien de
 * feuilles une étape occupe, et APITemplate ne le renvoie pas.
 *
 * On facture donc exactement ce que l'écran a annoncé : la cible du voyageur,
 * ou le nombre composé s'il l'a dépassée. **C'est l'invariant qui compte** —
 * le montant débité est celui qu'il a lu sur la carte de cagnotte, au centime
 * près, parce que les deux passent par cette fonction.
 *
 * ⚠️ `pageCount` est aujourd'hui toujours à 0 : aucun job du back-end ne
 * l'écrit. `Math.max` le neutralise donc, et la facturation tombe sur
 * `targetPageCount`. Signalé — le jour où le compte réel est écrit, cette
 * fonction devient juste sans changer d'appelant.
 */
export function billablePageCount(memo: {
  targetPageCount: number;
  pageCount: number;
}): number {
  return Math.max(memo.targetPageCount, memo.pageCount);
}

/**
 * Ce que coûte une commande, en centimes.
 *
 * L'arrondi tombe sur le prix **d'un** exemplaire, avant la multiplication :
 * deux exemplaires coûtent exactement deux fois un exemplaire, et la ligne de
 * facture se relit.
 */
export function bookPriceCents(pageCount: number, copies: number): number {
  return Math.round(pageCount * CENTS_PER_PAGE) * copies;
}
