/*
 * Ratio texte / photo — combien de photos une étape demande, et sur combien de
 * pages elle se compose.
 *
 * ⚠️ FICHIER GÉNÉRÉ. Ne pas éditer à la main : il est fabriqué depuis
 * `backend/src/services/photoRatio.ts` par `npm run ratio:build`, et
 * `backend/test/ratioPhotosAtelier.test.ts` échoue s'il n'est pas à jour.
 *
 * L'atelier est publié seul sur GitHub Pages : il ne peut pas importer le
 * back-end, et il n'a pas d'étape de construction. Le calcul, lui, doit être le
 * même aux deux bouts — le chat de l'app annonce au voyageur un nombre de
 * photos, et le PDF doit poser exactement celui-là.
 *
 * Les règles, les métriques et les tables de gabarits sont documentées dans le
 * fichier source. Le mode d'emploi est dans
 * `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`.
 */
"use strict";
var RatioPhotos = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/services/photoRatio.ts
  var photoRatio_exports = {};
  __export(photoRatio_exports, {
    A5: () => A5,
    COLLECTEUR_SOURCE: () => COLLECTEUR_SOURCE,
    FORMATS: () => FORMATS,
    GABARITS: () => GABARITS,
    MINIMUM_PHOTOS: () => MINIMUM_PHOTOS,
    PHOTO_RATIOS: () => PHOTO_RATIOS,
    PLANCHES: () => PLANCHES,
    PREFERENCES: () => PREFERENCES,
    RATIO_DEFAUT: () => RATIO_DEFAUT,
    RATIO_TOLERANCE: () => RATIO_TOLERANCE,
    SIGNES_MIN_RECIT: () => SIGNES_MIN_RECIT,
    appliquerRatio: () => appliquerRatio,
    capaciteDe: () => capaciteDe,
    etapesDe: () => etapesDe,
    getPhotoRatio: () => getPhotoRatio,
    layoutDe: () => layoutDe,
    layoutRendu: () => layoutRendu,
    mesurerRatio: () => mesurerRatio,
    normaliserRatio: () => normaliserRatio,
    paragraphesDe: () => paragraphesDe,
    photosRequired: () => photosRequired,
    plafondBande: () => plafondBande,
    signesDe: () => signesDe,
    surfaceDeParagraphes: () => surfaceDeParagraphes,
    surfaceTexte: () => surfaceTexte,
    surfaceTexteDuPlan: () => surfaceTexteDuPlan,
    surfaceUtile: () => surfaceUtile
  });
  var PHOTO_RATIOS = [0, 25, 50, 75, 100];
  var RATIO_TOLERANCE = 5;
  var RATIO_DEFAUT = 50;
  var A5 = {
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
    gapGaleriePleine: 11
  };
  var FORMATS = { a5: A5 };
  function surfaceUtile(f = A5) {
    return (f.largeur - 2 * f.marge) * (f.hauteur - 2 * f.marge);
  }
  function galerie(n, hauteur, f) {
    if (n <= 0) return 0;
    return (f.colonnes.pleine - f.gapGalerie * (n - 1)) * hauteur;
  }
  function chapitre(n, hauteur, f) {
    return n === 1 ? 136 * 196 : galerie(n, hauteur, f);
  }
  function trio(parts) {
    return (n, hauteur, f) => parts.slice(0, n).reduce((somme, [l, h]) => somme + f.colonnes.pleine * l * hauteur * h, 0);
  }
  function flottante(n, hauteur) {
    if (n <= 0) return 0;
    return 165 / 162 * hauteur * hauteur;
  }
  function galeriePleine(n, hauteur, f) {
    if (n <= 0) return 0;
    const largeur = f.largeur - 2 * f.margeGaleriePleine;
    const rangees = n >= 5 ? 3 : n >= 3 ? 2 : 1;
    const hauteurPhotos = hauteur - f.gapGaleriePleine * (rangees - 1);
    const ecartsHorizontaux = Math.max(0, n - rangees);
    return largeur * hauteurPhotos - ecartsHorizontaux * f.gapGaleriePleine * (hauteurPhotos / rangees);
  }
  var HAUTEUR_PLANCHE = A5.hauteur - 2 * A5.margeGaleriePleine;
  var HAUTEUR_PLANCHE_BANDEAU = HAUTEUR_PLANCHE - A5.bandeau;
  var GABARITS = {
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
      encart: true
    },
    layout_story_facts: {
      colonne: "pleine",
      photos: { min: 0, max: 1 },
      bande: { hauteur: 162, min: 140, max: 215 },
      surfacePhotos: flottante,
      capacite: { bandeau: 540, suite: 860 },
      bandeau: true,
      encart: true
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
      encart: false
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
      encart: true
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
      encart: false
    },
    // Trois photos en cascade sous un récit court. Page de suite seulement : la
    // première page porte le bandeau, et les photos n'auraient plus leur hauteur.
    layout_trio_portrait: {
      colonne: "pleine",
      photos: { min: 3, max: 3 },
      bande: { hauteur: 360, min: 300, max: 360 },
      surfacePhotos: trio([
        [0.32, 0.52],
        [0.38, 0.54],
        [0.37, 0.56]
      ]),
      capacite: { bandeau: 0, suite: 410 },
      suiteSeulement: true,
      bandeau: false,
      encart: false
    },
    layout_trio_landscape: {
      colonne: "pleine",
      photos: { min: 3, max: 3 },
      bande: { hauteur: 360, min: 300, max: 360 },
      surfacePhotos: trio([
        [0.58, 0.37],
        [0.36, 0.55],
        [0.36, 0.55]
      ]),
      capacite: { bandeau: 0, suite: 410 },
      suiteSeulement: true,
      bandeau: false,
      encart: false
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
      encart: true
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
      encart: false
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
        max: HAUTEUR_PLANCHE_BANDEAU
      },
      surfacePhotos: galeriePleine,
      capacite: { bandeau: 0, suite: 0 },
      bandeau: true,
      encart: true
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
      encart: true
    }
  };
  var MINIMUM_PHOTOS = {
    0: 0,
    25: 1,
    50: 2,
    75: 3,
    100: null
  };
  var PREFERENCES = {
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
      "layout_story_facts"
    ],
    75: [
      "layout_hero_top",
      "layout_collage",
      "layout_trio_portrait",
      "layout_trio_landscape",
      "layout_photo_page"
    ],
    100: ["layout_photo_wall_intro", "layout_photo_page"]
  };
  var REPLI = "layout_story_full";
  var SIGNES_MIN_RECIT = 200;
  var ORDRE_SOUS_S = ["layout_hero_top"];
  function paragraphesDe(bodyHtml) {
    return String(bodyHtml ?? "").replace(/<\s*(br|\/p|\/li|\/h[1-6])\s*\/?\s*>/gi, "\n").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#39;|&apos;/g, "'").replace(/&quot;/g, '"').split("\n").map((p) => p.trim()).filter((p) => p.length > 0);
  }
  function signesDe(bodyHtml) {
    return paragraphesDe(bodyHtml).join(" ").length;
  }
  function surfaceTexte(bodyHtml, colonne = "pleine", f = A5) {
    return surfaceDeParagraphes(
      paragraphesDe(bodyHtml).map((p) => p.length),
      colonne,
      f
    );
  }
  function surfaceDeParagraphes(longueurs, colonne = "pleine", f = A5) {
    if (colonne === "aucune" || longueurs.length === 0) return 0;
    const lignes = longueurs.reduce((somme, n) => somme + lignesDe(n, colonne, f), 0) + (longueurs.length - 1);
    return surfaceDeLignes(lignes, colonne, f);
  }
  function lignesDe(signes, colonne, f) {
    return Math.ceil(signes / f.signesParLigne[colonne]);
  }
  function surfaceDeLignes(lignes, colonne, f) {
    return lignes * f.ligne * f.colonnes[colonne];
  }
  function getPhotoRatio(day, carnet) {
    const brut = day?.["photo_ratio"] ?? carnet?.["photo_ratio"];
    return normaliserRatio(brut);
  }
  function normaliserRatio(valeur) {
    const n = Number(valeur);
    if (!Number.isFinite(n)) return RATIO_DEFAUT;
    let meilleur = PHOTO_RATIOS[0];
    for (const candidat of PHOTO_RATIOS) {
      if (Math.abs(candidat - n) < Math.abs(meilleur - n)) meilleur = candidat;
    }
    return meilleur;
  }
  function ratioDe(surfacePhoto, surfaceTexteTotale) {
    const total = surfacePhoto + surfaceTexteTotale;
    if (total <= 0) return 0;
    return surfacePhoto / total * 100;
  }
  function capaciteDe(g, premiere, funFacts) {
    const table = funFacts && g.capaciteAvecEncart ? g.capaciteAvecEncart : g.capacite;
    return premiere ? table.bandeau : table.suite;
  }
  function plafondBande(g, signes, premiere, funFacts, f) {
    if (g.bande.hauteur <= 0) return 0;
    if (g.colonne === "aucune") return g.bande.max;
    const libre = Math.max(0, capaciteDe(g, premiere, funFacts) - signes);
    const lignes = Math.floor(libre / f.signesParLigne[g.colonne]);
    return Math.max(g.bande.min, Math.min(g.bande.max, g.bande.hauteur + lignes * f.ligne));
  }
  function photosRequired(day, photoRatio = RATIO_DEFAUT, format = A5, options = {}) {
    const f = typeof format === "string" ? FORMATS[format] ?? A5 : format;
    const r = normaliserRatio(photoRatio);
    const journal = options.journal ?? (() => {
    });
    const funFacts = options.funFacts === true;
    const bodyHtml = String(day?.body_html ?? "");
    const longueurs = paragraphesDe(bodyHtml).map((p) => p.length);
    const signes = signesDe(bodyHtml);
    const utile = surfaceUtile(f);
    const fixes = f.colonnes.pleine * (f.bandeau + f.titre) + (funFacts ? f.encart : 0);
    journal("ratio: étape reçue", {
      ratio: r,
      signes,
      T: Math.round(surfaceDeParagraphes(longueurs, "pleine", f))
    });
    if (r === 100) return planCentPourCent(longueurs, signes, r, f, options, journal);
    const reference = gabaritLePlusCapace(PREFERENCES[r], funFacts);
    const parPage = repartirParagraphes(longueurs, reference, funFacts);
    const T = parPage.reduce((s, pars) => s + surfaceDeParagraphes(pars, "pleine", f), 0);
    if (r === 0) {
      const plan2 = parPage.map((pars, i) => ({
        layout: i === 0 && options.ouvreChapitre ? "layout_chapter_map" : REPLI,
        photos: 0,
        hauteurBande: 0,
        echelle: 1,
        paragraphes: pars,
        signes: pars.reduce((s, n) => s + n, 0),
        premiere: i === 0
      }));
      journal("ratio: 0 %, aucune photo", { pages: plan2.length, T: Math.round(T) });
      return finaliser({ plan: plan2, P: 0, r, f, journal, minimum: 0 });
    }
    const P = T * r / (100 - r);
    const planchePossible = PREFERENCES[r].some((nom) => GABARITS[nom]?.colonne === "aucune");
    const pagesMax = planchePossible ? Math.max(parPage.length, Math.min(parPage.length + 3, Math.ceil((T + P + fixes) / utile))) : parPage.length;
    journal("ratio: cible calculée", {
      P: Math.round(P),
      pagesTexte: parPage.length,
      pagesMax,
      utile: Math.round(utile)
    });
    const minimum = plancherDePhotos(day, r, f, options);
    let meilleur = null;
    for (let pages = parPage.length; pages <= pagesMax; pages += 1) {
      const reparti = repartirParagraphes(longueurs, reference, funFacts, pages);
      const essai = [];
      let restante = P;
      for (let i = 0; i < reparti.length; i += 1) {
        const page = choisirGabarit({
          candidats: PREFERENCES[r],
          premiere: i === 0,
          paragraphes: reparti[i] ?? [],
          part: restante / (reparti.length - i),
          funFacts,
          f
        });
        essai.push(page);
        restante -= GABARITS[page.layout].surfacePhotos(page.photos, page.hauteurBande, f);
      }
      appliquerMinimum(essai, minimum, r, funFacts);
      const cible2 = surfaceTexteDuPlan(essai, f) * r / (100 - r);
      reglerBandes(essai, cible2, funFacts, f);
      const surface = essai.reduce(
        (somme, page) => somme + GABARITS[page.layout].surfacePhotos(page.photos, page.hauteurBande, f),
        0
      );
      const ecart = Math.abs(ratioDe(surface, surfaceTexteDuPlan(essai, f)) - r);
      journal("ratio: hypothèse de pagination", { pages, ecart: Math.round(ecart * 10) / 10 });
      if (!meilleur || ecart < meilleur.ecart - 0.01) meilleur = { plan: essai, cible: cible2, ecart };
    }
    const { plan, cible } = meilleur;
    const fini = finaliser({ plan, P: cible, r, f, journal, minimum });
    const encartPlacable = funFacts && plan.some((page) => GABARITS[page.layout].encart);
    const sousLeMinimum = signes > 0 && signes < SIGNES_MIN_RECIT;
    if ((fini.depassementAssume || sousLeMinimum) && !encartPlacable) {
      for (const page of plan) {
        const g = GABARITS[page.layout];
        page.hauteurBande = plafondBande(g, page.signes, page.premiere, funFacts, f);
        page.echelle = g.bande.hauteur > 0 ? Math.round(page.hauteurBande / g.bande.hauteur * 1e3) / 1e3 : 1;
      }
      journal("ratio: photos agrandies pour remplir la page", { sousLeMinimum });
      return finaliser({ plan, P: cible, r, f, journal, minimum, assume: true, remplissage: true });
    }
    return fini;
  }
  function plancherDePhotos(day, r, f, options) {
    const propre = MINIMUM_PHOTOS[r] ?? 0;
    const index = PHOTO_RATIOS.indexOf(r);
    if (index <= 0) return propre;
    const dessous = PHOTO_RATIOS[index - 1];
    if (dessous === 0) return propre;
    const { journal: _ignore, ...sansJournal } = options;
    return Math.max(propre, photosRequired(day, dessous, f, sansJournal).photos);
  }
  function planCentPourCent(longueurs, signes, r, f, options, journal) {
    const pages = repartirParagraphes(longueurs, GABARITS[REPLI], options.funFacts === true).length;
    const plan = Array.from({ length: pages }, (_, i) => {
      const layout = i === 0 ? "layout_photo_wall_intro" : "layout_photo_page";
      const g = GABARITS[layout];
      return {
        layout,
        photos: g.photos.max,
        hauteurBande: g.bande.hauteur,
        echelle: 1,
        paragraphes: [],
        signes: 0,
        premiere: i === 0
      };
    });
    journal("ratio: 100 %, aucun récit rendu", { pages, signes });
    return finaliser({ plan, P: Number.POSITIVE_INFINITY, r, f, journal, minimum: 0 });
  }
  function gabaritLePlusCapace(candidats, funFacts) {
    let meilleur = GABARITS[REPLI];
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
    return plafond < 0 ? GABARITS[REPLI] : meilleur;
  }
  function repartirParagraphes(longueurs, g, funFacts, pagesVisees = 0) {
    const pages = [[]];
    let courante = 0;
    let reste = longueurs.reduce((s, n) => s + n, 0);
    for (const n of longueurs) {
      const premiere = courante === 0;
      const cap = Math.max(1, capaciteDe(g, premiere, funFacts));
      const budget = pagesVisees > courante + 1 ? Math.min(cap, Math.ceil(reste / (pagesVisees - courante))) : cap;
      const dejaLa = pages[courante].reduce((s, x) => s + x, 0);
      if (dejaLa > 0 && dejaLa + n > budget) {
        pages.push([]);
        courante += 1;
      }
      pages[courante].push(n);
      reste -= n;
    }
    while (pages.length < pagesVisees) pages.push([]);
    return pages;
  }
  function choisirGabarit(arg) {
    const { candidats, premiere, paragraphes, part, funFacts, f } = arg;
    const signes = paragraphes.reduce((s, n) => s + n, 0);
    const liste = signes > 0 && signes < SIGNES_MIN_RECIT ? [
      ...[...ORDRE_SOUS_S, ...candidats].filter(
        (nom, rang, tous) => tous.indexOf(nom) === rang && GABARITS[nom]?.porteParImage
      ),
      ...candidats
    ] : candidats;
    let repli = null;
    for (const nom of liste) {
      const g = GABARITS[nom];
      if (!g) continue;
      if (premiere && g.suiteSeulement) continue;
      if (g.colonne === "aucune" !== (signes === 0)) continue;
      if (g.colonne !== "aucune" && signes > capaciteDe(g, premiere, funFacts)) continue;
      let photos = g.photos.max;
      for (let n = g.photos.min; n <= g.photos.max; n += 1) {
        if (g.surfacePhotos(n, g.bande.hauteur, f) >= part) {
          photos = n;
          break;
        }
      }
      const candidat = {
        layout: nom,
        photos,
        hauteurBande: g.bande.hauteur,
        echelle: 1,
        paragraphes,
        signes,
        premiere
      };
      if (g.surfacePhotos(photos, g.bande.min, f) <= part * 1.35) return candidat;
      if (!repli) repli = candidat;
    }
    if (repli) return repli;
    return { layout: REPLI, photos: 0, hauteurBande: 0, echelle: 1, paragraphes, signes, premiere };
  }
  function appliquerMinimum(plan, minimum, r, funFacts) {
    const total = () => plan.reduce((s, p) => s + p.photos, 0);
    if (total() >= minimum) return;
    for (const page of plan) {
      const g = GABARITS[page.layout];
      while (total() < minimum && page.photos < g.photos.max) page.photos += 1;
    }
    if (total() >= minimum) return;
    for (const page of plan) {
      for (const nom of PREFERENCES[r]) {
        const g = GABARITS[nom];
        if (!g || page.premiere && g.suiteSeulement) continue;
        if (g.colonne === "aucune" && page.signes > 0) continue;
        if (g.colonne !== "aucune" && page.signes > capaciteDe(g, page.premiere, funFacts)) continue;
        if (g.photos.max <= GABARITS[page.layout].photos.max) continue;
        const vise = Math.min(g.photos.max, Math.max(g.photos.min, minimum - total() + page.photos));
        page.layout = nom;
        page.photos = vise;
        page.hauteurBande = g.bande.hauteur;
        break;
      }
      if (total() >= minimum) break;
    }
  }
  function reglerBandes(plan, P, funFacts, f) {
    if (!Number.isFinite(P) || P <= 0) return;
    const surfacePour = (k2) => plan.reduce((somme, page) => {
      const g = GABARITS[page.layout];
      if (g.bande.hauteur <= 0) return somme;
      const h = hauteurPour(page, k2, funFacts, f);
      return somme + g.surfacePhotos(page.photos, h, f);
    }, 0);
    let bas = 0.1;
    let haut = 4;
    if (surfacePour(haut) < P) {
      bas = haut;
    } else if (surfacePour(bas) > P) {
      haut = bas;
    } else {
      for (let i = 0; i < 40; i += 1) {
        const milieu = (bas + haut) / 2;
        if (surfacePour(milieu) < P) bas = milieu;
        else haut = milieu;
      }
    }
    const k = (bas + haut) / 2;
    for (const page of plan) {
      const g = GABARITS[page.layout];
      page.hauteurBande = hauteurPour(page, k, funFacts, f);
      page.echelle = g.bande.hauteur > 0 ? Math.round(page.hauteurBande / g.bande.hauteur * 1e3) / 1e3 : 1;
    }
  }
  function hauteurPour(page, k, funFacts, f) {
    const g = GABARITS[page.layout];
    if (g.bande.hauteur <= 0) return 0;
    const plafond = plafondBande(g, page.signes, page.premiere, funFacts, f);
    return Math.max(g.bande.min, Math.min(plafond, g.bande.hauteur * k));
  }
  function surfaceTexteDuPlan(plan, f = A5) {
    return plan.reduce(
      (somme, page) => somme + surfaceDeParagraphes(page.paragraphes, GABARITS[page.layout].colonne, f),
      0
    );
  }
  function finaliser(arg) {
    const { plan, P, r, f, journal, minimum } = arg;
    const photos = plan.reduce((s, p) => s + p.photos, 0);
    const surfacePhoto = plan.reduce(
      (s, p) => s + GABARITS[p.layout].surfacePhotos(p.photos, p.hauteurBande, f),
      0
    );
    const surfaceTexteTotale = surfaceTexteDuPlan(plan, f);
    const ratioEstime = r === 100 ? 100 : ratioDe(surfacePhoto, surfaceTexteTotale);
    const horsTolerance = Math.abs(ratioEstime - r) > RATIO_TOLERANCE;
    const auPlancher = plan.every((p) => {
      const g = GABARITS[p.layout];
      return g.bande.hauteur <= 0 || p.hauteurBande <= g.bande.min + 0.5;
    });
    const depassementAssume = horsTolerance && ratioEstime > r && minimum > 0 && photos <= minimum && (auPlancher || arg.assume === true);
    const remplissageForce = arg.remplissage === true;
    const raison = !horsTolerance ? remplissageForce ? "dans la tolérance, photos agrandies pour remplir la page" : "dans la tolérance" : depassementAssume ? arg.assume === true ? "dépassement assumé (minimum de photos), photos agrandies pour remplir la page" : "dépassement assumé (minimum de photos)" : ratioEstime > r ? `hors tolérance : ${Math.round(ratioEstime)} % pour une cible de ${r} %` : `hors tolérance : ${Math.round(ratioEstime)} %, plafonné par le texte`;
    journal("ratio: plan arrêté", {
      photos,
      pages: plan.length,
      ratioCible: r,
      ratioEstime: Math.round(ratioEstime * 10) / 10,
      surfaceTexte: Math.round(surfaceTexteTotale),
      surfacePhoto: Math.round(surfacePhoto),
      horsTolerance,
      raison
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
      raison
    };
  }
  function mesurerRatio(photos, notes, pages = 1) {
    const surfacePhoto = photos.reduce((s, p) => s + p.largeur * p.hauteur, 0);
    const surfaceTexte2 = notes.reduce((s, n) => s + n.largeur * n.hauteur, 0);
    return {
      surfacePhoto: Math.round(surfacePhoto),
      surfaceTexte: Math.round(surfaceTexte2),
      ratio: Math.round(ratioDe(surfacePhoto, surfaceTexte2) * 10) / 10,
      photos: photos.length,
      pages
    };
  }
  var COLLECTEUR_SOURCE = `(pages) => {
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
  var PLANCHES = ["layout_photo_page", "layout_photo_wall_intro"];
  var CHAMPS_CONSERVES = [
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
    "fun_facts_title"
  ];
  function etapesDe(days) {
    const etapes = [];
    for (const day of days) {
      if (day["day_intro"] || etapes.length === 0) etapes.push([day]);
      else etapes[etapes.length - 1].push(day);
    }
    return etapes;
  }
  function layoutDe(page) {
    return Object.keys(page).find((cle) => cle.startsWith("layout_") && page[cle] === true) ?? "layout_story_opener";
  }
  function paragraphesBruts(bodyHtml) {
    const trouves = bodyHtml.match(/<(p|ul|ol|h[1-6])\b[\s\S]*?<\/\1>/gi);
    if (trouves && trouves.length > 0) return trouves;
    return bodyHtml.trim() ? [bodyHtml] : [];
  }
  function appliquerRatio(days, photoRatio, options = {}) {
    const r = normaliserRatio(photoRatio);
    const sortie = [];
    for (const etape of etapesDe(days)) sortie.push(...appliquerRatioEtape(etape, r, options));
    return sortie;
  }
  function appliquerRatioEtape(pages, r, options) {
    const estPlanche = (page) => PLANCHES.includes(layoutDe(page));
    const paragraphes = pages.filter((page) => !estPlanche(page)).flatMap(
      (page) => typeof page["body_html"] === "string" ? paragraphesBruts(page["body_html"]) : []
    );
    const photos = pages.flatMap(
      (page) => Array.isArray(page["photos"]) ? page["photos"] : []
    );
    const premiere = pages[0] ?? {};
    const plan = photosRequired({ body_html: paragraphes.join("") }, r, A5, {
      ...options,
      ouvreChapitre: Boolean(premiere["map"] ?? premiere["map_svg"])
    });
    options.plans?.push(plan);
    const disponibles = r === 0 ? [] : photos;
    return plan.plan.map((page, index) => {
      const sortie = {};
      if (index === 0) {
        for (const champ of CHAMPS_CONSERVES) {
          if (premiere[champ] !== void 0) sortie[champ] = premiere[champ];
        }
        if (options.funFacts === false) {
          delete sortie["fun_facts"];
          delete sortie["fun_facts_title"];
        }
      } else {
        sortie["title"] = "";
      }
      const debutTexte = plan.plan.slice(0, index).reduce((somme, p) => somme + p.paragraphes.length, 0);
      const miens = paragraphes.slice(debutTexte, debutTexte + page.paragraphes.length);
      if (miens.length > 0) sortie["body_html"] = miens.join("");
      const debutPhotos = plan.plan.slice(0, index).reduce((somme, p) => somme + p.photos, 0);
      const miennes = disponibles.slice(debutPhotos, debutPhotos + page.photos);
      if (miennes.length > 0) sortie["photos"] = miennes;
      const rendu = layoutRendu(page, miennes.length);
      sortie[rendu] = true;
      if (page.echelle !== 1) sortie["band_scale"] = page.echelle;
      if (PLANCHES.includes(rendu)) sortie["body_html"] = "";
      return sortie;
    });
  }
  function layoutRendu(page, photos) {
    if (photos >= page.photos) return page.layout;
    if (page.signes === 0) return page.layout;
    if (photos >= 3) return "layout_collage";
    if (photos === 2) return "layout_split_left";
    if (photos === 1) return "layout_hero_top";
    return page.premiere ? "layout_story_opener" : "layout_story_facts";
  }
  return __toCommonJS(photoRatio_exports);
})();

// UMD : `require()` sous Node (tests du back-end), `window.RatioPhotos` dans
// l'atelier. Même forme que `partage.js` et `mise-en-page.js`.
if (typeof module !== "undefined" && module.exports) module.exports = RatioPhotos;
else if (typeof window !== "undefined") window.RatioPhotos = RatioPhotos;
