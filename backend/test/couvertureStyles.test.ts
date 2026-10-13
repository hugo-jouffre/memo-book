import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { runInNewContext } from "node:vm";
import { describe, expect, it } from "vitest";
import { BACK_COVER_STYLES, FRONT_COVER_STYLES } from "../src/services/coverCatalogue.js";

/**
 * Les styles de couverture de l'atelier (`MemoBook Generator/public/couverture-styles.js`),
 * d'après les spécifications de Hugo du 09/10/2026 : palette, polices, textes
 * rédigés puis modifiables, et la règle du dos commune à tous les styles.
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
  STYLES: { id: string; nom: string; dispo: boolean; recto: string }[];
  POLICES: Record<string, string[]>;
  POLICE_TITRE_DESSIN: string;
  CHAMPS: Record<string, { cle: string; ia: boolean; max?: number }[]>;
  textesParDefaut: (style: string, voyage: Record<string, unknown>) => Record<string, string>;
  consigneTextes: (style: string, voyage: Record<string, unknown>) => string | null;
  lireTextes: (style: string, reponse: unknown) => Record<string, string>;
  dessinsDuVoyage: (bibliotheque: Record<string, unknown>[], appeles?: Record<string, unknown>[]) => { famille: string; fichier: string }[];
  maquette: (style: string, contexte: Record<string, unknown>) => Maquette;
};

const voyage = { destination: "Philippines", titre: "Trois semaines", voyageurs: ["Margaux", "Claire", "Augustin"], debut: "2026-02-01", fin: "2026-02-24" };
const photo = (nom: string) => ({ fichier: `Liens/${nom}.jpg`, src: "data:image/jpeg;base64,", px: [1600, 1067] });
const bibliotheque = (
  JSON.parse(readFileSync(resolve(import.meta.dirname, "../../assets/stickers/stickers.json"), "utf8")) as {
    stickers: Record<string, unknown>[];
  }
).stickers;
const dessins = S.dessinsDuVoyage(bibliotheque).map((d) => ({ fichier: `Liens/${d.fichier}`, src: "data:image/png;base64,", px: [600, 400] }));

const maquette = (style: string) => {
  const defaut = S.textesParDefaut(style, voyage);
  return S.maquette(style, {
    fiche: C.ficheDuCarnet(C.FICHE_DEFAUT, 60),
    textes: { ...defaut, dosTitre: "Philippines", dosVoyageurs: "Margaux, Claire et Augustin", dosDates: "février 2026" },
    recto: photo("recto"),
    verso: photo("verso"),
    dessins,
    chiffres: [],
    logo: { fichier: "Liens/logo-memobook-beige.png", src: "data:image/png;base64,", px: [1200, 1200] },
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
  it("reprend les sept styles du catalogue de l'app, dans le même ordre", () => {
    expect(S.STYLES.map((s) => `front-${s.id}`)).toEqual(FRONT_COVER_STYLES.map((s) => s.id));
    expect(S.STYLES.map((s) => `back-${s.id}`)).toEqual(BACK_COVER_STYLES.map((s) => s.id));
    // Par défaut, Élégant et Dessin sont disponibles ; les styles à images générées viendront ensuite.
    expect(S.STYLES.filter((s) => s.dispo).map((s) => s.id)).toEqual(["default", "drawing", "elegant"]);
  });

  for (const style of ["elegant", "drawing"]) {
    describe(style, () => {
      const m = maquette(style);

      it("n'emploie que les polices de son style", () => {
        const polices = new Set(m.elements.map((e) => e["police"]).filter(Boolean));
        for (const p of polices) expect(S.POLICES[style]).toContain(p);
      });

      it("pose des fonds beige, et donne au dos le fond et la police du texte de la quatrième", () => {
        const fonds = m.elements.filter((e) => e.type === "rect" && (e["h"] as number) > m.hauteur);
        expect(fonds.map((e) => e["fond"])).toEqual(["beige", "beige", "beige"]);
        const dos = m.elements.filter((e) => e["rotation"] === 90);
        expect(dos.length).toBe(3);
        const texteVerso = m.elements.find((e) => e.type === "bloc")!;
        for (const e of dos) {
          expect(e["police"]).toBe(texteVerso["police"]);
          expect(e["couleur"]).toBe(texteVerso["couleur"]);
        }
      });

      it("écrit tout en noir typo", () => {
        const couleurs = new Set(m.elements.filter((e) => e.type === "texte" || e.type === "bloc").map((e) => e["couleur"]));
        expect([...couleurs]).toEqual(["noir"]);
        expect(m.couleurs["noir"]!.hex).toBe(C.COULEURS["noir"]!.hex);
      });

      it("garde tous ses textes et ses images dans les faces visibles", () => {
        for (const partie of ["verso", "recto"] as const) {
          const face = m.faces[partie];
          for (const e of sur(m, partie).filter((x) => ["texte", "bloc", "image"].includes(x.type))) {
            if (e.type === "image" && (e["h"] as number) > m.hauteur) continue;
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
});
