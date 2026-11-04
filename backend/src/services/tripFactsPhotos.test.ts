import { describe, expect, it } from "vitest";
import { groupIntoSteps, type StepPins } from "./tripFacts.js";
import { EMPTY_INSIGHTS } from "./redaction.js";
import { serializeTripStep } from "../routes/appSerializers.js";

/**
 * **La vignette d'une étape** : à quelle étape une photo se range, et comment
 * son adresse se sert. Logique pure — le jumeau qui passe par la base est
 * `test/tripFacts.test.ts`.
 *
 * Écrit le 04/11/2026 pour trancher « les photos ne s'affichent pas dans la
 * liste des étapes » : la chaîne est saine de bout en bout, sauf le cas de la
 * date EXIF, plus bas.
 */

const BASE = "https://api.memo-book.com";
const UUID = "0b3f7c2e-9a41-4d8b-bc10-5e6f7a8b9c0d";

/** Un souvenir, daté à la minute près pour que l'ordre se lise d'un coup d'œil. */
function entry(id: string, kind: "audio" | "text" | "photo", minute: number, stepId: string | null = null) {
  const at = new Date(Date.UTC(2026, 9, 29, 10, minute));
  return {
    id,
    kind,
    capturedAt: at,
    createdAt: at,
    stepId,
    insights: EMPTY_INSIGHTS,
    cdnUrl: null,
    continuesPrevious: false,
  };
}

/** Une étape telle que `GET /v1/trips/:id` la charge, avec ses souvenirs. */
function stepCarrying(entries: { id: string; kind: string; storageKey?: string }[]) {
  return {
    id: "etape-8",
    number: 8,
    memoId: "voyage",
    placeName: "Nikko",
    destinationName: null,
    destinationCountryCode: null,
    startDate: new Date(),
    endDate: new Date(),
    transport: null,
    validatedAt: null,
    photoUrl: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    entries: entries.map((one) => ({
      id: one.id,
      kind: one.kind,
      media: one.storageKey ? { storageKey: one.storageKey, cdnUrl: null } : null,
    })),
  } as never;
}

describe("à quelle étape une photo se range", () => {
  it("une photo envoyée après un récit rejoint son étape", () => {
    const groups = groupIntoSteps([entry("recit", "audio", 0), entry("photo", "photo", 5)]);
    expect(groups).toHaveLength(1);
    expect(groups[0]!.entries.map((one) => one.id)).toEqual(["recit", "photo"]);
  });

  it("une photo épinglée sur une étape choisie la rejoint", () => {
    const pins: StepPins = { stepOf: new Map([["photo", "etape-8"]]), illustrates: new Map() };
    const groups = groupIntoSteps([entry("recit", "audio", 0, "etape-8"), entry("photo", "photo", 5)], pins);
    expect(groups[0]!.entries.map((one) => one.id)).toContain("photo");
  });

  it("des photos sans aucun récit font quand même un groupe", () => {
    const groups = groupIntoSteps([entry("p1", "photo", 0), entry("p2", "photo", 1)]);
    expect(groups).toHaveLength(1);
    expect(groups[0]!.entries).toHaveLength(2);
  });

  /**
   * ⚠️ **Le défaut trouvé le 04/11/2026.** Une photo choisie dans la
   * photothèque porte sa date EXIF — le jour où elle a été *prise*, pas celui
   * du récit qu'on vient d'illustrer. Le rangement par défaut la donne au
   * dernier récit capturé **avant** cette date : elle part dans une étape
   * d'avant, et celle qu'on illustrait reste sans vignette.
   *
   * Le cas ne se produit que si rien ne l'épingle — ni l'étape d'une carte
   * ouverte (`message.stepId`), ni le récit que MEMO venait d'illustrer
   * (`forEntryId`). C'est exactement l'envoi **spontané** de photos.
   *
   * Ce test fige le comportement actuel ; il s'inversera le jour où l'on
   * tranche entre « la date de la photo » et « le moment où on l'envoie ».
   */
  it("une photo plus ancienne que le récit en cours part dans l'étape d'avant", () => {
    const groups = groupIntoSteps([
      entry("recit-nikko", "audio", 0),
      entry("recit-tokyo", "audio", 30),
      entry("photo-prise-a-nikko", "photo", 10),
    ]);
    const nikko = groups.find((group) => group.entries[0]!.id === "recit-nikko")!;
    const tokyo = groups.find((group) => group.entries[0]!.id === "recit-tokyo")!;
    expect(nikko.entries.map((one) => one.id)).toContain("photo-prise-a-nikko");
    expect(tokyo.entries.map((one) => one.id)).not.toContain("photo-prise-a-nikko");
  });

  it("…sauf épinglée sur le récit que MEMO venait d'illustrer", () => {
    const pins: StepPins = { stepOf: new Map(), illustrates: new Map([["photo-prise-a-nikko", "recit-tokyo"]]) };
    const groups = groupIntoSteps(
      [
        entry("recit-nikko", "audio", 0),
        entry("recit-tokyo", "audio", 30),
        entry("photo-prise-a-nikko", "photo", 10),
      ],
      pins,
    );
    const tokyo = groups.find((group) => group.entries[0]!.id === "recit-tokyo")!;
    expect(tokyo.entries.map((one) => one.id)).toContain("photo-prise-a-nikko");
  });
});

describe("l'adresse de la vignette", () => {
  it("se sert sans CDN, par la route publique des photos du chat", () => {
    const step = stepCarrying([
      { id: "recit", kind: "audio" },
      { id: "photo", kind: "photo", storageKey: `photo/${UUID}.jpg` },
    ]);
    expect(serializeTripStep(step, [], BASE).photoUrl).toBe(`${BASE}/v1/trip-photos/${UUID}.jpg`);
  });

  it("une étape sans entrée photo n'a pas de vignette", () => {
    expect(serializeTripStep(stepCarrying([{ id: "recit", kind: "audio" }]), [], BASE).photoUrl).toBeNull();
  });

  it("sans racine publique, aucune vignette", () => {
    const step = stepCarrying([{ id: "photo", kind: "photo", storageKey: `photo/${UUID}.jpg` }]);
    expect(serializeTripStep(step, []).photoUrl).toBeNull();
  });
});
