import { createRequire } from "node:module";
import { describe, expect, it } from "vitest";
import { construire } from "../scripts/build-ratio-photos.js";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  GABARITS,
  MINIMUM_PHOTOS,
  PHOTO_RATIOS,
  PREFERENCES,
  RATIO_TOLERANCE,
  photosRequired,
} from "../src/services/photoRatio.js";
import { LAYOUT_CAPACITY } from "../src/services/payloadValidator.js";

/**
 * L'atelier et l'app calculent-ils le même nombre de photos ?
 *
 * C'est la question à laquelle ce fichier répond, et elle n'est pas théorique :
 * le chat annonce au voyageur « il me faudrait 3 photos », et le PDF doit en
 * poser exactement trois. Un écart entre les deux bouts est un bug, pas une
 * approximation acceptable.
 *
 * `MemoBook Generator/public/ratio-photos.js` est **généré** depuis
 * `photoRatio.ts` (`npm run ratio:build`) : le premier test vérifie qu'il est à
 * jour, les suivants que le module chargé comme l'atelier le charge donne les
 * mêmes réponses que le module importé comme le back-end l'importe.
 */
const require = createRequire(import.meta.url);
const CHEMIN = resolve(import.meta.dirname, "../../MemoBook Generator/public/ratio-photos.js");
const atelier = require(CHEMIN) as typeof import("../src/services/photoRatio.js");

const paragraphe = (n: number) => `<p>${"recit ".repeat(Math.ceil(n / 6)).slice(0, n).trim()}</p>`;
const TEXTES = {
  court: paragraphe(150),
  moyen: paragraphe(280) + paragraphe(260),
  long: paragraphe(300) + paragraphe(300) + paragraphe(300) + paragraphe(300),
};

describe("ratio-photos.js, la copie de l'atelier", () => {
  it("est à jour avec photoRatio.ts", () => {
    // Si ce test échoue : `npm run ratio:build`. Il n'y a rien à corriger à la
    // main dans le fichier publié — il est généré.
    expect(readFileSync(CHEMIN, "utf8")).toBe(construire());
  });

  it("expose la même table de gabarits", () => {
    expect(Object.keys(atelier.GABARITS).sort()).toEqual(Object.keys(GABARITS).sort());
    for (const [nom, gabarit] of Object.entries(GABARITS)) {
      const copie = atelier.GABARITS[nom]!;
      expect(copie.colonne, nom).toBe(gabarit.colonne);
      expect(copie.photos, nom).toEqual(gabarit.photos);
      expect(copie.bande, nom).toEqual(gabarit.bande);
      expect(copie.capacite, nom).toEqual(gabarit.capacite);
      expect(copie.capaciteAvecEncart, nom).toEqual(gabarit.capaciteAvecEncart);
      expect(copie.suiteSeulement, nom).toBe(gabarit.suiteSeulement);
      expect(copie.bandeau, nom).toBe(gabarit.bandeau);
      expect(copie.encart, nom).toBe(gabarit.encart);
      // Les surfaces sont des fonctions : on les confronte sur leurs bornes.
      for (const n of [gabarit.photos.min, gabarit.photos.max]) {
        for (const h of [gabarit.bande.min, gabarit.bande.hauteur, gabarit.bande.max]) {
          expect(copie.surfacePhotos(n, h, atelier.A5), `${nom} ${n}@${h}`).toBeCloseTo(
            gabarit.surfacePhotos(n, h, atelier.A5),
            6,
          );
        }
      }
    }
  });

  it("expose les mêmes préférences et les mêmes minimums", () => {
    expect(atelier.PREFERENCES).toEqual(PREFERENCES);
    expect(atelier.MINIMUM_PHOTOS).toEqual(MINIMUM_PHOTOS);
    expect(atelier.PHOTO_RATIOS).toEqual([...PHOTO_RATIOS]);
    expect(atelier.RATIO_TOLERANCE).toBe(RATIO_TOLERANCE);
    expect(atelier.A5).toEqual(expect.objectContaining({ nom: "a5", ligne: 15.6 }));
  });

  it("rend le même plan sur toute la matrice longueurs × ratios × options", () => {
    for (const [nom, body_html] of Object.entries(TEXTES)) {
      for (const ratio of PHOTO_RATIOS) {
        for (const funFacts of [false, true]) {
          for (const decorations of [false, true]) {
            const options = { funFacts, decorations };
            const cle = `${nom} r=${ratio} ff=${funFacts} dec=${decorations}`;
            expect(atelier.photosRequired({ body_html }, ratio, "a5", options), cle).toEqual(
              photosRequired({ body_html }, ratio, "a5", options),
            );
          }
        }
      }
    }
  });
});

describe("la table des gabarits et celle du validateur", () => {
  /**
   * Les deux décrivent la même chose — ce qu'une page tient — et elles ont
   * divergé une fois : les marges de reliure du 12/10/2026 ont retiré 3 % à
   * chaque page dans `LAYOUT_CAPACITY` sans que `GABARITS` bouge, et le ratio
   * se serait calculé sur des pages plus grandes qu'elles ne sont. Ce test est
   * né de ce conflit de fusion.
   */
  it("donnent les mêmes plafonds de texte, layout par layout", () => {
    for (const [nom, gabarit] of Object.entries(GABARITS)) {
      const attendu = LAYOUT_CAPACITY[nom];
      if (!attendu) continue; // un gabarit propre au ratio, absent du validateur
      expect(gabarit.capacite, nom).toEqual(attendu);
    }
  });

  it("couvrent les mêmes layouts, pour qu'aucun ne passe entre les deux", () => {
    const manquants = Object.keys(LAYOUT_CAPACITY).filter((nom) => !GABARITS[nom]);
    // `layout_recit_photo` est une maquette faite à la main : le ratio ne le
    // choisit pas, il recompose la page sur un gabarit qu'il connaît.
    expect(manquants).toEqual(["layout_recit_photo"]);
  });
});

describe("photosRequired", () => {
  it("ne demande aucune photo à 0 %", () => {
    for (const body_html of Object.values(TEXTES)) {
      const plan = photosRequired({ body_html }, 0);
      expect(plan.photos).toBe(0);
      expect(plan.ratioEstime).toBe(0);
      expect(plan.layouts.every((l) => GABARITS[l]!.photos.max === 0 || l === "layout_chapter_map")).toBe(
        true,
      );
    }
  });

  it("ne rend aucun récit à 100 %, et garde le nombre de pages du texte", () => {
    for (const body_html of Object.values(TEXTES)) {
      const planche = photosRequired({ body_html }, 100);
      const sansPhoto = photosRequired({ body_html }, 0);
      expect(planche.pages).toBe(sansPhoto.pages);
      expect(planche.surfaceTexte).toBe(0);
      expect(planche.photos).toBeGreaterThanOrEqual(2);
      // La première page garde le bandeau : une étape sans bandeau ne se lit
      // plus comme une étape.
      expect(planche.layouts[0]).toBe("layout_photo_wall_intro");
      expect(planche.layouts.slice(1).every((l) => l === "layout_photo_page")).toBe(true);
    }
  });

  it("respecte le minimum de photos de chaque palier", () => {
    for (const body_html of Object.values(TEXTES)) {
      for (const ratio of PHOTO_RATIOS) {
        const minimum = MINIMUM_PHOTOS[ratio];
        if (minimum === null) continue;
        expect(photosRequired({ body_html }, ratio).photos, `r=${ratio}`).toBeGreaterThanOrEqual(
          minimum,
        );
      }
    }
  });

  it("ne demande jamais plus de photos qu'un palier plus haut", () => {
    // Le réglage doit se lire comme un curseur : plus de photos à 75 % qu'à 25 %.
    for (const body_html of Object.values(TEXTES)) {
      const suite = PHOTO_RATIOS.map((r) => photosRequired({ body_html }, r).photos);
      for (let i = 1; i < suite.length; i += 1) {
        expect(suite[i]!, `palier ${PHOTO_RATIOS[i]}`).toBeGreaterThanOrEqual(suite[i - 1]!);
      }
    }
  });

  it("est déterministe : même étape, même ratio, même plan", () => {
    const body_html = TEXTES.moyen;
    for (const ratio of PHOTO_RATIOS) {
      expect(photosRequired({ body_html }, ratio)).toEqual(photosRequired({ body_html }, ratio));
    }
  });

  it("n'ouvre jamais une page sans y porter ni texte ni photo", () => {
    for (const body_html of Object.values(TEXTES)) {
      for (const ratio of PHOTO_RATIOS) {
        for (const page of photosRequired({ body_html }, ratio).plan) {
          expect(page.signes > 0 || page.photos > 0, `r=${ratio} ${page.layout}`).toBe(true);
        }
      }
    }
  });

  it("ne pose jamais un trio sur la première page d'une étape", () => {
    for (const body_html of Object.values(TEXTES)) {
      for (const ratio of PHOTO_RATIOS) {
        const premier = photosRequired({ body_html }, ratio).plan[0]!;
        expect(GABARITS[premier.layout]!.suiteSeulement ?? false).toBe(false);
      }
    }
  });

  it("garde la bande de photos dans les bornes du CSS", () => {
    for (const body_html of Object.values(TEXTES)) {
      for (const ratio of PHOTO_RATIOS) {
        for (const page of photosRequired({ body_html }, ratio).plan) {
          const g = GABARITS[page.layout]!;
          if (g.bande.hauteur <= 0) continue;
          expect(page.hauteurBande, `${page.layout} r=${ratio}`).toBeGreaterThanOrEqual(
            g.bande.min - 0.01,
          );
          expect(page.hauteurBande, `${page.layout} r=${ratio}`).toBeLessThanOrEqual(
            g.bande.max + 0.01,
          );
        }
      }
    }
  });

  it("ne dépasse la tolérance que pour servir le minimum de photos", () => {
    const hors: string[] = [];
    for (const [nom, body_html] of Object.entries(TEXTES)) {
      for (const ratio of PHOTO_RATIOS) {
        const plan = photosRequired({ body_html }, ratio, "a5", { funFacts: true });
        if (plan.horsTolerance && !plan.depassementAssume) hors.push(`${nom} r=${ratio}: ${plan.raison}`);
      }
    }
    // Le rapport des cas hors tolérance est dans docs/ratio-texte-photo.md : s'il
    // s'allonge, c'est une régression, pas une fatalité.
    expect(hors).toEqual([]);
  });

  it("retombe sur le ratio du carnet, et accepte une surcharge par étape", () => {
    const carnet = { photo_ratio: 25 };
    expect(photosRequired({ body_html: TEXTES.moyen }, 25).photos).toBe(
      photosRequired(
        { body_html: TEXTES.moyen },
        // `getPhotoRatio` est la lecture qui rend la surcharge possible plus
        // tard sans refonte : un `photo_ratio` posé sur l'étape gagne.
        atelier.getPhotoRatio({}, carnet),
      ).photos,
    );
    expect(atelier.getPhotoRatio({ photo_ratio: 75 }, carnet)).toBe(75);
    expect(atelier.getPhotoRatio({}, carnet)).toBe(25);
    expect(atelier.getPhotoRatio({}, {})).toBe(50);
  });

  it("journalise T, P, N, les pages et le ratio quand on le lui demande", () => {
    const lignes: string[] = [];
    photosRequired({ body_html: TEXTES.moyen }, 50, "a5", {
      journal: (message, details) => lignes.push(`${message} ${JSON.stringify(details ?? {})}`),
    });
    expect(lignes.some((l) => l.includes("étape reçue") && l.includes('"T"'))).toBe(true);
    expect(lignes.some((l) => l.includes("cible calculée") && l.includes('"P"'))).toBe(true);
    const arret = lignes.find((l) => l.includes("plan arrêté"))!;
    expect(arret).toMatch(/"photos":\d+/);
    expect(arret).toMatch(/"pages":\d+/);
    expect(arret).toMatch(/"ratioEstime":/);
  });

  it("ne touche jamais au texte du voyageur", () => {
    const body_html = "<p>Un récit <em>validé</em> &amp; signé.</p><p>Deuxième idée.</p>";
    for (const ratio of PHOTO_RATIOS) {
      const day = { body_html, title: "Une étape" };
      photosRequired(day, ratio);
      expect(day.body_html).toBe(body_html);
    }
  });
});
