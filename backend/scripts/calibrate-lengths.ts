#!/usr/bin/env tsx
/**
 * Calibration du barème S/M/L/XL : combien de caractères chaque layout tient-il ?
 *
 * C'est ce script qui fait autorité sur les plafonds de
 * `LAYOUT_KB.md` § « Longueur des textes » et sur `LAYOUT_CAPACITY` dans
 * `payloadValidator.ts`. **Les chiffres ne se devinent pas : les redériver,
 * c'est relancer ce script**, pas rouvrir les tables.
 *
 * Il rend une page par variante — même chemin que la production,
 * `renderTemplateToHtml` puis Chromium en média `print` — et relève, pour
 * chaque couple (layout, longueur, nombre de paragraphes) :
 *
 * - `blanc` : ce qui reste sous le dernier texte peint. Négatif = le contenu
 *   passe sous la marge basse et se fera couper au massicot ;
 * - `compression` : de combien la bande d'images descend sous sa hauteur de
 *   conception. C'est **elle qui cède la première** — `.mb-gallery` est en
 *   `flex: 0 1 auto` pour que le récit ne soit jamais tronqué — donc c'est
 *   elle qui donne le vrai plafond éditorial : « l'image passe avant le
 *   texte » cesse d'être vrai bien avant que le texte ne déborde ;
 * - `trou` : le blanc qu'un texte trop court laisse entre le récit et la bande
 *   d'images, poussée en bas par `margin-top: auto`. C'est la borne basse ;
 * - `clip` : du texte réellement tronqué. Ne doit jamais arriver.
 *
 *   npm run calibrate                                  balaye tout
 *   npx tsx scripts/calibrate-lengths.ts --filtre SUITE --from 300 --to 1200
 *
 * Le détail par variante est écrit dans `.render-out/calibration.json`.
 */
import { writeFileSync } from "node:fs";
import { renderTemplateToHtml, installOfflineRouting, settle } from "../src/services/bookPdf.js";

const MOTS = (
  "la route serpente entre les rizieres et le vent porte une odeur de terre " +
  "mouillee nous marchons depuis le lever du jour sans croiser personne le " +
  "chauffeur du jeepney rit quand je lui montre le nom du village sur mon " +
  "carnet il repete deux fois avant de demarrer les enfants courent derriere " +
  "le vehicule et nous font de grands signes plus loin un marche installe ses " +
  "etals de mangues vertes et de poissons seches une femme me tend un verre " +
  "de jus de canne glace je bois trop vite et je tousse tout le monde rit " +
  "encore le soir tombe vite ici a six heures il fait nuit noire et les " +
  "lampes a petrole dessinent des cercles jaunes sur les murs de bambou"
).split(/\s+/);

/** Texte de `chars` caractères environ, decoupe en `paragraphs` blocs. */
function corps(chars: number, paragraphs: number): string {
  const parts: string[] = [];
  let curseur = 0;
  const parChunk = Math.round(chars / paragraphs);
  for (let p = 0; p < paragraphs; p += 1) {
    let texte = "";
    while (texte.length < parChunk) {
      texte += (texte ? " " : "") + MOTS[curseur % MOTS.length];
      curseur += 1;
    }
    parts.push(`<p>${texte.slice(0, parChunk).trim()}.</p>`);
  }
  return parts.join("");
}

/** Photo du bundle hors ligne : la mesure ne doit pas dépendre du réseau. */
const PHOTO =
  "https://cdn.prod.website-files.com/68827087b5bebc3702bf1a54/sample-jour-03a.jpg";

interface Variante extends Config {
  id: string;
  layout: string;
  chars: number;
  paragraphs: number;
}

interface Config {
  flag: string;
  photos: number;
  funFact: boolean;
  /** Bloc interactif : il remplace la zone flottante du bas de page. */
  bloc?: "prompt" | "quiz";
  /** Page de suite d'une étape : sans bandeau `day_intro`, comme le veut
      LAYOUT_KB pour la deuxième page d'une même étape. */
  suite?: boolean;
  note: string;
}

const LAYOUTS: Config[] = [
  { flag: "layout_story_opener", photos: 1, funFact: true, note: "récit + carte info et photo flottantes" },
  { flag: "layout_story_opener", photos: 1, funFact: false, note: "récit + photo flottante" },
  { flag: "layout_story_opener", photos: 1, funFact: false, bloc: "prompt", note: "récit + champ à remplir" },
  { flag: "layout_story_opener", photos: 1, funFact: false, bloc: "quiz", note: "récit + quiz" },
  { flag: "layout_hero_top", photos: 1, funFact: false, note: "photo héro en tête" },
  { flag: "layout_split_left", photos: 2, funFact: true, note: "colonne étroite, carte info à gauche" },
  { flag: "layout_split_left", photos: 2, funFact: false, note: "sans carte info : colonne pleine largeur" },
  { flag: "layout_collage", photos: 3, funFact: false, note: "récit pleine largeur + 3 photos" },
  { flag: "layout_collage", photos: 2, funFact: false, note: "récit pleine largeur + 2 photos" },
  { flag: "layout_chapter_map", photos: 2, funFact: true, note: "carte + carte info + 2 photos" },
  { flag: "layout_chapter_map", photos: 2, funFact: false, note: "carte + 2 photos" },
  { flag: "layout_chapter_map", photos: 0, funFact: false, note: "carte seule, pas de bande d'images" },
  { flag: "layout_story_opener", photos: 1, funFact: false, suite: true, note: "PAGE DE SUITE, sans bandeau" },
  { flag: "layout_collage", photos: 3, funFact: false, suite: true, note: "PAGE DE SUITE, sans bandeau" },
  { flag: "layout_split_left", photos: 2, funFact: false, suite: true, note: "PAGE DE SUITE, sans bandeau" },
  { flag: "layout_hero_top", photos: 1, funFact: false, suite: true, note: "PAGE DE SUITE, sans bandeau" },
  { flag: "layout_chapter_map", photos: 2, funFact: false, suite: true, note: "PAGE DE SUITE, sans bandeau" },
];

/** Plage balayée, réglable : `--from 80 --to 1200 --pas 20 --filtre suite`. */
const args = process.argv.slice(2);
const opt = (nom: string, defaut: string) => {
  const i = args.indexOf(`--${nom}`);
  return i >= 0 && args[i + 1] ? (args[i + 1] as string) : defaut;
};
const FROM = Number(opt("from", "80"));
const TO = Number(opt("to", "1000"));
const PAS = Number(opt("pas", "20"));
const FILTRE = opt("filtre", "");

const LONGUEURS: number[] = [];
for (let n = FROM; n <= TO; n += PAS) LONGUEURS.push(n);

/** Nombre de paragraphes testé pour une longueur : chaque `<p>` coûte une
    ligne vide, soit ~57 caractères de budget. On mesure les deux découpes
    plausibles pour chaque palier plutôt que d'en supposer une. */
function decoupes(chars: number): number[] {
  if (chars <= 200) return [1];
  if (chars <= 400) return [1, 2];
  if (chars <= 620) return [2, 3];
  if (chars <= 900) return [3, 4];
  return [4, 5];
}

const variantes: Variante[] = [];
for (const l of LAYOUTS) {
  if (FILTRE && !`${l.flag} ${l.note}`.toLowerCase().includes(FILTRE.toLowerCase())) continue;
  for (const chars of LONGUEURS) {
    for (const paragraphs of decoupes(chars)) {
      variantes.push({ ...l, id: `${l.flag}|${l.photos}|${l.funFact}|${l.bloc ?? ""}|${chars}|${paragraphs}`, layout: l.flag, chars, paragraphs });
    }
  }
}

const payload: Record<string, unknown> = {
  render_profile: "print",
  book_title: "Calibration",
  days: variantes.map((v) => {
    const day: Record<string, unknown> = {
      title: v.suite ? "" : "Un titre d'etape de longueur courante",
      body_html: corps(v.chars, v.paragraphs),
      photos: Array.from({ length: v.photos }, () => PHOTO),
      [v.layout]: true,
    };
    if (!v.suite) {
      day["day_intro"] = {
        day_number: "01",
        location: "Cebu, Philippines",
        date: "22 fev 2026",
        stay: "Casa Verde",
      };
    }
    if (v.funFact) {
      day["fun_facts"] = ["Les Philippines comptent plus de 7000 iles, dont un tiers seulement porte un nom."];
    }
    if (v.bloc === "prompt") day["prompt"] = { label: "Ton etat d'esprit ce jour-la" };
    if (v.bloc === "quiz") {
      day["quiz"] = {
        question: "Combien d'iles comptent les Philippines ?",
        choices: ["environ 700", "environ 7000", "environ 70 000"],
        answer: "environ 7641",
      };
    }
    if (v.layout === "layout_chapter_map") {
      day["map"] = { regions: ["PH"], points: [{ label: "Cebu", lat: 10.31, lon: 123.88 }] };
    }
    return day;
  }),
};

const { chromium } = await import("playwright-core");
const browser = await chromium.launch({ args: ["--font-render-hinting=none", "--hide-scrollbars"] });
const context = await browser.newContext({ deviceScaleFactor: 1, locale: "fr-FR" });
await installOfflineRouting(context);
const page = await context.newPage();
await page.emulateMedia({ media: "print" });
await page.setContent(renderTemplateToHtml({ payload, profile: "print" }), { waitUntil: "load" });
await settle(page);

const mesures = await page.evaluate(() => {
  const PT = 96 / 72;
  /* Hauteurs de conception, reprises de style.css : au-delà, la bande d'images
     cède avant le texte — c'est là que la page cesse d'être celle qu'on a
     dessinée, bien avant que le texte ne déborde vraiment. */
  const CONCEPTION = {
    ".mb-gallery": 206 * PT,
    ".mb-hero": 268 * PT,
    ".mb-day__floats": 175 * PT,
    ".mb-chapter__map": 176 * PT,
  };

  const pages = Array.from(document.querySelectorAll(".page--day"));
  return pages.map((p) => {
    const content = p.querySelector(".page__content") as HTMLElement;
    const style = getComputedStyle(content);
    const utile =
      content.getBoundingClientRect().height -
      parseFloat(style.paddingTop) -
      parseFloat(style.paddingBottom);

    // Texte tronqué : le bloc de récit ne rend plus tout ce qu'on lui a donné.
    let clip = 0;
    for (const note of Array.from(p.querySelectorAll(".mb-note"))) {
      const el = note as HTMLElement;
      clip = Math.max(clip, el.scrollHeight - el.clientHeight);
    }

    // Compression : la bande d'images descend sous sa hauteur de conception.
    let compression = 0;
    let bloc = "";
    for (const [selecteur, attendu] of Object.entries(CONCEPTION)) {
      const el = p.querySelector(selecteur);
      if (!el) continue;
      const manque = attendu - el.getBoundingClientRect().height;
      if (manque > compression) {
        compression = manque;
        bloc = selecteur;
      }
    }

    // Blanc restant en bas : ce qui reste sous le dernier bloc visible.
    const boxBottom = content.getBoundingClientRect().bottom - parseFloat(style.paddingBottom);
    /* On cherche le bas du texte réellement peint, pas celui des conteneurs :
       une boîte flex clampée garde sa hauteur pendant que son texte déborde
       par-dessous, et ce débordement-là est celui qui s'imprime. */
    let bas = content.getBoundingClientRect().top + parseFloat(style.paddingTop);
    for (const noeud of Array.from(p.querySelectorAll(".mb-note p, .mb-note ul, .mb-note__title, .mb-card, .mb-photo, .mb-gallery, .mb-prompt, .mb-quiz"))) {
      const r = (noeud as HTMLElement).getBoundingClientRect();
      if (r.height > 0) bas = Math.max(bas, r.bottom);
    }
    // Hauteur du seul récit, indicateur du poids du texte dans la page.
    const note = p.querySelector(".mb-note");

    /* Le vide qu'un texte trop court laisse au milieu de la page : la bande
       d'images est poussée en bas (`margin-top: auto`), le récit reste en
       haut, et le blanc s'installe entre les deux. C'est cette respiration-là
       qui devient un trou, pas le bas de page. */
    let trou = 0;
    if (note) {
      const apres = note.closest(".page__content") ? note.parentElement : null;
      const reference = apres === content ? note : (note.closest(".mb-split, .mb-chapter")) ?? note;
      let suivant = reference.nextElementSibling as HTMLElement | null;
      while (suivant && suivant.getBoundingClientRect().height === 0) {
        suivant = suivant.nextElementSibling as HTMLElement | null;
      }
      const basRecit = reference.getBoundingClientRect().bottom;
      trou = suivant
        ? suivant.getBoundingClientRect().top - basRecit
        : boxBottom - basRecit;
    }

    return {
      utile: Math.round(utile),
      recit: note ? Math.round(note.getBoundingClientRect().height) : 0,
      blanc: Math.round(boxBottom - bas),
      horsPage: Math.round(bas - p.getBoundingClientRect().bottom),
      trou: Math.round(trou),
      compression: Math.round(compression),
      blocComprime: bloc,
      clip: Math.round(clip),
    };
  });
});

type Mesure = (typeof mesures)[number];
const lignes = variantes.map((v, i) => ({ ...v, ...(mesures[i] as Mesure) }));
writeFileSync(
  new URL("../.render-out/calibration.json", import.meta.url),
  JSON.stringify(lignes, null, 2),
);

let dernier = "";
for (const l of lignes) {
  const cle = `${l.layout} — ${l.note} (${l.photos} photo(s)${l.bloc ? ", " + l.bloc : ""})`;
  if (cle !== dernier) {
    console.log(`\n=== ${cle} (hauteur utile ${l.utile} px) ===`);
    console.log("chars  ¶  récit  blanc   trou  compression        texte tronqué");
    dernier = cle;
  }
  console.log(
    [
      String(l.chars).padStart(5),
      String(l.paragraphs),
      String(l.recit).padStart(5),
      String(l.blanc).padStart(5),
      String(l.trou).padStart(5),
      (l.compression > 2 ? `-${l.compression}px ${l.blocComprime}` : "—").padEnd(28),
      l.clip > 2 ? `⚠ ${l.clip}px` : "—",
    ].join("  "),
  );
}

await browser.close();
