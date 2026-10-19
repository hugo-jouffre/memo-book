import { describe, expect, it } from "vitest";
import { billablePages } from "./printPricing.js";
import { composedPageCount } from "../jobs/render.js";

describe("le prix suit le carnet composé", () => {
  it("le nombre final de pages fait le prix, même sous la cible", () => {
    expect(billablePages({ targetPageCount: 40, pageCount: 24 })).toBe(24);
    expect(billablePages({ targetPageCount: 40, pageCount: 46 })).toBe(46);
  });

  it("avant tout carnet composé, la cible sert d'estimation", () => {
    expect(billablePages({ targetPageCount: 60, pageCount: 0 })).toBe(60);
  });

  it("le carnet compte ses pages d'avant, ses étapes et la page blanche finale", () => {
    const days = Array.from({ length: 20 }, () => ({}));
    // colophon + introduction + une page blanche pour ouvrir à gauche, 20 pages d'étape, une blanche finale.
    expect(composedPageCount({ intro_text: "<p>…</p>", pages_libres_avant: 1, days, page_blanche_finale: true })).toBe(24);
    expect(composedPageCount({ days })).toBe(21);
    expect(composedPageCount({})).toBeNull();
  });
});
