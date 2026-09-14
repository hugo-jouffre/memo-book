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

/** Ce qu'un exemplaire coûte, ligne à ligne. */
export function bookLines(pageCount: number) {
  const pages = Math.max(pageCount, 1);
  return [
    { id: "paper", label: "80g. non couché ivoire", amountCents: pages * PAPER_CENTS_PER_PAGE },
    { id: "cover", label: "Couverture rigide & matte", amountCents: COVER_CENTS },
    { id: "binding", label: "Livre broché", amountCents: BINDING_CENTS },
  ];
}

/**
 * Le prix d'**un** carnet. C'est aussi ce que l'étape 3 affiche en « prix
 * unitaire », et ce que la cagnotte estime.
 */
export function unitPriceCents(pageCount: number): number {
  return bookLines(pageCount).reduce((total, line) => total + line.amountCents, 0);
}

export function shippingCents(speed: ShippingSpeed): number {
  return speed === "express" ? EXPRESS_CENTS : 0;
}

/**
 * Comment la cagnotte se répartit entre ses deux provenances, à l'affichage.
 *
 * Le solde est **un seul nombre** : rien, dans le registre, ne dit quel euro
 * vient d'un don et lequel d'un versement d'abonnement. Les deux lignes du
 * récapitulatif sont donc une **répartition au prorata des crédits reçus**, et
 * pas un suivi à la pièce — le dire ici plutôt que de laisser croire à une
 * comptabilité par enveloppe.
 *
 * Le reste (`applied - gift`) va à l'abonnement, ce qui garantit que les deux
 * lignes retombent exactement sur le montant déduit, sans dérive d'arrondi.
 */
export function splitWalletCredit(
  appliedCents: number,
  giftCreditCents: number,
  topupCreditCents: number
): { giftCents: number; subscriptionCents: number } {
  const credits = giftCreditCents + topupCreditCents;
  if (appliedCents <= 0 || credits <= 0) return { giftCents: 0, subscriptionCents: 0 };

  const giftCents = Math.round((appliedCents * giftCreditCents) / credits);
  return { giftCents, subscriptionCents: appliedCents - giftCents };
}

export type QuoteInput = {
  bookTitle: string;
  pageCount: number;
  copies: number;
  speed: ShippingSpeed;
  /** Le solde de la cagnotte de **celui qui commande**. Chacun a la sienne. */
  walletBalanceCents: number;
  /** Les crédits reçus, par provenance, pour la répartition d'affichage. */
  giftCreditCents: number;
  topupCreditCents: number;
};

/**
 * Le récapitulatif complet, tel que l'étape 5 le dessine : deux groupes qui
 * portent chacun leur sous-total, les déductions, puis le net à payer.
 *
 * La cagnotte ne peut pas rendre la monnaie : elle est plafonnée au montant dû,
 * et le total ne descend jamais sous zéro.
 */
export function quote(input: QuoteInput) {
  const pages = Math.max(input.pageCount, 1);
  const copies = Math.max(input.copies, 1);

  const lines = bookLines(pages);
  const unitCents = lines.reduce((total, line) => total + line.amountCents, 0);

  const itemsCents = unitCents * copies;
  const shipCents = shippingCents(input.speed);
  const dueCents = itemsCents + shipCents;

  const appliedCents = Math.max(0, Math.min(input.walletBalanceCents, dueCents));
  const split = splitWalletCredit(appliedCents, input.giftCreditCents, input.topupCreditCents);

  const deductions = [
    {
      id: "subscription",
      label: "Déduction abonnements hebdomadaires versés",
      amountCents: split.subscriptionCents,
    },
    {
      id: "wallet",
      label: "Déduction de la cagnotte de tes proches",
      amountCents: split.giftCents,
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
    lines,
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
