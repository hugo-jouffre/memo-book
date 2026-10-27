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
import { HttpError } from "../lib/httpError.js";

/**
 * Un palier de la grille : le nom interne qui le désigne dans les logs et
 * dans ce que l'app reçoit, les bornes en pages (comprises), et le prix.
 */
export type PrintPriceTier = {
  /** Le nom interne du palier. **Jamais affiché** : voir `PRINT_PRICE_TIERS`. */
  readonly id: string;
  /** La première page du palier, comprise. */
  readonly from: number;
  /** La dernière page du palier, comprise. */
  readonly to: number;
  /** Le prix du carnet à ce palier, TTC, livraison standard comprise. */
  readonly cents: number;
};

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
 * ⚠️ **Les noms de paliers sont internes.** « Compact », « Détaillé » sont
 * aussi les noms des trois options de l'écran « Nombre de pages », et ce ne
 * sont pas les mêmes choses : l'option dit une densité de récit, le palier dit
 * une tranche de pages. Un « Compact » de six mois tombe dans « Grand carnet
 * + ». Rien de tout ceci ne s'affiche : l'app ne montre que le prix.
 *
 * Le calcul (coûts Pumbo estimés, marges, écarts) est dans le Google Sheet
 * « MemoBook, Prix du carnet par palier », onglet « Prix par palier » — hors
 * dépôt. **Cette constante en est la copie, et la seule source de vérité du
 * code** : le backend facture avec, et l'app reçoit les prix calculés ici
 * (`serializeTripSettings`), elle n'en garde aucune copie.
 */
export const PRINT_PRICE_TIERS: readonly PrintPriceTier[] = [
  { id: "compact", from: 16, to: 45, cents: 5_500 },
  { id: "standard", from: 46, to: 65, cents: 7_500 },
  { id: "detailed", from: 66, to: 85, cents: 8_000 },
  { id: "detailed-plus", from: 86, to: 100, cents: 8_500 },
  { id: "large", from: 101, to: 120, cents: 10_500 },
  { id: "large-plus", from: 121, to: 200, cents: 11_000 },
  { id: "very-large", from: 201, to: 300, cents: 12_900 },
  { id: "beyond", from: 301, to: 400, cents: 14_500 },
] as const;

/**
 * **Le minimum de l'imprimeur** : Pumbo ne relie pas moins de 16 pages, et un
 * carnet plus court se facture comme un carnet de 16. Ce n'est pas une remise
 * à zéro : les pages manquantes sont imprimées blanches.
 */
export const MINIMUM_BILLABLE_PAGES = 16;

/**
 * **Le dernier palier est fermé par défaut** (`ALLOW_OVER_300_PAGES`, faux
 * sauf mention contraire) : au-delà de 300 pages, la reliure de Pumbo n'est
 * pas tenue et on préfère refuser un prix à en inventer un. Le palier 301-400
 * existe, prêt, et s'ouvre en posant la variable à `true`.
 *
 * Lu à **chaque appel**, et non une fois au chargement du module : `loadEnv`
 * remplit `process.env` depuis le `.env` après les premiers imports, et une
 * constante figée à l'import aurait lu l'environnement d'avant.
 */
const allowsOver300 = (): boolean => process.env.ALLOW_OVER_300_PAGES === "true";

/** Les journaux du prix, en développement ou derrière `DEBUG_PRICING`. */
const debugsPricing = (): boolean =>
  process.env.DEBUG_PRICING === "true" || process.env.NODE_ENV === "development";

/** Le nombre de pages maximum qu'on accepte de facturer, flag compris. */
export function maxBillablePages(): number {
  const tiers = allowsOver300() ? PRINT_PRICE_TIERS : PRINT_PRICE_TIERS.filter((tier) => tier.to <= 300);
  // La grille n'est jamais vide, mais le type ne le sait pas : 300 pages est
  // le maximum de la grille fermée, et c'est le repli le plus prudent.
  return tiers[tiers.length - 1]?.to ?? 300;
}

/**
 * **Le prix d'un carnet de `pages` pages** — la seule porte d'entrée du tarif.
 *
 * Fonction pure (au flag de configuration près) : mêmes pages, même palier,
 * même prix. Moins de 16 pages se facturent comme 16 (voir
 * `MINIMUM_BILLABLE_PAGES`) ; au-delà du maximum autorisé, **elle refuse** —
 * il n'y a pas de prix à annoncer pour un carnet qu'on ne sait pas relier.
 *
 * Rend le palier **et** son prix : les journaux et les tests disent lequel a
 * servi, sans avoir à le redéduire du montant.
 */
export function getPrintPrice(pages: number): { tierId: string; priceCents: number } {
  const billed = Math.max(Math.ceil(pages), MINIMUM_BILLABLE_PAGES);
  const max = maxBillablePages();

  if (billed > max) {
    throw HttpError.badRequest(
      `Un carnet de ${billed} pages dépasse le maximum de ${max} pages.`,
      "page_count_too_high",
    );
  }

  const tier = PRINT_PRICE_TIERS.find((candidate) => billed <= candidate.to);
  // Inatteignable : `billed` est borné par `max`, qui est le `to` du dernier
  // palier retenu. Le repli existe pour que le type n'ait pas à mentir.
  if (!tier) {
    throw HttpError.badRequest(`Aucun palier de prix pour ${billed} pages.`, "page_count_too_high");
  }

  if (debugsPricing()) {
    console.debug(
      `[pricing] pages=${pages} facturées=${billed} palier=${tier.id} prix=${tier.cents}c`,
    );
  }

  return { tierId: tier.id, priceCents: tier.cents };
}

/** Le supplément de l'acheminement rapide. `standard` est inclus. */
const EXPRESS_CENTS = 990;

/**
 * **Le supplément des « Zones libres »** (maquette `3909:27845`) : une zone
 * blanche à la fin de chaque étape et trois pages blanches à la fin du carnet.
 * Facturé par exemplaire qui le porte — c'est du papier en plus dans celui-là,
 * pas une option de commande.
 */
export const FREE_ZONES_CENTS = 300;

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
 * Un alias de ``getPrintPrice`` : le palier, lui, n'intéresse que les
 * journaux et les tests.
 */
export function unitPriceCents(pageCount: number): number {
  return getPrintPrice(pageCount).priceCents;
}

export function shippingCents(speed: ShippingSpeed): number {
  return speed === "express" ? EXPRESS_CENTS : 0;
}

export type QuoteInput = {
  bookTitle: string;
  pageCount: number;
  copies: number;
  speed: ShippingSpeed;
  /**
   * Combien d'exemplaires portent l'option « Zones libres », qui se facture
   * par exemplaire (``FREE_ZONES_CENTS``). Absent, aucun : un devis qui ne
   * sait rien des options n'en facture pas.
   */
  freeZonesCopies?: number;
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
 *
 * **Un seul supplément d'option** : « Zones libres », 3,00 € par exemplaire
 * qui le porte (``FREE_ZONES_CENTS``). Les autres extras — pointillés, fun
 * facts, quiz, mot fléché — n'ajoutent pas de papier et ne se facturent pas.
 */
export function quote(input: QuoteInput) {
  const pages = Math.max(input.pageCount, 1);
  const copies = Math.max(input.copies, 1);

  const unitCents = unitPriceCents(pages);
  // Les carnets seuls — la ligne « Exemplaires » du récapitulatif.
  const booksCents = unitCents * copies;
  // Jamais plus d'exemplaires que la commande n'en compte, jamais moins de
  // zéro : le compte vient de l'app, et un devis ne se laisse pas dicter.
  const freeZonesCopies = Math.min(Math.max(Math.trunc(input.freeZonesCopies ?? 0), 0), copies);
  const freeZonesCents = FREE_ZONES_CENTS * freeZonesCopies;
  // **Tout ce qui n'est pas la livraison** : les carnets et leurs options.
  // C'est ce chiffre-là que la commande garde en base (`itemsCents`), pour
  // que `itemsCents + shippingCents` reste le prix entier de la commande.
  const itemsCents = booksCents + freeZonesCents;
  const shipCents = shippingCents(input.speed);
  const dueCents = itemsCents + shipCents;

  return {
    bookTitle: input.bookTitle,
    pageCount: pages,
    copies,
    speed: input.speed,
    unitCents,
    specifications: BOOK_SPECIFICATIONS,
    booksCents,
    itemsCents,
    freeZonesCopies,
    freeZonesCents,
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
