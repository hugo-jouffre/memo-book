import { describe, expect, it } from "vitest";
import { photosLesPlusNettes, type PhotoQuality } from "./photoPicking.js";

/** Une photo d'essai : son nom, et ce qu'on en a mesuré. */
type Photo = { nom: string } & PhotoQuality;

const choisir = (photos: Photo[], combien: number) =>
  photosLesPlusNettes(photos, combien, (photo) => photo).map((photo) => photo.nom);

describe("choisir les photos que la page montre", () => {
  it("garde les plus nettes quand la page n'en dessine qu'une partie", () => {
    const photos: Photo[] = [
      { nom: "floue", sharpness: 12 },
      { nom: "nette", sharpness: 180 },
      { nom: "moyenne", sharpness: 90 },
    ];
    // La page en dessine une : c'est la nette, pas la première arrivée.
    expect(choisir(photos, 1)[0]).toBe("nette");
  });

  /**
   * **Le test qui porte la décision.** On choisit par la qualité, on montre
   * dans l'ordre du récit : classer les photos affichées par netteté
   * décroissante ferait arriver le coucher de soleil avant le départ du matin.
   */
  it("rend aux retenues leur ordre d'origine, et laisse les autres derrière", () => {
    const photos: Photo[] = [
      { nom: "1-matin", sharpness: 150 },
      { nom: "2-floue", sharpness: 5 },
      { nom: "3-midi", sharpness: 200 },
      { nom: "4-soir", sharpness: 170 },
    ];
    // Les trois nettes sont 1, 3, 4 — et elles sortent dans cet ordre-là, pas
    // dans l'ordre 3, 4, 1 de leur netteté.
    expect(choisir(photos, 3)).toEqual(["1-matin", "3-midi", "4-soir", "2-floue"]);
  });

  /**
   * 🔴 **Ce test disait l'inverse jusqu'au 28/11/2026** (T310) : il exigeait
   * qu'un verdict `reject` repousse la photo derrière toutes les autres.
   *
   * La mesure dont ce verdict découle a été vérifiée, et elle ne mesure pas
   * le flou mais le **contraste** : une photo illisible de flou garde une
   * valeur haute, et un **ciel uni parfaitement net** tombe à zéro et sort
   * `reject`. Le test protégeait donc un bug — il faisait passer la photo
   * floue devant le ciel.
   */
  it("ne repousse plus une photo sur un verdict qui mesure le contraste", () => {
    const photos: Photo[] = [
      { nom: "ciel-uni-net", sharpness: 0, verdict: "reject", blur: 0.28 },
      { nom: "floue", sharpness: 900, blur: 0.82 },
    ];
    // La page en dessine une : c'est le ciel, qui est net.
    expect(choisir(photos, 1)[0]).toBe("ciel-uni-net");
  });

  it("départage deux photos sur le flou mesuré, sans seuil", () => {
    const photos: Photo[] = [
      { nom: "molle", blur: 0.71 },
      { nom: "nette", blur: 0.26 },
      { nom: "entre-deux", blur: 0.48 },
    ];
    // Classer est relatif : la moins floue devant, quels que soient les
    // chiffres. Aucun seuil n'est nécessaire pour ça, et aucun n'est posé.
    expect(choisir(photos, 2)).toEqual(["nette", "entre-deux", "molle"]);
  });

  it("ne condamne pas une photo faute de mesure du flou", () => {
    const photos: Photo[] = [
      { nom: "nette", blur: 0.26, sharpness: 200 },
      { nom: "non-mesurée", sharpness: 200 },
      { nom: "floue", blur: 0.84, sharpness: 200 },
    ];
    // Entre les deux : après la nette, avant la floue. Une photo d'avant le
    // 28/11/2026, ou une image sans aucun bord à juger, ne doit pas être
    // écartée pour une mesure qui manque.
    expect(choisir(photos, 2)).toEqual(["nette", "non-mesurée", "floue"]);
  });

  it("ne condamne pas une photo faute de toute mesure", () => {
    const photos: Photo[] = [
      { nom: "nette", sharpness: 200 },
      { nom: "non-mesurée" },
    ];
    // Une photo que `jimp` n'a pas su lire passe derrière celle qu'on a
    // mesurée — rien ne permet de la situer autrement —, mais elle reste
    // dans la liste.
    expect(choisir(photos, 2)).toEqual(["nette", "non-mesurée"]);
  });

  it("ne touche à rien quand la page montre tout", () => {
    const photos: Photo[] = [
      { nom: "floue", sharpness: 1 },
      { nom: "nette", sharpness: 999 },
    ];
    expect(choisir(photos, 2)).toEqual(["floue", "nette"]);
    expect(choisir(photos, 5)).toEqual(["floue", "nette"]);
  });

  it("reste stable entre deux photos qu'on ne sait pas départager", () => {
    const photos: Photo[] = [
      { nom: "a", sharpness: 100 },
      { nom: "b", sharpness: 100 },
      { nom: "c", sharpness: 100 },
    ];
    // Rien ne les distingue : l'ordre d'arrivée tranche, et il ne doit pas
    // changer d'une composition à l'autre — l'empreinte du carnet en dépend.
    expect(choisir(photos, 2)).toEqual(["a", "b", "c"]);
  });

  it("ne fait rien d'une page qui ne dessine aucune photo", () => {
    const photos: Photo[] = [{ nom: "a", sharpness: 1 }, { nom: "b", sharpness: 9 }];
    expect(choisir(photos, 0)).toEqual(["a", "b"]);
  });
});
