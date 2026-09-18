import { describe, expect, it } from "vitest";
import { normalizeNarrationPace } from "./narrationPace.js";

describe("normalizeNarrationPace", () => {
  it("garde une clé telle quelle", () => {
    expect(normalizeNarrationPace("daily")).toBe("daily");
    expect(normalizeNarrationPace(" Weekly ")).toBe("weekly");
  });

  it("ramène les libellés de l'ancien écran de création à leur clé", () => {
    expect(normalizeNarrationPace("Tous les jours")).toBe("daily");
    expect(normalizeNarrationPace("Tous les 2 jours")).toBe("every_two_days");
    expect(normalizeNarrationPace("Toutes les semaines")).toBe("weekly");
    expect(normalizeNarrationPace("Une fois par semaine")).toBe("weekly");
    expect(normalizeNarrationPace("Personnalisé")).toBe("custom");
  });

  it("laisse passer un mot qu'il ne connaît pas, et vide ce qui est vide", () => {
    expect(normalizeNarrationPace("À la pleine lune")).toBe("À la pleine lune");
    expect(normalizeNarrationPace("   ")).toBeNull();
    expect(normalizeNarrationPace(null)).toBeNull();
    expect(normalizeNarrationPace(undefined)).toBeNull();
  });
});
