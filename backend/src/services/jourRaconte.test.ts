import { describe, expect, it } from "vitest";
import { EMPTY_INSIGHTS, parseLivedDays } from "./redaction.js";
import { groupEntriesByDay, type StructuringEntry } from "./structuring.js";
import { stepFields, type StepGroup } from "./tripFacts.js";

/**
 * **Le jour que le récit raconte** (T308).
 *
 * Un vocal dit quand on en **parle**. L'étape affichait ce jour-là comme si
 * c'était celui qu'on avait vécu : un dimanche pour une journée de vendredi,
 * et une « tranche » de trois jours pour une étape racontée en trois fois.
 * Elle n'affiche maintenant que ce que la rédaction a compris — une date
 * précise pour une journée, une tranche pour une période, et rien du tout
 * quand le récit ne s'est pas situé.
 */

const GRECE = { startDate: new Date("2026-08-26T00:00:00Z"), endDate: new Date("2026-09-04T00:00:00Z") };

const day = (iso: string) => new Date(`${iso}T00:00:00Z`);

let clock = 8;

/** Un récit, enregistré à une heure qui n'a rien à voir avec ce qu'il raconte. */
function story(options: { livedFrom?: string; livedTo?: string; capturedOn?: string } = {}) {
  clock += 1;
  const at = new Date(`${options.capturedOn ?? "2026-09-02"}T0${clock % 10}:00:00Z`);
  return {
    id: `recit-${clock}`,
    kind: "audio" as const,
    capturedAt: at,
    createdAt: at,
    stepId: null,
    insights: EMPTY_INSIGHTS,
    cdnUrl: null,
    continuesPrevious: false,
    pinnedStepId: null,
    capturedPlaceName: null,
    livedFromDay: options.livedFrom ? day(options.livedFrom) : null,
    livedToDay: options.livedTo ? day(options.livedTo) : null,
  };
}

const groupOf = (...entries: ReturnType<typeof story>[]): StepGroup => ({
  place: null,
  entries,
  stepId: null,
  pinned: false,
});

describe("ce que la rédaction est autorisée à dire du jour vécu", () => {
  it("retient un jour bien formé, dans le voyage", () => {
    expect(parseLivedDays({ livedFrom: "2026-08-28", livedTo: null }, GRECE)).toEqual({
      livedFrom: "2026-08-28",
      livedTo: null,
    });
  });

  it("garde la tranche quand le récit couvre plusieurs jours", () => {
    expect(parseLivedDays({ livedFrom: "2026-08-28", livedTo: "2026-08-30" }, GRECE)).toEqual({
      livedFrom: "2026-08-28",
      livedTo: "2026-08-30",
    });
  });

  /**
   * Une fin le même jour n'est pas une période : c'est une journée, et c'est
   * ce que `livedFrom` seul dit déjà. La règle tient partout ensuite — une fin
   * renseignée veut dire une tranche.
   */
  it("ne fait pas une tranche d'une seule journée", () => {
    expect(parseLivedDays({ livedFrom: "2026-08-28", livedTo: "2026-08-28" }, GRECE).livedTo).toBeNull();
    expect(parseLivedDays({ livedFrom: "2026-08-28", livedTo: "2026-08-27" }, GRECE).livedTo).toBeNull();
  });

  /**
   * Le modèle rend parfois l'année en cours là où le voyage est l'an dernier.
   * Hors de la fenêtre, on préfère ne rien savoir : l'étape se taira.
   */
  it("refuse un jour hors du voyage", () => {
    expect(parseLivedDays({ livedFrom: "2025-08-28", livedTo: null }, GRECE).livedFrom).toBeNull();
    expect(parseLivedDays({ livedFrom: "2026-08-28", livedTo: "2026-12-01" }, GRECE).livedTo).toBeNull();
  });

  it("refuse ce qui n'est pas une date", () => {
    expect(parseLivedDays({ livedFrom: "hier", livedTo: null }, GRECE).livedFrom).toBeNull();
    expect(parseLivedDays({ livedFrom: 42, livedTo: null }, GRECE).livedFrom).toBeNull();
    expect(parseLivedDays({}, GRECE)).toEqual({ livedFrom: null, livedTo: null });
  });

  /** Une fin sans début ne situe rien, et afficherait « jusqu'au 30 » seul. */
  it("laisse tomber la fin quand le début manque", () => {
    expect(parseLivedDays({ livedFrom: null, livedTo: "2026-08-30" }, GRECE)).toEqual({
      livedFrom: null,
      livedTo: null,
    });
  });
});

describe("les dates d'une étape", () => {
  it("sont celles que son récit a dites, pas celles de son enregistrement", () => {
    const fields = stepFields(groupOf(story({ livedFrom: "2026-08-28", capturedOn: "2026-09-02" })), undefined);
    expect(fields.livedFromDay).toEqual(day("2026-08-28"));
    // Une journée : pas de fin, et les clients en font une date précise.
    expect(fields.livedToDay).toBeNull();
    // Les dates d'enregistrement, elles, restent ce qu'elles sont.
    expect(fields.startDate.toISOString().slice(0, 10)).toBe("2026-09-02");
  });

  /**
   * « Une étape se raconte en plusieurs fois » (T308) : deux séances qui
   * situent deux journées font une tranche, et c'est la seule façon d'en
   * obtenir une.
   */
  it("s'élargissent quand une seconde séance raconte un autre jour", () => {
    const fields = stepFields(
      groupOf(story({ livedFrom: "2026-08-28" }), story({ livedFrom: "2026-08-30" })),
      undefined,
    );
    expect(fields.livedFromDay).toEqual(day("2026-08-28"));
    expect(fields.livedToDay).toEqual(day("2026-08-30"));
  });

  it("reprennent la tranche qu'un seul récit annonce", () => {
    const fields = stepFields(groupOf(story({ livedFrom: "2026-08-28", livedTo: "2026-08-31" })), undefined);
    expect(fields.livedToDay).toEqual(day("2026-08-31"));
  });

  it("ne font pas une tranche de deux séances sur la même journée", () => {
    const fields = stepFields(
      groupOf(story({ livedFrom: "2026-08-28" }), story({ livedFrom: "2026-08-28" })),
      undefined,
    );
    expect(fields.livedFromDay).toEqual(day("2026-08-28"));
    expect(fields.livedToDay).toBeNull();
  });

  /** Le cas le plus fréquent : personne n'a daté quoi que ce soit. */
  it("restent nulles quand aucun récit ne s'est situé", () => {
    const fields = stepFields(groupOf(story(), story()), undefined);
    expect(fields.livedFromDay).toBeNull();
    expect(fields.livedToDay).toBeNull();
  });

  /** Un seul récit situé suffit : les autres ne l'effacent pas. */
  it("tiennent dès qu'un seul récit s'est situé", () => {
    const fields = stepFields(groupOf(story(), story({ livedFrom: "2026-08-29" })), undefined);
    expect(fields.livedFromDay).toEqual(day("2026-08-29"));
  });
});

describe("la journée du carnet", () => {
  const entry = (overrides: Partial<StructuringEntry>): StructuringEntry => ({
    kind: "audio",
    transcript: "On a marché jusqu'au phare.",
    editedByUser: false,
    title: null,
    funFact: null,
    funFactTitle: null,
    weatherKey: null,
    capturedAt: new Date("2026-09-02T09:00:00Z"),
    photoUrl: null,
    ...overrides,
  });

  /**
   * Deux séances, deux jours d'enregistrement, une seule journée vécue : le
   * carnet en faisait deux pages, datées des jours où l'on avait parlé.
   */
  it("réunit deux séances qui racontent le même jour", () => {
    const groups = groupEntriesByDay([
      entry({ capturedAt: new Date("2026-09-02T09:00:00Z"), livedDay: "2026-08-28" }),
      entry({ capturedAt: new Date("2026-09-03T21:00:00Z"), livedDay: "2026-08-28" }),
    ]);

    expect(groups).toHaveLength(1);
    expect(groups[0]?.date.toISOString()).toBe("2026-08-28T00:00:00.000Z");
  });

  /** L'ordre suit le jour vécu : une journée rattrapée revient à sa place. */
  it("remet une journée rattrapée avant celles qu'on a racontées avant elle", () => {
    const groups = groupEntriesByDay([
      entry({ capturedAt: new Date("2026-09-02T09:00:00Z"), livedDay: "2026-08-30" }),
      entry({ capturedAt: new Date("2026-09-03T09:00:00Z"), livedDay: "2026-08-27" }),
    ]);

    expect(groups.map((group) => group.key)).toEqual(["2026-08-27", "2026-08-30"]);
  });

  /** Sans jour vécu, rien ne change : c'est tout le carnet d'avant. */
  it("retombe sur la date d'enregistrement quand l'étape ne dit rien", () => {
    const groups = groupEntriesByDay([
      entry({ capturedAt: new Date("2026-09-02T09:00:00Z") }),
      entry({ capturedAt: new Date("2026-09-02T20:00:00Z") }),
      entry({ capturedAt: new Date("2026-09-03T08:00:00Z") }),
    ]);

    expect(groups.map((group) => group.key)).toEqual(["2026-09-02", "2026-09-03"]);
  });
});
