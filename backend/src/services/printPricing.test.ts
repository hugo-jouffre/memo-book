import { describe, expect, it } from "vitest";
import { quote, splitWalletCredit, unitPriceCents } from "./printPricing.js";

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

describe("la répartition de la cagnotte", () => {
  it("retombe exactement sur le montant déduit, sans dérive d'arrondi", () => {
    // Un tiers / deux tiers sur un montant impair : c'est là qu'un arrondi
    // naïf perdrait un centime en route.
    const split = splitWalletCredit(1_001, 1_000, 2_000);
    expect(split.giftCents + split.subscriptionCents).toBe(1_001);
  });

  it("ne répartit rien quand il n'y a rien à déduire", () => {
    expect(splitWalletCredit(0, 3_000, 800)).toEqual({ giftCents: 0, subscriptionCents: 0 });
  });

  it("ne répartit rien quand la cagnotte n'a jamais reçu de crédit", () => {
    // Le solde peut être positif sans crédit connu — un ajustement du support,
    // par exemple. Mieux vaut ne rien ventiler que d'inventer une provenance.
    expect(splitWalletCredit(500, 0, 0)).toEqual({ giftCents: 0, subscriptionCents: 0 });
  });
});

describe("le récapitulatif", () => {
  const base = {
    bookTitle: "Rome et la Dolce Vita",
    pageCount: 50,
    copies: 2,
    speed: "standard" as const,
    walletBalanceCents: 0,
    giftCreditCents: 0,
    topupCreditCents: 0,
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

  it("plafonne la cagnotte au montant dû : elle ne rend pas la monnaie", () => {
    const result = quote({ ...base, walletBalanceCents: 100_000, giftCreditCents: 100_000 });
    expect(result.walletAppliedCents).toBe(result.dueCents);
    expect(result.totalCents).toBe(0);
  });

  it("ne montre pas une déduction nulle", () => {
    // « - 0,00 € » ferait croire à une réduction qui n'a pas eu lieu.
    const result = quote({ ...base, walletBalanceCents: 3_000, giftCreditCents: 3_000 });
    expect(result.deductions.map((line) => line.id)).toEqual(["wallet"]);
  });

  it("boucle : total = articles + livraison - cagnotte", () => {
    const result = quote({
      ...base,
      speed: "express",
      walletBalanceCents: 3_199,
      giftCreditCents: 3_000,
      topupCreditCents: 199,
    });
    expect(result.totalCents).toBe(
      result.itemsCents + result.shippingCents - result.walletAppliedCents,
    );
    // Et les deux lignes affichées rendent bien ce qui a été déduit.
    const shown = result.deductions.reduce((sum, line) => sum + line.amountCents, 0);
    expect(shown).toBe(result.walletAppliedCents);
  });

  it("annonce les bornes du palier choisi", () => {
    expect(quote(base).estimatedDays).toEqual({ min: 5, max: 7 });
    expect(quote({ ...base, speed: "express" }).estimatedDays).toEqual({ min: 2, max: 3 });
  });
});
