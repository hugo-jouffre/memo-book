import { describe, expect, it } from "vitest";
import { EMPTY_CONVERSATION_STATE, type ConversationState } from "./conversation.js";
import {
  GAP_DECLINE_CAP,
  capturedAtFor,
  gapBorders,
  missingDays,
  shouldOfferGap,
  tellingDayOf,
  withGapAccepted,
  withGapDeclined,
  withGapOffered,
} from "./conversationGaps.js";

/** Un minuit UTC, comme Prisma rend une colonne `DATE`. */
const day = (iso: string) => new Date(`${iso}T00:00:00.000Z`);
/** Un souvenir raconté en milieu de journée. */
const told = (iso: string) => new Date(`${iso}T14:00:00.000Z`);

const trip = {
  startDate: day("2026-08-22"),
  endDate: day("2026-09-05"),
  stage: "ongoing",
  narrationPace: "daily",
};

const state = (overrides: Partial<ConversationState> = {}): ConversationState => ({
  ...EMPTY_CONVERSATION_STATE,
  ...overrides,
});

describe("les journées qui manquent au récit", () => {
  it("relève une journée sautée, encadrée par deux journées racontées", () => {
    const gaps = missingDays(
      trip,
      [told("2026-08-23"), told("2026-08-25")],
      new Date("2026-08-26T09:00:00.000Z"),
    );

    expect(gaps).toEqual([{ days: ["2026-08-24"] }]);
  });

  it("ne relève pas la journée d'aujourd'hui, qu'on n'a simplement pas encore racontée", () => {
    // Le cas qui ferait de la suggestion un reproche quotidien : le trou doit
    // être **refermé**. Celui-là appartient à la notification de relance.
    const gaps = missingDays(
      trip,
      [told("2026-08-23"), told("2026-08-24")],
      new Date("2026-08-26T09:00:00.000Z"),
    );

    expect(gaps).toEqual([]);
  });

  it("laisse passer un trou de trois jours : ce n'est plus un oubli", () => {
    const gaps = missingDays(
      trip,
      [told("2026-08-23"), told("2026-08-27")],
      new Date("2026-08-28T09:00:00.000Z"),
    );

    expect(gaps).toEqual([]);
  });

  it("garde un trou de deux jours", () => {
    const gaps = missingDays(
      trip,
      [told("2026-08-23"), told("2026-08-26")],
      new Date("2026-08-27T09:00:00.000Z"),
    );

    expect(gaps).toEqual([{ days: ["2026-08-24", "2026-08-25"] }]);
  });

  it("rend les trous du plus ancien au plus récent", () => {
    const gaps = missingDays(
      trip,
      [told("2026-08-23"), told("2026-08-25"), told("2026-08-27")],
      new Date("2026-08-28T09:00:00.000Z"),
    );

    expect(gaps).toEqual([{ days: ["2026-08-24"] }, { days: ["2026-08-26"] }]);
  });

  it("ne cherche aucun trou sans date de départ : il n'y a pas de fenêtre", () => {
    const gaps = missingDays(
      { startDate: null, endDate: null },
      [told("2026-08-23"), told("2026-08-25")],
      new Date("2026-08-26T09:00:00.000Z"),
    );

    expect(gaps).toEqual([]);
  });

  it("lit la journée dans le fuseau du voyage, pas celui du serveur", () => {
    // 23 h 30 à Tokyo le 24, c'est encore le 24 là-bas — et le 24 à 14 h 30
    // UTC. Lu à Paris, ce serait le même jour ; lu en UTC, aussi. Le test
    // garde l'intention : c'est `localDate` qui tranche, pas `toISOString`.
    const gaps = missingDays(
      trip,
      [told("2026-08-23"), new Date("2026-08-24T14:30:00.000Z"), told("2026-08-26")],
      new Date("2026-08-27T09:00:00.000Z"),
      "Asia/Tokyo",
    );

    expect(gaps).toEqual([{ days: ["2026-08-25"] }]);
  });

  it("nomme les deux journées qui encadrent un trou", () => {
    const borders = gapBorders({ days: ["2026-08-24"] }, [told("2026-08-23"), told("2026-08-25")]);

    expect(borders).toEqual({ before: "2026-08-23", after: "2026-08-25" });
  });
});

describe("la retenue — quand on propose, et quand on se tait", () => {
  const threeDays = [told("2026-08-23"), told("2026-08-25"), told("2026-08-26")];
  const now = new Date("2026-08-27T09:00:00.000Z");

  it("propose le trou le plus ancien jamais proposé", () => {
    expect(shouldOfferGap(trip, state(), threeDays, now)).toEqual({ days: ["2026-08-24"] });
  });

  it("ne repropose jamais une journée déjà proposée", () => {
    const asked = state({ gapAskedFor: ["2026-08-24"] });

    expect(shouldOfferGap(trip, asked, threeDays, now)).toBeNull();
  });

  it("se tait tant qu'une proposition est en vol", () => {
    const flying = state({ gapOffered: { days: ["2026-08-24"], askedAt: now.toISOString() } });

    expect(shouldOfferGap(trip, flying, threeDays, now)).toBeNull();
  });

  it("s'arrête définitivement au deuxième refus", () => {
    const refused = state({ gapDeclines: GAP_DECLINE_CAP });

    expect(shouldOfferGap(trip, refused, threeDays, now)).toBeNull();
  });

  it("laisse passer 48 heures entre deux propositions", () => {
    const recent = state({ gapLastAskedAt: new Date("2026-08-26T20:00:00.000Z").toISOString() });
    const old = state({ gapLastAskedAt: new Date("2026-08-24T20:00:00.000Z").toISOString() });

    expect(shouldOfferGap(trip, recent, threeDays, now)).toBeNull();
    expect(shouldOfferGap(trip, old, threeDays, now)).not.toBeNull();
  });

  it("se tait chez quelqu'un qui raconte à son rythme", () => {
    // Le garde-fou le plus efficace du lot : un trou est la norme à ces
    // rythmes-là, et le relever reviendrait à reprocher son propre réglage.
    for (const narrationPace of ["weekly", "every_three_days", "by_place", "custom", null]) {
      expect(shouldOfferGap({ ...trip, narrationPace }, state(), threeDays, now)).toBeNull();
    }
  });

  it("à « tous les 2 jours », ne relève qu'un trou d'une seule journée", () => {
    const pace = { ...trip, narrationPace: "every_two_days" };
    const twoDays = [told("2026-08-23"), told("2026-08-26"), told("2026-08-27")];

    expect(shouldOfferGap(pace, state(), threeDays, now)).toEqual({ days: ["2026-08-24"] });
    expect(shouldOfferGap(pace, state(), twoDays, new Date("2026-08-28T09:00:00.000Z"))).toBeNull();
  });

  it("ne dit rien sur un voyage passé depuis plus d'une semaine", () => {
    const over = { ...trip, endDate: day("2026-08-27"), stage: "past" };

    expect(shouldOfferGap(over, state(), threeDays, new Date("2026-08-30T09:00:00.000Z"))).not.toBeNull();
    expect(shouldOfferGap(over, state(), threeDays, new Date("2026-09-10T09:00:00.000Z"))).toBeNull();
  });

  it("attend trois journées racontées avant de relever quoi que ce soit", () => {
    const twoTold = [told("2026-08-23"), told("2026-08-25")];

    expect(shouldOfferGap(trip, state(), twoTold, now)).toBeNull();
  });

  it("ne compte pas une journée qui n'a que des photos", () => {
    // `told` ne reçoit que les souvenirs racontés : une photo du 24 n'y entre
    // pas, et la journée reste un trou. C'est l'appelant qui filtre, le test
    // fixe le contrat.
    expect(shouldOfferGap(trip, state(), threeDays, now)).toEqual({ days: ["2026-08-24"] });
  });
});

describe("le registre", () => {
  const now = new Date("2026-08-27T09:00:00.000Z");

  it("compte un refus et retient la journée quand une proposition reste sans suite", () => {
    const flying = withGapOffered(state(), { days: ["2026-08-24"] }, now);
    const after = withGapDeclined(flying);

    expect(after.gapDeclines).toBe(1);
    expect(after.gapOffered).toBeNull();
    expect(after.gapAskedFor).toEqual(["2026-08-24"]);
  });

  it("ne compte rien quand il n'y avait rien en vol", () => {
    expect(withGapDeclined(state())).toEqual(state());
  });

  it("retient la journée acceptée et ouvre le mode", () => {
    const accepted = withGapAccepted(state(), ["2026-08-24", "2026-08-25"], "2026-08-24", now);

    expect(accepted.gapAskedFor).toEqual(["2026-08-24", "2026-08-25"]);
    expect(accepted.gapOffered).toBeNull();
    expect(accepted.tellingDay).toEqual({ day: "2026-08-24", askedAt: now.toISOString() });
  });
});

describe("la journée que le prochain récit datera", () => {
  const now = new Date("2026-08-27T09:00:00.000Z");

  it("tient une demi-heure, pas davantage", () => {
    const fresh = state({ tellingDay: { day: "2026-08-24", askedAt: "2026-08-27T08:50:00.000Z" } });
    const stale = state({ tellingDay: { day: "2026-08-24", askedAt: "2026-08-27T08:10:00.000Z" } });

    expect(tellingDayOf(trip, fresh, now)).toBe("2026-08-24");
    expect(tellingDayOf(trip, stale, now)).toBeNull();
  });

  it("refuse une journée hors du voyage, ou dans le futur", () => {
    const before = state({ tellingDay: { day: "2026-08-01", askedAt: now.toISOString() } });
    const ahead = state({ tellingDay: { day: "2026-09-04", askedAt: now.toISOString() } });

    expect(tellingDayOf(trip, before, now)).toBeNull();
    expect(tellingDayOf(trip, ahead, now)).toBeNull();
  });

  it("date le souvenir à midi, dans le fuseau du voyage", () => {
    // Midi à Paris en août, c'est 10 h UTC — et c'est la seule heure qui
    // retombe sur la bonne journée d'où qu'on relise le souvenir.
    expect(capturedAtFor("2026-08-24", "Europe/Paris").toISOString()).toBe("2026-08-24T10:00:00.000Z");
    expect(capturedAtFor("2026-08-24", "Asia/Tokyo").toISOString()).toBe("2026-08-24T03:00:00.000Z");
  });
});
