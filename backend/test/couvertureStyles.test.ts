import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { runInNewContext } from "node:vm";
import { afterEach, describe, expect, it, vi } from "vitest";
import { BACK_COVER_STYLES, FRONT_COVER_STYLES } from "../src/services/coverCatalogue.js";

/**
 * Les styles de couverture de l'atelier (`MemoBook Generator/public/couverture-styles.js`),
 * d'après les spécifications de Hugo du 09/10/2026 : palette, polices, textes
 * rédigés puis modifiables, la règle du dos commune à tous les styles, et les
 * illustrations générées (Assouline, Aquarelle, Travel book) ou le contour
 * des voyageurs (Photo-dessin).
 */
const require = createRequire(import.meta.url);
type Element = Record<string, unknown> & { type: string };
type Zone = { x: number; y: number; l: number; h: number };
type Maquette = {
  elements: Element[];
  largeur: number;
  hauteur: number;
  fondPerdu: number;
  plats: Record<"verso" | "dos" | "recto", [number, number]>;
  faces: Record<"verso" | "dos" | "recto", Zone>;
  couleurs: Record<string, { nom: string; hex: string }>;
};
const C = require("../../MemoBook Generator/public/couverture.js") as {
  FICHE_DEFAUT: Record<string, unknown>;
  COULEURS: Record<string, { hex: string }>;
  ficheDuCarnet: (fiche: Record<string, unknown>, pages: number) => Record<string, unknown>;
  versJsx: (m: Maquette, o?: Record<string, unknown>) => string;
  versSvg: (m: Maquette) => string;
};
const S = require("../../MemoBook Generator/public/couverture-styles.js") as {
  STYLES: { id: string; nom: string; dispo: boolean; recto: string; verso: string }[];
  POLICES: Record<string, string[]>;
  POLICE_TITRE_DESSIN: string;
  CHAMPS: Record<string, { cle: string; ia: boolean; max?: number }[]>;
  textesParDefaut: (style: string, voyage: Record<string, unknown>) => Record<string, string>;
  consigneTextes: (style: string, voyage: Record<string, unknown>) => string | null;
  lireTextes: (style: string, reponse: unknown) => Record<string, string>;
  dessinsDuVoyage: (bibliotheque: Record<string, unknown>[], appeles?: Record<string, unknown>[]) => { famille: string; fichier: string }[];
  maquette: (style: string, contexte: Record<string, unknown>) => Maquette;
  MERCI_PHOTO_DESSIN: string;
  contraste: (a: string, b: string) => number;
  couleursAssouline: (dominante: string) => { fond: string; titre: string };
  couleursPhotoDessin: (dominante: string | null, luminance?: number) => { texte: string; ecriture: string };
  imagesDuStyle: (
    style: string,
    voyage: Record<string, unknown>,
    textes?: Record<string, string>,
  ) => { cle: string; pour: string; taille: string; transparent: boolean; reference: string; prompt: string }[];
  coutImages: (images: { taille: string }[]) => number;
  CONSIGNE_CONTOUR: string;
  lireContour: (reponse: unknown) => [number, number][];
};
const P = require("../../MemoBook Generator/public/partage.js") as {
  genererImage: (o: Record<string, unknown>) => Promise<{ data: string }>;
};

const voyage = { destination: "Philippines", titre: "Trois semaines", voyageurs: ["Margaux", "Claire", "Augustin"], debut: "2026-02-01", fin: "2026-02-24" };
const photo = (nom: string) => ({ fichier: `Liens/${nom}.jpg`, src: "data:image/jpeg;base64,", px: [1600, 1067] });
const bibliotheque = (
  JSON.parse(readFileSync(resolve(import.meta.dirname, "../../assets/stickers/stickers.json"), "utf8")) as {
    stickers: Record<string, unknown>[];
  }
).stickers;
const dessins = S.dessinsDuVoyage(bibliotheque).map((d) => ({ fichier: `Liens/${d.fichier}`, src: "data:image/png;base64,", px: [600, 400] }));

/** Une illustration générée, telle que l'atelier la garde : sa couleur dominante mesurée. */
const illustration = (cle: string, px: [number, number], dominante = "#3f7d3c") => ({
  fichier: `Liens/${cle}.png`,
  src: "data:image/png;base64,",
  px,
  dominante,
});
const images = {
  illustration: illustration("illustration", [1024, 1024]),
  recto: illustration("recto", [1024, 1536]),
  vignette1: illustration("vignette1", [1024, 1024]),
  vignette2: illustration("vignette2", [1024, 1024]),
  vignette3: illustration("vignette3", [1024, 1024]),
  timbres: illustration("timbres", [1536, 1024]),
  tampon: illustration("tampon", [1024, 1024]),
};
const contour = [[0.42, 0.4], [0.5, 0.36], [0.58, 0.4], [0.6, 0.55], [0.56, 0.7], [0.5, 0.72], [0.44, 0.7], [0.4, 0.55]];
const AQUARELLE = "Arrivée à **Manille**, la chaleur.\n\nTrois jours en scooter autour de Coron.\n\nLa dernière soirée à El Nido.";

const maquette = (style: string, contexte: Record<string, unknown> = {}) => {
  const defaut = S.textesParDefaut(style, voyage);
  return S.maquette(style, {
    fiche: C.ficheDuCarnet(C.FICHE_DEFAUT, 60),
    textes: {
      ...defaut,
      ...(style === "watercolor" ? { resume: AQUARELLE } : {}),
      dosTitre: "Philippines",
      dosVoyageurs: "Margaux, Claire et Augustin",
      dosDates: "février 2026",
    },
    recto: photo("recto"),
    verso: photo("verso"),
    dessins,
    images,
    contour,
    couleurPhoto: "#2f8f9d",
    luminancePhoto: 0.4,
    chiffres: [
      { valeur: "24", libelle: "jours" },
      { valeur: "7", libelle: "îles" },
    ],
    logo: { fichier: "Liens/logo-memobook-beige.png", src: "data:image/png;base64,", px: [1200, 1200] },
    ...contexte,
  });
};

/** Les éléments posés sur une partie de la planche (par leur abscisse de départ). */
const sur = (m: Maquette, partie: "verso" | "dos" | "recto") =>
  m.elements.filter((e) => {
    // Les textes du dos, tournés d'un quart de tour, n'appartiennent à aucun plat.
    if (e["rotation"]) return false;
    const x = (e["x"] ?? e["cx"]) as number;
    const [a, b] = m.plats[partie];
    return typeof x === "number" && x >= a - m.fondPerdu - 0.01 && x < b;
  });

describe("styles de couverture", () => {
  it("reprend les sept styles du catalogue de l'app, dans le même ordre, tous disponibles", () => {
    expect(S.STYLES.map((s) => `front-${s.id}`)).toEqual(FRONT_COVER_STYLES.map((s) => s.id));
    expect(S.STYLES.map((s) => `back-${s.id}`)).toEqual(BACK_COVER_STYLES.map((s) => s.id));
    expect(S.STYLES.every((s) => s.dispo)).toBe(true);
  });

  for (const style of ["elegant", "drawing", "assouline", "watercolor", "travel-book", "photo-drawing"]) {
    describe(style, () => {
      const m = maquette(style);

      it("n'emploie que les polices de son style", () => {
        const polices = new Set(m.elements.map((e) => e["police"]).filter(Boolean));
        expect(polices.size).toBeGreaterThan(0);
        for (const p of polices) expect(S.POLICES[style]).toContain(p);
      });

      it("donne au dos le fond de la quatrième, et la police et la couleur de son texte (ou de son titre)", () => {
        const fonds = m.elements.filter((e) => e.type === "rect" && (e["h"] as number) > m.hauteur);
        expect(fonds).toHaveLength(3);
        expect(fonds[1]!["fond"]).toBe(fonds[0]!["fond"]);
        const dos = m.elements.filter((e) => e["rotation"] === 90);
        expect(dos.length).toBe(3);
        const textes = (partie: "verso" | "recto") => sur(m, partie).filter((e) => e.type === "texte" || e.type === "bloc");
        const reference =
          sur(m, "verso").find((e) => e.type === "bloc") ?? textes("verso")[0] ?? textes("recto").find((e) => e.type === "texte")!;
        for (const e of dos) {
          expect(e["police"]).toBe(reference["police"]);
          expect(e["couleur"]).toBe(reference["couleur"]);
        }
      });

      it("ne nomme que des couleurs de sa palette", () => {
        const nommees = new Set(
          m.elements.flatMap((e) => [e["fond"], e["couleur"], (e["trait"] as { couleur?: string } | null)?.couleur]).filter(Boolean),
        );
        for (const c of nommees) expect(Object.keys(m.couleurs)).toContain(c);
      });

      it("garde tous ses textes et ses images dans les faces visibles", () => {
        for (const partie of ["verso", "recto"] as const) {
          const face = m.faces[partie];
          for (const e of sur(m, partie).filter((x) => ["texte", "bloc", "image"].includes(x.type))) {
            // Les images à fond perdu, et le motif M en transparence, débordent exprès.
            if (e.type === "image" && (e["h"] as number) > m.hauteur) continue;
            if (e.type === "image" && (e["y"] as number) + (e["h"] as number) >= m.hauteur + m.fondPerdu - 0.01) continue;
            if (e["opacite"] != null) continue;
            expect(e["x"] as number, `${e.type} ${typeof e["texte"] === "string" ? e["texte"] : typeof e["fichier"] === "string" ? e["fichier"] : ""}`).toBeGreaterThanOrEqual(face.x - 0.01);
            expect((e["x"] as number) + (e["l"] as number)).toBeLessThanOrEqual(face.x + face.l + 0.01);
            expect(e["y"] as number).toBeGreaterThanOrEqual(face.y - 0.01);
            expect((e["y"] as number) + (e["h"] as number)).toBeLessThanOrEqual(face.y + face.h + 0.01);
          }
        }
      });

      it("se construit en script InDesign et en aperçu SVG", () => {
        const jsx = C.versJsx(m, { titre: "Philippines" });
        // eslint-disable-next-line no-control-regex
        expect(jsx).toMatch(/^[\x00-\x7f]*$/);
        const enumeration = new Proxy({}, { get: (_, nom) => String(nom) });
        const objet = (chemin: string): unknown =>
          new Proxy(function () {}, {
            get: (_, nom) => {
              if (nom === Symbol.toPrimitive) return () => 0;
              if (nom === "length") return 0;
              if (nom === "exists") return true;
              // Le cadre de texte ne déborde pas : InDesign le dirait, pas l'imitation.
              if (nom === "overflows") return false;
              if (nom === "fullName" || nom === "fsName") return "/dossier";
              return objet(`${chemin}.${String(nom)}`);
            },
            set: () => true,
            apply: (_, __, args) => {
              if (chemin.endsWith("doScript")) (args[0] as () => void)();
              return objet(`${chemin}()`);
            },
          });
        const contexte = {
          app: objet("app"),
          $: { fileName: "/dossier/Couverture MemoBook.jsx" },
          File: (nom: string) => ({ nom, exists: true, parent: { fullName: "/dossier" }, fullName: nom }),
          alert: (message: string) => {
            throw new Error(`alert : ${message}`);
          },
          ...Object.fromEntries(
            [
              "PageOrientation", "LocationOptions", "MeasurementUnits", "RulerOrigin", "ColorModel", "ColorSpace",
              "EndCap", "CornerOptions", "FitOptions", "Justification", "VerticalJustification", "ShadowMode",
              "CoordinateSpaces", "AnchorPoint", "ScriptLanguage", "UndoModes", "ZoomOptions", "BlendMode",
              "PathType", "TextPathEffects", "StrokeAlignment",
            ].map((nom) => [nom, enumeration]),
          ),
        };
        expect(() => {
          runInNewContext(jsx, contexte);
        }).not.toThrow();
        expect(C.versSvg(m)).toContain(`width="${m.largeur + 2 * m.fondPerdu}mm"`);
      });
    });
  }

  for (const style of ["elegant", "drawing"]) {
    it(`${style} : fonds beige, tout en noir typo`, () => {
      const m = maquette(style);
      const fonds = m.elements.filter((e) => e.type === "rect" && (e["h"] as number) > m.hauteur);
      expect(fonds.map((e) => e["fond"])).toEqual(["beige", "beige", "beige"]);
      const couleurs = new Set(m.elements.filter((e) => e.type === "texte" || e.type === "bloc").map((e) => e["couleur"]));
      expect([...couleurs]).toEqual(["noir"]);
      expect(m.couleurs["noir"]!.hex).toBe(C.COULEURS["noir"]!.hex);
    });
  }

  it("Élégant : une grande photo sur la première, une bande en tête de la quatrième, le logo en pied", () => {
    const m = maquette("elegant");
    const recto = sur(m, "recto").find((e) => e.type === "image")!;
    const verso = sur(m, "verso").filter((e) => e.type === "image");
    expect(recto["fichier"]).toBe("Liens/recto.jpg");
    expect((recto["h"] as number) / m.faces.recto.h).toBeGreaterThan(0.6);
    expect(verso.map((e) => e["fichier"])).toEqual(["Liens/verso.jpg", "Liens/logo-memobook-beige.png"]);
    expect((verso[0]!["l"] as number) / (verso[0]!["h"] as number)).toBeGreaterThan(2.5);
    const titre = m.elements.find((e) => e.type === "texte" && e["police"] === "Cormorant Garamond")!;
    expect(titre["texte"]).toBe("PHILIPPINES");
  });

  it("Dessin : trois dessins de la bibliothèque, aucun réservé, titres en Gloria Hallelujah tant que Hansley attend sa licence", () => {
    expect(S.POLICE_TITRE_DESSIN).toBe("Gloria Hallelujah");
    const choisis = S.dessinsDuVoyage(bibliotheque);
    expect(choisis).toHaveLength(3);
    expect(new Set(choisis.map((d) => d.famille)).size).toBe(3);
    expect(choisis.every((d) => !(d as Record<string, unknown>)["reserve"])).toBe(true);
    const m = maquette("drawing");
    const images = m.elements.filter((e) => e.type === "image");
    expect(images.every((e) => e["contenir"] === true)).toBe(true);
    expect(images).toHaveLength(3);
  });

  it("rédige les textes d'un style d'après les récits, puis les borne", () => {
    const consigne = S.consigneTextes("elegant", {
      ...voyage,
      voyageurs: "Margaux, Claire et Augustin",
      dates: "février 2026",
      etapes: [{ titre: "Arrivée", lieu: "Manille", extrait: "Premier jour en scooter." }],
    })!;
    expect(consigne).toContain("Manille");
    expect(consigne).toContain('{"titre":"","date":"","resume":""}');
    expect(S.consigneTextes("default", voyage)).toBeNull();
    const lus = S.lireTextes("elegant", { titre: "  PHILIPPINES ", date: "FÉVRIER 2026", resume: "Un.\n\n\n\nDeux.", autre: "x" });
    expect(lus).toEqual({ titre: "PHILIPPINES", date: "FÉVRIER 2026", resume: "Un.\n\nDeux." });
    // Un texte bien trop long est coupé sur un mot.
    const long = S.lireTextes("drawing", { titre: "mot ".repeat(40) });
    expect(long["titre"]!.length).toBeLessThanOrEqual(41);
  });

  describe("les illustrations générées", () => {
    const etapes = [
      { titre: "Arrivée", lieu: "Manille" },
      { titre: "Plongée", lieu: "Coron" },
    ];

    it("demande à chaque style ses images, avec la couverture de référence en entrée", () => {
      const assouline = S.imagesDuStyle("assouline", { ...voyage, etapes });
      expect(assouline.map((i) => [i.cle, i.taille, i.transparent])).toEqual([["illustration", "1024x1024", true]]);
      expect(assouline[0]!.reference).toBe(S.STYLES.find((s) => s.id === "assouline")!.recto);
      expect(assouline[0]!.prompt).toContain("Philippines");
      expect(assouline[0]!.prompt).toContain("Coron");

      const aquarelle = S.imagesDuStyle("watercolor", { ...voyage, etapes }, { resume: AQUARELLE });
      expect(aquarelle.map((i) => i.cle)).toEqual(["recto", "vignette1", "vignette2", "vignette3"]);
      expect(aquarelle[0]!.transparent).toBe(false);
      // Chaque vignette illustre son paragraphe de la quatrième, sur le papier : sans contour net.
      expect(aquarelle[1]!.prompt).toContain("Manille");
      expect(aquarelle[3]!.prompt).toContain("El Nido");
      expect(aquarelle.slice(1).every((i) => i.transparent && i.reference === S.STYLES.find((s) => s.id === "watercolor")!.verso)).toBe(true);
      expect(S.coutImages(aquarelle)).toBeCloseTo(0.76);

      const travel = S.imagesDuStyle("travel-book", { ...voyage, etapes });
      expect(travel.map((i) => [i.cle, i.reference === "silhouette"])).toEqual([
        ["timbres", false],
        ["tampon", true],
      ]);
      expect(travel[1]!.prompt).toContain("PHILIPPINES");

      expect(S.imagesDuStyle("photo-drawing", voyage)).toEqual([]);
      expect(S.imagesDuStyle("elegant", voyage)).toEqual([]);
    });

    it("Assouline : le fond s'accorde à l'illustration, les titres prennent sa couleur, lisible", () => {
      expect(S.couleursAssouline("#3f7d3c").fond).toBe("bleu");
      expect(S.couleursAssouline("#2a6fb5").fond).toBe("beige");
      for (const dominante of ["#3f7d3c", "#2a6fb5", "#c0392b", "#f4d03f", "#8e44ad"]) {
        const { fond, titre } = S.couleursAssouline(dominante);
        expect(["bleu", "beige", "vertMarque"]).toContain(fond);
        expect(S.contraste(titre, C.COULEURS[fond]!.hex)).toBeGreaterThanOrEqual(3);
      }
      const m = maquette("assouline");
      expect(m.elements[0]!["fond"]).toBe("bleu");
      const titre = m.elements.find((e) => e.type === "texte" && e["police"] === "Black Han Sans")!;
      expect(titre["couleur"]).toBe("accent");
      expect(titre["texte"]).toBe("PHILIPPINES");
      // L'encadré des chiffres : blanc, bordé de la couleur des titres ; le résumé en noir typo.
      const encadre = m.elements.find((e) => e.type === "rect" && e["fond"] === "blanc")!;
      expect((encadre["trait"] as { couleur: string }).couleur).toBe("accent");
      expect(m.elements.find((e) => e.type === "bloc")!["couleur"]).toBe("noir");
      expect(sur(m, "recto").some((e) => e.type === "image" && e["fichier"] === "Liens/illustration.png")).toBe(true);
    });

    it("Aquarelle : l'illustration sous le titre, trois vignettes et leurs paragraphes, le motif M à 20 %", () => {
      const m = maquette("watercolor");
      expect(sur(m, "recto").find((e) => e.type === "image")!["fichier"]).toBe("Liens/recto.png");
      const vignettes = sur(m, "verso").filter((e) => e.type === "image" && /vignette/.test(String(e["fichier"])));
      expect(vignettes).toHaveLength(3);
      const blocs = m.elements.filter((e) => e.type === "bloc");
      expect(blocs.map((b) => (b["paragraphes"] as string[])[0])).toEqual(AQUARELLE.split("\n\n"));
      expect(blocs.every((b) => b["police"] === "Manrope" && b["couleur"] === "noir")).toBe(true);
      expect(m.elements.find((e) => e["opacite"] === 0.2)?.["fichier"]).toBe("Liens/logo-memobook-beige.png");
    });

    it("Travel book : timbres et tampon sur la première, la photo de la quatrième dans un cadre vert déchiré", () => {
      const m = maquette("travel-book");
      expect(sur(m, "recto").filter((e) => e.type === "image").map((e) => e["fichier"])).toEqual(["Liens/tampon.png", "Liens/timbres.png"]);
      expect(sur(m, "verso").find((e) => e.type === "image")!["fichier"]).toBe("Liens/verso.jpg");
      const cadre = m.elements.find((e) => e.type === "chemin")!;
      expect((cadre["trait"] as { couleur: string }).couleur).toBe("vertMarque");
      const textes = m.elements.filter((e) => e.type === "texte");
      expect(textes.every((e) => e["police"] === "Lilita One" && e["couleur"] === "vertMarque")).toBe(true);
    });

    it("Photo-dessin : les voyageurs entourés, le titre sur le contour, les couleurs tirées de la photo", () => {
      const m = maquette("photo-drawing");
      const anneaux = m.elements.filter((e) => e.type === "courbe" && e["ferme"]);
      expect(anneaux).toHaveLength(4);
      // Les anneaux tiennent dans la face visible de la première.
      const face = m.faces.recto;
      for (const a of anneaux) {
        for (const [, [x, y]] of a["ancres"] as [number[], number[], number[]][]) {
          expect(x).toBeGreaterThanOrEqual(face.x - 0.5);
          expect(x).toBeLessThanOrEqual(face.x + face.l + 0.5);
          expect(y).toBeGreaterThanOrEqual(face.y - 0.5);
          expect(y).toBeLessThanOrEqual(face.y + face.h + 0.5);
        }
      }
      const titre = m.elements.find((e) => e.type === "texteChemin")!;
      expect(titre["texte"]).toBe("PHILIPPINES");
      expect(titre["couleur"]).toBe("encre");
      // La quatrième prend la couleur de la photo ; ses textes, la teinte de la marque la plus lisible.
      expect(m.elements[0]!["fond"]).toBe("encre");
      const merci = sur(m, "verso").find((e) => e.type === "texte")!;
      expect(merci["texte"]).toBe(S.MERCI_PHOTO_DESSIN.toUpperCase().replace("MON AVENTURE", "MON\nAVENTURE"));
      expect(S.contraste(m.couleurs[merci["couleur"] as string]!.hex, m.couleurs["encre"]!.hex)).toBeGreaterThanOrEqual(3);
      // Un grand contour est resserré pour tenir dans la face.
      const large = maquette("photo-drawing", { contour: [[0.02, 0.02], [0.98, 0.02], [0.98, 0.98], [0.02, 0.98], [0.5, 0.99], [0.01, 0.5]] });
      const xs = large.elements.filter((e) => e.type === "courbe" && e["ferme"]).flatMap((e) => (e["ancres"] as number[][][]).map((a) => a[1]![0]!));
      expect(Math.min(...xs)).toBeGreaterThanOrEqual(face.x - 0.5);
      expect(Math.max(...xs)).toBeLessThanOrEqual(face.x + face.l + 0.5);
    });

    it("Photo-dessin : un contour illisible devient une ellipse au centre ; les textes restent lisibles sur la photo", () => {
      expect(S.lireContour({ contour: [[0.2, 0.2], [2, -1], "x", [0.4, 0.5], [0.5, 0.5], [0.6, 0.5], [0.7, 0.5], [0.8, 0.5]] })[1]).toEqual([1, 0]);
      expect(S.lireContour(null)).toHaveLength(18);
      expect(S.lireContour({ contour: [[0.1, 0.1]] })).toHaveLength(18);
      expect(S.CONSIGNE_CONTOUR).toContain('"contour"');
      for (const [dominante, lum] of [["#2f8f9d", 0.4], ["#e8d9c0", 0.85], ["#1b2a49", 0.12], [null, 0.3]] as const) {
        const { texte, ecriture } = S.couleursPhotoDessin(dominante, lum);
        const gris = Math.round(lum * 255).toString(16).padStart(2, "0");
        expect(S.contraste(texte, `#${gris}${gris}${gris}`)).toBeGreaterThanOrEqual(2.2);
        expect(["vertMarque", "bleu", "beige", "blancMarque"]).toContain(ecriture);
      }
    });

    it("fixe le texte de la quatrième de Photo-dessin, et ne rédige rien pour Travel book", () => {
      expect(S.textesParDefaut("photo-drawing", voyage)["texteVerso"]).toBe("Merci d'avoir suivi mon aventure !");
      expect(S.textesParDefaut("travel-book", voyage)).toMatchObject({ titre: "Philippines", voyageurs: "Margaux, Claire et Augustin" });
      expect(S.consigneTextes("travel-book", voyage)).toBeNull();
      expect(S.consigneTextes("watercolor", voyage)).toContain('{"titre":"","resume":""}');
      expect(S.textesParDefaut("watercolor", { ...voyage, etapes }).resume).toBe("Arrivée, Manille\n\nPlongée, Coron");
    });
  });

  describe("genererImage (partage.js)", () => {
    afterEach(() => {
      vi.unstubAllGlobals();
    });

    it("génère sans référence, ou retouche à partir de la référence du style", async () => {
      const appels: { url: string; init: RequestInit }[] = [];
      vi.stubGlobal(
        "fetch",
        vi.fn((url: string, init: RequestInit) => {
          appels.push({ url, init });
          return Promise.resolve(new Response(JSON.stringify({ data: [{ b64_json: "QUJD" }] }), { status: 200 }));
        }),
      );
      const seule = await P.genererImage({ cle: "k", prompt: "un palmier", taille: "1024x1024", transparent: true });
      expect(seule.data).toBe("data:image/png;base64,QUJD");
      expect(appels[0]!.url).toBe("https://api.openai.com/v1/images/generations");
      expect(JSON.parse(appels[0]!.init.body as string)).toMatchObject({ model: "gpt-image-1", size: "1024x1024", background: "transparent", quality: "high" });

      await P.genererImage({ cle: "k", prompt: "un tampon", references: [{ data: "data:image/png;base64,QUJD", nom: "silhouette.png" }] });
      expect(appels[1]!.url).toBe("https://api.openai.com/v1/images/edits");
      const formulaire = appels[1]!.init.body as FormData;
      expect(formulaire.get("model")).toBe("gpt-image-1");
      expect(formulaire.get("size")).toBe("1024x1536");
      expect((formulaire.get("image[]") as File).name).toBe("silhouette.png");
    });

    it("dit pourquoi l'image n'est pas venue", async () => {
      await expect(P.genererImage({ cle: "", prompt: "x" })).rejects.toThrow("Aucune clé OpenAI");
      vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response(JSON.stringify({ error: { message: "quota dépassé" } }), { status: 429 }))));
      await expect(P.genererImage({ cle: "k", prompt: "x" })).rejects.toThrow("quota dépassé");
    });
  });
});
