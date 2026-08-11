#!/usr/bin/env tsx
/**
 * Garde-fou du template : dialecte Jinja et invariants de la feuille de style.
 *
 * Le rendu local passe par Nunjucks, APITemplate par Jinja2. Les deux moteurs
 * se ressemblent beaucoup, mais pas assez : ce lint interdit tout ce qui les
 * ferait diverger, pour qu'un rendu local vert garantisse un rendu APITemplate
 * identique. Il vérifie aussi la forme exacte des fichiers envoyés à l'API.
 *
 *   npm run template:lint
 */
import { loadPayloadSchema, loadSamplePayload, loadTemplateHtml } from "../src/lib/templates.js";
import { assertNoNullValues, createTemplateEnvironment } from "../src/services/bookPdf.js";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { TEMPLATE_DIR } from "../src/lib/templates.js";

interface Problem {
  rule: string;
  detail: string;
}

const problems: Problem[] = [];
const fail = (rule: string, detail: string): void => void problems.push({ rule, detail });

const html = loadTemplateHtml();
const rawStyle = readFileSync(resolve(TEMPLATE_DIR, "style.css"), "utf8");
const rawFonts = readFileSync(resolve(TEMPLATE_DIR, "fonts.css"), "utf8");

// ---------------------------------------------------------------------------
// 1. Le gabarit compile avec le moteur du rendu local
// ---------------------------------------------------------------------------

try {
  createTemplateEnvironment().renderString(html, loadSamplePayload());
} catch (error) {
  fail("compilation", `Nunjucks refuse index.html : ${(error as Error).message}`);
}

// ---------------------------------------------------------------------------
// 2. Constructions propres à Jinja2, que Nunjucks ne comprend pas
// ---------------------------------------------------------------------------

const JINJA_ONLY: [RegExp, string][] = [
  [/\{%-?\s*with\b/, "{% with %}"],
  [/\{%-?\s*do\b/, "{% do %}"],
  [/\{%-?\s*(extends|include|import|from)\b/, "{% extends/include/import/from %} — APITemplate ne reçoit qu'un fichier"],
  [/\bnamespace\s*\(/, "namespace()"],
  [/\|\s*(tojson|xmlattr|filesizeformat|pprint|wordwrap|unique|format\s*\()/, "filtre absent de Nunjucks"],
  [/\bloop\.(revindex|cycle|changed|previtem|nextitem)/, "propriété de boucle absente de Nunjucks"],
  [/\bis\s+(none|sameas|undefined)\b/, "test `is none` / `is sameas`"],
  [/\{\{[^}]*\b(True|False|None)\b[^}]*\}\}/, "littéral Python (True/False/None)"],
  [/\{%[^%]*\b(True|False|None)\b[^%]*%\}/, "littéral Python (True/False/None)"],
  [/\{\{[^}]*~[^}]*\}\}/, "concaténation `~`"],
];

for (const [pattern, label] of JINJA_ONLY) {
  if (pattern.test(html)) fail("dialecte", `index.html utilise ${label}, incompatible entre les deux moteurs.`);
}

// ---------------------------------------------------------------------------
// 3. Tableaux : toujours tester la longueur, jamais la vérité
// ---------------------------------------------------------------------------

/**
 * En Jinja2 `[]` est faux, en JavaScript il est vrai. Un `{% if day.photos %}`
 * nu rendrait donc un bloc vide en local et rien du tout chez APITemplate.
 * On extrait du schéma tous les champs de type array et on exige le garde
 * `... | length >= n` sur chacun.
 */
function collectArrayFields(node: unknown, found = new Set<string>()): Set<string> {
  if (typeof node !== "object" || node === null) return found;

  const record = node as Record<string, unknown>;
  const properties = record["properties"] as Record<string, unknown> | undefined;

  if (properties) {
    for (const [name, schema] of Object.entries(properties)) {
      if ((schema as Record<string, unknown>)["type"] === "array") found.add(name);
      collectArrayFields(schema, found);
    }
  }

  for (const key of ["$defs", "items", "additionalProperties"]) {
    const child = record[key];
    if (child && typeof child === "object") {
      if (key === "$defs") {
        for (const sub of Object.values(child as Record<string, unknown>)) collectArrayFields(sub, found);
      } else {
        collectArrayFields(child, found);
      }
    }
  }
  return found;
}

const arrayFields = collectArrayFields(loadPayloadSchema());

for (const field of arrayFields) {
  // `{% if x.photos %}` ou `{% if photos %}` sans `| length` juste après.
  const bare = new RegExp(`\\{%-?\\s*if\\s+(?:[\\w.]+\\.)?${field}\\s*%\\}`, "g");
  for (const match of html.matchAll(bare)) {
    fail(
      "tableau",
      `${match[0]} teste la vérité d'un tableau. Jinja2 considère [] comme faux, ` +
        `JavaScript comme vrai : écris \`{% if x.${field} and x.${field} | length >= 1 %}\`.`,
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Forme des fichiers envoyés à APITemplate
// ---------------------------------------------------------------------------

// Les commentaires CSS peuvent citer <style> ou system-ui pour expliquer la
// règle : on les retire avant de compter, sinon la doc déclenche le lint.
const styleWithoutComments = rawStyle.replace(/\/\*[\s\S]*?\*\//g, "");

const openTags = (styleWithoutComments.match(/<style>/g) ?? []).length;
const closeTags = (styleWithoutComments.match(/<\/style>/g) ?? []).length;

if (openTags !== 1 || closeTags !== 1) {
  fail(
    "style.css",
    `${openTags} <style> et ${closeTags} </style>. APITemplate injecte ce champ ` +
      `verbatim dans le document : il lui faut exactement une paire.`,
  );
}

if (!/^<meta\s+name="viewport"/.test(rawStyle.trimStart())) {
  fail("style.css", "la première ligne doit rester le <meta name=\"viewport\">.");
}

if (styleWithoutComments.includes("**")) {
  fail(
    "style.css",
    "des marqueurs Markdown `**` traînent dans le CSS. Chromium jette " +
      "silencieusement les déclarations qui les contiennent — c'est ainsi que " +
      "`overflow: hidden` avait cessé de s'appliquer sur `.page`.",
  );
}

if (!rawFonts.includes("<style>") || !rawFonts.includes("data:font/woff2;base64,")) {
  fail(
    "fonts.css",
    "le fichier doit être un fragment <style> contenant les polices en base64. " +
      "Régénère-le avec `npm run fonts:build`.",
  );
}

if (/system-ui/.test(styleWithoutComments)) {
  fail(
    "style.css",
    "`system-ui` rend une police différente sur Mac, en CI et chez APITemplate. " +
      "Nomme une famille embarquée.",
  );
}

// ---------------------------------------------------------------------------
// 5. Le payload d'exemple reste rendable
// ---------------------------------------------------------------------------

try {
  assertNoNullValues(loadSamplePayload());
} catch (error) {
  fail("données", (error as Error).message);
}

const rendered = createTemplateEnvironment().renderString(html, loadSamplePayload());
const pages = (rendered.match(/class="page\b/g) ?? []).length;
const expected = 3 + (loadSamplePayload()["days"] as unknown[]).length + 1; // couv + colophon + intro + jours + 4e

if (pages !== expected) {
  fail("pagination", `${pages} pages rendues pour ${expected} attendues sur data.json.`);
}

// ---------------------------------------------------------------------------

if (problems.length === 0) {
  console.log(`✓ template conforme — ${arrayFields.size} champs tableau vérifiés, ${pages} pages`);
  process.exit(0);
}

console.error(`✗ ${problems.length} problème(s) :\n`);
for (const { rule, detail } of problems) console.error(`  [${rule}] ${detail}`);
process.exit(1);
