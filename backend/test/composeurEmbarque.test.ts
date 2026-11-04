import { readFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * **Le composeur part dans l'image avec tous ses `require`.**
 *
 * `services/bookComposer.ts` charge `MemoBook Generator/public/mise-en-page.js`
 * tel quel, et le Dockerfile le copie **fichier par fichier** — le dossier
 * entier est du navigateur, il n'a rien à faire dans l'image du back-end.
 *
 * C'est fragile par construction : un `require` ajouté dans l'atelier casse
 * l'app sans rien dire. `voyage.js` est arrivé le 08/10/2026 (`6941f81`) et
 * personne n'a touché au Dockerfile ; **toute composition a échoué en
 * production** jusqu'au 04/11, sur « Cannot find module './voyage.js' » —
 * levée à l'import, avant la moindre structuration. Ni la compilation, ni les
 * tests, ni le déploiement ne pouvaient la voir : il fallait un vrai carnet.
 *
 * Ce test suit les `require` depuis le composeur et vérifie que chacun est
 * copié. Il échoue ici, à la seconde, plutôt qu'en production dans un mois.
 */
const RACINE = resolve(import.meta.dirname, "../..");
const COMPOSEUR = resolve(RACINE, "MemoBook Generator/public/mise-en-page.js");
const DOCKERFILE = resolve(RACINE, "backend/Dockerfile");
const DOCKERIGNORE = resolve(RACINE, ".dockerignore");

/** Les fichiers que le composeur atteint, lui compris, chemins absolus. */
function fichiersDuComposeur(): string[] {
  const vus = new Set<string>();
  const àVoir = [COMPOSEUR];

  while (àVoir.length > 0) {
    const fichier = àVoir.pop();
    if (fichier === undefined || vus.has(fichier)) continue;
    vus.add(fichier);

    const source = readFileSync(fichier, "utf8");
    for (const [, cible] of source.matchAll(/require\(\s*["'](\.[^"']+)["']\s*\)/g)) {
      if (cible !== undefined) àVoir.push(resolve(dirname(fichier), cible));
    }
  }

  return [...vus];
}

describe("le composeur embarqué", () => {
  const chemins = () => fichiersDuComposeur().map((fichier) => relative(RACINE, fichier));

  it("est copié dans l'image, lui et ses require", () => {
    const dockerfile = readFileSync(DOCKERFILE, "utf8");
    const manquants = chemins().filter((chemin) => !dockerfile.includes(`"${chemin}"`));

    expect(manquants, `à copier dans backend/Dockerfile : ${manquants.join(", ")}`).toEqual([]);
  });

  /**
   * L'autre moitié de la règle, et celle qui m'a échappé le 04/11/2026 : un
   * `COPY` ne peut rien poser qu'un `.dockerignore` a gardé hors du contexte.
   * Le premier essai de correction avait la ligne de copie sans la ligne
   * d'exception, et la construction s'est arrêtée sur « not found » — le test
   * d'à côté, lui, était vert.
   */
  it("entre dans le contexte de construction", () => {
    const ignore = readFileSync(DOCKERIGNORE, "utf8");
    const exclus = chemins().filter((chemin) => !ignore.includes(`!${chemin}`));

    expect(exclus, `à ré-inclure dans .dockerignore (ligne « ! ») : ${exclus.join(", ")}`).toEqual([]);
  });
});
