import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { tmpdir } from "node:os";
import { describe, expect, it } from "vitest";
import { TEMPLATE_DIR, loadSamplePayload, loadTemplateHtml } from "../src/lib/templates.js";
import { assertNoNullValues, createTemplateEnvironment } from "../src/services/bookPdf.js";

/**
 * Le rendu local passe par Nunjucks, APITemplate par Jinja2. Ces tests
 * garantissent que les deux moteurs disent la même chose du même gabarit :
 * sans eux, une régression ne se verrait qu'en production, sur un PDF imprimé.
 */

describe("dialecte du gabarit", () => {
  it("le lint de template passe", () => {
    // Le lint est le contrat complet (dialecte + invariants CSS). On le lance
    // ici pour que `npm test` échoue aussi, pas seulement la CI dédiée.
    expect(() =>
      execFileSync("npx", ["tsx", "scripts/lint-template.ts"], {
        cwd: resolve(import.meta.dirname, ".."),
        stdio: "pipe",
      }),
    ).not.toThrow();
  });

  it("rend le payload d'exemple sans variable manquante", () => {
    const html = createTemplateEnvironment().renderString(loadTemplateHtml(), loadSamplePayload());

    expect(html).not.toContain("{{");
    expect(html).not.toContain("{%");
    expect(html).toContain("Claire et Gus en Colombie");
  });

  it("refuse un null, que Jinja2 imprimerait « None »", () => {
    expect(() => assertNoNullValues({ brand_name: null })).toThrow(/None/);
    expect(() => assertNoNullValues({ days: [{ title: null }] })).toThrow(/days\[0\]\.title/);
    expect(() => assertNoNullValues(loadSamplePayload())).not.toThrow();
  });

  it("traite un tableau vide comme Jinja2, pas comme JavaScript", () => {
    // `fun_facts: []` existe pour de vrai dans data.json (jour 2). En JS le
    // tableau vide est vrai : sans le garde `| length`, la carte s'afficherait
    // vide en local et pas du tout chez APITemplate.
    const environment = createTemplateEnvironment();
    const withEmpty = environment.renderString(
      "{% if x and x | length >= 1 %}CARTE{% endif %}",
      { x: [] },
    );
    expect(withEmpty).toBe("");

    const withItems = environment.renderString(
      "{% if x and x | length >= 1 %}CARTE{% endif %}",
      { x: ["fait"] },
    );
    expect(withItems).toBe("CARTE");
  });
});

// ---------------------------------------------------------------------------
// Oracle : le vrai Jinja2 doit produire le même document
// ---------------------------------------------------------------------------

const ORACLE = `
import json, sys
from jinja2 import Environment, Undefined
source = open(sys.argv[1], encoding="utf8").read()
payload = json.load(open(sys.argv[2], encoding="utf8"))
env = Environment(autoescape=True, undefined=Undefined)
sys.stdout.write(env.from_string(source).render(**payload))
`;

function jinja2Available(): boolean {
  try {
    execFileSync("python3", ["-c", "import jinja2"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/** Neutralise les écarts cosmétiques d'échappement entre les deux moteurs. */
function normalize(html: string): string {
  return html
    .replace(/&#34;/g, "&quot;")
    .replace(/&#39;/g, "&apos;")
    .replace(/&#x27;/g, "&apos;")
    .replace(/>\s+</g, "><")
    .trim();
}

describe.runIf(jinja2Available())("oracle Jinja2", () => {
  it("produit le même document que Nunjucks sur data.json", () => {
    const payloadPath = resolve(tmpdir(), "memobook-oracle-payload.json");
    writeFileSync(payloadPath, JSON.stringify(loadSamplePayload()));

    const fromJinja = execFileSync(
      "python3",
      ["-c", ORACLE, resolve(TEMPLATE_DIR, "index.html"), payloadPath],
      { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 },
    );

    const fromNunjucks = createTemplateEnvironment().renderString(
      loadTemplateHtml(),
      loadSamplePayload(),
    );

    expect(normalize(fromNunjucks)).toBe(normalize(fromJinja));
  });
});
