import { describe, expect, it } from "vitest";
import { groupIntoSteps } from "./tripFacts.js";
import { EMPTY_INSIGHTS } from "./redaction.js";

/**
 * **Le découpage des souvenirs en étapes** — ce que l'accueil du voyage
 * montre en cartes, et ce que le fil compte quand MEMO dit « ton carnet
 * compte une étape de plus ».
 *
 * La règle de base est **un récit, une étape** (Hugo, 12/10/2026). Celle du
 * 28/10/2026 la nuance : un récit qui en prolonge un autre le rejoint au lieu
 * d'ouvrir une étape — « 1 message n'est pas toujours égal à 1 étape ».
 *
 * Fonction pure : ces tests ne touchent pas la base.
 */

let clock = 0;

/** Un souvenir raconté, dans l'ordre où il a été vécu. */
function story(
  id: string,
  options: { continues?: boolean; place?: string; pinnedStepId?: string; stepId?: string } = {},
) {
  clock += 1;
  const at = new Date(Date.UTC(2026, 0, 1, clock));
  return {
    id,
    kind: "audio" as const,
    capturedAt: at,
    createdAt: at,
    stepId: options.stepId ?? null,
    insights: { ...EMPTY_INSIGHTS, ...(options.place ? { currentPlace: options.place } : {}) },
    cdnUrl: null,
    continuesPrevious: options.continues ?? false,
    pinnedStepId: options.pinnedStepId ?? null,
  };
}

/** Une photo, prise après les récits déjà posés. */
function photo(id: string) {
  clock += 1;
  const at = new Date(Date.UTC(2026, 0, 1, clock));
  return {
    id,
    kind: "photo" as const,
    capturedAt: at,
    createdAt: at,
    stepId: null,
    insights: EMPTY_INSIGHTS,
    cdnUrl: null,
    continuesPrevious: false,
    pinnedStepId: null,
  };
}

/** Les identifiants, étape par étape. */
const shape = (groups: ReturnType<typeof groupIntoSteps>) =>
  groups.map((group) => group.entries.map((entry) => entry.id));

describe("un récit, une étape", () => {
  it("chaque récit ouvre la sienne", () => {
    expect(shape(groupIntoSteps([story("a"), story("b"), story("c")]))).toEqual([["a"], ["b"], ["c"]]);
  });

  it("la photo rejoint le dernier récit vécu avant elle", () => {
    expect(shape(groupIntoSteps([story("a"), story("b"), photo("p")]))).toEqual([["a"], ["b", "p"]]);
  });
});

describe("sauf quand un récit prolonge le précédent (28/10/2026)", () => {
  it("il le rejoint au lieu d'ouvrir une étape", () => {
    const groups = groupIntoSteps([story("matin"), story("soir", { continues: true })]);
    expect(shape(groups)).toEqual([["matin", "soir"]]);
  });

  it("trois récits qui se suivent ne font qu'une étape", () => {
    const groups = groupIntoSteps([
      story("un"),
      story("deux", { continues: true }),
      story("trois", { continues: true }),
    ]);
    expect(shape(groups)).toEqual([["un", "deux", "trois"]]);
  });

  it("et le suivant, qui ne prolonge rien, en rouvre une", () => {
    const groups = groupIntoSteps([
      story("un"),
      story("deux", { continues: true }),
      story("lendemain"),
    ]);
    expect(shape(groups)).toEqual([["un", "deux"], ["lendemain"]]);
  });

  /** Un premier récit n'a rien à prolonger : il ouvre, quoi qu'il dise. */
  it("le premier récit ouvre l'étape, même marqué comme une suite", () => {
    expect(shape(groupIntoSteps([story("seul", { continues: true })]))).toEqual([["seul"]]);
  });

  it("l'étape garde le lieu du récit qui l'a ouverte", () => {
    const groups = groupIntoSteps([
      story("un", { place: "Trastevere" }),
      story("deux", { continues: true, place: "Monti" }),
    ]);
    expect(groups[0]?.place).toBe("Trastevere");
  });

  it("une photo rejoint l'étape réunie, pas une étape à elle", () => {
    const groups = groupIntoSteps([story("un"), story("deux", { continues: true }), photo("p")]);
    expect(shape(groups)).toEqual([["un", "deux", "p"]]);
  });
});

/**
 * **Un récit déplacé à la main** — « Déplacer dans une autre étape » (T270).
 *
 * `entries.pinnedStepId` passe devant tout le reste : la date, le lieu, et
 * « ça prolonge le précédent ». Sans ça, le découpage rendrait le récit à son
 * étape d'origine au premier recalcul, **sans rien dire** — c'est pour ça que
 * la première moitié de T270 ne déplaçait que des photos.
 */
describe("un récit déplacé à la main", () => {
  it("rejoint le groupe de l'étape où on l'a mis", () => {
    const cible = story("cible", { stepId: "etape-2" });
    const groups = groupIntoSteps([story("un"), cible, story("venu", { pinnedStepId: "etape-2" })]);

    expect(shape(groups)).toEqual([["un"], ["cible", "venu"]]);
  });

  it("n'ouvre pas son étape à lui, même s'il a été vécu ailleurs", () => {
    const cible = story("cible", { stepId: "etape-2" });
    // Le récit déplacé est le **premier** vécu : sans l'épingle, il ouvrirait
    // la première étape.
    const groups = groupIntoSteps([story("venu", { pinnedStepId: "etape-2" }), cible]);

    expect(shape(groups)).toEqual([["cible", "venu"]]);
  });

  it("ouvre l'étape visée quand plus aucun récit ne la porte", () => {
    // L'étape d'arrivée n'a que des photos : le récit qui arrive l'ouvre au
    // lieu de disparaître.
    const groups = groupIntoSteps([story("ailleurs"), story("venu", { pinnedStepId: "etape-photos" })]);

    expect(shape(groups)).toEqual([["ailleurs"], ["venu"]]);
    expect(groups[1]?.stepId).toBe("etape-photos");
  });

  it("l'épingle passe devant « ça prolonge le précédent »", () => {
    const cible = story("cible", { stepId: "etape-2" });
    const groups = groupIntoSteps([
      story("un"),
      cible,
      story("venu", { continues: true, pinnedStepId: "etape-2" }),
    ]);

    expect(shape(groups)).toEqual([["un"], ["cible", "venu"]]);
  });
});
