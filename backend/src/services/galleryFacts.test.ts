import { describe, expect, it } from "vitest";
import type { TripTransport } from "@prisma/client";
import { derivedGalleryCategorySlugs, derivedGallerySummary } from "./galleryFacts.js";

/** Un carnet qui ne sait rien de lui-même : chaque cas n'allume que ce qu'il teste. */
function facts(overrides: Partial<Parameters<typeof derivedGallerySummary>[0]> = {}) {
  return {
    dayCount: null,
    distanceKilometres: null,
    countryCount: 1,
    stepTransports: [] as (TripTransport | null)[],
    ...overrides,
  };
}

describe("la phrase déduite d'un carnet de la galerie", () => {
  it("ne dit rien quand le carnet ne sait rien", () => {
    // C'est le cas d'un voyage qui vient d'être partagé, avant qu'un souvenir
    // soit traité : la carte n'affiche que son titre, elle n'invente pas.
    expect(derivedGallerySummary(facts())).toBeNull();
  });

  it("compte les jours, puis les semaines, puis les mois", () => {
    expect(derivedGallerySummary(facts({ dayCount: 1 }))).toBe("1 jour");
    expect(derivedGallerySummary(facts({ dayCount: 12 }))).toBe("12 jours");
    // 21 jours est la frontière : « 21 jours » se lit encore mal, « 3 semaines » bien.
    expect(derivedGallerySummary(facts({ dayCount: 21 }))).toBe("3 semaines");
    expect(derivedGallerySummary(facts({ dayCount: 59 }))).toBe("8 semaines");
    expect(derivedGallerySummary(facts({ dayCount: 60 }))).toBe("2 mois");
  });

  it("ne compte pas un seul pays", () => {
    // « 1 pays » ne dit rien de plus que le drapeau déjà posé sur la carte.
    expect(derivedGallerySummary(facts({ dayCount: 9, countryCount: 1 }))).toBe("9 jours");
    expect(derivedGallerySummary(facts({ dayCount: 9, countryCount: 3 }))).toBe("9 jours · 3 pays");
  });

  it("range les trois faits du plus parlant au moins", () => {
    const summary = derivedGallerySummary(
      facts({ dayCount: 12, countryCount: 3, distanceKilometres: 1437.4 }),
    );
    // L'espace des milliers est l'insécable du français, celui que met
    // `toLocaleString("fr-FR")` — on compare donc la chaîne entière.
    expect(summary).toBe(`12 jours · 3 pays · ${(1437).toLocaleString("fr-FR")} km`);
  });

  it("tait une distance que la rédaction n'a pas su relever", () => {
    // Zéro kilomètre n'est pas « un voyage immobile », c'est « on ne sait pas » :
    // aucune étape n'a encore livré de distance.
    expect(derivedGallerySummary(facts({ dayCount: 4, distanceKilometres: 0 }))).toBe("4 jours");
    expect(derivedGallerySummary(facts({ dayCount: 4, distanceKilometres: 0.4 }))).toBe("4 jours");
  });
});

describe("les catégories déduites d'un carnet de la galerie", () => {
  it("ne range nulle part un carnet sans fait", () => {
    expect(derivedGalleryCategorySlugs(facts())).toEqual([]);
  });

  it("demande des pays *et* du temps pour un tour du monde", () => {
    // « La traversée des Alpes » du seed : trois pays, douze jours. Ce n'en est
    // pas un, et c'est exactement le cas que le plancher de durée écarte.
    expect(derivedGalleryCategorySlugs(facts({ countryCount: 3, dayCount: 12 }))).toEqual([]);
    // Deux mois dans un seul pays n'en est pas un non plus.
    expect(derivedGalleryCategorySlugs(facts({ countryCount: 1, dayCount: 60 }))).toEqual([]);
    // « Philippines avec Claire & Gus » : trois pays, deux mois.
    expect(derivedGalleryCategorySlugs(facts({ countryCount: 3, dayCount: 60 }))).toEqual([
      "tour-du-monde",
    ]);
  });

  it("range le carnet sous son transport dominant", () => {
    expect(derivedGalleryCategorySlugs(facts({ stepTransports: ["walk", "walk"] }))).toEqual([
      "randonnee",
    ]);
    expect(derivedGalleryCategorySlugs(facts({ stepTransports: ["bike", "bike", "walk"] }))).toEqual(
      ["velo"],
    );
    expect(derivedGalleryCategorySlugs(facts({ stepTransports: ["boat"] }))).toEqual(["voile"]);
    expect(derivedGalleryCategorySlugs(facts({ stepTransports: ["car", "car"] }))).toEqual([
      "road-trip",
    ]);
  });

  it("refuse de ranger sur une étape isolée", () => {
    // Une quinzaine balnéaire dont une seule journée s'est faite à pied n'est pas
    // une randonnée : à pied ne porte qu'une étape sur quatre. Ici c'est la
    // voiture qui domine, et deux étapes sur quatre *sont* un road trip.
    expect(
      derivedGalleryCategorySlugs(facts({ stepTransports: ["plane", "car", "car", "walk"] })),
    ).toEqual(["road-trip"]);

    // Et quand rien ne domine, on ne range nulle part : à pied mène d'une étape,
    // sans porter la moitié des quatre qui parlent.
    expect(
      derivedGalleryCategorySlugs(facts({ stepTransports: ["walk", "car", "boat", "plane"] })),
    ).toEqual([]);
  });

  it("ignore les transports qui ne disent que le trajet", () => {
    // L'avion et le train ne désignent aucune catégorie : un tour du monde et un
    // city trip prennent le même avion.
    expect(derivedGalleryCategorySlugs(facts({ stepTransports: ["plane", "train"] }))).toEqual([]);
  });

  it("ne laisse pas une étape muette diluer celles qui parlent", () => {
    // Trois étapes, une seule déclare un transport : c'est elle qui décide, et
    // les deux que la rédaction n'a pas su lire ne comptent ni pour ni contre.
    expect(derivedGalleryCategorySlugs(facts({ stepTransports: [null, "boat", null] }))).toEqual([
      "voile",
    ]);
  });

  it("cumule le tour du monde et le transport", () => {
    // Un tour du monde à pied est aussi une randonnée — c'est la raison d'être
    // du pluriel sur `categoryIds`.
    expect(
      derivedGalleryCategorySlugs(
        facts({ countryCount: 4, dayCount: 120, stepTransports: ["walk", "walk"] }),
      ),
    ).toEqual(["tour-du-monde", "randonnee"]);
  });
});
