import { describe, expect, it } from "vitest";
import { quote, unitPriceCents } from "./printPricing.js";

describe("le tarif d'un carnet", () => {
  it("garde l'ancre commerciale : 50 pages font 89,90 €", () => {
    expect(unitPriceCents(50)).toBe(8_990);
  });

  it("ne facture pas un carnet de dix pages au cinquième d'un carnet de cinquante", () => {
    // C'est tout l'intérêt d'avoir sorti les frais fixes du taux à la page :
    // la couverture et la reliure coûtent pareil quel que soit le nombre de
    // pages.
    expect(unitPriceCents(10)).toBeGreaterThan(unitPriceCents(50) / 5);
  });

  it("compte au moins une page, même sur un carnet vide", () => {
    expect(unitPriceCents(0)).toBe(unitPriceCents(1));
  });
});

describe("le récapitulatif", () => {
  const base = {
    bookTitle: "Rome et la Dolce Vita",
    pageCount: 50,
    copies: 2,
    speed: "standard" as const,
  };

  it("multiplie le prix unitaire par le nombre d'exemplaires", () => {
    const result = quote(base);
    expect(result.itemsCents).toBe(2 * 8_990);
    expect(result.totalCents).toBe(2 * 8_990);
  });

  it("n'ajoute rien pour l'acheminement standard, et le supplément pour l'express", () => {
    expect(quote(base).shippingCents).toBe(0);
    expect(quote({ ...base, speed: "express" }).shippingCents).toBe(990);
  });

  it("ne montre aucune déduction : la cagnotte est retirée (06/10/2026)", () => {
    // « - 0,00 € » ferait croire à une réduction qui n'a pas eu lieu, et il n'y
    // a plus rien à déduire : tout se paie par Stripe.
    const result = quote({ ...base, speed: "express" });
    expect(result.deductions).toEqual([]);
    expect(result.walletAppliedCents).toBe(0);
  });

  it("boucle : total = articles + livraison", () => {
    const result = quote({ ...base, speed: "express" });
    expect(result.totalCents).toBe(result.itemsCents + result.shippingCents);
    expect(result.totalCents).toBe(result.dueCents);
  });

  it("annonce les bornes du palier choisi", () => {
    expect(quote(base).estimatedDays).toEqual({ min: 5, max: 7 });
    expect(quote({ ...base, speed: "express" }).estimatedDays).toEqual({ min: 2, max: 3 });
  });
});
