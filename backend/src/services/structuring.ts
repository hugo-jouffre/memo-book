import OpenAI from "openai";
import { stringify as stringifyYaml } from "yaml";
import type { Env } from "../env.js";
import { loadLayoutKnowledgeBase, loadPayloadSchema } from "../lib/templates.js";
import {
  EDITORIAL_LIMITS,
  STEP_SIZES,
  pageCapacity,
  validatePayload,
  type ValidationIssue,
} from "./payloadValidator.js";

/** Une entrée du carnet telle que la voit l'étape de structuration. */
export interface StructuringEntry {
  kind: "audio" | "text" | "photo";
  /**
   * Le texte **définitif** de l'étape : corrigé par l'utilisateur s'il l'a
   * fait, sinon rédigé par l'agent de rédaction. Vide pour une photo seule.
   *
   * Ce n'est plus une transcription brute : la mise en page le reprend au mot
   * près, elle ne le réécrit pas.
   */
  transcript: string | null;
  /** `true` quand l'utilisateur a corrigé le texte à la main dans l'app. */
  editedByUser: boolean;
  /** Titre proposé par la rédaction, à reprendre tel quel. */
  title: string | null;
  /** Encart déjà rédigé et déjà borné à 140 caractères. */
  funFact: string | null;
  funFactTitle: string | null;
  /** Icône météo déjà choisie par la rédaction. */
  weatherKey: string | null;
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
function toBodyHtml(
  text: string,
  maxCharsPerParagraph = EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph,
): string {
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
 * Heuristique de choix de layout, reprise du catalogue de `LAYOUT_KB.md` et du
 * barème S/M/L/XL. Elle sert de secours déterministe : c'est le modèle qui
 * décide en mode `live`.
 *
 * Deux règles la gouvernent, dans cet ordre :
 *
 * 1. **sous le minimum de S, c'est l'image qui porte la page** — une page de
 *    photos si on en a de quoi la remplir, sinon la photo héro. Un récit court
 *    sur un layout de récit laisse une page aux trois quarts vide ;
 * 2. **au-dessus, le layout le plus visuel qui tienne le texte.** `layout_hero_top`
 *    plafonne à 380 caractères : au-delà, il faut un layout à récit pleine
 *    largeur.
 *
 * Elle ne rend que des drapeaux du catalogue : un drapeau inconnu n'échoue pas,
 * il est silencieusement ignoré et la journée retombe sur la mise en page par
 * défaut — exactement le genre de dérive que `LAYOUT_KB.md` interdit.
 */
export function pickLayout(photoCount: number, textLength: number): string {
  if (textLength < STEP_SIZES.S.min) {
    if (photoCount >= 3) return "layout_photo_page";
    if (photoCount >= 1) return "layout_hero_top";
    return "layout_story_facts";
  }

  if (photoCount >= 3) return "layout_collage";
  if (photoCount === 2) return "layout_split_left";
  if (photoCount === 1 && textLength <= LAYOUT_CAPACITY_HERO_TOP) return "layout_hero_top";
  return "layout_story_opener";
}

/** Plafond mesuré de `layout_hero_top` sur une page à bandeau. */
const LAYOUT_CAPACITY_HERO_TOP = 380;

/**
 * Coupe `text` au plus près de `max` caractères, sur une fin de phrase si
 * possible, sinon sur une espace. Couper au milieu d'un mot se verrait à
 * l'impression, et le texte est définitif : on ne le réécrit pas, on choisit
 * seulement où tourner la page.
 */
/** Nombre de pages déjà posées pour l'étape en cours de construction. */
function pagesDeLEtape(days: Record<string, unknown>[]): number {
  let pages = 0;
  for (let i = days.length - 1; i >= 0; i -= 1) {
    pages += 1;
    if (days[i]?.["day_intro"]) break;
  }
  return pages;
}

function splitAt(text: string, max: number): [string, string] {
  if (text.length <= max) return [text, ""];

  const fenetre = text.slice(0, max + 1);
  const finDePhrase = Math.max(
    fenetre.lastIndexOf(". "),
    fenetre.lastIndexOf("! "),
    fenetre.lastIndexOf("? "),
    fenetre.lastIndexOf("… "),
  );
  const coupe = finDePhrase > max / 2 ? finDePhrase + 1 : fenetre.lastIndexOf(" ");

  if (coupe <= 0) return [text.slice(0, max), text.slice(max).trim()];
  return [text.slice(0, coupe).trim(), text.slice(coupe).trim()];
}

/**
 * Structuration déterministe : une journée par date, un layout par heuristique,
 * aucun appel réseau. C'est ce que le smoke test et la CI utilisent, et c'est
 * aussi le filet de sécurité si l'appel modèle échoue.
 */
export class HeuristicStructurer implements Structurer {
  async structure(input: StructuringInput): Promise<BookPayload> {
    const groups = groupEntriesByDay(input.entries);

    const days: Record<string, unknown>[] = [];
    let numero = 0;

    groups.forEach((group) => {
      const photos = group.entries
        .map((entry) => entry.photoUrl)
        .filter((url): url is string => Boolean(url));

      const narrative = group.entries
        .map((entry) => entry.transcript?.trim())
        .filter((text): text is string => Boolean(text))
        .join(" ");

      const place =
        group.entries.find((entry) => entry.placeLabel)?.placeLabel ?? null;

      // Titre, météo et encart viennent de la rédaction quand elle est passée.
      // Le repli déterministe ne réinvente que ce qui manque.
      const redactedTitle = group.entries.find((entry) => entry.title)?.title ?? null;
      const weatherKey = group.entries.find((entry) => entry.weatherKey)?.weatherKey ?? null;
      const withFunFact = group.entries.find((entry) => entry.funFact);

      // Le récit se déverse page après page. Une étape occupe au plus deux
      // pages — la première porte le bandeau, la seconde enchaîne sans lui.
      // Au-delà, c'est une nouvelle étape, pas une page de plus : c'est ce que
      // dit le barème, et ce que le validateur vérifiera.
      let reste = narrative;
      let premierePage = true;

      while (reste.length > 0 || premierePage) {
        const ouvreEtape = premierePage || days.length === 0 || pagesDeLEtape(days) >= STEP_SIZES.XL.pages;

        if (ouvreEtape) numero += 1;

        const day: Record<string, unknown> = {
          // Une page de suite n'a ni bandeau ni titre — le titre reste présent
          // mais vide, parce que le schéma l'exige et que le gabarit ne rend
          // que les titres non vides.
          title: "",
          [pickLayout(ouvreEtape ? photos.length : 0, reste.length)]: true,
        };

        if (ouvreEtape) {
          day["title"] = redactedTitle ?? `Jour ${numero}${place ? ` – ${place}` : ""}`;
          day["date"] = DATE_FORMATTER.format(group.date);
          day["day_intro"] = {
            day_number: String(numero).padStart(2, "0"),
            location: place ?? "",
            date: SHORT_DATE_FORMATTER.format(group.date),
            ...(weatherKey ? { weather_key: weatherKey } : {}),
          };
          if (place) day["city"] = place;
          if (photos.length > 0) day["photos"] = photos;
          if (withFunFact?.funFact) {
            day["fun_facts"] = [withFunFact.funFact];
            if (withFunFact.funFactTitle) day["fun_facts_title"] = withFunFact.funFactTitle;
          }
        }

        // La capacité se lit sur la page telle qu'elle vient d'être montée :
        // le bandeau, la carte info et les photos la font varier du simple au
        // quadruple.
        const [page, suite] = splitAt(reste, pageCapacity(day));
        day["body_html"] = toBodyHtml(page);

        days.push(day);
        reste = suite;
        premierePage = false;
      }
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
      "Tu es le metteur en page de MemoBook. Tu reçois des textes **déjà rédigés et",
      "déjà validés par le voyageur**, et tu les arranges en pages de carnet.",
      "",
      "## Ta seule mission : arranger, jamais réécrire",
      "",
      "Le texte de chaque étape t'arrive fini. Une autre passe l'a écrit en suivant",
      "les règles de rédaction de la maison, et le voyageur l'a relu et corrigé au",
      "clavier. Le réécrire effacerait son travail.",
      "",
      "- Reprends `title`, le récit, `fun_facts` et `weather_key` **au mot près**.",
      "- Tu peux **découper** un texte en `<p>` et **répartir** une étape trop dense",
      "  sur plusieurs entrées consécutives de `days[]`. Découper n'est pas réécrire :",
      "  aucun mot n'est ajouté, retiré ni remplacé.",
      "- Une étape marquée « corrigée par le voyageur » est intouchable, même si elle",
      "  te semble maladroite. Si elle dépasse les limites de longueur, scinde-la en",
      "  plusieurs entrées plutôt que de la raccourcir.",
      "- N'invente aucun texte : ni titre, ni encart, ni transition, ni légende.",
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
        if (entry.title) lines.push(`Titre (à reprendre tel quel) : ${entry.title}`);
        if (entry.weatherKey) lines.push(`weather_key (déjà choisi) : ${entry.weatherKey}`);
        if (entry.funFact) {
          lines.push(
            `Encart « ${entry.funFactTitle ?? "Fun fact"} » (à reprendre tel quel) : ${entry.funFact}`,
          );
        }
        if (entry.transcript) {
          lines.push(
            entry.editedByUser
              ? `Récit — CORRIGÉ PAR LE VOYAGEUR, intouchable : ${entry.transcript}`
              : `Récit — texte validé : ${entry.transcript}`,
          );
        }
        if (entry.photoUrl) lines.push(`Photo : ${entry.photoUrl}`);
      }
    }

    lines.push(
      "",
      "Rappel : ces textes sont définitifs. Tu les découpes en paragraphes et tu",
      "choisis les layouts ; tu ne les réécris pas, tu ne les résumes pas, tu ne les",
      "complètes pas. N'invente aucun lieu, aucune date et aucune photo : n'utilise",
      "que les URLs listées ci-dessus. N'ajoute pas de `fun_facts` : ceux qui devaient",
      "exister sont déjà donnés ci-dessus.",
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
