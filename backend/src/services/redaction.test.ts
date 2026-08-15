import { describe, expect, it } from "vitest";
import { finalTextOf, parseCoherenceSheet } from "../jobs/redact.js";
import { loadWritingRules } from "../lib/templates.js";
import { EMPTY_COHERENCE_SHEET, FakeRedactor } from "./redaction.js";

/**
 * Le prompt système de la rédaction est le fichier de règles du dépôt. Si le
 * chemin casse — dossier déplacé, back-end lancé hors du monorepo — l'agent
 * rédigerait sans aucune consigne, et personne ne s'en apercevrait avant de
 * lire le carnet imprimé.
 */
describe("loadWritingRules", () => {
  it("charge agents/agent-transcription.md", () => {
    const rules = loadWritingRules();

    expect(rules).toContain("Agent Transcription");
    expect(rules.length).toBeGreaterThan(2000);
  });

  it("porte les règles sur lesquelles le carnet est jugé", () => {
    const rules = loadWritingRules();

    // Une par grande section : leur disparition silencieuse est exactement ce
    // qu'on veut voir échouer ici.
    expect(rules).toContain("fiche de cohérence");
    expect(rules).toContain("en revanche");
    expect(rules).toContain("global_stats");
  });
});

describe("FakeRedactor", () => {
  const baseInput = {
    memo: {
      title: "Colombie",
      subtitle: null,
      authors: "Claire et Augustin",
      theme: "voyage",
      styleKey: null,
    },
    entry: {
      transcript: "",
      capturedAt: new Date("2026-04-12T09:00:00Z"),
      placeLabel: "Bogotá",
    },
    coherenceSheet: EMPTY_COHERENCE_SHEET,
    previous: [],
  };

  it("retire les tics d'oral sans toucher au reste", async () => {
    const result = await new FakeRedactor().redact({
      ...baseInput,
      entry: {
        ...baseInput.entry,
        transcript: "euh du coup on est arrivés à Bogotá, en fait la ville est perchée.",
      },
    });

    expect(result.text).toBe("On est arrivés à Bogotá, la ville est perchée.");
  });

  it("ne perd pas la fiche de cohérence qu'on lui confie", async () => {
    const sheet = {
      ...EMPTY_COHERENCE_SHEET,
      people: [{ canonicalName: "Maÿlis", notes: "sa sœur" }],
    };

    const result = await new FakeRedactor().redact({
      ...baseInput,
      entry: { ...baseInput.entry, transcript: "Une journée tranquille." },
      coherenceSheet: sheet,
    });

    expect(result.coherenceSheet).toEqual(sheet);
  });

  it("respecte la limite de 420 caractères par paragraphe", async () => {
    const result = await new FakeRedactor().redact({
      ...baseInput,
      entry: { ...baseInput.entry, transcript: "Bogotá, ".repeat(200) },
    });

    expect(result.text.length).toBeLessThanOrEqual(420);
  });
});

/**
 * La hiérarchie des textes est la règle produit la plus importante du
 * pipeline : ce que l'utilisateur a corrigé au clavier gagne toujours.
 */
describe("finalTextOf", () => {
  it("préfère la correction manuelle au texte rédigé", () => {
    expect(
      finalTextOf({
        editedText: "Ma version.",
        redactedText: "La version du modèle.",
        transcript: "euh la version brute",
      }),
    ).toBe("Ma version.");
  });

  it("retombe sur le texte rédigé sans correction", () => {
    expect(
      finalTextOf({
        editedText: null,
        redactedText: "La version du modèle.",
        transcript: "euh la version brute",
      }),
    ).toBe("La version du modèle.");
  });

  it("retombe sur la transcription quand la rédaction a échoué", () => {
    expect(
      finalTextOf({ editedText: null, redactedText: null, transcript: "la version brute" }),
    ).toBe("la version brute");
  });

  it("renvoie null pour une entrée sans aucun texte", () => {
    expect(finalTextOf({ editedText: null, redactedText: null, transcript: null })).toBeNull();
  });
});

describe("parseCoherenceSheet", () => {
  it("repart d'une fiche vide plutôt que de faire échouer un souvenir", () => {
    expect(parseCoherenceSheet(null)).toEqual(EMPTY_COHERENCE_SHEET);
    expect(parseCoherenceSheet("pas un objet")).toEqual(EMPTY_COHERENCE_SHEET);
    expect(parseCoherenceSheet({ people: "cassé" })).toEqual(EMPTY_COHERENCE_SHEET);
  });

  it("conserve une fiche valide", () => {
    const sheet = {
      people: [{ canonicalName: "Paul", notes: "notre hôte" }],
      places: [],
      lexicon: [{ term: "le van", notes: "toujours « le van »" }],
      narration: { person: "on", tense: "passé composé" },
      figures: [{ label: "distance", value: "environ 12 500 km" }],
    };

    expect(parseCoherenceSheet(sheet)).toEqual(sheet);
  });
});
