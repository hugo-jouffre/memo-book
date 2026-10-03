import { describe, expect, it } from "vitest";
import type { Env } from "../env.js";
import { finalTextOf, parseCoherenceSheet } from "../jobs/redact.js";
import { loadWritingRules } from "../lib/templates.js";
import {
  DOUBT_MAX_CHARS,
  EMPTY_COHERENCE_SHEET,
  FakeRedactor,
  buildRedactionPrompt,
  createRedactor,
  parseDoubts,
  withinFunFactLimit,
  type RedactionInput,
} from "./redaction.js";
import { STEP_SIZES } from "./payloadValidator.js";

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
    expect(rules).toContain("Comprendre avant d'écrire");
    expect(rules).toContain("Les erreurs de transcription");
    expect(rules).toContain("fiche de cohérence");
    expect(rules).toContain("en revanche");
    expect(rules).toContain("`doubts`");
  });

  it("tient le même plafond de paragraphe que la validation du carnet", () => {
    // 420 dans le prompt, 379 à la validation : c'est ce désaccord qui coupait
    // des paragraphes au milieu d'une phrase (02/10/2026).
    expect(loadWritingRules()).toContain(`${STEP_SIZES.S.max} caractères`);
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
      voice: ["Phrases courtes, autodérision."],
    };

    expect(parseCoherenceSheet(sheet)).toEqual(sheet);
  });

  it("relit une fiche écrite avant le portrait du narrateur", () => {
    const { voice: _voice, ...older } = { ...EMPTY_COHERENCE_SHEET, people: [{ canonicalName: "Max", notes: "" }] };

    expect(parseCoherenceSheet(older).voice).toEqual([]);
    expect(parseCoherenceSheet({ ...older, voice: ["drôle", 42] }).voice).toEqual(["drôle"]);
  });
});

describe("parseDoubts", () => {
  it("garde les passages tels que transcrits, sans les guillemets du modèle", () => {
    expect(parseDoubts(["« je tarbé »", "  Famine ", "Famine", 3, ""])).toEqual(["je tarbé", "Famine"]);
  });

  it("coupe un passage trop long pour une bulle", () => {
    const [doubt] = parseDoubts(["x".repeat(80)]);

    expect(doubt).toHaveLength(DOUBT_MAX_CHARS);
    expect(doubt?.endsWith("…")).toBe(true);
  });

  it("rend une liste vide pour tout ce qui n'en est pas une", () => {
    expect(parseDoubts(undefined)).toEqual([]);
    expect(parseDoubts("je tarbé")).toEqual([]);
  });
});

/**
 * Le message de la rédaction. Une ligne de contexte qui disparaît ne fait
 * échouer aucun appel : elle fait seulement écrire plus mal. C'est ici qu'on
 * la voit partir.
 */
describe("buildRedactionPrompt", () => {
  const input: RedactionInput = {
    memo: {
      title: "Grèce 2026",
      subtitle: null,
      authors: null,
      theme: null,
      styleKey: null,
      tripContext: [],
      // Le 26 août et le 5 septembre à minuit, heure de Paris.
      startDate: new Date("2026-08-25T22:00:00Z"),
      endDate: new Date("2026-09-04T22:00:00Z"),
      destination: "Naxos",
      narrationPace: "daily",
    },
    narrator: { firstName: "Max", companions: ["Fanny"] },
    entry: {
      transcript: "On a fait la sortie en kayak.",
      capturedAt: new Date("2026-10-01T07:44:53Z"),
      placeLabel: null,
      precisions: [],
      step: { number: 3, placeName: "Naxos", startDate: null, endDate: null },
    },
    coherenceSheet: EMPTY_COHERENCE_SHEET,
    previous: [],
    earlier: { titles: ["Dernier brunch à Paros"], funFacts: ["La Portara est une porte de marbre."] },
  };

  it("dit qui raconte, pour qu'il ne devienne pas son propre compagnon", () => {
    const prompt = buildRedactionPrompt(input);

    expect(prompt).toContain("Le narrateur : Max.");
    expect(prompt).toContain("« Max » à la troisième personne, c'est de lui-même");
    expect(prompt).toContain("Avec lui sur le carnet : Fanny");
  });

  it("donne la date d'envoi pour ce qu'elle est, pas pour le jour raconté", () => {
    const prompt = buildRedactionPrompt(input);

    expect(prompt).toContain("Vocal envoyé le jeudi 1er octobre 2026.");
    expect(prompt).not.toMatch(/^Date : /m);
  });

  it("écrit les jours du voyage comme l'app, pas la veille", () => {
    const prompt = buildRedactionPrompt(input);

    expect(prompt).toContain("Dates du voyage : du 26 août 2026 au 5 septembre 2026");
    expect(prompt).toContain("Rythme de récit choisi : un récit par jour");
    expect(prompt).toContain("Étape n°3 du voyage — Naxos");
  });

  it("montre tout ce que le carnet a déjà employé", () => {
    const prompt = buildRedactionPrompt(input);

    expect(prompt).toContain("« Dernier brunch à Paros »");
    expect(prompt).toContain("- La Portara est une porte de marbre.");
  });

  it("rappelle le plafond de paragraphe de la validation", () => {
    expect(buildRedactionPrompt(input)).toContain(`**${STEP_SIZES.S.max} caractères au plus`);
  });

  it("ne prête pas de prénom à un narrateur inconnu", () => {
    const prompt = buildRedactionPrompt({ ...input, narrator: { firstName: null, companions: [] } });

    expect(prompt).toContain("Le narrateur : prénom inconnu.");
    expect(prompt).not.toContain("Avec lui sur le carnet");
  });
});

describe("withinFunFactLimit", () => {
  it("garde un encart qui tient", () => {
    expect(withinFunFactLimit({ funFact: "Ios revendique la tombe d'Homère.", funFactTitle: "Culture générale" })).toEqual({
      funFact: "Ios revendique la tombe d'Homère.",
      funFactTitle: "Culture générale",
    });
  });

  it("fait sauter un encart trop long plutôt que de casser le carnet", () => {
    expect(withinFunFactLimit({ funFact: "x".repeat(141), funFactTitle: "Fun fact" })).toEqual({
      funFact: null,
      funFactTitle: null,
    });
  });
});

describe("createRedactor", () => {
  it("choisit qui rédige selon sa propre clé", () => {
    const env = (mode: string, live: boolean, key: string) =>
      ({
        PIPELINE_MODE: mode,
        live,
        ANTHROPIC_API_KEY: key,
        ANTHROPIC_REDACTION_MODEL: "claude-opus-5",
      }) as Env;

    // « Personne n'appelle personne » : la seule chose qui coupe Claude.
    expect(createRedactor(env("fake", false, "sk-test")).constructor.name).toBe("FakeRedactor");
    expect(createRedactor(env("auto", true, "")).constructor.name).toBe("FakeRedactor");
    expect(createRedactor(env("auto", true, "sk-test")).constructor.name).toBe("AnthropicRedactor");

    // Le piège de `docs/modeles-ia.md` § 5 : une clé Anthropic valide, mais
    // pas de clé OpenAI, donc `live` faux. La rédaction comprend quand même.
    expect(createRedactor(env("auto", false, "sk-test")).constructor.name).toBe("AnthropicRedactor");
  });
});
