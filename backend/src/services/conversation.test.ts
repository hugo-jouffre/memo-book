import { describe, expect, it } from "vitest";
import type { Env } from "../env.js";
import {
  EMPTY_CONVERSATION_STATE,
  FakeResponder,
  createResponder,
  InvalidReplyError,
  composeBeats,
  firstSentence,
  nextConversationState,
  parseConversationState,
  scriptedReply,
  validateReply,
  type ConversationInput,
  type ConversationReply,
} from "./conversation.js";
import { ANSWERS, REFUSAL, ROTATION, SUGGESTIONS } from "./conversationCopy.js";
import { HeuristicResponder, readSignals } from "./conversationHeuristics.js";
import { EMPTY_COHERENCE_SHEET } from "./redaction.js";

/**
 * MEMO sans modèle, phrase par phrase — le portage de `ChatResponderTests`
 * (iOS), pour que le repli côté serveur réponde ce que l'app répondait seule.
 */

function turn(
  text: string,
  overrides: Partial<ConversationInput> & { history?: ConversationInput["history"] } = {},
): ConversationInput {
  return {
    memo: {
      id: "memo",
      title: "Rome 2026",
      theme: null,
      destinationCity: "Rome",
      startDate: null,
      endDate: null,
      narrationPace: null,
      prompt: null,
      coherenceSheet: EMPTY_COHERENCE_SHEET,
      state: EMPTY_CONVERSATION_STATE,
    },
    traveller: { firstName: "Hugo", memberCount: 1 },
    step: null,
    history: [],
    message: {
      id: "m",
      kind: "text",
      text,
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

const memoSaid = (texts: string[]): ConversationInput["history"] =>
  texts.map((text) => ({
    author: "memo",
    authorName: null,
    kind: "text",
    text,
    disposition: null,
    sentAt: new Date(),
  }));

describe("les signaux", () => {
  it("relève un lieu derrière une préposition forte, verbatim", () => {
    expect(readSignals("On est montés à Trastevere ce soir.").places).toEqual(["Trastevere"]);
  });

  it("ne prend pas un verbe pour un lieu générique", () => {
    expect(readSignals("on a marché toute la journée").places).toEqual([]);
    expect(readSignals("on a pris un café au marché couvert").places).toEqual(["café", "marché"]);
  });

  it("distingue une personne d'un lieu par la préposition", () => {
    const signals = readSignals("On a dîné avec Léa et Tom à Testaccio.");
    expect(signals.people).toEqual(["Léa", "Tom"]);
    expect(signals.places).toEqual(["Testaccio"]);
  });

  it("ignore la majuscule en tête de phrase", () => {
    expect(readSignals("Hier on a dormi. Camille est arrivée.").people).toEqual([]);
  });

  it("recopie un chiffre avec son unité, sans le convertir", () => {
    expect(readSignals("On a fait 12km puis 35 euros de taxi").figures).toEqual(["12 km", "35 €"]);
  });

  it("lit une question et son sujet", () => {
    const signals = readSignals("Comment je corrige un texte ?");
    expect(signals.isQuestion).toBe(true);
    expect(signals.subject).toBe("corrections");
  });

  it("pèse l'humeur avec les intensifieurs", () => {
    expect(readSignals("c'était vraiment magnifique").mood).toBe("positive");
    expect(readSignals("journée épuisante, on a tout raté, galère").mood).toBe("negative");
  });

  it("ne lit un refus doux que dans un message très court", () => {
    expect(readSignals("demain").isRefusal).toBe(true);
    expect(readSignals("demain on part pour Lisbonne, j'ai hâte de voir la mer").isRefusal).toBe(false);
  });
});

describe("le moteur de règles", () => {
  const memo = new HeuristicResponder();

  it("fait gagner le refus sur la question", async () => {
    const reply = await memo.reply(turn("Pas envie ce soir, comment on arrête ?"));
    expect(reply.beats.map((beat) => beat.text)).toEqual([REFUSAL]);
    expect(reply.disposition).toBe("command");
    expect(reply.suggestionIds).toEqual(["tomorrow", "else"]);
  });

  it("répond à une question au lieu de relancer", async () => {
    const reply = await memo.reply(turn("Combien coûte l'abonnement ?"));
    expect(reply.beats[0]?.text).toBe(ANSWERS.subscription);
    expect(reply.suggestionIds).toEqual(["clear", "another", "resume"]);
  });

  it("accuse une émotion difficile avant toute demande", async () => {
    const reply = await memo.reply(turn("Journée épuisante, on a tout raté et j'étais malade."));
    expect(reply.beats[0]?.text).toContain("Ça n’a pas dû être simple");
  });

  it("répète un lieu trouvé, verbatim", async () => {
    const reply = await memo.reply(
      turn("On est allés à Trastevere hier soir, il y avait du monde partout dans les rues."),
    );
    expect(reply.beats[0]?.text).toBe("Trastevere, je note. Qu’est-ce qui t’a marqué là-bas ?");
    expect(reply.disposition).toBe("memory");
  });

  it("classe un texte court sur un souvenir en cours comme une précision", async () => {
    const reply = await memo.reply(
      turn("Avec Clara.", {
        currentEntry: {
          id: "e",
          text: "…",
          redactionStatus: "ready",
          validatedAt: null,
          capturedAt: new Date(),
          placeLabel: null,
        },
      }),
    );
    expect(reply.disposition).toBe("context");
  });

  it("ne dit jamais deux fois la même relance de suite", async () => {
    const first = await memo.reply(turn("bonne journée ici aujourd'hui rien de spécial"));
    const second = await memo.reply(
      turn("bonne journée ici aujourd'hui rien de spécial", {
        history: memoSaid([first.beats[0]!.text]),
      }),
    );
    expect(second.beats[0]?.text).not.toBe(first.beats[0]?.text);
  });

  it("épuise la rotation neutre avant de se répéter", async () => {
    const said: string[] = [];
    for (let index = 0; index < ROTATION.length; index += 1) {
      const reply = await memo.reply(
        turn("bonne journée ici aujourd'hui rien de spécial", { history: memoSaid(said) }),
      );
      const text = reply.beats[0]!.text;
      expect(said).not.toContain(text);
      said.push(text);
    }
  });

  it("est déterministe et respire : jamais une bulle à zéro milliseconde", async () => {
    const input = turn("On a marché jusqu'au marché de Testaccio avec Clara ce matin.");
    const a = await memo.reply(input);
    const b = await memo.reply(input);
    expect(a).toEqual(b);
    expect(a.beats.every((beat) => beat.pauseMilliseconds >= 450)).toBe(true);
  });

  it("reformule un vocal entre guillemets puis propose le trio", async () => {
    const reply = await memo.reply(
      turn("On est partis tôt ce matin. Il faisait déjà chaud.", {
        message: {
          id: "v",
          kind: "voice",
          text: "On est partis tôt ce matin. Il faisait déjà chaud.",
          suggestionId: null,
          photoCount: 0,
          durationSeconds: 37,
          transcriptFailed: false,
          sentAt: new Date(),
        },
      }),
    );
    expect(reply.beats).toHaveLength(2);
    expect(reply.beats[0]?.text).toBe("Tu me racontes que « On est partis tôt ce matin ».");
    expect(reply.suggestionIds).toEqual(["accept", "edit-hand", "edit-voice"]);
    expect(reply.prompt).toBe("Comment ça se passe à Rome ?");
  });

  it("pose la rose, l'épine et la graine quand le code l'autorise", async () => {
    const reply = await memo.reply(
      turn("On a fini la journée sur une terrasse, tranquilles.", {
        allows: { roseEpineGraine: true },
      }),
    );
    expect(reply.asksRoseEpineGraine).toBe(true);
    expect(reply.beats[0]?.text).toContain("la rose, l’épine et la graine");
  });
});

describe("les commandes et les garde-fous", () => {
  it("répond à une puce sans modèle, et à une commande silencieuse aussi", () => {
    const accept = scriptedReply("accept", SUGGESTIONS.accept.label);
    expect(accept?.beats[0]?.text).toBe("C’est enregistré. Ton carnet compte une étape de plus.");
    expect(accept?.disposition).toBe("command");
    expect(scriptedReply("transcript_edited", "")?.suggestionIds).toEqual(["dictate", "photos", "later"]);
    expect(scriptedReply("else", "")).toBeNull();
    expect(scriptedReply(null, "")).toBeNull();
  });

  it("refuse deux questions dans un tour, et borne la relance", () => {
    const base: ConversationReply = {
      beats: composeBeats("x", ["Tu étais où ?", "Et avec qui ?"]),
      disposition: "memory",
      suggestionIds: ["voice", "inconnue" as never],
      prompt: "x".repeat(200),
      asksRoseEpineGraine: true,
      model: "test",
    };
    expect(() => validateReply(base, turn("x"))).toThrow(InvalidReplyError);

    const valid = validateReply(
      { ...base, beats: composeBeats("x", ["Tu étais où ?", "Je note."]) },
      turn("x"),
    );
    expect(valid.suggestionIds).toEqual(["voice"]);
    expect(valid.prompt).toHaveLength(90);
    expect(valid.asksRoseEpineGraine).toBe(false);
  });

  it("relit l'état de conversation sans se laisser casser", () => {
    expect(parseConversationState(null)).toEqual(EMPTY_CONVERSATION_STATE);
    expect(parseConversationState({ roseEpineGraineAskedFor: ["2026-09-21", 3] })).toEqual({
      roseEpineGraineAskedFor: ["2026-09-21"],
    });
    const next = nextConversationState(
      EMPTY_CONVERSATION_STATE,
      { ...scriptedReply("accept", "")!, asksRoseEpineGraine: true },
      "2026-09-21",
    );
    expect(next.roseEpineGraineAskedFor).toEqual(["2026-09-21"]);
  });

  it("tronque une reformulation trop longue à la première phrase", () => {
    expect(firstSentence("Première phrase. Deuxième phrase.")).toBe("Première phrase");
    expect(firstSentence("a".repeat(300))).toHaveLength(120);
  });

  it("le répondeur simulé est lisible et pilotable", async () => {
    const fake = new FakeResponder([{ prompt: "Relance forcée" }]);
    const reply = await fake.reply(turn("Une longue journée à marcher dans Rome sous le soleil."));
    expect(reply.model).toBe("fake");
    expect(reply.prompt).toBe("Relance forcée");
    expect(reply.disposition).toBe("memory");
    expect(fake.calls).toBe(1);
  });

  /**
   * Les trois paliers de `docs/conversation.md` § 12 — et, accessoirement, le
   * garde-fou d'une panne qui ne se voyait qu'au démarrage : ce fichier charge
   * `conversation.ts` **en premier**, l'ordre exact qui cassait le serveur
   * quand `conversationAnthropic.ts` lisait les bornes à l'initialisation du
   * module (« Cannot access 'MAX_BEATS' before initialization »). Le typecheck
   * et les tests passaient ; seul `npm run dev` tombait.
   */
  it("choisit qui répond selon ce dont on dispose", () => {
    const env = (live: boolean, key: string) =>
      ({ live, ANTHROPIC_API_KEY: key, ANTHROPIC_CONVERSATION_MODEL: "claude-sonnet-5" }) as Env;

    expect(createResponder(env(false, "sk-test")).constructor.name).toBe("FakeResponder");
    expect(createResponder(env(true, "")).constructor.name).toBe("HeuristicResponder");
    expect(createResponder(env(true, "sk-test")).constructor.name).toBe("AnthropicResponder");
  });
});
