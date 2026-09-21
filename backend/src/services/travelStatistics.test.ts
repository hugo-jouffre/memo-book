import { describe, expect, it } from "vitest";
import { parseInsights } from "./redaction.js";
import {
  aggregateTravelStatistics,
  tripDayCount,
  type MemoForStatistics,
} from "./travelStatistics.js";

/**
 * Les statistiques s'additionnent à la lecture, depuis les relevés de la
 * rédaction. Ce qui est vérifié ici : le plancher déclaré par le voyage, la
 * priorité du relevé sur la fiche, la dédoublonnage des lieux, et le compte
 * des souvenirs qui attendent encore leur relevé — c'est lui qui pilote le
 * rafraîchissement de la feuille dans l'app.
 */

function memo(overrides: Partial<MemoForStatistics> = {}): MemoForStatistics {
  return {
    id: "memo",
    stage: "ongoing",
    startDate: new Date("2026-12-10T00:00:00Z"),
    endDate: new Date("2027-01-02T00:00:00Z"),
    dayCount: null,
    destinationCountryCode: "IT",
    destinationCity: "Rome",
    distanceKilometres: 87.4,
    steps: [],
    entries: [],
    ...overrides,
  };
}

function entry(
  insights: unknown,
  overrides: Partial<MemoForStatistics["entries"][number]> = {},
): MemoForStatistics["entries"][number] {
  return {
    kind: "audio",
    redactionStatus: "ready",
    capturedAt: new Date("2026-12-11T10:00:00Z"),
    insights,
    ...overrides,
  };
}

describe("tripDayCount", () => {
  it("préfère le compteur de la fiche, sinon compte les bornes comprises", () => {
    expect(tripDayCount({ dayCount: 21, startDate: null, endDate: null })).toBe(21);
    expect(
      tripDayCount({
        dayCount: null,
        startDate: new Date("2026-12-10T00:00:00Z"),
        endDate: new Date("2026-12-12T00:00:00Z"),
      }),
    ).toBe(3);
    expect(tripDayCount({ dayCount: null, startDate: null, endDate: null })).toBe(0);
  });
});

describe("aggregateTravelStatistics", () => {
  it("part de ce que le voyage déclare, sans aucun relevé", () => {
    const stats = aggregateTravelStatistics([
      memo({ steps: [{ destinationCountryCode: "IT", transport: "plane" }] }),
    ]);

    expect(stats.tripCount).toBe(1);
    expect(stats.overall).toEqual({
      countries: 1,
      regions: 0,
      cities: 1,
      encounters: 0,
      distanceKilometres: 87,
    });
    expect(stats.currentTrip?.currentPlace).toBe("Rome");
    expect(stats.currentTrip?.transports).toEqual([{ kind: "plane", count: 1 }]);
    expect(stats.currentTrip?.dayCount).toBe(24);
    expect(stats.pendingDetections).toBe(0);
  });

  it("additionne les relevés et laisse le relevé primer sur la fiche", () => {
    const stats = aggregateTravelStatistics([
      memo({
        steps: [{ destinationCountryCode: "IT", transport: "plane" }],
        entries: [
          entry({
            countries: [{ code: "it", name: "Italie" }],
            regions: ["Latium"],
            cities: ["rome", "Ostie"],
            peopleMet: 3,
            distanceKilometres: 30,
            transports: [{ kind: "train", count: 2 }],
            currentPlace: "Ostie",
          }),
          entry(
            {
              countries: [{ code: "VA", name: "Vatican" }],
              regions: ["latium"],
              cities: ["Rome"],
              peopleMet: 1,
              distanceKilometres: null,
              transports: [{ kind: "scooter", count: null }],
              currentPlace: "Rome",
            },
            { capturedAt: new Date("2026-12-12T09:00:00Z"), kind: "text" },
          ),
        ],
      }),
    ]);

    const current = stats.currentTrip;
    expect(current?.figures).toEqual({
      countries: 2,
      regions: 1,
      cities: 2,
      encounters: 4,
      // Les 30 km relevés remplacent les 87,4 de la fiche — pas d'addition.
      distanceKilometres: 30,
    });
    // Le souvenir le plus récent situe le voyageur.
    expect(current?.currentPlace).toBe("Rome");
    // Les transports relevés remplacent ceux des étapes ; le non compté ferme
    // la marche.
    expect(current?.transports).toEqual([
      { kind: "train", count: 2 },
      { kind: "scooter", count: null },
    ]);
    expect(current?.recordings).toBe(1);
    expect(current?.validatedDays).toBe(2);
  });

  it("compte les souvenirs qui attendent encore leur relevé", () => {
    const stats = aggregateTravelStatistics([
      memo({
        entries: [
          entry(null, { redactionStatus: "pending" }),
          entry(null, { redactionStatus: "processing" }),
          entry(null, { kind: "photo", redactionStatus: "pending" }),
          entry(null, { redactionStatus: "failed" }),
        ],
      }),
    ]);

    // Les photos n'ont pas de relevé à attendre, et un échec n'attend plus.
    expect(stats.pendingDetections).toBe(2);
    expect(stats.currentTrip?.validatedDays).toBe(0);
  });

  it("dédoublonne les lieux entre voyages et choisit le voyage en cours le plus récent", () => {
    const stats = aggregateTravelStatistics([
      memo({
        id: "old",
        stage: "past",
        destinationCountryCode: "PT",
        destinationCity: "Lisbonne",
        distanceKilometres: 41,
      }),
      memo({
        id: "rome-1",
        startDate: new Date("2026-08-26T00:00:00Z"),
        entries: [entry({ ...parseInsights(null), cities: ["Rome"], currentPlace: "Rome" })],
      }),
      memo({
        id: "rome-2",
        startDate: new Date("2026-12-10T00:00:00Z"),
        destinationCity: "rome",
      }),
    ]);

    expect(stats.tripCount).toBe(3);
    expect(stats.overall.countries).toBe(2);
    expect(stats.overall.cities).toBe(2);
    // Arrondi sur le total, pas voyage par voyage : 41 + 87,4 + 87,4.
    expect(stats.overall.distanceKilometres).toBe(216);
    expect(stats.currentTrip?.id).toBe("rome-2");
  });

  it("ne rend aucun voyage en cours quand il n'y en a pas", () => {
    const stats = aggregateTravelStatistics([memo({ stage: "upcoming" })]);
    expect(stats.currentTrip).toBeNull();
    expect(stats.tripCount).toBe(1);
  });
});

describe("parseInsights", () => {
  it("relit un relevé de travers sans casser", () => {
    expect(parseInsights(undefined)).toEqual(parseInsights(null));
    expect(
      parseInsights({
        countries: [{ code: "italie", name: "Italie" }, { code: "fr", name: " France " }, "IT"],
        regions: ["Latium", " latium ", 3],
        cities: [],
        peopleMet: -4,
        distanceKilometres: "12",
        transports: [{ kind: "rocket", count: 1 }, { kind: "bus", count: 2.4 }, { kind: "bus" }],
        currentPlace: "  ",
      }),
    ).toEqual({
      countries: [{ code: "FR", name: "France" }],
      regions: ["Latium"],
      cities: [],
      peopleMet: 0,
      distanceKilometres: null,
      transports: [{ kind: "bus", count: 2 }],
      currentPlace: null,
    });
  });
});
