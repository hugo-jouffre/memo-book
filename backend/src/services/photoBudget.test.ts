import { describe, expect, it } from "vitest";
import { photosWanted } from "./conversationCopy.js";
import { photoBudgetFor } from "./photoBudget.js";

describe("le nombre de photos d'une étape", () => {
  it("est un chiffre exact, fixé par le layout qui tient le texte validé", () => {
    expect(photoBudgetFor(150)).toEqual({ photos: 1, pages: 1, layouts: ["layout_hero_top"] });
    expect(photoBudgetFor(200).photos).toBe(3);
    expect(photoBudgetFor(559)).toEqual({ photos: 3, pages: 1, layouts: ["layout_collage"] });
    expect(photoBudgetFor(560)).toEqual({
      photos: 6,
      pages: 2,
      layouts: ["layout_collage", "layout_collage"],
    });
    expect(photoBudgetFor(1440).photos).toBe(6);
  });

  it("se dit au singulier comme au pluriel, page ou pages", () => {
    expect(photosWanted(1, 1)).toBe("Illustre ce souvenir avec une photo : c’est ce qu’il faut pour remplir sa page.");
    expect(photosWanted(6, 2)).toBe(
      "Illustre ce souvenir avec 6 photos : c’est ce qu’il faut pour remplir ses deux pages.",
    );
  });
});
