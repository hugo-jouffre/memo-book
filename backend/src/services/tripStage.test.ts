import { describe, expect, it } from "vitest";
import { effectiveStage, stageFromDates } from "./tripStage.js";

const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);

describe("l'état d'un voyage, lu sur ses dates", () => {
  it("ferme un voyage le lendemain de sa date de fin, pas le jour même", () => {
    // Le voyage de Clara : fini le 15, encore « en cours » le 16 parce que la
    // colonne était figée. Le 15, il est en cours jusqu'au bout de la journée.
    const start = day("2026-09-01");
    const end = day("2026-09-15");

    expect(stageFromDates(start, end, new Date("2026-09-15T18:00:00.000Z"))).toBe("ongoing");
    expect(stageFromDates(start, end, new Date("2026-09-16T00:00:00.000Z"))).toBe("past");
    expect(stageFromDates(start, end, new Date("2026-09-16T09:00:00.000Z"))).toBe("past");
  });

  it("annonce un voyage à venir tant que son départ n'est pas là", () => {
    expect(stageFromDates(day("2026-10-01"), null, day("2026-09-16"))).toBe("upcoming");
    expect(stageFromDates(day("2026-10-01"), null, day("2026-10-01"))).toBe("ongoing");
  });

  it("garde en cours un voyage sans date de fin", () => {
    expect(stageFromDates(day("2026-09-01"), null, day("2027-01-01"))).toBe("ongoing");
  });

  it("s'en remet à la colonne quand il n'y a aucune date", () => {
    expect(stageFromDates(null, null, day("2026-09-16"), "past")).toBe("past");
    expect(stageFromDates(null, null, day("2026-09-16"))).toBe("ongoing");
  });
});

describe("l'état d'un carnet lu en base", () => {
  it("préfère les dates à ce que la colonne a retenu", () => {
    const memo = { stage: "ongoing", startDate: day("2026-09-01"), endDate: day("2026-09-15") };
    expect(effectiveStage(memo, day("2026-09-16"))).toBe("past");
  });

  it("lit la colonne d'un carnet sans date, et ignore une valeur inconnue", () => {
    expect(effectiveStage({ stage: "past", startDate: null, endDate: null })).toBe("past");
    expect(effectiveStage({ stage: "???", startDate: null, endDate: null })).toBe("ongoing");
  });
});
