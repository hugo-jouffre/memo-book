import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import pino from "pino";
import {
  AnthropicRedactor,
  EMPTY_COHERENCE_SHEET,
  RELEVE_SCHEMA,
  mergeCoherenceSheet,
  type CoherenceAdditions,
  type CoherenceSheet,
  type RedactionInput,
} from "../src/services/redaction.js";

/**
 * **La fiche de cohérence ne se réécrit plus à chaque étape** (T307).
 *
 * Le schéma faisait rendre la fiche entière. Sur le banc des neuf vocaux de
 * Maxime, la dernière étape écrivait 7 233 caractères de fiche pour 1 193
 * caractères de texte, et ça grandissait en ligne droite depuis 1 586 — une
 * attente qui s'allonge à mesure que le carnet grandit, pour des caractères
 * que le modèle avait sous les yeux.
 *
 * Le modèle ne rend plus que les **ajouts** ; la couture se fait ici. Ce qui
 * était une consigne dans un schéma — « ne retire aucune entrée, ne change
 * aucune graphie fixée » — devient la forme du code, et c'est ce que ces
 * tests tiennent : un modèle qui oublie la moitié de la fiche ne peut plus
 * l'effacer.
 */

const muet = pino({ level: "silent" });

function ajouts(partiel: Partial<CoherenceAdditions> = {}): CoherenceAdditions {
  return {
    newPeople: [],
    newPlaces: [],
    newLexicon: [],
    newFigures: [],
    narration: { person: "", tense: "" },
    voice: [],
    ...partiel,
  };
}

function fiche(partiel: Partial<CoherenceSheet> = {}): CoherenceSheet {
  return { ...EMPTY_COHERENCE_SHEET, ...partiel };
}

describe("la fiche de cohérence se recoud côté serveur", () => {
  it("ajoute ce que l'étape apporte à ce que le carnet savait", () => {
    const avant = fiche({
      places: [{ canonicalName: "Naxos", notes: "première île" }],
      lexicon: [{ term: "la taverne de Georges", notes: "le dîner du premier soir" }],
    });

    const apres = mergeCoherenceSheet(
      avant,
      ajouts({
        newPlaces: [{ canonicalName: "Paros", notes: "l'île d'après" }],
        newFigures: [{ label: "traversée", value: "45 minutes" }],
      }),
    );

    expect(apres.places.map((place) => place.canonicalName)).toEqual(["Naxos", "Paros"]);
    expect(apres.figures).toEqual([{ label: "traversée", value: "45 minutes" }]);
    // Et le lexique que l'étape n'a pas mentionné est toujours là.
    expect(apres.lexicon).toEqual(avant.lexicon);
  });

  it("n'efface rien quand le modèle ne redonne rien", () => {
    const avant = fiche({
      people: [{ canonicalName: "Fanny", notes: "voyage avec Maxime" }],
      places: [{ canonicalName: "Naxos", notes: "première île" }],
      lexicon: [{ term: "la taverne de Georges", notes: "le premier soir" }],
      figures: [{ label: "durée", value: "douze jours" }],
      narration: { person: "on", tense: "passé composé" },
      voice: ["phrases courtes", "ironie douce"],
    });

    // Le cas qui comptait : avant T307, une fiche rendue amputée écrasait la
    // vraie. Des ajouts vides ne peuvent plus rien enlever.
    expect(mergeCoherenceSheet(avant, ajouts())).toEqual(avant);
  });

  it("ne fait pas entrer deux fois le même lieu écrit autrement", () => {
    const apres = mergeCoherenceSheet(
      fiche({ places: [{ canonicalName: "Naxos", notes: "première île" }] }),
      ajouts({ newPlaces: [{ canonicalName: "naxos ", notes: "l'île du début" }] }),
    );

    // La graphie fixée la première fois gagne : c'est la règle de la fiche
    // (« une personne = une orthographe »), et ici elle est garantie.
    expect(apres.places).toEqual([{ canonicalName: "Naxos", notes: "première île" }]);
  });

  it("laisse tomber une entrée sans nom", () => {
    const apres = mergeCoherenceSheet(
      fiche(),
      ajouts({ newPeople: [{ canonicalName: "  ", notes: "quelqu'un" }] }),
    );

    expect(apres.people).toEqual([]);
  });

  it("fixe la narration à la première étape qui la pose, et n'en bouge plus", () => {
    const ouverte = mergeCoherenceSheet(
      fiche(),
      ajouts({ narration: { person: "on", tense: "passé composé" } }),
    );
    expect(ouverte.narration).toEqual({ person: "on", tense: "passé composé" });

    // « Le même pour tout le carnet » était une consigne dans un schéma ; une
    // étape qui change d'avis au milieu ne peut plus faire basculer le carnet.
    const plusTard = mergeCoherenceSheet(
      ouverte,
      ajouts({ narration: { person: "je", tense: "présent" } }),
    );
    expect(plusTard.narration).toEqual({ person: "on", tense: "passé composé" });
  });

  it("remplace le portrait du narrateur, sans le laisser enfler", () => {
    const avant = fiche({ voice: ["phrases courtes", "ironie douce"] });

    const affine = mergeCoherenceSheet(avant, ajouts({ voice: ["phrases courtes", "tendre avec Fanny"] }));
    // Un portrait s'affine : il ne s'additionne pas, sans quoi il grossirait
    // d'étape en étape — précisément ce qu'on corrige ailleurs.
    expect(affine.voice).toEqual(["phrases courtes", "tendre avec Fanny"]);

    // Et une étape qui n'en rend pas garde celui du carnet.
    expect(mergeCoherenceSheet(avant, ajouts()).voice).toEqual(avant.voice);
  });
});

/** Ce que le SDK rend : un flux dont `finalMessage()` donne le message entier. */
function clientQuiRepond(reponses: unknown[], prompts: string[]): Anthropic {
  return {
    messages: {
      stream(requete: Record<string, unknown>) {
        const messages = requete.messages as { content: string }[];
        prompts.push(messages[0]?.content ?? "");
        const corps = reponses[prompts.length - 1];
        return {
          finalMessage: async () => ({
            stop_reason: "end_turn",
            content: [{ type: "text", text: JSON.stringify(corps) }],
          }),
        };
      },
    },
  } as unknown as Anthropic;
}

function souvenir(coherenceSheet: CoherenceSheet): RedactionInput {
  return {
    memo: { title: "Grèce", subtitle: null, authors: null, theme: null, styleKey: null },
    entry: {
      transcript: "On a pris le ferry pour Paros, quarante-cinq minutes de traversée.",
      capturedAt: new Date("2026-07-12T18:00:00Z"),
      placeLabel: "Paros",
    },
    coherenceSheet,
    previous: [{ capturedAt: new Date("2026-07-11T18:00:00Z"), placeLabel: "Naxos", title: "Naxos", text: "…" }],
  };
}

describe("ce qu'on demande au modèle, et ce qu'on en ressort", () => {
  it("ne demande que les ajouts, et rend pourtant la fiche entière", async () => {
    const avant = fiche({
      places: [{ canonicalName: "Naxos", notes: "première île" }],
      narration: { person: "on", tense: "passé composé" },
      voice: ["phrases courtes"],
    });
    const prompts: string[] = [];
    const client = clientQuiRepond(
      [
        {
          understanding: { heart: "le ferry", tone: "", readings: [] },
          title: "Le ferry pour Paros",
          text: "Quarante-cinq minutes de traversée.",
          weatherKey: null,
          funFact: null,
          funFactTitle: null,
          quiz: null,
          doubts: [],
          namesToConfirm: [],
          continuesPrevious: false,
          moments: [],
        },
        {
          // Le relevé ne renvoie **que** le neuf : pas un mot de Naxos.
          coherenceAdditions: ajouts({
            newPlaces: [{ canonicalName: "Paros", notes: "l'île d'après" }],
            newFigures: [{ label: "traversée", value: "45 minutes" }],
            narration: { person: "on", tense: "passé composé" },
            voice: ["phrases courtes"],
          }),
          insights: {
            countries: [],
            regions: [],
            cities: [],
            peopleMet: 0,
            distanceKilometres: null,
            transports: [],
            currentPlace: null,
          },
          temperatureC: null,
        },
      ],
      prompts,
    );

    const result = await new AnthropicRedactor(client, "claude-opus-5", muet).redact(souvenir(avant));

    // Ce que la rédaction rend est inchangé pour tout le reste du serveur : la
    // fiche entière, Naxos compris, alors que le modèle ne l'a pas réécrite.
    expect(result.coherenceSheet.places.map((place) => place.canonicalName)).toEqual(["Naxos", "Paros"]);
    expect(result.coherenceSheet.figures).toEqual([{ label: "traversée", value: "45 minutes" }]);
    expect(result.coherenceSheet.narration).toEqual({ person: "on", tense: "passé composé" });

    // Et ce qu'on lui demande le dit : la fiche est acquise, on veut les ajouts.
    const releve = prompts[1] ?? "";
    expect(releve).toContain("coherenceAdditions");
    expect(releve).not.toContain("Rends seulement `coherenceSheet`");
    // La fiche lui est toujours **donnée** — c'est elle qui tient la cohérence.
    expect(releve).toContain("Naxos");
  });

  it("ne laisse plus le schéma réclamer la fiche entière", () => {
    const releve = RELEVE_SCHEMA as unknown as {
      properties: Record<string, unknown>;
      required: string[];
    };

    expect(Object.keys(releve.properties)).toEqual(["coherenceAdditions", "insights", "temperatureC"]);
    expect(releve.required).toContain("coherenceAdditions");
    expect(releve.properties.coherenceSheet).toBeUndefined();
  });
});
