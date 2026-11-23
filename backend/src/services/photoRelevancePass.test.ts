import { describe, expect, it } from "vitest";
import { photosLesPlusNettes, type PhotoQuality } from "./photoPicking.js";
import { etapesQuiDebordent, texteDeLaPage } from "./photoRelevancePass.js";

/**
 * **La pertinence** (T265, le dernier tiers) : ce qu'on fait juger, et ce que
 * la note change au moment de choisir.
 *
 * Ce qui se teste ici est le **garde-fou** autant que la règle. La pertinence
 * se recalcule à chaque composition : en demander une de trop, c'est payer
 * pour rien, et ça se répète trente fois sur un carnet.
 */

type Photo = { nom: string } & PhotoQuality;

const choisir = (photos: Photo[], combien: number) =>
  photosLesPlusNettes(photos, combien, (photo) => photo).map((photo) => photo.nom);

const jour = (photos: string[], layout = "layout_collage") => ({
  [layout]: true,
  photos,
});

describe("n'interroger que les étapes qui débordent", () => {
  it("laisse de côté une page dont toutes les photos tiennent", () => {
    // `layout_collage` en dessine trois.
    expect(etapesQuiDebordent([jour(["a.jpg", "b.jpg", "c.jpg"])])).toEqual([]);
  });

  it("retient une page qui en porte plus qu'elle n'en montre", () => {
    const debordante = jour(["a.jpg", "b.jpg", "c.jpg", "d.jpg"]);
    expect(etapesQuiDebordent([debordante])).toEqual([debordante]);
  });

  it("compte selon le gabarit, pas selon un nombre fixe", () => {
    // `layout_hero_top` n'en montre qu'une : deux photos débordent déjà.
    expect(etapesQuiDebordent([jour(["a.jpg", "b.jpg"], "layout_hero_top")])).toHaveLength(1);
    // `layout_photo_page` en montre cinq : trois tiennent.
    expect(etapesQuiDebordent([jour(["a.jpg", "b.jpg", "c.jpg"], "layout_photo_page")])).toEqual([]);
  });

  it("ignore une page sans photo, ou dont les photos ne sont pas une liste", () => {
    expect(etapesQuiDebordent([{ layout_collage: true }])).toEqual([]);
    expect(etapesQuiDebordent([{ layout_collage: true, photos: "a.jpg" }])).toEqual([]);
  });
});

describe("le texte qu'on montre au juge", () => {
  it("assemble le titre, le lieu et le récit, sans balises", () => {
    const texte = texteDeLaPage({
      title: "Adieu Kane, cap sur Naxos",
      day_intro: { location: "Paros" },
      body_html: "<p>On a rendu le scooter,<br>puis pris le ferry.</p>",
    });
    expect(texte).toBe("Adieu Kane, cap sur Naxos\nParos\nOn a rendu le scooter, puis pris le ferry.");
  });

  /** Le lieu est souvent déjà dans le titre : le répéter n'apprend rien. */
  it("ne répète pas deux fois la même chose", () => {
    expect(texteDeLaPage({ title: "Paros", city: "Paros" })).toBe("Paros");
  });

  it("rend une chaîne vide quand la page n'a rien à dire", () => {
    expect(texteDeLaPage({})).toBe("");
  });
});

/**
 * **Les deux notes pèsent autant.** Une belle photo qui ne raconte pas la
 * page n'a pas sa place ; une photo juste mais ratée non plus. Les
 * hiérarchiser reviendrait à décréter laquelle des deux fautes est la pire.
 */
describe("mêler la beauté et la pertinence", () => {
  it("préfère la photo qui raconte la page à la plus jolie", () => {
    const photos: Photo[] = [
      { nom: "jolie-hors-sujet", beauty: 90, relevance: 10 },
      { nom: "juste-et-correcte", beauty: 60, relevance: 80 },
    ];
    expect(choisir(photos, 1)[0]).toBe("juste-et-correcte");
  });

  it("n'écarte pas une photo juste parce qu'elle est moyennement belle", () => {
    const photos: Photo[] = [
      { nom: "tres-belle-hors-sujet", beauty: 100, relevance: 0 },
      { nom: "moyenne-mais-juste", beauty: 50, relevance: 90 },
    ];
    expect(choisir(photos, 1)[0]).toBe("moyenne-mais-juste");
  });

  /**
   * Le cas courant : la pertinence n'est calculée que sur les étapes qui
   * débordent, donc la plupart des photos n'en ont pas. La beauté décide
   * alors seule.
   */
  it("laisse la beauté décider seule quand la pertinence manque", () => {
    const photos: Photo[] = [
      { nom: "belle", beauty: 80 },
      { nom: "fade", beauty: 20 },
    ];
    expect(choisir(photos, 1)[0]).toBe("belle");
  });

  it("laisse la pertinence décider seule quand la beauté manque", () => {
    const photos: Photo[] = [
      { nom: "juste", relevance: 85 },
      { nom: "hors-sujet", relevance: 15 },
    ];
    expect(choisir(photos, 1)[0]).toBe("juste");
  });

  /** Le verdict d'impression reste au-dessus des deux. */
  it("ne sauve pas une photo refusée, même juste et belle", () => {
    const photos: Photo[] = [
      { nom: "refusee", beauty: 95, relevance: 95, verdict: "reject" },
      { nom: "ordinaire", beauty: 40, relevance: 40 },
    ];
    expect(choisir(photos, 1)[0]).toBe("ordinaire");
  });
});
