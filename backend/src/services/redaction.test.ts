import { describe, expect, it } from "vitest";
import type { Env } from "../env.js";
import { finalTextOf, parseCoherenceSheet, quizHistoryOf } from "../jobs/redact.js";
import { loadWritingRules } from "../lib/templates.js";
import {
  DOUBT_MAX_CHARS,
  EMPTY_COHERENCE_SHEET,
  FakeRedactor,
  MAX_MOMENTS,
  buildRedactionPrompt,
  createRedactor,
  parseDoubts,
  parseMoments,
  withinFunFactLimit,
  withinQuizLimits,
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

/**
 * **Les moments d'un récit**, relus de façon défensive (Hugo, 28/10/2026).
 * Un modèle peut rendre n'importe quoi, et une proposition douteuse
 * découperait un souvenir sur des mots que personne n'a dits.
 */
describe("parseMoments", () => {
  const transcript =
    "Jeudi on a marché jusqu'au Colisée, il y avait un monde fou. " +
    "Le lendemain on a pris la route du sud, direction Naples.";

  const moments = [
    { title: "Le Colisée bondé", transcript: "Jeudi on a marché jusqu'au Colisée, il y avait un monde fou." },
    { title: "La route du sud", transcript: "Le lendemain on a pris la route du sud, direction Naples." },
  ];

  it("garde une proposition qui cite la transcription", () => {
    expect(parseMoments(moments, transcript)).toEqual(moments);
  });

  it("refuse une part que personne n'a dite", () => {
    const invented = [moments[0], { title: "Inventé", transcript: "On a dormi sur la plage de Positano." }];
    expect(parseMoments(invented, transcript)).toEqual([]);
  });

  it("tolère la ponctuation et les espaces d'une citation recollée", () => {
    const requoted = [
      { title: moments[0]!.title, transcript: "jeudi on a marché jusqu'au colisée il y avait un monde fou" },
      { title: moments[1]!.title, transcript: moments[1]!.transcript },
    ];
    expect(parseMoments(requoted, transcript)).toHaveLength(2);
  });

  it("refuse une seule part : découper en un, c'est ne pas découper", () => {
    expect(parseMoments([moments[0]], transcript)).toEqual([]);
  });

  it("refuse au-delà du maximum", () => {
    const tooMany = Array.from({ length: MAX_MOMENTS + 1 }, () => moments[0]);
    expect(parseMoments(tooMany, transcript)).toEqual([]);
  });

  it("refuse une part sans titre ou sans texte", () => {
    expect(parseMoments([{ title: "", transcript: moments[0]!.transcript }, moments[1]], transcript)).toEqual([]);
    expect(parseMoments([{ title: "Un titre", transcript: "  " }, moments[1]], transcript)).toEqual([]);
  });

  it("refuse tout sans transcription à vérifier", () => {
    expect(parseMoments(moments, null)).toEqual([]);
    expect(parseMoments(moments, "")).toEqual([]);
  });

  it("refuse ce qui n'est pas une liste d'objets", () => {
    expect(parseMoments(null, transcript)).toEqual([]);
    expect(parseMoments("deux moments", transcript)).toEqual([]);
    expect(parseMoments([moments[0], "le second"], transcript)).toEqual([]);
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

  it("règle la densité du récit sur le nombre de pages cible", () => {
    // 26 août – 5 septembre : 11 jours, donc un palier « Par défaut » à 10
    // pages, borné à 30 ; 20 pages, c'est un récit compact.
    const compact = buildRedactionPrompt({ ...input, memo: { ...input.memo, targetPageCount: 20 } });
    expect(compact).toContain("Nombre de pages cible du carnet : 20 (entre 16 et 25)");
    expect(compact).toContain("récit **compact**");

    const detailed = buildRedactionPrompt({ ...input, memo: { ...input.memo, targetPageCount: 40 } });
    expect(detailed).toContain("récit **détaillé**");
    expect(buildRedactionPrompt(input)).not.toContain("Nombre de pages cible");
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

describe("quiz", () => {
  const quiz = { question: "Qui a renversé le café ?", choices: ["Clara", "Hugo", "Le serveur"], answerIndex: 1 };

  it("garde un quiz bien formé", () => {
    expect(withinQuizLimits({ ...quiz, question: "  Qui a renversé   le café ? " })).toEqual(quiz);
  });

  it("fait sauter un quiz mal formé plutôt que de le réparer", () => {
    expect(withinQuizLimits(null)).toBeNull();
    expect(withinQuizLimits({ ...quiz, answerIndex: 3 })).toBeNull();
    expect(withinQuizLimits({ ...quiz, answerIndex: 0.5 })).toBeNull();
    expect(withinQuizLimits({ ...quiz, choices: ["Hugo"], answerIndex: 0 })).toBeNull();
    expect(withinQuizLimits({ ...quiz, choices: ["Hugo", "hugo", "Clara"] })).toBeNull();
    expect(withinQuizLimits({ ...quiz, choices: ["a", "b", "c", "d", "e"] })).toBeNull();
    expect(withinQuizLimits({ ...quiz, question: "x".repeat(121) })).toBeNull();
    expect(withinQuizLimits({ ...quiz, choices: ["x".repeat(41), "b", "c"] })).toBeNull();
  });

  it("compte les étapes depuis le dernier quiz, et n'en veut qu'un par étape", () => {
    const row = (id: string, stepId: string | null, quizQuestion: string | null = null) => ({ id, stepId, quizQuestion });
    expect(quizHistoryOf([], row("e1", "s1"))).toEqual({ asked: [], stepsSinceLast: null, thisStepHasOne: false });

    const earlier = [row("e1", "s1", "Q1 ?"), row("e2", "s1"), row("e3", "s2"), row("e4", null)];
    expect(quizHistoryOf(earlier, row("e5", "s3"))).toEqual({ asked: ["Q1 ?"], stepsSinceLast: 3, thisStepHasOne: false });
    expect(quizHistoryOf(earlier, row("e5", "s1"))).toMatchObject({ stepsSinceLast: 0, thisStepHasOne: true });
  });

  it("dit à l'écrivain où en est le carnet de ses quiz", () => {
    const base: RedactionInput = {
      memo: { title: "Carnet", subtitle: null, authors: null, theme: null, styleKey: null, tripContext: [], startDate: null, endDate: null, destination: null, narrationPace: null },
      entry: { transcript: "On a fait du kayak.", capturedAt: new Date("2026-10-01T07:44:53Z"), placeLabel: null, precisions: [], step: null },
      coherenceSheet: EMPTY_COHERENCE_SHEET,
      previous: [],
    };
    expect(buildRedactionPrompt(base)).toContain("Aucun quiz encore dans le carnet.");
    const proche = buildRedactionPrompt({ ...base, quizzes: { asked: ["Q1 ?"], stepsSinceLast: 1, thisStepHasOne: false } });
    expect(proche).toContain("trop près, `quiz` est `null`");
    expect(proche).toContain("- Q1 ?");
    expect(buildRedactionPrompt({ ...base, quizzes: { asked: [], stepsSinceLast: 3, thisStepHasOne: false } })).toContain(
      "Le dernier quiz remonte à 3 étapes.",
    );
    expect(buildRedactionPrompt({ ...base, quizzes: { asked: ["Q1 ?"], stepsSinceLast: 0, thisStepHasOne: true } })).toContain(
      "porte déjà son quiz",
    );
  });

  it("le faux rédacteur n'en pose pas", async () => {
    const result = await new FakeRedactor().redact({
      memo: { title: "Carnet", subtitle: null, authors: null, theme: null, styleKey: null, tripContext: [], startDate: null, endDate: null, destination: null, narrationPace: null },
      entry: { transcript: "On a fait du kayak.", capturedAt: new Date(), placeLabel: null, precisions: [], step: null },
      coherenceSheet: EMPTY_COHERENCE_SHEET,
      previous: [],
    });
    expect(result.quiz).toBeNull();
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
