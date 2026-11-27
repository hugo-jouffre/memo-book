import { describe, expect, it } from "vitest";
import { EMPTY_INSIGHTS } from "../services/redaction.js";
import { livedDaysOf } from "../services/livedDays.js";
import { stepFields, type StepGroup } from "../services/tripFacts.js";

/** Un souvenir tel que le calcul des étapes le lit — `FactEntry`, qui ne s'exporte pas. */
type FactEntry = StepGroup["entries"][number];
import { changesTripFacts, handWrittenFields } from "./entries.js";

/**
 * **Les dates et le lieu qu'on fixe à la main** (T288, Hugo — « l'appui long
 * sur un message de MEMO ouvre ses gestes à lui : […] changer les dates
 * (déduites automatiquement), changer le nom du lieu »).
 *
 * La règle est partout la même : la main passe devant la machine, et `null`
 * lui rend la parole. Ce qui est écrit à la main vit **à côté** de ce que la
 * rédaction a compris, jamais à sa place — une relance la réécrit, elle, et ne
 * touche pas à la correction.
 */

const day = (iso: string) => new Date(`${iso}T00:00:00Z`);

describe("ce que la main fixe", () => {
  it("pose le jour dit, et lui seul", () => {
    expect(handWrittenFields({ livedFrom: "2026-11-14" })).toEqual({
      pinnedLivedFromDay: day("2026-11-14"),
      pinnedLivedToDay: null,
    });
  });

  it("pose une période quand la fin est après le départ", () => {
    expect(handWrittenFields({ livedFrom: "2026-11-14", livedTo: "2026-11-16" })).toEqual({
      pinnedLivedFromDay: day("2026-11-14"),
      pinnedLivedToDay: day("2026-11-16"),
    });
  });

  /** Deux bouts le même jour ne font pas une période — la règle de T308. */
  it("ne fait pas une période d'une seule journée", () => {
    expect(handWrittenFields({ livedFrom: "2026-11-14", livedTo: "2026-11-14" })).toEqual({
      pinnedLivedFromDay: day("2026-11-14"),
      pinnedLivedToDay: null,
    });
  });

  it("laisse tomber une fin antérieure au départ", () => {
    expect(handWrittenFields({ livedFrom: "2026-11-14", livedTo: "2026-11-02" })).toEqual({
      pinnedLivedFromDay: day("2026-11-14"),
      pinnedLivedToDay: null,
    });
  });

  /**
   * ⚠️ **Corriger le départ seul efface la fin.** Sans ça, « en fait c'était
   * le 12 » sur une fiche que le modèle avait datée « du 10 au 15 » donnerait
   * « du 12 au 15 » — une période que personne n'a dite.
   */
  it("efface la fin quand la main ne redonne qu'un départ", () => {
    expect(handWrittenFields({ livedFrom: "2026-11-12" }).pinnedLivedToDay).toBeNull();
  });

  it("rend la parole à la rédaction sur un null", () => {
    expect(handWrittenFields({ livedFrom: null })).toEqual({
      pinnedLivedFromDay: null,
      pinnedLivedToDay: null,
    });
  });

  it("garde le nom du lieu, sans ses espaces", () => {
    expect(handWrittenFields({ placeName: "  Naxos " })).toEqual({ pinnedPlaceName: "Naxos" });
  });

  /** Un champ vidé au clavier, c'est « reviens au lieu deviné ». */
  it("lit un nom vide comme un retour au lieu deviné", () => {
    expect(handWrittenFields({ placeName: "   " })).toEqual({ pinnedPlaceName: null });
  });

  it("ne touche à rien quand le corps ne parle que du texte", () => {
    expect(handWrittenFields({ editedText: "un texte corrigé" })).toEqual({});
    expect(changesTripFacts({ editedText: "un texte corrigé" })).toBe(false);
  });

  it("demande un recalcul dès qu'une date ou un lieu bouge", () => {
    expect(changesTripFacts({ livedFrom: "2026-11-14" })).toBe(true);
    expect(changesTripFacts({ placeName: null })).toBe(true);
  });
});

describe("les jours qu'un souvenir raconte", () => {
  it("sont ceux de la main quand elle a parlé", () => {
    expect(
      livedDaysOf({
        livedFromDay: day("2026-11-01"),
        livedToDay: day("2026-11-03"),
        pinnedLivedFromDay: day("2026-11-14"),
        pinnedLivedToDay: null,
      }),
    ).toEqual({ from: day("2026-11-14"), to: null });
  });

  it("sont ceux de la rédaction sinon", () => {
    expect(
      livedDaysOf({
        livedFromDay: day("2026-11-01"),
        livedToDay: day("2026-11-03"),
        pinnedLivedFromDay: null,
        pinnedLivedToDay: null,
      }),
    ).toEqual({ from: day("2026-11-01"), to: day("2026-11-03") });
  });
});

const story = (id: string, options: { place?: string; hand?: string } = {}): FactEntry => ({
  id,
  kind: "audio",
  capturedAt: day("2026-11-14"),
  createdAt: day("2026-11-14"),
  stepId: null,
  insights: { ...EMPTY_INSIGHTS, ...(options.place ? { currentPlace: options.place } : {}) },
  cdnUrl: null,
  continuesPrevious: false,
  pinnedStepId: null,
  capturedPlaceName: null,
  pinnedPlaceName: options.hand ?? null,
  livedFromDay: null,
  livedToDay: null,
});

const groupOf = (...entries: FactEntry[]): StepGroup => ({
  place: entries[0]?.insights.currentPlace ?? null,
  entries,
  stepId: null,
  pinned: false,
});

describe("le nom d'une étape", () => {
  it("est celui que la main a écrit, et non celui que le récit dit", () => {
    const group = groupOf(story("a", { place: "Naxos", hand: "Apollonas" }));
    expect(stepFields(group, undefined).placeName).toBe("Apollonas");
  });

  it("reste celui du récit quand aucune main n'a écrit", () => {
    expect(stepFields(groupOf(story("a", { place: "Naxos" })), undefined).placeName).toBe("Naxos");
  });

  /** Deux fiches renommées, c'est le nom le plus fréquent — pas le dernier. */
  it("prend le nom le plus fréquent quand deux souvenirs en portent un", () => {
    const group = groupOf(
      story("a", { place: "Naxos", hand: "Apollonas" }),
      story("b", { place: "Naxos", hand: "Apollonas" }),
      story("c", { place: "Naxos", hand: "Chora" }),
    );
    expect(stepFields(group, undefined).placeName).toBe("Apollonas");
  });
});
