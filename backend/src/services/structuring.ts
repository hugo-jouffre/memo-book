import OpenAI from "openai";
import { stringify as stringifyYaml } from "yaml";
import type { Env } from "../env.js";
import { loadLayoutKnowledgeBase, loadPayloadSchema } from "../lib/templates.js";
import { validatePayload, type ValidationIssue } from "./payloadValidator.js";

/** Une entrée du carnet telle que la voit l'étape de structuration. */
export interface StructuringEntry {
  kind: "audio" | "text" | "photo";
  /** Texte transcrit (audio) ou saisi (text). Vide pour une photo seule. */
  transcript: string | null;
  capturedAt: Date;
  placeLabel: string | null;
  /** URL publique de la photo, quand l'entrée en porte une. */
  photoUrl: string | null;
}

export interface StructuringInput {
  title: string;
  subtitle: string | null;
  authors: string | null;
  theme: string | null;
  coverPhotoUrl: string | null;
  entries: StructuringEntry[];
}

export type BookPayload = Record<string, unknown>;

export interface Structurer {
  structure(input: StructuringInput): Promise<BookPayload>;
}

const DATE_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

const SHORT_DATE_FORMATTER = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  timeZone: "UTC",
});

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Regroupe les entrées par journée civile, dans l'ordre chronologique. */
export function groupEntriesByDay(
  entries: StructuringEntry[],
): { key: string; date: Date; entries: StructuringEntry[] }[] {
  const buckets = new Map<string, { key: string; date: Date; entries: StructuringEntry[] }>();

  for (const entry of [...entries].sort(
    (a, b) => a.capturedAt.getTime() - b.capturedAt.getTime(),
  )) {
    const key = dayKey(entry.capturedAt);
    const bucket = buckets.get(key);
    if (bucket) {
      bucket.entries.push(entry);
    } else {
      buckets.set(key, { key, date: entry.capturedAt, entries: [entry] });
    }
  }

  return [...buckets.values()];
}

function formatDateRange(days: { date: Date }[]): string {
  const first = days[0];
  const last = days[days.length - 1];
  if (!first || !last) return "";
  if (days.length === 1) return DATE_FORMATTER.format(first.date);
  return `${DATE_FORMATTER.format(first.date)} – ${DATE_FORMATTER.format(last.date)}`;
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Découpe un texte long en paragraphes qui tiennent dans la page. */
function toBodyHtml(text: string, maxCharsPerParagraph = 400): string {
  const sentences = text
    .replace(/\s+/g, " ")
    .trim()
    .split(/(?<=[.!?…])\s+/)
    .filter(Boolean);

  const paragraphs: string[] = [];
  let current = "";

  for (const sentence of sentences) {
    if (current.length === 0) {
      current = sentence;
    } else if (current.length + 1 + sentence.length <= maxCharsPerParagraph) {
      current = `${current} ${sentence}`;
    } else {
      paragraphs.push(current);
      current = sentence;
    }
  }
  if (current.length > 0) paragraphs.push(current);

  if (paragraphs.length === 0) return "<p>Journée sans récit enregistré.</p>";

  return paragraphs
    .map((paragraph) => `<p>${escapeHtml(paragraph.slice(0, maxCharsPerParagraph))}</p>`)
    .join("");
}

/**
 * Heuristique de choix de layout, reprise de LAYOUT_KB.md § « Sélection rapide ».
 * Elle sert de secours déterministe : c'est le modèle qui décide en mode `live`.
 */
export function pickLayout(photoCount: number, textLength: number): string {
  if (photoCount >= 3) return "layout_gallery_stack";
  if (photoCount === 0) return "layout_story_facts";
  if (photoCount === 1) return textLength > 400 ? "layout_hero_top" : "layout_postcard";
  return "layout_modern_journal";
}

/**
 * Structuration déterministe : une journée par date, un layout par heuristique,
 * aucun appel réseau. C'est ce que le smoke test et la CI utilisent, et c'est
 * aussi le filet de sécurité si l'appel modèle échoue.
 */
export class HeuristicStructurer implements Structurer {
  async structure(input: StructuringInput): Promise<BookPayload> {
    const groups = groupEntriesByDay(input.entries);

    const days = groups.map((group, index) => {
      const photos = group.entries
        .map((entry) => entry.photoUrl)
        .filter((url): url is string => Boolean(url));

      const narrative = group.entries
        .map((entry) => entry.transcript?.trim())
        .filter((text): text is string => Boolean(text))
        .join(" ");

      const place =
        group.entries.find((entry) => entry.placeLabel)?.placeLabel ?? null;

      const day: Record<string, unknown> = {
        title: `Jour ${index + 1}${place ? ` – ${place}` : ""}`,
        date: DATE_FORMATTER.format(group.date),
        day_intro: {
          day_number: String(index + 1).padStart(2, "0"),
          location: place ?? "",
          date: SHORT_DATE_FORMATTER.format(group.date),
        },
        body_html: toBodyHtml(narrative),
        [pickLayout(photos.length, narrative.length)]: true,
      };

      if (place) day["city"] = place;
      if (photos.length > 0) day["photos"] = photos;

      return day;
    });

    const payload: BookPayload = {
      book_title: input.title,
      authors: input.authors ?? "",
      date_range: formatDateRange(groups),
      brand_name: "MemoBook",
      days,
    };

    if (input.subtitle) payload["book_subtitle"] = input.subtitle;
    if (input.coverPhotoUrl) payload["cover_photo"] = input.coverPhotoUrl;

    return payload;
  }
}

function formatIssues(issues: ValidationIssue[]): string {
  return issues
    .map((issue) => `- ${issue.path || "(racine)"}: ${issue.message}`)
    .join("\n");
}

/**
 * Structuration par modèle. Le prompt système est construit à partir des
 * fichiers du dépôt (`gpt_image_schema.yaml`, `LAYOUT_KB.md`) : quand le
 * template évolue, le prompt suit sans changement de code.
 */
export class LlmStructurer implements Structurer {
  constructor(
    private readonly client: OpenAI,
    private readonly model: string,
    /** Reprend la main si le modèle ne produit rien d'exploitable. */
    private readonly fallback: Structurer = new HeuristicStructurer(),
  ) {}

  private buildSystemPrompt(): string {
    return [
      "Tu es l'éditeur de MemoBook. Tu transformes des récits oraux transcrits en",
      "un carnet imprimable. Tu écris en français, à la première personne du",
      "narrateur, dans un ton chaleureux et concret — jamais promotionnel.",
      "",
      "Tu réponds UNIQUEMENT par un objet JSON conforme au schéma ci-dessous.",
      "",
      "## Schéma du payload",
      "```yaml",
      stringifyYaml(loadPayloadSchema()),
      "```",
      "",
      "## Règles éditoriales (à respecter strictement)",
      loadLayoutKnowledgeBase(),
    ].join("\n");
  }

  private buildUserPrompt(input: StructuringInput): string {
    const groups = groupEntriesByDay(input.entries);

    const lines: string[] = [
      `Titre du carnet : ${input.title}`,
      input.subtitle ? `Sous-titre : ${input.subtitle}` : "",
      input.authors ? `Auteurs : ${input.authors}` : "",
      input.theme ? `Thème : ${input.theme}` : "",
      input.coverPhotoUrl ? `Photo de couverture : ${input.coverPhotoUrl}` : "",
      "",
      `Matière brute — ${groups.length} journée(s) :`,
    ].filter(Boolean);

    for (const [index, group] of groups.entries()) {
      lines.push("", `### Journée ${index + 1} — ${DATE_FORMATTER.format(group.date)}`);
      for (const entry of group.entries) {
        if (entry.placeLabel) lines.push(`Lieu : ${entry.placeLabel}`);
        if (entry.transcript) lines.push(`Récit : ${entry.transcript}`);
        if (entry.photoUrl) lines.push(`Photo : ${entry.photoUrl}`);
      }
    }

    lines.push(
      "",
      "N'invente aucun lieu, aucune date et aucune photo : n'utilise que les URLs",
      "listées ci-dessus. Tu peux en revanche enrichir les `fun_facts` avec des",
      "informations factuelles sur les lieux réellement mentionnés.",
    );

    return lines.join("\n");
  }

  async structure(input: StructuringInput): Promise<BookPayload> {
    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
      { role: "system", content: this.buildSystemPrompt() },
      { role: "user", content: this.buildUserPrompt(input) },
    ];

    // Deux tentatives : la seconde reçoit les erreurs de validation de la
    // première. En pratique, c'est ce qui rattrape les dépassements de longueur
    // et les layouts multiples.
    for (let attempt = 1; attempt <= 2; attempt += 1) {
      const completion = await this.client.chat.completions.create({
        model: this.model,
        messages,
        response_format: { type: "json_object" },
        temperature: 0.7,
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) break;

      let candidate: unknown;
      try {
        candidate = JSON.parse(content);
      } catch {
        messages.push(
          { role: "assistant", content },
          { role: "user", content: "Ta réponse n'était pas du JSON valide. Recommence." },
        );
        continue;
      }

      // Le modèle renvoie parfois le schéma complet de l'agent plutôt que le
      // seul payload : on accepte les deux formes.
      const payload =
        candidate && typeof candidate === "object" && "apitemplate_payload" in candidate
          ? (candidate as Record<string, unknown>)["apitemplate_payload"]
          : candidate;

      const result = validatePayload(payload);
      if (result.valid) return payload as BookPayload;

      if (attempt === 2) break;

      messages.push(
        { role: "assistant", content },
        {
          role: "user",
          content: `Ton JSON ne respecte pas le schéma :\n${formatIssues(result.errors)}\n\nCorrige-le et renvoie le JSON complet.`,
        },
      );
    }

    return this.fallback.structure(input);
  }
}

export function createStructurer(env: Env): Structurer {
  if (!env.live) return new HeuristicStructurer();
  return new LlmStructurer(
    new OpenAI({ apiKey: env.OPENAI_API_KEY }),
    env.OPENAI_STRUCTURING_MODEL,
  );
}
