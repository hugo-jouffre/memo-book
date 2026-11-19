import { describe, expect, it } from "vitest";
import { momentInstants } from "./entrySplit.js";
import { PART_OF_DAY_HOURS, type RedactedMoment } from "./redaction.js";
import { localDate } from "./localCalendar.js";

/**
 * **L'ordre d'un récit découpé** (T279).
 *
 * Le découpage lui-même est exercé de bout en bout par `conversation.test.ts`.
 * Ici, seule la question que le ticket pose : quand chaque part a-t-elle été
 * vécue, et non dans quel ordre a-t-elle été racontée.
 */
const PARIS = "Europe/Paris";

/** Une part de récit, aussi nue que possible. */
function part(titre: string, quand: Partial<RedactedMoment> = {}): RedactedMoment {
  return { title: titre, transcript: titre, day: null, partOfDay: null, ...quand };
}

describe("momentInstants", () => {
  // 14 h 30 à Paris, le 9 avril — l'heure d'envoi d'un vocal.
  const envoi = new Date("2026-04-09T12:30:00Z");

  it("sans rien de dit, garde l'ordre du récit à la seconde près", () => {
    const dates = momentInstants([part("un"), part("deux"), part("trois")], envoi, PARIS);
    // Le comportement d'avant : la première part garde la date du souvenir.
    expect(dates.map((d) => d.toISOString())).toEqual([
      "2026-04-09T12:30:00.000Z",
      "2026-04-09T12:30:01.000Z",
      "2026-04-09T12:30:02.000Z",
    ]);
  });

  it("remet dans l'ordre un récit qui revient en arrière", () => {
    // « Hier on a fait ça… ah, et avant-hier… » : le désordre du ticket.
    const dates = momentInstants(
      [part("hier", { day: "2026-04-08" }), part("avant-hier", { day: "2026-04-07" })],
      envoi,
      PARIS,
    );
    expect(dates[0]!.getTime()).toBeGreaterThan(dates[1]!.getTime());
    expect(dates.map((d) => localDate(d, PARIS))).toEqual(["2026-04-08", "2026-04-07"]);
  });

  it("pose une part datée à midi, l'heure des souvenirs racontés après coup", () => {
    const [date] = momentInstants([part("la veille", { day: "2026-04-08" }), part("après")], envoi, PARIS);
    // Midi à Paris en avril : UTC+2.
    expect(date!.toISOString()).toBe("2026-04-08T10:00:00.000Z");
  });

  it("donne à un moment de journée son heure, sans qu'un jour soit dit", () => {
    const dates = momentInstants([part("au réveil", { partOfDay: "matin" }), part("le soir", { partOfDay: "soir" })], envoi, PARIS);
    const heures = dates.map((d) => Number(d.toISOString().slice(11, 13)));
    // 9 h et 20 h à Paris, décalés d'UTC+2, plus la seconde de rang.
    expect(heures).toEqual([PART_OF_DAY_HOURS.matin - 2, PART_OF_DAY_HOURS.soir - 2]);
    // Faute de jour dit, les deux restent sur la journée du vocal.
    expect(dates.map((d) => localDate(d, PARIS))).toEqual(["2026-04-09", "2026-04-09"]);
  });

  it("garde le jour de la part précédente pour « le matin… puis le soir »", () => {
    const dates = momentInstants(
      [part("la veille au matin", { day: "2026-04-08", partOfDay: "matin" }), part("et le soir", { partOfDay: "soir" })],
      envoi,
      PARIS,
    );
    expect(dates.map((d) => localDate(d, PARIS))).toEqual(["2026-04-08", "2026-04-08"]);
    expect(dates[1]!.getTime()).toBeGreaterThan(dates[0]!.getTime());
  });

  it("accroche une part muette à la dernière datée, et non au vocal", () => {
    const dates = momentInstants(
      [part("hier", { day: "2026-04-08" }), part("et puis ça"), part("et ça encore")],
      envoi,
      PARIS,
    );
    expect(dates.map((d) => localDate(d, PARIS))).toEqual(["2026-04-08", "2026-04-08", "2026-04-08"]);
    expect(dates[0]!.getTime()).toBeLessThan(dates[1]!.getTime());
    expect(dates[1]!.getTime()).toBeLessThan(dates[2]!.getTime());
  });

  it("sépare deux parts qui disent le même matin", () => {
    const matin = { day: "2026-04-08", partOfDay: "matin" } as const;
    const dates = momentInstants([part("d'abord", matin), part("ensuite", matin)], envoi, PARIS);
    // Même heure dite : c'est le rang dans le récit qui tranche, et rien
    // d'autre ne le ferait — `capturedAt` est ce qui range le carnet.
    expect(dates[1]!.getTime() - dates[0]!.getTime()).toBe(1_000);
  });

  it("suit le fuseau du voyage, pas celui du serveur", () => {
    const [tokyo] = momentInstants([part("hier", { day: "2026-04-08" }), part("après")], envoi, "Asia/Tokyo");
    // Midi à Tokyo : UTC+9.
    expect(tokyo!.toISOString()).toBe("2026-04-08T03:00:00.000Z");
  });
});
