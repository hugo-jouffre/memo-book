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
