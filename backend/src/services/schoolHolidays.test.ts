import { describe, expect, it } from "vitest";
import { parseCalendar, schoolZoneOf } from "./schoolHolidays.js";

describe("la zone scolaire, d'après l'adresse du profil", () => {
  it("lit le département dans le code postal", () => {
    expect(schoolZoneOf("69003", "FR")).toBe("A"); // Lyon
    expect(schoolZoneOf("44000", "France")).toBe("B"); // Nantes
    expect(schoolZoneOf("75011", null)).toBe("C"); // Paris, adresse d'avant le champ pays
    expect(schoolZoneOf("20000", "FR")).toBe("Corse");
    expect(schoolZoneOf(" 31 000 ", "FR")).toBe("C");
  });

  it("ne devine rien hors de la métropole, ni sur un code qui ne ressemble à rien", () => {
    expect(schoolZoneOf("97400", "FR")).toBeNull(); // La Réunion : calendrier à part
    expect(schoolZoneOf("1000", "BE")).toBeNull();
    expect(schoolZoneOf("75011", "BE")).toBeNull();
    expect(schoolZoneOf(null, "FR")).toBeNull();
    expect(schoolZoneOf("ABCDE", "FR")).toBeNull();
  });
});

describe("le calendrier du ministère", () => {
  it("garde les vacances, au jour de Paris, une période par zone, libellé et année", () => {
    const periods = parseCalendar([
      {
        description: "Vacances de la Toussaint",
        start_date: "2026-10-16T22:00:00+00:00",
        end_date: "2026-11-01T23:00:00+00:00",
        zones: "Zone B",
        annee_scolaire: "2026-2027",
      },
      // Deux populations pour l'été : on garde la reprise des élèves.
      {
        description: "Vacances d'Été",
        start_date: "2027-07-02T22:00:00+00:00",
        end_date: "2027-08-31T22:00:00+00:00",
        zones: "Zone A",
        annee_scolaire: "2026-2027",
      },
      {
        description: "Vacances d'Été",
        start_date: "2027-07-02T22:00:00+00:00",
        end_date: "2027-09-01T22:00:00+00:00",
        zones: "Zone A",
        annee_scolaire: "2026-2027",
      },
      // Un pont n'est pas une période de vacances, l'outre-mer n'est pas repris.
      {
        description: "Pont de l'Ascension",
        start_date: "2027-05-06T22:00:00+00:00",
        end_date: "2027-05-06T22:00:00+00:00",
        zones: "Zone C",
        annee_scolaire: "2026-2027",
      },
      {
        description: "Vacances après 1ère période",
        start_date: "2026-10-09T22:00:00+00:00",
        end_date: "2026-10-25T23:00:00+00:00",
        zones: "Réunion",
        annee_scolaire: "2026-2027",
      },
    ]);

    expect(periods).toEqual([
      {
        zone: "B",
        label: "Vacances de la Toussaint",
        schoolYear: "2026-2027",
        startsOn: "2026-10-17",
        endsOn: "2026-11-02",
      },
      { zone: "A", label: "Vacances d'Été", schoolYear: "2026-2027", startsOn: "2027-07-03", endsOn: "2027-09-02" },
    ]);
  });
});
