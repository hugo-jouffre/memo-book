import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import {
  AnthropicResponder,
  buildUserPrompt,
  suggestionCatalogue,
  toReply,
} from "./conversationAnthropic.js";
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
    },
    traveller: { firstName: "Hugo", memberCount: 1 },
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
    allows: { roseEpineGraine: false },
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
    expect(buildUserPrompt(turn({ allows: { roseEpineGraine: true } }))).toContain("**autorisée**");
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
    expect(buildUserPrompt(turn({ traveller: { firstName: "Hugo", memberCount: 3 } }))).toContain(
      "Ils sont 3 sur ce carnet",
    );
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
