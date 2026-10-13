#!/usr/bin/env tsx
/**
 * Fabrique `MemoBook Generator/public/ratio-photos.js` depuis
 * `src/services/photoRatio.ts`.
 *
 *   npm run ratio:build          régénère le fichier
 *   npm run ratio:build -- --check   vérifie seulement qu'il est à jour
 *
 * ## Pourquoi un fichier généré
 *
 * Le calcul du ratio texte / photo doit tourner **aux deux bouts** : dans le
 * back-end, parce que le chat annonce au voyageur le nombre exact de photos
 * qu'il lui faut ; dans l'atelier, parce que c'est lui qui compose le PDF de
 * travail. Un écart entre les deux est un bug — le chat demanderait trois
 * photos et le carnet en placerait quatre.
 *
 * Or l'atelier est publié **seul** sur GitHub Pages (`pages-atelier.yml`
 * n'envoie que `MemoBook Generator/public/`) : il ne peut rien importer du
 * back-end, et il n'a pas d'étape de construction.
 *
 * Le dépôt a déjà deux réponses à ce problème, et aucune n'est bonne ici :
 * `carte.js` ↔ `mapSvg.ts` sont deux recopies manuelles gardées identiques par
 * un test, et `mise-en-page.js` recopie en code les règles de LAYOUT_KB. Les
 * deux ont dérivé au moins une fois. Ici, on **génère** : la source est unique,
 * la copie n'est pas éditable à la main, et `ratioPhotosAtelier.test.ts` vérifie
 * qu'elle est à jour.
 *
 * Le résultat est un module UMD, comme `partage.js` et `mise-en-page.js` : il
 * s'attache à `window.RatioPhotos` dans le navigateur et répond à `require()`
 * sous Node, pour que les tests du back-end puissent le charger tel quel.
 */
import { buildSync } from "esbuild";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const SOURCE = resolve(import.meta.dirname, "../src/services/photoRatio.ts");
const CIBLE = resolve(import.meta.dirname, "../../MemoBook Generator/public/ratio-photos.js");

const EN_TETE = `/*
 * Ratio texte / photo — combien de photos une étape demande, et sur combien de
 * pages elle se compose.
 *
 * ⚠️ FICHIER GÉNÉRÉ. Ne pas éditer à la main : il est fabriqué depuis
 * \`backend/src/services/photoRatio.ts\` par \`npm run ratio:build\`, et
 * \`backend/test/ratioPhotosAtelier.test.ts\` échoue s'il n'est pas à jour.
 *
 * L'atelier est publié seul sur GitHub Pages : il ne peut pas importer le
 * back-end, et il n'a pas d'étape de construction. Le calcul, lui, doit être le
 * même aux deux bouts — le chat de l'app annonce au voyageur un nombre de
 * photos, et le PDF doit poser exactement celui-là.
 *
 * Les règles, les métriques et les tables de gabarits sont documentées dans le
 * fichier source. Le mode d'emploi est dans
 * \`MemoBook Generator/templates/travel-journal/LAYOUT_KB.md\`.
 */
`;

/** Le module compilé, en IIFE UMD attachée à `RatioPhotos`. */
export function construire(): string {
  const { outputFiles } = buildSync({
    entryPoints: [SOURCE],
    bundle: true,
    write: false,
    format: "iife",
    globalName: "RatioPhotos",
    platform: "neutral",
    target: "es2020",
    charset: "utf8",
    legalComments: "none",
    // Lisible : ce fichier se relit quand une mise en page surprend, et il part
    // en ligne tel quel.
    minify: false,
  });
  const corps = outputFiles[0]!.text;
  return `${EN_TETE}${corps}
// UMD : \`require()\` sous Node (tests du back-end), \`window.RatioPhotos\` dans
// l'atelier. Même forme que \`partage.js\` et \`mise-en-page.js\`.
if (typeof module !== "undefined" && module.exports) module.exports = RatioPhotos;
else if (typeof window !== "undefined") window.RatioPhotos = RatioPhotos;
`;
}

const attendu = construire();
if (process.argv.includes("--check")) {
  const actuel = readFileSync(CIBLE, "utf8");
  if (actuel !== attendu) {
    console.error(
      `${CIBLE} n'est pas à jour avec photoRatio.ts. Lance : npm run ratio:build`,
    );
    process.exit(1);
  }
  console.log("ratio-photos.js est à jour.");
} else {
  writeFileSync(CIBLE, attendu);
  console.log(`${CIBLE} régénéré (${attendu.length} octets).`);
}
