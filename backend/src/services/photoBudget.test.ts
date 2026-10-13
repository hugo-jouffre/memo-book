import { describe, expect, it } from "vitest";
import { photosWanted } from "./conversationCopy.js";
import { photoBudgetFor } from "./photoBudget.js";

/** Un récit de `n` signes, en un paragraphe. */
const recit = (n: number) => "recit ".repeat(Math.ceil(n / 6)).slice(0, n).trim();

describe("le nombre de photos d'une étape", () => {
  it("est un chiffre exact, fixé par le texte validé et le ratio du voyageur", () => {
    // Le défaut du carnet, 50 % : l'équilibre, et ce que le carnet faisait déjà.
    expect(photoBudgetFor(recit(280)).photos).toBe(2);
    expect(photoBudgetFor(recit(560)).pages).toBe(1);
    // Un récit plus long occupe plus de pages, et chaque page prend ses photos.
    const long = photoBudgetFor(`${recit(400)}\n\n${recit(400)}\n\n${recit(400)}`);
    expect(long.pages).toBeGreaterThan(1);
    expect(long.photos).toBeGreaterThan(2);
  });

  it("suit le ratio réglé par le voyageur, pas seulement la longueur", () => {
    const texte = `${recit(280)}\n\n${recit(260)}`;
    const compte = (photoTextRatio: number) => photoBudgetFor(texte, { photoTextRatio }).photos;
    // À 0 %, le carnet n'a aucune photo : le chat n'en demande aucune.
    expect(compte(0)).toBe(0);
    // Et le réglage se lit comme un curseur : jamais moins de photos en montant.
    expect(compte(25)).toBeGreaterThanOrEqual(1);
    expect(compte(50)).toBeGreaterThanOrEqual(compte(25));
    expect(compte(75)).toBeGreaterThanOrEqual(compte(50));
    expect(compte(100)).toBeGreaterThanOrEqual(compte(75));
  });

  it("rend le plan complet, pour que la composition pose exactement ces photos", () => {
    const budget = photoBudgetFor(`${recit(280)}\n\n${recit(260)}`, { photoTextRatio: 75 });
    expect(budget.ratio).toBe(75);
    expect(budget.layouts).toHaveLength(budget.pages);
    expect(budget.plan.plan.reduce((somme, page) => somme + page.photos, 0)).toBe(budget.photos);
  });

  it("ne réclame qu'une photo quand il n'y a pas encore de récit", () => {
    // Le minimum d'un palier est un rapport de surfaces : sans texte, il n'a
    // pas de sens. Cas réel — « Photos de test » sur un carnet encore vide.
    expect(photoBudgetFor("").photos).toBe(1);
    expect(photoBudgetFor("", { photoTextRatio: 75 }).photos).toBe(1);
    // À 0 %, le carnet ne porte aucune photo, même là.
    expect(photoBudgetFor("", { photoTextRatio: 0 }).photos).toBe(0);
  });

  it("normalise un réglage hors paliers plutôt que de composer au hasard", () => {
    expect(photoBudgetFor(recit(300), { photoTextRatio: 60 }).ratio).toBe(50);
    expect(photoBudgetFor(recit(300), { photoTextRatio: null }).ratio).toBe(50);
  });

  it("se dit au singulier comme au pluriel, page ou pages", () => {
    expect(photosWanted(1, 1)).toBe("Illustre ce souvenir avec une photo : c’est ce qu’il faut pour remplir sa page.");
    expect(photosWanted(6, 2)).toBe(
      "Illustre ce souvenir avec 6 photos : c’est ce qu’il faut pour remplir ses deux pages.",
    );
    expect(photosWanted(9, 3)).toBe(
      "Illustre ce souvenir avec 9 photos : c’est ce qu’il faut pour remplir ses trois pages.",
    );
  });
});
