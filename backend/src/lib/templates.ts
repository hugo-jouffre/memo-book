import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";

const here = dirname(fileURLToPath(import.meta.url));

/**
 * `templates/travel-journal/` est la source de vérité du format du carnet : le
 * même dossier alimente APITemplate.io via la CI. Le back-end le lit, il ne le
 * duplique pas — toute évolution du template se propage sans changement de code.
 */
export const TEMPLATE_DIR = resolve(here, "../../../templates/travel-journal");

function readTemplateFile(name: string): string {
  const path = resolve(TEMPLATE_DIR, name);
  try {
    return readFileSync(path, "utf8");
  } catch (cause) {
    throw new Error(
      `Impossible de lire ${path}. Le back-end doit tourner depuis le monorepo, ` +
        `à côté du dossier templates/.`,
      { cause },
    );
  }
}

export interface JsonSchema {
  [key: string]: unknown;
}

let cachedAgentSchema: JsonSchema | undefined;
let cachedPayloadSchema: JsonSchema | undefined;
let cachedLayoutKnowledgeBase: string | undefined;

/** Le schéma complet de l'agent (`image_uploads` + `apitemplate_payload`). */
export function loadAgentSchema(): JsonSchema {
  cachedAgentSchema ??= parseYaml(readTemplateFile("gpt_image_schema.yaml")) as JsonSchema;
  return cachedAgentSchema;
}

/**
 * Le seul morceau qui nous intéresse pour valider un rendu : le payload envoyé
 * à APITemplate. On le ré-enracine avec les `$defs` du schéma parent pour que
 * les `$ref: '#/$defs/day'` continuent de résoudre.
 */
export function loadPayloadSchema(): JsonSchema {
  if (cachedPayloadSchema) return cachedPayloadSchema;

  const agentSchema = loadAgentSchema();
  const properties = agentSchema.properties as Record<string, JsonSchema> | undefined;
  const payloadSchema = properties?.["apitemplate_payload"];

  if (!payloadSchema) {
    throw new Error(
      "gpt_image_schema.yaml ne définit plus `properties.apitemplate_payload`.",
    );
  }

  cachedPayloadSchema = {
    $schema: "http://json-schema.org/draft-07/schema#",
    $id: "https://memo-book.com/schemas/apitemplate-payload.json",
    ...payloadSchema,
    $defs: agentSchema["$defs"],
  };

  return cachedPayloadSchema;
}

/** Le mémo de règles éditoriales qui pilote le choix des layouts. */
export function loadLayoutKnowledgeBase(): string {
  cachedLayoutKnowledgeBase ??= readTemplateFile("LAYOUT_KB.md");
  return cachedLayoutKnowledgeBase;
}

/** Le payload d'exemple, utilisé comme référence de style dans les prompts. */
export function loadSamplePayload(): Record<string, unknown> {
  return JSON.parse(readTemplateFile("data.json")) as Record<string, unknown>;
}

/**
 * Un payload de `templates/travel-journal/samples/`.
 *
 * `data.json` n'exerce qu'une partie du gabarit : ni carte de chapitre, ni
 * photo enrichie par l'analyse d'image. Les échantillons couvrent le reste, et
 * c'est à ce titre qu'ils entrent dans la non-régression visuelle.
 */
export function loadNamedPayload(name: string): Record<string, unknown> {
  return JSON.parse(readTemplateFile(`samples/${name}.json`)) as Record<string, unknown>;
}

/** Le gabarit Jinja2 consommé tel quel par APITemplate (`body`). */
export function loadTemplateHtml(): string {
  return readTemplateFile("index.html");
}

/**
 * La feuille de style consommée telle quelle par APITemplate (`css`).
 *
 * Attention : ce n'est pas du CSS nu mais un fragment HTML (`<meta>` puis
 * `<style>…</style>`). APITemplate l'injecte verbatim dans le document ; le
 * rendu local doit faire exactement pareil, sans le ré-encapsuler.
 */
export function loadTemplateCss(): string {
  // `fonts.css` porte les @font-face inlinés en base64 (généré par
  // scripts/build-font-css.ts) ; il est concaténé plutôt que fusionné pour que
  // `style.css` reste éditable à la main. Les deux consommateurs — rendu local
  // et sync APITemplate — doivent faire cette concaténation à l'identique.
  return `${readTemplateFile("fonts.css")}\n${readTemplateFile("style.css")}`;
}

/**
 * Géométrie de page, en points. 1 unité Figma = 1 pt : toute valeur relevée
 * dans la maquette se reporte telle quelle dans `style.css`.
 */
export interface PrintSettings {
  format: string;
  unit: "pt";
  widthPt: number;
  heightPt: number;
  bleedPt: number;
  marginPt: { top: number; right: number; bottom: number; left: number };
  printBackground: boolean;
  preferCSSPageSize: boolean;
  scale: number;
  expectedPageCountForSample: number;
}

let cachedPrintSettings: PrintSettings | undefined;

export function loadPrintSettings(): PrintSettings {
  cachedPrintSettings ??= JSON.parse(readTemplateFile("print.json")) as PrintSettings;
  return cachedPrintSettings;
}
