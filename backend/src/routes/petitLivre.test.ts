import { describe, expect, it } from "vitest";

import { COVER_AFTER_STEPS, bookDoorOf, type MemoForChat } from "./chatSerializers.js";

/**
 * **Le petit livre qui dépasse du bord** (T297) : son âge, décidé par le
 * serveur.
 *
 * L'app ne refait pas ce calcul — elle lit `coverUrl` et `stepsBeforeCover`,
 * et dessine. Si elle le refaisait, la règle vivrait à trois endroits.
 */
const memo = (steps: (string | null)[], coverPhotoUrl: string | null = "https://cdn/photo.jpg") =>
  ({
    coverPhotoUrl,
    steps: steps.map((coverEntryId) => ({ coverEntryId })),
  }) as unknown as MemoForChat;

describe("le petit livre et son âge (T297)", () => {
  it("compte les étapes qui ont une photo, et dit combien il en manque", () => {
    expect(bookDoorOf(memo([]), "https://api")).toEqual({
      coverUrl: null,
      stepsBeforeCover: COVER_AFTER_STEPS,
    });
    expect(bookDoorOf(memo(["e1", null, "e2"]), "https://api")).toEqual({
      coverUrl: null,
      stepsBeforeCover: COVER_AFTER_STEPS - 2,
    });
  });

  it("montre la couverture à la quatrième étape avec photos, pas avant", () => {
    const presque = bookDoorOf(memo(["e1", "e2", "e3"]), "https://api");
    expect(presque.coverUrl).toBeNull();
    expect(presque.stepsBeforeCover).toBe(1);

    const arrivée = bookDoorOf(memo(["e1", "e2", "e3", "e4"]), "https://api");
    expect(arrivée.coverUrl).toBe("https://cdn/photo.jpg");
    expect(arrivée.stepsBeforeCover).toBeNull();
  });

  it("garde la couverture quand une étape de plus arrive", () => {
    // Le décompte ne redescend jamais : la photo est là, le livre l'a.
    const plus = bookDoorOf(memo(["e1", "e2", "e3", "e4", "e5", "e6"]), "https://api");
    expect(plus.stepsBeforeCover).toBeNull();
  });

  it("n'invente pas de couverture quand le voyage n'a pas de photo élue", () => {
    // Quatre étapes avec photos et aucune photo de couverture ne se produit
    // qu'entre deux recalculs : le livre reste nu plutôt que de montrer un
    // trou, et il ne redemande pas d'étapes pour autant.
    const sansPhoto = bookDoorOf(memo(["e1", "e2", "e3", "e4"], null), "https://api");
    expect(sansPhoto.coverUrl).toBeNull();
    expect(sansPhoto.stepsBeforeCover).toBeNull();
  });
});
