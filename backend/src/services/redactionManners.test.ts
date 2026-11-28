import { describe, expect, it } from "vitest";

import {
  cleanNotes,
  mannerBlock,
  mannerInstruction,
  mannerOf,
  REDACTION_MANNER_KEYS,
  REDACTION_NOTES_MAX,
} from "./redactionManners.js";

describe("la manière d'être rédigé (T292)", () => {
  it("prend la manière par défaut quand personne n'a choisi", () => {
    expect(mannerOf(null)).toBe("spoken");
    expect(mannerOf(undefined)).toBe("spoken");
    expect(mannerOf("")).toBe("spoken");
  });

  it("prend la manière par défaut sur une clé qu'elle ne connaît pas", () => {
    // Une version future de l'app peut écrire une clé que ce serveur ignore :
    // elle doit rédiger par défaut, pas faire échouer la rédaction.
    expect(mannerOf("ecrit-en-vers")).toBe("spoken");
  });

  it("n'injecte rien pour la manière par défaut", () => {
    // Le cœur du dispositif : un carnet qui n'a pas touché au réglage est
    // rédigé exactement comme avant T292.
    expect(mannerInstruction("spoken")).toBeNull();
    expect(mannerBlock({ manner: null, notes: null })).toBeNull();
    expect(mannerBlock({ manner: "spoken", notes: "   " })).toBeNull();
  });

  it("charge la consigne des deux autres manières, après « ## Consigne »", () => {
    for (const manner of ["literary", "factual"] as const) {
      const instruction = mannerInstruction(manner);
      expect(instruction).not.toBeNull();
      expect(instruction).toContain("Écris cette étape");
      // Le titre de la fiche est un repère pour nous : `mannerBlock` pose le
      // sien, et deux titres de suite pour une section n'en font pas une plus
      // claire.
      expect(instruction).not.toContain("## Consigne");
      // La documentation de la fiche ne part pas au modèle.
      expect(instruction).not.toContain("chargé et inséré tel quel");
      expect(instruction).not.toContain("Ce que le voyageur lit dans l'app");
    }
  });

  it("pose la manière sous un titre que le prompt sait lire", () => {
    const block = mannerBlock({ manner: "factual", notes: null });
    expect(block).toContain("## Comment écrire cette étape");
    expect(block).toContain("journal factuel");
  });

  it("met les indications du voyageur après la manière, et dit leur rang", () => {
    const block = mannerBlock({ manner: "literary", notes: "Appelle-moi Max." }) ?? "";
    const manner = block.indexOf("récit littéraire");
    const notes = block.indexOf("## Ce que le voyageur demande en plus");
    expect(manner).toBeGreaterThanOrEqual(0);
    expect(notes).toBeGreaterThan(manner);
    // Sans cette phrase, « invente ce qui manque » contournerait les règles.
    expect(block).toContain("les règles l'emportent");
  });

  it("sert les indications seules quand la manière est celle par défaut", () => {
    const block = mannerBlock({ manner: null, notes: "Tutoie-moi." }) ?? "";
    expect(block).toContain("Tutoie-moi.");
    expect(block).not.toContain("Écris cette étape");
  });

  it("coupe des indications trop longues plutôt que de les refuser", () => {
    const long = "a".repeat(REDACTION_NOTES_MAX + 50);
    expect(cleanNotes(long)).toHaveLength(REDACTION_NOTES_MAX);
  });

  it("traite des indications vides comme une absence", () => {
    expect(cleanNotes("   \n  ")).toBeNull();
    expect(cleanNotes(null)).toBeNull();
  });

  it("annonce ses trois manières, dans l'ordre où l'app les propose", () => {
    expect(REDACTION_MANNER_KEYS).toEqual(["spoken", "literary", "factual"]);
  });
});
