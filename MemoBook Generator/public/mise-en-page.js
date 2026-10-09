/*
 * Mise en page des étapes — l'équivalent, dans l'atelier, de l'Agent Mise en
 * page de l'app.
 *
 * L'atelier ne lit pas `LAYOUT_KB.md` : ses règles y sont recopiées ici, en
 * code. Ce fichier ne touche ni au DOM ni au réseau, pour être testé tel quel
 * depuis la suite du back-end (`backend/test/miseEnPageAtelier.test.ts`).
 *
 * Le chemin, étape par étape (`composerJours`) :
 *
 * 1. le récit est découpé en paragraphes de taille S au plus, puis en pages
 *    (`pagesDeRecit`) ;
 * 2. chaque photo va sur la page du passage qu'elle illustre, et les photos
 *    d'une même scène restent ensemble (`affecterPhotos`) — d'après l'analyse
 *    d'étape faite par le modèle, à défaut dans l'ordre du voyage ;
 * 3. une étape qui arrive dans un nouveau lieu ouvre un chapitre, sur une
 *    carte (`layout_chapter_map`) cadrée sur la zone que les récits
 *    parcourent dans le pays (`cadreDuVoyage`) ;
 * 4. puis, sur tout le carnet, deux pages qui se font face ne gardent jamais
 *    la même composition (`varierDoublesPages`) ;
 * 5. si le carnet a ses fun facts allumés, les encarts proposés par l'analyse
 *    se posent, un toutes les trois pages au plus (`placerEncarts`) ;
 * 6. enfin chaque photo prend l'emplacement qui la rogne le moins
 *    (`placerPhotos`).
 *
 * Règles et chiffres : `templates/travel-journal/LAYOUT_KB.md`.
 */
(function (racine) {
  "use strict";

  // Les trajets racontés et leurs moyens de transport (`voyage.js`).
  const Voyage = typeof module !== "undefined" && module.exports ? require("./voyage.js") : racine.Voyage;

  /** Le moyen de transport qui a mené à `nom` pendant l'étape, si le récit le raconte. */
  function modeArrivee(analyse, nom) {
    const cle = normaliser(nom);
    const trajet = (analyse?.trajets || []).find((t) => normaliser(t?.arrivee?.nom) === cle);
    return trajet ? Voyage.modeDe(trajet.mode) : null;
  }

  /**
   * Un paragraphe ne dépasse jamais la taille S du barème (379 signes) : c'est la
   * limite que `payloadValidator.ts` applique au carnet, et au-delà c'est un mur
   * de texte quelle que soit la taille de l'étape.
   */
  const SIGNES_PAR_PARAGRAPHE = 379;

  /**
   * Coupe une phrase trop longue pour un paragraphe. Un vocal transcrit en donne
   * souvent : 1 300 signes sans un point, que le découpage par phrases laissait
   * d'un bloc et qui débordaient de la page. On coupe sur la dernière virgule
   * avant la limite, à défaut sur le dernier espace — jamais au milieu d'un mot,
   * et aucun mot n'est perdu.
   */
  function couperPhrase(phrase, maxSignes) {
    const morceaux = [];
    let reste = phrase;
    while (reste.length > maxSignes) {
      const tete = reste.slice(0, maxSignes + 1);
      let coupe = tete.lastIndexOf(", ");
      if (coupe < maxSignes / 2) coupe = tete.lastIndexOf(" ");
      else coupe += 1;
      if (coupe <= 0) coupe = maxSignes;
      morceaux.push(reste.slice(0, coupe).trim());
      reste = reste.slice(coupe).trim();
    }
    if (reste) morceaux.push(reste);
    return morceaux;
  }

  /** Découpe un récit en paragraphes qui tiennent dans une page du carnet. */
  function enParagraphes(texte, maxSignes = SIGNES_PAR_PARAGRAPHE) {
    const phrases = String(texte || "")
      .replace(/\s+/g, " ")
      .trim()
      .split(/(?<=[.!?…])\s+/)
      .filter(Boolean)
      .flatMap((phrase) => couperPhrase(phrase, maxSignes));
    const paragraphes = [];
    let courant = "";
    for (const phrase of phrases) {
      if (!courant) courant = phrase;
      else if (courant.length + 1 + phrase.length <= maxSignes) courant += ` ${phrase}`;
      else {
        paragraphes.push(courant);
        courant = phrase;
      }
    }
    if (courant) paragraphes.push(courant);
    return paragraphes;
  }

  const echapperHtml = (t) =>
    String(t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  const paragraphesEnHtml = (paragraphes) =>
    paragraphes.map((t) => `<p>${echapperHtml(t)}</p>`).join("");

  /**
   * Combien de photos chaque gabarit **rend réellement**, d'après le catalogue de
   * `MemoBook Generator/templates/travel-journal/LAYOUT_KB.md`. Au-delà de ce
   * nombre, les photos envoyées ne sont pas dessinées : elles disparaissent du
   * carnet sans que rien ne le signale.
   *
   * Le layout par défaut (`story_opener` / `story_facts`) pose une photo
   * flottante en bas de page, sous le récit.
   */
  const PHOTOS_RENDUES = {
    layout_chapter_map: 2,
    layout_story_facts: 1,
    layout_story_opener: 1,
    layout_hero_top: 1,
    layout_split_left: 2,
    layout_collage: 3,
    layout_trio_portrait: 3,
    layout_trio_landscape: 3,
    layout_photo_page: 5,
  };

  /** Une page de récit porte au plus trois photos (`layout_collage`). */
  const MAX_PHOTOS_RECIT = PHOTOS_RENDUES.layout_collage;

  /** Le gabarit « page pleine de photos » exige au moins trois images. */
  const MIN_PAGE_PHOTOS = 3;

  /**
   * Capacité d'une page de récit, recopiée de `payloadValidator.ts`
   * (`LAYOUT_CAPACITY`, `PARAGRAPHS_PER_PAGE`) : l'atelier ne passe pas par le
   * validateur, il doit donc respecter les mêmes plafonds de lui-même.
   * `bandeau` : première page de l'étape ; `suite` : pages suivantes, sans
   * bandeau ni titre, qui gagnent la place de ceux-ci.
   */
  const CAPACITE_PAGE = {
    defaut: { bandeau: 560, suite: 880 },
    layout_hero_top: { bandeau: 380, suite: 680 },
    // Pages de suite seulement : sous un bandeau, les trois photos n'ont plus
    // leur hauteur. Mesuré le 08/10/2026 (`calibrate-lengths.ts --filtre
    // trio`) : 440 signes en deux paragraphes avant que les photos cèdent.
    layout_trio: { bandeau: 0, suite: 420, paragraphes: 2 },
  };
  const PARAGRAPHES_PAR_PAGE = { bandeau: 2, suite: 4 };

  /** Minimum de la taille S : une page de récit plus maigre n'est qu'un reliquat. */
  const MIN_SIGNES_PAGE = 200;

  /** Compté comme `bodyLength` de `payloadValidator.ts` : paragraphes joints par une espace. */
  const signes = (paragraphes) => paragraphes.join(" ").length;

  /** En dessous, un bout de paragraphe en bas de page ne vaut pas la coupe. */
  const MIN_SIGNES_COUPE = 100;

  /**
   * Coupe un paragraphe pour en loger le début dans `place` signes : sur la
   * dernière fin de phrase qui tient, à défaut sur une virgule, à défaut — un
   * vocal transcrit d'un seul souffle — sur un espace. Jamais au milieu d'un mot.
   * Renvoie `null` si le début serait trop court pour valoir la coupe.
   */
  function couperAuPlus(paragraphe, place) {
    const fenetre = paragraphe.slice(0, place + 1);
    const derniere = (motif) => {
      let fin = -1;
      for (const m of fenetre.matchAll(motif)) fin = m.index + m[0].length;
      return fin;
    };
    let coupe = derniere(/[.!?…]\s/g);
    if (coupe < MIN_SIGNES_COUPE) coupe = derniere(/,\s/g);
    if (coupe < MIN_SIGNES_COUPE) coupe = fenetre.lastIndexOf(" ");
    if (coupe < MIN_SIGNES_COUPE) return null;
    return [paragraphe.slice(0, coupe).trim(), paragraphe.slice(coupe).trim()];
  }

  /**
   * Répartit les paragraphes d'une étape sur ses pages de récit.
   *
   * C'est ce qui manquait : l'atelier posait tout le récit sur une seule page, et
   * un long vocal débordait — la fin du texte coupée net, la photo du bas poussée
   * hors de la feuille. Les règles sont celles de LAYOUT_KB, § « Longueur des
   * textes » et § « La répartition sur une étape à plusieurs pages » :
   *
   * - on remplit la première page avant d'ouvrir la suivante, sans dépasser ni
   *   les signes ni les paragraphes qu'elle tient ; un paragraphe qui ne tient
   *   plus entier se coupe, de préférence sur une fin de phrase, et la suite
   *   ouvre la page d'après ;
   * - mais la dernière page ne doit pas être un reliquat : sous la taille S, elle
   *   reprend des paragraphes à la précédente tant que celle-ci reste au-dessus.
   */
  function pagesDeRecit(paragraphes) {
    const pages = [];
    const file = [...paragraphes];
    while (file.length) {
      const paragraphe = file.shift();
      const page = pages[pages.length - 1];
      const sorte = pages.length <= 1 ? "bandeau" : "suite";
      const place = page ? CAPACITE_PAGE.defaut[sorte] - signes(page) - 1 : 0;
      if (page && page.length < PARAGRAPHES_PAR_PAGE[sorte] && paragraphe.length <= place) {
        page.push(paragraphe);
        continue;
      }
      const coupe = page && page.length < PARAGRAPHES_PAR_PAGE[sorte] ? couperAuPlus(paragraphe, place) : null;
      if (coupe) {
        page.push(coupe[0]);
        file.unshift(coupe[1]);
      } else {
        pages.push([paragraphe]);
      }
    }

    const derniere = pages[pages.length - 1];
    const avant = pages[pages.length - 2];
    while (
      avant &&
      avant.length > 1 &&
      signes(derniere) < MIN_SIGNES_PAGE &&
      signes(avant.slice(0, -1)) >= MIN_SIGNES_PAGE &&
      signes([avant[avant.length - 1], ...derniere]) <= CAPACITE_PAGE.defaut.suite &&
      derniere.length < PARAGRAPHES_PAR_PAGE.suite
    ) {
      derniere.unshift(avant.pop());
    }
    return pages;
  }

  /**
   * Le format (largeur / hauteur) de chaque emplacement photo, gabarit par
   * gabarit, dans l'ordre où le gabarit lit `photos[]`. Mesuré sur le rendu de
   * `templates/travel-journal/index.html`, image seule, sans le cadre blanc —
   * à remesurer si la géométrie d'un gabarit change (LAYOUT_KB § « Rognage des
   * photos »).
   */
  const FORMATS_EMPLACEMENTS = {
    layout_chapter_map: { 2: [0.93, 0.93] },
    layout_story_opener: { 1: [1.02] },
    layout_story_facts: { 1: [1.02] },
    layout_hero_top: { 1: [1.35] },
    layout_split_left: { 2: [0.9, 0.9] },
    layout_collage: { 2: [0.9, 0.9], 3: [0.56, 0.56, 0.56] },
    // En haut, puis en bas à gauche et à droite (l'ordre de `photos[]`).
    layout_trio_portrait: { 3: [0.6, 0.69, 0.65] },
    layout_trio_landscape: { 3: [1.6, 0.64, 0.64] },
    layout_photo_page: {
      3: [0.73, 0.45, 1.65],
      4: [0.73, 0.45, 0.62, 0.99],
      5: [1.76, 1.44, 0.9, 0.9, 1.44],
    },
  };

  /**
   * Plafond de rognage : on garde toujours au moins les deux tiers de l'image.
   * Une photo paysage 4:3 entre dans un emplacement presque carré (32 % rognés)
   * mais pas dans une colonne étroite (58 % à 66 %), où l'on ne reconnaît plus
   * l'image. Au-delà, la photo est réduite sans être rognée. Voir LAYOUT_KB
   * § « Rognage des photos ».
   */
  const MAX_ROGNAGE = 1 / 3;

  /** Part de l'image perdue quand une photo de format `photo` remplit un emplacement de format `cadre`. */
  function rognage(photo, cadre) {
    if (!photo || !cadre) return 0;
    return 1 - Math.min(cadre / photo, photo / cadre);
  }

  /** Toutes les permutations d'un petit tableau (cinq éléments au plus : 120). */
  function permutations(liste) {
    if (liste.length <= 1) return [liste];
    return liste.flatMap((x, i) =>
      permutations([...liste.slice(0, i), ...liste.slice(i + 1)]).map((reste) => [x, ...reste]),
    );
  }

  /**
   * Place les photos d'une page dans ses emplacements, et dit comment chacune
   * s'affiche.
   *
   * 1. **L'ordre** : parmi toutes les façons de répartir les photos dans les
   *    emplacements, on retient celle qui rogne le moins — une photo paysage va
   *    dans l'emplacement large, une portrait dans la colonne étroite. C'est ce
   *    qui coupait la photo de groupe du 28 août : paysage, posée dans la
   *    colonne la plus étroite de la planche.
   * 2. **Le rendu** : une photo de groupe, ou une photo qui serait rognée de plus
   *    d'un tiers même à la meilleure place, passe en `fit: "contain"` — réduite
   *    proportionnellement, jamais coupée. Une photo plus haute que son
   *    emplacement garde le haut de l'image (`focus` à 30 %) : c'est là que sont
   *    les visages, sur la plupart des photos prises à hauteur d'homme.
   */
  function placerPhotos(layout, photos) {
    const formats = FORMATS_EMPLACEMENTS[layout]?.[photos.length];
    const cout = (ordre) =>
      ordre.reduce((total, photo, i) => total + rognage(photo.format, formats[i]), 0);
    const ordre =
      formats && photos.every((p) => p.format)
        ? permutations(photos).reduce((meilleur, essai) => (cout(essai) < cout(meilleur) ? essai : meilleur))
        : photos;

    return ordre.map((photo, i) => {
      const cadre = formats?.[i];
      if (photo.groupe || rognage(photo.format, cadre) > MAX_ROGNAGE) return { url: photo.src, fit: "contain" };
      if (photo.format && cadre && photo.format < cadre) return { url: photo.src, focus: "50% 30%" };
      return photo.src;
    });
  }

  /**
   * Combien de photos une page de récit peut porter, d'après les formats de
   * l'étape. Les trois emplacements d'un collage sont des colonnes étroites
   * (format 0,56) : une photo paysage y perd 58 % de sa surface, bien au-delà du
   * plafond de rognage. Une étape surtout en paysage met donc deux photos par
   * page de récit (format 0,90 : 32 % au plus), et le surplus va sur les
   * planches, dont les grands emplacements leur conviennent.
   */
  function photosParPageDeRecit(photos) {
    const paysages = photos.filter((p) => p.format > 1).length;
    return paysages * 2 > photos.length ? 2 : MAX_PHOTOS_RECIT;
  }

  /**
   * Le gabarit d'une page de récit, d'après les photos qu'elle porte.
   *
   * `layout_hero_top` (grande photo en tête, format 1,35) tient moins de texte
   * que les autres, et ne convient qu'à une photo paysage : une portrait y
   * perdrait 44 % de sa surface. On ne le choisit que si le texte de la page y
   * entre et que la photo y tient sans dépasser le plafond de rognage ; sinon la
   * photo passe en photo flottante (format 1,02) sous le récit.
   */
  function layoutDeRecit(photosDeLaPage, texte, sorte, premiere) {
    const nbPhotos = photosDeLaPage.length;
    const trio = nbPhotos === 3 ? trioDe(photosDeLaPage, texte, sorte) : null;
    if (trio) return trio;
    const parDefaut = premiere ? "layout_story_opener" : "layout_story_facts";
    if (nbPhotos === 0) return parDefaut;
    if (nbPhotos === 1) {
      const [photo] = photosDeLaPage;
      const heroLisible =
        !photo.format || rognage(photo.format, FORMATS_EMPLACEMENTS.layout_hero_top[1][0]) <= MAX_ROGNAGE;
      return heroLisible && signes(texte) <= CAPACITE_PAGE.layout_hero_top[sorte] ? "layout_hero_top" : parDefaut;
    }
    if (nbPhotos === 2) return "layout_split_left";
    return "layout_collage";
  }



  /**
   * Le trio d'une page de suite à trois photos et récit court : une photo en
   * haut, deux en bas (maquettes du 08/10/2026). La variante est celle où les
   * trois photos se rognent le moins — la paysage en haut s'il y en a une —,
   * à condition qu'aucune n'y dépasse le plafond de rognage : une photo
   * réduite dans un trio, c'est un timbre-poste au milieu du collage. Sinon,
   * `null` : la page reste un collage.
   */
  function trioDe(photos, texte, sorte) {
    const cap = CAPACITE_PAGE.layout_trio;
    if (sorte !== "suite" || signes(texte) > cap.suite || texte.length > cap.paragraphes) return null;
    if (photos.some((p) => p.groupe)) return null;
    let meilleur = null;
    for (const layout of ["layout_trio_portrait", "layout_trio_landscape"]) {
      const formats = FORMATS_EMPLACEMENTS[layout][3];
      for (const ordre of permutations(photos)) {
        const pertes = ordre.map((p, i) => (p.format ? rognage(p.format, formats[i]) : 0));
        if (pertes.some((r) => r > MAX_ROGNAGE)) continue;
        const cout = pertes.reduce((a, b) => a + b, 0);
        if (!meilleur || cout < meilleur.cout) meilleur = { layout, cout };
      }
    }
    return meilleur?.layout ?? null;
  }

  /* --------------------------------------------------- ouverture de chapitre */

  /**
   * Ce que tient une ouverture de chapitre : la carte prend 176 pt à droite et
   * la colonne de récit tombe à ~24 caractères par ligne (LAYOUT_KB § « Chapitre
   * ou journée ordinaire »). 540 et non 560 : c'est le dernier palier où le
   * calibrage du 07/10 ne relève aucun débordement.
   */
  const CAPACITE_CHAPITRE = { sansPhoto: 540, deuxPhotos: 320 };

  /** Six points au plus sur une carte (LAYOUT_KB § « Les cartes »). */
  const MAX_POINTS_CARTE = 6;

  const normaliser = (t) =>
    String(t || "")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .split(",")[0]
      .trim();

  /** Le lieu de l'étape tel que l'analyse l'a situé, ou `null` s'il n'est pas sûr. */
  function lieuSitue(analyse, contours) {
    const lieu = analyse?.lieu;
    if (!lieu || !contours) return null;
    const pays = String(lieu.pays || "").toUpperCase();
    const lat = Number(lieu.lat);
    const lon = Number(lieu.lon);
    if (!contours[pays] || !Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    if (lat === 0 && lon === 0) return null;
    return { pays, lat, lon, nom: String(lieu.nom || "").trim() };
  }

  /**
   * Tous les lieux où les récits emmènent le voyageur : le lieu de chaque
   * étape, et ceux que l'analyse a relevés dans son récit (une excursion, une
   * traversée). Seuls ceux que l'analyse a situés avec certitude.
   */
  function lieuxDuVoyage(etapes, contours) {
    const lieux = [];
    for (const etape of etapes) {
      const principal = lieuSitue(etape.analyse, contours);
      if (principal) lieux.push(principal);
      for (const lieu of etape.analyse?.lieux || []) {
        const situe = lieuSitue({ lieu }, contours);
        if (situe) lieux.push(situe);
      }
    }
    return lieux;
  }

  /** Un degré au moins de côté (~110 km) : en deçà, la carte ne montre plus où l'on est. */
  const CADRE_MIN_DEGRES = 1;
  /** La marge autour des lieux, de part et d'autre : 20 % de leur étendue. */
  const MARGE_CADRE = 0.2;

  /**
   * Le cadre d'une carte de chapitre : la zone que le voyage parcourt dans ce
   * pays, d'après ce que racontent les récits — et non le pays entier. Un
   * voyage dans les Cyclades se cadre sur les Cyclades ; un tour de la Grèce,
   * sur la Grèce. Le même cadre sert à tous les chapitres du pays : d'une
   * carte à l'autre, on voit le trajet avancer.
   *
   * `[ouest, sud, est, nord]` en degrés, jamais plus grand que le pays (plus
   * une marge), ou `null` sans lieu situé.
   */
  function cadreDuVoyage(lieux, pays, contours, minimum = CADRE_MIN_DEGRES) {
    const dans = lieux.filter((l) => l.pays === pays);
    if (!dans.length) return null;
    let o = Math.min(...dans.map((l) => l.lon));
    let e = Math.max(...dans.map((l) => l.lon));
    let s = Math.min(...dans.map((l) => l.lat));
    let n = Math.max(...dans.map((l) => l.lat));
    // Un degré de longitude rétrécit avec la latitude : le minimum se compte
    // en distance, pas en degrés bruts.
    const cosLat = Math.max(0.2, Math.cos((((s + n) / 2) * Math.PI) / 180));
    const elargir = (a, b, min) => {
      const c = (a + b) / 2;
      const demi = Math.max(((b - a) * (1 + 2 * MARGE_CADRE)) / 2, min / 2);
      return [c - demi, c + demi];
    };
    [s, n] = elargir(s, n, minimum);
    [o, e] = elargir(o, e, minimum / cosLat);

    // Pas au-delà du pays : un voyage qui le parcourt en entier retrouve la
    // carte du pays.
    const rings = contours?.[pays]?.rings;
    if (rings?.length) {
      const lons = rings.flat().map((p) => p[0]);
      const lats = rings.flat().map((p) => p[1]);
      const marge = 0.3;
      o = Math.max(o, Math.min(...lons) - marge);
      e = Math.min(e, Math.max(...lons) + marge);
      s = Math.max(s, Math.min(...lats) - marge);
      n = Math.min(n, Math.max(...lats) + marge);
    }
    const arrondi = (v) => Math.round(v * 1000) / 1000;
    return [arrondi(o), arrondi(s), arrondi(e), arrondi(n)];
  }

  /**
   * Un séjour en un seul lieu — une ville, une île : tous les lieux du voyage
   * dans le pays tiennent dans ~30 km. Sa première carte montre le pays et y
   * situe la ville ; les suivantes zooment sur la ville et y tracent les
   * déplacements (LAYOUT_KB § « Les cartes »).
   */
  const ETENDUE_SEJOUR = 0.3;
  /** Trois kilomètres de côté au moins pour une carte de ville : deux rues voisines n'en font pas une carte. */
  const CADRE_MIN_VILLE = 0.03;
  /** Lieux nouveaux nommés sur une carte de ville : au-delà, les noms se chevauchent. */
  const MAX_NOUVEAUX_VILLE = 3;

  function sejourUnique(lieux, pays) {
    const dans = lieux.filter((l) => l.pays === pays);
    if (!dans.length) return false;
    const lats = dans.map((l) => l.lat);
    const lons = dans.map((l) => l.lon);
    const cosLat = Math.max(0.2, Math.cos((((Math.min(...lats) + Math.max(...lats)) / 2) * Math.PI) / 180));
    return (
      Math.max(...lats) - Math.min(...lats) <= ETENDUE_SEJOUR &&
      (Math.max(...lons) - Math.min(...lons)) * cosLat <= ETENDUE_SEJOUR
    );
  }

  /**
   * Le pays entier, avec la même marge que le plafond de `cadreDuVoyage` —
   * mais le pays tel qu'on le reconnaît : son plus grand territoire et les
   * terres à moins de deux degrés (la Corse), pas l'outre-mer (la boîte de la
   * France va jusqu'à la Guyane). Le lieu du séjour y est toujours.
   */
  function cadreDuPays(pays, contours, lieu = null) {
    const tous = contours?.[pays]?.rings;
    if (!tous?.length) return null;
    const boite = (ring) => [
      Math.min(...ring.map((p) => p[0])),
      Math.min(...ring.map((p) => p[1])),
      Math.max(...ring.map((p) => p[0])),
      Math.max(...ring.map((p) => p[1])),
    ];
    const aire = (b) => (b[2] - b[0]) * (b[3] - b[1]);
    const boites = tous.map(boite);
    const principal = boites.reduce((a, b) => (aire(b) > aire(a) ? b : a));
    const proches = boites.filter(
      (b) => b[0] <= principal[2] + 2 && principal[0] - 2 <= b[2] && b[1] <= principal[3] + 2 && principal[1] - 2 <= b[3],
    );
    const lons = proches.flatMap((b) => [b[0], b[2]]).concat(lieu ? [lieu.lon] : []);
    const lats = proches.flatMap((b) => [b[1], b[3]]).concat(lieu ? [lieu.lat] : []);
    const marge = 0.3;
    const arrondi = (v) => Math.round(v * 1000) / 1000;
    return [
      arrondi(Math.min(...lons) - marge),
      arrondi(Math.min(...lats) - marge),
      arrondi(Math.max(...lons) + marge),
      arrondi(Math.max(...lats) + marge),
    ];
  }

  /** Tous les cadres dont les cartes du carnet auront besoin : de quoi charger les bons contours. */
  function cadresDesCartes(etapes, contours) {
    const lieux = lieuxDuVoyage(etapes, contours);
    return [...new Set(lieux.map((l) => l.pays))]
      .flatMap((pays) =>
        sejourUnique(lieux, pays)
          ? [
              cadreDuPays(pays, contours, lieux.find((l) => l.pays === pays)),
              cadreDuVoyage(lieux, pays, contours, CADRE_MIN_VILLE),
            ]
          : [cadreDuVoyage(lieux, pays, contours)],
      )
      .filter(Boolean);
  }

  /* ----------------------------------------------- photos ↔ passages du récit */

  /**
   * Pour chaque paragraphe d'origine, la page qui en porte le plus. Les pages
   * sont faites de morceaux de paragraphes, dans l'ordre : un paragraphe coupé
   * entre deux pages appartient à celle qui en a la plus grande part.
   */
  function pageDeChaqueParagraphe(paragraphes, pages) {
    const parts = paragraphes.map(() => new Map());
    let i = 0;
    let reste = paragraphes[0]?.length ?? 0;
    pages.forEach((page, p) => {
      for (const morceau of page) {
        if (i >= paragraphes.length) return;
        parts[i].set(p, (parts[i].get(p) || 0) + morceau.length);
        reste -= morceau.length;
        // Les coupes retirent une ou deux espaces : un reste de 3 signes est épuisé.
        if (reste <= 3) {
          i += 1;
          reste = paragraphes[i]?.length ?? 0;
        }
      }
    });
    return parts.map((m) => [...m.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? 0);
  }

  /** La valeur la plus fréquente ; à égalité, la plus petite. */
  function mode(valeurs) {
    const compte = new Map();
    for (const v of valeurs) compte.set(v, (compte.get(v) || 0) + 1);
    return [...compte.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0]?.[0] ?? 0;
  }

  /**
   * Répartit les photos d'une étape entre ses pages de récit et ses planches.
   *
   * 1. **Chaque photo vise la page du passage qu'elle illustre** — le
   *    paragraphe que l'analyse lui a attribué. Sans analyse, ou sans
   *    paragraphe, elle vise la page qui correspond à son rang dans l'étape :
   *    les premières photos sur la première page, et ainsi de suite.
   * 2. **Les photos d'une même scène restent ensemble** (même arrière-plan,
   *    même libellé `scene`) : le groupe vise la page que vise la majorité de
   *    ses photos, et il ne se coupe que s'il dépasse ce qu'une page porte.
   * 3. Une page porte au plus `maxParPage` photos ; l'ouverture de chapitre, 0
   *    ou 2 (son gabarit n'en montre pas une seule).
   * 4. **Le surplus d'une page** va, s'il fait au moins trois photos, sur une
   *    planche posée **juste après elle** : ce sont les photos de son passage,
   *    elles restent à côté de lui. Une ou deux photos en trop vont sur la page
   *    la plus proche qui a de la place, à défaut sur la planche la plus proche.
   * 5. **Jamais deux planches de suite** : il y a au plus une planche après
   *    chaque page de récit. Ce qui ne tient nulle part reste hors du carnet
   *    (`ecartees`), signalé.
   */
  function affecterPhotos({ pages, paragraphes, photos, maxParPage, capPremiere }) {
    const n = pages.length;
    const cap = pages.map((_, p) => (p === 0 && capPremiere != null ? capPremiere : maxParPage));
    const pageDuParagraphe = pageDeChaqueParagraphe(paragraphes, pages);

    const cible = photos.map((photo, rang) => {
      const par = photo.paragraphe;
      if (Number.isInteger(par) && par >= 0 && par < paragraphes.length) return pageDuParagraphe[par];
      return Math.min(n - 1, Math.floor((rang * n) / Math.max(1, photos.length)));
    });

    // Groupes de scène, dans l'ordre de leur première photo.
    const groupes = [];
    const parScene = new Map();
    photos.forEach((photo, rang) => {
      const cle = photo.scene ? `s:${normaliser(photo.scene)}` : `p:${rang}`;
      if (!parScene.has(cle)) {
        parScene.set(cle, { membres: [] });
        groupes.push(parScene.get(cle));
      }
      parScene.get(cle).membres.push(rang);
    });
    for (const g of groupes) g.cible = mode(g.membres.map((r) => cible[r]));
    groupes.sort((a, b) => a.cible - b.cible || b.membres.length - a.membres.length);

    const poses = pages.map(() => []);
    const surplus = pages.map(() => []);
    for (const g of groupes) {
      const place = Math.max(0, cap[g.cible] - poses[g.cible].length);
      g.membres.forEach((r, k) => (k < place ? poses[g.cible] : surplus[g.cible]).push(r));
    }
    // L'ouverture de chapitre montre 0 ou 2 photos, jamais une seule.
    if (capPremiere === 2 && poses[0].length === 1) surplus[0].unshift(poses[0].pop());

    const planches = pages.map(() => null);
    const distance = (a, b) => Math.abs(a - b) + (a < b ? 0.5 : 0); // à égalité, après plutôt qu'avant
    const peutRecevoir = (q) =>
      poses[q].length < cap[q] && !(q === 0 && capPremiere === 2 && poses[0].length === 0);

    // a. Le surplus va d'abord sur les pages de récit qui ont de la place, la
    //    plus proche du passage d'abord : chaque page de récit prend ses photos
    //    avant qu'une planche s'ouvre (LAYOUT_KB, règle 2 de la répartition).
    const restes = pages.map(() => []);
    surplus.forEach((liste, p) => {
      for (const r of liste) {
        const q = pages.map((_, k) => k).filter(peutRecevoir).sort((a, b) => distance(p, a) - distance(p, b))[0];
        if (q === undefined) restes[p].push(r);
        else poses[q].push(r);
      }
    });

    // b. Ce qui reste fait une planche juste après sa page d'origine, s'il y a
    //    de quoi (trois photos au moins) ; cinq au plus par planche.
    const ecartees = [];
    const orphelins = [];
    restes.forEach((liste, p) => {
      if (liste.length >= MIN_PAGE_PHOTOS) {
        planches[p] = liste.slice(0, PHOTOS_RENDUES.layout_photo_page);
        orphelins.push(...liste.slice(PHOTOS_RENDUES.layout_photo_page).map((r) => ({ r, p })));
      } else {
        orphelins.push(...liste.map((r) => ({ r, p })));
      }
    });

    // c. Une ou deux photos sans place rejoignent la planche la plus proche ;
    //    sans planche, les pages en cèdent pour en faire une de trois, juste
    //    après la page d'origine — plutôt que de perdre une photo.
    for (const { r, p } of orphelins) {
      const q = planches
        .map((pl, k) => ({ pl, k }))
        .filter(({ pl }) => pl && pl.length < PHOTOS_RENDUES.layout_photo_page)
        .sort((a, b) => distance(p, a.k) - distance(p, b.k))[0];
      if (q) q.pl.push(r);
      else ecartees.push({ r, p });
    }
    if (ecartees.length && ecartees.length < MIN_PAGE_PHOTOS) {
      const origine = ecartees[0].p;
      const manque = MIN_PAGE_PHOTOS - ecartees.length;
      const donneuses = pages
        .map((_, k) => k)
        // Une page qui cède garde au moins une photo : vider une page de récit
        // pour remplir une planche, c'est le « texte nu puis pile d'images »
        // que LAYOUT_KB proscrit.
        .filter((k) => poses[k].length > (k === 0 && capPremiere === 2 ? 2 : 1))
        .sort((a, b) => distance(origine, a) - distance(origine, b));
      const repris = [];
      for (const k of donneuses) {
        // Une ouverture de chapitre garde ses deux photos ou n'en garde aucune.
        if (k === 0 && capPremiere === 2) continue;
        while (repris.length < manque && poses[k].length > 1) repris.push(poses[k].pop());
        if (repris.length === manque) break;
      }
      if (repris.length === manque && !planches[origine]) {
        planches[origine] = [...ecartees.map((e) => e.r), ...repris];
        ecartees.length = 0;
      } else {
        for (const r of repris.reverse()) poses[donneuses.find((k) => poses[k].length < cap[k]) ?? 0].push(r);
      }
    }

    // Chaque page garde ses photos dans l'ordre du voyage.
    const ordre = (liste) => [...liste].sort((a, b) => a - b).map((r) => photos[r]);
    return {
      recit: poses.map(ordre),
      planches: planches.map((pl) => (pl ? ordre(pl) : null)),
      ecartees: ecartees.map((e) => photos[e.r]),
    };
  }

  /* ------------------------------------------- composition des doubles pages */

  /**
   * La composition d'une page, telle qu'on la voit d'un coup d'œil. Deux
   * layouts qui se ressemblent comptent pour un : `layout_split_left` sans fun
   * fact et `layout_collage` à deux photos donnent la même page (récit pleine
   * largeur, deux photos dessous).
   */
  function composition(plan) {
    if (plan.genre === "planche") return "planche";
    // Un encart change la page : la carte info se voit avant le texte.
    const encart = plan.encart ? "+encart" : "";
    if (plan.layout === "layout_chapter_map") return `carte${encart}`;
    if (plan.layout === "layout_hero_top") return "hero";
    if (plan.layout === "layout_trio_portrait" || plan.layout === "layout_trio_landscape") return plan.layout;
    const n = plan.photos.length;
    if (n === 0) return `texte${encart}`;
    if (n === 1) return `texte+photo${encart}`;
    return (n === 2 ? "bande2" : "bande3") + encart;
  }

  function heroAdmis(plan) {
    if (plan.photos.length !== 1) return false;
    const [photo] = plan.photos;
    const lisible =
      !photo.format || rognage(photo.format, FORMATS_EMPLACEMENTS.layout_hero_top[1][0]) <= MAX_ROGNAGE;
    return lisible && signes(plan.texte) <= CAPACITE_PAGE.layout_hero_top[plan.sorte];
  }

  function recalculer(plan) {
    if (plan.genre !== "recit" || plan.layout === "layout_chapter_map") return;
    plan.layout = layoutDeRecit(plan.photos, plan.texte, plan.sorte, plan.ouvreLeCarnet);
  }

  /**
   * Deux pages qui se font face n'ont jamais la même composition (« Consignes
   * IA », Notion : « Les deux pages d'une même double page n'ont jamais la même
   * composition »).
   *
   * Les doubles pages sont celles du livre imprimé : `pagesAvant` pages
   * précèdent la première page d'étape (le colophon, qui est la page 1, à
   * droite). Pour chaque double page dont les deux côtés se ressemblent, dans
   * cet ordre :
   *
   * 1. une page à une photo passe de la grande photo en tête à la photo
   *    flottante, ou l'inverse quand la photo et le texte le permettent ;
   * 2. deux pages de la même étape échangent une photo — de préférence une
   *    photo qui illustre le passage de la page qui la reçoit, ou de la même
   *    scène que ses photos — pour que l'une en porte une de plus que l'autre ;
   * 3. sinon on laisse : deux pages de texte sans photo, ou deux ouvertures de
   *    chapitre, n'ont pas d'autre composition possible.
   */
  function varierDoublesPages(plans, pagesAvant) {
    const gauche = (i) => (pagesAvant + 1 + i) % 2 === 0;
    let restants = 0;
    for (let i = 0; i + 1 < plans.length; i += 1) {
      if (!gauche(i)) continue;
      const a = plans[i];
      const b = plans[i + 1];
      if (composition(a) !== composition(b)) continue;
      if (a.genre !== "recit" || b.genre !== "recit") continue;

      // 1. Grande photo en tête ↔ photo flottante.
      let regle = false;
      for (const p of [b, a]) {
        if (p.photos.length !== 1 || p.layout === "layout_chapter_map") continue;
        const avant = p.layout;
        if (p.layout === "layout_hero_top") p.layout = p.ouvreLeCarnet ? "layout_story_opener" : "layout_story_facts";
        else if (heroAdmis(p)) p.layout = "layout_hero_top";
        if (p.layout !== avant && composition(a) !== composition(b)) {
          regle = true;
          break;
        }
        p.layout = avant;
      }
      if (regle) continue;

      // 2. Une photo passe d'une page à l'autre, dans la même étape.
      if (a.etape === b.etape && a.layout !== "layout_chapter_map" && b.layout !== "layout_chapter_map") {
        for (const [donne, recoit] of [[a, b], [b, a]]) {
          if (!donne.photos.length || recoit.photos.length >= recoit.capPhotos) continue;
          const scenes = new Set(recoit.photos.map((ph) => normaliser(ph.scene)).filter(Boolean));
          const choix =
            donne.photos.findIndex((ph) => recoit.paragraphes.includes(ph.paragraphe)) >= 0
              ? donne.photos.findIndex((ph) => recoit.paragraphes.includes(ph.paragraphe))
              : donne.photos.findIndex((ph) => ph.scene && scenes.has(normaliser(ph.scene))) >= 0
                ? donne.photos.findIndex((ph) => ph.scene && scenes.has(normaliser(ph.scene)))
                : donne.photos.length - 1;
          const [photo] = donne.photos.splice(choix, 1);
          recoit.photos.push(photo);
          recalculer(donne);
          recalculer(recoit);
          if (composition(a) !== composition(b)) {
            regle = true;
            break;
          }
          recoit.photos.pop();
          donne.photos.splice(choix, 0, photo);
          recalculer(donne);
          recalculer(recoit);
        }
      }
      if (!regle) restants += 1;
    }
    return restants;
  }

  /* ---------------------------------------------------------- les encarts --- */

  /** 140 caractères : la limite de `payloadValidator.ts` (`funFactChars`). */
  const MAX_SIGNES_ENCART = 140;
  /** Sous cette note, aucun encart : un encart de remplissage coûte plus qu'il ne rapporte. */
  const SEUIL_PERTINENCE = 7;
  /** Un encart toutes les trois pages au plus — LAYOUT_KB, et le réglage de l'app. */
  const ECART_ENCARTS = 3;
  const TITRES_ENCART = ["Fun fact", "Infos", "Culture générale", "Chiffres clés"];

  /** L'encart proposé par l'analyse d'étape, s'il est imprimable et assez pertinent. */
  function encartDe(analyse) {
    const f = analyse?.funFact;
    const texte = typeof f?.texte === "string" ? f.texte.replace(/\s+/g, " ").trim() : "";
    const pertinence = Number(f?.pertinence);
    if (!texte || texte.length > MAX_SIGNES_ENCART || !(pertinence >= SEUIL_PERTINENCE)) return null;
    return {
      texte,
      titre: TITRES_ENCART.includes(f.titre) ? f.titre : "Fun fact",
      registre: normaliser(f.registre),
      paragraphe: Number.isInteger(f.paragraphe) ? f.paragraphe : null,
      pertinence,
    };
  }

  /** Ce qui a manqué au fun fact d'une étape pour être imprimé. */
  function raisonSansEncart(analyse) {
    const f = analyse?.funFact;
    if (!analyse) return "étape pas encore analysée";
    const texte = typeof f?.texte === "string" ? f.texte.replace(/\s+/g, " ").trim() : "";
    if (!texte) return "l'analyse n'a proposé aucun fun fact";
    if (texte.length > MAX_SIGNES_ENCART) return `fun fact trop long (${texte.length} signes, ${MAX_SIGNES_ENCART} au plus)`;
    return `fun fact noté ${Number(f?.pertinence) || 0}/10, sous le seuil de ${SEUIL_PERTINENCE}`;
  }

  /**
   * La page peut-elle porter l'encart sans perdre une ligne de récit ? Plafonds
   * relevés par `calibrate-lengths.ts` :
   *
   * - récit avec 0 ou 1 photo : l'encart se pose dans la zone flottante, à côté
   *   de la photo, sans rien coûter (560 / 2 paragraphes sous un bandeau, 880
   *   sur une page de suite). Une grande photo en tête n'a pas cette zone : la
   *   page passe à la photo flottante ;
   * - deux photos (`layout_split_left`) : la colonne de récit se rétrécit, 240 ;
   * - ouverture de chapitre avec deux photos : 120 ;
   * - trois photos (`layout_collage`) ou carte seule : pas de place prévue.
   */
  function peutPorterEncart(plan) {
    if (plan.genre !== "recit" || !plan.texte.length) return false;
    const n = signes(plan.texte);
    if (plan.layout === "layout_chapter_map") return plan.photos.length === 2 && n <= 120;
    if (plan.photos.length <= 1) return true;
    return plan.photos.length === 2 && n <= 240;
  }

  /**
   * Quels encarts s'impriment, et sur quelle page (LAYOUT_KB § « Les fun facts
   * — dosage et matière ») :
   *
   * - un par étape au plus, sur la page du passage dont il vient quand elle peut
   *   le porter, sinon sur la première page de l'étape qui le peut ;
   * - trois pages au moins d'un encart au suivant : parmi les candidats, on
   *   garde la combinaison la mieux notée qui respecte cet écart ;
   * - jamais deux encarts du même registre à la suite : le moins bien noté
   *   s'efface.
   *
   * Pose `plan.encart` sur les pages retenues et renvoie leur nombre.
   */
  function placerEncarts(plans, etapes, journal = () => {}) {
    const candidats = [];
    // Pourquoi une étape n'a pas d'encart : le journal de l'atelier le dit.
    const raisons = [];
    etapes.forEach((etape, e) => {
      const encart = encartDe(etape.analyse);
      if (!encart) {
        raisons.push(`étape ${e + 1} : ${raisonSansEncart(etape.analyse)}`);
        return;
      }
      const pages = plans.map((plan, i) => ({ plan, i })).filter(({ plan }) => plan.etape === e && peutPorterEncart(plan));
      const hote = pages.find(({ plan }) => plan.paragraphes.includes(encart.paragraphe)) || pages[0];
      if (hote) candidats.push({ i: hote.i, encart, e });
      else raisons.push(`étape ${e + 1} : aucune page n'a la place (trois photos, ou deux à côté d'un récit de plus de 240 signes)`);
    });

    // La meilleure somme des notes sous la contrainte d'écart : un choix
    // pondéré d'intervalles, les candidats étant déjà dans l'ordre des pages.
    const meilleur = [0];
    const pris = [];
    candidats.forEach((c, k) => {
      let j = k - 1;
      while (j >= 0 && candidats[j].i > c.i - ECART_ENCARTS) j -= 1;
      const avec = c.encart.pertinence + meilleur[j + 1];
      pris[k] = { avec: avec > meilleur[k], j };
      meilleur[k + 1] = Math.max(meilleur[k], avec);
    });
    let retenus = [];
    for (let k = candidats.length - 1; k >= 0; ) {
      if (pris[k].avec) {
        retenus.unshift(candidats[k]);
        k = pris[k].j;
      } else k -= 1;
    }

    // Deux registres identiques à la suite : on garde le mieux noté.
    retenus = retenus.reduce((liste, c) => {
      const avant = liste[liste.length - 1];
      if (!avant || !c.encart.registre || avant.encart.registre !== c.encart.registre) return [...liste, c];
      return c.encart.pertinence > avant.encart.pertinence ? [...liste.slice(0, -1), c] : liste;
    }, []);

    for (const c of candidats) {
      if (!retenus.includes(c)) raisons.push(`étape ${c.e + 1} : écarté au profit d'un voisin mieux noté (trois pages d'écart, jamais deux du même registre)`);
    }
    if (raisons.length) journal(`fun facts non imprimés — ${raisons.join(" ; ")}.`);

    for (const { i, encart } of retenus) {
      const plan = plans[i];
      plan.encart = encart;
      if (plan.layout === "layout_hero_top") plan.layout = plan.ouvreLeCarnet ? "layout_story_opener" : "layout_story_facts";
    }
    return retenus.length;
  }

  /* ------------------------------------------------------------ le carnet --- */

  const drapeaux = (actif) => ({
    layout_chapter_map: actif === "layout_chapter_map",
    layout_story_opener: actif === "layout_story_opener",
    layout_story_facts: actif === "layout_story_facts",
    layout_hero_top: actif === "layout_hero_top",
    layout_split_left: actif === "layout_split_left",
    layout_collage: actif === "layout_collage",
    layout_trio_portrait: actif === "layout_trio_portrait",
    layout_trio_landscape: actif === "layout_trio_landscape",
    layout_photo_page: actif === "layout_photo_page",
  });

  /**
   * Les pages d'étape du carnet, prêtes pour `days[]`.
   *
   * `etapes` : `{ titre, lieu, dateLongue, numero, lieuComplet, recit,
   * photos: [{ id, src, format, groupe }], analyse }` — `analyse` est la réponse
   * de l'analyse d'étape (`consigneAnalyseEtape`), ou `null`.
   * `options` : `{ contours, dessinerCarte, pagesAvant, funFacts, journal }` —
   * `funFacts` est le réglage « Insérer des Fun facts » du carnet : coupé,
   * aucun encart.
   */
  function composerJours(etapes, options = {}) {
    const { contours = null, dessinerCarte = null, pagesAvant = 1, funFacts = false, journal = () => {} } = options;
    const plans = [];
    const chapitresPasses = [];
    const lieux = lieuxDuVoyage(etapes, contours);
    let lieuPrecedent = null;
    // Séjour en un seul lieu : pays dont la carte du pays est déjà passée,
    // lieux déjà nommés, et le parcours en ville, dans l'ordre.
    const sejoursOuverts = new Set();
    const villeDuSejour = new Map();
    const titreDuSejour = new Map();
    const dejaPasses = new Set();
    const parcoursEnVille = [];

    etapes.forEach((etape, index) => {
      const analysePhotos = new Map((etape.analyse?.photos || []).map((ph) => [String(ph.id), ph]));
      const photos = etape.photos.map((photo) => {
        const lu = analysePhotos.get(String(photo.id)) || {};
        return {
          ...photo,
          paragraphe: Number.isInteger(lu.paragraphe) ? lu.paragraphe : null,
          scene: lu.scene || "",
          // Trois visages ou plus : une photo de groupe, qui ne se rogne pas.
          groupe: Boolean(photo.groupe) || Number(lu.personnes) >= 3,
        };
      });

      const paragraphes = enParagraphes(etape.recit);
      // Sans récit, une ou deux photos tiennent sur la page à bandeau ; de trois
      // à cinq, l'étape devient une planche ; au-delà, la page à bandeau en
      // porte aussi, pour ne rien perdre.
      const pages = paragraphes.length
        ? pagesDeRecit(paragraphes)
        : photos.length < MIN_PAGE_PHOTOS || photos.length > PHOTOS_RENDUES.layout_photo_page
          ? [[]]
          : [];

      // Chapitre : la première étape, puis chaque arrivée dans un nouveau lieu.
      // Pour un séjour en un seul lieu, chaque étape qui emmène le voyageur
      // ailleurs dans la ville : sa carte trace ses déplacements.
      const situeBrut = lieuSitue(etape.analyse, contours);
      const situe = situeBrut && { ...situeBrut, mode: modeArrivee(etape.analyse, situeBrut.nom) };
      const cleLieu = normaliser(situe?.nom || etape.lieu);
      const sejour = Boolean(situe && sejourUnique(lieux, situe.pays));
      let nouveauLieu = index === 0 || (cleLieu && cleLieu !== lieuPrecedent);
      if (cleLieu) lieuPrecedent = cleLieu;
      // Les lieux de l'étape pas encore passés, dans l'ordre du récit — sauf
      // la ville du séjour elle-même (le lieu principal de sa première étape),
      // que la carte du pays situe et qui n'est pas un déplacement.
      let nouveauxEnVille = [];
      if (sejour) {
        if (!villeDuSejour.has(situe.pays)) {
          villeDuSejour.set(situe.pays, cleLieu);
          titreDuSejour.set(situe.pays, situe.nom || etape.lieu);
        }
        const vus = new Set([villeDuSejour.get(situe.pays)]);
        nouveauxEnVille = [situe, ...(etape.analyse?.lieux || []).map((l) => lieuSitue({ lieu: l }, contours))]
          .filter((l) => l && l.pays === situe.pays)
          .map((l) => (l === situe ? l : { ...l, mode: modeArrivee(etape.analyse, l.nom) }))
          .filter((l) => {
            const cle = normaliser(l.nom);
            if (!cle || vus.has(cle) || dejaPasses.has(cle)) return false;
            vus.add(cle);
            return true;
          });
        nouveauLieu = !sejoursOuverts.has(situe.pays) || nouveauxEnVille.length > 0;
      }
      let chapitre = Boolean(nouveauLieu && situe && dessinerCarte && pages.length && paragraphes.length);
      let capPremiere = null;
      if (chapitre) {
        const texte0 = signes(pages[0]);
        const deuxPhotos = texte0 <= CAPACITE_CHAPITRE.deuxPhotos && photos.length >= 2;
        // Une étape d'une seule page ne sacrifie pas ses photos à la carte :
        // ses photos n'auraient nulle part où aller, sauf une planche collée à
        // une page de texte nu — ce que LAYOUT_KB proscrit.
        if (texte0 > CAPACITE_CHAPITRE.sansPhoto) chapitre = false;
        else if (pages.length === 1 && photos.length > 0 && !deuxPhotos) chapitre = false;
        else capPremiere = deuxPhotos ? 2 : 0;
      }

      const maxParPage = photosParPageDeRecit(photos);
      let repartition = pages.length
        ? affecterPhotos({ pages, paragraphes, photos, maxParPage, capPremiere })
        : { recit: [], planches: [photos.slice(0, PHOTOS_RENDUES.layout_photo_page)], ecartees: photos.slice(PHOTOS_RENDUES.layout_photo_page) };
      // Une carte ne coûte jamais une photo, ni une page de récit sans image à
      // côté d'une planche : si l'ouverture de chapitre fait l'un ou l'autre et
      // que l'étape s'en passe sans carte, elle s'ouvre sans carte.
      const defauts = (r) =>
        r.ecartees.length * 10 +
        (r.planches.some(Boolean) ? r.recit.filter((liste, p) => !liste.length && !(p === 0 && chapitre)).length : 0);
      if (chapitre && defauts(repartition) > 0) {
        const sansCarte = affecterPhotos({ pages, paragraphes, photos, maxParPage, capPremiere: null });
        if (defauts(sansCarte) < defauts(repartition)) {
          chapitre = false;
          capPremiere = null;
          repartition = sansCarte;
        }
      }
      if (repartition.ecartees.length) {
        journal(
          `étape ${index + 1} : ${repartition.ecartees.length} photo(s) laissée(s) hors du carnet — ` +
            "plus de photos que ses pages ne peuvent en porter sans aligner deux planches.",
        );
      }

      let carte = "";
      if (chapitre) {
        let requete;
        if (sejour && !sejoursOuverts.has(situe.pays)) {
          // Première carte d'un séjour en un seul lieu : le pays entier, la
          // ville située dedans.
          requete = {
            regions: [situe.pays],
            cadre: cadreDuPays(situe.pays, contours, situe),
            points: [{ label: situe.nom || etape.lieu, lat: situe.lat, lon: situe.lon }],
          };
        } else if (sejour) {
          // Les suivantes : la ville, les lieux de l'étape nommés, ceux des
          // étapes précédentes en petits points, et le trajet qui les relie.
          const montres = nouveauxEnVille.slice(0, MAX_NOUVEAUX_VILLE);
          const passes = parcoursEnVille.slice(-(MAX_POINTS_CARTE - montres.length));
          requete = {
            regions: [situe.pays],
            cadre: cadreDuVoyage(lieux, situe.pays, contours, CADRE_MIN_VILLE),
            points: [
              ...passes.map((c) => ({ label: c.nom, lat: c.lat, lon: c.lon, secondaire: true, mode: c.mode })),
              ...montres.map((c) => ({ label: c.nom, lat: c.lat, lon: c.lon, mode: c.mode })),
            ],
            ville: true,
            titre: titreDuSejour.get(situe.pays) || "",
          };
        } else {
          const passes = chapitresPasses
            .filter((c) => c.pays === situe.pays && normaliser(c.nom) !== cleLieu)
            .slice(-(MAX_POINTS_CARTE - 1));
          requete = {
            regions: [situe.pays],
            // Cadrée sur ce que le voyage parcourt dans le pays, pas sur le pays entier.
            cadre: cadreDuVoyage(lieux, situe.pays, contours),
            points: [
              ...passes.map((c) => ({ label: c.nom, lat: c.lat, lon: c.lon, secondaire: true, mode: c.mode })),
              { label: situe.nom || etape.lieu, lat: situe.lat, lon: situe.lon, mode: situe.mode },
            ],
          };
        }
        try {
          carte = dessinerCarte(requete);
        } catch (erreur) {
          journal(`étape ${index + 1} : carte impossible (${erreur.message}), page ordinaire.`);
          chapitre = false;
        }
        if (chapitre) {
          chapitresPasses.push(situe);
          if (sejour) sejoursOuverts.add(situe.pays);
        }
      }

      // Le parcours en ville avance à chaque étape, carte ou pas : une étape
      // sans carte (faute de place) a quand même eu lieu, et la carte suivante
      // en montre les lieux en petits points sur le trajet.
      if (sejour) {
        for (const l of nouveauxEnVille) {
          parcoursEnVille.push(l);
          dejaPasses.add(normaliser(l.nom));
        }
      }

      const paragraphesDeLaPage = pages.map(() => []);
      const pageDuParagraphe = pageDeChaqueParagraphe(paragraphes, pages);
      pageDuParagraphe.forEach((p, i) => paragraphesDeLaPage[p]?.push(i));

      let premierePlanche = true;
      const planche = (liste) => {
        const plan = { genre: "planche", etape: index, photos: liste, titre: premierePlanche ? etape.titre || "" : "" };
        premierePlanche = false;
        return plan;
      };

      if (!pages.length) {
        for (const liste of repartition.planches) if (liste?.length) plans.push(planche(liste));
        return;
      }
      pages.forEach((texte, p) => {
        const plan = {
          genre: "recit",
          etape: index,
          rang: p,
          sorte: p === 0 ? "bandeau" : "suite",
          texte,
          photos: repartition.recit[p],
          paragraphes: paragraphesDeLaPage[p],
          capPhotos: p === 0 && capPremiere != null ? capPremiere : maxParPage,
          ouvreLeCarnet: index === 0 && p === 0,
          bandeau: p === 0 ? etape : null,
          carte: p === 0 && chapitre ? carte : "",
        };
        plan.layout = plan.carte ? "layout_chapter_map" : layoutDeRecit(plan.photos, texte, plan.sorte, plan.ouvreLeCarnet);
        plans.push(plan);
        if (repartition.planches[p]?.length) plans.push(planche(repartition.planches[p]));
      });
    });

    const restants = varierDoublesPages(plans, pagesAvant);
    if (restants) journal(`${restants} double(s) page(s) gardent la même composition faute d'alternative.`);

    // Les encarts en dernier : ils se posent sur des pages déjà composées, sans
    // déplacer ni photo ni ligne de récit, et ne font que distinguer davantage
    // deux pages en vis-à-vis.
    if (funFacts) journal(`${placerEncarts(plans, etapes, journal)} encart(s) « fun fact » dans le carnet.`);

    return plans.map((plan) => {
      if (plan.genre === "planche") {
        return {
          title: plan.titre,
          body_html: "",
          ...drapeaux("layout_photo_page"),
          photos: placerPhotos("layout_photo_page", plan.photos),
          fun_facts: [],
          sticker_groups: [],
        };
      }
      const jour = {
        ...drapeaux(plan.layout),
        body_html: paragraphesEnHtml(plan.texte),
        photos: placerPhotos(plan.layout, plan.photos),
        fun_facts: plan.encart ? [plan.encart.texte] : [],
        // L'encart est écrit par le modèle : la page le dit, en petit
        // (LAYOUT_KB § « La mention généré par IA »).
        ...(plan.encart ? { fun_facts_title: plan.encart.titre, ai_note: "Fun fact rédigé par IA" } : {}),
        sticker_groups: [],
        ...(plan.carte ? { map_svg: plan.carte } : {}),
      };
      if (!plan.bandeau) return { title: "", ...jour };
      const e = plan.bandeau;
      return {
        title: e.titre,
        date: e.dateLongue,
        city: e.lieu || "",
        country: e.destination || "",
        day_intro: { day_number: e.numero, location: e.lieuComplet, date: e.dateLongue },
        ...jour,
      };
    });
  }

  const api = {
    SIGNES_PAR_PARAGRAPHE,
    MAX_ROGNAGE,
    enParagraphes,
    pagesDeRecit,
    affecterPhotos,
    placerPhotos,
    varierDoublesPages,
    placerEncarts,
    cadreDuVoyage,
    cadreDuPays,
    cadresDesCartes,
    sejourUnique,
    lieuxDuVoyage,
    composition,
    composerJours,
    paragraphesEnHtml,
    rognage,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.MiseEnPage = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
