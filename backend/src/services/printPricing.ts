/**
 * Le tarif d'un carnet imprimé, et le récapitulatif que l'étape 5 affiche.
 *
 * **C'est le seul endroit où se calcule de l'argent.** L'app n'additionne
 * rien : elle demande un devis et dessine ce qu'on lui rend. Un prix calculé
 * des deux côtés est un prix qui finit par diverger, et c'est le client qui a
 * tort au mauvais moment — devant la personne qui paie.
 *
 * Tout est en **centimes entiers**. Aucun flottant ne traverse ce fichier :
 * `euros()` n'intervient qu'à la sérialisation.
 */

import type { ShippingSpeed } from "@prisma/client";

/**
 * **Le prix du carnet, par palier de pages** (Hugo, 21/10/2026), livraison
 * standard comprise. Il remplace le prix à la page (1,32 € la page + 23,90 €),
 * qui faisait payer 110 € un carnet de 65 pages et 288 € un de 200.
 *
 * La grille vise **10 à 20 € sous Polarsteps Premium** à chaque tranche, et en
 * suit les seuils — dont le saut de 95 à 120 € à 101 pages. Les trois premiers
 * paliers sont les cibles Compact / Par défaut / Détaillé d'un voyage sans date
 * de fin, 40 / 60 / 80 pages à ± 5 (`pageTarget.ts`). Les paliers sont **fixes
 * en pages** : un Compact de six mois en fait 120, et se paie 110 €, pas 55.
 *
 * Plus cher que Polarsteps de 16 à 24 pages (45 € chez eux) et de 46 à 50
 * (70 €) : accepté par Hugo, la marge n'y descendrait pas plus bas.
 *
 * Le calcul (coûts Pumbo estimés, marges, écarts) est dans
 * `livrables/MemoBook Prix du carnet par palier.xlsx`, hors dépôt. Chaque
 * palier vaut jusqu'à `upTo` pages comprises ; au-delà du dernier, son prix.
 */
const LAST_TIER = { upTo: 400, cents: 14_500 };
const PRICE_TIERS: readonly { upTo: number; cents: number }[] = [
  { upTo: 45, cents: 5_500 },
  { upTo: 65, cents: 7_500 },
  { upTo: 85, cents: 8_000 },
  { upTo: 100, cents: 8_500 },
  { upTo: 120, cents: 10_500 },
  { upTo: 200, cents: 11_000 },
  { upTo: 300, cents: 12_900 },
  LAST_TIER,
];

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
 * unitaire », et ce que la notification de fin de voyage annonce.
 *
 * Le palier de `PRICE_TIERS` où tombe le nombre de pages.
 */
export function unitPriceCents(pageCount: number): number {
  const pages = Math.max(pageCount, 1);
  return (PRICE_TIERS.find((t) => pages <= t.upTo) ?? LAST_TIER).cents;
}

export function shippingCents(speed: ShippingSpeed): number {
  return speed === "express" ? EXPRESS_CENTS : 0;
}

export type QuoteInput = {
  bookTitle: string;
  pageCount: number;
  copies: number;
  speed: ShippingSpeed;
};

/**
 * Le récapitulatif complet, tel que l'étape 5 le dessine : deux groupes qui
 * portent chacun leur sous-total, les déductions, puis le net à payer.
 *
 * **Plus aucune déduction** (Hugo, 06/10/2026 — « on supprime la cagnotte »).
 * La cagnotte était la dernière ; la « Déduction abonnements hebdomadaires
 * versés » était partie le 03/10 avec l'abonnement hebdomadaire. Une commande
 * se paie désormais **entièrement par Stripe** : le net à payer est le dû.
 *
 * `deductions` reste dans la réponse, vide : l'app le décode comme un tableau
 * obligatoire, et c'est elle qui dessine les lignes qu'on lui donne.
 * `walletAppliedCents` aussi, à zéro : la colonne de la commande existe
 * toujours (`print_orders.walletAppliedCents`), et les commandes d'avant le
 * 06/10 y gardent ce que la cagnotte avait payé.
 */
export function quote(input: QuoteInput) {
  const pages = Math.max(input.pageCount, 1);
  const copies = Math.max(input.copies, 1);

  const unitCents = unitPriceCents(pages);
  const itemsCents = unitCents * copies;
  const shipCents = shippingCents(input.speed);
  const dueCents = itemsCents + shipCents;

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
    deductions: [] as { id: string; label: string; amountCents: number }[],
    walletAppliedCents: 0,
    totalCents: dueCents,
    estimatedDays: SHIPPING_DAYS[input.speed],
  };
}

export type PrintQuote = ReturnType<typeof quote>;

/**
 * **Le nombre de pages qui fait le prix : celui du carnet composé** (Hugo,
 * 18/10/2026 — « c'est le nombre final de pages du carnet qui doit être
 * utilisé pour calculer son prix »). Couvertures exclues, comme la cible
 * (`composedPageCount`, `jobs/render.ts`). Avant tout carnet composé, la cible
 * en tient lieu d'estimation : le carnet final y tient à ± 5 pages.
 *
 * L'ancienne règle prenait le plus grand des deux : un carnet de 24 pages
 * visé à 40 se payait 40.
 */
export function billablePages(memo: { targetPageCount: number; pageCount: number }): number {
  return Math.max(memo.pageCount > 0 ? memo.pageCount : memo.targetPageCount, 1);
}
