import { describe, expect, it } from "vitest";
import { readScores } from "./photoBeauty.js";
import { photosLesPlusNettes, type PhotoQuality } from "./photoPicking.js";

/**
 * **Ce que vaut une photo à regarder** (T265, 23/11/2026) : ce que le modèle
 * rend, et ce que sa note change au moment de choisir.
 */

type Photo = { nom: string } & PhotoQuality;

const choisir = (photos: Photo[], combien: number) =>
  photosLesPlusNettes(photos, combien, (photo) => photo).map((photo) => photo.nom);

describe("relire ce que le juge rend", () => {
  const connues = new Set(["a", "b"]);

  it("garde les notes bien formées, bornées à 0–100", () => {
    const rendu = '{"photos":[{"photo_id":"a","score":87.4},{"photo_id":"b","score":140}]}';
    expect(readScores(rendu, connues)).toEqual([
      { id: "a", score: 87 },
      { id: "b", score: 100 },
    ]);
  });

  /**
   * Un modèle rend n'importe quoi un jour sur cent. Une entrée douteuse
   * s'écarte seule : les autres notes restent, et la photo écartée se rangera
   * sur sa netteté.
   */
  it("écarte ce qui ne se lit pas, sans perdre le reste", () => {
    const rendu = [
      '{"photos":[',
      '{"photo_id":"inventee","score":90},',
      '{"photo_id":"a","score":"beaucoup"},',
      '{"photo_id":"b","score":42},',
      '{"photo_id":"b","score":10}',
      "]}",
    ].join("");
    expect(readScores(rendu, connues)).toEqual([{ id: "b", score: 42 }]);
  });

  it("ne tombe pas sur un JSON tordu ni sur rien du tout", () => {
    expect(readScores("{pas du json", connues)).toEqual([]);
    expect(readScores(null, connues)).toEqual([]);
    expect(readScores('{"photos":"beaucoup"}', connues)).toEqual([]);
  });
});

/**
 * **La beauté passe avant la netteté.** La netteté seule gardait la photo
 * nette d'un mur plutôt que la photo un peu molle d'un visage.
 */
describe("la note du juge dans le choix", () => {
  it("préfère la belle à la nette", () => {
    const photos: Photo[] = [
      { nom: "mur-net", sharpness: 300, beauty: 10 },
      { nom: "visage-mou", sharpness: 60, beauty: 90 },
    ];
    expect(choisir(photos, 1)[0]).toBe("visage-mou");
  });

  /** Une photo trop floue pour l'impression ne se rattrape pas en étant jolie. */
  it("ne sauve pas une photo refusée", () => {
    const photos: Photo[] = [
      { nom: "refusee-mais-belle", sharpness: 5, beauty: 99, verdict: "reject" },
      { nom: "ordinaire", sharpness: 80, beauty: 30 },
    ];
    expect(choisir(photos, 1)[0]).toBe("ordinaire");
  });

  /**
   * Une photo que le juge n'a pas vue se range **au milieu** : on ne la
   * privilégie pas, on ne la condamne pas pour une note qui manque. C'est la
   * doctrine de la netteté absente, appliquée à la note — et elle compte,
   * parce qu'un carnet mêle toujours des photos notées et des photos qui
   * viennent d'arriver.
   */
  it("ne condamne pas une photo pas encore notée", () => {
    const photos: Photo[] = [
      { nom: "mediocre", sharpness: 200, beauty: 20 },
      { nom: "pas-notee", sharpness: 100 },
      { nom: "belle", sharpness: 100, beauty: 80 },
    ];
    // La fonction réordonne, elle ne tronque pas : les écartées restent
    // derrière, dans leur ordre.
    expect(choisir(photos, 2)).toEqual(["pas-notee", "belle", "mediocre"]);
  });

  it("départage deux notes égales sur la netteté, puis sur l'ordre", () => {
    const photos: Photo[] = [
      { nom: "1", sharpness: 50, beauty: 70 },
      { nom: "2", sharpness: 150, beauty: 70 },
      { nom: "3", sharpness: 150, beauty: 70 },
    ];
    expect(choisir(photos, 2)).toEqual(["2", "3", "1"]);
  });

  /** Sans aucune note — le juge éteint —, rien ne change : c'est le repli. */
  it("se comporte comme avant quand personne n'est noté", () => {
    const photos: Photo[] = [
      { nom: "floue", sharpness: 12 },
      { nom: "nette", sharpness: 180 },
    ];
    expect(choisir(photos, 1)[0]).toBe("nette");
  });
});
