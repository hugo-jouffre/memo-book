import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * La mise en page de l'atelier (`MemoBook Generator/public/mise-en-page.js`) :
 * l'équivalent, en code, des règles que l'Agent Mise en page de l'app lit dans
 * LAYOUT_KB. Ces tests en gardent les règles qui se vérifient sans navigateur.
 */
const require = createRequire(import.meta.url);
type Jour = Record<string, unknown> & { photos: (string | { url: string })[]; body_html: string };
const M = require("../../MemoBook Generator/public/mise-en-page.js") as {
  composerJours: (etapes: unknown[], options?: Record<string, unknown>) => Jour[];
  cadreDuVoyage: (lieux: unknown[], pays: string, contours: unknown) => [number, number, number, number] | null;
  composition: (plan: unknown) => string;
  layoutAvecEncart: (plan: unknown) => string | null;
  bandeAjustee: (photos: unknown[], avecEncart: boolean) => { poids: number[]; bandeMax: number } | null;
  couperEnDeux: (texte: string[]) => [string[], string[]];
};
const carte = require("../../MemoBook Generator/public/carte.js") as {
  renderMapDataUri: (contours: unknown, requete: unknown) => string;
};
const contours = JSON.parse(
  readFileSync(resolve(import.meta.dirname, "../../assets/maps/countries.json"), "utf8"),
) as Record<string, unknown>;

const phrase = (sujet: string) =>
  `Le matin nous sommes allés voir ${sujet} et nous y sommes restés longtemps, ravis de la journée. `;
const paragrapheDe = (sujet: string, n = 3) => Array.from({ length: n }, () => phrase(sujet)).join("");

const photo = (id: string, format = 0.75) => ({ id, src: `https://exemple.test/${id}.jpg`, format, groupe: false });
const url = (p: string | { url: string }) => (typeof p === "string" ? p : p.url);

function etape(recit: string, photos: ReturnType<typeof photo>[], analyse: unknown = null, lieu = "Paros") {
  return {
    titre: `Étape ${lieu}`,
    lieu,
    destination: "Grèce",
    numero: "01",
    lieuComplet: `${lieu}, Grèce`,
    dateLongue: "22 août 2026",
    recit,
    photos,
    analyse,
  };
}

const texteDes = (jours: Jour[]) => jours.map((j) => j.body_html.replace(/<\/p><p>/g, " ").replace(/<[^>]+>/g, "")).join(" ");
const normal = (t: string) => t.replace(/\s+/g, " ").trim();

describe("mise en page de l'atelier", () => {
  it("met chaque photo sur la page du passage qu'elle illustre", () => {
    // Trois passages longs : la plage, puis le musée, puis le restaurant — trois pages.
    const recit = [paragrapheDe("la plage"), paragrapheDe("le musée"), paragrapheDe("le restaurant"), paragrapheDe("le port")].join(" ");
    const photos = [photo("resto"), photo("plage"), photo("musee")];
    const analyse = {
      photos: [
        { id: "resto", paragraphe: null, scene: "terrasse du port" },
        { id: "plage", paragraphe: 0, scene: "plage" },
        { id: "musee", paragraphe: 1, scene: "musée" },
      ],
    };
    // Sans paragraphe, la photo du restaurant suit son rang ; on la rattache au restaurant.
    analyse.photos[0]!.paragraphe = 2;
    const jours = M.composerJours([etape(recit, photos, analyse)]);
    const pageDe = (id: string) => jours.findIndex((j) => j.photos.some((p) => url(p).includes(`/${id}.`)));
    const texteDeLaPage = (i: number) => jours[i]!.body_html;
    expect(texteDeLaPage(pageDe("plage"))).toContain("la plage");
    expect(texteDeLaPage(pageDe("musee"))).toContain("le musée");
    expect(texteDeLaPage(pageDe("resto"))).toContain("le restaurant");
  });

  it("garde ensemble les photos prises au même endroit", () => {
    const recit = [paragrapheDe("la plage"), paragrapheDe("le musée"), paragrapheDe("le port")].join(" ");
    const photos = [photo("a"), photo("b"), photo("c")];
    const analyse = {
      photos: [
        { id: "a", paragraphe: 0, scene: "plage de sable" },
        { id: "b", paragraphe: 2, scene: "Plage de sable" },
        { id: "c", paragraphe: 1, scene: "musée" },
      ],
    };
    const jours = M.composerJours([etape(recit, photos, analyse)]);
    const pageDe = (id: string) => jours.findIndex((j) => j.photos.some((p) => url(p).includes(`/${id}.`)));
    expect(pageDe("a")).toBe(pageDe("b"));
  });

  it("ne perd aucun mot du récit", () => {
    const recit = Array.from({ length: 9 }, (_, i) => paragrapheDe(`le lieu ${i}`)).join(" ");
    const jours = M.composerJours([etape(recit, [photo("a"), photo("b"), photo("c"), photo("d")])]);
    expect(normal(texteDes(jours))).toBe(normal(recit));
  });

  it("ouvre un chapitre sur une carte à l'arrivée dans un nouveau lieu", () => {
    const situe = (nom: string, lat: number, lon: number) => ({ lieu: { nom, pays: "GR", lat, lon }, photos: [] });
    const options = {
      contours,
      dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r),
    };
    const jours = M.composerJours(
      [
        etape(paragrapheDe("Paros", 2), [], situe("Paros", 37.08, 25.15), "Paros"),
        etape(paragrapheDe("Paros encore", 2), [], situe("Paros", 37.08, 25.15), "Paros"),
        etape(paragrapheDe("Naxos", 2), [], situe("Naxos", 37.1, 25.38), "Naxos"),
      ],
      options,
    );
    // La carte ouvre la première page de l'étape (celle qui porte le bandeau).
    const ouvertures = jours.filter((j) => j["day_intro"]);
    expect(ouvertures.map((j) => Boolean(j["layout_chapter_map"]))).toEqual([true, false, true]);
    expect(String(ouvertures[2]!["map_svg"])).toMatch(/^data:image\/svg\+xml;base64,/);
  });

  it("garde la carte du chapitre quand le récit dépasse ce que tient la page à carte", () => {
    // La page à bandeau tient 540 signes, la page à carte 500 : un récit long
    // se redécoupe pour l'ouverture au lieu de perdre sa carte.
    const situe = (nom: string, lat: number, lon: number) => ({ lieu: { nom, pays: "GR", lat, lon }, photos: [] });
    // Un vocal d'un seul tenant : coupé en paragraphes de 379 signes au plus,
    // la page à bandeau en prend deux, au-delà des 500 de la page à carte.
    const long = (sujet: string) =>
      Array.from({ length: 12 }, (_, i) => `Phrase ${i} sur ${sujet}, avec un peu de matière pour remplir la page du récit.`).join(" ");
    const jours = M.composerJours(
      [
        etape(long("Paros"), [], situe("Paros", 37.08, 25.15), "Paros"),
        etape(long("Naxos"), [], situe("Naxos", 37.1, 25.38), "Naxos"),
      ],
      { contours, dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r) },
    );
    const ouvertures = jours.filter((j) => j["day_intro"]);
    expect(ouvertures.map((j) => Boolean(j["layout_chapter_map"]))).toEqual([true, true]);
    expect(normal(texteDes(jours))).toContain("Phrase 11 sur Naxos");
  });

  it("n'ouvre pas de chapitre sans lieu situé avec certitude", () => {
    const jours = M.composerJours([etape(paragrapheDe("quelque part", 2), [], { lieu: null, photos: [] })], {
      contours,
      dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r),
    });
    expect(jours[0]!["layout_chapter_map"]).toBe(false);
  });

  it("ne laisse pas deux pages en vis-à-vis avec la même composition quand une alternative existe", () => {
    // Deux pages d'une même étape, deux photos chacune : bande de deux photos des deux côtés.
    const recit = Array.from({ length: 4 }, (_, i) => paragrapheDe(`le lieu ${i}`, 2)).join(" ");
    const photos = ["a", "b", "c", "d"].map((id) => photo(id));
    const sans = M.composerJours([etape(recit, photos)], { pagesAvant: 1 });
    // Les gabarits à deux photos des maquettes du 15/10/2026 (photo contournée,
    // photos en tête) ne sont pas une bande : ils varient la double page.
    const comp = (j: Jour) =>
      j["layout_hero_top"]
        ? "hero"
        : j["layout_recit_deux_photos"]
          ? "recit+deux-photos"
          : j["layout_photos_en_tete"]
            ? "photos-en-tete"
            : j.photos.length === 0
              ? "texte"
              : j.photos.length === 1
                ? "texte+photo"
                : `bande${j.photos.length}`;
    // Page 0 à gauche (pagesAvant = 1 : le colophon est la page 1), page 1 à droite.
    expect(comp(sans[0]!)).not.toBe(comp(sans[1]!));
    expect(sans.reduce((n, j) => n + j.photos.length, 0)).toBe(4);
  });

  describe("structure d'une étape", () => {
    // Les pages d'une étape : de sa page à bandeau à la suivante.
    const etapesDe = (jours: Jour[]) =>
      jours.reduce<Jour[][]>((liste, j) => {
        if (j["day_intro"] || !liste.length) liste.push([j]);
        else liste[liste.length - 1]!.push(j);
        return liste;
      }, []);
    const estPlanche = (j: Jour) => Boolean(j["layout_photo_page"]);
    const toutesLesPhotos = (jours: Jour[]) => jours.flatMap((j) => j.photos.map(url));

    it("ne coupe jamais le récit par une page de photos, et compte un nombre de pages pair", () => {
      // L'étape 1 de Paros : ouverture sur la carte, ~770 signes, six photos.
      const recit = [paragrapheDe("le port", 2), paragrapheDe("la plage", 2), paragrapheDe("la ville", 2), paragrapheDe("le soir", 2)].join(" ");
      const photos = ["a", "b", "c", "d", "e", "f"].map((id) => photo(id));
      const jours = M.composerJours([etape(recit, photos, { lieu: { nom: "Paros", pays: "GR", lat: 37.08, lon: 25.15 }, photos: [] })], {
        contours,
        dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r),
      });
      expect(jours[0]!["layout_chapter_map"]).toBe(true);
      expect(jours.length % 2).toBe(0);
      const premiere = jours.findIndex(estPlanche);
      if (premiere >= 0) expect(jours.slice(premiere).every(estPlanche)).toBe(true);
      expect(toutesLesPhotos(jours).sort()).toEqual(photos.map((p) => p.src).sort());
      expect(normal(texteDes(jours))).toBe(normal(recit));
    });

    it("alterne les deux scénarios d'une étape courte : récit sur deux pages, puis texte et page de photos", () => {
      const courte = (lieu: string) => etape(paragrapheDe(lieu, 3), ["1", "2", "3"].map((id) => photo(`${lieu}-${id}`)), null, lieu);
      const etapes = etapesDe(M.composerJours([courte("Paros"), courte("Naxos"), courte("Ios")]));
      expect(etapes.map((e) => e.length)).toEqual([2, 2, 2]);
      // A : deux pages de récit ; B : une page de récit, puis une page de photos ; puis A.
      expect(etapes.map((e) => e.map((j) => (estPlanche(j) ? "photos" : "récit")).join("+"))).toEqual([
        "récit+récit",
        "récit+photos",
        "récit+récit",
      ]);
      // Dans B, la page de récit garde une ou deux photos.
      expect(etapes[1]![0]!.photos.length).toBeGreaterThanOrEqual(1);
      expect(etapes[1]![0]!.photos.length).toBeLessThanOrEqual(2);
    });

    it("répartit le récit d'une étape courte sans photo sur deux pages", () => {
      const recit = paragrapheDe("la plage", 3);
      const jours = M.composerJours([etape(recit, [])]);
      expect(jours).toHaveLength(2);
      expect(normal(texteDes(jours))).toBe(normal(recit));
      const longueurs = jours.map((j) => j.body_html.replace(/<[^>]+>/g, "").length);
      expect(Math.abs(longueurs[0]! - longueurs[1]!)).toBeLessThan(120);
    });

    it("garde un nombre de pages pair et les photos en fin d'étape, quelle que soit la matière", () => {
      for (let n = 1; n <= 10; n += 1) {
        for (const nbPhotos of [0, 1, 2, 3, 5, 7, 9]) {
          const recit = Array.from({ length: n }, (_, i) => paragrapheDe(`le lieu ${i}`, 2)).join(" ");
          const photos = Array.from({ length: nbPhotos }, (_, i) => photo(`p${n}-${i}`, i % 3 ? 0.75 : 1.4));
          const jours = M.composerJours([etape(recit, photos)]);
          const cas = `${n} paragraphe(s), ${nbPhotos} photo(s)`;
          expect(jours.length % 2, cas).toBe(0);
          const premiere = jours.findIndex(estPlanche);
          if (premiere >= 0) expect(jours.slice(premiere).every(estPlanche), cas).toBe(true);
          expect(toutesLesPhotos(jours).sort(), cas).toEqual(photos.map((p) => p.src).sort());
          expect(normal(texteDes(jours)), cas).toBe(normal(recit));
        }
      }
    });
  });

  describe("plafonds d'une étape et photos écartées (décisions du 12/10/2026)", () => {
    const etapesDe = (jours: Jour[]) =>
      jours.reduce<Jour[][]>((liste, j) => {
        if (j["day_intro"] || !liste.length) liste.push([j]);
        else liste[liste.length - 1]!.push(j);
        return liste;
      }, []);
    const nette = { nettete: 600, luminance: 128, ecretage: 0.02 };

    it("ne dépasse jamais six pages, dont deux de photos, et écarte d'abord la floue, puis le doublon, puis la moins bien notée", () => {
      const recit = Array.from({ length: 4 }, (_, i) => paragrapheDe(`le lieu ${i}`, 2)).join(" ");
      const photos = Array.from({ length: 24 }, (_, i) => ({ ...photo(`p${i}`), mesure: nette }));
      photos[3] = { ...photos[3]!, mesure: { ...nette, nettete: 10 } }; // floue
      const analyse = {
        photos: photos.map((p, i) => ({
          id: p.id,
          paragraphe: null,
          // p5 et p6 : même scène, p6 mieux notée ; les autres, une scène chacune.
          scene: i === 5 || i === 6 ? "port" : `scène ${i}`,
          couverture: i === 6 ? 9 : i === 7 ? 1 : 6,
        })),
      };
      const lignes: string[] = [];
      const jours = M.composerJours([etape(recit, photos, analyse)], { journal: (t: string) => lignes.push(t) });
      expect(jours.length).toBeLessThanOrEqual(6);
      expect(jours.length % 2).toBe(0);
      expect(jours.filter((j) => j["layout_photo_page"]).length).toBeLessThanOrEqual(2);
      const imprimees = new Set(jours.flatMap((j) => j.photos.map(url)));
      const ecartees = photos.filter((p) => !imprimees.has(p.src)).map((p) => p.id);
      expect(ecartees.length).toBeGreaterThanOrEqual(3);
      // Dans l'ordre : la floue, le doublon moins bien noté, la plus mal notée.
      expect(ecartees.slice(0, 3).sort()).toEqual(["p3", "p5", "p7"]);
      expect(lignes.some((l) => l.startsWith("photo(s) écartée(s)"))).toBe(true);
    });

    it("n'écrit plus de légende sur les pages de photos", () => {
      const jours = M.composerJours([etape(paragrapheDe("la plage", 2), ["a", "b", "c", "d", "e", "f", "g"].map((id) => photo(id)))]);
      for (const j of jours.filter((x) => x["layout_photo_page"])) expect(j["title"]).toBe("");
    });

    it("imprime une photo exceptionnelle en pleine page, une fois par chapitre au plus", () => {
      const grande = (id: string) => ({ ...photo(id, 0.75), largeur: 3000, hauteur: 4000, mesure: nette });
      const etapePleine = (lieu: string) =>
        etape(paragrapheDe(lieu, 2), [grande(`${lieu}-a`), grande(`${lieu}-b`)], {
          photos: ["a", "b"].map((x) => ({ id: `${lieu}-${x}`, paragraphe: null, couverture: 10 })),
        }, lieu);
      const pleines = (jours: Jour[]) => jours.filter((j) => j["pleine_page"]).length;
      // Quatre étapes courtes au même lieu (A, B, A, B) : deux pages de photos
      // à une photo, mais un seul chapitre, donc une seule pleine page.
      const memeLieu = M.composerJours(["Paros", "Paros", "Paros", "Paros"].map(etapePleine));
      expect(pleines(memeLieu)).toBe(1);
      // Un nouveau lieu ouvre un nouveau chapitre, qui a droit à la sienne.
      const deuxLieux = M.composerJours(["Paros", "Paros", "Naxos", "Naxos"].map(etapePleine));
      expect(pleines(deuxLieux)).toBe(2);
      for (const j of memeLieu.filter((x) => x["pleine_page"])) expect(j.photos).toHaveLength(1);
      expect(etapesDe(memeLieu).every((e) => e.length % 2 === 0)).toBe(true);
    });
  });

  describe("retouches du 13/10/2026", () => {
    const options = { contours, dessinerCarte: (r: unknown) => carte.renderMapDataUri(contours, r) };
    const situe = (ids: string[]) => ({
      lieu: { nom: "Paros", pays: "GR", lat: 37.08, lon: 25.15 },
      photos: ids.map((id) => ({ id, paragraphe: 0 })),
    });

    it("pose une photo au-dessus de la carte de chapitre", () => {
      // Un récit trop long pour la bande de deux photos (plus de 300 signes) :
      // la page de chapitre garde une photo, au-dessus de sa carte.
      const ids = ["a", "b", "c"];
      const jours = M.composerJours([etape(paragrapheDe("le port", 4), ids.map((id) => photo(id)), situe(ids))], options);
      const chapitre = jours.find((j) => j["layout_chapter_map"]);
      expect(chapitre).toBeDefined();
      expect(chapitre!.photos).toHaveLength(1);
      // Les autres photos de l'étape ne sont pas perdues.
      expect(jours.flatMap((j) => j.photos)).toHaveLength(ids.length);
    });

    it("alterne les planches de cinq photos entre colonnes et rangées", () => {
      const photos = Array.from({ length: 16 }, (_, i) => photo(`p${i}`));
      const jours = M.composerJours([etape(paragrapheDe("la plage", 2), photos)]);
      const planches = jours.filter((j) => j["layout_photo_page"] && j.photos.length === 5);
      expect(planches.map((j) => Boolean(j["planche_colonnes"]))).toEqual([true, false]);
    });

    it("donne au contour d'une photo réduite la taille de l'image, pas de l'emplacement", () => {
      // Une photo de groupe n'est jamais rognée : réduite, son tirage occupe
      // une part de l'emplacement, à son format.
      const groupe = { ...photo("groupe", 1.5), groupe: true };
      const jours = M.composerJours([etape(paragrapheDe("le marché", 2), [groupe])]);
      const reduite = jours.flatMap((j) => j.photos).find((p) => typeof p !== "string" && p["fit" as "url"] === "contain") as
        | { tirage?: [number, number] }
        | undefined;
      expect(reduite?.tirage).toBeDefined();
      const [l, h] = reduite!.tirage!;
      expect(Math.max(l, h)).toBe(100);
      expect(Math.min(l, h)).toBeLessThan(100);
    });
  });

  describe("corps du récit ajusté d'un point (décisions du 12/10/2026)", () => {
    // Quatorze phrases en paragraphes de trois : un peu plus que deux pages en
    // 12 pt une fois les coupes faites sur des fins de phrase.
    const recitDe = (phrases: number) => {
      const liste = Array.from({ length: phrases }, (_, i) => phrase(`le lieu ${i}`));
      const paragraphes: string[] = [];
      for (let i = 0; i < liste.length; i += 3) paragraphes.push(liste.slice(i, i + 3).join(""));
      return paragraphes.join("\n\n");
    };

    it("serre le récit en 11 pt plutôt que de lui ajouter des pages", () => {
      const recit = recitDe(14);
      const jours = M.composerJours([etape(recit, [])]);
      expect(jours).toHaveLength(2);
      expect(jours.map((j) => j["taille_texte"])).toEqual(["serre", "serre"]);
      expect(normal(texteDes(jours))).toBe(normal(recit));
    });

    it("ne serre pas un récit qui tient déjà, ni un qui dépasse de plus de 8 %", () => {
      for (const phrases of [12, 17]) {
        const jours = M.composerJours([etape(recitDe(phrases), [])]);
        expect(jours.every((j) => j["taille_texte"] === undefined)).toBe(true);
      }
    });

    it("passe en 13 pt une étape trop courte pour remplir ses pages, sans photo pour combler", () => {
      const court = M.composerJours([etape(paragrapheDe("la plage", 2), [])]);
      expect(court.every((j) => j["taille_texte"] === "ample")).toBe(true);
      // Une photo remplit la page : le corps ne bouge pas.
      const illustre = M.composerJours([etape(paragrapheDe("la plage", 2), [photo("a")])]);
      expect(illustre.every((j) => j["taille_texte"] === undefined)).toBe(true);
    });
  });

  describe("habillage et décors (décisions du 12/10/2026)", () => {
    const doubles = (jours: Jour[], pagesAvant = 1) => {
      const liste: Jour[][] = [];
      jours.forEach((j, i) => {
        if ((pagesAvant + 1 + i) % 2 === 0 || !liste.length) liste.push([j]);
        else liste[liste.length - 1]!.push(j);
      });
      return liste;
    };
    const objets = (j: Jour) => j.photos as unknown as Record<string, unknown>[];
    const carnet = (stickers: unknown[] = [], decorations = 2) => {
      const etapes = ["Paros", "Naxos", "Ios", "Mykonos"].map((lieu, n) =>
        etape(
          `${paragrapheDe(`le jeepney de ${lieu}`, 3)} ${paragrapheDe(`le ferry de ${lieu}`, 3)}`,
          ["a", "b", "c", "d", "e"].map((x) => photo(`${lieu}-${x}`)),
          { photos: ["a", "b", "c", "d", "e"].map((x, i) => ({ id: `${lieu}-${x}`, paragraphe: null, legende: `Vue ${n}${i}`, couverture: 5 + i })) },
          lieu,
        ),
      );
      return M.composerJours(etapes, { stickers, decorations });
    };

    it("habille chaque photo de son scotch, sauf la pleine page", () => {
      for (const j of carnet()) {
        if (j["pleine_page"]) continue;
        for (const p of objets(j)) if (p["fit"] !== "contain") expect(p["tape_corner"]).toBeTruthy();
      }
    });

    it("pose au plus une étiquette et un tracé par double page", () => {
      const jours = carnet();
      expect(jours.some((j) => objets(j).some((p) => p["label"]))).toBe(true);
      for (const d of doubles(jours)) {
        expect(d.flatMap(objets).filter((p) => p["label"]).length).toBeLessThanOrEqual(1);
        expect(d.filter((j) => ["a", "b", "c"].includes(String(j["trace"]))).length).toBeLessThanOrEqual(1);
      }
    });

    it("préfère l'étiquette du voyageur à celle de l'IA", () => {
      const p = { ...photo("riz"), etiquette: "Nos rizières" };
      const jours = M.composerJours([etape(paragrapheDe("les rizières", 4), [p], { photos: [{ id: "riz", legende: "Rizières de Banaue", couverture: 9 }] })]);
      expect(jours.flatMap(objets).find((x) => x["label"])?.["label"]).toBe("Nos rizières");
    });

    it("pose autant de stickers par étape que le réglage, de 1 à 4, aucun à 0 (14/10/2026)", () => {
      const bibliotheque = [
        { fichier: "jeep.png", famille: "jeep", url: "https://exemple.test/jeep.png", mots: ["jeep"] },
        { fichier: "ferry.png", famille: "ferry", url: "https://exemple.test/ferry.png", mots: ["ferry"] },
        { fichier: "chameau.png", famille: "chameau", url: "https://exemple.test/chameau.png", mots: ["chameau"] },
        // Les familles de voyage, qui complètent quand le récit n'en appelle
        // pas assez, en trois variantes chacune.
        ...["appareil-photo", "carte-postale", "boussole", "globe"].flatMap((famille) =>
          [1, 2, 3].map((v) => ({ fichier: `${famille}-${v}.png`, famille, url: `https://exemple.test/${famille}-${v}.png`, mots: [famille] })),
        ),
      ];
      const voyage = (decorations: number) =>
        M.composerJours(
          ["Paros", "Naxos", "Ios", "Mykonos"].map((lieu) =>
            etape(
              `${paragrapheDe(`la jeep et le ferry de ${lieu}`, 2)} ${paragrapheDe(`le port de ${lieu}`, 3)}`,
              ["a", "b", "c", "d", "e"].map((x) => photo(`${lieu}-${x}`)),
              null,
              lieu,
            ),
          ),
          { stickers: bibliotheque, decorations },
        );
      /** Les pages de chaque étape : de sa page à bandeau à la suivante. */
      const pagesParEtape = (jours: Jour[]) =>
        jours.reduce<Jour[][]>((t, j) => (j["day_intro"] ? [...t, [j]] : [...t.slice(0, -1), [...(t.at(-1) ?? []), j]]), []);
      const stickersDe = (j: Jour) => (j["stickers"] as { url: string }[] | undefined) ?? [];
      const parEtape = (jours: Jour[]) => pagesParEtape(jours).map((pages) => pages.flatMap(stickersDe).length);
      const totaux = [0, 1, 2, 3, 4].map((d) => parEtape(voyage(d)).reduce((a, b) => a + b, 0));
      // Chaque cran en pose davantage : « 1 » et « 4 » ne donnent plus le même carnet.
      expect(totaux[0]).toBe(0);
      for (let d = 1; d <= 4; d += 1) expect(totaux[d]!, `réglage ${d} : ${totaux.join(", ")}`).toBeGreaterThan(totaux[d - 1]!);
      // Chaque étape a son compte : les places ne manquent pas.
      for (let d = 1; d <= 4; d += 1) expect(parEtape(voyage(d)), `réglage ${d}`).toEqual([d, d, d, d]);
      // Deux stickers sur une étape de plusieurs pages ne se serrent pas sur la même.
      for (const [e, pages] of pagesParEtape(voyage(2)).entries()) {
        expect(pages.filter((j) => stickersDe(j).length).length, `étape ${e}`).toBe(Math.min(2, pages.length));
      }
      // Jamais deux fois la même famille dans une étape.
      for (const pages of pagesParEtape(voyage(4))) {
        const familles = pages.flatMap(stickersDe).map((s) => s.url.replace(/-\d+\.png$/, ""));
        expect(new Set(familles).size).toBe(familles.length);
      }

      const jours = voyage(4);
      const poses = jours.flatMap((j) => (j["stickers"] as { url: string }[] | undefined) ?? []);
      // Le récit ne parle jamais de chameau.
      expect(poses.map((s) => s.url)).not.toContain("https://exemple.test/chameau.png");
      // Le récit d'abord : la jeep et le ferry sont posés.
      expect(poses.map((s) => s.url)).toContain("https://exemple.test/jeep.png");
      expect(poses.map((s) => s.url)).toContain("https://exemple.test/ferry.png");
      for (const [k, d] of doubles(jours).entries()) {
        const urls = d.flatMap((j) => ((j["stickers"] as { url: string }[] | undefined) ?? []).map((s) => s.url));
        // Jamais deux fois le même sur une double page…
        expect(new Set(urls).size).toBe(urls.length);
        // … ni d'une double page à la suivante.
        const suivante = doubles(jours)[k + 1];
        const urlsSuivantes = (suivante ?? []).flatMap((j) => ((j["stickers"] as { url: string }[] | undefined) ?? []).map((s) => s.url));
        for (const u of urls) expect(urlsSuivantes).not.toContain(u);
        // Deux par page au plus.
        for (const j of d) expect(((j["stickers"] as unknown[]) ?? []).length).toBeLessThanOrEqual(2);
      }
    });

    it("n'imprime plus la mention « Fun fact rédigé par IA » (15/10/2026), et les stickers reprennent son coin", () => {
      const bibliotheque = ["appareil-photo", "carte-postale", "boussole", "globe"].map((famille) => ({
        fichier: `${famille}.png`,
        famille,
        url: `https://exemple.test/${famille}.png`,
        mots: [famille],
      }));
      const jours = M.composerJours(
        ["Paros", "Naxos", "Ios"].map((lieu, n) =>
          etape(
            paragrapheDe(`le port de ${lieu}`, 4),
            ["a", "b", "c", "d"].map((x) => photo(`${lieu}-${x}`)),
            { photos: [], funFacts: [{ texte: `Fait ${n}.`, registre: "histoire", paragraphe: 0, pertinence: 9 }] },
            lieu,
          ),
        ),
        { stickers: bibliotheque, decorations: 4, funFacts: true },
      );
      const avecEncart = jours.filter((j) => (j["fun_facts"] as string[]).length);
      expect(avecEncart.length).toBeGreaterThan(0);
      for (const j of jours) expect(j["ai_note"] ?? "").not.toMatch(/fun fact/i);
    });

    describe("bibliothèque de stickers (Notion, 12/10/2026)", () => {
      const index = JSON.parse(
        readFileSync(resolve(import.meta.dirname, "../../assets/stickers/stickers.json"), "utf8"),
      ) as { stickers: { fichier: string; famille: string; style: string; mots: string[]; maxPt: number; reserve?: string }[] };
      const bibliotheque = index.stickers.map((s) => ({ ...s, url: `https://exemple.test/${s.fichier}` }));
      const posesDe = (jours: Jour[]) =>
        jours.flatMap((j) => (j["stickers"] as { url: string; largeur: number }[] | undefined) ?? []);
      const familleDe = (url: string) => bibliotheque.find((s) => s.url === url)?.famille;
      const voyage = (recits: string[]) =>
        M.composerJours(
          recits.map((recit, n) => etape(recit, [photo(`e${n}-a`), photo(`e${n}-b`)], null, `Lieu ${n}`)),
          { stickers: bibliotheque, decorations: 4 },
        );

      it("pose le sticker dont le récit parle, une famille une fois par double page, jamais un personnage", () => {
        const jours = voyage([
          paragrapheDe("la ville en scooter", 2),
          paragrapheDe("l'aéroport avant notre avion", 2),
          paragrapheDe("la plage de sable blanc", 2),
          paragrapheDe("le marché du matin", 2),
        ]);
        const familles = posesDe(jours).map((s) => familleDe(s.url));
        expect(familles).toContain("scooter");
        expect(familles).toContain("avion");
        expect(familles).not.toContain("personnage");
        for (const d of doubles(jours)) {
          const sur = posesDe(d).map((s) => familleDe(s.url));
          expect(new Set(sur).size).toBe(sur.length);
          expect(sur.length).toBeLessThanOrEqual(4);
        }
      });

      it("lit tout le récit, pas seulement sa première proposition", () => {
        // Le scooter n'arrive qu'après une virgule : on ne lisait que le début.
        const jours = voyage([paragrapheDe("la ville, puis le port en scooter", 2)]);
        expect(posesDe(jours).map((s) => familleDe(s.url))).toContain("scooter");
      });

      it("complète par les familles de voyage quand aucun mot entier du récit n'appelle un sticker", () => {
        // « vanille » ne déclenche pas « van », « visage » pas « visa » : le
        // carnet a ses stickers quand même, mais seulement des familles de voyage.
        const familles = posesDe(voyage([paragrapheDe("un visage, une glace à la vanille", 2)])).map((s) => familleDe(s.url));
        expect(familles.length).toBeGreaterThan(0);
        for (const f of familles) expect(["appareil-photo", "carte-postale", "boussole", "globe", "repere", "carte"]).toContain(f);
      });

      it("ne dépasse jamais la définition du dessin", () => {
        const jours = voyage([paragrapheDe("la ville en scooter", 2), paragrapheDe("la randonnée avec boussole", 2)]);
        for (const s of posesDe(jours)) {
          const sticker = bibliotheque.find((b) => b.url === s.url)!;
          expect(s.largeur).toBeGreaterThan(0);
          expect(s.largeur).toBeLessThanOrEqual(sticker.maxPt);
        }
      });
    });

    it("garde le titre proposé pour le fun fact, et ne répète jamais le même titre deux encarts de suite", () => {
      const analyse = { photos: [], funFact: { texte: "Un fait.", titre: "Culture générale", registre: "histoire", paragraphe: 0, pertinence: 9 } };
      const jours = M.composerJours([etape(paragrapheDe("la plage", 1), [], analyse)], { funFacts: true });
      expect(jours.find((j) => (j["fun_facts"] as string[]).length)?.["fun_facts_title"]).toBe("Culture générale");

      // Six étapes aux fun facts du même registre, sans titre : « Infos »,
      // « Le saviez-vous ? »… varient.
      const tous = M.composerJours(
        ["Paros", "Naxos", "Ios", "Milos", "Sifnos", "Syros"].map((lieu) =>
          etape(paragrapheDe(`le port de ${lieu}`, 2), [], { photos: [], funFact: { texte: `Le port de ${lieu}.`, registre: "cuisine", paragraphe: 0, pertinence: 9 } }, lieu),
        ),
        { funFacts: true },
      );
      const titres = tous.filter((j) => (j["fun_facts"] as string[]).length).map((j) => j["fun_facts_title"] as string);
      expect(titres.length).toBeGreaterThan(1);
      for (const t of titres) expect(["Infos", "Le saviez-vous ?", "Fun fact", "Culture générale"]).toContain(t);
      titres.slice(1).forEach((t, k) => expect(t).not.toBe(titres[k]));
    });
  });

  describe("récit qui contourne une grande photo (maquette faite à la main)", () => {
    it("fait contourner au récit une photo en hauteur, avec son étiquette de titre", () => {
      const analyse = { photos: [{ id: "riz", paragraphe: 0, scene: "rizières en terrasses", legende: "Rizières de Banaue" }] };
      const jours = M.composerJours([etape(paragrapheDe("les rizières", 4), [photo("riz", 0.75)], analyse, "Banaue")]);
      const page = jours.find((j) => j["layout_recit_photo"])!;
      expect(page).toBeTruthy();
      expect(page.photos[0]).toMatchObject({ label: "Rizières de Banaue" });
    });

    it("garde la grande photo en tête pour une photo en largeur", () => {
      const jours = M.composerJours([etape(paragrapheDe("la baie", 2), [photo("baie", 1.5)])]);
      expect(jours.some((j) => j["layout_recit_photo"])).toBe(false);
    });

    it("pose le fun fact en post-it à côté de la photo quand le récit laisse la place", () => {
      const analyse = {
        photos: [{ id: "riz", paragraphe: 0, scene: "rizières" }],
        funFact: { texte: "Les rizières de Banaue ont deux mille ans.", titre: "Infos", registre: "histoire", paragraphe: 0, pertinence: 9 },
      };
      const jours = M.composerJours([etape(paragrapheDe("les rizières", 4), [photo("riz", 0.75)], analyse, "Banaue")], { funFacts: true });
      const page = jours.find((j) => (j["fun_facts"] as string[]).length)!;
      expect(page["layout_recit_photo"]).toBe(true);
      expect(page["fun_facts_title"]).toBe("Infos");
    });
  });

  describe("trios (une photo en haut, deux en bas)", () => {
    // Deux paragraphes courts sur la page à bandeau, un troisième sur la page de suite.
    const recit = [paragrapheDe("la plage", 2), paragrapheDe("le port", 2), paragrapheDe("la ville", 2)].join(" ");
    const layoutDe = (j: Jour) =>
      j["layout_trio_portrait"] ? "trio_portrait" : j["layout_trio_landscape"] ? "trio_landscape" : j["layout_collage"] ? "collage" : "autre";

    it("pose trois portraits d'une page de suite courte en trio portrait", () => {
      const jours = M.composerJours([etape(recit, ["a", "b", "c", "d", "e", "f"].map((id) => photo(id)))]);
      expect(jours).toHaveLength(2);
      expect(jours[0]!["day_intro"]).toBeTruthy();
      expect(layoutDe(jours[0]!)).toBe("collage");
      expect(layoutDe(jours[1]!)).toBe("trio_portrait");
    });

    it("met la photo paysage en bas d'un trio paysage, sous la grande photo (maquettes du 15/10/2026)", () => {
      const photos = ["a", "b", "c", "d", "e"].map((id) => photo(id)).concat(photo("large", 1.5));
      const jours = M.composerJours([etape(recit, photos)]);
      expect(layoutDe(jours[1]!)).toBe("trio_landscape");
      expect(url(jours[1]!.photos[2]!)).toContain("/large.");
      expect(jours[1]!["trio_cote"]).toBe("gauche");
    });

    it("n'en fait jamais sur la première page d'une étape", () => {
      const jours = M.composerJours([etape(paragrapheDe("la plage", 2), ["a", "b", "c"].map((id) => photo(id)))]);
      expect(jours.length % 2).toBe(0);
      expect(jours[0]!["day_intro"]).toBeTruthy();
      expect(layoutDe(jours[0]!)).not.toMatch(/^trio/);
    });

    it("garde le collage quand une photo y serait trop rognée", () => {
      // Deux paysages sur trois : l'une irait dans un emplacement portrait du bas.
      const photos = ["a", "b", "c", "d"].map((id) => photo(id)).concat(photo("l1", 1.5), photo("l2", 1.5));
      const jours = M.composerJours([etape(recit, photos)]);
      expect(jours.map(layoutDe)).not.toContain("trio_landscape");
      expect(jours.map(layoutDe)).not.toContain("trio_portrait");
    });
  });

  describe("cadre des cartes de chapitre", () => {
    const lieu = (nom: string, lat: number, lon: number, pays = "GR") => ({ nom, pays, lat, lon });

    it("se cadre sur les lieux du voyage, pas sur le pays entier", () => {
      const cyclades = [lieu("Paros", 37.08, 25.15), lieu("Naxos", 37.1, 25.38), lieu("Ios", 36.73, 25.28), lieu("Mykonos", 37.45, 25.33)];
      const [o, s, e, n] = M.cadreDuVoyage(cyclades, "GR", contours)!;
      for (const l of cyclades) {
        expect(l.lon).toBeGreaterThan(o);
        expect(l.lon).toBeLessThan(e);
        expect(l.lat).toBeGreaterThan(s);
        expect(l.lat).toBeLessThan(n);
      }
      // Ni Athènes ni la Crète.
      expect(o).toBeGreaterThan(24);
      expect(s).toBeGreaterThan(35.5);
    });

    it("garde au moins un degré de côté autour d'un lieu unique", () => {
      const [o, s, e, n] = M.cadreDuVoyage([lieu("Ios", 36.73, 25.28)], "GR", contours)!;
      expect(n - s).toBeCloseTo(1, 2);
      expect(e - o).toBeGreaterThan(1);
    });

    it("ne dépasse pas le pays quand le voyage le parcourt en entier", () => {
      const tour = [lieu("Thessalonique", 40.64, 22.94), lieu("Héraklion", 35.34, 25.13), lieu("Rhodes", 36.43, 28.22), lieu("Corfou", 39.62, 19.92)];
      const [o, s, e, n] = M.cadreDuVoyage(tour, "GR", contours)!;
      expect(o).toBeGreaterThanOrEqual(19);
      expect(e).toBeLessThanOrEqual(29);
      expect(s).toBeGreaterThanOrEqual(34);
      expect(n).toBeLessThanOrEqual(42.2);
    });

    it("transmet le cadre du voyage, lieux des récits compris, à la carte du chapitre", () => {
      const analyse = (nom: string, lat: number, lon: number, lieux: unknown[] = []) => ({ lieu: lieu(nom, lat, lon), lieux, photos: [] });
      const requetes: { cadre: number[] }[] = [];
      M.composerJours(
        [
          etape(paragrapheDe("le port", 1), [], analyse("Paros", 37.08, 25.15, [lieu("Antiparos", 37.04, 25.08)]), "Paros"),
          etape(paragrapheDe("la plage", 1), [], analyse("Amorgos", 36.83, 25.9), "Amorgos"),
        ],
        { contours, dessinerCarte: (r: { cadre: number[] }) => (requetes.push(r), "data:image/svg+xml;base64,") },
      );
      expect(requetes).toHaveLength(2);
      const [o, , e] = requetes[0]!.cadre;
      expect(o).toBeLessThan(25.08);
      expect(e).toBeGreaterThan(25.9);
      expect(requetes[1]!.cadre).toEqual(requetes[0]!.cadre);
    });
  });

  describe("séjour dans une seule ville", () => {
    const lieu = (nom: string, lat: number, lon: number) => ({ nom, pays: "FR", lat, lon });
    const paris = lieu("Paris", 48.8566, 2.3522);
    const jour = (lieux: ReturnType<typeof lieu>[], sujet: string) =>
      etape(paragrapheDe(sujet, 1), [], { lieu: paris, lieux, photos: [] }, "Paris");
    type Requete = {
      cadre: [number, number, number, number];
      points: { label: string; secondaire?: boolean }[];
      ville?: boolean;
      titre?: string;
    };
    const requetes = (etapes: unknown[]) => {
      const liste: Requete[] = [];
      M.composerJours(etapes, { contours, dessinerCarte: (r: Requete) => (liste.push(r), "data:image/svg+xml;base64,") });
      return liste;
    };

    it("ouvre sur le pays avec la ville située, puis zoome sur la ville et trace les déplacements", () => {
      const cartes = requetes([
        jour([lieu("Tour Eiffel", 48.8584, 2.2945)], "la tour"),
        jour([lieu("Louvre", 48.8606, 2.3376), lieu("Tuileries", 48.8635, 2.327)], "le musée"),
        jour([], "un jour au lit"),
        jour([lieu("Montmartre", 48.8867, 2.3431)], "la butte"),
      ]);
      expect(cartes).toHaveLength(3);

      // Le pays entier, la ville seule.
      const [o, s, e, n] = cartes[0]!.cadre;
      expect(e - o).toBeGreaterThan(8);
      expect(n - s).toBeGreaterThan(8);
      expect(cartes[0]!.points.map((p) => p.label)).toEqual(["Paris"]);

      // La ville : les lieux du jour nommés, la tour Eiffel déjà passée en petit point, le trajet.
      const ville = cartes[1]!;
      expect(ville.cadre[3] - ville.cadre[1]).toBeLessThan(0.3);
      expect(ville.points.map((p) => [p.label, Boolean(p.secondaire)])).toEqual([
        ["Tour Eiffel", true],
        ["Louvre", false],
        ["Tuileries", false],
      ]);
      expect(ville.ville).toBe(true);
      expect(ville.titre).toBe("Paris");

      // Le jour sans nouveau lieu n'ouvre pas de chapitre ; le suivant prolonge le parcours.
      expect(cartes[2]!.points.map((p) => p.label)).toEqual(["Tour Eiffel", "Louvre", "Tuileries", "Montmartre"]);
      expect(cartes[2]!.cadre).toEqual(ville.cadre);
    });

    it("ne prend pas un voyage de plusieurs villes pour un séjour", () => {
      const cartes = requetes([
        etape(paragrapheDe("le port", 1), [], { lieu: lieu("Marseille", 43.2965, 5.3698), photos: [] }, "Marseille"),
        etape(paragrapheDe("la place", 1), [], { lieu: lieu("Lyon", 45.764, 4.8357), photos: [] }, "Lyon"),
      ]);
      expect(cartes[0]!.points.map((p) => p.label)).toEqual(["Marseille"]);
      expect(cartes[0]!.cadre[2] - cartes[0]!.cadre[0]).toBeLessThan(5);
      expect(cartes[1]!.ville).toBeUndefined();
    });
  });

  describe("fun facts", () => {
    const encart = (texte: string, pertinence: number, registre = "histoire") => ({
      photos: [],
      funFact: { texte, titre: "Fun fact", registre, paragraphe: 0, pertinence },
    });
    // Une page par étape : un paragraphe court, sans photo.
    const etapes = (notes: [number, string?][]) =>
      notes.map(([note, registre], i) => etape(paragrapheDe(`le lieu ${i}`, 1), [], encart(`Fait n° ${i}.`, note, registre), `Lieu ${i}`));
    const encarts = (jours: Jour[]) => jours.map((j) => (j["fun_facts"] as string[])[0] ?? null);

    it("n'en met aucun quand le réglage du carnet est coupé", () => {
      expect(encarts(M.composerJours(etapes([[9], [9]]), { funFacts: false }))).toEqual([null, null]);
    });

    it("n'imprime ni un encart sous le seuil de pertinence, ni un encart trop long", () => {
      const jours = M.composerJours(
        [
          etape(paragrapheDe("la plage", 1), [], encart("Un fait sans intérêt.", 4)),
          etape(paragrapheDe("le port", 1), [], encart("x".repeat(141), 9)),
        ],
        { funFacts: true },
      );
      expect(encarts(jours)).toEqual([null, null]);
    });

    it("dit au journal pourquoi un fun fact n'est pas imprimé", () => {
      const lignes: string[] = [];
      M.composerJours(
        [
          etape(paragrapheDe("la plage", 1), [], encart("Un fait sans intérêt.", 4)),
          etape(paragrapheDe("le port", 1), [], { photos: [] }),
          // Deux pages de récit chargées, trois photos sur chacune : pas de place.
          etape(
            Array.from({ length: 4 }, (_, i) => paragrapheDe(`la ville ${i}`, 2)).join(" "),
            ["a", "b", "c", "d", "e", "f"].map((id) => photo(id)),
            encart("Un fait remarquable.", 9),
          ),
        ],
        { funFacts: true, journal: (t: string) => lignes.push(t) },
      );
      const rapport = lignes.find((l) => l.startsWith("fun facts non imprimés")) ?? "";
      expect(rapport).toContain("étape 1 : fun fact(s) noté(s) sous 5/10");
      expect(rapport).toContain("étape 2 : l'analyse n'a proposé aucun fun fact");
      // Les pages de récit de l'étape 3 sont pleines, mais une de ses planches
      // a un emplacement libre (14/10/2026) : son fun fact s'imprime.
      expect(rapport).not.toContain("étape 3");
    });

    it("en met un toutes les trois pages, pile à sa place quand un fun fact y tient", () => {
      const jours = M.composerJours(
        etapes([[7, "histoire"], [9, "vecu"], [7, "cuisine"], [7, "record"], [8, "usage-local"]]),
        { funFacts: true },
      );
      // La promesse est une fréquence : le 7 de la page visée passe devant le
      // 9 ou le 8 d'une page voisine.
      expect(encarts(jours)).toEqual(["Fait n° 0.", null, null, "Fait n° 3.", null]);
      expect(["Infos", "Le saviez-vous ?", "Fun fact", "Culture générale"]).toContain(jours[0]?.["fun_facts_title"]);
      expect(jours[0]?.["ai_note"]).toBeUndefined();
    });

    it("évite deux encarts du même registre à la suite quand il y a mieux", () => {
      const jours = M.composerJours(etapes([[8, "histoire"], [7, "vecu"], [7, "cuisine"], [7, "histoire"]]), {
        funFacts: true,
      });
      // À la page visée, un fun fact du même registre que le précédent ; une
      // page avant, un autre registre : il passe devant.
      expect(encarts(jours)).toEqual(["Fait n° 0.", null, "Fait n° 2.", null]);
    });

    it("tient la promesse d'environ un toutes les trois pages, même dans un carnet chargé en photos", () => {
      // Dix étapes, trois photos par page de récit (comme le carnet de Hugo du
      // 13/10/2026), trois fun facts proposés par étape, notés 5 à 9.
      const lourdes = Array.from({ length: 10 }, (_, e) =>
        etape(
          [paragrapheDe(`la ville ${e}`, 3), paragrapheDe(`le port ${e}`, 3)].join(" "),
          Array.from({ length: 9 }, (_, k) => photo(`${e}-${k}`)),
          {
            photos: [],
            funFacts: [9, 7, 5].map((note, k) => ({ texte: `Fait ${e}.${k}.`, registre: ["vecu", "histoire", "cuisine"][k], paragraphe: 0, pertinence: note })),
          },
          `Lieu ${e}`,
        ),
      );
      const jours = M.composerJours(lourdes, { funFacts: true });
      const poses = jours.map((j, i) => ((j["fun_facts"] as string[]).length ? i : -1)).filter((i) => i >= 0);
      const attendus = Math.round(jours.length / 3);
      expect(Math.abs(poses.length - attendus), `${poses.length} encarts pour ${jours.length} pages`).toBeLessThanOrEqual(1);
      // Jamais plus près que deux pages, jamais au-delà de quatre tant qu'il reste de quoi.
      for (let k = 1; k < poses.length; k += 1) {
        expect(poses[k]! - poses[k - 1]!).toBeGreaterThanOrEqual(2);
        expect(poses[k]! - poses[k - 1]!).toBeLessThanOrEqual(4);
      }
      // Des pages de photos en portent, dans un emplacement de la planche.
      expect(poses.some((i) => jours[i]!["layout_photo_page"] && Number.isInteger(jours[i]!["case_fun_fact"]))).toBe(true);
      // Ni photo perdue ni étape impaire.
      expect(jours.flatMap((j) => j.photos)).toHaveLength(90);
      const tailles = jours.reduce<number[]>((t, j) => (j["day_intro"] ? [...t, 1] : [...t.slice(0, -1), (t.at(-1) ?? 0) + 1]), []);
      expect(tailles.every((n) => n % 2 === 0)).toBe(true);
    });

    it("met le fun fact à la place d'une photo, jamais par-dessus (14/10/2026)", () => {
      // Des étapes chargées de photos : leurs pages de récit n'ont plus la
      // place d'une carte, leurs planches ont un emplacement libre.
      const lourdes = Array.from({ length: 6 }, (_, e) =>
        etape(
          [paragrapheDe(`la ville ${e}`, 3), paragrapheDe(`le port ${e}`, 3)].join(" "),
          Array.from({ length: 9 }, (_, k) => photo(`${e}-${k}`)),
          { photos: [], funFacts: [9, 8, 7].map((note, k) => ({ texte: `Fait ${e}.${k}.`, registre: ["vecu", "histoire", "cuisine"][k], paragraphe: 0, pertinence: note })) },
          `Lieu ${e}`,
        ),
      );
      const jours = M.composerJours(lourdes, { funFacts: true });
      const enCase = jours.filter((j) => j["case_fun_fact"] !== undefined);
      expect(enCase.some((j) => j["layout_photo_page"])).toBe(true);
      for (const j of enCase) {
        // La page de k photos prend le gabarit de k + 1 : l'emplacement existe,
        // et c'est l'encart de la page qui l'occupe.
        const k = j.photos.length;
        expect((j["fun_facts"] as string[]).length).toBe(1);
        expect(k + 1).toBeLessThanOrEqual(j["layout_photo_page"] ? 5 : 3);
        expect(j["case_fun_fact"]).toBeGreaterThanOrEqual(0);
        expect(j["case_fun_fact"]).toBeLessThanOrEqual(k);
        expect(j["planche_colonnes"] || j["pleine_page"]).toBeFalsy();
      }
      // Plus de post-it posé sur une bande de photos.
      expect(jours.some((j) => j["postit_bande"])).toBe(false);
      // Aucune photo perdue.
      expect(jours.flatMap((j) => j.photos)).toHaveLength(54);
    });

    it("prend le troisième emplacement d'un collage quand la bande de deux photos n'a plus de place dans la page", () => {
      // Un récit trop long pour la carte à côté des deux photos (plus de 230
      // signes) : le fun fact entre dans la bande, si les photos tiennent dans
      // les colonnes du collage.
      const recit = Array.from({ length: 4 }, (_, i) => paragrapheDe(`la ville ${i}`, 2)).join(" ");
      const jours = M.composerJours(
        [etape(recit, Array.from({ length: 9 }, (_, k) => photo(`p${k}`)), encart("Un fait.", 9))],
        { funFacts: true },
      );
      const hote = jours.find((j) => (j["fun_facts"] as string[]).length)!;
      expect(hote["layout_collage"]).toBe(true);
      expect(hote["layout_split_left"]).toBe(false);
      expect(hote.photos).toHaveLength(2);
      // À coût égal, le dernier emplacement : le fun fact ferme la bande.
      expect(hote["case_fun_fact"]).toBe(2);
      // Jamais sur une bande de photos paysage, qui s'y rogneraient au-delà du plafond.
      const paysages = M.composerJours(
        [etape(recit, Array.from({ length: 9 }, (_, k) => photo(`p${k}`, 1.5)), encart("Un fait.", 9))],
        { funFacts: true },
      );
      expect(paysages.some((j) => j["layout_collage"] && j["case_fun_fact"] !== undefined)).toBe(false);
    });

    it("pose l'encart à côté de la photo flottante plutôt que sous une grande photo en tête", () => {
      // Un récit court, réparti sur deux pages ; la photo et l'encart sur la première.
      const jours = M.composerJours([etape(paragrapheDe("la plage", 4), [photo("p", 1.4)], encart("Fait.", 9))], {
        funFacts: true,
      });
      const hote = jours.find((j) => (j["fun_facts"] as string[]).length)!;
      expect(hote["layout_hero_top"]).toBe(false);
      expect(hote["layout_story_opener"]).toBe(true);
      expect(hote.photos).toHaveLength(1);
      expect(encarts(jours).filter(Boolean)).toEqual(["Fait."]);
    });
  });

  describe("quiz (Hugo, 15/10/2026)", () => {
    const quizSur = (i: number, reponse = `Réponse ${i}`) => ({
      question: `Question n° ${i} ?`,
      choix: [reponse, `Leurre ${i}a`, `Leurre ${i}b`],
      reponse,
    });
    // Une étape d'un paragraphe court, sans photo : ses pages peuvent porter un quiz.
    const etapes = (n: number, analyse = (i: number): unknown => ({ photos: [], quiz: quizSur(i) })) =>
      Array.from({ length: n }, (_, i) => etape(paragrapheDe(`le lieu ${i}`, 1), [], analyse(i), `Lieu ${i}`));
    const etapeDe = (jours: Jour[]) =>
      jours.reduce<number[]>((rangs, j) => [...rangs, (rangs.at(-1) ?? -1) + (j["day_intro"] ? 1 : 0)], []);
    const quizPoses = (jours: Jour[]) => {
      const rangs = etapeDe(jours);
      return jours.flatMap((j, i) => (j["quiz"] ? [{ etape: rangs[i]!, page: i, quiz: j["quiz"] as Record<string, unknown> }] : []));
    };

    it("n'en met aucun quand le réglage du carnet est coupé", () => {
      expect(quizPoses(M.composerJours(etapes(4), { quiz: false }))).toEqual([]);
      expect(quizPoses(M.composerJours(etapes(4)))).toEqual([]);
    });

    it("en pose environ un toutes les trois étapes, un par étape au plus, sur sa première page", () => {
      const jours = M.composerJours(etapes(10), { quiz: true });
      const poses = quizPoses(jours);
      expect(poses.map((q) => q.etape)).toEqual([0, 3, 6, 9]);
      for (const { etape: e, page, quiz } of poses) {
        // La première page de l'étape, dans la forme du gabarit.
        expect(jours[page]!["day_intro"]).toBeTruthy();
        expect(quiz).toEqual({ question: `Question n° ${e} ?`, choices: [`Réponse ${e}`, `Leurre ${e}a`, `Leurre ${e}b`], answer: `Réponse ${e}` });
        expect(jours[page]!["ai_note"]).toBe("Quiz rédigé par IA");
      }
    });

    it("reprend tel quel le quiz déjà rédigé que l'app apporte", () => {
      const quiz = { question: "Qui a renversé le café ?", choices: ["Clara", "Hugo", "Le serveur"], answer: "Hugo" };
      const [premiere] = M.composerJours([{ ...etape(paragrapheDe("le port", 1), []), quiz }], { quiz: true });
      expect(premiere!["quiz"]).toEqual(quiz);
    });

    it("ne prend jamais la place d'une photo, d'un fun fact ni d'une carte", () => {
      const lourdes = Array.from({ length: 6 }, (_, e) =>
        etape(
          [paragrapheDe(`la ville ${e}`, 2), paragrapheDe(`le port ${e}`, 2)].join(" "),
          Array.from({ length: e % 2 ? 6 : 1 }, (_, k) => photo(`${e}-${k}`)),
          {
            photos: [],
            quiz: quizSur(e),
            funFacts: [{ texte: `Fait ${e}.`, registre: "histoire", paragraphe: 0, pertinence: 9 }],
          },
          `Lieu ${e}`,
        ),
      );
      const jours = M.composerJours(lourdes, { quiz: true, funFacts: true });
      expect(jours.some((jour) => jour["quiz"])).toBe(true);
      for (const j of jours.filter((jour) => jour["quiz"])) {
        expect(j.photos).toHaveLength(0);
        expect(j["fun_facts"]).toEqual([]);
        expect(j["map"] ?? j["map_svg"]).toBeUndefined();
        expect(j["layout_story_opener"] || j["layout_story_facts"]).toBe(true);
      }
      expect(jours.flatMap((j) => j.photos)).toHaveLength(3 + 3 * 6);
    });

    it("ne se pose pas sur la page dont le récit donne la réponse", () => {
      // Le récit se répartit sur deux pages ; la réponse n'est que sur la première.
      const recit = [paragrapheDe("la crique", 2), paragrapheDe("le port", 2)].join(" ");
      const jours = M.composerJours([etape(recit, [], { photos: [], quiz: quizSur(0, "la crique") })], { quiz: true });
      expect(jours).toHaveLength(2);
      const poses = quizPoses(jours);
      expect(poses.map((q) => q.page)).toEqual([1]);
      expect(texteDes([jours[1]!])).not.toContain("la crique");
    });

    it("n'imprime pas un quiz mal formé", () => {
      const malFormes = [
        { question: "", choix: ["a", "b"], reponse: "a" },
        { question: "Une seule proposition ?", choix: ["a"], reponse: "a" },
        { question: "La réponse manque ?", choix: ["a", "b", "c"], reponse: "d" },
        { question: "Deux fois la même ?", choix: ["a", "A", "b"], reponse: "b" },
        { question: "x".repeat(121), choix: ["a", "b"], reponse: "a" },
      ];
      const jours = M.composerJours(
        malFormes.map((quiz, i) => etape(paragrapheDe(`le lieu ${i}`, 1), [], { photos: [], quiz }, `Lieu ${i}`)),
        { quiz: true },
      );
      expect(quizPoses(jours)).toEqual([]);
    });
  });

  describe("nombre de pages cible (Hugo, 15/10/2026)", () => {
    // Dix étapes d'un paragraphe, six photos chacune : le récit en fait peu,
    // les photos de quoi allonger. Avec le colophon et les pages libres
    // (`pagesFixes`), le carnet composé seul fait 25 pages.
    const voyage = (photos = 6) =>
      Array.from({ length: 10 }, (_, e) =>
        etape(paragrapheDe(`le lieu ${e}`, 2), Array.from({ length: photos }, (_, k) => photo(`${e}-${k}`)), null, `Lieu ${e}`),
      );
    const pagesParEtape = (jours: Jour[]) =>
      jours.reduce<number[]>((n, j) => (j["day_intro"] ? [...n, 1] : [...n.slice(0, -1), (n.at(-1) ?? 0) + 1]), []);
    const photosDe = (jours: Jour[]) => jours.flatMap((j) => j.photos.map(url)).sort();
    const recalage = (jours: string[]) => jours.filter((t) => t.startsWith("pages cible"));

    it("fait tenir un carnet à cible 40 entre 35 et 45 pages, par ses seules planches", () => {
      const sans = M.composerJours(voyage(), { ratio: 50, pagesFixes: 5 });
      expect(sans.length + 5).toBeLessThan(35);
      const journal: string[] = [];
      const jours = M.composerJours(voyage(), { ratio: 50, pagesFixes: 5, pagesCible: 40, journal: (t: string) => journal.push(t) });
      expect(jours.length + 5).toBeGreaterThanOrEqual(35);
      expect(jours.length + 5).toBeLessThanOrEqual(45);
      // Le récit n'a pas bougé d'un mot, et aucune page de récit n'est apparue.
      expect(normal(texteDes(jours))).toBe(normal(texteDes(sans)));
      expect(jours.filter((j) => j.body_html).length).toBe(sans.filter((j) => j.body_html).length);
      // Les mêmes photos, ni plus ni moins : le ratio en a dit le nombre.
      expect(photosDe(jours)).toEqual(photosDe(sans));
      // Ce qui s'ajoute, ce sont des planches, en fin d'étape, et chaque étape reste paire.
      const ajoutees = jours.filter((j) => j["layout_photo_page"]).length - sans.filter((j) => j["layout_photo_page"]).length;
      expect(ajoutees).toBe(jours.length - sans.length);
      for (const n of pagesParEtape(jours)) expect(n % 2).toBe(0);
      expect(recalage(journal)).toEqual([expect.stringContaining("35 après 10 page(s) de photos ajoutée(s)")]);
    });

    it("compte les pages libres de fin dans le carnet", () => {
      const avecLibres = M.composerJours(voyage(), { ratio: 50, pagesFixes: 5, pagesCible: 40 });
      const sansLibres = M.composerJours(voyage(), { ratio: 50, pagesFixes: 2, pagesCible: 40 });
      expect(sansLibres.length).toBeGreaterThan(avecLibres.length);
      expect(sansLibres.length + 2).toBeGreaterThanOrEqual(35);
    });

    it("ne touche à rien quand le carnet est déjà dans sa fourchette", () => {
      const sans = M.composerJours(voyage(), { ratio: 50, pagesFixes: 5 });
      const journal: string[] = [];
      const avec = M.composerJours(voyage(), { ratio: 50, pagesFixes: 5, pagesCible: 28, journal: (t: string) => journal.push(t) });
      expect(avec).toEqual(sans);
      expect(recalage(journal)).toEqual([]);
    });

    it("raccourcit en resserrant les planches, sans perdre une photo", () => {
      // À 100 %, des étapes de quatre planches à deux ou trois photos : 45 pages.
      const sans = M.composerJours(voyage(9), { ratio: 100, pagesFixes: 5 });
      expect(sans.length + 5).toBe(45);
      const jours = M.composerJours(voyage(9), { ratio: 100, pagesFixes: 5, pagesCible: 30 });
      expect(jours.length + 5).toBe(35);
      expect(photosDe(jours)).toEqual(photosDe(sans));
      for (const n of pagesParEtape(jours)) expect(n % 2).toBe(0);
      // La planche qui ouvre l'étape garde son bandeau et quatre photos au plus.
      for (const j of jours.filter((jour) => jour["day_intro"])) {
        expect(j["layout_photo_wall_intro"]).toBe(true);
        expect(j.photos.length).toBeLessThanOrEqual(4);
      }
      for (const j of jours) expect(j.photos.length).toBeLessThanOrEqual(5);
    });

    it("ne force rien quand les photos manquent, et le dit", () => {
      const sans = M.composerJours(voyage(0), { ratio: 50, pagesFixes: 5 });
      const journal: string[] = [];
      const jours = M.composerJours(voyage(0), { ratio: 50, pagesFixes: 5, pagesCible: 40, journal: (t: string) => journal.push(t) });
      expect(jours).toEqual(sans);
      expect(recalage(journal)).toEqual([expect.stringMatching(/hors d'atteinte, 25 pages .*pas assez de photos/)]);
    });

    it("ne force rien quand le récit seul dépasse la cible, et le dit", () => {
      const long = Array.from({ length: 6 }, (_, e) =>
        etape([0, 1, 2, 3].map((k) => paragrapheDe(`le lieu ${e}-${k}`)).join(" "), [photo(`${e}`)], null, `Lieu ${e}`),
      );
      const sans = M.composerJours(long, { ratio: 25, pagesFixes: 5 });
      const journal: string[] = [];
      const jours = M.composerJours(long, { ratio: 25, pagesFixes: 5, pagesCible: 10, journal: (t: string) => journal.push(t) });
      expect(normal(texteDes(jours))).toBe(normal(texteDes(sans)));
      expect(jours.length).toBe(sans.length);
      expect(recalage(journal)).toEqual([expect.stringMatching(/hors d'atteinte.*le récit seul en fait/)]);
    });
  });

  describe("lot 12 : layouts du 15/10/2026, fun facts, bandes ajustées", () => {
    const plan = (sorte: "bandeau" | "suite", texte: string[], photos: ReturnType<typeof photo>[]) => ({
      genre: "recit",
      sorte,
      texte,
      photos,
      layout: photos.length === 2 ? "layout_split_left" : "layout_story_facts",
    });
    const court = [paragrapheDe("le port", 2).trim()];

    it("met en scène le fun fact d'une page à deux photos : photo contournée à l'ouverture, photos en tête ensuite", () => {
      expect(M.layoutAvecEncart(plan("bandeau", court, [photo("a"), photo("b")]))).toBe("layout_recit_deux_photos");
      expect(M.layoutAvecEncart(plan("suite", court, [photo("a"), photo("b")]))).toBe("layout_photos_en_tete");
      // Un récit trop long pour la maquette garde son gabarit.
      const long = [paragrapheDe("le port", 4).trim()];
      expect(M.layoutAvecEncart(plan("bandeau", long, [photo("a"), photo("b")]))).toBeNull();
      // Une photo en largeur ne tient pas dans un emplacement en hauteur.
      expect(M.layoutAvecEncart(plan("suite", court, [photo("a", 1.6), photo("b", 1.6)]))).toBeNull();
    });

    it("coupe le récit d'une page de suite à une photo par la photo et le post-it", () => {
      const texte = [paragrapheDe("le port", 2).trim(), paragrapheDe("la plage", 2).trim()];
      expect(M.layoutAvecEncart(plan("suite", texte, [photo("a")]))).toBe("layout_recit_encart_milieu");
      // Trop court pour être coupé en deux : la zone flottante suffit.
      expect(M.layoutAvecEncart(plan("suite", [phrase("le port").trim()], [photo("a")]))).toBeNull();
      const [avant, apres] = M.couperEnDeux(texte);
      expect(avant).toEqual([texte[0]]);
      expect(apres).toEqual([texte[1]]);
      // Un seul paragraphe se coupe sur une fin de phrase, sans perdre un mot.
      const seul = paragrapheDe("le marché", 4).trim();
      const [a1, a2] = M.couperEnDeux([seul]);
      expect(a1).toHaveLength(1);
      expect(a2).toHaveLength(1);
      expect(`${a1[0]} ${a2[0]}`).toBe(seul);
      expect(a1[0]).toMatch(/\.$/);
    });

    it("pose le fun fact sur une page de texte seul plutôt que sur une page de photos", () => {
      const jours = M.composerJours(
        [
          etape([paragrapheDe("le port", 3), paragrapheDe("la plage", 3), paragrapheDe("la ville", 3)].join(" "), [], {
            photos: [],
            funFacts: [{ texte: "Un fait.", registre: "histoire", paragraphe: 0, pertinence: 7 }],
          }),
          etape(paragrapheDe("Naxos", 2), [photo("n1"), photo("n2")], {
            photos: [],
            funFacts: [{ texte: "Un autre.", registre: "vecu", paragraphe: 0, pertinence: 9 }],
          }, "Naxos"),
        ],
        { funFacts: true, pagesAvant: 1 },
      );
      const premier = jours.find((j) => (j["fun_facts"] as string[]).length)!;
      expect(premier.photos).toHaveLength(0);
      expect(premier["fun_facts"]).toEqual(["Un fait."]);
    });

    it("ajuste la bande de photos au format de chacune, sans timbre-poste", () => {
      const bande = M.bandeAjustee([photo("a"), photo("b", 1.5), photo("c")], false)!;
      expect(bande.poids).toEqual([0.75, 1.5, 0.75]);
      // Elle ne grandit pas au point de rogner ses photos de plus d'un quart.
      expect(bande.bandeMax).toBeLessThanOrEqual(322);
      expect(bande.bandeMax).toBeGreaterThanOrEqual(160);
      // Une photo de groupe ne se rogne pas : la bande garde ses emplacements.
      expect(M.bandeAjustee([photo("a"), { ...photo("b"), groupe: true }], false)).toBeNull();

      const jours = M.composerJours(
        [etape(`${paragrapheDe("le port", 3)} ${paragrapheDe("la plage", 2)}`, [photo("a"), photo("b", 1.5), photo("c"), photo("d")])],
        { pagesAvant: 1 },
      );
      const page = jours.find((j) => j["layout_split_left"] || j["layout_collage"])!;
      expect(page["bande_max"]).toBeGreaterThan(0);
      const poids = page.photos.map((p) => (p as { poids?: number }).poids);
      expect(poids.every((x) => x !== undefined && x >= 0.5 && x <= 2)).toBe(true);
    });

    it("alterne le côté du récit d'un trio à l'autre", () => {
      const recit = [paragrapheDe("la plage", 2), paragrapheDe("le port", 2), paragrapheDe("la ville", 2)].join(" ");
      const jours = M.composerJours(
        ["Paros", "Naxos"].map((lieu) => etape(recit, ["a", "b", "c", "d", "e", "f"].map((id) => photo(`${lieu}-${id}`)), null, lieu)),
      );
      const trios = jours.filter((j) => j["layout_trio_portrait"] || j["layout_trio_landscape"]);
      expect(trios.map((j) => j["trio_cote"])).toEqual(["gauche", "droite"]);
    });
  });
});
