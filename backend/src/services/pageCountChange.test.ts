import { describe, expect, it } from "vitest";
import { formatEuros } from "./notificationCopy.js";
import { changementDePages, pageCountChangeText } from "./pageCountChange.js";

/**
 * **Quand le carnet change de prix** (T265, 24/11/2026).
 *
 * Ce qui se teste ici est surtout le **silence** : l'aperçu se recompose à
 * chaque changement du carnet, et une bulle à chaque pagination noierait le
 * fil. Les paliers de `printPricing.ts` : 46–65 pages à 75 €, 66–85 à 80 €,
 * 86–100 à 85 €.
 */
describe("décider s'il y a quelque chose à dire", () => {
  it("parle quand le carnet change de palier", () => {
    const change = changementDePages(80, 90, 0);
    expect(change).toEqual({ avant: 80, apres: 90, prixAvant: 8_000, prixApres: 8_500 });
  });

  it("se tait quand les pages bougent sans changer le prix", () => {
    // 70 et 80 pages sont dans le même palier : rien à décider, rien à dire.
    expect(changementDePages(70, 80, 0)).toBeNull();
  });

  it("se tait sur le premier carnet, qui n'a rien à comparer", () => {
    expect(changementDePages(null, 90, 0)).toBeNull();
    expect(changementDePages(0, 90, 0)).toBeNull();
  });

  it("se tait quand rien n'a bougé", () => {
    expect(changementDePages(90, 90, 0)).toBeNull();
  });

  /**
   * **Ce qui est composé se facture, même sous la cible.** `billablePages` ne
   * retombe sur la cible que tant que rien n'est composé : un carnet de
   * 40 pages visant 90 se paie 40. Passer de 40 à 60 change donc bien de
   * palier, et se dit.
   */
  it("compte les pages composées, pas la cible", () => {
    expect(changementDePages(40, 60, 90)).toEqual({
      avant: 40,
      apres: 60,
      prixAvant: 5_500,
      prixApres: 7_500,
    });
  });

  it("parle aussi quand le carnet maigrit", () => {
    const change = changementDePages(90, 60, 0);
    expect(change?.prixApres).toBeLessThan(change?.prixAvant ?? 0);
  });

  /** Au-delà du maximum relié, il n'y a pas de prix : ce n'est pas ici qu'on l'apprend. */
  it("se tait quand le carnet dépasse ce que l'imprimeur sait relier", () => {
    expect(changementDePages(90, 900, 0)).toBeNull();
  });
});

describe("ce que MEMO en dit", () => {
  it("annonce la nouvelle pagination et le nouveau prix", () => {
    const texte = pageCountChangeText({ avant: 80, apres: 90, prixAvant: 8_000, prixApres: 8_500 });
    expect(texte).toContain("fait maintenant 90 pages");
    expect(texte).toContain("contre 80");
    // `formatEuros` sépare le montant et l'euro par une espace insécable
    // étroite : on compare à ce qu'il rend, pas à ce qu'on croit qu'il rend.
    expect(texte).toContain(formatEuros(8_000));
    expect(texte).toContain(formatEuros(8_500));
  });

  it("dit l'inverse quand le carnet maigrit", () => {
    const texte = pageCountChangeText({ avant: 90, apres: 60, prixAvant: 8_500, prixApres: 7_500 });
    expect(texte).toContain("ne fait plus que 60 pages");
  });
});
