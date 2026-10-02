import { describe, expect, it } from "vitest";
import {
  EMPTY_TRIP_CONTEXT,
  advance,
  companionNamesIn,
  describeTripContext,
  introTextFor,
  introTitleFor,
  isComplete,
  mergeTripContext,
  missingFields,
  parseTripContext,
  questionFor,
  serializeTripContext,
  travellerCountIn,
  updateByRules,
  type TripContext,
} from "./tripContext.js";

/**
 * Le contexte du voyage : ce qui le rend complet, ce qu'on demande ensuite, et
 * ce que le repli sait ranger sans modèle — `docs/conversation.md` § 2 bis.
 */

const full: TripContext = {
  ...EMPTY_TRIP_CONTEXT,
  departureCountry: "France",
  travellerCount: 3,
  companions: [
    { name: "Clara", relation: "ma femme" },
    { name: "Léo", relation: null },
  ],
  dates: "du 12 au 26 septembre 2026",
  tripType: "road trip en van",
};

describe("ce qui manque", () => {
  it("demande les cinq lignes dans l'ordre, et rien quand tout y est", () => {
    expect(missingFields(EMPTY_TRIP_CONTEXT)).toEqual([
      "departureCountry",
      "travellerCount",
      "companions",
      "dates",
      "tripType",
    ]);
    expect(isComplete(full)).toBe(true);
  });

  it("veut un prénom par compagnon : quatre voyageurs et deux prénoms, ce n'est pas fini", () => {
    const partial = { ...full, travellerCount: 4 };
    expect(missingFields(partial)).toEqual(["companions"]);
    expect(questionFor("companions", partial)).toBe(
      "Il me manque un prénom : qui est le dernier compagnon de route ?",
    );
  });

  it("n'attend aucun prénom d'un voyageur en solo", () => {
    const solo = { ...full, travellerCount: 1, companions: [] };
    expect(isComplete(solo)).toBe(true);
    expect(serializeTripContext(solo)?.items.find((item) => item.key === "companions")?.value).toBe("En solo");
  });

  it("ne pose jamais deux questions à la fois", () => {
    for (const field of missingFields(EMPTY_TRIP_CONTEXT)) {
      const question = questionFor(field, EMPTY_TRIP_CONTEXT);
      expect(question.match(/\?/g)?.length ?? 0).toBeLessThanOrEqual(1);
    }
  });

  it("avance : il attend la première ligne vide, puis se déclare complet", () => {
    expect(advance(EMPTY_TRIP_CONTEXT).awaiting).toBe("departureCountry");
    expect(advance(full)).toMatchObject({ status: "complete", awaiting: null });
  });
});

describe("fondre ce qui vient d'être dit", () => {
  it("complète sans rien vider, et ajoute la relation d'un prénom déjà connu", () => {
    const before = { ...EMPTY_TRIP_CONTEXT, companions: [{ name: "Clara", relation: null }] };
    const after = mergeTripContext(before, {
      departureCountry: "France",
      dates: null,
      companions: [
        { name: "clara", relation: "ma femme" },
        { name: "Léo", relation: null },
      ],
    });
    expect(after.departureCountry).toBe("France");
    expect(after.dates).toBeNull();
    expect(after.companions).toEqual([
      { name: "Clara", relation: "ma femme" },
      { name: "Léo", relation: null },
    ]);
  });

  it("déduit le nombre de voyageurs des prénoms, narrateur compris", () => {
    const after = mergeTripContext(EMPTY_TRIP_CONTEXT, {
      companions: [
        { name: "Clara", relation: null },
        { name: "Léo", relation: null },
      ],
    });
    expect(after.travellerCount).toBe(3);
  });

  it("relit défensivement ce qui est en base", () => {
    expect(parseTripContext(null)).toBeNull();
    expect(parseTripContext({ travellerCount: "trois", companions: [{ name: "" }, "Léo"] })).toMatchObject({
      status: "gathering",
      travellerCount: null,
      companions: [],
    });
  });
});

describe("le repli, sans modèle", () => {
  it("compte les voyageurs dans une phrase", () => {
    expect(travellerCountIn("Je pars seule")).toBe(1);
    expect(travellerCountIn("on part en couple")).toBe(2);
    expect(travellerCountIn("On est 4")).toBe(4);
    expect(travellerCountIn("nous sommes trois")).toBe(3);
  });

  it("lit les prénoms sans compter le narrateur", () => {
    expect(companionNamesIn("Clara, Léo et moi, Hugo", "Hugo").map((companion) => companion.name)).toEqual([
      "Clara",
      "Léo",
    ]);
  });

  it("range la réponse dans la ligne que MEMO venait de demander", () => {
    const awaitingDates = { ...EMPTY_TRIP_CONTEXT, awaiting: "dates" as const };
    expect(updateByRules(awaitingDates, "Du 3 au 17 octobre.", null)).toEqual({ dates: "Du 3 au 17 octobre" });

    const awaitingCountry = { ...EMPTY_TRIP_CONTEXT, awaiting: "departureCountry" as const };
    expect(updateByRules(awaitingCountry, "de France", null).departureCountry).toBe("France");
  });

  it("garde une description libre pour l'écrivain, sans la découper", () => {
    expect(updateByRules(EMPTY_TRIP_CONTEXT, "On part à 3 en Malaisie", null)).toEqual({
      notes: "On part à 3 en Malaisie",
      travellerCount: 3,
    });
  });
});

describe("pour les autres lecteurs", () => {
  it("écrit le contexte en lignes que MEMO et l'écrivain relisent", () => {
    expect(describeTripContext(full, "Hugo")).toEqual([
      "Pays de départ : France",
      "Voyageurs : 3, narrateur compris",
      "Compagnons : Clara (ma femme), Léo",
      "Dates : du 12 au 26 septembre 2026",
      "Genre de voyage : road trip en van",
    ]);
  });

  it("compte ce qui est rempli pour la pastille de l'app", () => {
    const serialized = serializeTripContext({ ...EMPTY_TRIP_CONTEXT, departureCountry: "France" });
    expect(serialized).toMatchObject({ status: "gathering", filledCount: 1, requiredCount: 5 });
  });
});

describe("l'intro du carnet", () => {
  it("titre l'intro d'après le genre de voyage", () => {
    expect(introTitleFor(full)).toBe("Road trip en van");
  });

  it("titre l'intro d'après l'occasion, à défaut de genre de voyage", () => {
    expect(introTitleFor({ ...EMPTY_TRIP_CONTEXT, occasion: "lune de miel" })).toBe("Lune de miel");
  });

  it("retombe sur un titre générique sans contexte", () => {
    expect(introTitleFor(null)).toBe("Avant de commencer");
    expect(introTitleFor(EMPTY_TRIP_CONTEXT)).toBe("Avant de commencer");
  });

  it("compose un texte d'intro dans un seul paragraphe HTML", () => {
    const text = introTextFor(full);
    expect(text.startsWith("<p>")).toBe(true);
    expect(text.endsWith("</p>")).toBe(true);
    expect(text).toContain("France");
    expect(text).toContain("Clara");
    expect(text).toContain("road trip en van");
  });

  it("échappe le HTML d'un champ libre", () => {
    const text = introTextFor({ ...full, tripType: "<script>alert(1)</script>" });
    expect(text).not.toContain("<script>");
    expect(text).toContain("&lt;script&gt;");
  });

  it("rend une chaîne vide sans contexte", () => {
    expect(introTextFor(null)).toBe("");
  });

  it("respecte la limite éditoriale d'un paragraphe d'intro", () => {
    const text = introTextFor({
      ...full,
      notes: null,
      tripType: "a".repeat(600),
    });
    // 700 caractères par paragraphe (LAYOUT_KB), balises HTML non comprises.
    const inner = text.slice("<p>".length, -"</p>".length);
    expect(inner.length).toBeLessThanOrEqual(700);
  });
});
