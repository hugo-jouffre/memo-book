import Anthropic from "@anthropic-ai/sdk";
import type { Env } from "../env.js";
import { loadWritingRules } from "../lib/templates.js";

/**
 * Passe de rédaction — étape 2 du pipeline, entre la transcription et la mise
 * en page.
 *
 * Elle existe séparément parce que les deux passes n'ont ni le même moment, ni
 * la même matière, ni les mêmes règles :
 *
 * - **Rédiger** se fait souvenir par souvenir, juste après l'enregistrement,
 *   pendant que l'utilisateur est là pour relire et corriger. Le contrat est
 *   `agents/agent-transcription.md`.
 * - **Mettre en page** se fait à la prévisualisation, sur l'ensemble du carnet,
 *   à partir de textes déjà validés. Le contrat est `LAYOUT_KB.md`.
 *
 * Les mélanger reviendrait à réécrire, à chaque aperçu PDF, un texte que
 * l'utilisateur a corrigé à la main.
 */

/** Ce que la rédaction sait déjà du carnet quand elle écrit une étape. */
export interface CoherenceSheet {
  people: { canonicalName: string; notes: string }[];
  places: { canonicalName: string; notes: string }[];
  lexicon: { term: string; notes: string }[];
  narration: { person: string; tense: string };
  /** Chiffres déjà annoncés dans le carnet, pour ne pas se contredire. */
  figures: { label: string; value: string }[];
}

export const EMPTY_COHERENCE_SHEET: CoherenceSheet = {
  people: [],
  places: [],
  lexicon: [],
  narration: { person: "", tense: "" },
  figures: [],
};

/** Une étape déjà rédigée et validée, donnée en contexte à la suivante. */
export interface RedactedNeighbour {
  capturedAt: Date;
  placeLabel: string | null;
  title: string | null;
  text: string;
}

export interface RedactionInput {
  memo: {
    title: string;
    subtitle: string | null;
    authors: string | null;
    theme: string | null;
    styleKey: string | null;
  };
  entry: {
    transcript: string;
    capturedAt: Date;
    placeLabel: string | null;
  };
  coherenceSheet: CoherenceSheet;
  /** Étapes précédentes, de la plus ancienne à la plus récente. */
  previous: RedactedNeighbour[];
}

export interface RedactionResult {
  title: string;
  text: string;
  weatherKey: "sun" | "sun-wind" | "cloud" | "rain" | "snow";
  funFact: string | null;
  funFactTitle: string | null;
  coherenceSheet: CoherenceSheet;
  /** Modèle qui a produit le texte, tracé sur l'entrée. */
  model: string;
}

export interface Redactor {
  redact(input: RedactionInput): Promise<RedactionResult>;
}

const DATE_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

/**
 * Le schéma de sortie. Les contraintes de longueur du gabarit
 * (`LAYOUT_KB.md` § Contraintes de longueur) sont rappelées ici *et* dans le
 * prompt : le schéma ne sait pas compter les caractères, mais il empêche au
 * moins les champs manquants et les clés inventées.
 */
const COHERENCE_ENTRY_SCHEMA = {
  type: "object",
  properties: {
    canonicalName: { type: "string", description: "La graphie retenue, à réutiliser telle quelle." },
    notes: { type: "string", description: "Ce qu'il faut savoir : lien, rôle, prononciation." },
  },
  required: ["canonicalName", "notes"],
  additionalProperties: false,
} as const;

const REDACTION_SCHEMA = {
  type: "object",
  properties: {
    title: {
      type: "string",
      description:
        "Titre manuscrit de l'étape. Court, tient sur une ligne. Même registre que les titres déjà employés dans le carnet.",
    },
    text: {
      type: "string",
      description:
        "Le récit rédigé, à la première personne. Paragraphes séparés par une ligne vide. " +
        "2 à 3 paragraphes, 420 caractères maximum chacun.",
    },
    weatherKey: {
      type: "string",
      enum: ["sun", "sun-wind", "cloud", "rain", "snow"],
      description:
        "Temps dominant de l'étape. Si le récit n'en dit rien, se fier au lieu et à la saison. " +
        "En cas d'hésitation entre deux valeurs : sun-wind.",
    },
    funFact: {
      anyOf: [{ type: "string" }, { type: "null" }],
      description:
        "Encart de culture générale sur un lieu réellement visité, 140 caractères maximum. " +
        "null si rien de sûr et de pertinent — une étape sur deux au maximum en porte un.",
    },
    funFactTitle: {
      anyOf: [
        { type: "string", enum: ["Fun fact", "Infos", "Culture générale", "Chiffres clés"] },
        { type: "null" },
      ],
      description: "Titre de l'encart. null quand funFact est null.",
    },
    coherenceSheet: {
      type: "object",
      description:
        "La fiche de cohérence mise à jour : l'ancienne, plus ce que cette étape ajoute. " +
        "Ne jamais retirer une entrée existante ni changer une graphie déjà fixée.",
      properties: {
        people: { type: "array", items: COHERENCE_ENTRY_SCHEMA },
        places: { type: "array", items: COHERENCE_ENTRY_SCHEMA },
        lexicon: {
          type: "array",
          items: {
            type: "object",
            properties: {
              term: { type: "string" },
              notes: { type: "string" },
            },
            required: ["term", "notes"],
            additionalProperties: false,
          },
        },
        narration: {
          type: "object",
          properties: {
            person: { type: "string", description: "« je », « on » ou « nous » — le même pour tout le carnet." },
            tense: { type: "string", description: "Le système de temps retenu." },
          },
          required: ["person", "tense"],
          additionalProperties: false,
        },
        figures: {
          type: "array",
          description: "Chiffres déjà annoncés dans le carnet, pour ne pas se contredire.",
          items: {
            type: "object",
            properties: {
              label: { type: "string" },
              value: { type: "string" },
            },
            required: ["label", "value"],
            additionalProperties: false,
          },
        },
      },
      required: ["people", "places", "lexicon", "narration", "figures"],
      additionalProperties: false,
    },
  },
  required: ["title", "text", "weatherKey", "funFact", "funFactTitle", "coherenceSheet"],
  additionalProperties: false,
} as const;

/**
 * Rédaction réelle, par Claude.
 *
 * Le prompt système est **le fichier de règles lui-même**, pas une
 * paraphrase : quand l'équipe édite `agents/agent-transcription.md`, le
 * comportement change au redémarrage suivant, sans toucher au code. C'est le
 * même contrat que `templates/` a déjà avec la mise en page.
 */
export class AnthropicRedactor implements Redactor {
  constructor(
    private readonly client: Anthropic,
    private readonly model: string,
  ) {}

  private buildSystemPrompt(): Anthropic.TextBlockParam[] {
    return [
      {
        type: "text",
        text: [
          "Tu es l'agent de rédaction de MemoBook. Tu transformes la transcription brute",
          "d'un souvenir raconté à l'oral en un texte de carnet de voyage.",
          "",
          "Les règles ci-dessous font autorité et s'appliquent intégralement, sans exception.",
          "Elles priment sur tes habitudes de rédaction. En cas de conflit entre deux règles,",
          "la hiérarchie des quatre principes tranche.",
          "",
          "Tu réponds uniquement par l'objet JSON demandé.",
          "",
          "---",
          "",
          loadWritingRules(),
        ].join("\n"),
        // Les règles sont identiques d'un souvenir à l'autre : mises en cache,
        // elles ne sont facturées plein tarif qu'au premier appel de la série.
        cache_control: { type: "ephemeral" },
      },
    ];
  }

  private buildUserPrompt(input: RedactionInput): string {
    const { memo, entry, coherenceSheet, previous } = input;

    const lines: string[] = ["## Le carnet", `Titre : ${memo.title}`];
    if (memo.subtitle) lines.push(`Sous-titre : ${memo.subtitle}`);
    if (memo.authors) lines.push(`Voyageurs : ${memo.authors}`);
    if (memo.theme) lines.push(`Thème : ${memo.theme}`);
    if (memo.styleKey) lines.push(`Style de carnet : ${memo.styleKey}`);

    lines.push(
      "",
      "## Fiche de cohérence",
      previous.length === 0
        ? "Première étape du carnet : la fiche est vide, c'est toi qui l'ouvres. " +
            "Les choix que tu fais ici (personne, temps, appellations) engagent tout le carnet."
        : "Relis-la avant d'écrire, complète-la après. Ne change aucune graphie déjà fixée.",
      "```json",
      JSON.stringify(coherenceSheet, null, 2),
      "```",
    );

    if (previous.length > 0) {
      // Les trois dernières suffisent : au-delà, la fiche de cohérence porte
      // ce qui doit rester stable, et le contexte coûterait plus qu'il
      // n'apporte.
      const recent = previous.slice(-3);
      lines.push(
        "",
        `## Les ${recent.length} étapes précédentes, déjà validées`,
        "Elles donnent le ton, le rythme et la voix à tenir. Ne les résume pas, ne les",
        "reprends pas : enchaîne. La dernière phrase de la dernière étape et la première",
        "phrase de la tienne ne doivent pas se recouvrir.",
      );
      for (const neighbour of recent) {
        lines.push(
          "",
          `### ${neighbour.title ?? "(sans titre)"} — ${DATE_FORMATTER.format(neighbour.capturedAt)}` +
            (neighbour.placeLabel ? ` — ${neighbour.placeLabel}` : ""),
          neighbour.text,
        );
      }
    }

    lines.push(
      "",
      "## L'étape à rédiger",
      `Date : ${DATE_FORMATTER.format(entry.capturedAt)}`,
      entry.placeLabel ? `Lieu : ${entry.placeLabel}` : "Lieu : non précisé par le voyageur",
      "",
      "Transcription brute de ce que le voyageur a raconté à l'oral :",
      "```",
      entry.transcript,
      "```",
      "",
      "## Rappels de format",
      "- `text` : 2 à 3 paragraphes, séparés par une ligne vide, **420 caractères maximum",
      "  par paragraphe**. Un dépassement fait échouer la génération du carnet.",
      "- `funFact` : 140 caractères maximum, ou `null`.",
      "- Aucun HTML, aucun Markdown, aucun emoji dans `text` : du texte nu, la mise en",
      "  page s'en charge.",
      "- Tout ce que tu écris dans `text` doit se retrouver dans la transcription",
      "  ci-dessus. La culture générale va dans `funFact`, jamais dans le récit.",
    );

    return lines.join("\n");
  }

  async redact(input: RedactionInput): Promise<RedactionResult> {
    const response = await this.client.messages.create({
      model: this.model,
      // Large : la réflexion compte dans ce plafond, et un texte tronqué au
      // milieu d'une phrase est pire qu'une erreur franche.
      max_tokens: 12_000,
      thinking: { type: "adaptive" },
      output_config: {
        effort: "high",
        format: { type: "json_schema", schema: REDACTION_SCHEMA },
      },
      system: this.buildSystemPrompt(),
      messages: [{ role: "user", content: this.buildUserPrompt(input) }],
    });

    // À vérifier avant de lire `content` : un refus renvoie un 200 avec un
    // tableau vide, et `content[0]` planterait sur un souvenir parfaitement
    // anodin mais mal classé.
    if (response.stop_reason === "refusal") {
      throw new Error(
        "Le modèle a refusé de rédiger ce souvenir. Le texte brut reste disponible : " +
          "corrige-le à la main dans l'app, ou relance la rédaction.",
      );
    }

    if (response.stop_reason === "max_tokens") {
      throw new Error(
        "La rédaction s'est arrêtée avant la fin. Relance-la : si ça se reproduit, " +
          "le souvenir est probablement trop long pour une seule étape.",
      );
    }

    const text = response.content.find((block) => block.type === "text")?.text;
    if (!text) {
      throw new Error("Le modèle n'a produit aucun texte exploitable.");
    }

    const parsed = JSON.parse(text) as Omit<RedactionResult, "model">;
    return { ...parsed, model: this.model };
  }
}

/**
 * Rédaction déterministe, sans réseau ni clé — tests, smoke et boucle de
 * travail sur la mise en page.
 *
 * Elle nettoie ce qu'un vrai passage nettoierait (hésitations, tics) sans rien
 * inventer : le texte produit reste reconnaissable, ce qui rend les tests de
 * bout en bout lisibles.
 */
export class FakeRedactor implements Redactor {
  private static readonly ORAL_TICS =
    /\b(euh+|ben|bah|du coup|en fait|genre|voilà quoi|tu vois|quoi)\b[,.]?\s*/gi;

  async redact(input: RedactionInput): Promise<RedactionResult> {
    const cleaned = input.entry.transcript
      .replace(FakeRedactor.ORAL_TICS, "")
      .replace(/\s{2,}/g, " ")
      .trim();

    const body = cleaned.length > 0 ? cleaned : "Souvenir sans récit exploitable.";
    const capitalized = body.charAt(0).toUpperCase() + body.slice(1);

    const firstSentence = capitalized.split(/(?<=[.!?…])\s+/)[0] ?? capitalized;

    return {
      title: firstSentence.slice(0, 60).replace(/[.!?…]+$/, ""),
      text: capitalized.slice(0, 420),
      weatherKey: "sun-wind",
      funFact: null,
      funFactTitle: null,
      // La fiche est propagée telle quelle : le faux rédacteur ne prétend pas
      // tenir une cohérence, mais il ne la détruit pas non plus.
      coherenceSheet: input.coherenceSheet,
      model: "fake-redactor",
    };
  }
}

export function createRedactor(env: Env): Redactor {
  if (!env.live || env.ANTHROPIC_API_KEY === "") return new FakeRedactor();
  return new AnthropicRedactor(
    new Anthropic({ apiKey: env.ANTHROPIC_API_KEY }),
    env.ANTHROPIC_REDACTION_MODEL,
  );
}
