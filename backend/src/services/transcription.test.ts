import { describe, expect, it } from "vitest";
import { TRANSCRIPTION_HINT_MAX_CHARS, transcriptionHintFor } from "./transcription.js";

/**
 * L'indice du transcripteur : sans lui, la machine écrit « Famine » pour
 * Fanny et « Cora » pour Chora (vocaux de Maxime, Grèce 2026).
 */
describe("transcriptionHintFor", () => {
  const known = {
    narrator: "Maxime",
    companions: ["Fanny"],
    destination: "Cyclades, Grèce",
    people: ["Maxime", "Fanny"],
    places: ["Paros", "Naxos", "Pied dans le Sable", "Ios"],
  };

  it("souffle qui raconte, avec qui, et les lieux les plus récents d'abord", () => {
    expect(transcriptionHintFor(known)).toBe(
      "Récit de voyage de Maxime et Fanny (Cyclades, Grèce). Lieux : Ios, Pied dans le Sable, Naxos, Paros.",
    );
  });

  it("ne dépasse pas ce que le transcripteur lit, et coupe sur les plus anciens", () => {
    const places = Array.from({ length: 60 }, (_, index) => `Village numéro ${index}`);
    const hint = transcriptionHintFor({ ...known, places }) ?? "";

    expect(hint.length).toBeLessThanOrEqual(TRANSCRIPTION_HINT_MAX_CHARS);
    expect(hint).toContain("Village numéro 59");
    expect(hint).not.toContain("Village numéro 0,");
    expect(hint.endsWith(".")).toBe(true);
  });

  it("ne souffle rien quand le carnet ne sait rien", () => {
    expect(
      transcriptionHintFor({ narrator: null, companions: [], destination: null, people: [], places: [] }),
    ).toBeUndefined();
  });
});
