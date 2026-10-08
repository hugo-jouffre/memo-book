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
type Zone = { x: number; y: number; l: number; h: number };
type Maquette = {
  elements: Element[];
  largeur: number;
  hauteur: number;
  fondPerdu: number;
  plats: Record<"verso" | "dos" | "recto", [number, number]>;
  faces: Record<"verso" | "dos" | "recto", Zone>;
};
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
  estUneIle: (lieu: Record<string, unknown>, detail: unknown) => boolean;
  lieuxDeQuatrieme: (lieux: unknown[], detail: unknown) => Record<string, unknown>[];
  RETRAIT: number;
  RETRAIT_DOS: number;
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

  it("compte les lieux de la carte, nommés comme elle les montre : îles, villes ou lieux", () => {
    const libelles = (sejours: Record<string, unknown>[]) =>
      C.chiffresQuatrieme({ jours: 15, km: 3817, pays: ["GR"], villes: ["Naoussa", "Chora"], sejours })[2]!.libelle.replace("\n", " ");
    const valeur = (sejours: Record<string, unknown>[]) =>
      C.chiffresQuatrieme({ jours: 15, km: 3817, pays: ["GR"], villes: [], sejours })[2]!.valeur;
    const iles = ["Paros", "Naxos", "Ios", "Mykonos", "Paros"].map((nom) => ({ nom, ile: true, genre: "site" }));
    // Paros revisitée compte une fois : 4 îles, comme sur la carte.
    expect(valeur(iles)).toBe("4");
    expect(libelles(iles)).toBe("îles visitées");
    expect(libelles([{ nom: "Lyon", genre: "ville" }, { nom: "Marseille", genre: "ville" }])).toBe("villes visitées");
    expect(libelles([{ nom: "Athènes", genre: "ville" }, { nom: "Paros", genre: "site", ile: true }])).toBe("lieux visités");
    expect(libelles([{ nom: "Paros", genre: "ile", ile: true }])).toBe("île visitée");
  });

  it("reconnaît une île à l'analyse, ou à sa terre sur la carte quand l'analyse n'en dit rien", () => {
    const gr = { GR: detail("GR") };
    const lieu = (nom: string, lat: number, lon: number, genre: string) => ({ nom, pays: "GR", lat, lon, genre });
    expect(C.estUneIle(lieu("Paros", 37.08, 25.15, "site"), gr)).toBe(true);
    expect(C.estUneIle(lieu("Ios", 36.73, 25.28, "site"), gr)).toBe(true);
    expect(C.estUneIle(lieu("Naxos", 0, 0, "ile"), {})).toBe(true);
    // Delphes est sur le continent ; Chora est une ville, même sur une île.
    expect(C.estUneIle(lieu("Delphes", 38.48, 22.5, "site"), gr)).toBe(false);
    expect(C.estUneIle(lieu("Chora", 37.106, 25.374, "ville"), gr)).toBe(false);
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

  it("centre le titre de la première sur sa face visible, entre le dos et la zone de pliage", () => {
    const m = mq();
    const face = m.faces.recto;
    // Face visible du relié 154 × 216 : 178 − 19 = 159 mm, mors compris.
    expect(face).toMatchObject({ x: m.plats.recto[0], l: 159, y: 19, h: 222 });
    for (const texte of ["Cyclades", "Lou, Sam et Noé\naoût 2026"]) {
      const e = m.elements.find((x) => x["texte"] === texte)!;
      const [x, y, l, h] = ["x", "y", "l", "h"].map((k) => e[k] as number) as [number, number, number, number];
      expect(x + l / 2).toBeCloseTo(face.x + face.l / 2, 1);
      // Ni sur le pli de tête, ni sur celui de pied.
      expect(y).toBeGreaterThanOrEqual(face.y + C.RETRAIT - 0.01);
      expect(y + h).toBeLessThanOrEqual(face.y + face.h - C.RETRAIT + 0.01);
    }
  });

  it("pose le dos sur le papier beige, et y écrit les voyageurs, le titre et les dates, de bas en haut", () => {
    const m = mq();
    const dos = m.elements.find((e) => e.type === "rect" && e["l"] === 8)!;
    expect(dos["fond"]).toBe("papier");
    const textes = m.elements.filter((e) => e.type === "texte" && e["rotation"] === 90);
    expect(textes.map((e) => e["couleur"])).toEqual(["encre", "encre", "encre"]);
    const par = (t: string) => textes.find((e) => e["texte"] === t)!;
    // Voyageurs calés en pied, dates en tête, titre au milieu du dos.
    expect(par("Lou, Sam et Noé")["alignement"]).toBe("gauche");
    expect(par("août 2026")["alignement"]).toBe("droite");
    const titre = par("Cyclades");
    const face = m.faces.dos;
    expect((titre["y"] as number) + (titre["h"] as number) / 2).toBeCloseTo(face.y + face.h / 2, 1);
    // Tous, une fois tournés, tiennent entre les zones de pliage de tête et de pied.
    for (const e of textes) {
      const centre = (e["y"] as number) + (e["h"] as number) / 2;
      const demi = (e["l"] as number) / 2;
      expect(centre - demi).toBeGreaterThanOrEqual(face.y + C.RETRAIT_DOS - 0.01);
      expect(centre + demi).toBeLessThanOrEqual(face.y + face.h - C.RETRAIT_DOS + 0.01);
      expect((e["x"] as number) + (e["l"] as number) / 2).toBeCloseTo(m.plats.dos[0] + 4, 1);
    }
  });

  it("garde le titre du dos à l'écart des voyageurs et des dates, quitte à réduire le corps", () => {
    const m = C.maquette({
      textes: {
        titre: "Road trip dans l'Ouest américain, de Seattle à San Diego",
        voyageurs: "Margaux, Claire, Augustin, Pierre, Jeanne et Louis",
        dates: "décembre 2025 – janvier 2026",
      },
    });
    const textes = m.elements.filter((e) => e.type === "texte" && e["rotation"] === 90);
    expect(textes).toHaveLength(3);
    expect(textes[0]!["corps"]).toBeLessThan(10);
  });

  it("centre le cadre pointillé de la quatrième sur sa face visible, à l'écart du pli et du mors, et tout son contenu dedans", () => {
    const m = mq();
    const face = m.faces.verso;
    const cadre = m.elements.find((e) => e.type === "rect" && (e["trait"] as { tirets?: unknown } | null)?.tirets)!;
    const [x, y, l, h] = ["x", "y", "l", "h"].map((k) => cadre[k] as number) as [number, number, number, number];
    expect(x - face.x).toBeCloseTo(C.RETRAIT, 5);
    expect(face.x + face.l - (x + l)).toBeCloseTo(C.RETRAIT, 5);
    expect(y - face.y).toBeCloseTo(C.RETRAIT, 5);
    expect(face.y + face.h - (y + h)).toBeCloseTo(C.RETRAIT, 5);
    const axe = x + l / 2;
    const boite = m.elements.find((e) => e.type === "rect" && e["rayon"])!;
    const logo = m.elements.find((e) => e["fichier"] === "Liens/logo-memobook.png")!;
    for (const e of [boite, logo]) {
      expect((e["x"] as number) + (e["l"] as number) / 2).toBeCloseTo(axe, 1);
      expect(e["y"] as number).toBeGreaterThan(y);
      expect((e["y"] as number) + (e["h"] as number)).toBeLessThan(y + h);
    }
    for (const e of m.elements.filter((z) => z.type === "chemin" || z.type === "cercle")) {
      const pts = e.type === "cercle" ? [[e["cx"], e["cy"]]] : (e["points"] as number[][]);
      for (const [px, py] of pts as number[][]) {
        expect(px).toBeGreaterThan(x);
        expect(px).toBeLessThan(x + l);
        expect(py).toBeGreaterThan(y);
        expect(py).toBeLessThan((boite["y"] as number));
      }
    }
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
