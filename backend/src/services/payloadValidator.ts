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

/** Limites reprises de LAYOUT_KB.md § « Contraintes de longueur ». */
export const EDITORIAL_LIMITS = {
  introTextCharsPerParagraph: 700,
  introTextMaxParagraphs: 3,
  bodyHtmlCharsPerParagraph: 420,
  bodyHtmlMaxParagraphs: 3,
  funFactChars: 140,
  highlightChars: 80,
  maxHighlights: 3,
  /** LAYOUT_KB : « les layouts sont exclusifs (activer 1 à 2 maximum par jour) ». */
  maxLayoutsPerDay: 2,
} as const;

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
          message: `${paragraph.length} caractères — maximum ${EDITORIAL_LIMITS.bodyHtmlCharsPerParagraph}, le texte déborderait de la page.`,
        });
      }
    }
    if (paragraphs.length > EDITORIAL_LIMITS.bodyHtmlMaxParagraphs) {
      warnings.push({
        path: at(field),
        message: `${paragraphs.length} paragraphes — LAYOUT_KB en recommande ${EDITORIAL_LIMITS.bodyHtmlMaxParagraphs} au maximum.`,
      });
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
