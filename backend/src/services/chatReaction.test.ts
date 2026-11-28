import { describe, expect, it } from "vitest";

import { READING, TAKEN, VALIDATED, reactionFor, type ReactionInput } from "./chatReaction.js";

const tour = (over: Partial<ReactionInput> = {}): ReactionInput => ({
  author: "traveller",
  suggestionId: null,
  repliedAt: new Date("2026-11-28T10:00:00Z"),
  entry: null,
  ...over,
});

const avecTransport = (kind: string) =>
  tour({ entry: { insights: { transports: [{ kind, count: 1 }] } } });

describe("la pastille d'une bulle (T296)", () => {
  it("dit « je lis » tant que MEMO n'a pas répondu", () => {
    expect(reactionFor(tour({ repliedAt: null }))).toEqual(READING);
  });

  it("dit « pris en compte » une fois le tour traité", () => {
    expect(reactionFor(tour())).toEqual(TAKEN);
  });

  it("dit le déplacement que le récit nomme", () => {
    expect(reactionFor(avecTransport("train"))?.emoji).toBe("🚂");
    expect(reactionFor(avecTransport("plane"))?.emoji).toBe("✈️");
    expect(reactionFor(avecTransport("boat"))?.emoji).toBe("⛵️");
    expect(reactionFor(avecTransport("car"))?.emoji).toBe("🚘");
  });

  it("range le métro avec le train et le taxi avec la voiture", () => {
    // Le même regroupement que l'étape (`STEP_TRANSPORT`) : une seule table
    // décide de ce qui roule sur des rails.
    expect(reactionFor(avecTransport("metro"))?.emoji).toBe("🚂");
    expect(reactionFor(avecTransport("taxi"))?.emoji).toBe("🚘");
    expect(reactionFor(avecTransport("scooter"))?.emoji).toBe("🚲");
  });

  it("garde le premier déplacement quand le récit en nomme plusieurs", () => {
    const message = tour({
      entry: {
        insights: { transports: [{ kind: "boat", count: 1 }, { kind: "walk", count: null }] },
      },
    });
    expect(reactionFor(message)?.emoji).toBe("⛵️");
  });

  it("retombe sur « pris en compte » quand les relevés sont illisibles", () => {
    // `insights` est du JSON relu défensivement : un relevé cassé ne doit pas
    // faire disparaître la pastille.
    expect(reactionFor(tour({ entry: { insights: { transports: "le train" } } }))).toEqual(TAKEN);
    expect(reactionFor(tour({ entry: { insights: null } }))).toEqual(TAKEN);
  });

  it("ne pose rien sur une puce", () => {
    // « Ça me convient » n'est pas un message que MEMO lit : c'est une
    // commande, et une pastille dessus ferait croire à un souvenir de plus.
    expect(reactionFor(tour({ suggestionId: "accept" }))).toBeNull();
    expect(reactionFor(tour({ suggestionId: "accept", repliedAt: null }))).toBeNull();
  });

  it("ne pose rien sur une bulle de MEMO, sauf le 👍 du voyageur", () => {
    expect(reactionFor(tour({ author: "memo", repliedAt: null }))).toBeNull();
    expect(reactionFor(tour({ author: "memo" }), true)).toEqual(VALIDATED);
  });

  it("ne pose pas le 👍 sur une bulle du voyageur", () => {
    // Le 👍 est une réaction **à** MEMO. Reçu par erreur sur un tour du
    // voyageur, il ne doit pas écraser l'état de ce tour.
    expect(reactionFor(tour(), true)).toEqual(TAKEN);
  });
});
