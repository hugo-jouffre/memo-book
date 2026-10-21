import { describe, expect, it } from "vitest";
import { billablePages, unitPriceCents } from "./printPricing.js";
import { composedPageCount } from "../jobs/render.js";

describe("le prix par palier de pages", () => {
  it("chaque palier vaut jusqu'à sa borne haute comprise", () => {
    expect(unitPriceCents(16)).toBe(5_500);
    expect(unitPriceCents(45)).toBe(5_500);
    expect(unitPriceCents(46)).toBe(7_500);
    expect(unitPriceCents(65)).toBe(7_500);
    expect(unitPriceCents(85)).toBe(8_000);
    expect(unitPriceCents(100)).toBe(8_500);
    expect(unitPriceCents(101)).toBe(10_500);
    expect(unitPriceCents(200)).toBe(11_000);
    expect(unitPriceCents(300)).toBe(12_900);
    expect(unitPriceCents(400)).toBe(14_500);
  });

  it("sous 16 pages, le premier palier ; au-delà de 400, le dernier", () => {
    expect(unitPriceCents(0)).toBe(5_500);
    expect(unitPriceCents(10)).toBe(5_500);
    expect(unitPriceCents(500)).toBe(14_500);
  });
});

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
