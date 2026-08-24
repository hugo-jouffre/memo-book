import { describe, expect, it } from "vitest";
import { loadSamplePayload } from "../lib/templates.js";
import {
  EDITORIAL_LIMITS,
  LENGTH_HINTS,
  STEP_SIZES,
  groupSteps,
  pageCapacity,
  sizeForStep,
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

/** Un récit de taille S (290 caractères), la cible du barème. */
const RECIT_S = `<p>${"a".repeat(290)}</p>`;

function minimalPayload(day: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    book_title: "Carnet de test",
    days: [
      {
        title: "Jour 1",
        day_intro: { day_number: "01" },
        body_html: RECIT_S,
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
    // 2 × 270 = 540 caractères, taille M : ça tient sur `layout_collage`, qui
    // en accepte 560. Le même texte en un seul paragraphe dépasserait la
    // limite par paragraphe.
    const paragraph = "a".repeat(270);
    const result = validatePayload(
      minimalPayload({
        layout_hero_top: false,
        layout_collage: true,
        body_html: `<p>${paragraph}</p><p>${paragraph}</p>`,
      }),
    );

    expect(result.errors).toEqual([]);
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

/**
 * Le barème S/M/L/XL. Les valeurs testées ici sont celles que
 * `scripts/calibrate-lengths.ts` a relevées sur le rendu : ce sont elles qui
 * font autorité, pas l'intuition.
 */
describe("barème S / M / L / XL", () => {
  const recit = (chars: number, paragraphes = 1): string =>
    Array.from({ length: paragraphes }, () => `<p>${"a".repeat(Math.round(chars / paragraphes))}</p>`).join("");

  const etape = (
    chars: number,
    day: Record<string, unknown> = {},
    paragraphes = 1,
  ): Record<string, unknown> => ({
    book_title: "Carnet",
    days: [
      {
        title: "Étape",
        day_intro: { day_number: "01" },
        body_html: recit(chars, paragraphes),
        layout_story_opener: true,
        ...day,
      },
    ],
  });

  it("range chaque longueur dans une seule taille", () => {
    expect(sizeForStep(290)).toBe("S");
    expect(sizeForStep(470)).toBe("M");
    expect(sizeForStep(720)).toBe("L");
    expect(sizeForStep(1150)).toBe("XL");
  });

  it("laisse les longueurs sous S sans taille", () => {
    expect(sizeForStep(STEP_SIZES.S.min - 1)).toBeUndefined();
  });

  it("couvre 200 → 1440 sans trou entre deux tailles", () => {
    for (let chars = STEP_SIZES.S.min; chars <= STEP_SIZES.XL.max; chars += 1) {
      expect(sizeForStep(chars), `${chars} caractères`).toBeDefined();
    }
  });

  it("accepte une étape de taille M sur le layout par défaut", () => {
    const result = validatePayload(etape(470, {}, 2));

    expect(result.errors).toEqual([]);
  });

  it("refuse une étape de taille M sur `layout_hero_top`, qui plafonne à 380", () => {
    const result = validatePayload(
      etape(470, { layout_story_opener: false, layout_hero_top: true }, 2),
    );

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.message).toContain("qui en tient 380");
  });

  it("nomme le layout de repli quand la page est trop pleine", () => {
    const result = validatePayload(
      etape(470, { layout_story_opener: false, layout_hero_top: true }, 2),
    );

    expect(result.errors[0]?.message).toContain("layout_chapter_map");
  });

  it("refuse une étape sous S quand une photo aurait pu porter la page", () => {
    const result = validatePayload(etape(150, { photos: ["https://cdn.test/a.jpg"] }));

    expect(result.valid).toBe(false);
    expect(result.errors[0]?.message).toContain("layout_hero_top");
  });

  it("accepte la même étape courte sur `layout_hero_top`", () => {
    const result = validatePayload(
      etape(150, {
        layout_story_opener: false,
        layout_hero_top: true,
        photos: ["https://cdn.test/a.jpg"],
      }),
    );

    expect(result.errors).toEqual([]);
  });

  it("se contente d'avertir quand rien n'aurait pu porter la page", () => {
    // Ni photo ni carte : aucun layout n'aurait fait mieux. Refuser le carnet
    // demanderait à l'utilisateur une correction qu'il ne peut pas faire.
    const result = validatePayload(etape(150));

    expect(result.errors).toEqual([]);
    expect(result.warnings[0]?.message).toContain("rien pour porter la page");
  });

  it("laisse passer une étape très courte que l'image porte", () => {
    const result = validatePayload(
      etape(60, {
        layout_story_opener: false,
        layout_hero_top: true,
        photos: ["https://cdn.test/a.jpg"],
      }),
    );

    expect(result.errors).toEqual([]);
  });

  it("refuse une étape au-dessus de XL", () => {
    const result = validatePayload({
      book_title: "Carnet",
      days: [
        {
          title: "Étape",
          day_intro: { day_number: "01" },
          body_html: recit(540, 2),
          layout_story_opener: true,
        },
        { title: "Suite", body_html: recit(950, 4), layout_story_opener: true },
      ],
    });

    expect(result.valid).toBe(false);
    expect(result.errors.some((issue) => issue.message.includes(LENGTH_HINTS.tropLong))).toBe(true);
  });

  it("accepte une taille L répartie sur deux entrées consécutives", () => {
    const result = validatePayload({
      book_title: "Carnet",
      days: [
        {
          title: "Étape",
          day_intro: { day_number: "01" },
          body_html: recit(400, 2),
          layout_story_opener: true,
        },
        { title: "", body_html: recit(400, 2), layout_story_opener: true },
      ],
    });

    expect(result.errors).toEqual([]);
  });
});

describe("groupSteps", () => {
  it("ouvre une étape à chaque `day_intro`", () => {
    const steps = groupSteps([
      { day_intro: {} },
      {},
      { day_intro: {} },
    ]);

    expect(steps.map((step) => step.days.length)).toEqual([2, 1]);
    expect(steps.map((step) => step.start)).toEqual([0, 2]);
  });

  it("ouvre une étape même si la première journée n'a pas de bandeau", () => {
    expect(groupSteps([{}, {}])).toHaveLength(1);
  });
});

describe("pageCapacity", () => {
  it("plafonne `layout_split_left` à 240 quand la carte info rétrécit la colonne", () => {
    const base = { day_intro: {}, layout_split_left: true, photos: ["a", "b"] };

    expect(pageCapacity(base)).toBe(560);
    expect(pageCapacity({ ...base, fun_facts: ["un fait"] })).toBe(240);
  });

  it("plafonne une ouverture de chapitre qui porte aussi une bande d'images", () => {
    const base = { day_intro: {}, layout_chapter_map: true };

    expect(pageCapacity(base)).toBe(560);
    expect(pageCapacity({ ...base, photos: ["a", "b"] })).toBe(320);
    expect(pageCapacity({ ...base, photos: ["a", "b"], fun_facts: ["f"] })).toBe(120);
  });

  it("ouvre la page de suite, qui n'a ni bandeau ni titre", () => {
    expect(pageCapacity({ layout_story_opener: true })).toBe(880);
    expect(pageCapacity({ day_intro: {}, layout_story_opener: true })).toBe(560);
  });

  it("rend sa place au récit quand un bloc interactif remplace la zone du bas", () => {
    expect(pageCapacity({ day_intro: {}, layout_story_opener: true, prompt: { label: "x" } })).toBe(
      760,
    );
  });

  it("donne une capacité nulle à `layout_photo_page`, qui ne rend aucun récit", () => {
    expect(pageCapacity({ day_intro: {}, layout_photo_page: true })).toBe(0);
  });
});

describe("EDITORIAL_LIMITS", () => {
  it("déduit la limite par paragraphe du barème plutôt que de l'inventer", () => {
    expect(EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph).toBe(STEP_SIZES.S.max);
  });
});
