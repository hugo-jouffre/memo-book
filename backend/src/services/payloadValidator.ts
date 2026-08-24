import { Ajv, type ValidateFunction } from "ajv";
import addFormatsModule from "ajv-formats";
import { loadPayloadSchema } from "../lib/templates.js";

// `ajv-formats` est un module CommonJS dont l'export par défaut est la fonction
// elle-même. Sous `module: NodeNext`, TypeScript la voit comme un espace de
// noms : le cast rétablit la signature réelle, la valeur d'exécution est bonne.
const addFormats = addFormatsModule as unknown as typeof addFormatsModule.default;

/**
 * Deux niveaux de contrôle sur le payload produit par le modèle :
 *
 * 1. le JSON Schema de `templates/travel-journal/gpt_image_schema.yaml`, qui
 *    dit ce qui existe ;
 * 2. les règles éditoriales de `LAYOUT_KB.md`, qui disent ce qui tient dans la
 *    page. Ces limites de longueur existent pour éviter le débordement à
 *    l'impression : les faire respecter côté serveur, pas seulement les
 *    suggérer au modèle.
 */

/**
 * Barème S / M / L / XL — mesuré en rendant le gabarit, pas estimé.
 *
 * Le problème qu'il résout : la mise en page comptait par layout, la rédaction
 * écrivait librement, et une étape allait de 200 à 1260 caractères sans que
 * personne ne sache laquelle tenait sur la page. Les deux agents comptent
 * désormais la même chose — **le récit d'une étape entière**, jamais un
 * paragraphe isolé. Le nombre de paragraphes se déduit de la taille, il ne la
 * définit pas.
 *
 * Chaque borne haute est un plafond relevé par `scripts/calibrate-lengths.ts`,
 * qui rend chaque layout à longueur croissante et note le point où la bande de
 * photos se comprime ou le contenu passe sous la marge. Redériver le barème,
 * c'est relancer ce script — pas rouvrir cette table.
 *
 * `max` est inclusif ; les fourchettes sont contiguës et couvrent 200 → 1440.
 * `paragraphes` est une **cible de rédaction**, pas un plafond : ce qui se
 * vérifie, c'est le nombre de paragraphes que chaque page peut porter
 * (`PARAGRAPHS_PER_PAGE`), parce que c'est lui qui a été mesuré.
 */
export const STEP_SIZES = {
  /** Un souvenir, une page. Le cas le plus courant. */
  S: { min: 200, max: 379, cible: 290, paragraphes: 1, pages: 1 },
  /** Une page bien remplie : le plafond mesuré d'une page à bandeau. */
  M: { min: 380, max: 559, cible: 470, paragraphes: 2, pages: 1 },
  /** Deux pages : la première porte le bandeau, la seconde enchaîne. */
  L: { min: 560, max: 899, cible: 720, paragraphes: 3, pages: 2 },
  /** 1440 = 560 (page à bandeau) + 880 (page de suite). Les deux mesurés. */
  XL: { min: 900, max: 1440, cible: 1150, paragraphes: 4, pages: 2 },
} as const;

export type StepSize = keyof typeof STEP_SIZES;

const SIZE_ORDER: readonly StepSize[] = ["S", "M", "L", "XL"];

/** Limites reprises de LAYOUT_KB.md § « Longueur des textes ». */
export const EDITORIAL_LIMITS = {
  introTextCharsPerParagraph: 700,
  introTextMaxParagraphs: 3,
  /**
   * Un paragraphe ne dépasse jamais la taille S : au-delà, c'est un mur de
   * texte quelle que soit la taille de l'étape. Valeur déduite du barème
   * (`STEP_SIZES.S.max`), plus inventée séparément.
   */
  bodyHtmlCharsPerParagraph: STEP_SIZES.S.max,
  /** Plancher absolu : en dessous, ce n'est plus une étape, c'est une légende. */
  stepMinChars: 120,
  /** Plafond absolu : au-delà, il faut deux étapes, pas une étape plus longue. */
  stepMaxChars: STEP_SIZES.XL.max,
  funFactChars: 140,
  highlightChars: 80,
  maxHighlights: 3,
  /** LAYOUT_KB : « les layouts sont exclusifs (activer 1 à 2 maximum par jour) ». */
  maxLayoutsPerDay: 2,
} as const;

/**
 * Capacité d'**une page**, en caractères de récit, photos gardées à leur
 * hauteur de conception. `bandeau` : première page d'une étape, celle qui porte
 * `day_intro` et le titre. `suite` : page suivante de la même étape, qui n'a ni
 * l'un ni l'autre et gagne donc ~320 caractères.
 *
 * Mesuré, layout par layout. `layout_photo_page` ne rend aucun récit : sa
 * capacité est nulle, ce n'est pas une erreur de barème.
 *
 * Les 880 de `suite` gardent 20 caractères de marge sur les 900 relevés : le
 * balayage avance par pas de 20, et la dernière valeur qui passe n'est pas la
 * première qui casse. Arrondir vers le bas, jamais vers le haut.
 */
export const LAYOUT_CAPACITY: Readonly<Record<string, { bandeau: number; suite: number }>> = {
  layout_photo_page: { bandeau: 0, suite: 0 },
  layout_hero_top: { bandeau: 380, suite: 680 },
  layout_chapter_map: { bandeau: 560, suite: 880 },
  layout_split_left: { bandeau: 560, suite: 880 },
  layout_collage: { bandeau: 560, suite: 880 },
  layout_story_opener: { bandeau: 560, suite: 880 },
  layout_story_facts: { bandeau: 560, suite: 880 },
};

/** Capacité par défaut : celle du layout de récit pleine largeur. */
const DEFAULT_CAPACITY = { bandeau: 560, suite: 880 } as const;

/**
 * Combien de paragraphes une page porte, à sa capacité.
 *
 * Chaque `<p>` est suivi d'une ligne vide — c'est l'espace resté libre dans le
 * gabarit, et il se paie. Aux plafonds mesurés ci-dessus, un paragraphe de plus
 * fait passer le contenu sous la marge : 560 caractères tiennent en 2
 * paragraphes et débordent en 3, 880 tiennent en 4 et débordent en 5.
 *
 * C'est donc bien un couple (caractères, paragraphes) qui a été mesuré, pas un
 * nombre de caractères seul.
 */
export const PARAGRAPHS_PER_PAGE = { bandeau: 2, suite: 4 } as const;

/**
 * Layouts qui restent beaux sous le minimum de S : la grande photo ou la carte
 * tiennent la hauteur à eux seuls, un récit court n'y creuse pas de trou.
 * Vérifié à l'œil sur le rendu, pas seulement au décamètre.
 *
 * Le drapeau ne suffit pas : c'est l'image qui porte la page. Un
 * `layout_hero_top` sans photo, c'est le layout par défaut avec un trou en
 * plus — d'où le prédicat `portéeParImage` plutôt qu'une simple appartenance.
 */
export const SUB_S_LAYOUTS = ["layout_hero_top", "layout_chapter_map", "layout_photo_page"] as const;

/**
 * Les deux messages que l'app affiche pendant que l'utilisateur écrit. Ils
 * vivent ici pour que le texte du bandeau d'alerte et celui du refus serveur
 * soient le même — l'app iOS les recopie (`EntryEditorView.swift`).
 */
export const LENGTH_HINTS = {
  tropCourt:
    `Encore quelques lignes : sous ${STEP_SIZES.S.min} caractères, l'étape laisse une page ` +
    "aux trois quarts vide. Raconte un détail de plus — ce que tu as vu, mangé, entendu.",
  tropLong:
    `Ce souvenir dépasse ce qu'une étape peut contenir : ${STEP_SIZES.XL.max} caractères, ` +
    "soit deux pages de carnet. Coupe-le en deux étapes, chacune aura les siennes.",
} as const;

/** La page tient-elle debout toute seule, sans récit pour la remplir ? */
export function carriedByImage(day: Record<string, unknown>): boolean {
  const photos = Array.isArray(day["photos"]) ? day["photos"].length : 0;
  const layout = Object.entries(day)
    .filter(([key, value]) => key.startsWith("layout_") && value === true)
    .map(([key]) => key)[0];

  if (layout === "layout_photo_page") return photos >= 3;
  if (layout === "layout_hero_top") return photos >= 1;
  if (layout === "layout_chapter_map") return Boolean(day["map"] ?? day["map_svg"]);
  return false;
}

/** La taille du barème qui correspond à une longueur, si elle en a une. */
export function sizeForStep(chars: number): StepSize | undefined {
  return SIZE_ORDER.find((size) => chars >= STEP_SIZES[size].min && chars <= STEP_SIZES[size].max);
}

export interface ValidationIssue {
  /** Chemin JSON de l'élément fautif, ex. `days[2].body_html`. */
  path: string;
  message: string;
}

export interface ValidationResult {
  valid: boolean;
  /** Bloquant : le payload ne doit pas partir chez APITemplate. */
  errors: ValidationIssue[];
  /** Non bloquant : s'écarte des bonnes pratiques sans casser le rendu. */
  warnings: ValidationIssue[];
}

let cachedValidator: ValidateFunction | undefined;

function getSchemaValidator(): ValidateFunction {
  if (cachedValidator) return cachedValidator;

  // `strict: false` : le schéma du dépôt utilise `$defs` en draft-07 et des
  // descriptions libres, ce qui n'a pas à faire échouer la compilation.
  const ajv = new Ajv({ allErrors: true, strict: false });
  addFormats(ajv);
  cachedValidator = ajv.compile(loadPayloadSchema());
  return cachedValidator;
}

/** Découpe un fragment HTML en paragraphes de texte brut. */
export function splitParagraphs(html: string): string[] {
  return html
    .replace(/<br\s*\/?>\s*<br\s*\/?>/gi, "\n\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.replace(/\s+/g, " ").trim())
    .filter((paragraph) => paragraph.length > 0);
}

const LAYOUT_FLAG_PREFIX = "layout_";

/** Longueur du récit d'une journée, en caractères de texte brut. */
export function bodyLength(day: Record<string, unknown>): number {
  const body = day["body_html"];
  if (typeof body !== "string") return 0;
  return splitParagraphs(body).join(" ").length;
}

/** Les `layout_*` à `true` sur une journée, dans l'ordre du catalogue. */
function activeLayouts(day: Record<string, unknown>): string[] {
  return Object.entries(day)
    .filter(([key, value]) => key.startsWith(LAYOUT_FLAG_PREFIX) && value === true)
    .map(([key]) => key);
}

/** Le layout qui décide du rendu : le premier drapeau actif l'emporte. */
function mainLayout(day: Record<string, unknown>): string {
  return activeLayouts(day)[0] ?? "layout_story_opener";
}

/**
 * Combien de caractères cette page-là accepte.
 *
 * Trois correctifs s'appliquent à la capacité de base, tous mesurés :
 *
 * - la **carte info rétrécit la colonne**. Sur `layout_split_left` et
 *   `layout_chapter_map`, l'encart occupe 173 pt : le récit passe de ~59 à ~24
 *   caractères par ligne. C'est le piège principal du barème — un `fun_facts`
 *   sur ces deux layouts retire une taille ;
 * - une **ouverture de chapitre qui porte aussi une bande d'images** doit loger
 *   la carte *et* les photos ;
 * - un **bloc interactif** (`prompt`, `quiz`) remplace la zone flottante du bas
 *   et libère de la place — mais seul le layout par défaut en rend un.
 */
export function pageCapacity(day: Record<string, unknown>): number {
  const layout = mainLayout(day);
  const suite = !day["day_intro"];
  const table = LAYOUT_CAPACITY[layout] ?? DEFAULT_CAPACITY;
  let capacity = suite ? table.suite : table.bandeau;

  const photos = Array.isArray(day["photos"]) ? day["photos"].length : 0;
  const funFact = Array.isArray(day["fun_facts"]) && day["fun_facts"].length > 0;

  if (layout === "layout_chapter_map" && photos >= 2) {
    capacity = funFact ? 120 : suite ? 500 : 320;
  } else if (layout === "layout_split_left" && funFact) {
    capacity = 240;
  }

  const parDefaut = layout === "layout_story_opener" || layout === "layout_story_facts";
  if (parDefaut && (day["prompt"] || day["quiz"])) capacity = Math.max(capacity, 760);

  return capacity;
}

/**
 * Une **étape** est une ou plusieurs entrées consécutives de `days[]` : la
 * première porte le bandeau `day_intro`, les suivantes enchaînent le récit sans
 * le remettre (LAYOUT_KB § « Étapes, chapitres et sauts de page »). Le barème
 * se mesure sur l'étape entière, c'est donc ce découpage-là qu'il faut faire
 * avant de compter quoi que ce soit.
 */
export function groupSteps(
  days: Record<string, unknown>[],
): { start: number; days: Record<string, unknown>[] }[] {
  const steps: { start: number; days: Record<string, unknown>[] }[] = [];
  for (const [index, day] of days.entries()) {
    if (day["day_intro"] || steps.length === 0) {
      steps.push({ start: index, days: [day] });
    } else {
      (steps[steps.length - 1] as { days: Record<string, unknown>[] }).days.push(day);
    }
  }
  return steps;
}

/** Le layout à conseiller pour loger `chars` caractères sur une page. */
function fallbackLayout(chars: number, day: Record<string, unknown>): string {
  if (chars < STEP_SIZES.S.min) {
    return day["map"] ? "layout_chapter_map" : "layout_hero_top";
  }
  const candidat = Object.entries(LAYOUT_CAPACITY).find(
    ([flag, capacity]) => flag !== "layout_photo_page" && capacity.bandeau >= chars,
  );
  // Au-delà de la plus grande capacité d'une page, aucun layout ne sauve
  // l'étape : c'est le découpage qui doit changer, pas le drapeau.
  return candidat ? candidat[0] : "";
}

/**
 * Contrôles de longueur d'une étape : la taille du barème, le découpage en
 * paragraphes qu'elle implique, et la capacité de chacune de ses pages.
 */
function checkStep(
  step: { start: number; days: Record<string, unknown>[] },
  errors: ValidationIssue[],
  warnings: ValidationIssue[],
): void {
  // `layout_photo_page` ne rend pas de récit : ces pages ne comptent ni dans la
  // longueur de l'étape, ni dans son nombre de pages.
  const recit = step.days.filter((day) => mainLayout(day) !== "layout_photo_page");
  const chars = recit.reduce((total, day) => total + bodyLength(day), 0);
  const at = `days[${step.start}]`;

  for (const [offset, day] of step.days.entries()) {
    const index = step.start + offset;
    const longueur = bodyLength(day);
    const capacity = pageCapacity(day);
    const layout = mainLayout(day);

    if (layout === "layout_photo_page") {
      if (longueur > 0) {
        warnings.push({
          path: `days[${index}].body_html`,
          message:
            `${longueur} caractères sur un \`layout_photo_page\`, qui ne rend aucun récit — ` +
            "le texte serait perdu. Déplace-le sur la page précédente ou change de layout.",
        });
      }
      continue;
    }

    const body = day["body_html"];
    const paragraphes = typeof body === "string" ? splitParagraphs(body).length : 0;
    const plafondParagraphes = day["day_intro"]
      ? PARAGRAPHS_PER_PAGE.bandeau
      : PARAGRAPHS_PER_PAGE.suite;

    if (paragraphes > plafondParagraphes) {
      errors.push({
        path: `days[${index}].body_html`,
        message:
          `${paragraphes} paragraphes sur une ${day["day_intro"] ? "page à bandeau" : "page de suite"}, ` +
          `qui en porte ${plafondParagraphes} — chaque paragraphe est suivi d'une ligne vide, et ` +
          "celle de trop pousse le contenu sous la marge. Regroupe deux idées, ou " +
          "scinde l'étape en deux entrées consécutives.",
      });
    }

    if (longueur > capacity) {
      const repli = fallbackLayout(longueur, day);
      errors.push({
        path: `days[${index}].body_html`,
        message:
          `${longueur} caractères sur \`${layout}\`, qui en tient ${capacity} ` +
          `(${day["day_intro"] ? "page à bandeau" : "page de suite"}) — la bande de photos ` +
          "serait écrasée ou le texte passerait sous la marge. " +
          (repli
            ? `Bascule sur \`${repli}\`, ou scinde l'étape en deux entrées consécutives.`
            : "Scinde l'étape en deux entrées consécutives : la seconde n'a pas de " +
              "bandeau et accepte 880 caractères."),
      });
    }
  }

  if (recit.length === 0) return;


  if (chars > EDITORIAL_LIMITS.stepMaxChars) {
    errors.push({
      path: at,
      message:
        `${chars} caractères pour l'étape — maximum ${EDITORIAL_LIMITS.stepMaxChars} ` +
        `(taille XL, deux pages). ${LENGTH_HINTS.tropLong}`,
    });
    return;
  }

  const size = sizeForStep(chars);

  /*
   * Sous le minimum de S, la page reste aux trois quarts vide. La sévérité
   * dépend de ce qu'on pouvait faire :
   *
   * - une image ou une carte porte déjà la page → rien à redire ;
   * - le layout ne respire pas mais l'étape a des photos → **refus**, parce
   *   qu'un layout qui aurait tenu la page était disponible et n'a pas été
   *   choisi. C'est le cas que le barème vise ;
   * - ni photo ni carte → **avertissement** seulement. Refuser un carnet
   *   entier parce qu'un souvenir est court, alors qu'aucun layout n'aurait
   *   fait mieux, coûterait à l'utilisateur ce qu'il n'a pas les moyens de
   *   corriger. Une page trop vide s'imprime ; une page qui déborde, non.
   */
  if (!size) {
    const aQuoiSeRaccrocher = recit.filter((day) => !carriedByImage(day));
    const auraitPu = aQuoiSeRaccrocher.filter(
      (day) => (Array.isArray(day["photos"]) ? day["photos"].length : 0) >= 1 || day["map"],
    );

    if (auraitPu.length > 0) {
      errors.push({
        path: at,
        message:
          `${chars} caractères pour l'étape, sous le minimum de S (${STEP_SIZES.S.min}), ` +
          `sur un layout de récit. À cette longueur la page reste aux trois quarts vide : ` +
          `bascule sur \`${auraitPu[0]?.["map"] ? "layout_chapter_map" : "layout_hero_top"}\`, ` +
          "qui tient la page par l'image ou la carte.",
      });
    } else if (aQuoiSeRaccrocher.length > 0) {
      warnings.push({
        path: at,
        message:
          `${chars} caractères pour l'étape, sous le minimum de S (${STEP_SIZES.S.min}), ` +
          "et rien pour porter la page — ni photo, ni carte. Elle s'imprimera très aérée. " +
          "Fusionne-la avec l'étape voisine si le récit s'y prête.",
      });
    }
    return;
  }

  const attendu = STEP_SIZES[size];

  if (recit.length > attendu.pages) {
    warnings.push({
      path: at,
      message:
        `étape de taille ${size} étalée sur ${recit.length} pages — ${attendu.pages} suffi` +
        `${attendu.pages > 1 ? "sent" : "t"} pour ${chars} caractères.`,
    });
  }

}

function checkDay(
  day: Record<string, unknown>,
  index: number,
  errors: ValidationIssue[],
  warnings: ValidationIssue[],
): void {
  const at = (field: string) => `days[${index}].${field}`;

  const activeLayouts = Object.entries(day)
    .filter(([key, value]) => key.startsWith(LAYOUT_FLAG_PREFIX) && value === true)
    .map(([key]) => key);

  if (activeLayouts.length === 0) {
    errors.push({
      path: `days[${index}]`,
      message:
        "aucun layout activé — le jour ne serait pas rendu. Active exactement " +
        "un `layout_*` (voir LAYOUT_KB.md § « Sélection rapide du layout »).",
    });
  } else if (activeLayouts.length > EDITORIAL_LIMITS.maxLayoutsPerDay) {
    errors.push({
      path: `days[${index}]`,
      message: `${activeLayouts.length} layouts activés (${activeLayouts.join(", ")}) — maximum ${EDITORIAL_LIMITS.maxLayoutsPerDay}.`,
    });
  } else if (activeLayouts.length === EDITORIAL_LIMITS.maxLayoutsPerDay) {
    warnings.push({
      path: `days[${index}]`,
      message:
        `${activeLayouts.length} layouts activés (${activeLayouts.join(", ")}). ` +
        "LAYOUT_KB recommande un seul layout fort par jour.",
    });
  }

  for (const field of ["body_html", "opener_body_html"] as const) {
    const value = day[field];
    if (typeof value !== "string") continue;

    const paragraphs = splitParagraphs(value);
    for (const [paragraphIndex, paragraph] of paragraphs.entries()) {
      if (paragraph.length > EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph) {
        errors.push({
          path: `${at(field)}[¶${paragraphIndex + 1}]`,
          message:
            `${paragraph.length} caractères — maximum ${EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph}, ` +
            "soit la taille S : au-delà, c'est un mur de texte quelle que soit la taille " +
            "de l'étape. Coupe-le en deux `<p>`.",
        });
      }
    }
  }

  const funFacts = day["fun_facts"];
  if (Array.isArray(funFacts)) {
    for (const [factIndex, fact] of funFacts.entries()) {
      if (typeof fact === "string" && fact.length > EDITORIAL_LIMITS.funFactChars) {
        errors.push({
          path: `${at("fun_facts")}[${factIndex}]`,
          message: `${fact.length} caractères — maximum ${EDITORIAL_LIMITS.funFactChars}.`,
        });
      }
    }
  }

  const highlights = day["highlights"];
  if (Array.isArray(highlights)) {
    if (highlights.length > EDITORIAL_LIMITS.maxHighlights) {
      errors.push({
        path: at("highlights"),
        message: `${highlights.length} bullets — maximum ${EDITORIAL_LIMITS.maxHighlights}.`,
      });
    }
    for (const [bulletIndex, bullet] of highlights.entries()) {
      if (
        typeof bullet === "string" &&
        bullet.length > EDITORIAL_LIMITS.highlightChars
      ) {
        errors.push({
          path: `${at("highlights")}[${bulletIndex}]`,
          message: `${bullet.length} caractères — maximum ${EDITORIAL_LIMITS.highlightChars}.`,
        });
      }
    }
  }
}

function checkEditorialRules(payload: Record<string, unknown>): {
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
} {
  const errors: ValidationIssue[] = [];
  const warnings: ValidationIssue[] = [];

  const introText = payload["intro_text"];
  if (typeof introText === "string") {
    const paragraphs = splitParagraphs(introText);
    for (const [index, paragraph] of paragraphs.entries()) {
      if (paragraph.length > EDITORIAL_LIMITS.introTextCharsPerParagraph) {
        errors.push({
          path: `intro_text[¶${index + 1}]`,
          message: `${paragraph.length} caractères — maximum ${EDITORIAL_LIMITS.introTextCharsPerParagraph}.`,
        });
      }
    }
    if (paragraphs.length > EDITORIAL_LIMITS.introTextMaxParagraphs) {
      warnings.push({
        path: "intro_text",
        message: `${paragraphs.length} paragraphes — LAYOUT_KB en recommande ${EDITORIAL_LIMITS.introTextMaxParagraphs} au maximum.`,
      });
    }
  }

  const days = payload["days"];
  if (Array.isArray(days)) {
    for (const [index, day] of days.entries()) {
      if (day && typeof day === "object") {
        checkDay(day as Record<string, unknown>, index, errors, warnings);
      }
    }

    // Le barème se mesure sur l'étape, pas sur la page : il faut donc regrouper
    // les journées avant de compter.
    const objets = days.filter(
      (day): day is Record<string, unknown> => Boolean(day) && typeof day === "object",
    );
    for (const step of groupSteps(objets)) checkStep(step, errors, warnings);
  }

  return { errors, warnings };
}

/**
 * Valide un payload de carnet. Ne lève jamais : le pipeline a besoin du détail
 * des erreurs pour les remonter à l'utilisateur et, à terme, les renvoyer au
 * modèle pour correction.
 */
export function validatePayload(payload: unknown): ValidationResult {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return {
      valid: false,
      errors: [{ path: "", message: "le payload doit être un objet JSON." }],
      warnings: [],
    };
  }

  const validate = getSchemaValidator();
  const schemaValid = validate(payload);

  const errors: ValidationIssue[] = schemaValid
    ? []
    : (validate.errors ?? []).map((error) => ({
        path: error.instancePath.replace(/^\//, "").replace(/\//g, ".") || "",
        message: `${error.message ?? "invalide"}${
          error.keyword === "required"
            ? ` (${String((error.params as { missingProperty?: string }).missingProperty)})`
            : ""
        }`,
      }));

  const editorial = checkEditorialRules(payload as Record<string, unknown>);
  errors.push(...editorial.errors);

  return { valid: errors.length === 0, errors, warnings: editorial.warnings };
}

/** Variante levante, pour les appels où un payload invalide est un bug. */
export function assertValidPayload(payload: unknown): void {
  const result = validatePayload(payload);
  if (!result.valid) {
    const details = result.errors
      .map((issue) => `  - ${issue.path || "(racine)"}: ${issue.message}`)
      .join("\n");
    throw new Error(`Payload de carnet invalide :\n${details}`);
  }
}
