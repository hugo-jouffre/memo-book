import { describe, expect, it } from "vitest";
import { pageDensity, pageDensityInstruction, standardPageCount, tripDays } from "./pageTarget.js";

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
