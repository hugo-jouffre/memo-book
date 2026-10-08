import { describe, expect, it } from "vitest";
import type { Env } from "../env.js";
import {
  EMPTY_CONVERSATION_STATE,
  FakeResponder,
  callsToActionAllowed,
  createResponder,
  InvalidReplyError,
  composeBeats,
  firstSentence,
  isTooShortToKeep,
  nextConversationState,
  parseConversationState,
  scriptedReply,
  validateReply,
  type ConversationInput,
  type ConversationReply,
} from "./conversation.js";
import {
  ANSWERS,
  REFUSAL,
  ROTATION,
  SUGGESTIONS,
  VALIDATION_QUESTION,
  tooShort,
  validationQuestionFor,
} from "./conversationCopy.js";
import { HeuristicResponder, mentionsSubscription, readSignals } from "./conversationHeuristics.js";
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
      tripContext: null,
    },
    traveller: { firstName: "Hugo", memberCount: 1, isUnlimited: false },
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
    allows: { roseEpineGraine: false, callsToAction: [] },
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

  it("dit les faits du crédit et de l'abonnement, et pose le bouton quand le code le permet", async () => {
    const reply = await memo.reply(
      turn("Combien coûte l'abonnement ?", {
        allows: { roseEpineGraine: false, callsToAction: ["subscribe", "open_trip_settings"] },
      }),
    );
    expect(reply.beats[0]?.text).toContain("5 minutes de récit par jour");
    expect(reply.beats[0]?.text).toContain("4,99 €");
    expect(reply.beats[0]?.text).toContain("« Découvrir l’abonnement »");
    // Plus rien de l'ancien modèle.
    expect(reply.beats[0]?.text).not.toMatch(/étapes? offertes?|limites? de souvenirs|Mon abonnement/);
    expect(reply.callToActionId).toBe("subscribe");
  });

  it("ne pose pas le bouton que le tour ne permet pas", async () => {
    const reply = await memo.reply(turn("Combien coûte l'abonnement ?"));
    expect(reply.beats[0]?.text).toBe(ANSWERS.subscription);
    expect(reply.callToActionId).toBeNull();
  });

  it("répond à un abonné qu'il raconte sans limite, sans lui vendre l'offre", async () => {
    const reply = await memo.reply(
      turn("Il me reste combien de temps aujourd'hui ?", {
        traveller: { firstName: "Hugo", memberCount: 1, isUnlimited: true },
        allows: { roseEpineGraine: false, callsToAction: ["open_trip_settings"] },
      }),
    );
    expect(reply.beats[0]?.text).toBe(ANSWERS.subscriptionUnlimited);
    expect(reply.callToActionId).toBeNull();
  });

  it("répond au prix du carnet par le carnet, et à l'Europe sans offre", async () => {
    const allowsEverything = {
      allows: { roseEpineGraine: false, callsToAction: ["subscribe" as const] },
    };
    const book = await memo.reply(turn("Combien coûte le carnet imprimé ?", allowsEverything));
    expect(book.beats[0]?.text).toBe(ANSWERS.book);
    expect(book.callToActionId).toBeNull();

    const europe = await memo.reply(turn("Tu connais des bons restos en Europe ?", allowsEverything));
    expect(europe.beats[0]?.text).toBe(ANSWERS.unknown);
    expect(europe.callToActionId).toBeNull();
  });

  it("entend une question sur le temps qui reste comme une question sur la limite", async () => {
    const reply = await memo.reply(turn("il me reste combien de temps aujourd'hui ?"));
    expect(reply.beats[0]?.text).toBe(ANSWERS.subscription);
    expect(reply.disposition).toBe("command");
  });

  // S09 (03/10/2026) : la question d'exemple du prompt
  // (`agents/agent-conversation.md`) n'ouvrait plus rien.
  it("répond à « Il me reste combien aujourd’hui ? » par le crédit, et pose le bouton", async () => {
    const reply = await memo.reply(
      turn("Il me reste combien aujourd’hui ?", {
        allows: { roseEpineGraine: false, callsToAction: ["subscribe"] },
      }),
    );
    expect(reply.beats[0]?.text).toBe(ANSWERS.subscription);
    expect(reply.callToActionId).toBe("subscribe");
  });

  // S02 (03/10/2026) : Claude en panne, une question de trajet recevait
  // l'offre et son bouton.
  it("ne récite pas l'offre à une question de trajet, même quand le bouton serait permis", async () => {
    for (const travel of [
      "C’est à combien de minutes à pied, le Colisée ?",
      "Il me reste combien de temps avant l’embarquement ?",
      "Je n’ai plus de crédit sur mon téléphone, tu sais où recharger ?",
    ]) {
      const reply = await memo.reply(
        turn(travel, { allows: { roseEpineGraine: false, callsToAction: ["subscribe"] } }),
      );
      expect(reply.beats[0]?.text, travel).not.toBe(ANSWERS.subscription);
      expect(reply.callToActionId, travel).toBeNull();
    }
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

  it("dit qu'il n'a pas compris un message trop court, sans inventer la suite", async () => {
    const reply = await memo.reply(turn("ok"));
    expect(reply.beats.map((beat) => beat.text)).toEqual([tooShort("ok")[0]]);
    expect(reply.beats[0]?.text).toContain("« ok »");
    expect(reply.beats[0]?.text).not.toMatch(/où|qui était/);
    // Rien n'entre dans le carnet : ce n'est pas un souvenir.
    expect(reply.disposition).toBe("command");
  });

  it("change de tournure au second message incompris", async () => {
    const reply = await memo.reply(turn("ok", { history: memoSaid([tooShort("ok")[0]!]) }));
    expect(reply.beats[0]?.text).toBe(tooShort("ok")[1]);
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
        allows: { roseEpineGraine: true, callsToAction: [] },
      }),
    );
    expect(reply.asksRoseEpineGraine).toBe(true);
    expect(reply.beats[0]?.text).toContain("la rose, l’épine et la graine");
  });
});

describe("ce qui est trop court pour un souvenir", () => {
  it("compte les mots, pas les signes ni la ponctuation", () => {
    expect(isTooShortToKeep("ok")).toBe(true);
    expect(isTooShortToKeep("Trop bien !!! 🎉")).toBe(true);
    expect(isTooShortToKeep("  ")).toBe(true);
    expect(isTooShortToKeep("Plage de Copacabana")).toBe(false);
    expect(isTooShortToKeep("On a mangé une glace")).toBe(false);
  });

  it("recopie un long message coupé à quarante signes", () => {
    const line = tooShort("x".repeat(80))[0]!;
    expect(line).toContain(`« ${"x".repeat(39)}… »`);
  });
});

describe("les commandes et les garde-fous", () => {
  it("répond à une puce sans modèle, et à une commande silencieuse aussi", () => {
    const accept = scriptedReply("accept", SUGGESTIONS.accept.label);
    expect(accept?.beats[0]?.text).toBe("C’est enregistré. Ton carnet compte une étape de plus.");
    expect(accept?.disposition).toBe("command");
    expect(scriptedReply("transcript_edited", "")?.suggestionIds).toEqual(["accept", "edit-hand"]);
    expect(scriptedReply("else", "")).toBeNull();
    expect(scriptedReply(null, "")).toBeNull();
    // Une réponse écrite d'avance ne porte jamais de bouton.
    expect(accept?.callToActionId).toBeNull();
  });

  it("refuse deux questions dans un tour, et borne la relance", () => {
    const base: ConversationReply = {
      beats: composeBeats("x", ["Tu étais où ?", "Et avec qui ?"]),
      disposition: "memory",
      suggestionIds: ["voice", "inconnue" as never],
      prompt: "x".repeat(200),
      asksRoseEpineGraine: true,
      callToActionId: null,
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

  it("jette « Photos de test » : seul le code la pose, hors production", () => {
    const reply = validateReply(
      {
        beats: composeBeats("x", ["Je note."]),
        disposition: "command",
        suggestionIds: ["photos-sample", "photos"],
        prompt: null,
        asksRoseEpineGraine: false,
        callToActionId: null,
        model: "test",
      },
      turn("x"),
    );
    expect(reply.suggestionIds).toEqual(["photos"]);
  });

  it("jette un bouton que le tour ne permet pas — le modèle propose, le code dispose", () => {
    const base: ConversationReply = {
      beats: composeBeats("x", ["L’abonnement est à 4,99 € par mois."]),
      disposition: "command",
      suggestionIds: [],
      prompt: null,
      asksRoseEpineGraine: false,
      callToActionId: "subscribe",
      model: "test",
    };
    const allowing = (callsToAction: ConversationInput["allows"]["callsToAction"]) =>
      turn("Combien ça coûte ?", { allows: { roseEpineGraine: false, callsToAction } });

    expect(validateReply(base, allowing(["subscribe"])).callToActionId).toBe("subscribe");
    expect(validateReply(base, allowing(["open_trip_settings"])).callToActionId).toBeNull();
    expect(validateReply(base, allowing([])).callToActionId).toBeNull();
    // Un bouton réservé au code ne passe jamais, même si `allows` le listait.
    expect(
      validateReply(
        { ...base, callToActionId: "daily_credit_subscribe" },
        allowing(["daily_credit_subscribe"]),
      ).callToActionId,
    ).toBeNull();
  });

  it("le répondeur simulé pose un bouton seulement s'il est permis", async () => {
    const allowed = await new FakeResponder([{ callToActionId: "open_trip_settings" }]).reply(
      turn("Où je change le rythme des relances ?", {
        allows: { roseEpineGraine: false, callsToAction: ["open_trip_settings"] },
      }),
    );
    expect(allowed.callToActionId).toBe("open_trip_settings");

    const refused = await new FakeResponder([{ callToActionId: "subscribe" }]).reply(
      turn("Une longue journée à marcher dans Rome sous le soleil."),
    );
    expect(refused.callToActionId).toBeNull();
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
    const env = (mode: string, live: boolean, key: string) =>
      ({
        PIPELINE_MODE: mode,
        live,
        ANTHROPIC_API_KEY: key,
        ANTHROPIC_CONVERSATION_MODEL: "claude-sonnet-5",
      }) as Env;

    // « Personne n'appelle personne » : la seule chose qui coupe Claude.
    expect(createResponder(env("fake", false, "sk-test")).constructor.name).toBe("FakeResponder");
    expect(createResponder(env("auto", true, "")).constructor.name).toBe("HeuristicResponder");
    expect(createResponder(env("auto", true, "sk-test")).constructor.name).toBe("AnthropicResponder");

    // Le cas qui avait rendu MEMO muet sans le dire : une clé Anthropic
    // valide, mais pas de clé OpenAI, donc `live` faux. MEMO parle quand même.
    expect(createResponder(env("auto", false, "sk-test")).constructor.name).toBe("AnthropicResponder");
    expect(createResponder(env("auto", false, "")).constructor.name).toBe("FakeResponder");
  });
});

describe("les boutons qu'un tour permet", () => {
  const text = (value: string, overrides: Partial<Parameters<typeof callsToActionAllowed>[0]> = {}) =>
    callsToActionAllowed({
      kind: "text",
      text: value,
      suggestionId: null,
      authorIsUnlimited: false,
      hasPreview: false,
      ...overrides,
    });

  it("ne permet l'abonnement qu'à qui en parle, et n'a pas déjà l'illimité", () => {
    expect(text("Combien coûte l'abonnement ?")).toContain("subscribe");
    expect(text("il me reste combien de temps aujourd'hui ?")).toContain("subscribe");
    expect(text("C'est quoi la limite du crédit ?")).toContain("subscribe");
    expect(text("Combien coûte l'abonnement ?", { authorIsUnlimited: true })).not.toContain("subscribe");
    expect(text("On a mangé une glace pistache place Navone.")).not.toContain("subscribe");
  });

  // R53 (03/10/2026) : la bulle « reviens demain » s'écrit avec le tour du
  // voyageur, avant la réponse de MEMO — qui ne pose pas une seconde offre.
  it("ne permet pas l'abonnement quand la bulle « reviens demain » est le dernier bouton du fil", () => {
    const posted = text("Combien coûte l'abonnement ?", { lastCallToActionId: "daily_credit_subscribe" });
    expect(posted).not.toContain("subscribe");
    expect(posted).toEqual(["open_trip_settings", "import_photos"]);
  });

  // S10 (03/10/2026) : « jamais deux fois de suite le même bouton dans le fil ».
  it("ne repose pas le bouton de la dernière bulle de MEMO qui en portait un", () => {
    const question = "Combien coûte l'abonnement ?";
    expect(text(question, { lastCallToActionId: "subscribe" })).toEqual(["open_trip_settings", "import_photos"]);
    // Un autre bouton avant : l'offre reste permise, ce bouton-là non.
    expect(text(question, { hasPreview: true, lastCallToActionId: "open_preview" })).toEqual([
      "subscribe",
      "open_trip_settings",
      "import_photos",
    ]);
    // Un identifiant que le catalogue ne connaît plus ne retient rien.
    expect(text(question, { lastCallToActionId: "ancien_bouton" })).toContain("subscribe");
    expect(text(question, { lastCallToActionId: null })).toContain("subscribe");
  });

  it("ne prend pas « tu m’écoutes ? » pour une question de prix", () => {
    expect(mentionsSubscription("Tu m’écoutes ?")).toBe(false);
    expect(mentionsSubscription("Ça coûte combien ?")).toBe(true);
    expect(mentionsSubscription("C’est illimité ?")).toBe(true);
  });

  // R27 (03/10/2026) : « euro » attrapait « Europe », « limit » la limite de
  // vitesse, « prix » le prix du carnet — et le repli posait l'offre dessous.
  it("ne prend pas une question de voyage pour une question d'abonnement", () => {
    for (const travel of [
      "Tu connais des bons restos en Europe ?",
      "On a pris l’Eurostar ce matin, tu savais ?",
      "Le musée est gratuit le dimanche ?",
      "Quelle est la limite de vitesse en Italie ?",
      "Il fallait payer l’entrée du Colisée ?",
      "Combien coûte le carnet imprimé ?",
      "Combien coûte le carnet MemoBook ?",
      "Le billet de train coûte combien ?",
      "Quel est le prix du billet pour le Vatican ?",
      "J’ai payé par carte de crédit, c’est grave ?",
      "Le musée, c’est payant ?",
      "Il me reste combien de jours de voyage ?",
      // S02 (03/10/2026) : le temps d'un trajet, le crédit du téléphone, le
      // wifi illimité, une autre app.
      "C’est à combien de minutes à pied, le Colisée ?",
      "Il y a une limite de temps pour visiter le Louvre ?",
      "Il me reste combien de temps avant l’embarquement ?",
      "Il reste combien de minutes avant le départ du train ?",
      "Combien de temps pour aller au Colisée ?",
      "Je n’ai plus de crédit sur mon téléphone, tu sais où recharger ?",
      "Il me reste du crédit sur ma carte SIM ?",
      "On a eu le wifi illimité ?",
      "La voiture de location a le kilométrage illimité ?",
      "L’abonnement de métro vaut le coup ?",
      "Je dois résilier mon forfait téléphone ?",
      "Il y a une app gratuite pour le métro de Rome ?",
      "Tu connais une appli gratuite pour traduire ?",
      "Je suis bloqué à l’aéroport, tu sais quoi faire ?",
      "Il me reste combien jusqu’à Florence ?",
    ]) {
      expect(mentionsSubscription(travel), travel).toBe(false);
      expect(readSignals(travel).subject, travel).not.toBe("subscription");
      expect(text(travel), travel).not.toContain("subscribe");
    }
  });

  it("entend l'abonnement, le crédit du jour, la limite du récit et le temps qui reste", () => {
    for (const question of [
      "Combien coûte l'abonnement ?",
      "Comment je résilie ?",
      "C’est illimité ?",
      "C'est quoi la limite du crédit ?",
      "Mon crédit du jour est fini ?",
      "il me reste combien de temps aujourd'hui ?",
      "Combien de minutes je peux raconter ?",
      "Ça coûte combien ?",
      "Est-ce que c’est payant ?",
      "Ça coûte combien, MEMO ?",
      "MemoBook, c'est gratuit ?",
      "Il y a une limite ?",
      // S09 (03/10/2026) : ce qui reste, et pourquoi on est limité.
      "Il me reste combien aujourd’hui ?",
      "Il me reste combien ?",
      "Il me reste combien de temps ?",
      "Combien de temps il me reste ?",
      "Il me reste combien, MEMO ?",
      "Il reste combien de crédit ?",
      "Combien de crédit il reste ?",
      "Pourquoi je suis limité ?",
      "Il y a une limite de temps ?",
      "Combien de minutes par jour ?",
      "Combien de temps je peux raconter par jour ?",
      "Il me reste combien de temps pour raconter le Colisée ?",
      "Le crédit se recharge quand ?",
      "Je n’ai plus de crédit pour raconter ?",
      "L’appli est payante ?",
    ]) {
      expect(mentionsSubscription(question), question).toBe(true);
      expect(readSignals(question).subject, question).toBe("subscription");
    }
  });

  it("n'ouvre l'aperçu que si un rendu est prêt", () => {
    expect(text("Je peux voir mon carnet ?")).not.toContain("open_preview");
    expect(text("Je peux voir mon carnet ?", { hasPreview: true })).toContain("open_preview");
  });

  it("ne permet rien sous un vocal, des photos ou une puce, ni jamais un bouton du code", () => {
    expect(text("Combien ça coûte ?", { kind: "voice" })).toEqual([]);
    expect(text("", { kind: "photos" })).toEqual([]);
    expect(text("Ça me convient", { suggestionId: "accept" })).toEqual([]);
    const all = text("Combien coûte l'abonnement ?", { hasPreview: true });
    expect(all).toEqual(["subscribe", "open_trip_settings", "open_preview", "import_photos"]);
    expect(all).not.toContain("daily_credit_subscribe");
    expect(all).not.toContain("open_photo_settings");
  });
});

describe("la question de validation", () => {
  it("reste la même quand l'écrivain a tout compris", () => {
    expect(validationQuestionFor([])).toBe(VALIDATION_QUESTION);
  });

  it("cite dans la même bulle ce qu'il a laissé de côté", () => {
    expect(validationQuestionFor(["je tarbé"])).toBe(
      "Voilà ton texte pour le carnet. Je n’ai pas compris « je tarbé » : je l’ai laissé de côté. " +
        "Redis-le-moi autrement si tu veux qu’il y soit. Il te convient ?",
    );
  });

  it("n'en cite jamais plus de deux", () => {
    const question = validationQuestionFor(["Famine", "jeans toniques", "Cora"]);

    expect(question).toContain("Je n’ai compris ni « Famine » ni « jeans toniques »");
    expect(question).not.toContain("Cora");
    expect(question.endsWith("Il te convient ?")).toBe(true);
  });
});
