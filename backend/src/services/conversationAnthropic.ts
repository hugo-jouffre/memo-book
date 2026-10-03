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
  type TripContextTurnInput,
  type TripContextTurnReply,
} from "./conversation.js";
import { tripDate } from "./localCalendar.js";
import { describeTripContext, questionFor, type TripContextUpdate } from "./tripContext.js";
import {
  CALLS_TO_ACTION,
  MODEL_CALL_TO_ACTION_IDS,
  isCallToActionId,
  type CallToActionKind,
} from "./callsToAction.js";
import {
  MODEL_SUGGESTION_IDS,
  OPENING_TEXT,
  SUGGESTIONS,
  SUGGESTION_SETS,
  type SuggestionId,
  type SuggestionIntent,
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
 * retour, celui des boutons depuis `callsToAction.ts` (un identifiant, jamais
 * un libellé : le modèle ne choisit que parmi ceux que le tour permet), la
 * rose/épine/graine n'est retenue que si le code l'autorisait, et
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

  /**
   * Écoute un tour du contexte du voyage. Le modèle **extrait** ce qui a été
   * dit et le reformule en une phrase ; il ne pose aucune question — c'est le
   * code qui sait ce qui manque et qui demande (`tripContext.questionFor`).
   */
  async gatherContext(input: TripContextTurnInput): Promise<TripContextTurnReply> {
    const response = await this.client.messages.create({
      model: this.model,
      max_tokens: 2_000,
      thinking: { type: "adaptive" },
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: tripContextSchema() },
      },
      system: [{ type: "text", text: TRIP_CONTEXT_SYSTEM, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: buildTripContextPrompt(input) }],
    });

    if (response.stop_reason === "refusal") throw new Error("Le modèle a refusé ce tour de contexte.");
    if (response.stop_reason === "max_tokens") throw new Error("La réponse s'est arrêtée avant la fin.");
    const text = response.content.find((block) => block.type === "text")?.text;
    if (!text) throw new Error("Le modèle n'a produit aucun texte exploitable.");

    const raw = JSON.parse(text) as RawTripContext;
    const acknowledgement = raw.acknowledgement?.trim() ?? "";
    return {
      update: {
        departureCountry: raw.departureCountry,
        travellerCount: raw.travellerCount,
        companions: raw.companions,
        dates: raw.dates,
        tripType: raw.tripType,
        itinerary: raw.itinerary,
        occasion: raw.occasion,
        narrationMoment: raw.narrationMoment,
        notes: raw.notes,
      },
      // L'accusé ne pose pas de question — la question est au code. Une
      // phrase qui en pose une, ou trop longue, est jetée : le code accuse.
      acknowledgement:
        acknowledgement.length > 0 &&
        acknowledgement.length <= REFORMULATION_LIMIT &&
        !/[?？]/.test(acknowledgement)
          ? acknowledgement
          : null,
      model: this.model,
    };
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
          "",
          callToActionCatalogue(),
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
 * Sans « Photos de test », que seul le code pose, hors production
 * (`MODEL_SUGGESTION_IDS`).
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
  for (const id of MODEL_SUGGESTION_IDS) {
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

/**
 * Typé sur `SuggestionIntent` : une intention ajoutée au catalogue sans sa
 * ligne ici ne compile plus. `open_preview` manquait, et la puce « Voir ma
 * page » arrivait au modèle avec « undefined » pour effet (03/10/2026).
 */
const INTENT_LABELS: Record<SuggestionIntent, string> = {
  send: "envoie le libellé, sans rien ouvrir",
  send_then_write: "envoie, puis ouvre le clavier",
  send_then_speak: "envoie, puis arme le micro",
  send_then_edit_transcript: "envoie, puis ouvre le texte de la fiche à corriger",
  import_photos: "ouvre la photothèque, sans rien envoyer",
  open_preview: "ouvre l'aperçu du carnet, sans rien envoyer",
};

/**
 * Les boutons que le modèle peut poser sous sa dernière bulle, écrits depuis
 * `CALLS_TO_ACTION` pour la même raison que les puces. Seulement ceux qu'il a
 * le droit de choisir (`allowedForModel`) ; **quand** les poser est dans
 * `agents/agent-conversation.md`, et **lesquels ce tour-ci** dans le prompt du
 * tour — le code les a déjà filtrés (`callsToActionAllowed`).
 */
export function callToActionCatalogue(): string {
  const lines = [
    "## Les boutons que tu peux poser sous ta réponse",
    "",
    "Un au plus, rarement, par son identifiant exact dans `callToActionId` — et",
    "seulement s'il figure parmi les boutons que le code autorise ce tour-ci. Sinon",
    "`null`. Tu n'écris ni le libellé ni l'action : l'app les connaît. Un identifiant",
    "non autorisé est jeté sans avertissement.",
    "",
    "| Identifiant | Ce que le voyageur lit | Ce que ça ouvre |",
    "|---|---|---|",
  ];
  for (const id of MODEL_CALL_TO_ACTION_IDS) {
    const definition = CALLS_TO_ACTION[id];
    lines.push(`| \`${id}\` | « ${definition.label} » | ${KIND_LABELS[definition.kind]} |`);
  }
  return lines.join("\n");
}

const KIND_LABELS: Record<CallToActionKind, string> = {
  subscribe: "l'offre d'abonnement",
  open_trip_settings: "les réglages du voyage (rythme des relances, crédit du jour, co-voyageurs)",
  open_preview: "l'aperçu du carnet",
  import_photos: "la photothèque, pour ajouter des photos",
  open_photo_settings: "les Réglages de l'iPhone, pour l'accès aux photos",
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
    lines.push(`Dates : ${tripDayOf(memo.startDate)} → ${tripDayOf(memo.endDate)}`);
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
    traveller.isUnlimited
      ? "Abonnement : oui — son récit est illimité, le crédit du jour ne le concerne pas."
      : "Abonnement : non — il raconte sur le crédit du jour du voyage.",
  );

  if (step) {
    lines.push(
      "",
      "## L'étape en cours",
      `Étape n°${step.number}${step.placeName ? ` — ${step.placeName}` : ""}`,
      `Du ${tripDayOf(step.startDate)} au ${tripDayOf(step.endDate)}`,
    );
  }

  const known = describeTripContext(memo.tripContext, traveller.firstName);
  if (known.length > 0) {
    lines.push(
      "",
      "## Le contexte du voyage",
      "_Posé par le voyageur avant la première étape. Ne redemande rien de ce qui est ici :",
      "ces compagnons sont connus, ces dates aussi._",
      ...known,
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
    allows.callsToAction.length > 0
      ? `Les boutons : ${allows.callsToAction.map((id) => `\`${id}\``).join(", ")} — un au plus, et ` +
          "seulement si ta réponse l'appelle. Le plus souvent, aucun."
      : "Les boutons : **aucun** ce tour-ci. `callToActionId` doit rester `null`.",
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
    "- `callToActionId` : un bouton parmi ceux que le code autorise ce tour-ci, ou `null` —",
    "  presque toujours `null`.",
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

/** Une date de voyage ou d'étape : un minuit local, pas un instant (`tripDate`). */
function tripDayOf(date: Date | null): string {
  return date ? tripDate(date) : "inconnue";
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
 * ⚠️ **Les bornes vivent dans les descriptions, pas dans le schéma.** L'API
 * refuse `minItems`/`maxItems` sur un tableau (400 `invalid_request_error`), et
 * on ne l'apprend qu'au premier appel réel : un client doublé accepte
 * n'importe quel schéma. Ce n'est pas une perte — `validateReply` fait déjà
 * respecter les mêmes bornes, et lui refuse une réponse au lieu de la tronquer.
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
        items: { type: "string" },
        description:
          `Les bulles de MEMO, dans l'ordre : une à ${MAX_BEATS}, jamais plus. ` +
          "Texte simple, sans Markdown ni emoji.",
      },
      disposition: {
        type: "string",
        enum: ["memory", "context", "command"],
        description: "Ce qu'est le message reçu.",
      },
      suggestionIds: {
        type: "array",
        items: { type: "string", enum: MODEL_SUGGESTION_IDS },
        description: "Trois identifiants du catalogue au plus, jamais des libellés.",
      },
      prompt: {
        type: ["string", "null"],
        description:
          `La relance de la carte du voyage, ${PROMPT_LIMIT} caractères au plus, qui se lit ` +
          "seule. `null` pour ne pas y toucher.",
      },
      asksRoseEpineGraine: {
        type: "boolean",
        description: "Vrai seulement si cette réponse pose la rose, l'épine et la graine.",
      },
      // Même forme que `narrationMoment` : une chaîne de l'enum, ou `null`.
      // L'enum ne contient que les boutons que le modèle a le droit de choisir ;
      // ceux de **ce** tour, c'est `validateReply` qui les fait respecter.
      callToActionId: {
        type: ["string", "null"],
        enum: [...MODEL_CALL_TO_ACTION_IDS, null],
        description:
          "Le bouton sous ta dernière bulle, parmi ceux que le code autorise ce tour-ci. " +
          "Presque toujours null.",
      },
    },
    required: [
      "beats",
      "disposition",
      "suggestionIds",
      "prompt",
      "asksRoseEpineGraine",
      "callToActionId",
    ],
    additionalProperties: false,
  } as const;
}

interface RawReply {
  beats: string[];
  disposition: ConversationReply["disposition"];
  suggestionIds: string[];
  prompt: string | null;
  asksRoseEpineGraine: boolean;
  callToActionId: string | null;
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
    // Inconnu → `null` ici ; non permis ce tour-ci → `null` dans `validateReply`.
    callToActionId: isCallToActionId(raw.callToActionId) ? raw.callToActionId : null,
    model,
  };
}

// ---------------------------------------------------------------------------
// Le contexte du voyage
// ---------------------------------------------------------------------------

const TRIP_CONTEXT_SYSTEM = [
  "Tu es MEMO, la voix de MemoBook. Avant la première étape de son carnet, le voyageur te",
  "raconte le contexte de son voyage. Ton travail : **extraire** ce qu'il a dit, et le lui",
  "redire en une phrase. Tu ne poses aucune question : le code demandera ce qui manque.",
  "",
  "Règles, sans exception :",
  "- N'invente rien. Un champ que le message ne dit pas vaut `null` (ou une liste vide).",
  "- Ne redis pas ce qui est déjà connu : ne renvoie que ce que **ce** message apprend.",
  "- `travellerCount` compte **le narrateur compris**. « Je pars avec Clara et Léo » = 3.",
  "  « Seul », « en solo » = 1. « En couple » = 2.",
  "- `companions` : les autres voyageurs, **jamais le narrateur**. Le prénom exactement",
  "  comme il est dit, sans le compléter ni le corriger. `relation` : ce qu'il dit du lien",
  "  (« ma femme », « un ami d'enfance »), sinon `null`.",
  "- `departureCountry` : le **pays** d'où il part, en français (« France »). Une ville de",
  "  départ donne son pays seulement si c'est sans ambiguïté (Lyon → France).",
  "- `dates` : les dates comme il les dit, en clair (« du 12 au 26 septembre 2026 »).",
  "  Tu peux compléter l'année avec la date du jour si elle est évidente.",
  "- `tripType` : quelques mots (« road trip en van », « trek », « city trip »).",
  "- `narrationMoment` : `before` s'il n'est pas encore parti, `during` s'il y est,",
  "  `after` s'il est rentré — seulement si c'est dit ou évident.",
  "- `notes` : ce qui éclaire le récit et n'entre nulle part ailleurs, une ou deux phrases.",
  "- `acknowledgement` : une phrase, tutoiement, 160 caractères au plus, qui reprend ses",
  "  mots. Pas de question, pas d'emoji, pas de Markdown. Si le message ne dit rien du",
  "  contexte, dis simplement que tu as noté.",
  "",
  "Tu réponds uniquement par l'objet JSON demandé.",
].join("\n");

export function buildTripContextPrompt(input: TripContextTurnInput): string {
  const lines: string[] = ["## Le carnet", `Titre : ${input.memo.title}`];
  const destination = [input.memo.destinationCity, input.memo.destinationName].filter(Boolean).join(", ");
  if (destination) lines.push(`Destination : ${destination}`);
  lines.push(`Aujourd'hui : ${dayOf(input.now)}`);
  lines.push("", "## Le narrateur", input.travellerFirstName ? `Prénom : ${input.travellerFirstName}` : "Prénom : inconnu");

  const known = describeTripContext(input.context, input.travellerFirstName);
  lines.push("", "## Ce qu'on sait déjà du voyage", ...(known.length > 0 ? known : ["_Rien encore._"]));
  if (input.context.awaiting) {
    lines.push(
      "",
      "## La question que MEMO vient de poser",
      questionFor(input.context.awaiting, input.context),
      "_Le message y répond probablement._",
    );
  }

  const recent = input.history.slice(-6);
  if (recent.length > 0) {
    lines.push("", "## Les derniers tours du fil");
    for (const turn of recent) {
      const who = turn.author === "memo" ? "MEMO" : (turn.authorName ?? "Le voyageur");
      if (turn.text) lines.push(`- **${who}** : ${truncate(turn.text, 400)}`);
    }
  }

  lines.push("", "## Le message à écouter", `> ${input.text.replace(/\n+/g, "\n> ")}`);
  return lines.join("\n");
}

/** Même prudence que `replySchema` : aucune borne de tableau dans le schéma, l'API les refuse. */
export function tripContextSchema() {
  const nullableString = (description: string) => ({ type: ["string", "null"], description });
  return {
    type: "object",
    properties: {
      acknowledgement: { type: "string", description: "Une phrase qui reprend ses mots, sans question." },
      departureCountry: nullableString("Le pays de départ, en français."),
      travellerCount: { type: ["integer", "null"], description: "Voyageurs, narrateur compris." },
      companions: {
        type: "array",
        description: "Les autres voyageurs, jamais le narrateur.",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            relation: { type: ["string", "null"] },
          },
          required: ["name", "relation"],
          additionalProperties: false,
        },
      },
      dates: nullableString("Les dates du voyage, en clair."),
      tripType: nullableString("Le genre de voyage, en quelques mots."),
      itinerary: nullableString("Les lieux prévus, dans l'ordre."),
      occasion: nullableString("L'occasion : lune de miel, anniversaire…"),
      narrationMoment: {
        type: ["string", "null"],
        enum: ["before", "during", "after", null],
        description: "Avant, pendant ou après le voyage.",
      },
      notes: nullableString("Ce qui éclaire le récit et n'entre nulle part ailleurs."),
    },
    required: [
      "acknowledgement",
      "departureCountry",
      "travellerCount",
      "companions",
      "dates",
      "tripType",
      "itinerary",
      "occasion",
      "narrationMoment",
      "notes",
    ],
    additionalProperties: false,
  } as const;
}

interface RawTripContext extends Required<{ [K in keyof TripContextUpdate]: TripContextUpdate[K] }> {
  acknowledgement: string;
}
