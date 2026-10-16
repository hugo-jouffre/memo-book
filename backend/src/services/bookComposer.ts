/**
 * La composition du carnet de l'app, par **le même composeur que l'atelier**.
 *
 * Hugo, 13/10/2026 : « le composeur compose, le ratio dit combien de photos ».
 * Jusqu'ici l'app recomposait chaque étape avec le module de ratio
 * (`appliquerRatio`), qui choisissait seul ses layouts : ni étapes paires, ni
 * photos en fin d'étape, ni planches, ni décors. Désormais :
 *
 * 1. le **module de ratio** (`photoRatio.ts`, `photosRequired`) dit combien de
 *    photos chaque étape garde, selon le palier du voyageur ;
 * 2. le **composeur de l'atelier** (`MemoBook Generator/public/mise-en-page.js`,
 *    `composerJours`) met en page — structure de l'étape, layouts, cartes de
 *    chapitre, fun facts, tracé, étiquettes, stickers — exactement comme pour
 *    le PDF de l'atelier.
 *
 * Le composeur est chargé tel quel (`createRequire`), pas recopié : c'est un
 * module UMD sans dépendance, que les tests chargent déjà de la même façon.
 * L'image Docker le copie à côté des gabarits (`backend/Dockerfile`).
 *
 * Ce qui vient de l'Agent Mise en page et que le composeur ne sait pas
 * deviner — le bandeau (météo, nuit, hôte), l'étiquette de section, le champ à
 * remplir, la carte du chapitre — est repris sur la première page de
 * l'étape. Le quiz, lui, est placé par le composeur (`placerQuiz`) : il
 * remplace la zone flottante du bas, et la première page n'a pas toujours de
 * quoi le porter sans perdre une photo. **Le récit ne perd ni ne gagne un mot** : ses paragraphes passent
 * tels quels, au pire coupés sur une fin de phrase entre deux pages.
 */
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { etapesDe, layoutDe, paragraphesDe, PLANCHES, photosRequired, type PhotoRatio } from "./photoRatio.js";

type Jour = Record<string, unknown>;

interface Sticker {
  fichier: string;
  famille?: string;
  url?: string;
  [cle: string]: unknown;
}

interface Composeur {
  composerJours: (etapes: unknown[], options: Record<string, unknown>) => Jour[];
  paragraphesEnHtml: (paragraphes: string[]) => string;
}

const require = createRequire(import.meta.url);
const ATELIER = resolve(import.meta.dirname, "../../../MemoBook Generator/public/mise-en-page.js");
const STICKERS = resolve(import.meta.dirname, "../../../assets/stickers/stickers.json");

/**
 * Les fichiers de stickers, servis par GitHub à une adresse publique que le
 * moteur PDF peut charger — la même que l'atelier (`STICKERS_URL`, `app.js`).
 */
export const STICKERS_URL = "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/assets/stickers/";

let composeur: Composeur | undefined;
function charger(): Composeur {
  composeur ??= require(ATELIER) as Composeur;
  return composeur;
}

let bibliotheque: Sticker[] | undefined;
/** La bibliothèque de stickers (`assets/stickers/stickers.json`), avec l'adresse de chaque fichier. */
export function stickersDuCarnet(): Sticker[] {
  if (!bibliotheque) {
    try {
      const index = JSON.parse(readFileSync(STICKERS, "utf8")) as { stickers?: Sticker[] };
      bibliotheque = (index.stickers ?? []).map((s) => ({ ...s, url: `${STICKERS_URL}${encodeURIComponent(s.fichier)}` }));
    } catch {
      // Sans bibliothèque, le carnet n'a pas de stickers : rien d'autre ne change.
      bibliotheque = [];
    }
  }
  return bibliotheque;
}

/**
 * Ce que l'agent pose sur la première page d'une étape et que le composeur
 * reprend tel quel. Pas le quiz : le composeur le place lui-même, et un quiz
 * recopié ici reviendrait sur une page qui a peut-être des photos — le gabarit
 * les remplacerait par lui.
 */
const CHAMPS_DU_BANDEAU = ["title", "date", "city", "country", "day_intro", "tag", "prompt"] as const;

/** Les pages qui précèdent la première étape : colophon, introduction, et la page blanche qui la met à gauche. */
function pagesAvant(payload: Record<string, unknown>): number {
  const avant = 1 + (payload["intro_text"] ? 1 : 0);
  return avant + (avant % 2 === 0 ? 1 : 0);
}

/**
 * Les pages du carnet hors des étapes : celles d'avant. Les pages libres de
 * fin ne sont plus imprimées (15/10/2026) : `pages_libres` ne compte plus.
 */
function pagesFixes(payload: Record<string, unknown>): number {
  return pagesAvant(payload);
}

const texte = (valeur: unknown): string => (typeof valeur === "string" ? valeur : "");
const urlDe = (photo: unknown): string =>
  typeof photo === "string" ? photo : texte((photo as Record<string, unknown> | null)?.["url"]);

/** Une étape du payload de l'app, dans la forme que le composeur lit (`composerJours`). */
function etapeDuPayload(pages: Jour[], rang: number, funFacts: boolean, quiz: boolean) {
  const premiere = pages[0] ?? {};
  const intro = (premiere["day_intro"] ?? {}) as Record<string, unknown>;
  const paragraphes = pages
    .filter((page) => !(PLANCHES as readonly string[]).includes(layoutDe(page)))
    .flatMap((page) => paragraphesDe(texte(page["body_html"])));
  const photos = pages
    .flatMap((page) => (Array.isArray(page["photos"]) ? (page["photos"] as unknown[]) : []))
    .filter((p) => urlDe(p))
    .map((p, i) => {
      const objet = typeof p === "string" ? {} : (p as Record<string, unknown>);
      return {
        id: `${rang}-${i}`,
        src: urlDe(p),
        // Le format et la photo de groupe, quand l'analyse d'image les a donnés.
        ...(typeof objet["format"] === "number" ? { format: objet["format"] } : {}),
        groupe: objet["fit"] === "contain",
      };
    });
  // Tous les fun facts de l'étape, de toutes ses pages : la mise en page en
  // pose environ un toutes les trois pages (Hugo, 13/10/2026).
  // Chacun avec le titre que la rédaction lui a donné (« Infos », « Culture
  // générale »…) : le composeur le garde, et varie les autres.
  const funFactsDeLEtape = pages.flatMap((page) =>
    (Array.isArray(page["fun_facts"]) ? (page["fun_facts"] as unknown[]) : [])
      .filter((f): f is string => typeof f === "string" && f.trim().length > 0)
      .map((texte) => ({ texte, titre: typeof page["fun_facts_title"] === "string" ? page["fun_facts_title"] : "" })),
  );
  // Le quiz de l'étape, où que le metteur en page l'ait posé — un seul.
  const quizDeLEtape = pages.find((page) => page["quiz"] && typeof page["quiz"] === "object")?.["quiz"] ?? null;
  return {
    titre: texte(premiere["title"]),
    lieu: texte(premiere["city"]) || texte(intro["location"]),
    destination: texte(premiere["country"]),
    numero: texte(intro["day_number"]),
    lieuComplet: texte(intro["location"]),
    dateLongue: texte(intro["date"]) || texte(premiere["date"]),
    paragraphes,
    recit: paragraphes.join(" "),
    photos,
    // La carte que l'agent a choisie pour ouvrir le chapitre.
    carte: premiere["map"] ?? premiere["map_svg"] ?? null,
    // Les fun facts déjà rédigés et bornés à 140 signes par la rédaction : ils
    // ont passé leur tri, ils sont imprimables.
    analyse: funFacts && funFactsDeLEtape.length ? { funFacts: funFactsDeLEtape.map((f) => ({ ...f, pertinence: 8 })) } : null,
    // Le quiz déjà rédigé, déjà filtré par le réglage (`structure.ts`).
    quiz: quiz ? quizDeLEtape : null,
    // Le champ à remplir revient sur la première page : le quiz ne s'y pose pas.
    promptEnTete: Boolean(premiere["prompt"]),
    premiere,
  };
}

export interface ComposerOptions {
  ratio: PhotoRatio;
  funFacts: boolean;
  /** « Quiz intégrés à l'histoire ». Absent : allumé, comme le défaut du carnet. */
  quiz?: boolean;
  decorations: number;
  /**
   * Le nombre de pages cible du voyage (`Memo.targetPageCount`). Le carnet
   * entier — étapes, et les pages fixes autour : colophon, introduction, pages
   * libres — tient alors dans la cible à ± `PAGE_TARGET_TOLERANCE` pages, par
   * ses seules planches de photos (`recalerSurLaCible`, `mise-en-page.js`).
   * Absent : aucun recalage.
   */
  pagesCible?: number;
  /** Ce que le composeur note en chemin : photos écartées, cible hors d'atteinte. */
  journal?: (texte: string) => void;
}

/**
 * Les `days[]` de l'app, recomposés par le composeur de l'atelier, au palier
 * de photos du voyageur.
 */
export function composerCarnet(payload: Record<string, unknown>, options: ComposerOptions): Jour[] {
  const days = Array.isArray(payload["days"]) ? (payload["days"] as Jour[]) : [];
  const quiz = options.quiz !== false;
  const etapes = etapesDe(days).map((pages, rang) => etapeDuPayload(pages, rang, options.funFacts, quiz));
  const { composerJours, paragraphesEnHtml } = charger();

  const sortie: Jour[] = [];
  let etapeCourante = -1;
  const jours = composerJours(
    etapes.map(({ premiere: _premiere, ...etape }) => etape),
    {
      pagesAvant: pagesAvant(payload),
      funFacts: options.funFacts,
      quiz,
      stickers: options.decorations > 0 ? stickersDuCarnet() : [],
      decorations: options.decorations,
      ratio: options.ratio,
      ...(options.pagesCible ? { pagesCible: options.pagesCible, pagesFixes: pagesFixes(payload) } : {}),
      ...(options.journal ? { journal: options.journal } : {}),
      budgetPhotos: (etape: { paragraphes: string[] }) =>
        photosRequired({ body_html: paragraphesEnHtml(etape.paragraphes) }, options.ratio, "a5", {
          funFacts: options.funFacts,
          decorations: options.decorations > 0,
        }).photos,
    },
  );

  // Le bandeau de l'agent revient sur la page qui ouvre chaque étape : c'est
  // elle qui porte `day_intro` en sortie du composeur.
  for (const jour of jours) {
    if (jour["day_intro"]) {
      etapeCourante += 1;
      const premiere = etapes[etapeCourante]?.premiere ?? {};
      for (const champ of CHAMPS_DU_BANDEAU) {
        if (premiere[champ] !== undefined) jour[champ] = premiere[champ];
      }
    }
    sortie.push(jour);
  }
  return sortie;
}
