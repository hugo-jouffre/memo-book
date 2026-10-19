import { describe, expect, it } from "vitest";
import {
  expectedStepCount,
  pageDensity,
  pageDensityInstruction,
  pageTargetTiers,
  pageTargetTierOf,
  photosForTarget,
  reachablePageRange,
  standardPageCount,
  tripDays,
} from "./pageTarget.js";

describe("la cible de pages", () => {
  it("vise 40 / 60 / 80 pages sans date de fin", () => {
    expect(standardPageCount(null)).toBe(60);
    expect(pageDensity(40, null)).toBe("compact");
    expect(pageDensity(60, null)).toBe("standard");
    expect(pageDensity(80, null)).toBe("detailed");
  });

  it("lit la densité par rapport à la durée du voyage", () => {
    const days = tripDays(new Date("2026-08-01"), new Date("2026-08-30"));
    expect(days).toBe(30);
    expect(standardPageCount(days)).toBe(30);
    expect(pageDensity(60, days)).toBe("detailed");
    expect(pageDensity(20, days)).toBe("compact");
    expect(tripDays(new Date("2026-08-01"), null)).toBeNull();
  });

  it("donne à la rédaction la fourchette de ± 5 pages", () => {
    expect(pageDensityInstruction(40, null)).toContain("entre 35 et 45");
    expect(pageDensityInstruction(40, null)).toContain("compact");
  });
});

describe("les paliers suivent aussi le ratio (18/10/2026)", () => {
  it("sans date de fin : 40 à 0 %, 60 à 50 %, 80 à 100 %", () => {
    expect(standardPageCount(null, 0)).toBe(40);
    expect(standardPageCount(null, 25)).toBe(50);
    expect(standardPageCount(null, 50)).toBe(60);
    expect(standardPageCount(null, 75)).toBe(70);
    expect(standardPageCount(null, 100)).toBe(80);
  });

  it("un voyage de 40 jours à 25 % vise moins qu'à 75 %", () => {
    expect(pageTargetTiers(40, 25)).toEqual({ compact: 20, standard: 30, detailed: 40 });
    expect(pageTargetTiers(40, 75)).toEqual({ compact: 30, standard: 50, detailed: 70 });
    expect(pageTargetTierOf(50, 40, 75)).toBe("standard");
    expect(pageTargetTierOf(44, 40, 75)).toBeNull();
  });

  it("estime les étapes sur la durée et le rythme du récit, jamais sous celles écrites", () => {
    expect(expectedStepCount(10, "daily", 0)).toBe(10);
    expect(expectedStepCount(10, "every_two_days", 0)).toBe(5);
    expect(expectedStepCount(10, "every_two_days", 7)).toBe(7);
    expect(expectedStepCount(null, "weekly", 0)).toBe(3);
  });
});

describe("la cible demande des photos au-delà du ratio", () => {
  it("dix étapes de trois paragraphes à 50 %, cible 40 : une double page de photos de plus par étape", () => {
    const extra = photosForTarget({ targetPageCount: 40, ratio: 50, days: 10, pace: "daily", writtenSteps: 3, stepPages: 2 });
    expect(extra).toEqual({ extraPages: 2, extraPhotos: 6 });
    // 4 pages fixes + 10 étapes de 4 pages : 44, dans 40 ± 5.
  });

  it("rien sans date de fin : le nombre d'étapes est inconnu", () => {
    expect(photosForTarget({ targetPageCount: 60, ratio: 50, days: null, pace: null, writtenSteps: 1, stepPages: 2 }).extraPages).toBe(0);
  });

  it("rien quand le récit suffit, rien à 0 %", () => {
    expect(photosForTarget({ targetPageCount: 24, ratio: 50, days: 10, pace: "daily", writtenSteps: 0, stepPages: 2 }).extraPages).toBe(0);
    expect(photosForTarget({ targetPageCount: 80, ratio: 0, days: 10, pace: "daily", writtenSteps: 0, stepPages: 2 }).extraPages).toBe(0);
  });

  it("deux doubles pages au plus à 75 %, une à 25 %, six pages par étape", () => {
    const at = (ratio: number, stepPages = 2) =>
      photosForTarget({ targetPageCount: 180, ratio, days: 10, pace: "daily", writtenSteps: 0, stepPages }).extraPages;
    expect(at(25)).toBe(2);
    expect(at(75)).toBe(4);
    expect(at(75, 4)).toBe(2);
  });
});

describe("ce que le carnet peut atteindre", () => {
  const voyage = { days: 10, pace: "daily", density: "standard" as const };

  it("dix étapes à venir : de 24 à 44 pages à 50 %, 24 tout court à 0 %", () => {
    expect(reachablePageRange({ ...voyage, ratio: 50, writtenStepPages: [] })).toEqual({ min: 24, max: 44, steps: 10 });
    expect(reachablePageRange({ ...voyage, ratio: 0, writtenStepPages: [] })).toEqual({ min: 24, max: 24, steps: 10 });
  });

  it("le récit détaillé ouvre la taille XXL aux étapes à venir", () => {
    expect(reachablePageRange({ ...voyage, density: "detailed", ratio: 0, writtenStepPages: [] }).max).toBe(44);
  });

  it("un ratio plus haut ouvre une cible plus longue", () => {
    const at = (ratio: number) => reachablePageRange({ ...voyage, ratio, writtenStepPages: [2, 3] });
    expect(at(75).max).toBeGreaterThan(at(25).max);
    expect(at(0).min).toBe(at(100).min);
  });
});
