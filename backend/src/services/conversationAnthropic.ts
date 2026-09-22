import Anthropic from "@anthropic-ai/sdk";
import { loadConversationRules } from "../lib/templates.js";
import {
  ASIDE_LIMIT,
  HISTORY_TEXT_LIMIT,
  MAX_BEATS,
  PROMPT_LIMIT,
  REFORMULATION_LIMIT,
  composeBeats,
  scriptedReply,
  validateReply,
  type ConversationInput,
  type ConversationReply,
  type MemoResponder,
} from "./conversation.js";
import {
  OPENING_TEXT,
  SUGGESTIONS,
  SUGGESTION_IDS,
  SUGGESTION_SETS,
  type SuggestionId,
} from "./conversationCopy.js";

/**
 * MEMO, pour de vrai — `docs/conversation.md`, `agents/agent-conversation.md`.
 *
 * **Le prompt système est le fichier de règles lui-même**, pas une paraphrase :
 * l'équipe édite `agents/agent-conversation.md`, le comportement change au
 * redémarrage suivant, sans toucher au code. Même contrat que la rédaction
 * (`AnthropicRedactor`) et que la mise en page avec `templates/`.
 *
 * **Le modèle écrit des phrases ; le code garde tout le reste.** Les silences
 * entre deux bulles se calculent sur la longueur du texte (`composeBeats`), le
 * catalogue de puces est injecté depuis `conversationCopy.ts` et filtré au
 * retour, la rose/épine/graine n'est retenue que si le code l'autorisait, et
 * une réponse qui sort du contrat est **refusée** — pas rattrapée. Un modèle
 * qui déciderait du rythme ou inventerait une puce ferait un écran qui ment,
 * et on ne saurait pas lequel des deux côtés a tort.
 *
 * En cas de panne — réseau, refus, JSON illisible, contrat violé — on lève :
 * le job passe au moteur de règles (`fallbackResponder`), et la panne se lit
 * dans `model`, jamais dans un silence.
 */
export class AnthropicResponder implements MemoResponder {
  constructor(
    private readonly client: Anthropic,
    private readonly model: string,
  ) {}

  opening(): { text: string; suggestionIds: SuggestionId[] } {
    return { text: OPENING_TEXT, suggestionIds: [...SUGGESTION_SETS.opening] };
  }

  async reply(input: ConversationInput): Promise<ConversationReply> {
    const received = input.message.text ?? "";

    // Une commande connue se répond sans modèle — et sans appel réseau.
    const command = scriptedReply(input.message.suggestionId, received);
    if (command) return command;

    const response = await this.client.messages.create({
      model: this.model,
      // Trois bulles courtes : le plafond sert à la réflexion, pas au texte.
      max_tokens: 2_000,
      thinking: { type: "adaptive" },
      output_config: {
        // `low` et non `high` : un tour de conversation se décide en quelques
        // secondes, et quelqu'un attend devant son écran. La rédaction, elle,
        // a le droit de réfléchir — personne ne la regarde écrire.
        effort: "low",
        format: { type: "json_schema", schema: replySchema() },
      },
      system: this.buildSystemPrompt(),
      messages: [{ role: "user", content: buildUserPrompt(input) }],
    });

    // À vérifier avant `content` : un refus renvoie un 200 avec un tableau
    // vide, et `content[0]` planterait sur un récit parfaitement anodin.
    if (response.stop_reason === "refusal") {
      throw new Error("Le modèle a refusé de répondre à ce tour.");
    }
    if (response.stop_reason === "max_tokens") {
      throw new Error("La réponse s'est arrêtée avant la fin.");
    }

    const text = response.content.find((block) => block.type === "text")?.text;
    if (!text) throw new Error("Le modèle n'a produit aucun texte exploitable.");

    return validateReply(toReply(JSON.parse(text) as RawReply, received, this.model), input);
  }

  private buildSystemPrompt(): Anthropic.TextBlockParam[] {
    return [
      {
        type: "text",
        text: [
          "Tu es MEMO, la voix de MemoBook. Le voyageur te raconte son voyage ; tu écoutes,",
          "tu lui redis ce que tu as compris, et tu demandes ce qui manquera à son carnet.",
          "",
          "Les règles ci-dessous font autorité et s'appliquent intégralement, sans exception.",
          "Elles priment sur tes habitudes de conversation. En cas de conflit entre deux",
          "règles, la hiérarchie des quatre principes tranche.",
          "",
          "Tu réponds uniquement par l'objet JSON demandé. Tes bulles sont du texte simple :",
          "ni Markdown, ni listes, ni emoji.",
          "",
          "---",
          "",
          loadConversationRules(),
          "",
          "---",
          "",
          suggestionCatalogue(),
        ].join("\n"),
        // Les règles et le catalogue sont identiques d'un tour à l'autre : mis
        // en cache, ils ne sont facturés plein tarif qu'au premier tour de la
        // série.
        cache_control: { type: "ephemeral" },
      },
    ];
  }
}

// ---------------------------------------------------------------------------
// Le catalogue, écrit depuis le code
// ---------------------------------------------------------------------------

/**
 * Les puces disponibles, telles que le modèle doit les nommer.
 *
 * Écrit depuis `SUGGESTIONS` et non recopié dans le prompt : une puce ajoutée
 * au catalogue est immédiatement proposable, et une puce retirée disparaît du
 * prompt le jour même. Un catalogue recopié à la main dérive en une semaine.
 */
export function suggestionCatalogue(): string {
  const lines = [
    "## Les puces que tu peux proposer",
    "",
    "Trois au plus, par leur identifiant exact, dans `suggestionIds`. Un",
    "identifiant absent de cette liste est jeté sans avertissement.",
    "",
    "| Identifiant | Ce que le voyageur lit | Ce que ça déclenche |",
    "|---|---|---|",
  ];
  for (const id of SUGGESTION_IDS) {
    lines.push(`| \`${id}\` | « ${SUGGESTIONS[id].label} » | ${INTENT_LABELS[SUGGESTIONS[id].intent]} |`);
  }
  lines.push(
    "",
    "Les jeux habituels : sous une fiche prête, `accept` / `edit-hand` / `edit-voice` ;",
    "après un refus, `tomorrow` / `else` ; après une réponse à une question,",
    "`clear` / `another` / `resume` ; quand rien ne s'impose, aucune.",
  );
  return lines.join("\n");
}

const INTENT_LABELS: Record<string, string> = {
  send: "envoie le libellé, sans rien ouvrir",
  send_then_write: "envoie, puis ouvre le clavier",
  send_then_speak: "envoie, puis arme le micro",
  send_then_edit_transcript: "envoie, puis ouvre le texte de la fiche à corriger",
  import_photos: "ouvre la photothèque, sans rien envoyer",
};

// ---------------------------------------------------------------------------
// Ce qu'on donne à lire au modèle
// ---------------------------------------------------------------------------

/**
 * Le contexte du tour, en Markdown : le carnet, qui parle, où on en est, le
 * fil, et le message à traiter.
 *
 * Tout ce qui peut faire inventer une question déjà répondue est ici — la
 * fiche de cohérence, le souvenir en cours, les trois derniers rédigés. « Ta
 * question est déjà répondue » est le reproche numéro un d'une relecture, et
 * il se règle par le contexte, pas par une consigne de plus.
 */
export function buildUserPrompt(input: ConversationInput): string {
  const { memo, traveller, step, history, message, currentEntry, recentEntries, allows } = input;
  const lines: string[] = [];

  lines.push("## Le carnet", `Titre : ${memo.title}`);
  if (memo.theme) lines.push(`Thème : ${memo.theme}`);
  if (memo.destinationCity) lines.push(`Destination : ${memo.destinationCity}`);
  if (memo.startDate || memo.endDate) {
    lines.push(`Dates : ${dayOf(memo.startDate)} → ${dayOf(memo.endDate)}`);
  }
  if (memo.narrationPace) lines.push(`Rythme de récit choisi : ${memo.narrationPace}`);
  lines.push(`Aujourd'hui : ${dayOf(input.now)}`);

  lines.push(
    "",
    "## À qui tu parles",
    traveller.firstName ? `Prénom : ${traveller.firstName}` : "Prénom : inconnu",
    traveller.memberCount > 1
      ? `Ils sont ${traveller.memberCount} sur ce carnet : le fil est commun, chacun lit ce que tu écris.`
      : "Il est seul sur ce carnet.",
  );

  if (step) {
    lines.push(
      "",
      "## L'étape en cours",
      `Étape n°${step.number}${step.placeName ? ` — ${step.placeName}` : ""}`,
      `Du ${dayOf(step.startDate)} au ${dayOf(step.endDate)}`,
    );
  }

  const sheet = memo.coherenceSheet;
  if (sheet.people.length > 0 || sheet.places.length > 0 || sheet.lexicon.length > 0) {
    lines.push("", "## Ce que le carnet sait déjà", "_Ne redemande pas ce qui est écrit ici._");
    if (sheet.people.length > 0) {
      lines.push(`Personnes : ${sheet.people.map((person) => person.canonicalName).join(", ")}`);
    }
    if (sheet.places.length > 0) {
      lines.push(`Lieux : ${sheet.places.map((place) => place.canonicalName).join(", ")}`);
    }
    if (sheet.lexicon.length > 0) {
      lines.push(`Mots fixés : ${sheet.lexicon.map((entry) => entry.term).join(", ")}`);
    }
  }

  if (recentEntries.length > 0) {
    lines.push("", "## Les souvenirs déjà écrits", "_Les plus récents. N'y reviens pas sans raison._");
    for (const entry of recentEntries) {
      const where = entry.placeLabel ? ` — ${entry.placeLabel}` : "";
      lines.push(`- ${dayOf(entry.capturedAt)}${where} : ${truncate(entry.text, 240)}`);
    }
  }

  lines.push("", "## Le souvenir en cours");
  if (currentEntry) {
    lines.push(
      `Capté le ${dayOf(currentEntry.capturedAt)}${currentEntry.placeLabel ? ` à ${currentEntry.placeLabel}` : ""}.`,
      currentEntry.validatedAt ? "Déjà validé par le voyageur." : "Pas encore validé.",
      `Rédaction : ${REDACTION_LABELS[currentEntry.redactionStatus]}`,
      currentEntry.text ? `Texte : ${truncate(currentEntry.text, 600)}` : "Texte : pas encore disponible.",
    );
  } else {
    lines.push("Aucun. Le prochain texte qui raconte quelque chose en ouvrira un.");
  }

  lines.push("", "## Le fil", "_Du plus ancien au plus récent. Le message à traiter n'y est pas._");
  if (history.length === 0) {
    lines.push("_Vide : tu viens d'ouvrir la conversation._");
  } else {
    for (const turn of history) {
      const who = turn.author === "memo" ? "MEMO" : (turn.authorName ?? "Le voyageur");
      const body =
        turn.text !== null
          ? truncate(turn.text, HISTORY_TEXT_LIMIT)
          : turn.kind === "photos"
            ? "(des photos)"
            : "(sans texte)";
      lines.push(`- **${who}** : ${body}`);
    }
  }

  lines.push("", "## Le message à traiter", `Reçu le ${dayOf(message.sentAt)}.`);
  switch (message.kind) {
    case "voice":
      lines.push(
        message.durationSeconds
          ? `Un vocal de ${Math.round(message.durationSeconds)} secondes. C'est un souvenir.`
          : "Un vocal. C'est un souvenir.",
      );
      if (message.transcriptFailed) {
        lines.push(
          "**La transcription a échoué** : tu n'as pas entendu ce vocal. Dis-le, et propose de",
          "réenregistrer ou d'écrire. N'invente rien de son contenu.",
        );
      }
      break;
    case "photos":
      lines.push(
        `${message.photoCount} photo(s). C'est un souvenir. Tu ne les vois pas : n'en décris aucune.`,
      );
      break;
    case "text":
      lines.push("Un texte.");
      break;
  }
  if (message.text) lines.push("", `> ${message.text.replace(/\n+/g, "\n> ")}`);

  lines.push(
    "",
    "## Ce que le code autorise ce tour-ci",
    allows.roseEpineGraine
      ? "La rose, l'épine et la graine : **autorisée**. À poser en une seule bulle, si le moment s'y prête."
      : "La rose, l'épine et la graine : **interdite** ce tour-ci. `asksRoseEpineGraine` doit rester `false`.",
  );

  lines.push(
    "",
    "## Ce que tu rends",
    `- \`beats\` : une à ${MAX_BEATS} bulles, dans l'ordre où le voyageur les lira. La première`,
    `  reformule (${REFORMULATION_LIMIT} caractères au plus), la deuxième pose **la** question,`,
    `  la troisième est facultative (${ASIDE_LIMIT} caractères au plus).`,
    "- `disposition` : ce qu'est le message reçu — `memory`, `context` ou `command`.",
    "- `suggestionIds` : trois identifiants du catalogue au plus, ou aucun.",
    `- \`prompt\` : la relance de la carte du voyage, ${PROMPT_LIMIT} caractères au plus, qui se lit`,
    "  **seule**. `null` pour laisser celle en place" +
      (memo.prompt ? ` (aujourd'hui : « ${memo.prompt} »).` : "."),
    "- `asksRoseEpineGraine` : `true` seulement si tu viens de la poser.",
  );

  return lines.join("\n");
}

const REDACTION_LABELS: Record<string, string> = {
  pending: "pas commencée",
  processing: "en cours — le texte va changer",
  ready: "prête",
  failed: "elle a échoué ; le texte brut reste",
};

function dayOf(date: Date | null): string {
  return date ? date.toISOString().slice(0, 10) : "inconnue";
}

function truncate(text: string, limit: number): string {
  const clean = text.trim().replace(/\s+/g, " ");
  return clean.length > limit ? `${clean.slice(0, limit - 1)}…` : clean;
}

// ---------------------------------------------------------------------------
// Ce que le modèle rend
// ---------------------------------------------------------------------------

/**
 * Le schéma de sortie. **Pas de `pauseMilliseconds`** : le rythme est calculé
 * par le serveur sur la matière (`composeBeats`), et c'est le seul endroit où
 * il se décide — côté app comme côté modèle, on ne fait que l'appliquer.
 *
 * ⚠️ Une **fonction** et non une constante : `conversation.ts` importe ce
 * fichier (pour la fabrique) et ce fichier importe ses bornes — le cycle est
 * sain tant que rien ne les lit à l'initialisation du module. Une constante
 * ici plantait au démarrage sur « Cannot access 'MAX_BEATS' before
 * initialization », et seulement au démarrage : la compilation, elle, passait.
 */
export function replySchema() {
  return {
    type: "object",
    properties: {
      beats: {
        type: "array",
        minItems: 1,
        maxItems: MAX_BEATS,
        items: { type: "string", minLength: 1, maxLength: 400 },
        description: "Les bulles de MEMO, dans l'ordre. Texte simple, sans Markdown ni emoji.",
      },
      disposition: {
        type: "string",
        enum: ["memory", "context", "command"],
        description: "Ce qu'est le message reçu.",
      },
      suggestionIds: {
        type: "array",
        maxItems: 3,
        items: { type: "string", enum: SUGGESTION_IDS },
        description: "Des identifiants du catalogue, jamais des libellés.",
      },
      prompt: {
        type: ["string", "null"],
        maxLength: PROMPT_LIMIT,
        description: "La relance de la carte du voyage, qui se lit seule. `null` pour ne pas y toucher.",
      },
      asksRoseEpineGraine: {
        type: "boolean",
        description: "Vrai seulement si cette réponse pose la rose, l'épine et la graine.",
      },
    },
    required: ["beats", "disposition", "suggestionIds", "prompt", "asksRoseEpineGraine"],
    additionalProperties: false,
  } as const;
}

interface RawReply {
  beats: string[];
  disposition: ConversationReply["disposition"];
  suggestionIds: string[];
  prompt: string | null;
  asksRoseEpineGraine: boolean;
}

/**
 * Du JSON du modèle à une réponse du contrat : le texte est à lui, le rythme
 * est au serveur.
 */
export function toReply(raw: RawReply, received: string, model: string): ConversationReply {
  return {
    beats: composeBeats(received, raw.beats ?? []),
    disposition: raw.disposition,
    suggestionIds: (raw.suggestionIds ?? []) as SuggestionId[],
    prompt: raw.prompt,
    asksRoseEpineGraine: raw.asksRoseEpineGraine === true,
    model,
  };
}
