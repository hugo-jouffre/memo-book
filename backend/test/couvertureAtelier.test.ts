import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { runInNewContext } from "node:vm";
import { describe, expect, it } from "vitest";
import { renderTemplateToHtml } from "../src/services/bookPdf.js";

/**
 * La couverture imprimée de l'atelier (`MemoBook Generator/public/couverture.js`) :
 * le choix des photos et leur contrôle qualité, les textes et les chiffres
 * tirés du voyage, la maquette, et le script InDesign qui la construit.
 *
 * InDesign n'existe pas ici : le script est lu en ES3 (ExtendScript) et
 * exécuté contre une imitation de son modèle objet, qui retient chaque objet
 * créé. C'est ce qui attrape une coquille, une fonction moderne ou un élément
 * oublié — pas un rendu InDesign.
 */
const require = createRequire(import.meta.url);
type Element = Record<string, unknown> & { type: string };
type Maquette = { elements: Element[]; largeur: number; hauteur: number; fondPerdu: number };
type Evaluation = { score: number; dpi: number; alertes: string[]; suffisante: boolean };
type Photo = { id: string; largeur: number; hauteur: number; groupe?: boolean; mesure?: unknown; analyse?: unknown };
const C = require("../../MemoBook Generator/public/couverture.js") as {
  FICHE_DEFAUT: Record<string, unknown>;
  dosPumbo: (pages: number) => number;
  pagesDuPdf: (payload: Record<string, unknown>) => number;
  ficheDuCarnet: (fiche: Record<string, unknown>, pages: number) => Record<string, unknown>;
  evaluerPhoto: (photo: Photo, options?: Record<string, unknown>) => Evaluation;
  proposerPhotos: (photos: Photo[]) => {
    recto: { photo: Photo }[];
    verso: { photo: Photo }[];
    meilleure: { photo: Photo } | null;
  };
  moisDuVoyage: (debut: string, fin: string) => string;
  textesParDefaut: (o: Record<string, unknown>) => { titre: string; voyageurs: string; dates: string };
  chiffresQuatrieme: (o: Record<string, unknown>) => { valeur: string; libelle: string }[];
  maquette: (o: Record<string, unknown>) => Maquette;
  versJsx: (m: Maquette, o?: Record<string, unknown>) => string;
  versSvg: (m: Maquette) => string;
  zipper: (fichiers: { nom: string; octets: Uint8Array }[]) => Uint8Array;
  crc32: (o: Uint8Array) => number;
};
const V = require("../../MemoBook Generator/public/voyage.js") as {
  lieuxDeSejour: (etapes: unknown[]) => unknown[];
};
const detail = (code: string) =>
  JSON.parse(readFileSync(resolve(import.meta.dirname, `../../assets/maps/detail/${code}.json`), "utf8")) as unknown;

const nette = { nettete: 600, luminance: 128, ecretage: 0.02 };
const portrait = (id: string, autres: Partial<Photo> = {}): Photo => ({
  id,
  largeur: 3000,
  hauteur: 4000,
  mesure: nette,
  analyse: { couverture: 7, personnes: 0 },
  ...autres,
});

describe("couverture : les photos", () => {
  it("ne signale rien pour une photo nette, bien exposée et assez grande", () => {
    expect(C.evaluerPhoto(portrait("a"), { mesure: nette }).alertes).toEqual([]);
  });

  it("signale une résolution insuffisante, une photo floue, sombre ou trop rognée", () => {
    const alertes = (photo: Photo, mesure: unknown) => C.evaluerPhoto(photo, { mesure }).alertes.join(" ");
    expect(alertes(portrait("a", { largeur: 900, hauteur: 1200 }), nette)).toMatch(/Résolution insuffisante/);
    expect(alertes(portrait("a"), { ...nette, nettete: 12 })).toMatch(/floue/);
    expect(alertes(portrait("a"), { ...nette, luminance: 30 })).toMatch(/sombre/);
    expect(alertes(portrait("a"), { ...nette, ecretage: 0.4 })).toMatch(/surexposée/);
    expect(alertes(portrait("a", { largeur: 4000, hauteur: 3000 }), nette)).toMatch(/rogne/);
    // Une photo de groupe se rogne moins qu'une autre.
    expect(alertes(portrait("a", { largeur: 3200, hauteur: 3000, groupe: true }), nette)).toMatch(/groupe/);
  });

  it("propose six photos différentes, les meilleures d'abord, jamais une qui échoue au contrôle qualité", () => {
    const photos = [
      portrait("plat", { analyse: { couverture: 2 } }),
      portrait("paysage-large", { largeur: 4000, hauteur: 2000, analyse: { couverture: 10 } }),
      portrait("petite", { largeur: 900, hauteur: 1200, analyse: { couverture: 10 } }),
      portrait("floue", { mesure: { ...nette, nettete: 10 }, analyse: { couverture: 10 } }),
      ...["a", "b", "c", "d", "e", "f"].map((id, i) => portrait(id, { analyse: { couverture: 9 - i * 0.5 } })),
    ];
    const { recto, verso } = C.proposerPhotos(photos);
    expect(recto.map((e) => e.photo.id)).toEqual(["a", "b", "c"]);
    expect(verso.map((e) => e.photo.id)).toEqual(["d", "e", "f"]);
  });

  it("garde la mieux notée de toutes pour la couverture quand aucune ne passe le contrôle", () => {
    const { recto, meilleure } = C.proposerPhotos([
      portrait("petite", { largeur: 900, hauteur: 1200 }),
      portrait("minuscule", { largeur: 300, hauteur: 400 }),
    ]);
    expect(recto).toEqual([]);
    expect(meilleure?.photo.id).toBe("petite");
  });
});

describe("couverture : le dos", () => {
  it("suit le barème Pumbo : 8 mm jusqu'à 56 pages, puis 3 mm + 0,09 mm par page", () => {
    expect(C.dosPumbo(16)).toBe(8);
    expect(C.dosPumbo(56)).toBe(8);
    expect(C.dosPumbo(58)).toBe(8.2);
    expect(C.dosPumbo(100)).toBe(12);
    expect(C.dosPumbo(200)).toBe(21);
    expect(C.dosPumbo(137)).toBe(15.3);
  });

  it("compte les pages comme le gabarit les rend — en version imprimeur, sans couverture ni quatrième", () => {
    const jour = (i: number) => ({ title: `Jour ${i}`, body_html: "<p>Un récit.</p>", layout_story_opener: true, photos: [] });
    const base = {
      render_profile: "print",
      book_title: "Cyclades",
      days: [1, 2, 3, 4].map(jour),
      back_cover: { closing_text: "À suivre.", cta: "memobook.fr" },
    };
    const pagesRendues = (payload: Record<string, unknown>) =>
      (renderTemplateToHtml({ payload, profile: "print" }).match(/<div class="page[ "]/g) ?? []).length;
    for (const payload of [
      base,
      { ...base, sans_couvertures: true },
      { ...base, sans_couvertures: true, page_blanche_finale: true },
      { ...base, sans_couvertures: true, intro_text: "<p>Avant le départ.</p>" },
    ]) {
      expect(C.pagesDuPdf(payload)).toBe(pagesRendues(payload));
    }
    // Quatre étapes, le colophon et la page blanche : six pages reliées.
    expect(C.pagesDuPdf({ ...base, sans_couvertures: true, page_blanche_finale: true })).toBe(6);
  });

  it("élargit la planche du dos du carnet, plats de la fiche inchangés", () => {
    const fiche = C.ficheDuCarnet(C.FICHE_DEFAUT, 100);
    expect(fiche).toMatchObject({ dos: 12, pages: 100, largeurPlat: 178, hauteurPlat: 260, parDefaut: false });
    const m = C.maquette({ fiche, textes: { titre: "Cyclades" } });
    expect(m.largeur).toBe(2 * 178 + 12);
    expect(C.ficheDuCarnet(C.FICHE_DEFAUT, 12)["tropCourt"]).toBe(true);
  });
});

describe("couverture : textes et chiffres", () => {
  it("tire les textes du carnet, rien d'écrit en dur", () => {
    const t = C.textesParDefaut({ destination: "Cyclades", voyageurs: ["Lou", "Sam", "Noé"], debut: "2026-08-22", fin: "2026-09-05" });
    expect(t).toEqual({ titre: "Cyclades", voyageurs: "Lou, Sam et Noé", dates: "août – septembre 2026" });
    expect(C.moisDuVoyage("2026-02-03", "2026-02-20")).toBe("février 2026");
    expect(C.moisDuVoyage("2025-12-28", "2026-01-04")).toBe("décembre 2025 – janvier 2026");
  });

  it("montre les pays quand il y en a plusieurs, sinon les villes", () => {
    const valeurs = (o: Record<string, unknown>) =>
      C.chiffresQuatrieme(o).map((c) => `${c.valeur} ${c.libelle.split("\n")[0]}`.replace(/\s/g, " "));
    expect(valeurs({ jours: 13, km: 22340, pays: ["PH", "ID", "MY"], villes: ["Manille"] })).toEqual(["13 jours", "22k km", "3 pays"]);
    expect(valeurs({ jours: 15, km: 3817, pays: ["GR"], villes: ["Naoussa", "Chora"] })).toEqual(["15 jours", "3 817 km", "2 villes"]);
    expect(valeurs({ jours: 4, km: null, pays: ["FR"], villes: [] })).toEqual(["4 jours", "1 pays"]);
  });
});

const L = (nom: string, lat: number, lon: number) => ({ nom, pays: "GR", lat, lon });
const etapes = [
  { analyse: { lieu: L("Paros", 37.08, 25.15), lieux: [L("Kolymbithres", 37.13, 25.21)], trajets: [{ depart: { nom: "Genève", pays: "CH", lat: 46.2, lon: 6.14 }, arrivee: L("Paros", 37.08, 25.15), mode: "avion" }] } },
  { analyse: { lieu: L("Naxos", 37.1, 25.38), lieux: [], trajets: [{ depart: L("Paros", 37.08, 25.15), arrivee: L("Naxos", 37.1, 25.38), mode: "bateau" }] } },
  { analyse: { lieu: L("Ios", 36.73, 25.28), lieux: [], trajets: [] } },
];
const mq = () =>
  C.maquette({
    textes: { titre: "Cyclades", voyageurs: "Lou, Sam et Noé", dates: "août 2026" },
    recto: { fichier: "Liens/recto.jpg", src: "data:image/jpeg;base64,AAAA", px: [3000, 4000] },
    chiffres: C.chiffresQuatrieme({ jours: 15, km: 3817, pays: ["GR"], villes: ["Naoussa"] }),
    carte: { lieux: V.lieuxDeSejour(etapes), detail: { GR: detail("GR") } },
    logo: { fichier: "Liens/logo-memobook.png", src: "data:image/png;base64,AAAA", px: [1200, 1200] },
  });

describe("couverture : la maquette", () => {
  it("pose la photo en fond perdu sur la première, et les textes du voyage", () => {
    const m = mq();
    const image = m.elements.find((e) => e.type === "image" && e["fichier"] === "Liens/recto.jpg")!;
    // Fond perdu : la photo dépasse du trait de coupe en haut, en bas et à droite.
    expect(image["y"]).toBe(-m.fondPerdu);
    expect((image["x"] as number) + (image["l"] as number)).toBe(m.largeur + m.fondPerdu);
    const textes = m.elements.filter((e) => e.type === "texte").map((e) => e["texte"]);
    expect(textes).toContain("Cyclades");
    expect(textes).toContain("Lou, Sam et Noé\naoût 2026");
    expect(textes).toContain("Mon voyage en quelques chiffres");
    // Rien du modèle de `assets/covers/` : ni Philippines, ni Margaux.
    expect(JSON.stringify(m.elements)).not.toMatch(/Philippines|Margaux|Augustin|22k/);
  });

  it("pose le dos sur le papier beige de la quatrième, le texte à l'encre", () => {
    const m = mq();
    const dos = m.elements.find((e) => e.type === "rect" && e["l"] === 8)!;
    expect(dos["fond"]).toBe("papier");
    expect(m.elements.find((e) => e.type === "texte" && e["rotation"] === 90)!["couleur"]).toBe("encre");
  });

  it("dessine sur la quatrième les villes du séjour, reliées dans l'ordre de visite", () => {
    const m = mq();
    const noms = m.elements.filter((e) => e.type === "texte" && e["corps"] === 6.5).map((e) => e["texte"]);
    // La plage visitée sur Paros n'est pas une étape du séjour : pas de nom, pas de point.
    expect(noms).toEqual(["Paros", "Naxos", "Ios"]);
    expect(m.elements.filter((e) => e.type === "cercle")).toHaveLength(3);
    // Paros → Naxos en bateau (pointillés), Naxos → Ios sans moyen connu.
    const trajets = m.elements.filter((e) => e.type === "chemin" && (e["trait"] as { epaisseur: number }).epaisseur === 0.7);
    expect(trajets).toHaveLength(2);
    // Toute la carte reste sur la quatrième, dans le cadre.
    for (const e of m.elements.filter((x) => x.type === "chemin")) {
      for (const [x] of e["points"] as number[][]) expect(x).toBeLessThan(m.largeur / 2);
    }
  });
});

describe("couverture : le fichier InDesign", () => {
  it("est un script ExtendScript (ES3), en ASCII", () => {
    const jsx = C.versJsx(mq(), { titre: "Cyclades" });
    // eslint-disable-next-line no-control-regex
    expect(jsx).toMatch(/^[\x00-\x7f]*$/);
    // acorn vient avec ESLint : s'il manque, on se contente du contrôle ASCII.
    type Analyseur = { parse: (source: string, options: Record<string, unknown>) => unknown };
    const analyseur = (() => {
      try {
        return require("acorn") as Analyseur;
      } catch {
        return null;
      }
    })();
    if (analyseur) expect(() => analyseur.parse(jsx, { ecmaVersion: 3, allowReserved: true })).not.toThrow();
  });

  it("construit chaque élément de la maquette dans le modèle objet d'InDesign", () => {
    const m = mq();
    const crees: string[] = [];
    const places: string[] = [];
    const enumeration = new Proxy({}, { get: (_, nom) => String(nom) });
    const objet = (chemin: string): unknown =>
      new Proxy(function () {}, {
        get: (_, nom) => {
          if (nom === Symbol.toPrimitive) return () => 0;
          if (nom === "length") return 0;
          if (nom === "exists") return true;
          if (nom === "fullName" || nom === "fsName") return "/dossier";
          return objet(`${chemin}.${String(nom)}`);
        },
        set: () => true,
        apply: (_, __, args) => {
          const nom = chemin.split(".").pop()!;
          if (nom === "add") crees.push(chemin.split(".").slice(-2)[0]!);
          if (nom === "place") places.push(String((args[0] as { nom?: string })?.nom));
          if (nom === "doScript") (args[0] as () => void)();
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
          "CoordinateSpaces", "AnchorPoint", "ScriptLanguage", "UndoModes", "ZoomOptions",
        ].map((nom) => [nom, enumeration]),
      ),
    };
    runInNewContext(C.versJsx(m, { titre: "Cyclades" }), contexte);

    const compte = (type: string) => m.elements.filter((e) => e.type === type).length;
    const nombre = (collection: string) => crees.filter((c) => c === collection).length;
    expect(nombre("rectangles")).toBe(compte("rect") + compte("image"));
    expect(nombre("textFrames")).toBe(compte("texte"));
    expect(nombre("graphicLines") + nombre("polygons")).toBe(compte("chemin"));
    expect(nombre("ovals")).toBe(compte("cercle"));
    expect(places).toEqual(["/dossier/Liens/recto.jpg", "/dossier/Liens/logo-memobook.png"]);
  });

  it("se range dans une archive .zip lisible", () => {
    const enc = new TextEncoder();
    const zip = C.zipper([
      { nom: "Couverture MemoBook/Couverture MemoBook.jsx", octets: enc.encode(C.versJsx(mq())) },
      { nom: "Couverture MemoBook/Liens/recto.jpg", octets: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]) },
    ]);
    expect(C.crc32(enc.encode("123456789"))).toBe(0xcbf43926);
    const dossier = mkdtempSync(join(tmpdir(), "couverture-"));
    const fichier = join(dossier, "couverture.zip");
    writeFileSync(fichier, zip);
    let sortie = "";
    try {
      sortie = execFileSync("unzip", ["-t", fichier], { encoding: "utf8" });
    } catch (erreur) {
      if ((erreur as NodeJS.ErrnoException).code === "ENOENT") return;
      throw erreur;
    }
    expect(sortie).toMatch(/No errors detected/);
  });

  it("donne un aperçu SVG aux dimensions de la planche, fond perdu compris", () => {
    const m = mq();
    const svg = C.versSvg(m);
    expect(svg).toContain(`width="${m.largeur + 2 * m.fondPerdu}mm"`);
    expect(svg).toContain(">Cyclades<");
  });
});
