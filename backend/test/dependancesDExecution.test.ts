import { readFileSync, readdirSync, statSync } from "node:fs";
import { builtinModules } from "node:module";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * **Ce que `src/` importe doit survivre à `npm ci --omit=dev`.**
 *
 * L'image d'exécution n'installe pas les dépendances de développement
 * (`backend/Dockerfile`). Un paquet importé par du code de production mais
 * déclaré en `devDependencies` compile, passe les tests, se déploie — et le
 * process meurt au démarrage sur `ERR_MODULE_NOT_FOUND`.
 *
 * C'est arrivé le 13/11/2026 : `sharp`, employé par les ciseaux à stickers
 * (`services/stickerCut.ts`, PR #191), était en `devDependencies`. L'API et le
 * worker n'ont plus démarré, Railway a gardé l'ancienne version de l'API en
 * ligne — elle répondait `status: ok` — et le worker est resté par terre.
 * Aucun carnet ne se composait, et rien ne le disait.
 *
 * Deux importations échappent à la règle, et c'est voulu : `import type`,
 * effacé à la compilation, et l'`import()` dynamique, qu'on enveloppe d'un
 * message clair (`services/bookPdf.ts` pour `playwright-core`).
 */

const BACKEND = resolve(import.meta.dirname, "..");

const manifest = JSON.parse(readFileSync(join(BACKEND, "package.json"), "utf8")) as {
  dependencies: Record<string, string>;
};

/** Les fichiers de `src/` qui partent en production — les tests n'y vont pas. */
function sourcesDeProduction(dossier: string): string[] {
  return readdirSync(dossier).flatMap((entree) => {
    const chemin = join(dossier, entree);
    if (statSync(chemin).isDirectory()) return sourcesDeProduction(chemin);
    if (!chemin.endsWith(".ts") || chemin.endsWith(".test.ts")) return [];
    return [chemin];
  });
}

/**
 * Les paquets d'un fichier : `import … from "x"` et `import "x"`, plus les
 * `export … from "x"`. On laisse de côté `import type`, effacé à la
 * compilation, et les chemins relatifs.
 */
function paquetsImportes(source: string): string[] {
  const statique = /(?:^|\n)\s*(?:import|export)\s+(?!type\s)[\s\S]*?\sfrom\s*["']([^"']+)["']/g;
  const effetDeBord = /(?:^|\n)\s*import\s*["']([^"']+)["']/g;

  const specificateurs = [
    ...[...source.matchAll(statique)].map((m) => m[1]!),
    ...[...source.matchAll(effetDeBord)].map((m) => m[1]!),
  ];

  return specificateurs
    .filter((s) => !s.startsWith(".") && !s.startsWith("#") && !s.startsWith("node:"))
    .map(nomDuPaquet)
    .filter((nom) => !builtinModules.includes(nom));
}

/** `@scope/paquet/sous/chemin` → `@scope/paquet` ; `paquet/sous` → `paquet`. */
function nomDuPaquet(specificateur: string): string {
  const morceaux = specificateur.split("/");
  return specificateur.startsWith("@") ? morceaux.slice(0, 2).join("/") : morceaux[0]!;
}

describe("les dépendances d'exécution", () => {
  const fichiers = sourcesDeProduction(join(BACKEND, "src"));

  it("trouve bien les sources de production", () => {
    expect(fichiers.length).toBeGreaterThan(50);
  });

  it("déclare en `dependencies` tout ce que `src/` importe vraiment", () => {
    const manquants = new Map<string, string[]>();

    for (const fichier of fichiers) {
      for (const paquet of paquetsImportes(readFileSync(fichier, "utf8"))) {
        if (paquet in manifest.dependencies) continue;
        const fichiers = manquants.get(paquet) ?? [];
        fichiers.push(fichier.slice(BACKEND.length + 1));
        manquants.set(paquet, fichiers);
      }
    }

    // Le message porte le remède : le nom du paquet et qui l'importe.
    expect(Object.fromEntries(manquants)).toEqual({});
  });

  it("voit `sharp`, qui est précisément le paquet qui a manqué", () => {
    const ciseaux = readFileSync(join(BACKEND, "src/services/stickerCut.ts"), "utf8");

    expect(paquetsImportes(ciseaux)).toContain("sharp");
    expect(manifest.dependencies).toHaveProperty("sharp");
  });

  it("laisse passer un `import type`, effacé à la compilation", () => {
    expect(paquetsImportes('import type { Browser } from "playwright-core";')).toEqual([]);
  });
});
