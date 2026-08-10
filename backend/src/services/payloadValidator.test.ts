import { describe, expect, it } from "vitest";
import { loadSamplePayload } from "../lib/templates.js";
import {
  EDITORIAL_LIMITS,
  splitParagraphs,
  validatePayload,
} from "./payloadValidator.js";

/**
 * Le payload d'exemple du dépôt est la référence : c'est lui qui alimente
 * APITemplate.io aujourd'hui. S'il cesse de passer le validateur, c'est le
 * validateur qui a tort.
 */
describe("validatePayload — référence du dépôt", () => {
  it("accepte templates/travel-journal/data.json", () => {
    const result = validatePayload(loadSamplePayload());

    expect(result.errors).toEqual([]);
    expect(result.valid).toBe(true);
  });

  it("signale l'intro trop découpée sans la rejeter", () => {
    const result = validatePayload(loadSamplePayload());

    expect(result.warnings.map((warning) => warning.path)).toContain("intro_text");
  });
});

function minimalPayload(day: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    book_title: "Carnet de test",
    days: [
      {
        title: "Jour 1",
        body_html: "<p>Une journée courte.</p>",
        layout_hero_top: true,
        ...day,
      },
    ],
  };
}

describe("validatePayload — schéma", () => {
  it("rejette un payload sans book_title", () => {
    const payload = minimalPayload();
    delete payload["book_title"];

    const result = validatePayload(payload);

    expect(result.valid).toBe(false);
    expect(result.errors.some((issue) => issue.message.includes("book_title"))).toBe(true);
  });

  it("rejette un jour sans body_html", () => {
    const result = validatePayload({
      book_title: "Carnet",
      days: [{ title: "Jour 1", layout_hero_top: true }],
    });

    expect(result.valid).toBe(false);
    expect(result.errors.some((issue) => issue.message.includes("body_html"))).toBe(true);
  });

  it("rejette autre chose qu'un objet", () => {
    expect(validatePayload(null).valid).toBe(false);
    expect(validatePayload([]).valid).toBe(false);
    expect(validatePayload("carnet").valid).toBe(false);
  });
});

describe("validatePayload — règles éditoriales de LAYOUT_KB", () => {
  it("rejette un jour sans aucun layout activé", () => {
    const result = validatePayload({
      book_title: "Carnet",
      days: [{ title: "Jour 1", body_html: "<p>Récit.</p>" }],
    });

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.message).toContain("aucun layout activé");
  });

  it("rejette trois layouts activés sur le même jour", () => {
    const result = validatePayload(
      minimalPayload({ layout_collage: true, layout_timeline: true }),
    );

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.message).toContain("3 layouts activés");
  });

  it("tolère deux layouts mais le signale", () => {
    const result = validatePayload(minimalPayload({ layout_collage: true }));

    expect(result.valid).toBe(true);
    expect(result.warnings[0]?.message).toContain("2 layouts activés");
  });

  it("rejette un paragraphe qui déborderait de la page", () => {
    const tooLong = "a".repeat(EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph + 1);
    const result = validatePayload(minimalPayload({ body_html: `<p>${tooLong}</p>` }));

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.path).toBe("days[0].body_html[¶1]");
  });

  it("accepte plusieurs paragraphes courts là où un seul long échoue", () => {
    const paragraph = "a".repeat(400);
    const result = validatePayload(
      minimalPayload({ body_html: `<p>${paragraph}</p><p>${paragraph}</p>` }),
    );

    expect(result.valid).toBe(true);
  });

  it("rejette un fun fact trop long", () => {
    const result = validatePayload(
      minimalPayload({ fun_facts: ["f".repeat(EDITORIAL_LIMITS.funFactChars + 1)] }),
    );

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.path).toBe("days[0].fun_facts[0]");
  });

  it("rejette plus de trois highlights", () => {
    const result = validatePayload(
      minimalPayload({ highlights: ["un", "deux", "trois", "quatre"] }),
    );

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.message).toContain("4 bullets");
  });

  it("rejette un highlight trop long", () => {
    const result = validatePayload(
      minimalPayload({ highlights: ["h".repeat(EDITORIAL_LIMITS.highlightChars + 1)] }),
    );

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.path).toBe("days[0].highlights[0]");
  });

  it("applique les mêmes limites à opener_body_html", () => {
    const tooLong = "a".repeat(EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph + 1);
    const result = validatePayload(
      minimalPayload({
        layout_hero_top: false,
        layout_story_opener: true,
        opener_body_html: `<p>${tooLong}</p>`,
      }),
    );

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.path).toBe("days[0].opener_body_html[¶1]");
  });
});

describe("splitParagraphs", () => {
  it("découpe sur les balises <p>", () => {
    expect(splitParagraphs("<p>Un</p><p>Deux</p>")).toEqual(["Un", "Deux"]);
  });

  it("traite un double <br> comme une rupture de paragraphe", () => {
    expect(splitParagraphs("Un<br><br>Deux")).toEqual(["Un", "Deux"]);
  });

  it("garde un simple <br> à l'intérieur du paragraphe", () => {
    expect(splitParagraphs("Un<br>Deux")).toEqual(["UnDeux"]);
  });

  it("retire le balisage inline sans le compter dans la longueur", () => {
    expect(splitParagraphs("<p>Un <strong>mot</strong> fort</p>")).toEqual([
      "Un mot fort",
    ]);
  });

  it("ignore les paragraphes vides", () => {
    expect(splitParagraphs("<p></p><p>Un</p>")).toEqual(["Un"]);
  });
});
