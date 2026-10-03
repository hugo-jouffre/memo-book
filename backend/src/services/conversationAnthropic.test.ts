import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import {
  AnthropicResponder,
  buildUserPrompt,
  callToActionCatalogue,
  replySchema,
  suggestionCatalogue,
  toReply,
  tripContextSchema,
} from "./conversationAnthropic.js";
import { EMPTY_TRIP_CONTEXT, questionFor } from "./tripContext.js";
import {
  EMPTY_CONVERSATION_STATE,
  InvalidReplyError,
  MIN_PAUSE_MS,
  type ConversationInput,
} from "./conversation.js";
import { EMPTY_COHERENCE_SHEET } from "./redaction.js";

/**
 * MEMO avec un modèle — **sans appeler le modèle**. Le client est doublé : ce
 * qu'on vérifie ici, c'est le contrat autour de lui, qui est tout ce qu'on
 * maîtrise. Ce que Claude répond vraiment se relit à la main, avec la grille
 * de `docs/conversation.md` § 13 (`npm run conversation:eval`).
 */

function turn(overrides: Partial<ConversationInput> = {}): ConversationInput {
  return {
    memo: {
      id: "memo",
      title: "Rome 2026",
      theme: "Gastronomie",
      destinationCity: "Rome",
      startDate: new Date("2026-09-10T00:00:00Z"),
      endDate: new Date("2026-09-30T00:00:00Z"),
      narrationPace: "daily",
      prompt: "Et ce dîner à Trastevere ?",
      coherenceSheet: {
        ...EMPTY_COHERENCE_SHEET,
        people: [{ canonicalName: "Clara", notes: "" }],
        places: [{ canonicalName: "Testaccio", notes: "" }],
      },
      state: EMPTY_CONVERSATION_STATE,
      tripContext: null,
    },
    traveller: { firstName: "Hugo", memberCount: 1, isUnlimited: false },
    step: null,
    history: [],
    message: {
      id: "m",
      kind: "text",
      text: "On a passé l’après-midi au marché avec Clara.",
      suggestionId: null,
      photoCount: 0,
      durationSeconds: null,
      transcriptFailed: false,
      sentAt: new Date("2026-09-21T10:00:00Z"),
    },
    currentEntry: null,
    recentEntries: [],
    allows: { roseEpineGraine: false, callsToAction: [] },
    now: new Date("2026-09-21T10:00:00Z"),
    ...overrides,
  };
}

const ANSWER = {
  beats: ["Tu as passé l’après-midi au marché avec Clara.", "Vous avez goûté quoi là-bas ?"],
  disposition: "memory",
  suggestionIds: ["voice", "write"],
  prompt: "Et ce marché avec Clara, ça a donné quoi ?",
  asksRoseEpineGraine: false,
  callToActionId: null,
};

/** Une question sur le prix, et la réponse du modèle qui pose le bouton. */
const PRICE_QUESTION = {
  ...turn().message,
  text: "Combien coûte l’abonnement ?",
};
const PRICE_ANSWER = {
  beats: ["L’abonnement est à 4,99 € par mois : ton récit devient illimité."],
  disposition: "command",
  suggestionIds: ["clear", "another"],
  prompt: null,
  asksRoseEpineGraine: false,
  callToActionId: "subscribe",
};

/** Un client qui rend ce qu'on lui dit de rendre, et garde ce qu'on lui a demandé. */
function client(
  payload: unknown,
  options: { stopReason?: string; text?: string } = {},
): { anthropic: Anthropic; calls: Anthropic.MessageCreateParamsNonStreaming[] } {
  const calls: Anthropic.MessageCreateParamsNonStreaming[] = [];
  const anthropic = {
    messages: {
      create: (params: Anthropic.MessageCreateParamsNonStreaming) => {
        calls.push(params);
        return Promise.resolve({
          stop_reason: options.stopReason ?? "end_turn",
          content:
            options.stopReason === "refusal"
              ? []
              : [{ type: "text", text: options.text ?? JSON.stringify(payload) }],
        });
      },
    },
  } as unknown as Anthropic;
  return { anthropic, calls };
}

describe("le prompt", () => {
  it("donne le catalogue des puces depuis le code, pas une copie", () => {
    const catalogue = suggestionCatalogue();
    expect(catalogue).toContain("`accept`");
    expect(catalogue).toContain("« Ça me convient »");
    expect(catalogue).toContain("`edit-voice`");
    // Une puce retirée du catalogue disparaît du prompt le jour même.
    expect(catalogue).not.toContain("`inexistante`");
  });

  it("donne à chaque puce son effet — « Voir ma page » n'ouvre plus « undefined »", () => {
    const catalogue = suggestionCatalogue();
    expect(catalogue).not.toContain("undefined");
    expect(catalogue).toContain("| `preview` | « Voir ma page » | ouvre l'aperçu du carnet, sans rien envoyer |");
  });

  it("ne tend jamais « Photos de test » au modèle", () => {
    expect(suggestionCatalogue()).not.toContain("photos-sample");
    expect(JSON.stringify(replySchema())).not.toContain("photos-sample");
  });

  it("donne le catalogue des boutons depuis le code, sans ceux que seul le code pose", () => {
    const catalogue = callToActionCatalogue();
    expect(catalogue).toContain("`subscribe`");
    expect(catalogue).toContain("« Découvrir l’abonnement »");
    expect(catalogue).toContain("`open_trip_settings`");
    expect(catalogue).not.toContain("daily_credit_subscribe");
    expect(catalogue).not.toContain("open_photo_settings");
  });

  it("dit au modèle quels boutons ce tour permet, ou qu'il n'y en a aucun", () => {
    expect(buildUserPrompt(turn())).toContain("Les boutons : **aucun** ce tour-ci");
    const allowing = buildUserPrompt(
      turn({ allows: { roseEpineGraine: false, callsToAction: ["subscribe", "open_trip_settings"] } }),
    );
    expect(allowing).toContain("Les boutons : `subscribe`, `open_trip_settings`");
  });

  it("dit au modèle si celui qui parle raconte déjà sans limite", () => {
    expect(buildUserPrompt(turn())).toContain("Abonnement : non");
    expect(
      buildUserPrompt(turn({ traveller: { firstName: "Hugo", memberCount: 1, isUnlimited: true } })),
    ).toContain("Abonnement : oui");
  });

  it("porte ce qui empêche de redemander ce qu'on sait déjà", () => {
    const prompt = buildUserPrompt(
      turn({
        currentEntry: {
          id: "e1",
          text: "Le marché de Testaccio, en fin de matinée.",
          redactionStatus: "ready",
          validatedAt: null,
          capturedAt: new Date("2026-09-21T09:00:00Z"),
          placeLabel: "Testaccio",
        },
        recentEntries: [
          {
            capturedAt: new Date("2026-09-20T09:00:00Z"),
            placeLabel: "Trastevere",
            title: null,
            text: "Un dîner tardif, place Santa Maria.",
          },
        ],
      }),
    );

    expect(prompt).toContain("Clara");
    expect(prompt).toContain("Testaccio");
    expect(prompt).toContain("Un dîner tardif");
    expect(prompt).toContain("Pas encore validé");
    expect(prompt).toContain("Rome 2026");
  });

  it("dit noir sur blanc quand la rose, l'épine et la graine est interdite", () => {
    expect(buildUserPrompt(turn())).toContain("**interdite**");
    expect(buildUserPrompt(turn({ allows: { roseEpineGraine: true, callsToAction: [] } }))).toContain(
      "**autorisée**",
    );
  });

  it("dit qu'un vocal n'a pas été entendu au lieu de le laisser inventer", () => {
    const prompt = buildUserPrompt(
      turn({
        message: { ...turn().message, kind: "voice", text: null, transcriptFailed: true },
      }),
    );
    expect(prompt).toContain("La transcription a échoué");
    expect(prompt).toContain("N'invente rien");
  });

  it("dit à MEMO qu'ils sont plusieurs sur le carnet", () => {
    expect(
      buildUserPrompt(turn({ traveller: { firstName: "Hugo", memberCount: 3, isUnlimited: false } })),
    ).toContain("Ils sont 3 sur ce carnet");
  });
});

describe("le rythme", () => {
  it("est calculé par le serveur, jamais rendu par le modèle", () => {
    const reply = toReply(
      { ...ANSWER, disposition: "memory" },
      "On a passé l’après-midi au marché avec Clara.",
      "claude-sonnet-5",
    );

    expect(reply.beats).toHaveLength(2);
    for (const beat of reply.beats) {
      expect(beat.pauseMilliseconds).toBeGreaterThanOrEqual(MIN_PAUSE_MS);
    }
    // La première pause est le temps de **lire** ce qu'on vient de recevoir :
    // elle dépend du message, pas de la réponse.
    expect(reply.beats[0]!.pauseMilliseconds).toBeGreaterThan(reply.beats[1]!.pauseMilliseconds);
  });
});

describe("un tour", () => {
  it("rend les bulles du modèle, avec sa signature", async () => {
    const { anthropic, calls } = client(ANSWER);
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").reply(turn());

    expect(reply.beats.map((beat) => beat.text)).toEqual(ANSWER.beats);
    expect(reply.disposition).toBe("memory");
    expect(reply.suggestionIds).toEqual(["voice", "write"]);
    expect(reply.model).toBe("claude-sonnet-5");

    expect(calls).toHaveLength(1);
    expect(calls[0]!.model).toBe("claude-sonnet-5");
    // Les règles sont le fichier d'`agents/`, et elles sont mises en cache.
    const system = calls[0]!.system as Anthropic.TextBlockParam[];
    expect(system[0]!.text).toContain("Tu es **MEMO**");
    expect(system[0]!.cache_control).toEqual({ type: "ephemeral" });
  });

  it("répond une commande sans appeler le modèle", async () => {
    const { anthropic, calls } = client(ANSWER);
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").reply(
      turn({ message: { ...turn().message, suggestionId: "accept" } }),
    );

    expect(calls).toHaveLength(0);
    expect(reply.model).toBe("scripted");
    expect(reply.suggestionIds).toEqual(["dictate", "photos", "later"]);
  });

  it("jette une puce que le catalogue ne connaît pas", async () => {
    const { anthropic } = client({ ...ANSWER, suggestionIds: ["voice", "inventée"] });
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").reply(turn());
    expect(reply.suggestionIds).toEqual(["voice"]);
  });

  it("ne retient pas la rose, l'épine et la graine quand le code l'interdit", async () => {
    const { anthropic } = client({ ...ANSWER, asksRoseEpineGraine: true });
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").reply(turn());
    expect(reply.asksRoseEpineGraine).toBe(false);
  });

  it("garde le bouton quand le tour le permet", async () => {
    const { anthropic, calls } = client(PRICE_ANSWER);
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").reply(
      turn({
        message: PRICE_QUESTION,
        allows: { roseEpineGraine: false, callsToAction: ["subscribe", "open_trip_settings"] },
      }),
    );
    expect(reply.callToActionId).toBe("subscribe");
    // Le catalogue des boutons voyage avec les règles, dans le prompt système en cache.
    const system = calls[0]!.system as Anthropic.TextBlockParam[];
    expect(system[0]!.text).toContain("## Les boutons que tu peux poser sous ta réponse");
  });

  it("jette un bouton que le tour ne permet pas, ou que le catalogue ne connaît pas", async () => {
    const notAllowed = client(PRICE_ANSWER);
    const reply = await new AnthropicResponder(notAllowed.anthropic, "claude-sonnet-5").reply(
      turn({ message: PRICE_QUESTION, allows: { roseEpineGraine: false, callsToAction: ["open_trip_settings"] } }),
    );
    expect(reply.callToActionId).toBeNull();
    // La réponse elle-même reste : ce qui est en trop tombe, le reste parle.
    expect(reply.beats).toHaveLength(1);

    const invented = client({ ...PRICE_ANSWER, callToActionId: "open_url" });
    const replyInvented = await new AnthropicResponder(invented.anthropic, "claude-sonnet-5").reply(
      turn({ message: PRICE_QUESTION, allows: { roseEpineGraine: false, callsToAction: ["subscribe"] } }),
    );
    expect(replyInvented.callToActionId).toBeNull();
  });

  it("refuse deux questions dans un même tour — le repli parlera", async () => {
    const { anthropic } = client({
      ...ANSWER,
      beats: ["Tu étais où ?", "Et avec qui ?"],
    });
    await expect(new AnthropicResponder(anthropic, "claude-sonnet-5").reply(turn())).rejects.toThrow(
      InvalidReplyError,
    );
  });

  it("lève quand le modèle refuse, se coupe, ou rend du non-JSON", async () => {
    const refusal = client(ANSWER, { stopReason: "refusal" });
    await expect(
      new AnthropicResponder(refusal.anthropic, "claude-sonnet-5").reply(turn()),
    ).rejects.toThrow(/refusé/);

    const cut = client(ANSWER, { stopReason: "max_tokens" });
    await expect(
      new AnthropicResponder(cut.anthropic, "claude-sonnet-5").reply(turn()),
    ).rejects.toThrow(/avant la fin/);

    const garbage = client(ANSWER, { text: "désolé, je ne peux pas" });
    await expect(
      new AnthropicResponder(garbage.anthropic, "claude-sonnet-5").reply(turn()),
    ).rejects.toThrow();
  });
});

describe("le contexte du voyage", () => {
  const contextTurn = (text: string) => ({
    context: { ...EMPTY_TRIP_CONTEXT, departureCountry: "France", awaiting: "companions" as const },
    memo: { title: "Malaisie 2026", destinationName: "Malaisie", destinationCity: "Kuala Lumpur" },
    travellerFirstName: "Hugo",
    history: [],
    text,
    now: new Date("2026-09-28T10:00:00Z"),
  });

  const EXTRACTED = {
    acknowledgement: "Clara et Léo t’accompagnent, je note.",
    departureCountry: null,
    travellerCount: 3,
    companions: [
      { name: "Clara", relation: "ma femme" },
      { name: "Léo", relation: null },
    ],
    dates: null,
    tripType: null,
    itinerary: null,
    occasion: null,
    narrationMoment: "during",
    notes: null,
  };

  it("extrait et reformule, en disant au modèle ce qui est su et ce qui vient d'être demandé", async () => {
    const { anthropic, calls } = client(EXTRACTED);
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").gatherContext(
      contextTurn("Je pars avec ma femme Clara et Léo"),
    );

    expect(reply.update.companions).toEqual(EXTRACTED.companions);
    expect(reply.update.travellerCount).toBe(3);
    expect(reply.acknowledgement).toBe(EXTRACTED.acknowledgement);

    const prompt = calls[0]!.messages[0]!.content as string;
    expect(prompt).toContain("Pays de départ : France");
    expect(prompt).toContain(questionFor("companions", contextTurn("").context));
    expect(prompt).toContain("> Je pars avec ma femme Clara et Léo");
  });

  it("jette un accusé qui pose une question : la question appartient au code", async () => {
    const { anthropic } = client({ ...EXTRACTED, acknowledgement: "Clara et Léo, super ! Vous partez quand ?" });
    const reply = await new AnthropicResponder(anthropic, "claude-sonnet-5").gatherContext(contextTurn("Clara et Léo"));
    expect(reply.acknowledgement).toBeNull();
  });

  it("lève sur un refus : le job passe au repli", async () => {
    const { anthropic } = client(EXTRACTED, { stopReason: "refusal" });
    await expect(
      new AnthropicResponder(anthropic, "claude-sonnet-5").gatherContext(contextTurn("Clara")),
    ).rejects.toThrow();
  });

  it("n'emploie aucune borne de tableau dans le schéma, que l'API refuse", () => {
    expect(JSON.stringify(tripContextSchema())).not.toMatch(/minItems|maxItems/);
  });
});

describe("le schéma de la réponse", () => {
  it("n'emploie aucune borne de tableau, que l'API refuse", () => {
    expect(JSON.stringify(replySchema())).not.toMatch(/minItems|maxItems/);
  });

  it("exige le bouton, choisi parmi ceux du modèle ou `null`", () => {
    const schema = replySchema();
    expect(schema.required).toContain("callToActionId");
    expect(schema.properties.callToActionId.enum).toEqual([
      "subscribe",
      "open_trip_settings",
      "open_preview",
      "import_photos",
      null,
    ]);
  });
});
