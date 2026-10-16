#!/usr/bin/env tsx
/**
 * Fabrique l'inspecteur de mise en page : une page HTML autonome qui affiche
 * le carnet rendu et nomme chaque élément au survol.
 *
 * Le but est de rendre les demandes de retouche précises. Plutôt que « le
 * bloc avec la pince est trop haut », l'inspecteur donne le nom du composant,
 * son sélecteur, les champs JSON qui l'alimentent et les variables CSS en jeu.
 *
 *   npm run inspector             le carnet d'exemple (samples/showcase.json)
 *   npm run inspector:catalogue   une variante de layout par page (samples/layouts.json)
 *
 * Tout est inliné (polices en base64, images en data URI) : la page doit
 * fonctionner sans réseau, y compris publiée en artefact.
 */
import { existsSync, readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { TEMPLATE_DIR, loadTemplateCss } from "../src/lib/templates.js";
import {
  COLLECTEUR_SOURCE,
  RATIO_TOLERANCE,
  etapesDe,
  getPhotoRatio,
  layoutDe,
  photosRequired,
} from "../src/services/photoRatio.js";
import { renderBookPdf, renderTemplateToHtml, type RenderProfile } from "../src/services/bookPdf.js";
import type { Browser } from "playwright-core";

const OFFLINE_DIR = resolve(import.meta.dirname, "../test/fixtures/offline");

// ---------------------------------------------------------------------------
// Dictionnaire d'annotation
// ---------------------------------------------------------------------------

interface Part {
  /** Nom lisible, celui qu'on emploie en parlant du carnet. */
  name: string;
  /** Ce que l'élément fait, en une phrase. */
  role: string;
  /** Champs du payload qui l'alimentent. */
  fields?: string[];
  /** Variables CSS qui le pilotent. */
  vars?: string[];
  /** Famille, pour le regroupement et la couleur de la pastille. */
  kind: "page" | "structure" | "composant" | "decor";
}

/**
 * Indexé par classe CSS. L'annotation vit ici plutôt que dans `index.html` :
 * le gabarit part chez APITemplate tel quel, il n'a pas à porter les
 * métadonnées d'un outil de travail.
 */
const PARTS: Record<string, Part> = {
  // --- Pages ---------------------------------------------------------------
  "page--cover": { kind: "page", name: "Couverture", role: "Photo pleine page, titre et signature. Ni teinte ni grain : la photo occupe tout.", fields: ["book_title", "book_subtitle", "authors", "date_range", "cover_photo"] },
  "page--colophon": { kind: "page", name: "Page de garde", role: "La page « Tout commence… par une feuille blanche », avec les mentions d'édition.", fields: ["brand_name", "year", "authors"] },
  "page--intro": { kind: "page", name: "Page d'introduction", role: "Récit d'ouverture manuscrit, précédé de deux photos scotchées. N'apparaît que si intro_text est fourni.", fields: ["intro_title", "intro_text", "intro_photos"] },
  "page--day": { kind: "page", name: "Page de journée", role: "Une entrée de days[] = une page. Le layout est choisi par les drapeaux layout_*.", fields: ["days[]"] },
  "page--back": { kind: "page", name: "Quatrième de couverture", role: "Photo pleine page et mot de fin.", fields: ["back_cover"] },

  // --- Structure -----------------------------------------------------------
  "page__content": { kind: "structure", name: "Zone de contenu", role: "Colonne flex à 30 pt de marge. Tout ce qui doit rester dans les marges d'impression vit ici.", vars: ["--mb-margin"] },
  "page__decor": { kind: "structure", name: "Calque décor", role: "Sous le contenu. Ce qui déborde volontairement des marges : tracés, stickers.", },
  "mb-split": { kind: "structure", name: "Bloc scindé", role: "Carte info d'un côté, récit de l'autre. Ne se comprime jamais : c'est la bande de photos qui cède.", },
  "mb-split__aside": { kind: "structure", name: "Colonne latérale", role: "Reçoit la carte info. Largeur fixe de 173 pt.", },
  "mb-split__main": { kind: "structure", name: "Colonne de récit", role: "Le texte manuscrit, en colonne étroite." },
  "mb-gallery": { kind: "structure", name: "Bande de photos", role: "2 ou 3 photos alignées, calées en bas de page. Se comprime si le récit est long, jamais sous 160 pt. Porte le tracé pointillé.", fields: ["day.photos"] },
  "mb-day__floats": { kind: "structure", name: "Zone flottante", role: "Bas de la page de journée : carte info à gauche, photo à droite. Absorbe la hauteur restante." },
  "mb-intro__photos": { kind: "structure", name: "Photos d'introduction", role: "Deux photos inclinées, positionnées en absolu.", fields: ["intro_photos"] },

  // --- Composants ----------------------------------------------------------
  "mb-header": { kind: "composant", name: "Bandeau de journée", role: "Ruban « jour NN », encart lieu, encart date. Ne s'affiche que si day_intro est présent. Seul (sans nuit, hôte, météo ni étiquette), il garde une ligne de réglure sous le ruban.", fields: ["day.day_intro"] },
  "mb-header--seul": { kind: "composant", name: "Bandeau seul", role: "Bandeau sans rangée dessous : une ligne de réglure le sépare du titre, pour que le récit ne colle pas au ruban.", fields: ["day.day_intro"] },
  "mb-ribbon": { kind: "composant", name: "Ruban de journée", role: "Fanion à encoche qui dépasse du bord haut et se fait couper net par la page, comme un signet glissé dans le carnet.", fields: ["day.day_intro.day_number"] },
  "mb-ribbon__number": { kind: "composant", name: "Numéro de jour", role: "Playfair Display Black 27,6 pt, légèrement pivoté.", fields: ["day.day_intro.day_number"] },
  "mb-ribbon__label": { kind: "composant", name: "Mot « jour »", role: "Playfair Display Black 10,4 pt au-dessus du numéro." },
  "mb-field": { kind: "composant", name: "Encart lieu / date", role: "Contour unique, très légèrement pivoté. La pastille du haut l\u0027interrompt : c\u0027est elle qui coupe le trait, sans masque ni découpe.", fields: ["day.day_intro.location", "day.day_intro.date"] },
  "mb-field__label": { kind: "composant", name: "Pastille d'encart", role: "Le petit « lieu » ou « date » posé sur le bord haut. Opaque, pour interrompre le contour proprement.", vars: ["--mb-label-solid"] },
  "mb-field__value": { kind: "composant", name: "Valeur d'encart", role: "Le lieu ou la date. Trop long, il élargit le cadre au détriment de l'autre.", fields: ["day.day_intro.location", "day.day_intro.date"] },
  "mb-weather": { kind: "composant", name: "Rangée météo", role: "Cinq icônes ; celle du jour est mise en pastille, les autres restent à 30 % d'opacité. Rendue seulement quand le voyageur a dit le temps dans son vocal.", fields: ["day.day_intro.weather_key"] },
  "mb-weather__item": { kind: "composant", name: "Pastille météo", role: "État sélectionné : disque carotte plein, halo de la même teinte à 23 %, icône en blanc.", fields: ["day.day_intro.weather_key"], vars: ["--mb-carrot"] },
  "mb-weather__icon": { kind: "composant", name: "Icône météo", role: "SVG au trait, 19 pt, tiré de assets/icons/weather/ et embarqué par npm run icons:build.", fields: ["day.day_intro.weather_key"] },
  "mb-tag": { kind: "composant", name: "Étiquette de section", role: "Pastille manuscrite (« Top départ »). Trois mots maximum, sinon elle déborde de sa forme.", fields: ["day.tag"] },
  "mb-note": { kind: "composant", name: "Bloc de texte manuscrit", role: "Encre bleue sur réglure générée. Chaque paragraphe est suivi d'une ligne vide : elle montre l'emplacement resté libre dans le gabarit. Tout ce que la réglure traverse doit peser un multiple entier de --mb-line, sinon les lignes dérivent.", fields: ["day.body_html", "intro_text"], vars: ["--mb-ink", "--mb-rule", "--mb-line", "--mb-font-hand"] },
  "mb-note__title": { kind: "composant", name: "Titre manuscrit", role: "16 pt sur exactement deux interlignes, pour ne pas rompre la réglure. Devrait être en Hansley — police propriétaire encore absente, repli sur Gloria Hallelujah.", fields: ["day.title", "intro_title"], vars: ["--mb-font-title"] },
  "mb-card": { kind: "composant", name: "Carte info", role: "Carte blanche pivotée de 6,5°, liseré pointillé, ombre bleutée. Seul le premier fun fact est affiché.", fields: ["day.fun_facts[0]", "day.fun_facts_title"], vars: ["--mb-card-bg", "--mb-card-shadow"] },
  "mb-card__title": { kind: "composant", name: "Bandeau de carte", role: "Fond menthe, contour plein puis liseré pointillé interne, pivoté de −1°.", fields: ["day.fun_facts_title"], vars: ["--mb-mint"] },
  "mb-card__body": { kind: "composant", name: "Texte de carte", role: "Playfair Display 12 pt. 140 caractères maximum, refusés au-delà par le validateur.", fields: ["day.fun_facts[0]"] },
  "mb-card__clip": { kind: "composant", name: "Pince", role: "Pince métallique posée sur le bord haut de la carte. SVG dessiné, pas une image." },
  "mb-photo": { kind: "composant", name: "Photo scotchée", role: "Contour noir tracé à la main, tourné de 2° par rapport à la photo, rotation légère, scotch. Recadrage en object-fit: cover, centré sur focus, jamais plus d'un tiers de l'image perdu.", fields: ["day.photos[]"] },
  "mb-photowall--colonnes": { kind: "composant", name: "Planche en colonnes", role: "Cinq photos en deux colonnes décalées, sans inclinaison : deux portraits à gauche, trois tirages à droite. Alterne avec la planche en rangées.", fields: ["day.planche_colonnes"] },
  "mb-photo--contain": { kind: "composant", name: "Photo réduite, non rognée", role: "Photo de groupe, ou rognage au-delà d'un tiers : réduite entière, contour dessiné ajusté à l'image (`tirage`), sans scotch.", fields: ["day.photos[].fit"] },
  "mb-hero": { kind: "composant", name: "Photo héro", role: "Grande photo en tête de page, layout hero_top.", fields: ["day.photos[0]"] },

  // --- Couverture et dos ---------------------------------------------------
  "mb-cover__photo": { kind: "composant", name: "Photo de couverture", role: "Pleine page, sous le titre.", fields: ["cover_photo"] },
  "mb-cover__title": { kind: "composant", name: "Titre du carnet", role: "Playfair Display Black 64 pt. Rétrécit si le titre est long, au lieu de déborder.", fields: ["book_title"] },
  "mb-cover__subtitle": { kind: "composant", name: "Sous-titre", role: "Bandeau blanc incliné sous le titre.", fields: ["book_subtitle"] },
  "mb-cover__byline": { kind: "composant", name: "Signature", role: "Auteurs et période, en bas de couverture.", fields: ["authors", "date_range"] },
  "mb-colophon__credits": { kind: "composant", name: "Mentions d'édition", role: "Marque, année, auteurs.", fields: ["brand_name", "year", "authors"] },
  "mb-back__text": { kind: "composant", name: "Mot de fin", role: "Texte de clôture sur la photo de dos.", fields: ["back_cover.closing_text"] },
  "mb-back__footer": { kind: "composant", name: "Pied de dos", role: "Sous-texte et appel à l'action.", fields: ["back_cover.closing_subtext", "back_cover.cta"] },
  "mb-back__photo": { kind: "composant", name: "Photo de dos", role: "Pleine page.", fields: ["back_cover.image"] },

  "mb-chapter": { kind: "structure", name: "Ouverture de chapitre", role: "Récit et carte info à gauche, carte de la région à droite. Le layout qui ouvre un chapitre.", fields: ["day.layout_chapter_map"] },
  "mb-chapter__map": { kind: "composant", name: "Carte de chapitre", role: "SVG projeté en Mercator depuis Natural Earth : le contour et les épingles passent par la même transformation, ils ne peuvent pas diverger. 175 pays.", fields: ["day.map.regions", "day.map.points"] },
  "mb-photo__tape": { kind: "composant", name: "Scotch", role: "Posé sur le coin le plus vide de l'image, choisi par l'analyse de détail — au hasard, il finirait un jour sur un visage.", fields: ["day.photos[].tape_corner"] },

  // --- Pages de photos, trios, blocs à remplir -----------------------------
  "page--photos": { kind: "page", name: "Page de photos", role: "Ni récit, ni légende : l'image prend le pas sur le texte. Toujours en fin d'étape, après le récit.", fields: ["day.layout_photo_page"] },
  "page--photos-intro": { kind: "page", name: "Planche d'ouverture", role: "La planche qui ouvre une étape à 100 % de photos : elle garde le bandeau et la carte fun fact, sinon l'étape ne se lit plus comme une étape.", fields: ["day.layout_photo_wall_intro"] },
  "page--libre": { kind: "page", name: "Page libre", role: "La réglure seule, pour écrire à la main. Trois pages en fin de carnet au réglage « Zones libres », et une avant la première étape quand il faut la ramener à gauche.", fields: ["pages_libres", "pages_libres_avant"] },
  "mb-photowall": { kind: "structure", name: "Planche de photos", role: "Trois à cinq photos bord à bord, en rangées. L'habillage reste : cadre blanc, scotch, inclinaison — moins marquée (±1,2°).", fields: ["day.photos"] },
  "mb-photowall--libre": { kind: "structure", name: "Page d'album", role: "Une ou deux photos seulement : les tirages inclinés et le tracé pointillé entre eux, la place des stickers.", fields: ["day.photos"] },
  "mb-photowall__header": { kind: "structure", name: "Bandeau de planche", role: "Le bandeau jour · lieu · date posé en tête de la planche d'ouverture." },
  "mb-pleine-page": { kind: "structure", name: "Photo pleine page", role: "Bord à bord, sans cadre ni inclinaison ni décor. Une par chapitre au plus, sur une photo notée 9 qui se rogne de moins d'un tiers.", fields: ["day.pleine_page"] },
  "mb-trio": { kind: "structure", name: "Trio de photos", role: "Une photo en haut, deux en bas qui la chevauchent à peine. Pages de suite seulement : sous un bandeau, les trois n'auraient plus leur hauteur.", fields: ["day.photos"] },
  "mb-note--contourne": { kind: "composant", name: "Récit qui contourne", role: "Quelques lignes pleine largeur, puis la colonne de texte à gauche de la grande photo qui flotte à droite. La cale, un flottant sans largeur, la fait commencer plus bas.", fields: ["day.body_html"] },
  "mb-note--remplit": { kind: "composant", name: "Récit qui remplit", role: "La réglure descend jusqu'au bas du bloc : la page n'a pas de trou entre le récit et ce qui suit." },
  "mb-note--libre": { kind: "composant", name: "Réglure vierge", role: "La réglure d'une page libre, sans texte." },
  "mb-card--postit": { kind: "composant", name: "Post-it « Infos »", role: "Le fun fact de la page qui contourne une photo, posé en bas à gauche dans le blanc que la colonne laisse.", fields: ["day.fun_facts[0]"] },
  "mb-card--planche": { kind: "composant", name: "Carte de planche", role: "La carte posée sur la planche d'ouverture : c'est elle qui absorbe le résidu d'une étape à 100 %.", fields: ["day.fun_facts[0]"] },
  "mb-photo__label": { kind: "composant", name: "Étiquette de titre", role: "Le titre écrit sur la photo. Une par double page au plus, sur la photo la mieux notée ; 30 signes.", fields: ["day.photos[].label"] },
  "mb-prompt": { kind: "composant", name: "Bloc à remplir", role: "Trois lignes à écrire à la main. Remplace la zone flottante du bas : empilés, les deux feraient déborder la page. Un seul bloc interactif par page.", fields: ["day.prompt.label"] },
  "mb-quiz": { kind: "composant", name: "Quiz", role: "Petit jeu, réponse imprimée à l'envers. Comme le bloc à remplir, il occupe le bas de la page et s'exclut de lui.", fields: ["day.quiz"] },
  "mb-stay": { kind: "composant", name: "Rangée nuit / hôte", role: "Le gîte et les hôtes, sous le bandeau. Ils passent avant la météo : ce sont eux qui rattachent un souvenir à un lieu, des années après.", fields: ["day.day_intro.stay", "day.day_intro.host"] },
  "mb-ai-note": { kind: "composant", name: "Mention « généré par IA »", role: "En petit, en bas de page, dès qu'un élément vient de la machine. Dite sans s'en excuser.", fields: ["day.ai_note"] },
  "mb-sticker": { kind: "decor", name: "Sticker", role: "Un dessin de la bibliothèque, posé quand un de ses mots apparaît en mot entier dans le récit. Deux par double page au plus, jamais deux fois la même famille.", fields: ["day.stickers[]"] },

  // --- Décor ---------------------------------------------------------------
  "mb-path": { kind: "decor", name: "Tracé du voyage", role: "Pointillé carotte, dessiné dans la bande de photos et jamais derrière du texte. Quatre variantes tirées selon le rang de la page, et une page sur cinq n'en porte aucune : un motif identique partout se lit comme une trame.", fields: ["day.trace"] },
};

// ---------------------------------------------------------------------------
// Fiches des layouts
// ---------------------------------------------------------------------------

interface LayoutFiche {
  /** Nom de la composition, celui qu'on emploie en parlant d'une page. */
  name: string;
  /** Ce que la page montre, en une phrase. */
  rendu: string;
  /** Le critère de choix, tel que le catalogue de LAYOUT_KB le formule. */
  quand: string;
  /** Nombre de photos que le layout consomme. */
  photos: string;
  /** Plafond du récit, en caractères : page à bandeau / page de suite. */
  plafond: string;
  /** Tailles du barème S / M / L / XL que la configuration accepte. */
  tailles: string;
}

/**
 * Une fiche par drapeau `layout_*`, recopiée du § « Catalogue des layouts » de
 * `LAYOUT_KB.md` et de la table des plafonds mesurés.
 *
 * Elle vit ici, à côté du dictionnaire des composants, pour la même raison :
 * le gabarit part chez APITemplate tel quel. Les plafonds, eux, ne se
 * devinent pas — ils sortent de `calibrate-lengths.ts`, et `LAYOUT_CAPACITY`
 * (`payloadValidator.ts`) est la source dont ces lignes sont le résumé lisible.
 */
const LAYOUTS: Record<string, LayoutFiche> = {
  layout_chapter_map: {
    name: "Ouverture de chapitre",
    rendu: "Carte de la région à droite, récit et carte info à gauche, photos en bas.",
    quand: "Ouverture d'un chapitre, et seulement si le récit nomme un lieu cartographiable : la carte exige un code ISO et des coordonnées justes.",
    photos: "0 à 2",
    plafond: "500 sans photo, 300 avec deux photos, 110 avec deux photos et un fun fact (830 en page de suite)",
    tailles: "sous S à M, selon la carte info et les photos",
  },
  layout_hero_top: {
    name: "Grande photo en tête",
    rendu: "Grande photo en tête de page, récit dessous.",
    quand: "Une photo iconique porte la journée.",
    photos: "1",
    plafond: "380 (660 en page de suite)",
    tailles: "sous S, S",
  },
  layout_split_left: {
    name: "Carte info à gauche",
    rendu: "Carte info à gauche, récit en colonne à droite, puis deux photos en bas.",
    quand: "Un fait à mettre en avant et deux belles images.",
    photos: "2",
    plafond: "230 avec le fun fact, 540 sans (860 en page de suite)",
    tailles: "S, M — S seulement avec un fun fact",
  },
  layout_collage: {
    name: "Bande de photos",
    rendu: "Récit pleine largeur, puis 2 ou 3 photos inclinées en bas.",
    quand: "Journée dense visuellement.",
    photos: "2 à 3",
    plafond: "540 (860 en page de suite)",
    tailles: "S, M",
  },
  layout_trio_portrait: {
    name: "Trio portrait",
    rendu: "Récit court, réglure prolongée, puis trois portraits en cascade et le tracé derrière.",
    quand: "Fin d'étape courte avec trois photos en portrait. Page de suite seulement — le validateur refuse un trio sous un bandeau.",
    photos: "3",
    plafond: "410, et 2 paragraphes au plus",
    tailles: "sous S, S partiel",
  },
  layout_trio_landscape: {
    name: "Trio paysage",
    rendu: "Le même trio, avec une photo paysage en haut ; les deux du bas restent des portraits.",
    quand: "Fin d'étape courte avec une paysage et deux portraits. Entre les deux trios, celui qui rogne le moins.",
    photos: "3",
    plafond: "410, et 2 paragraphes au plus",
    tailles: "sous S, S partiel",
  },
  layout_recit_photo: {
    name: "Récit qui contourne la photo",
    rendu: "Quelques lignes pleine largeur, puis le récit en colonne à gauche d'une grande photo en hauteur, inclinée, avec son étiquette de titre.",
    quand: "Une page à une photo en portrait (format sous 0,77), en ouverture comme en suite. Un fun fact y devient un post-it « Infos ».",
    photos: "1",
    plafond: "560 (880 en page de suite, 800 avec le post-it)",
    tailles: "S, M",
  },
  layout_photo_page: {
    name: "Page de photos",
    rendu: "De 3 à 5 photos, une planche bord à bord ; 1 ou 2, une page d'album ; avec pleine_page, une seule photo bord à bord sans cadre.",
    quand: "Toujours en fin d'étape, après le récit. Une double page de photos au plus par étape.",
    photos: "1 à 5",
    plafond: "aucun — le récit n'est pas rendu",
    tailles: "—",
  },
  layout_photo_wall_intro: {
    name: "Planche d'ouverture",
    rendu: "Bandeau en tête, photos sur le reste de la feuille, carte fun fact.",
    quand: "Première page d'une étape à 100 % de photos. Le récit sert de matière au fun fact, il n'est pas imprimé.",
    photos: "1 à 4",
    plafond: "aucun — le récit n'est pas rendu",
    tailles: "—",
  },
  layout_story_full: {
    name: "Récit pleine page",
    rendu: "Récit pleine page, réglure jusqu'en bas, aucune photo.",
    quand: "Palier 0 % du ratio texte / photo. La carte fun fact reste possible : elle n'est pas une photo.",
    photos: "0",
    plafond: "1140 (1640 en page de suite), et 5 paragraphes au plus",
    tailles: "le récit occupe la feuille entière",
  },
  layout_story_opener: {
    name: "Ouverture de journée",
    rendu: "Récit, puis carte info et photo flottantes en bas de page.",
    quand: "Le cas par défaut, et le plus courant. Un prompt ou un quiz y remplace la zone flottante.",
    photos: "0 à 1",
    plafond: "540 (860 en page de suite, 740 avec un prompt)",
    tailles: "S, M",
  },
};

/** `layout_story_facts` est le même rendu : le validateur accepte les deux noms. */
LAYOUTS["layout_story_facts"] = {
  ...LAYOUTS["layout_story_opener"]!,
  name: "Journée avec fun fact",
};

// ---------------------------------------------------------------------------
// Assemblage du document
// ---------------------------------------------------------------------------

const MIME: Record<string, string> = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png" };

/** Remplace chaque URL distante par son équivalent local en data URI. */
function inlineImages(html: string): string {
  const manifestPath = resolve(OFFLINE_DIR, "manifest.json");
  if (!existsSync(manifestPath)) return html;
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as Record<string, string>;

  let out = html;
  for (const [url, file] of Object.entries(manifest)) {
    const path = resolve(OFFLINE_DIR, file);
    if (!existsSync(path)) continue;
    const ext = file.split(".").pop() ?? "png";
    const dataUri = `data:${MIME[ext] ?? "image/png"};base64,${readFileSync(path).toString("base64")}`;
    out = out.split(url).join(dataUri);
  }
  return out;
}

interface PageMeta {
  index: number;
  label: string;
  detail: string;
  /** Le layout tel qu'on le nomme dans le sélecteur : drapeau court et variante. */
  layout: string;
  /** Clé de la fiche (`layout_*`), absente sur les pages qui n'en ont pas. */
  fiche?: string;
  /** Ce qui distingue cette page des autres du même layout. */
  variante?: string;
}

/** Les valeurs du payload sont typées `unknown` : on n'affiche que les chaînes. */
function text(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function compte(value: unknown): number {
  return Array.isArray(value) ? value.length : 0;
}

/**
 * Ce qui distingue une page des autres pages du même layout.
 *
 * Un catalogue qui dirait trois fois « photo_page » sans préciser laquelle des
 * trois formes est à l'écran ne servirait à rien : c'est le nombre de photos,
 * la présence du fun fact ou du bloc à remplir qui font la variante, et ce sont
 * elles que le gabarit lit pour choisir sa branche.
 */
function varianteDe(day: Record<string, unknown>, flag: string): string {
  const photos = compte(day["photos"]);
  const funFact = compte(day["fun_facts"]) > 0;
  const suite = !day["day_intro"];
  const morceaux: string[] = [];

  if (flag === "layout_photo_page") {
    if (day["pleine_page"]) morceaux.push("pleine page, bord à bord");
    else if (photos <= 2) morceaux.push(`album, ${photos} photo${photos > 1 ? "s" : ""}`);
    else morceaux.push(`planche, ${photos} photos`);
  } else if (flag === "layout_photo_wall_intro") {
    morceaux.push(`planche, ${photos} photo${photos > 1 ? "s" : ""}`);
    if (funFact) morceaux.push("carte fun fact");
  } else {
    if (photos > 0) morceaux.push(`${photos} photo${photos > 1 ? "s" : ""}`);
    if (photos === 0 && flag !== "layout_story_full") morceaux.push("sans photo");
    if (funFact) morceaux.push(flag === "layout_recit_photo" ? "post-it Infos" : "fun fact");
    if (day["prompt"]) morceaux.push("bloc à remplir");
    if (day["quiz"]) morceaux.push("quiz");
    if (compte(day["photos"]) > 0 && (day["photos"] as Record<string, unknown>[]).some((p) => p?.["fit"] === "contain")) {
      morceaux.push("photo non rognée");
    }
  }

  const intro = day["day_intro"] as Record<string, unknown> | undefined;
  if (suite) morceaux.push("page de suite");
  else if (intro && !(intro["stay"] ?? intro["host"] ?? intro["weather_key"] ?? day["tag"])) {
    morceaux.push("bandeau seul");
  }
  if (day["ai_note"]) morceaux.push("mention IA");
  return morceaux.join(" · ");
}

/**
 * Décrit chaque page pour la navigation.
 *
 * L'ordre doit être **exactement** celui des `.page` du document : le panneau
 * mesure les pages par leur rang, et une page libre oubliée ici décalerait
 * toutes les étiquettes d'un cran.
 */
function describePages(payload: Record<string, unknown>): PageMeta[] {
  const pages: PageMeta[] = [];
  const push = (label: string, detail: string, layout: string, reste: Partial<PageMeta> = {}): void => {
    pages.push({ index: pages.length, label, detail, layout, ...reste });
  };

  if (!payload["sans_couvertures"]) push("Couverture", text(payload["book_title"]), "cover");
  push("Page de garde", "Mentions d'édition", "colophon");
  if (payload["intro_text"]) push("Introduction", text(payload["intro_title"], "Intro"), "intro");

  const libres = (cle: string): void => {
    const nombre = Number(payload[cle] ?? 0);
    for (let i = 0; i < nombre; i += 1) push("Page libre", "Réglure seule", "libre");
  };
  libres("pages_libres_avant");

  for (const day of (payload["days"] as Record<string, unknown>[] | undefined) ?? []) {
    const intro = day["day_intro"] as Record<string, unknown> | undefined;
<<<<<<< Updated upstream
    const layout = day["layout_hero_top"]
      ? "hero_top"
      : day["layout_split_left"]
        ? "split_left"
        : day["layout_collage"]
          ? "collage"
          : day["layout_trio_portrait"] || day["layout_trio_landscape"]
            ? "trio"
            : day["layout_recit_photo"]
              ? "recit_photo"
              : day["layout_recit_deux_photos"]
                ? "recit_deux_photos"
                : day["layout_photos_en_tete"]
                  ? "photos_en_tete"
                  : day["layout_recit_encart_milieu"]
                    ? "recit_encart_milieu"
                    : "story_opener";
    push(`Jour ${text(intro?.["day_number"], "—")}`, text(day["title"]), layout);
=======
    const flag = layoutDe(day);
    const variante = varianteDe(day, flag);
    push(
      intro ? `Jour ${text(intro["day_number"], "—")}` : "Suite",
      text(day["title"], LAYOUTS[flag]?.name ?? ""),
      variante ? `${flag.replace("layout_", "")} · ${variante}` : flag.replace("layout_", ""),
      { fiche: flag, variante },
    );
>>>>>>> Stashed changes
  }

  libres("pages_libres");
  if (payload["page_blanche_finale"]) push("Page blanche", "Feuillet de fin", "blanche");
  if (payload["back_cover"] && !payload["sans_couvertures"]) push("Quatrième", "Mot de fin", "back");
  return pages;
}

/**
 * Le bilan de ratio texte / photo d'une étape, pour le panneau de l'inspecteur.
 *
 * Le ratio **cible** et le nombre de photos **demandé** sortent du calcul
 * (`photosRequired`) ; le ratio **mesuré** et le nombre **placé** sont relevés
 * dans le navigateur, sur le rendu — c'est le seul moyen de savoir si le
 * gabarit a tenu la cible. `pages` dit sur combien de feuilles l'étape court,
 * et `premiere` à quelle page du carnet elle commence : c'est ce qui permet au
 * panneau de mesurer les bons `.page--day`.
 */
interface RatioMeta {
  etape: number;
  titre: string;
  premiere: number;
  pages: number;
  ratioCible: number;
  photosDemandees: number;
  depassementAssume: boolean;
  raison: string;
}

/** Un bilan par étape du carnet affiché. */
function describeRatios(payload: Record<string, unknown>): RatioMeta[] {
  const days = (payload["days"] as Record<string, unknown>[] | undefined) ?? [];
  const ratio = getPhotoRatio(null, payload);
  const bilans: RatioMeta[] = [];
  let curseur = 0;
  for (const [index, etape] of etapesDe(days).entries()) {
    const recit = etape
      .map((jour) => (typeof jour["body_html"] === "string" ? jour["body_html"] : ""))
      .join("");
    const plan = photosRequired({ body_html: recit }, ratio, "a5", {
      funFacts: etape.some((jour) => Array.isArray(jour["fun_facts"]) && jour["fun_facts"].length > 0),
      decorations: Number(payload["decoration_quota"] ?? 2) > 0,
      ouvreChapitre: Boolean(etape[0]?.["map"] ?? etape[0]?.["map_svg"]),
    });
    bilans.push({
      etape: index + 1,
      titre: text(etape[0]?.["title"], `Étape ${index + 1}`),
      premiere: curseur,
      pages: etape.length,
      ratioCible: plan.ratioCible,
      photosDemandees: plan.photos,
      depassementAssume: plan.depassementAssume,
      raison: plan.raison,
    });
    curseur += etape.length;
  }
  return bilans;
}

/**
 * Transporte le document du carnet jusqu'au navigateur.
 *
 * Le contenu d'un <script> n'est PAS décodé par le parseur HTML : y déposer du
 * HTML échappé donnerait un mur de texte au lieu d'une page. On passe donc par
 * du JSON, en échappant `<` pour qu'aucun `</script>` interne ne referme la
 * balise prématurément.
 */
const asJsonPayload = (value: string): string =>
  JSON.stringify(value).replace(/</g, "\\u003c");

/**
 * Le navigateur des deux PDF.
 *
 * Playwright ne fournit pas de Chromium pour toutes les plateformes où ce dépôt
 * se développe (macOS 12, par exemple) : à défaut du navigateur groupé, on
 * prend le Chrome du système, comme le fait déjà `test/ratioPhotos.test.ts`.
 * `CHROMIUM_PATH` permet d'en désigner un troisième. Sans aucun des trois, la
 * page se fabrique quand même, sans PDF embarqué — l'inspecteur sert d'abord à
 * regarder les pages.
 */
const CHROMES = [
  process.env["CHROMIUM_PATH"],
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].filter((chemin): chemin is string => Boolean(chemin));

async function ouvrirNavigateur(): Promise<Browser | null> {
  const { chromium } = await import("playwright-core");
  const args = [
    "--font-render-hinting=none",
    "--disable-lcd-text",
    "--disable-font-subpixel-positioning",
    "--force-color-profile=srgb",
    "--hide-scrollbars",
  ];
  try {
    return await chromium.launch({ args });
  } catch {
    const executablePath = CHROMES.find((chemin) => existsSync(chemin));
    if (!executablePath) return null;
    return chromium.launch({ args, executablePath });
  }
}

/**
 * Les deux visages de l'inspecteur.
 *
 * `carnet` montre un carnet d'exemple, celui qui sert à juger le rendu
 * d'ensemble ; `catalogue` met une variante de layout par page, dans l'ordre
 * du § « Catalogue des layouts » de LAYOUT_KB. Le bilan de ratio texte / photo
 * n'a de sens que sur le premier : le catalogue mélange exprès des
 * compositions qu'aucun réglage de ratio ne demanderait ensemble, et un tableau
 * tout en rouge ne dirait rien de juste.
 */
const VUES = {
  carnet: { sample: "showcase", sortie: "inspecteur.html", bilan: true },
  catalogue: { sample: "layouts", sortie: "inspecteur-layouts.html", bilan: false },
} as const;

/** Un PDF de profil aperçu dépasse souvent ce que le visualiseur accepte. */
const LIMITE_ARTEFACT = 15 * 1024 * 1024;

async function main(): Promise<void> {
  const vue = process.argv.includes("--catalogue") ? VUES.catalogue : VUES.carnet;
  const payload = JSON.parse(
    readFileSync(resolve(TEMPLATE_DIR, `samples/${vue.sample}.json`), "utf8"),
  ) as Record<string, unknown>;

  // Rendu unique : le profil imprimeur est obtenu en redéfinissant deux
  // variables CSS sur la scène, exactement comme le fait `body.profile-print`.
  const carnet = inlineImages(renderTemplateToHtml({ payload, profile: "preview" }));
  const body = carnet.slice(carnet.indexOf("<body"), carnet.lastIndexOf("</body>"));
  const inner = body.slice(body.indexOf(">") + 1);

  const document = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
${loadTemplateCss()}
<style>
  html, body { background: transparent; }
  body { margin: 0; padding: 0; }
  /* Profil imprimeur : mêmes deux variables que body.profile-print. */
  body.is-print { --mb-paper-tint: transparent; --mb-grain-opacity: 0; }
  .page { margin: 0 auto 28px; box-shadow: 0 10px 30px rgba(12, 16, 24, .22); }
  .page:last-child { margin-bottom: 0; }
  #mb-outline { position: absolute; z-index: 9999; pointer-events: none;
    border: 1.5px solid #f86015; background: rgba(248, 96, 21, .08);
    border-radius: 2px; display: none; }
  #mb-outline.is-pinned { border-style: dashed; background: rgba(248, 96, 21, .14); }
</style></head><body>${inner}<div id="mb-outline"></div></body></html>`;

  const pages = describePages(payload);
  const template = readFileSync(resolve(import.meta.dirname, "inspector-shell.html"), "utf8");

  // Les deux PDF voyagent avec la page. L'impression du navigateur est
  // refusée dans une iframe d'artefact : sans les fichiers embarqués, le
  // bouton d'export ne pourrait rien produire.
  const pdfs: Record<RenderProfile, string> = { print: "", preview: "" };
  const browser = await ouvrirNavigateur();
  if (!browser) {
    console.log("  aucun Chromium : page fabriquée sans PDF embarqué");
  } else {
    try {
      for (const profile of ["print", "preview"] as RenderProfile[]) {
        const { pdf } = await renderBookPdf({ payload, profile, offline: true, browser });
        pdfs[profile] = pdf.toString("base64");
        console.log(`  ${profile} : ${(pdf.length / 1048576).toFixed(1)} Mo`);
      }
    } finally {
      await browser.close();
    }
  }

  // Le visualiseur d'artefacts refuse une page de plus de 16 Mio. Le profil
  // aperçu pèse le plus lourd — Chromium rastérise le grain du papier à chaque
  // page — donc c'est lui qu'on lâche d'abord : mieux vaut un export sur deux
  // qu'une page qu'on ne peut pas publier. Le bouton le dit au lecteur.
  for (const profile of ["preview", "print"] as RenderProfile[]) {
    const poids = Object.values(pdfs).reduce((somme, base64) => somme + base64.length, 0);
    if (poids <= LIMITE_ARTEFACT || !pdfs[profile]) continue;
    pdfs[profile] = "";
    console.log(`  ${profile} : écarté, la page dépasserait la limite de 16 Mio du visualiseur`);
  }

  const html = template
    .replace("__PARTS__", JSON.stringify(PARTS))
    .replace("__LAYOUTS__", JSON.stringify(LAYOUTS))
    .replace("__PAGES__", JSON.stringify(pages))
    .replace("__RATIOS__", JSON.stringify(vue.bilan ? describeRatios(payload) : []))
    .replace("__RATIO_TOLERANCE__", String(RATIO_TOLERANCE))
    .replace("__COLLECTEUR__", COLLECTEUR_SOURCE)
    .replace("__PDFS__", asJsonPayload(JSON.stringify(pdfs)))
    .replace("__DOCUMENT__", asJsonPayload(document));

  const sortie = resolve(import.meta.dirname, "../.render-out", vue.sortie);
  await mkdir(resolve(import.meta.dirname, "../.render-out"), { recursive: true });
  await writeFile(sortie, html);
  console.log(`✓ ${sortie} — ${(Buffer.byteLength(html) / 1024).toFixed(0)} ko, ${pages.length} pages`);
}

await main().catch((error: unknown) => {
  console.error(`✗ ${(error as Error).message}`);
  process.exit(1);
});
