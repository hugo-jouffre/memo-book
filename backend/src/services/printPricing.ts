/**
 * Le tarif d'un carnet imprimé, et le récapitulatif que l'étape 5 affiche.
 *
 * **C'est le seul endroit où se calcule de l'argent.** L'app n'additionne
 * rien : elle demande un devis et dessine ce qu'on lui rend. Un prix calculé
 * des deux côtés est un prix qui finit par diverger, et c'est le client qui a
 * tort au mauvais moment — devant la personne qui paie.
 *
 * Tout est en **centimes entiers**, comme `wallet_entries`. Aucun flottant ne
 * traverse ce fichier : `euros()` n'intervient qu'à la sérialisation.
 */

import type { ShippingSpeed } from "@prisma/client";

/**
 * Le prix de fabrication, décomposé comme l'imprimeur le facture : une part
 * qui suit le nombre de pages, deux qui n'en dépendent pas.
 *
 * C'était jusqu'ici un taux unique de 1,798 € la page, avec le défaut que son
 * propre commentaire signalait — « un carnet de dix pages ne coûte pas un
 * cinquième d'un carnet de cinquante ». Les frais fixes en sortent, ce qui
 * rend la courbe juste aux petits carnets sans bouger l'ancre commerciale :
 * **50 pages font toujours 89,90 €**, valeur de la maquette.
 *
 * ⚠️ À retarifer avec l'imprimeur avant d'encaisser quoi que ce soit. Les
 * trois lignes sont celles que le récapitulatif nomme, pas une invention
 * d'affichage.
 */
const PAPER_CENTS_PER_PAGE = 132;
const COVER_CENTS = 1_490;
const BINDING_CENTS = 900;

/** Le supplément de l'acheminement rapide. `standard` est inclus. */
const EXPRESS_CENTS = 990;

/** Les bornes annoncées par palier, en jours ouvrés. */
export const SHIPPING_DAYS: Record<ShippingSpeed, { min: number; max: number }> = {
  standard: { min: 5, max: 7 },
  express: { min: 2, max: 3 },
};

/**
 * Ce que le carnet est, et qui ne se choisit pas.
 *
 * **Une fabrication et une seule** : un papier, une couverture, une reliure.
 * Ces trois lignes ont d'abord été facturées séparément dans le récapitulatif,
 * ce qui laissait croire à trois options — alors qu'on ne peut en changer
 * aucune. Elles sont devenues ce qu'elles sont vraiment : la description du
 * produit, posée sous son prix. **Le prix, lui, ne dépend que du nombre de
 * pages.**
 */
export const BOOK_SPECIFICATIONS = [
  "80g. non couché ivoire",
  "Couverture rigide & matte",
  "Livre relié",
] as const;

/**
 * Le prix d'**un** carnet. C'est aussi ce que l'étape 3 affiche en « prix
 * unitaire », et ce que la cagnotte estime.
 *
 * La décomposition reste interne : une part qui suit les pages, deux frais
 * fixes. Elle ne sort plus vers l'app — voir ``BOOK_SPECIFICATIONS``.
 */
export function unitPriceCents(pageCount: number): number {
  const pages = Math.max(pageCount, 1);
  return pages * PAPER_CENTS_PER_PAGE + COVER_CENTS + BINDING_CENTS;
}

export function shippingCents(speed: ShippingSpeed): number {
  return speed === "express" ? EXPRESS_CENTS : 0;
}

export type QuoteInput = {
  bookTitle: string;
  pageCount: number;
  copies: number;
  speed: ShippingSpeed;
  /** Le solde de la cagnotte de **celui qui commande**. Chacun a la sienne. */
  walletBalanceCents: number;
};

/**
 * Le récapitulatif complet, tel que l'étape 5 le dessine : deux groupes qui
 * portent chacun leur sous-total, les déductions, puis le net à payer.
 *
 * La cagnotte ne peut pas rendre la monnaie : elle est plafonnée au montant dû,
 * et le total ne descend jamais sous zéro.
 *
 * **Une seule déduction : la cagnotte** (Hugo, 03/10/2026). La ligne
 * « Déduction abonnements hebdomadaires versés » est partie avec l'abonnement
 * hebdomadaire : l'abonnement ne se déduit plus du carnet. Elle n'était
 * d'ailleurs qu'une répartition au prorata des recharges de la cagnotte, pas
 * des abonnements réellement payés.
 */
export function quote(input: QuoteInput) {
  const pages = Math.max(input.pageCount, 1);
  const copies = Math.max(input.copies, 1);

  const unitCents = unitPriceCents(pages);
  const itemsCents = unitCents * copies;
  const shipCents = shippingCents(input.speed);
  const dueCents = itemsCents + shipCents;

  const appliedCents = Math.max(0, Math.min(input.walletBalanceCents, dueCents));

  const deductions = [
    {
      id: "wallet",
      // « De ta cagnotte », pas « de tes proches » (03/10/2026) : elle reçoit
      // aussi les recharges que le voyageur paie lui-même
      // (`POST /v1/wallet/topup`), et l'abonnement n'est plus là pour les
      // ranger à part. L'app affiche ce libellé tel quel.
      label: "Déduction de ta cagnotte",
      amountCents: appliedCents,
    },
    // Une déduction nulle ne se montre pas : « - 0,00 € » ferait croire à une
    // réduction qui n'a pas eu lieu.
  ].filter((deduction) => deduction.amountCents > 0);

  return {
    bookTitle: input.bookTitle,
    pageCount: pages,
    copies,
    speed: input.speed,
    unitCents,
    specifications: BOOK_SPECIFICATIONS,
    itemsCents,
    shippingCents: shipCents,
    dueCents,
    deductions,
    walletAppliedCents: appliedCents,
    totalCents: dueCents - appliedCents,
    estimatedDays: SHIPPING_DAYS[input.speed],
  };
}

export type PrintQuote = ReturnType<typeof quote>;
