/**
 * Le ratio texte / photo : combien de photos une étape demande, et sur combien
 * de pages elle se compose.
 *
 * ## La règle absolue
 *
 * **Le texte validé par le voyageur ne bouge jamais.** Pas de coupe, pas de
 * reformulation, pas de troncature, pas de corps de police réduit au-delà de ce
 * que le gabarit fait déjà. C'est le nombre de pages et le nombre de photos qui
 * s'adaptent au texte — jamais l'inverse. Tout ce fichier découle de là : il
 * part de la surface que le récit occupe, et il en déduit le reste. Le texte
 * n'est lu que pour sa longueur ; `body_html` n'est jamais réécrit ici.
 *
 * ## Ce que « ratio » veut dire
 *
 * Le voyageur choisit une valeur parmi 0, 25, 50, 75, 100 % (champ
 * `photo_ratio` du carnet, `photoTextRatio` en base). C'est le **pourcentage de
 * surface occupée par les photos**, mesuré sur **l'ensemble des pages d'une
 * étape** — pas page par page, sinon une étape de deux pages n'aurait aucune
 * marge de manœuvre.
 *
 *     ratio = surface photo / (surface photo + surface texte)
 *
 * - **surface texte** : ce que `mb-note` occupe réellement, lignes × `--mb-line`
 *   × largeur de colonne ;
 * - **surface photo** : les emplacements `mb-photo` (le contour dessiné,
 *   qui déborde autour, ne compte pas) ;
 * - **exclus** : bandeau, titre, étiquette, météo, carte fun fact, carte de
 *   chapitre, décor. Ce sont des éléments fixes : les compter ferait varier le
 *   ratio sans qu'aucun réglage du voyageur n'ait changé.
 *
 * Tolérance : ±5 points (`RATIO_TOLERANCE`).
 *
 * ## Pourquoi un calcul, et pas une mesure
 *
 * L'étape est mesurée **par le rendu réel** pour la vérification
 * (`mesurerRatio`, appliqué au DOM par l'atelier, l'inspecteur et les tests
 * Chromium), mais le **nombre de photos** doit sortir d'une fonction pure : le
 * chat de l'app la rappelle juste après que le voyageur a raconté son étape,
 * côté serveur, sans navigateur. D'où deux étages :
 *
 * 1. `photosRequired` — pure, déterministe, sans DOM, à partir des métriques de
 *    police et de gabarit précalculées ci-dessous (`A5`, `GABARITS`). Même JSON
 *    et même ratio donnent toujours le même résultat, donc le même PDF ;
 * 2. `mesurerRatio` — la vérification, sur le rendu. Elle ne décide rien : elle
 *    dit si le gabarit a tenu la cible, et l'inspecteur l'affiche.
 *
 * Les métriques viennent de `backend/scripts/calibrate-lengths.ts` et du CSS du
 * gabarit. **Elles ne se devinent pas** : les redériver, c'est relancer le
 * script, pas rouvrir la table.
 *
 * ## Une seule vérité, deux copies
 *
 * Ce fichier est la **source primaire**. `MemoBook Generator/public/ratio-photos.js`
 * en est la recopie pour l'atelier — qui est publié seul sur GitHub Pages et ne
 * peut donc rien importer d'ici. `backend/test/ratioPhotosAtelier.test.ts` les
 * garde identiques : tables comparées champ par champ, et `photosRequired`
 * confronté sur toute la matrice longueurs × ratios. Un écart y est une erreur
 * de test, pas une divergence qu'on découvre dans un PDF.
 *
 * Même mécanisme que `mapSvg.ts` ↔ `public/carte.js`.
 */

/** Les cinq valeurs du réglage. Rien d'autre n'est accepté. */
export const PHOTO_RATIOS = [0, 25, 50, 75, 100] as const;
export type PhotoRatio = (typeof PHOTO_RATIOS)[number];

/** Tolérance autour de la cible, en points de pourcentage. */
export const RATIO_TOLERANCE = 5;

/** Le ratio par défaut, celui de l'app et de l'atelier. */
export const RATIO_DEFAUT: PhotoRatio = 50;

// ---------------------------------------------------------------------------
// Métriques du format
// ---------------------------------------------------------------------------

/**
 * La géométrie d'un format de carnet, en points (1 unité Figma = 1 pt).
 *
 * `signesParLigne` est la seule valeur qui vienne d'une police plutôt que d'une
 * boîte : 57 signes sur 349 pt en Gloria Hallelujah 12 pt, 23 dans la colonne
 * étroite que laisse la carte info. Relevés au rendu
 * (LAYOUT_KB § « Longueur des textes »), pas calculés sur une largeur moyenne
 * de glyphe — une manuscrite n'en a pas d'utile.
 *
 * ⚠️ Recalibré le 12/10/2026 avec les **marges de reliure** : 15 mm côté pli,
 * 10 mm à l'extérieur. La colonne passe de 360 à 349 pt et chaque page perd
 * environ 3 % de signes — `LAYOUT_CAPACITY` a bougé d'autant, et les deux
 * tables doivent rester d'accord.
 */
export interface Format {
  nom: string;
  /** Feuille entière. */
  largeur: number;
  hauteur: number;
  /** Marge de contenu. */
  marge: number;
  /** Pas de la réglure, `--mb-line`. */
  ligne: number;
  /** Largeur des deux colonnes de récit. */
  colonnes: { pleine: number; etroite: number };
  /** Signes par ligne dans chacune. */
  signesParLigne: { pleine: number; etroite: number };
  /** Hauteur du bandeau de journée, ruban compris (élément fixe). */
  bandeau: number;
  /** Le titre manuscrit pèse exactement deux interlignes. */
  titre: number;
  /** Encombrement de la carte fun fact, 148 pt de large pivotée (élément fixe). */
  encart: number;
  /** Écart entre deux photos d'une bande. */
  gapGalerie: number;
  /** Marge intérieure d'une page pleine de photos. */
  margeGaleriePleine: number;
  /** Écart entre deux photos d'une page pleine. */
  gapGaleriePleine: number;
}

/** A5, le seul format du carnet aujourd'hui. */
export const A5: Format = {
  nom: "a5",
  largeur: 420,
  hauteur: 595,
  marge: 30,
  ligne: 15.6,
  colonnes: { pleine: 349.2, etroite: 166.2 },
  signesParLigne: { pleine: 57, etroite: 23 },
  bandeau: 88,
  titre: 31.2,
  encart: 148 * 86,
  gapGalerie: 14,
  margeGaleriePleine: 14,
  gapGaleriePleine: 11,
};

export const FORMATS: Readonly<Record<string, Format>> = { a5: A5 };

/** La surface qu'une page offre au contenu, marges retirées. */
export function surfaceUtile(f: Format = A5): number {
  return (f.largeur - 2 * f.marge) * (f.hauteur - 2 * f.marge);
}

// ---------------------------------------------------------------------------
// La table de configuration des gabarits
// ---------------------------------------------------------------------------

/**
 * Ce que chaque layout sait faire, déclaré **une fois ici** plutôt que codé
 * dans chaque gabarit.
 *
 * C'est la condition pour tenir dans dix mille carnets et pour qu'un gabarit
 * ajouté plus tard n'oblige pas à relire l'algorithme : ajouter une mise en
 * page, c'est ajouter une ligne à cette table et son nom dans `PREFERENCES`.
 * **L'algorithme ne nomme aucun layout en dur**, à une exception près et elle
 * est délibérée : `layout_story_full`, le repli qui tient n'importe quel texte,
 * employé quand aucun candidat ne le tient — le texte ne tombe jamais sur une
 * page sans place prévue.
 *
 * - `colonne` : la largeur de récit employée. `etroite` quand une carte info ou
 *   une carte de chapitre occupe les 173 pt de gauche — la colonne tombe alors
 *   à 24 signes par ligne, et c'est le seul piège du barème ;
 * - `photos` : les emplacements prévus, min et max. En dehors de ces bornes, le
 *   layout n'est pas candidat ;
 * - `bande` : la hauteur de la bande de photos, telle que le CSS la dessine, et
 *   ses bornes. **C'est le seul réglage continu du système** : c'est lui qui
 *   permet d'atterrir dans la tolérance sans toucher au texte ni au nombre de
 *   photos. Les planchers viennent du CSS (`mb-gallery` jamais sous 160 pt) ;
 * - `surfacePhotos(n, hauteur, f)` : la surface des emplacements de photos ;
 * - `capacite` / `capaciteAvecEncart` : les plafonds de texte mesurés
 *   (`LAYOUT_CAPACITY`, `payloadValidator.ts`), **à la hauteur de bande de
 *   conception**. `bandeau` pour la première page d'une étape, `suite` pour les
 *   suivantes ; 0 = le layout ne porte pas de récit. Une bande plus haute retire
 *   du texte, et c'est `plafondBande` qui en tient le compte.
 */
export interface Gabarit {
  colonne: "pleine" | "etroite" | "aucune";
  photos: { min: number; max: number };
  /**
   * La page tient-elle debout sans récit pour la remplir ? Vrai quand une
   * grande image, une carte ou une planche porte la page à elle seule. C'est ce
   * qui sauve un souvenir de trois lignes : sous le minimum de la taille S, le
   * validateur refuse un layout de récit dès qu'une photo était disponible
   * (LAYOUT_KB § « Les deux bornes basses »).
   */
  porteParImage?: boolean;
  bande: { hauteur: number; min: number; max: number };
  surfacePhotos: (n: number, hauteur: number, f: Format) => number;
  capacite: { bandeau: number; suite: number };
  capaciteAvecEncart?: { bandeau: number; suite: number };
  /** Les trios ne s'emploient jamais sur la première page d'une étape. */
  suiteSeulement?: boolean;
  /** Le layout porte le bandeau jour · lieu · date. */
  bandeau: boolean;
  /** Une place est prévue pour la carte fun fact. */
  encart: boolean;
}

/** Bande de photos alignées : largeur utile moins les écarts, par la hauteur. */
function galerie(n: number, hauteur: number, f: Format): number {
  if (n <= 0) return 0;
  return (f.colonnes.pleine - f.gapGalerie * (n - 1)) * hauteur;
}

/**
 * Ouverture de chapitre : une photo seule se pose au-dessus de la carte, à
 * taille fixe (136 × 196 pt, `.mb-photo--chapitre`) ; deux photos forment la
 * bande du bas, comme une galerie.
 */
function chapitre(n: number, hauteur: number, f: Format): number {
  return n === 1 ? 136 * 196 : galerie(n, hauteur, f);
}

/**
 * Trio (maquettes du 15/10/2026) : trois emplacements de taille fixe, en
 * points (`style.css`, `.mb-photo--trio-*`) — la grande photo à côté du récit,
 * puis les deux du bas.
 */
function trio(emplacements: readonly (readonly [number, number])[]) {
  return (n: number): number => emplacements.slice(0, n).reduce((somme, [l, h]) => somme + l * h, 0);
}

/**
 * Photo flottante du bas de page : un cadre unique, qui grandit dans les deux
 * dimensions à la fois — c'est une photo, pas une bande. `hauteur` pilote donc
 * aussi sa largeur, à format constant.
 */
function flottante(n: number, hauteur: number): number {
  if (n <= 0) return 0;
  return (165 / 162) * hauteur * hauteur;
}

/**
 * Page pleine de photos : les cadres couvrent la feuille entière, marges
 * d'impression comprises — c'est une page à fond perdu, pas une page de récit.
 * `hauteur` est celle de la zone disponible ; les écarts entre cadres en sont
 * retirés.
 */
function galeriePleine(n: number, hauteur: number, f: Format): number {
  if (n <= 0) return 0;
  const largeur = f.largeur - 2 * f.margeGaleriePleine;
  const rangees = n >= 5 ? 3 : n >= 3 ? 2 : 1;
  const hauteurPhotos = hauteur - f.gapGaleriePleine * (rangees - 1);
  const ecartsHorizontaux = Math.max(0, n - rangees);
  return (
    largeur * hauteurPhotos -
    ecartsHorizontaux * f.gapGaleriePleine * (hauteurPhotos / rangees)
  );
}

/** Hauteur disponible sur une page pleine de photos, bandeau éventuel retiré. */
const HAUTEUR_PLANCHE = A5.hauteur - 2 * A5.margeGaleriePleine;
const HAUTEUR_PLANCHE_BANDEAU = HAUTEUR_PLANCHE - A5.bandeau;

export const GABARITS: Readonly<Record<string, Gabarit>> = {
  /* --- Layouts de récit, 0 ou 1 photo ------------------------------------- */

  // Récit, puis carte info et photo flottantes en bas de page. Le cas le plus
  // courant, et celui qui porte le palier 25 % : la photo flottante occupe
  // 28 % de la surface mesurée d'une page pleine de texte.
  layout_story_opener: {
    colonne: "pleine",
    photos: { min: 0, max: 1 },
    // 162 pt de conception ; elle peut grandir jusqu'à remplir la zone
    // flottante (175 pt de haut, 360 de large), ce qui est exactement le repli
    // du « texte court à ratio bas ».
    bande: { hauteur: 162, min: 140, max: 215 },
    surfacePhotos: flottante,
    capacite: { bandeau: 540, suite: 860 },
    bandeau: true,
    encart: true,
  },
  layout_story_facts: {
    colonne: "pleine",
    photos: { min: 0, max: 1 },
    bande: { hauteur: 162, min: 140, max: 215 },
    surfacePhotos: flottante,
    capacite: { bandeau: 540, suite: 860 },
    bandeau: true,
    encart: true,
  },

  // Grande photo en tête, récit dessous : la moitié de la page en image.
  layout_hero_top: {
    colonne: "pleine",
    porteParImage: true,
    photos: { min: 1, max: 1 },
    // 200 pt au plancher (en deçà ce n'est plus une héro), 330 au plafond (au
    // delà le récit n'a plus ses deux paragraphes).
    bande: { hauteur: 268, min: 200, max: 330 },
    surfacePhotos: galerie,
    capacite: { bandeau: 380, suite: 660 },
    bandeau: true,
    encart: false,
  },

  /* --- Layouts de récit à bande de photos --------------------------------- */

  // Carte info à gauche, récit en colonne étroite, deux photos en bas.
  layout_split_left: {
    colonne: "etroite",
    photos: { min: 2, max: 2 },
    bande: { hauteur: 206, min: 160, max: 260 },
    surfacePhotos: galerie,
    capacite: { bandeau: 540, suite: 860 },
    // La carte info retire une taille : la colonne tombe à 23 signes la ligne.
    capaciteAvecEncart: { bandeau: 230, suite: 540 },
    bandeau: true,
    encart: true,
  },

  // Récit pleine largeur, puis 2 ou 3 photos inclinées en bas. Le palier 50 % :
  // 52 % mesurés sur une page de 560 signes.
  layout_collage: {
    colonne: "pleine",
    photos: { min: 2, max: 3 },
    bande: { hauteur: 206, min: 160, max: 260 },
    surfacePhotos: galerie,
    capacite: { bandeau: 540, suite: 860 },
    bandeau: true,
    encart: false,
  },

  // Le récit en colonne à côté d'une grande photo, deux photos dessous. Page
  // de suite seulement : la première page porte le bandeau, et les photos
  // n'auraient plus leur hauteur.
  layout_trio_portrait: {
    colonne: "pleine",
    photos: { min: 3, max: 3 },
    bande: { hauteur: 360, min: 360, max: 360 },
    surfacePhotos: trio([
      [146, 250],
      [145, 194],
      [136, 182],
    ]),
    capacite: { bandeau: 0, suite: 450 },
    suiteSeulement: true,
    bandeau: false,
    encart: false,
  },
  layout_trio_landscape: {
    colonne: "pleine",
    photos: { min: 3, max: 3 },
    bande: { hauteur: 360, min: 360, max: 360 },
    surfacePhotos: trio([
      [146, 250],
      [128, 172],
      [196, 138],
    ]),
    capacite: { bandeau: 0, suite: 450 },
    suiteSeulement: true,
    bandeau: false,
    encart: false,
  },

  // Ouverture de chapitre : carte de la région à droite, récit en colonne
  // étroite ; une photo au-dessus de la carte, ou deux en bas. La carte est un
  // élément fixe, hors du ratio.
  layout_chapter_map: {
    colonne: "etroite",
    porteParImage: true,
    photos: { min: 0, max: 2 },
    bande: { hauteur: 206, min: 160, max: 206 },
    surfacePhotos: chapitre,
    capacite: { bandeau: 500, suite: 830 },
    capaciteAvecEncart: { bandeau: 110, suite: 300 },
    bandeau: true,
    encart: true,
  },

  /* --- Pages sans récit --------------------------------------------------- */

  // Page pleine de photos : ni récit, ni bandeau. La respiration visuelle du
  // carnet, et la seule façon de dépasser 60 % sur une étape dont le texte
  // remplit ses pages.
  layout_photo_page: {
    colonne: "aucune",
    porteParImage: true,
    photos: { min: 3, max: 5 },
    bande: { hauteur: HAUTEUR_PLANCHE, min: HAUTEUR_PLANCHE, max: HAUTEUR_PLANCHE },
    surfacePhotos: galeriePleine,
    capacite: { bandeau: 0, suite: 0 },
    bandeau: false,
    encart: false,
  },

  // La même, mais elle ouvre l'étape : elle garde le bandeau jour · lieu · date
  // et, si le carnet a ses fun facts allumés, la carte. C'est la première page
  // d'une étape à 100 % — à 100 %, aucun `mb-note` n'est émis, mais une étape
  // sans bandeau ne se lit plus comme une étape.
  layout_photo_wall_intro: {
    colonne: "aucune",
    porteParImage: true,
    photos: { min: 2, max: 4 },
    bande: {
      hauteur: HAUTEUR_PLANCHE_BANDEAU,
      min: HAUTEUR_PLANCHE_BANDEAU,
      max: HAUTEUR_PLANCHE_BANDEAU,
    },
    surfacePhotos: galeriePleine,
    capacite: { bandeau: 0, suite: 0 },
    bandeau: true,
    encart: true,
  },

  // Étape à 0 % : le récit prend toute la page, la réglure descend jusqu'en
  // bas. Pas de zone flottante, donc une capacité bien supérieure à 560 — c'est
  // la seule configuration où `mb-note` occupe la feuille entière.
  layout_story_full: {
    colonne: "pleine",
    photos: { min: 0, max: 0 },
    bande: { hauteur: 0, min: 0, max: 0 },
    surfacePhotos: () => 0,
    // 535 pt de hauteur utile, 34 lignes de 57 signes, moins le bandeau et le
    // titre sur la première page et les lignes vides entre paragraphes.
    capacite: { bandeau: 1140, suite: 1640 },
    bandeau: true,
    encart: true,
  },
};

/**
 * Le minimum de photos par étape, par ratio. **Il gagne sur le ratio** : une
 * étape de trois lignes à 25 % aura sa photo, et le dépassement de tolérance
 * est assumé plutôt que de laisser une page aux trois quarts vide.
 *
 * À 100 %, il n'y a pas de minimum fixe : le nombre se déduit du nombre de
 * pages, lui-même donné par le texte (voir `planCentPourCent`).
 *
 * ⚠️ Ce n'est pas le seul plancher. Un palier demande toujours **au moins
 * autant de photos que le palier d'en dessous** (`plancherDePhotos`) : le
 * réglage doit se lire comme un curseur. Sans cette règle, un récit long sortait
 * à 6 photos à 50 % (trois bandes de deux) et à 4 à 75 % (quatre grandes
 * héros) : la surface photo augmentait bien, mais le chat demandait moins de
 * photos pour un réglage plus visuel, ce qui ne s'explique pas au voyageur.
 */
export const MINIMUM_PHOTOS: Readonly<Record<PhotoRatio, number | null>> = {
  0: 0,
  25: 1,
  50: 2,
  75: 3,
  100: null,
};

/**
 * Les layouts candidats, par ratio, **dans l'ordre de préférence**.
 *
 * C'est ici que se règle le caractère de chaque palier, pas dans l'algorithme :
 *
 * - **0 %** : aucune photo. Le récit occupe la feuille (`layout_story_full`), et
 *   une ouverture de chapitre garde sa carte, qui n'est pas une photo ;
 * - **25 %** : le récit tient la page, chaque page garde sa photo flottante
 *   (28 % de la surface mesurée) ; un collage si le compte le demande encore ;
 * - **50 %** : l'équilibre, et ce que le carnet fait déjà — la bande de deux ou
 *   trois photos (52 % mesurés) ;
 * - **75 %** : la photo passe devant. L'héro (68 %), le collage à bande haussée,
 *   les trios, et une planche pleine pour absorber le reliquat ;
 * - **100 %** : des planches, et rien d'autre. La première porte le bandeau.
 */
export const PREFERENCES: Readonly<Record<PhotoRatio, readonly string[]>> = {
  0: ["layout_story_full", "layout_chapter_map"],
  25: ["layout_story_opener", "layout_story_facts", "layout_collage"],
  50: [
    "layout_collage",
    "layout_split_left",
    "layout_hero_top",
    "layout_trio_portrait",
    "layout_trio_landscape",
    // En queue : les layouts de récit, qui savent porter **une seule photo ou
    // aucune**. Une étape qui tient déjà sa cible n'a pas à poser deux photos
    // de plus sur sa dernière page parce que le collage en exige deux — c'est
    // ce qui faisait sortir une étape moyenne à 67 % au lieu de 50 %.
    "layout_story_opener",
    "layout_story_facts",
  ],
  75: [
    "layout_hero_top",
    "layout_collage",
    "layout_trio_portrait",
    "layout_trio_landscape",
    "layout_photo_page",
  ],
  100: ["layout_photo_wall_intro", "layout_photo_page"],
};

/** Le repli qui tient n'importe quel texte, quand aucun candidat ne le tient. */
const REPLI = "layout_story_full";

/**
 * Le minimum de la taille S du barème. En dessous, une page de récit reste aux
 * trois quarts vide : c'est à l'image de tenir la page.
 */
export const SIGNES_MIN_RECIT = 200;

/**
 * Les layouts à essayer **avant** la préférence du palier quand le récit est
 * sous le minimum de S. Ils ne remplacent pas la préférence : ils s'y ajoutent
 * en tête, et seuls ceux qui sont portés par l'image sont retenus.
 */
const ORDRE_SOUS_S = ["layout_hero_top"] as const;

// ---------------------------------------------------------------------------
// Surface du texte
// ---------------------------------------------------------------------------

/** Les paragraphes d'un `body_html`, texte brut, balises retirées. */
export function paragraphesDe(bodyHtml: string): string[] {
  return String(bodyHtml ?? "")
    .replace(/<\s*(br|\/p|\/li|\/h[1-6])\s*\/?\s*>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .split("\n")
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
}

/** Le texte brut d'une étape, additionné — c'est ce que compte le barème. */
export function signesDe(bodyHtml: string): number {
  return paragraphesDe(bodyHtml).join(" ").length;
}

/**
 * La surface qu'un texte occupe dans une colonne, en pt².
 *
 *     lignes = Σ ⌈signes du paragraphe / signes par ligne⌉ + (paragraphes − 1)
 *     surface = lignes × --mb-line × largeur de colonne
 *
 * Le « + (paragraphes − 1) » est la **ligne vide qui suit chaque paragraphe** :
 * elle montre l'emplacement resté libre dans le gabarit, et elle se paie en
 * surface comme une ligne de texte. C'est elle qui fait que 560 signes tiennent
 * en 2 paragraphes et débordent en 3.
 *
 * Le titre n'est pas compté : il pèse deux interlignes, c'est un élément fixe.
 */
export function surfaceTexte(
  bodyHtml: string,
  colonne: Gabarit["colonne"] = "pleine",
  f: Format = A5,
): number {
  return surfaceDeParagraphes(
    paragraphesDe(bodyHtml).map((p) => p.length),
    colonne,
    f,
  );
}

/**
 * La même, à partir des seules longueurs de paragraphes — c'est cette forme que
 * l'algorithme emploie, parce qu'elle survit à la répartition en pages.
 *
 * La ligne vide ne compte qu'**entre** deux paragraphes d'une même page : un
 * saut de page n'en demande pas.
 */
export function surfaceDeParagraphes(
  longueurs: readonly number[],
  colonne: Gabarit["colonne"] = "pleine",
  f: Format = A5,
): number {
  if (colonne === "aucune" || longueurs.length === 0) return 0;
  const lignes =
    longueurs.reduce((somme, n) => somme + lignesDe(n, colonne, f), 0) + (longueurs.length - 1);
  return surfaceDeLignes(lignes, colonne, f);
}

/** Lignes qu'occupent `signes` caractères dans une colonne. */
function lignesDe(signes: number, colonne: "pleine" | "etroite", f: Format): number {
  return Math.ceil(signes / f.signesParLigne[colonne]);
}

/** Surface d'un nombre de lignes dans une colonne. */
function surfaceDeLignes(lignes: number, colonne: "pleine" | "etroite", f: Format): number {
  return lignes * f.ligne * f.colonnes[colonne];
}

// ---------------------------------------------------------------------------
// photosRequired — la source de vérité partagée avec l'app
// ---------------------------------------------------------------------------

/** Ce qu'une page d'étape porte. */
export interface PagePlan {
  /** Le layout retenu, tel qu'il sera posé en drapeau sur `days[]`. */
  layout: string;
  /** Les photos de cette page. */
  photos: number;
  /** La hauteur de la bande de photos, en pt. */
  hauteurBande: number;
  /** La même, en multiple de la hauteur de conception : ce que le CSS reçoit. */
  echelle: number;
  /** Les longueurs des paragraphes de récit que cette page porte. */
  paragraphes: number[];
  /** Leur total, en signes. */
  signes: number;
  /** Première page de l'étape : elle porte le bandeau et le titre. */
  premiere: boolean;
}

export interface PhotoPlan {
  /** Le nombre **exact** de photos à demander au voyageur. */
  photos: number;
  /** Les pages de l'étape. */
  pages: number;
  /** Le layout de chaque page, dans l'ordre. */
  layouts: string[];
  /** Le plan détaillé, pour la composition et l'inspecteur. */
  plan: PagePlan[];
  /** Le ratio demandé, en %. */
  ratioCible: PhotoRatio;
  /** Le ratio que ce plan donne, en % — calculé, pas mesuré. */
  ratioEstime: number;
  /** Surface du texte, en pt². */
  surfaceTexte: number;
  /** Surface photo visée, en pt². */
  surfaceCible: number;
  /** Surface photo du plan, en pt². */
  surfacePhoto: number;
  /** Hors tolérance ? */
  horsTolerance: boolean;
  /**
   * Hors tolérance **parce que le minimum de photos l'imposait** — un texte
   * très court à ratio bas. L'inspecteur le marque « dépassement assumé
   * (minimum de photos) », et non comme une erreur.
   */
  depassementAssume: boolean;
  /**
   * Les photos ont été **agrandies pour remplir la page**, au-delà de ce que la
   * cible demandait : un récit sous le minimum du barème, ou un minimum de
   * photos qu'un récit très court ne peut pas absorber. Le ratio mesuré peut
   * alors dépasser la tolérance, et ce n'est pas une erreur de composition —
   * « la page ne doit pas laisser de grande zone blanche » passe devant.
   */
  remplissageForce: boolean;
  /** En une phrase, ce qui s'est joué. Pour l'inspecteur et le journal. */
  raison: string;
}

export interface PhotoPlanOptions {
  /** Le carnet a ses fun facts allumés : la carte info a sa place. */
  funFacts?: boolean;
  /** Le carnet a ses décorations allumées (quota > 0). */
  decorations?: boolean;
  /** Cette étape ouvre un chapitre, et son lieu est cartographiable. */
  ouvreChapitre?: boolean;
  /** Sortie de debug : T, P, N, pages et ratio, étape par étape. */
  journal?: (message: string, details?: Record<string, number | string | boolean>) => void;
}

/** Le ratio d'une étape : surcharge par étape d'abord, puis celui du carnet. */
export function getPhotoRatio(
  day: Record<string, unknown> | null | undefined,
  carnet?: Record<string, unknown> | null,
): PhotoRatio {
  const brut = day?.["photo_ratio"] ?? carnet?.["photo_ratio"];
  return normaliserRatio(brut);
}

/** La valeur la plus proche parmi les cinq. Un réglage inconnu retombe au défaut. */
export function normaliserRatio(valeur: unknown): PhotoRatio {
  const n = Number(valeur);
  if (!Number.isFinite(n)) return RATIO_DEFAUT;
  let meilleur: PhotoRatio = PHOTO_RATIOS[0];
  for (const candidat of PHOTO_RATIOS) {
    if (Math.abs(candidat - n) < Math.abs(meilleur - n)) meilleur = candidat;
  }
  return meilleur;
}

/** Le ratio d'un couple de surfaces, en % — jamais de division par zéro. */
function ratioDe(surfacePhoto: number, surfaceTexteTotale: number): number {
  const total = surfacePhoto + surfaceTexteTotale;
  if (total <= 0) return 0;
  return (surfacePhoto / total) * 100;
}

/** Le plafond de texte d'un gabarit à sa bande de conception, encart compris. */
export function capaciteDe(g: Gabarit, premiere: boolean, funFacts: boolean): number {
  const table = funFacts && g.capaciteAvecEncart ? g.capaciteAvecEncart : g.capacite;
  return premiere ? table.bandeau : table.suite;
}

/**
 * Jusqu'où la bande de photos d'une page peut monter **sans voler une ligne au
 * texte**.
 *
 * C'est la contrepartie exacte de la règle absolue : une bande plus haute que
 * sa conception pousse le récit, et le récit ne se comprime pas. Chaque ligne
 * libre (la marge entre ce que la page porte et son plafond) vaut un
 * `--mb-line` de bande en plus.
 */
export function plafondBande(
  g: Gabarit,
  signes: number,
  premiere: boolean,
  funFacts: boolean,
  f: Format,
): number {
  if (g.bande.hauteur <= 0) return 0;
  if (g.colonne === "aucune") return g.bande.max;
  const libre = Math.max(0, capaciteDe(g, premiere, funFacts) - signes);
  const lignes = Math.floor(libre / f.signesParLigne[g.colonne]);
  return Math.max(g.bande.min, Math.min(g.bande.max, g.bande.hauteur + lignes * f.ligne));
}

/**
 * Combien de photos demander, et sur combien de pages composer — **la fonction
 * que le chat de l'app et l'atelier appellent tous les deux.** Un écart entre
 * le nombre annoncé dans le chat et le nombre posé dans le PDF est un bug.
 *
 * L'algorithme, dans l'ordre :
 *
 * 1. mesurer la surface texte **T** de l'étape (`surfaceTexte`) ;
 * 2. calculer la surface photo cible **P = T × r / (1 − r)** ;
 * 3. nombre de pages : le maximum entre ce que le **texte** impose (réparti en
 *    remplissant chaque page avant d'ouvrir la suivante) et ce que **T + P +
 *    éléments fixes** impose. Au moins une page, et jamais une coupe : si le
 *    récit déborde, on ajoute une page ;
 * 4. choisir le layout de chaque page dans `PREFERENCES[r]` — le premier qui
 *    tient le texte de la page sans dépasser la part de surface photo visée ;
 * 5. **N** = max(minimum du ratio, ce que les layouts retenus portent) ;
 * 6. régler la hauteur des bandes pour atterrir dans la tolérance, chacune
 *    bornée par ce que son texte laisse (`plafondBande`) ;
 * 7. absorber le résidu — carte fun fact, puis décor, puis agrandissement des
 *    photos. Jamais en étirant le texte, jamais en ajoutant une photo au-delà
 *    du nombre demandé dans le chat.
 */
export function photosRequired(
  day: { body_html?: string } & Record<string, unknown>,
  photoRatio: unknown = RATIO_DEFAUT,
  format: string | Format = A5,
  options: PhotoPlanOptions = {},
): PhotoPlan {
  const f = typeof format === "string" ? (FORMATS[format] ?? A5) : format;
  const r = normaliserRatio(photoRatio);
  const journal = options.journal ?? (() => {});
  const funFacts = options.funFacts === true;
  const bodyHtml = String(day?.body_html ?? "");

  // 1. La surface du texte. La structure en paragraphes est conservée tout du
  //    long : c'est elle qui porte les lignes vides, et c'est la même mesure
  //    qui sert à la cible P et au ratio final — sans quoi les deux divergent.
  const longueurs = paragraphesDe(bodyHtml).map((p) => p.length);
  const signes = signesDe(bodyHtml);
  const utile = surfaceUtile(f);

  // Éléments fixes de la première page : bandeau et titre, plus la carte fun
  // fact quand le carnet l'a allumée. Hors du ratio, mais ils occupent la page,
  // donc ils comptent dans le nombre de pages.
  const fixes = f.colonnes.pleine * (f.bandeau + f.titre) + (funFacts ? f.encart : 0);

  journal("ratio: étape reçue", {
    ratio: r,
    signes,
    T: Math.round(surfaceDeParagraphes(longueurs, "pleine", f)),
  });

  if (r === 100) return planCentPourCent(longueurs, signes, r, f, options, journal);

  // 3a. Les pages que le texte impose. La référence est le candidat **le plus
  //     tolérant au texte** du palier : on n'ouvre pas une page de plus parce
  //     que le gabarit préféré est plus visuel.
  const reference = gabaritLePlusCapace(PREFERENCES[r], funFacts);
  const parPage = repartirParagraphes(longueurs, reference, funFacts);
  const T = parPage.reduce((s, pars) => s + surfaceDeParagraphes(pars, "pleine", f), 0);

  if (r === 0) {
    const plan: PagePlan[] = parPage.map((pars, i) => ({
      layout: i === 0 && options.ouvreChapitre ? "layout_chapter_map" : REPLI,
      photos: 0,
      hauteurBande: 0,
      echelle: 1,
      paragraphes: pars,
      signes: pars.reduce((s, n) => s + n, 0),
      premiere: i === 0,
    }));
    journal("ratio: 0 %, aucune photo", { pages: plan.length, T: Math.round(T) });
    return finaliser({ plan, P: 0, r, f, journal, minimum: 0 });
  }

  // 2. La surface photo cible.
  const P = (T * r) / (100 - r);

  // 3b. Le nombre de pages. Le texte en impose un plancher ; la surface photo
  //     peut en demander plus. On n'en décide pas au calcul : on **compose
  //     chaque hypothèse et on garde celle qui approche le mieux la cible**.
  //     Trois essais au plus, déterministes, et ça évite la page de trop dont
  //     la planche fait exploser le ratio.
  //
  //     Une page de plus ne veut pas dire une page de photos : le texte est
  //     réparti sur toutes les pages de l'étape. LAYOUT_KB est explicite —
  //     « une page entièrement couverte de texte suivie d'une planche
  //     entièrement couverte de photos » est le cas à proscrire.
  const planchePossible = PREFERENCES[r].some((nom) => GABARITS[nom]?.colonne === "aucune");
  const pagesMax = planchePossible
    ? Math.max(parPage.length, Math.min(parPage.length + 3, Math.ceil((T + P + fixes) / utile)))
    : parPage.length;

  journal("ratio: cible calculée", {
    P: Math.round(P),
    pagesTexte: parPage.length,
    pagesMax,
    utile: Math.round(utile),
  });

  const minimum = plancherDePhotos(day, r, f, options);
  let meilleur: { plan: PagePlan[]; cible: number; ecart: number } | null = null;

  for (let pages = parPage.length; pages <= pagesMax; pages += 1) {
    const reparti = repartirParagraphes(longueurs, reference, funFacts, pages);
    // 4 et 5. Les layouts, page par page.
    const essai: PagePlan[] = [];
    let restante = P;
    for (let i = 0; i < reparti.length; i += 1) {
      const page = choisirGabarit({
        candidats: PREFERENCES[r],
        premiere: i === 0,
        paragraphes: reparti[i] ?? [],
        part: restante / (reparti.length - i),
        funFacts,
        f,
      });
      essai.push(page);
      restante -= GABARITS[page.layout]!.surfacePhotos(page.photos, page.hauteurBande, f);
    }

    // Le minimum du ratio gagne sur le ratio lui-même.
    appliquerMinimum(essai, minimum, r, funFacts);

    // 6. Les hauteurs de bande, pour atterrir dans la tolérance. La cible est
    //    recalculée sur les colonnes réellement retenues : une carte info fait
    //    tomber la colonne à 24 signes la ligne, donc le texte occupe plus de
    //    surface, donc les photos en demandent plus pour le même ratio.
    const cible = (surfaceTexteDuPlan(essai, f) * r) / (100 - r);
    reglerBandes(essai, cible, funFacts, f);

    const surface = essai.reduce(
      (somme, page) => somme + GABARITS[page.layout]!.surfacePhotos(page.photos, page.hauteurBande, f),
      0,
    );
    const ecart = Math.abs(ratioDe(surface, surfaceTexteDuPlan(essai, f)) - r);
    journal("ratio: hypothèse de pagination", { pages, ecart: Math.round(ecart * 10) / 10 });
    // À égalité, le moins de pages : un carnet ne s'épaissit pas pour rien.
    if (!meilleur || ecart < meilleur.ecart - 0.01) meilleur = { plan: essai, cible, ecart };
  }

  const { plan, cible } = meilleur!;

  const fini = finaliser({ plan, P: cible, r, f, journal, minimum });

  // 7. Le résidu, dans l'ordre de la spécification : la carte fun fact, puis le
  //    décor, puis l'agrandissement des photos.
  //
  //    La carte ne remplit du blanc que **si le layout lui a prévu une place** :
  //    un `layout_collage` n'en a pas, et croire qu'une carte allumée allait
  //    remplir sa page laissait un quart de feuille blanche sous un récit de
  //    trois lignes. D'où `encart`, lu dans la table des gabarits.
  //
  //    Le décor, lui, n'absorbe rien dans ce gabarit : le tracé pointillé est
  //    dessiné **à l'intérieur** de la bande de photos (`mb_trace`, appelé par
  //    `.mb-gallery`) et le scotch tient aux coins des images. Aucun des deux ne
  //    descend dans le blanc d'une page. Il ne compte donc pas comme absorbeur
  //    — c'est une différence assumée avec la spécification, notée dans
  //    `docs/ratio-texte-photo.md`.
  const encartPlacable = funFacts && plan.some((page) => GABARITS[page.layout]!.encart);
  // Un récit sous le minimum de S ne remplit pas sa page, quel que soit le
  // ratio atteint : ses photos vont au bout de ce que le texte leur laisse.
  // « La page ne doit pas laisser de grande zone blanche » passe avant la
  // tolérance — et le validateur refuse de toute façon un layout de récit à
  // cette longueur (LAYOUT_KB § « Les deux bornes basses »).
  const sousLeMinimum = signes > 0 && signes < SIGNES_MIN_RECIT;
  if ((fini.depassementAssume || sousLeMinimum) && !encartPlacable) {
    for (const page of plan) {
      const g = GABARITS[page.layout]!;
      page.hauteurBande = plafondBande(g, page.signes, page.premiere, funFacts, f);
      page.echelle =
        g.bande.hauteur > 0 ? Math.round((page.hauteurBande / g.bande.hauteur) * 1000) / 1000 : 1;
    }
    journal("ratio: photos agrandies pour remplir la page", { sousLeMinimum });
    return finaliser({ plan, P: cible, r, f, journal, minimum, assume: true, remplissage: true });
  }

  return fini;
}

/**
 * Le plancher de photos d'un palier : son minimum déclaré, et jamais moins que
 * ce que le palier d'en dessous demanderait pour la même étape.
 *
 * La chaîne est courte (25 → 50 → 75) et sans DOM : six appels au plus pour le
 * palier le plus haut, tous déterministes.
 */
function plancherDePhotos(
  day: { body_html?: string } & Record<string, unknown>,
  r: PhotoRatio,
  f: Format,
  options: PhotoPlanOptions,
): number {
  const propre = MINIMUM_PHOTOS[r] ?? 0;
  const index = PHOTO_RATIOS.indexOf(r);
  if (index <= 0) return propre;
  const dessous = PHOTO_RATIOS[index - 1]!;
  if (dessous === 0) return propre;
  // Sans journal : c'est un calcul intermédiaire, pas une décision à tracer.
  const { journal: _ignore, ...sansJournal } = options;
  return Math.max(propre, photosRequired(day, dessous, f, sansJournal).photos);
}

/**
 * 100 % : aucun `mb-note`. Seulement le bandeau d'étape, la carte fun fact si
 * l'option est activée, et des légendes sous certaines photos.
 *
 * **Le nombre de pages est celui qu'occuperait le texte seul à 0 %, au moins
 * une.** Le récit du voyageur ne disparaît pas du carnet : il devient la
 * matière des fun facts et des légendes, et c'est lui qui dit combien l'étape
 * pèse. Une étape longue garde donc ses deux ou trois pages, en planches.
 */
function planCentPourCent(
  longueurs: readonly number[],
  signes: number,
  r: PhotoRatio,
  f: Format,
  options: PhotoPlanOptions,
  journal: NonNullable<PhotoPlanOptions["journal"]>,
): PhotoPlan {
  const pages = repartirParagraphes(longueurs, GABARITS[REPLI]!, options.funFacts === true).length;
  const plan: PagePlan[] = Array.from({ length: pages }, (_, i) => {
    const layout = i === 0 ? "layout_photo_wall_intro" : "layout_photo_page";
    const g = GABARITS[layout]!;
    return {
      layout,
      photos: g.photos.max,
      hauteurBande: g.bande.hauteur,
      echelle: 1,
      paragraphes: [],
      signes: 0,
      premiere: i === 0,
    };
  });
  journal("ratio: 100 %, aucun récit rendu", { pages, signes });
  return finaliser({ plan, P: Number.POSITIVE_INFINITY, r, f, journal, minimum: 0 });
}

/** Le candidat qui tient le plus de texte sur sa première page. */
function gabaritLePlusCapace(candidats: readonly string[], funFacts: boolean): Gabarit {
  let meilleur = GABARITS[REPLI]!;
  let plafond = -1;
  for (const nom of candidats) {
    const g = GABARITS[nom];
    if (!g || g.colonne === "aucune") continue;
    const cap = capaciteDe(g, true, funFacts);
    if (cap > plafond) {
      plafond = cap;
      meilleur = g;
    }
  }
  return plafond < 0 ? GABARITS[REPLI]! : meilleur;
}

/**
 * Les paragraphes de chaque page : **on remplit la première page avant d'ouvrir
 * la seconde** (LAYOUT_KB). Répartir 720 signes en 360 + 360 laisse deux pages
 * à moitié pleines et un blanc au milieu de chacune ; 560 + 160 en laisse une
 * pleine et une aérée, ce qui est le rythme d'un carnet.
 *
 * La coupe se fait **sur une fin de paragraphe**, jamais au milieu d'une idée :
 * un paragraphe qui ne tient pas ouvre la page suivante. Il tient toujours sur
 * une page — la rédaction les plafonne à 379 signes (taille S du barème) — donc
 * aucun texte ne se perd, et une page n'est jamais vide par cette règle.
 */
function repartirParagraphes(
  longueurs: readonly number[],
  g: Gabarit,
  funFacts: boolean,
  pagesVisees = 0,
): number[][] {
  const pages: number[][] = [[]];
  let courante = 0;
  let reste = longueurs.reduce((s, n) => s + n, 0);

  for (const n of longueurs) {
    const premiere = courante === 0;
    const cap = Math.max(1, capaciteDe(g, premiere, funFacts));
    // Avec un nombre de pages visé, le budget d'une page est la part qui lui
    // revient du texte restant — c'est ce qui répartit au lieu de tasser.
    const budget =
      pagesVisees > courante + 1
        ? Math.min(cap, Math.ceil(reste / (pagesVisees - courante)))
        : cap;
    const dejaLa = pages[courante]!.reduce((s, x) => s + x, 0);
    if (dejaLa > 0 && dejaLa + n > budget) {
      pages.push([]);
      courante += 1;
    }
    pages[courante]!.push(n);
    reste -= n;
  }

  // Les pages visées qui restent sans texte : à 75 et 100 %, ce sont les
  // planches. Ailleurs, elles n'existent pas (voir `planchePossible`).
  while (pages.length < pagesVisees) pages.push([]);
  return pages;
}

/**
 * Le layout d'une page : le premier candidat qui tient le texte de la page et
 * qui n'excède pas la part de surface photo visée.
 *
 * Aucun nom de layout n'apparaît ici hors du repli : tout vient de `GABARITS` et
 * de `PREFERENCES`. Un gabarit ajouté demain entre dans le jeu sans toucher à
 * ce code.
 */
function choisirGabarit(arg: {
  candidats: readonly string[];
  premiere: boolean;
  paragraphes: number[];
  part: number;
  funFacts: boolean;
  f: Format;
}): PagePlan {
  const { candidats, premiere, paragraphes, part, funFacts, f } = arg;
  const signes = paragraphes.reduce((s, n) => s + n, 0);

  // Un récit sous le minimum de S laisserait une page aux trois quarts vide :
  // on essaie d'abord les gabarits qu'une image tient à elle seule. Le
  // dépassement de ratio que ça provoque est assumé — une grande photo valant
  // mieux qu'un grand blanc, et c'est ce que LAYOUT_KB demande.
  const liste =
    signes > 0 && signes < SIGNES_MIN_RECIT
      ? [
          ...[...ORDRE_SOUS_S, ...candidats].filter(
            (nom, rang, tous) => tous.indexOf(nom) === rang && GABARITS[nom]?.porteParImage,
          ),
          ...candidats,
        ]
      : candidats;

  let repli: PagePlan | null = null;

  for (const nom of liste) {
    const g = GABARITS[nom];
    if (!g) continue;
    if (premiere && g.suiteSeulement) continue;
    // Un récit ne tombe pas sur une planche pleine, et une page sans récit ne
    // prend pas un layout de récit : ce serait une grande photo et un trou.
    if ((g.colonne === "aucune") !== (signes === 0)) continue;
    if (g.colonne !== "aucune" && signes > capaciteDe(g, premiere, funFacts)) continue;

    // Le nombre de photos : le plus petit qui atteigne la part visée — on ne
    // demande jamais au voyageur une photo dont la page n'a pas besoin. Si
    // aucun ne l'atteint, le maximum du gabarit.
    let photos = g.photos.max;
    for (let n = g.photos.min; n <= g.photos.max; n += 1) {
      if (g.surfacePhotos(n, g.bande.hauteur, f) >= part) {
        photos = n;
        break;
      }
    }
    const candidat: PagePlan = {
      layout: nom,
      photos,
      hauteurBande: g.bande.hauteur,
      echelle: 1,
      paragraphes,
      signes,
      premiere,
    };
    // Le premier candidat qui sait descendre à la part visée l'emporte ; sinon
    // on garde le premier de la liste, par ordre de préférence.
    if (g.surfacePhotos(photos, g.bande.min, f) <= part * 1.35) return candidat;
    if (!repli) repli = candidat;
  }
  if (repli) return repli;

  // Aucun candidat ne tient le texte : le récit pleine page, qui le tient
  // toujours. Le texte ne tombe jamais sur une page sans place prévue.
  return { layout: REPLI, photos: 0, hauteurBande: 0, echelle: 1, paragraphes, signes, premiere };
}

/**
 * Le minimum de photos du ratio, imposé si le plan n'y arrive pas.
 *
 * On ne change **jamais** le nombre de pages pour y arriver, et on ne retire
 * jamais de texte : on sert d'abord les emplacements libres des layouts déjà
 * choisis, puis on bascule une page vers le premier gabarit de la préférence
 * qui en porte assez **et qui tient encore son texte**.
 */
function appliquerMinimum(
  plan: PagePlan[],
  minimum: number,
  r: PhotoRatio,
  funFacts: boolean,
): void {
  const total = () => plan.reduce((s, p) => s + p.photos, 0);
  if (total() >= minimum) return;

  for (const page of plan) {
    const g = GABARITS[page.layout]!;
    while (total() < minimum && page.photos < g.photos.max) page.photos += 1;
  }
  if (total() >= minimum) return;

  // Le cas du « texte très court à ratio bas » : la page bascule vers un
  // gabarit plus visuel, pour ne pas laisser de grande zone blanche.
  for (const page of plan) {
    for (const nom of PREFERENCES[r]) {
      const g = GABARITS[nom];
      if (!g || (page.premiere && g.suiteSeulement)) continue;
      if (g.colonne === "aucune" && page.signes > 0) continue;
      if (g.colonne !== "aucune" && page.signes > capaciteDe(g, page.premiere, funFacts)) continue;
      if (g.photos.max <= GABARITS[page.layout]!.photos.max) continue;
      const vise = Math.min(g.photos.max, Math.max(g.photos.min, minimum - total() + page.photos));
      page.layout = nom;
      page.photos = vise;
      page.hauteurBande = g.bande.hauteur;
      break;
    }
    if (total() >= minimum) break;
  }
}

/**
 * La hauteur des bandes, pour atterrir dans la tolérance.
 *
 * C'est le seul réglage continu du système, et il ne touche ni au texte ni au
 * nombre de photos : seule la **taille** des cadres bouge, entre le plancher
 * que le CSS impose (`mb-gallery` jamais sous 160 pt) et le plafond que le
 * texte de la page laisse (`plafondBande`).
 *
 * On cherche le facteur unique `k` tel que la somme des surfaces atteigne la
 * cible, par dichotomie : chaque bande est bornée séparément, donc la somme
 * n'est pas inversible à la main. Quarante itérations, déterministe, et la
 * convergence ne dépend d'aucun flottant limite.
 */
function reglerBandes(plan: PagePlan[], P: number, funFacts: boolean, f: Format): void {
  if (!Number.isFinite(P) || P <= 0) return;

  const surfacePour = (k: number): number =>
    plan.reduce((somme, page) => {
      const g = GABARITS[page.layout]!;
      if (g.bande.hauteur <= 0) return somme;
      const h = hauteurPour(page, k, funFacts, f);
      return somme + g.surfacePhotos(page.photos, h, f);
    }, 0);

  let bas = 0.1;
  let haut = 4;
  if (surfacePour(haut) < P) {
    bas = haut; // même au plafond, on n'atteint pas la cible : tout en haut.
  } else if (surfacePour(bas) > P) {
    haut = bas; // même au plancher, on dépasse : tout en bas.
  } else {
    for (let i = 0; i < 40; i += 1) {
      const milieu = (bas + haut) / 2;
      if (surfacePour(milieu) < P) bas = milieu;
      else haut = milieu;
    }
  }
  const k = (bas + haut) / 2;
  for (const page of plan) {
    const g = GABARITS[page.layout]!;
    page.hauteurBande = hauteurPour(page, k, funFacts, f);
    page.echelle =
      g.bande.hauteur > 0 ? Math.round((page.hauteurBande / g.bande.hauteur) * 1000) / 1000 : 1;
  }
}

/** La hauteur de la bande d'une page, au facteur `k`, bornée des deux côtés. */
function hauteurPour(page: PagePlan, k: number, funFacts: boolean, f: Format): number {
  const g = GABARITS[page.layout]!;
  if (g.bande.hauteur <= 0) return 0;
  const plafond = plafondBande(g, page.signes, page.premiere, funFacts, f);
  return Math.max(g.bande.min, Math.min(plafond, g.bande.hauteur * k));
}

/**
 * La surface de récit d'un plan, chaque page mesurée **dans la colonne de son
 * propre layout** : la même étape occupe plus de hauteur quand une carte info
 * lui prend 173 pt de large.
 */
export function surfaceTexteDuPlan(plan: readonly PagePlan[], f: Format = A5): number {
  return plan.reduce(
    (somme, page) => somme + surfaceDeParagraphes(page.paragraphes, GABARITS[page.layout]!.colonne, f),
    0,
  );
}

/** Le plan fini : ratio estimé, tolérance, raison. */
function finaliser(arg: {
  plan: PagePlan[];
  P: number;
  r: PhotoRatio;
  f: Format;
  journal: NonNullable<PhotoPlanOptions["journal"]>;
  minimum: number;
  /** Le dépassement était déjà assumé avant que les photos remplissent le blanc. */
  assume?: boolean;
  /** Les photos ont été agrandies pour remplir la page. */
  remplissage?: boolean;
}): PhotoPlan {
  const { plan, P, r, f, journal, minimum } = arg;
  const photos = plan.reduce((s, p) => s + p.photos, 0);
  const surfacePhoto = plan.reduce(
    (s, p) => s + GABARITS[p.layout]!.surfacePhotos(p.photos, p.hauteurBande, f),
    0,
  );
  const surfaceTexteTotale = surfaceTexteDuPlan(plan, f);

  const ratioEstime = r === 100 ? 100 : ratioDe(surfacePhoto, surfaceTexteTotale);
  const horsTolerance = Math.abs(ratioEstime - r) > RATIO_TOLERANCE;

  // Le dépassement est « assumé » quand il vient du minimum de photos : le plan
  // est déjà au plus petit nombre de photos possible et à la plus petite bande,
  // et c'est le plancher du ratio qui déborde — pas une erreur de composition.
  const auPlancher = plan.every((p) => {
    const g = GABARITS[p.layout]!;
    return g.bande.hauteur <= 0 || p.hauteurBande <= g.bande.min + 0.5;
  });
  const depassementAssume =
    horsTolerance &&
    ratioEstime > r &&
    minimum > 0 &&
    photos <= minimum &&
    (auPlancher || arg.assume === true);

  const remplissageForce = arg.remplissage === true;
  const raison = !horsTolerance
    ? remplissageForce
      ? "dans la tolérance, photos agrandies pour remplir la page"
      : "dans la tolérance"
    : depassementAssume
      ? arg.assume === true
        ? "dépassement assumé (minimum de photos), photos agrandies pour remplir la page"
        : "dépassement assumé (minimum de photos)"
      : ratioEstime > r
        ? `hors tolérance : ${Math.round(ratioEstime)} % pour une cible de ${r} %`
        : `hors tolérance : ${Math.round(ratioEstime)} %, plafonné par le texte`;

  journal("ratio: plan arrêté", {
    photos,
    pages: plan.length,
    ratioCible: r,
    ratioEstime: Math.round(ratioEstime * 10) / 10,
    surfaceTexte: Math.round(surfaceTexteTotale),
    surfacePhoto: Math.round(surfacePhoto),
    horsTolerance,
    raison,
  });

  return {
    photos,
    pages: plan.length,
    layouts: plan.map((p) => p.layout),
    plan,
    ratioCible: r,
    ratioEstime: Math.round(ratioEstime * 10) / 10,
    surfaceTexte: Math.round(surfaceTexteTotale),
    surfaceCible: Number.isFinite(P) ? Math.round(P) : 0,
    surfacePhoto: Math.round(surfacePhoto),
    horsTolerance,
    depassementAssume,
    remplissageForce,
    raison,
  };
}

// ---------------------------------------------------------------------------
// La mesure sur le rendu
// ---------------------------------------------------------------------------

/** Un rectangle relevé sur le rendu, en points. */
export interface Rect {
  largeur: number;
  hauteur: number;
}

export interface MesureEtape {
  /** Surface des emplacements `mb-photo`. */
  surfacePhoto: number;
  /** Surface réellement occupée par les `mb-note`. */
  surfaceTexte: number;
  /** Le ratio mesuré, en %. */
  ratio: number;
  /** Les photos effectivement posées. */
  photos: number;
  /** Les pages de l'étape. */
  pages: number;
}

/**
 * Le ratio **mesuré**, à partir des rectangles relevés sur le rendu.
 *
 * Pure elle aussi : c'est le collecteur (`COLLECTEUR_SOURCE`, qui a besoin d'un
 * DOM) qui fournit les rectangles. On peut donc la vérifier sans navigateur, et
 * l'inspecteur comme les tests Chromium appellent la même.
 *
 * Les éléments fixes n'y sont pas : le collecteur ne relève que `.mb-photo` et
 * `.mb-note`.
 */
export function mesurerRatio(photos: Rect[], notes: Rect[], pages = 1): MesureEtape {
  const surfacePhoto = photos.reduce((s, p) => s + p.largeur * p.hauteur, 0);
  const surfaceTexte = notes.reduce((s, n) => s + n.largeur * n.hauteur, 0);
  return {
    surfacePhoto: Math.round(surfacePhoto),
    surfaceTexte: Math.round(surfaceTexte),
    ratio: Math.round(ratioDe(surfacePhoto, surfaceTexte) * 10) / 10,
    photos: photos.length,
    pages,
  };
}

/**
 * Le code à exécuter **dans la page** pour relever les rectangles d'une étape.
 *
 * Livré en source plutôt qu'en fonction : il part dans `page.evaluate` (tests,
 * inspecteur), où rien de ce module n'est disponible.
 *
 * ⚠ La hauteur relevée pour un `mb-note` est celle de son **texte peint**, pas
 * celle de la boîte : une boîte flex garde sa hauteur pendant que son texte
 * déborde, et c'est le texte qui fait la surface.
 */
export const COLLECTEUR_SOURCE = `(pages) => {
  const PT = 96 / 72;                       // le rendu est en px CSS
  const photos = [];
  const notes = [];
  for (const page of pages) {
    for (const el of page.querySelectorAll(".mb-photo")) {
      const r = el.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) photos.push({ largeur: r.width / PT, hauteur: r.height / PT });
    }
    for (const note of page.querySelectorAll(".mb-note")) {
      const largeur = note.getBoundingClientRect().width / PT;
      let haut = Infinity;
      let bas = -Infinity;
      for (const bloc of note.querySelectorAll("p, ul, li")) {
        const r = bloc.getBoundingClientRect();
        if (r.height <= 0) continue;
        haut = Math.min(haut, r.top);
        bas = Math.max(bas, r.bottom);
      }
      if (bas > haut) notes.push({ largeur, hauteur: (bas - haut) / PT });
    }
  }
  return { photos, notes };
}`;

// ---------------------------------------------------------------------------
// Appliquer le plan à des pages déjà composées
// ---------------------------------------------------------------------------

/**
 * Les layouts qui n'impriment aucun récit : les deux planches du palier 100 %.
 * Recopié de `payloadValidator.ts` à dessein — ce module ne doit rien importer,
 * pour que l'atelier n'embarque pas le validateur du back-end avec lui.
 */
export const PLANCHES = ["layout_photo_page", "layout_photo_wall_intro"] as const;

/** Ce qu'une page de récit porte et qui ne vient pas du plan de ratio. */
const CHAMPS_CONSERVES = [
  "title",
  "date",
  "city",
  "country",
  "day_intro",
  "tag",
  "map",
  "map_svg",
  "prompt",
  "quiz",
  "ai_note",
  "fun_facts",
  "fun_facts_title",
] as const;

/**
 * Les **étapes** d'un `days[]` : une entrée qui porte `day_intro` ouvre une
 * étape, les suivantes la prolongent (LAYOUT_KB § « Étapes, chapitres et sauts
 * de page »). Même découpage que `groupSteps` du validateur.
 */
export function etapesDe(days: Record<string, unknown>[]): Record<string, unknown>[][] {
  const etapes: Record<string, unknown>[][] = [];
  for (const day of days) {
    if (day["day_intro"] || etapes.length === 0) etapes.push([day]);
    else etapes[etapes.length - 1]!.push(day);
  }
  return etapes;
}

/** Le layout actif d'une page, tel que le gabarit le lira. */
export function layoutDe(page: Record<string, unknown>): string {
  return (
    Object.keys(page).find((cle) => cle.startsWith("layout_") && page[cle] === true) ??
    "layout_story_opener"
  );
}

/** Les paragraphes d'un `body_html`, gardés **tels quels**, balises comprises. */
function paragraphesBruts(bodyHtml: string): string[] {
  const trouves = bodyHtml.match(/<(p|ul|ol|h[1-6])\b[\s\S]*?<\/\1>/gi);
  if (trouves && trouves.length > 0) return trouves;
  return bodyHtml.trim() ? [bodyHtml] : [];
}

export interface AppliquerOptions extends PhotoPlanOptions {
  /** Pour l'inspecteur : le plan retenu de chaque étape, dans l'ordre. */
  plans?: PhotoPlan[];
}

/**
 * Un `days[]` déjà composé, **recomposé selon le ratio**.
 *
 * C'est le point où l'app et l'atelier se rejoignent : les deux composent
 * d'abord à leur façon — l'Agent Mise en page d'un côté, `composerJours` de
 * l'autre —, puis passent leurs pages ici. Le plan de `photosRequired` tranche
 * le nombre de pages, le layout de chacune, la répartition des photos et la
 * hauteur des bandes. Un carnet dont le PDF ne porterait pas le nombre de
 * photos annoncé dans le chat serait un bug ; c'est cette fonction qui
 * l'empêche.
 *
 * **Le texte ne bouge jamais.** Un paragraphe peut passer d'une page à la
 * suivante ; aucun n'est coupé, réécrit ni perdu, et le récit d'une étape bout
 * à bout reste identique octet pour octet.
 */
export function appliquerRatio(
  days: Record<string, unknown>[],
  photoRatio: unknown,
  options: AppliquerOptions = {},
): Record<string, unknown>[] {
  const r = normaliserRatio(photoRatio);
  const sortie: Record<string, unknown>[] = [];
  for (const etape of etapesDe(days)) sortie.push(...appliquerRatioEtape(etape, r, options));
  return sortie;
}

/** Une étape, ramenée à ses matières premières puis recomposée. */
function appliquerRatioEtape(
  pages: Record<string, unknown>[],
  r: PhotoRatio,
  options: AppliquerOptions,
): Record<string, unknown>[] {
  const estPlanche = (page: Record<string, unknown>) =>
    (PLANCHES as readonly string[]).includes(layoutDe(page));
  const paragraphes = pages
    .filter((page) => !estPlanche(page))
    .flatMap((page) =>
      typeof page["body_html"] === "string" ? paragraphesBruts(page["body_html"]) : [],
    );
  const photos = pages.flatMap((page): unknown[] =>
    Array.isArray(page["photos"]) ? (page["photos"] as unknown[]) : [],
  );
  const premiere = pages[0] ?? {};

  const plan = photosRequired({ body_html: paragraphes.join("") }, r, A5, {
    ...options,
    ouvreChapitre: Boolean(premiere["map"] ?? premiere["map_svg"]),
  });
  options.plans?.push(plan);

  // À 0 %, les photos ne sont pas réparties : le carnet n'en imprime aucune.
  const disponibles = r === 0 ? [] : photos;

  return plan.plan.map((page, index) => {
    const sortie: Record<string, unknown> = {};

    // Les éléments fixes ne vivent que sur la première page de l'étape : c'est
    // ce qui permet au validateur de reconnaître la suite d'une même étape.
    if (index === 0) {
      for (const champ of CHAMPS_CONSERVES) {
        if (premiere[champ] !== undefined) sortie[champ] = premiere[champ];
      }
      if (options.funFacts === false) {
        delete sortie["fun_facts"];
        delete sortie["fun_facts_title"];
      }
    } else {
      // Une page de suite a un `title` vide et pas de `day_intro` : les 320
      // caractères du bandeau lui sont rendus (LAYOUT_KB).
      sortie["title"] = "";
    }

    // Le récit de cette page : ses paragraphes, tels quels.
    const debutTexte = plan.plan
      .slice(0, index)
      .reduce((somme, p) => somme + p.paragraphes.length, 0);
    const miens = paragraphes.slice(debutTexte, debutTexte + page.paragraphes.length);
    if (miens.length > 0) sortie["body_html"] = miens.join("");

    // Les photos de cette page, dans l'ordre du voyage. Moins de photos que
    // demandé : on compose avec ce qui est là, on n'en invente aucune.
    const debutPhotos = plan.plan.slice(0, index).reduce((somme, p) => somme + p.photos, 0);
    const miennes = disponibles.slice(debutPhotos, debutPhotos + page.photos);
    if (miennes.length > 0) sortie["photos"] = miennes;

    const rendu = layoutRendu(page, miennes.length);
    sortie[rendu] = true;
    if (page.echelle !== 1) sortie["band_scale"] = page.echelle;

    // Une planche n'imprime aucun récit : le texte y serait perdu, et le
    // validateur le refuserait. Le récit a servi de matière aux fun facts et
    // aux légendes (LAYOUT_KB § « Les réglages du voyageur »).
    // `body_html` est requis par le schéma du gabarit : une planche le laisse
    // vide plutôt que de l'omettre, et le récit reste sur les pages qui le
    // rendent.
    if ((PLANCHES as readonly string[]).includes(rendu)) sortie["body_html"] = "";
    return sortie;
  });
}

/**
 * Le drapeau à poser, une fois les photos réellement disponibles comptées.
 *
 * Le plan demande N photos ; le voyageur en a peut-être envoyé moins. Un
 * drapeau de photos sur une page qui n'en a pas assez laisserait un trou à leur
 * place — d'où le repli vers un layout que le nombre réel sait tenir. Une
 * planche, elle, reste une planche : il n'y a pas de récit à poser dessus.
 */
export function layoutRendu(page: PagePlan, photos: number): string {
  if (photos >= page.photos) return page.layout;
  if (page.signes === 0) return page.layout;
  if (photos >= 3) return "layout_collage";
  if (photos === 2) return "layout_split_left";
  if (photos === 1) return "layout_hero_top";
  return page.premiere ? "layout_story_opener" : "layout_story_facts";
}
