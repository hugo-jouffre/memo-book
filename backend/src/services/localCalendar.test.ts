import { describe, expect, it } from "vitest";
import { addDays, daysBetween, isValidTimeZone, localDate, localHour, sameDayInYear } from "./localCalendar.js";

describe("le calendrier du voyageur", () => {
  it("lit le jour et l'heure dans le fuseau du téléphone, pas dans celui du serveur", () => {
    const instant = new Date("2026-10-14T22:30:00Z");
    expect(localDate(instant, "Europe/Paris")).toBe("2026-10-15");
    expect(localHour(instant, "Europe/Paris")).toBe(0);
    expect(localDate(instant, "America/Montreal")).toBe("2026-10-14");
    expect(localHour(instant, "Asia/Tokyo")).toBe(7);
  });

  it("compte les jours sans se tromper au changement d'heure", () => {
    expect(addDays("2026-10-24", 3)).toBe("2026-10-27");
    expect(daysBetween("2026-10-24", "2026-10-27")).toBe(3);
    expect(daysBetween("2026-10-27", "2026-10-24")).toBe(-3);
  });

  it("garde un 29 février au 28 les autres années", () => {
    expect(sameDayInYear("2000-02-29", 2027)).toBe("2027-02-28");
    expect(sameDayInYear("2000-02-29", 2028)).toBe("2028-02-29");
  });

  it("refuse un fuseau qui n'existe pas", () => {
    expect(isValidTimeZone("Europe/Paris")).toBe(true);
    expect(isValidTimeZone("Mars/Olympus")).toBe(false);
  });
});
