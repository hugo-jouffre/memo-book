import { afterEach, describe, expect, it } from "vitest";
import {
  billablePages,
  getPrintPrice,
  maxBillablePages,
  MINIMUM_BILLABLE_PAGES,
  PRINT_PRICE_TIERS,
  quote,
  unitPriceCents,
} from "./printPricing.js";
import { PAGE_TARGET_TOLERANCE, pageTargetTiers } from "./pageTarget.js";
import { composedPageCount } from "../jobs/render.js";

/** Ouvre ou referme le palier 301-400 le temps d'un test. */
function allowOver300(isOpen: boolean): void {
  if (isOpen) process.env.ALLOW_OVER_300_PAGES = "true";
  else delete process.env.ALLOW_OVER_300_PAGES;
}

afterEach(() => {
  allowOver300(false);
});

describe("le prix par palier de pages", () => {
  it("chaque palier vaut de sa première à sa dernière page comprises", () => {
    // Les bornes de la grille, palier par palier (Hugo, 21/10/2026).
    const bornes: [number, string, number][] = [
      [16, "compact", 5_500],
      [45, "compact", 5_500],
      [46, "standard", 7_500],
      [65, "standard", 7_500],
      [66, "detailed", 8_000],
      [85, "detailed", 8_000],
      [86, "detailed-plus", 8_500],
      [100, "detailed-plus", 8_500],
      [101, "large", 10_500],
      [120, "large", 10_500],
      [121, "large-plus", 11_000],
      [200, "large-plus", 11_000],
      [201, "very-large", 12_900],
      [300, "very-large", 12_900],
    ];

    for (const [pages, tierId, priceCents] of bornes) {
      expect(getPrintPrice(pages), `${pages} pages`).toEqual({ tierId, priceCents });
    }
  });

  it("sous le minimum de l'imprimeur, le carnet se facture comme 16 pages", () => {
    expect(MINIMUM_BILLABLE_PAGES).toBe(16);
    expect(getPrintPrice(1)).toEqual({ tierId: "compact", priceCents: 5_500 });
    expect(getPrintPrice(15)).toEqual({ tierId: "compact", priceCents: 5_500 });
    expect(getPrintPrice(16)).toEqual({ tierId: "compact", priceCents: 5_500 });
  });

  it("au-delà de 300 pages, pas de prix : le palier 301-400 est fermé par défaut", () => {
    expect(maxBillablePages()).toBe(300);
    expect(() => getPrintPrice(301)).toThrowError(/dépasse le maximum de 300 pages/);
    expect(() => getPrintPrice(400)).toThrowError(/dépasse le maximum de 300 pages/);
    expect(() => getPrintPrice(401)).toThrowError(/dépasse le maximum de 300 pages/);
  });

  it("le flag ouvre le dernier palier, et pas un de plus", () => {
    allowOver300(true);
    expect(maxBillablePages()).toBe(400);
    expect(getPrintPrice(301)).toEqual({ tierId: "beyond", priceCents: 14_500 });
    expect(getPrintPrice(400)).toEqual({ tierId: "beyond", priceCents: 14_500 });
    expect(() => getPrintPrice(401)).toThrowError(/dépasse le maximum de 400 pages/);
  });

  it("la grille ne laisse aucun trou entre deux paliers", () => {
    expect(PRINT_PRICE_TIERS[0]?.from).toBe(MINIMUM_BILLABLE_PAGES);
    for (let index = 1; index < PRINT_PRICE_TIERS.length; index += 1) {
      expect(PRINT_PRICE_TIERS[index]?.from).toBe((PRINT_PRICE_TIERS[index - 1]?.to ?? 0) + 1);
    }
  });

  it("le prix ne dépend que des pages — jamais de la durée ni du nom de l'option", () => {
    // Un « Compact » de six mois fait 120 pages : il se paie au palier
    // 101-120, pas au premier.
    expect(unitPriceCents(pageTargetTiers(180, 50).compact)).toBe(10_500);
  });
});

describe("le prix affiché par l'onglet « Nmb de pages »", () => {
  /**
   * Ce que l'écran annonce pour une option : le palier de **cible +
   * tolérance**, puisque le carnet composé ne dépasse jamais cet écart. Le
   * prix facturé ne peut donc pas dépasser le prix affiché.
   */
  const displayed = (pages: number) => getPrintPrice(pages + PAGE_TARGET_TOLERANCE).priceCents;

  it("suit l'onglet « Cibles » du sheet, au ratio photo de 50 %", () => {
    // Durée en jours (nulle = sans date de fin), puis les trois prix attendus.
    const cas: [number | null, number, number, number][] = [
      [30, 5_500, 5_500, 5_500],
      [60, 5_500, 7_500, 8_000],
      [90, 7_500, 8_500, 11_000],
      [180, 11_000, 11_000, 12_900],
      [null, 5_500, 7_500, 8_000],
    ];

    for (const [days, compact, standard, detailed] of cas) {
      const cibles = pageTargetTiers(days, 50);
      expect([displayed(cibles.compact), displayed(cibles.standard), displayed(cibles.detailed)], `${days} jours`)
        .toEqual([compact, standard, detailed]);
    }
  });
});

describe("le devis", () => {
  it("facture les zones libres par exemplaire qui les porte", () => {
    const sans = quote({ bookTitle: "Rome", pageCount: 60, copies: 2, speed: "standard" });
    expect(sans.freeZonesCents).toBe(0);
    expect(sans.totalCents).toBe(2 * 7_500);

    const avec = quote({
      bookTitle: "Rome",
      pageCount: 60,
      copies: 2,
      speed: "standard",
      freeZonesCopies: 1,
    });
    expect(avec.freeZonesCents).toBe(300);
    expect(avec.totalCents).toBe(2 * 7_500 + 300);
  });

  it("ne facture jamais plus d'exemplaires que la commande n'en compte", () => {
    const priced = quote({
      bookTitle: "Rome",
      pageCount: 60,
      copies: 1,
      speed: "standard",
      freeZonesCopies: 9,
    });
    expect(priced.freeZonesCopies).toBe(1);
    expect(priced.freeZonesCents).toBe(300);
  });
});

describe("le prix suit le carnet composé", () => {
  it("le nombre final de pages fait le prix, même sous la cible", () => {
    expect(billablePages({ targetPageCount: 40, pageCount: 24 })).toBe(24);
    expect(billablePages({ targetPageCount: 40, pageCount: 46 })).toBe(46);
  });

  it("avant tout carnet composé, la cible sert d'estimation", () => {
    expect(billablePages({ targetPageCount: 60, pageCount: 0 })).toBe(60);
  });

  it("le carnet compte ses pages d'avant, ses étapes et la page blanche finale", () => {
    const days = Array.from({ length: 20 }, () => ({}));
    // colophon + introduction + une page blanche pour ouvrir à gauche, 20 pages d'étape, une blanche finale.
    expect(composedPageCount({ intro_text: "<p>…</p>", pages_libres_avant: 1, days, page_blanche_finale: true })).toBe(24);
    expect(composedPageCount({ days })).toBe(21);
    expect(composedPageCount({})).toBeNull();
  });
});
