import { describe, expect, it } from "vitest";
import { SUGGESTION_SETS } from "../services/conversationCopy.js";
import { suggestionIdsByMessage } from "./chatSerializers.js";

/**
 * **Les puces répondent à un message, pas au fil entier** (T286, Hugo — « un
 * clic simple sur un message le cerne d'un liseré bleu clair, et les
 * propositions s'adaptent à ce message-là »).
 *
 * Jusqu'ici la dernière bulle décidait pour tout le monde. Le serveur rend
 * maintenant, pour chacune, celles qu'il aurait proposées **si le fil
 * s'arrêtait là** — c'est la même règle (``currentSuggestionIds``), lue autant
 * de fois qu'il y a de bulles.
 */

type Row = Parameters<typeof suggestionIdsByMessage>[0][number];

const memo = (id: string, suggestionIds: string[] = []): Row => ({
  id,
  author: "memo",
  kind: "text",
  entryId: null,
  isEntryValidated: false,
  suggestionIds,
  reactionTo: null,
});

const traveller = (id: string): Row => ({
  id,
  author: "traveller",
  kind: "text",
  entryId: null,
  isEntryValidated: false,
  suggestionIds: [],
  reactionTo: null,
});

const card = (id: string, entryId: string | null, isEntryValidated = false): Row => ({
  id,
  author: "memo",
  kind: "transcript",
  entryId,
  isEntryValidated,
  suggestionIds: [],
  reactionTo: null,
});

describe("les puces de chaque message", () => {
  it("sont celles que le fil aurait proposées en s'arrêtant là", () => {
    const rows = [
      memo("ouverture", [...SUGGESTION_SETS.opening]),
      traveller("premier-recit"),
      card("fiche", "entry-1"),
      memo("apres", [...SUGGESTION_SETS.afterAccept]),
    ];

    const byMessage = suggestionIdsByMessage(rows, null);

    // Rien n'a encore été dit : l'ouverture.
    expect(byMessage.get("ouverture")).toEqual([...SUGGESTION_SETS.opening]);
    // Le voyageur vient de parler : le trio neutre.
    expect(byMessage.get("premier-recit")).toEqual([...SUGGESTION_SETS.neutral]);
    // Sous une fiche non relue : le trio de validation.
    expect(byMessage.get("fiche")).toEqual([...SUGGESTION_SETS.trio]);
    // Et sous la dernière bulle de MEMO : les siennes.
    expect(byMessage.get("apres")).toEqual([...SUGGESTION_SETS.afterAccept]);
  });

  /** Une fiche déjà relue ne repropose pas « Ça me convient ». */
  it("suivent l'état du souvenir d'une fiche", () => {
    const byMessage = suggestionIdsByMessage(
      [memo("ouverture"), traveller("recit"), card("fiche", "entry-1", true)],
      null,
    );
    expect(byMessage.get("fiche")).toEqual([...SUGGESTION_SETS.afterAccept]);
  });

  /** Chaque bulle en a : choisir la première d'un long fil doit marcher. */
  it("en donne à toutes, et une seule fois chacune", () => {
    const rows = [memo("a", [...SUGGESTION_SETS.opening]), traveller("b"), memo("c", [...SUGGESTION_SETS.neutral])];
    const byMessage = suggestionIdsByMessage(rows, null);
    expect([...byMessage.keys()]).toEqual(["a", "b", "c"]);
  });

  /**
   * ⚠️ **Même pendant que MEMO réfléchit.** Les puces du bas disparaissent le
   * temps d'un tour (`currentSuggestionIds` rend vide sur `replying`), mais
   * choisir une bulle d'hier doit montrer les siennes : la carte se calcule
   * donc au repos.
   */
  it("ne se taisent pas parce qu'un tour est en vol", () => {
    const byMessage = suggestionIdsByMessage([memo("ouverture", [...SUGGESTION_SETS.opening])], null);
    expect(byMessage.get("ouverture")).not.toEqual([]);
  });
});
