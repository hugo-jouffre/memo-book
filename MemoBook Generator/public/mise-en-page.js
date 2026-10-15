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
    layout_recit_photo: 1,
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
  // Recalibré le 12/10/2026 pour les marges de reliure (colonne de 349 pt au
  // lieu de 360) : environ 3 % de signes en moins par page.
  const CAPACITE_PAGE = {
    defaut: { bandeau: 540, suite: 860 },
    layout_hero_top: { bandeau: 380, suite: 660 },
    // Pages de suite seulement : sous un bandeau, les trois photos n'ont plus
    // leur hauteur. Mesuré le 08/10/2026 (`calibrate-lengths.ts --filtre
    // trio`) : 440 signes en deux paragraphes avant que les photos cèdent,
    // 410 avec les marges de reliure.
    layout_trio: { bandeau: 0, suite: 410, paragraphes: 2 },
    // Le récit qui contourne une grande photo (maquette faite à la main) tient
    // la capacité ordinaire ; avec le post-it « Infos » en bas à gauche, 800
    // signes sur une page de suite avant que le texte ne passe dessous
    // (mesuré le 12/10/2026).
    layout_recit_photo: { bandeau: 560, suite: 880, postit: { bandeau: 560, suite: 800 } },
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
   * `templates/travel-journal/index.html` : l'image remplit son emplacement,
   * le contour dessiné déborde autour sans compter (13/10/2026) — à remesurer
   * si la géométrie d'un gabarit change (LAYOUT_KB § « Rognage des photos »).
   */
  const FORMATS_EMPLACEMENTS = {
    // Une photo au-dessus de la carte, ou deux en bande sous un récit court.
    layout_chapter_map: { 1: [0.69], 2: [0.89, 0.89] },
    layout_story_opener: { 1: [1.02] },
    layout_story_facts: { 1: [1.02] },
    layout_hero_top: { 1: [1.31] },
    layout_split_left: { 2: [0.86, 0.86] },
    layout_collage: { 2: [0.86, 0.86], 3: [0.55, 0.55, 0.55] },
    // En haut, puis en bas à gauche et à droite (l'ordre de `photos[]`).
    layout_trio_portrait: { 3: [0.6, 0.68, 0.64] },
    layout_trio_landscape: { 3: [1.52, 0.64, 0.64] },
    layout_recit_photo: { 1: [0.51] },
    // Une seule photo en largeur sur la page d'album.
    album_paysage: { 1: [1.38] },
    // La photo en pleine page, bord à bord : le format de la page.
    pleine_page: { 1: [420 / 595] },
    layout_photo_page: {
      // Une ou deux photos : la page d'album de fin d'étape.
      1: [0.85],
      2: [0.96, 0.96],
      3: [0.71, 0.44, 1.59],
      4: [0.71, 0.44, 0.6, 0.95],
      5: [1.72, 1.38, 0.87, 0.87, 1.38],
    },
    // Cinq photos en deux colonnes décalées : deux portraits à gauche, puis
    // trois tirages à droite, celui du milieu plus étroit.
    planche_colonnes: { 5: [0.77, 0.77, 0.94, 0.77, 0.94] },
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
  /**
   * La place d'une photo réduite dans son emplacement, en pourcentages de
   * largeur et de hauteur : c'est le tirage qui porte le contour dessiné, pour
   * qu'il épouse l'image et non l'emplacement vide autour d'elle.
   */
  function tirageReduit(format, cadre) {
    return format > cadre ? [100, Math.round((cadre / format) * 100)] : [Math.round((format / cadre) * 100), 100];
  }

  function placerPhotos(layout, photos, imposes = null) {
    const formats = imposes || FORMATS_EMPLACEMENTS[layout]?.[photos.length];
    const cout = (ordre) =>
      ordre.reduce((total, photo, i) => total + rognage(photo.format, formats[i]), 0);
    // Des emplacements imposés viennent avec leur ordre, déjà le meilleur.
    const ordre =
      !imposes && formats && photos.every((p) => p.format)
        ? permutations(photos).reduce((meilleur, essai) => (cout(essai) < cout(meilleur) ? essai : meilleur))
        : photos;

    return ordre.map((photo, i) => {
      const cadre = formats?.[i];
      if (photo.groupe || rognage(photo.format, cadre) > MAX_ROGNAGE) {
        return { url: photo.src, fit: "contain", ...(photo.format && cadre ? { tirage: tirageReduit(photo.format, cadre) } : {}) };
      }
      if (photo.format && cadre && photo.format < cadre) return { url: photo.src, focus: "50% 30%" };
      return photo.src;
    });
  }

  /**
   * Les photos rendues d'une page. Quand le fun fact y prend l'emplacement
   * d'une photo (`plan.caseEncart`), les photos vont, dans l'ordre retenu,
   * dans les emplacements qu'il laisse : le gabarit les lit dans l'ordre des
   * emplacements, en sautant celui du fun fact.
   */
  function photosRendues(plan, gabarit) {
    if (!plan.caseEncart) return placerPhotos(gabarit, plan.photos);
    const { c, ordre, gabarit: avecCase } = plan.caseEncart;
    const formats = FORMATS_EMPLACEMENTS[avecCase][plan.photos.length + 1].filter((_, i) => i !== c);
    return placerPhotos(avecCase, ordre.map((k) => plan.photos[k]), formats);
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
      // Une photo en hauteur : le récit la contourne (maquette faite à la main).
      if (recitPhotoAdmis(photo, texte, sorte)) return "layout_recit_photo";
      const heroLisible =
        !photo.format || rognage(photo.format, FORMATS_EMPLACEMENTS.layout_hero_top[1][0]) <= MAX_ROGNAGE;
      return heroLisible && signes(texte) <= CAPACITE_PAGE.layout_hero_top[sorte] ? "layout_hero_top" : parDefaut;
    }
    if (nbPhotos === 2) return "layout_split_left";
    return "layout_collage";
  }



  /** Une étiquette de titre posée sur une photo ne dépasse pas une ligne courte. */
  const MAX_SIGNES_ETIQUETTE = 30;

  /**
   * L'étiquette de titre d'une photo (« Rizières de Banaue ») : la `legende`
   * que l'analyse propose, à défaut sa `scene` avec une majuscule — si elle
   * tient sur une ligne courte. Sinon, pas d'étiquette.
   */
  function etiquetteDe(lu) {
    for (const brut of [lu?.legende, lu?.scene]) {
      const t = typeof brut === "string" ? brut.replace(/\s+/g, " ").trim() : "";
      if (t && t.length <= MAX_SIGNES_ETIQUETTE) return t[0].toUpperCase() + t.slice(1);
    }
    return "";
  }

  /** Les coins où poser le scotch, tour à tour d'une photo à l'autre. */
  const COINS_SCOTCH = ["top-left", "top-right", "top", "bottom-right", "bottom-left"];

  /**
   * L'habillage des photos rendues d'une page (Hugo, 12/10/2026 : « toujours
   * tout ») : chaque photo a son scotch — sauf une photo réduite sans être
   * rognée, dont le cadre épouse l'image, et la pleine page —, et la photo
   * choisie pour la double page porte son étiquette de titre.
   */
  function habillerPhotos(plan, rendues, rangPage) {
    const etiquetee = plan.photos.find((p) => p.id === plan.etiquette);
    return rendues.map((item, k) => {
      const objet = typeof item === "string" ? { url: item } : { ...item };
      if (objet.fit !== "contain" && !plan.pleinePage) objet.tape_corner = COINS_SCOTCH[(rangPage + k) % COINS_SCOTCH.length];
      if (etiquetee && objet.url === etiquetee.src) objet.label = etiquetee.legende;
      return objet;
    });
  }

  /**
   * Une photo en hauteur que le récit peut contourner : son emplacement est
   * très étroit (format 0,51), une photo carrée ou en largeur y perdrait plus
   * d'un tiers. Le texte, lui, tient la capacité ordinaire de la page.
   */
  function recitPhotoAdmis(photo, texte, sorte) {
    if (!photo?.format || photo.groupe) return false;
    const cap = CAPACITE_PAGE.layout_recit_photo;
    return (
      rognage(photo.format, FORMATS_EMPLACEMENTS.layout_recit_photo[1][0]) <= MAX_ROGNAGE &&
      signes(texte) <= cap[sorte] &&
      texte.length <= PARAGRAPHES_PAR_PAGE[sorte]
    );
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
   * ou journée ordinaire »). 500 : c'est le dernier palier où le calibrage du
   * 12/10 (marges de reliure) ne relève aucun débordement.
   */
  const CAPACITE_CHAPITRE = { sansPhoto: 500, deuxPhotos: 300 };

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
   * Répartit les photos d'une étape entre ses pages de récit ; ce qui n'y tient
   * pas va **en fin d'étape** (`fin`), sur les pages de photos qui suivent le
   * récit — jamais entre deux pages de récit (LAYOUT_KB § « Structure d'une
   * étape »).
   *
   * 1. **Chaque photo vise la page du passage qu'elle illustre** — le
   *    paragraphe que l'analyse lui a attribué. Sans analyse, ou sans
   *    paragraphe, elle vise la page qui correspond à son rang dans l'étape :
   *    les premières photos sur la première page, et ainsi de suite.
   * 2. **Les photos d'une même scène restent ensemble** (même arrière-plan,
   *    même libellé `scene`) : le groupe vise la page que vise la majorité de
   *    ses photos, et il ne se coupe que s'il dépasse ce qu'une page porte.
   * 3. La page `p` porte au plus `caps[p]` photos. L'ouverture de chapitre en
   *    porte une au-dessus de sa carte, ou deux en bande sous un récit court
   *    (`chapitreDeux`).
   * 4. Le surplus d'une page va sur la page de récit la plus proche qui a de la
   *    place, puis en fin d'étape. Chaque liste garde l'ordre du voyage.
   */
  function affecterPhotos({ pages, paragraphes, photos, caps }) {
    const n = pages.length;
    const cap = caps;
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
    const distance = (a, b) => Math.abs(a - b) + (a < b ? 0.5 : 0); // à égalité, après plutôt qu'avant
    const peutRecevoir = (q) => poses[q].length < cap[q];

    // Le surplus va d'abord sur les pages de récit qui ont de la place, la
    // plus proche du passage d'abord ; le reste, en fin d'étape.
    const fin = [];
    surplus.forEach((liste, p) => {
      for (const r of liste) {
        const q = pages.map((_, k) => k).filter(peutRecevoir).sort((a, b) => distance(p, a) - distance(p, b))[0];
        if (q === undefined) fin.push(r);
        else poses[q].push(r);
      }
    });
    const ordre = (liste) => [...liste].sort((a, b) => a - b).map((r) => photos[r]);
    return { recit: poses.map(ordre), fin: ordre(fin) };
  }

  /**
   * Les coupes possibles d'un paragraphe, de la meilleure à la pire : une fin
   * de phrase (chaque morceau garde 40 signes au moins), une virgule (60), un
   * espace (80) — et ce que chacune coûte de plus qu'une fin de phrase.
   */
  const COUPES = [
    { motif: /[.!?…]\s/g, min: 40, cout: 0 },
    { motif: /,\s/g, min: 60, cout: 25 },
    { motif: / /g, min: 80, cout: 60 },
  ];

  /**
   * Coupe un paragraphe au plus près de `cible` signes, sans dépasser `max` :
   * de préférence sur une fin de phrase, même un peu plus loin qu'une virgule
   * ou un espace. `null` s'il n'y a pas de coupe possible.
   */
  function couperPres(paragraphe, cible, max) {
    let meilleure = null;
    for (const { motif, min, cout } of COUPES) {
      for (const m of paragraphe.matchAll(motif)) {
        const c = m.index + m[0].length;
        if (c < min || c > max || paragraphe.length - c < min) continue;
        const note = Math.abs(c - cible) + cout;
        if (!meilleure || note < meilleure.note) meilleure = { c, note };
      }
    }
    if (!meilleure) return null;
    return [paragraphe.slice(0, meilleure.c).trim(), paragraphe.slice(meilleure.c).trim()];
  }

  /**
   * Répartit le récit sur exactement `k` pages, chacune remplie à peu près
   * dans la même proportion de ce qu'elle tient —
   * le scénario A : le texte qui dépassait à peine d'une page s'étale à parts
   * égales sur deux. `capacites[i]` : `{ signes, paragraphes }` de la page `i`.
   * Un paragraphe se coupe au besoin sur une fin de phrase (`couperAuPlus`).
   * `null` si le récit ne se partage pas ainsi (trop court pour `k` pages, ou
   * trop long pour leurs capacités).
   */
  function repartirRecit(paragraphes, k, capacites) {
    if (!paragraphes.length || k < 1) return null;
    const file = [...paragraphes];
    const pages = [];
    for (let i = 0; i < k; i += 1) {
      const cap = capacites[i];
      const page = [];
      if (i === k - 1) {
        page.push(...file.splice(0));
      } else {
        // Chaque page reçoit une part du reste à la mesure de ce qu'elle tient :
        // la colonne étroite d'une ouverture de chapitre en prend moins
        // qu'une page de suite pleine largeur.
        const restantes = capacites.slice(i).reduce((t, c) => t + c.signes, 0);
        const cible = ((signes(file) - (k - i - 1)) * cap.signes) / restantes;
        while (file.length && page.length < cap.paragraphes) {
          const actuel = page.length ? signes(page) + 1 : 0;
          const p = file[0];
          if (actuel + p.length <= Math.min(cap.signes, cible + 40)) {
            page.push(file.shift());
            continue;
          }
          // Trop long : on en coupe le début au plus près de la cible.
          const coupe = couperPres(p, Math.round(cible) - actuel, cap.signes - actuel);
          if (coupe) {
            page.push(coupe[0]);
            file[0] = coupe[1];
          } else if (!page.length && p.length <= cap.signes) {
            page.push(file.shift());
          }
          break;
        }
      }
      if (!page.length) return null;
      pages.push(page);
    }
    const derniere = pages[k - 1];
    if (signes(derniere) > capacites[k - 1].signes || derniere.length > capacites[k - 1].paragraphes) return null;
    return pages;
  }

  /** Répartit `n` photos sur `q` pages, au plus près de parts égales : 7 sur 2 → [4, 3]. */
  function partsEgales(n, q) {
    return Array.from({ length: q }, (_, i) => Math.floor(n / q) + (i < n % q ? 1 : 0));
  }

  /**
   * Ce que coûte une page de récit de plus pour une étape qui en a déjà deux
   * ou plus : un récit étiré laisse des pages à moitié vides. On ne le fait
   * que si rien d'autre n'atteint un nombre pair.
   */
  const ETIRER = 10;

  /**
   * Le corps du récit s'ajuste d'un point au plus (Hugo, 12/10/2026) :
   *
   * - **serré** (11 pt) : un récit qui dépasse de 8 % au plus ce que ses pages
   *   tiennent passe en 11 pt plutôt que de prendre une page de plus. Le 11 pt
   *   en tient bien davantage (mesuré au calibrage) ; 8 % est la limite qu'on
   *   s'impose pour que le récit ne paraisse pas tassé ;
   * - **ample** (13 pt) : une étape dont chaque page de récit est remplie à
   *   moins de 45 %, sans photo ni encart pour combler, passe en 13 pt.
   *
   * Toujours l'étape entière : un récit ne change pas de corps en tournant la
   * page.
   */
  const CORPS = { serre: 1.08, ample: 0.45 };

  /**
   * Une photo digne d'une pleine page : notée 9 au moins par l'analyse, pas
   * une photo de groupe (elle serait rognée), au format de la page à un tiers
   * près, et assez définie pour 154 × 216 mm à 200 dpi.
   */
  function pleinePageAdmise(photo) {
    if (!(photo.note >= 9) || photo.groupe || !photo.largeur || !photo.hauteur) return false;
    if (rognage(photo.format, FORMATS_EMPLACEMENTS.pleine_page[1][0]) > MAX_ROGNAGE) return false;
    const dpi = Math.min(photo.largeur / (154 / 25.4), photo.hauteur / (216 / 25.4));
    return dpi >= 200;
  }

  /** Une étape tient sur six pages au plus (Hugo, 12/10/2026)… */
  const MAX_PAGES_ETAPE = 6;
  /** …dont une double page de photos au plus en fin d'étape. */
  const MAX_PAGES_PHOTOS = 2;

  /**
   * Les seuils du contrôle qualité, ceux de `couverture.js` (`SEUILS`) : une
   * photo plus floue, plus sombre ou plus brûlée s'écarte la première.
   */
  const QUALITE = { nettete: 40, sombre: 45, clair: 215, ecretage: 0.25 };

  const defautDeQualite = (photo) => {
    const m = photo.mesure;
    if (!m) return false;
    return m.nettete < QUALITE.nettete || m.luminance < QUALITE.sombre || m.luminance > QUALITE.clair || m.ecretage > QUALITE.ecretage;
  };

  /**
   * Les photos d'une étape, de la première à écarter à la dernière (Hugo,
   * 12/10/2026) : les floues ou sombres, puis les doublons d'une même scène
   * (on garde la mieux notée), puis les moins bien notées. À note égale, la
   * plus tardive part d'abord.
   */
  function trierPourEcarter(photos) {
    const note = (p) => (Number.isFinite(p.note) ? p.note : 5);
    const meilleureDeScene = new Map();
    for (const p of photos) {
      const cle = normaliser(p.scene);
      if (!cle || defautDeQualite(p)) continue;
      const deja = meilleureDeScene.get(cle);
      if (!deja || note(p) > note(deja)) meilleureDeScene.set(cle, p);
    }
    const rang = (p) => {
      if (defautDeQualite(p)) return 0;
      const cle = normaliser(p.scene);
      if (cle && meilleureDeScene.get(cle) !== p) return 1;
      return 2;
    };
    return photos
      .map((p, i) => ({ p, i }))
      .sort((a, b) => rang(a.p) - rang(b.p) || note(a.p) - note(b.p) || b.i - a.i)
      .map(({ p }) => p);
  }

  /** Une page de photos en porte cinq au plus (`layout_photo_page`). */
  const MAX_PAGE_PHOTOS = 5;
  /** La planche qui ouvre une étape sans récit en porte quatre (`layout_photo_wall_intro`). */
  const MAX_PHOTOS_OUVERTURE = 4;

  /**
   * La structure d'une étape (LAYOUT_KB § « Structure d'une étape ») :
   *
   * - le récit d'un seul tenant, sur ses pages qui se suivent ;
   * - puis les pages de photos seules, **toujours après le texte** ;
   * - un **nombre de pages pair**.
   *
   * Le récit se répartit **à parts égales** sur ses pages : un récit qui
   * dépassait à peine d'une page ne laisse plus une page pleine et une page
   * presque vide. Puis on énumère les structures possibles :
   *
   * - **A** : toutes les photos avec le texte, pas de page de photos ;
   * - **B** : le texte avec une ou deux photos par page, puis une ou plusieurs
   *   pages de photos en fin d'étape.
   *
   * Le récit peut prendre une page de plus — c'est le scénario A d'une étape
   * courte, qui tient sur une page : son récit se partage en deux. Pour une
   * étape plus longue, ce n'est qu'un recours (`ETIRER`).
   *
   * Parmi les structures au nombre de pages pair, on garde celles qui en ont le
   * moins. Si A et B y sont toutes deux, on alterne d'une étape à l'autre dans
   * la même situation (`court` : le récit tient sur une page ; `impair`, `pair`
   * : son nombre de pages naturel), en commençant par A — `memoire` retient le
   * dernier choix. Puis le moins de défauts : une page de récit sans photo
   * quand l'étape en a, une page de photos qui n'en porte qu'une ou deux.
   */
  function structurerEtape({ paragraphes, pagesNaturelles, photos: toutes, maxParPage, chapitre, memoire }) {
    const T = pagesNaturelles.length;
    const capacites = (k, facteur = 1) =>
      Array.from({ length: k }, (_, i) => ({
        signes:
          Math.floor(
            ((i === 0 ? (chapitre ? CAPACITE_CHAPITRE.sansPhoto : CAPACITE_PAGE.defaut.bandeau) : CAPACITE_PAGE.defaut.suite) *
              facteur) /
              10,
          ) * 10,
        paragraphes: i === 0 ? PARAGRAPHES_PAR_PAGE.bandeau : PARAGRAPHES_PAR_PAGE.suite,
      }));
    // Le récit à parts égales sur ses pages (à défaut, rempli page après
    // page) ; et sur une page de plus — pour une étape courte, c'est le
    // scénario A ; pour une plus longue, un recours qui coûte (`ETIRER`).
    const decoupages = [
      { pages: repartirRecit(paragraphes, T, capacites(T)) || pagesNaturelles, plus: false },
    ];
    const etale = repartirRecit(paragraphes, T + 1, capacites(T + 1));
    if (etale) decoupages.push({ pages: etale, plus: true });
    // Et sur une page de moins, en corps serré : retenu seulement s'il fait
    // gagner des pages (voir plus bas).
    const serre = T > 1 ? repartirRecit(paragraphes, T - 1, capacites(T - 1, CORPS.serre)) : null;

    const candidatsPour = (photos, liste = decoupages) => {
    const N = photos.length;
    const candidats = [];
    const vus = new Set();
    for (const d of liste) {
      const k = d.pages.length;
      const chapitreDeux = chapitre && signes(d.pages[0]) <= CAPACITE_CHAPITRE.deuxPhotos && N >= 2;
      const base = d.pages.map((_, i) => (i === 0 && chapitre ? (chapitreDeux ? 2 : 1) : maxParPage));
      const capTotal = base.reduce((a, b) => a + b, 0);
      for (let garde = Math.min(N, capTotal); garde >= 0; garde -= 1) {
        // Toute la place quand les pages de récit gardent tout ce qu'elles
        // peuvent ; sinon on en retire une à une à la page qui en a le plus
        // (la plus loin à égalité), pour qu'aucune ne reste sans photo avant
        // les autres. La page de chapitre cède en dernier : sa carte tient la
        // page sans photo.
        const caps = [...base];
        let exces = garde === Math.min(N, capTotal) ? 0 : capTotal - garde;
        while (exces > 0) {
          let i = -1;
          caps.forEach((c, j) => {
            if (j === 0 && chapitre) return;
            if (c > 0 && (i < 0 || c >= caps[i])) i = j;
          });
          if (i < 0 && chapitre && caps[0] > 0) i = 0;
          if (i < 0) break;
          caps[i] -= 1;
          exces -= 1;
        }
        const affectee = affecterPhotos({ pages: d.pages, paragraphes, photos, caps });
        // Les photos suivent leur passage : un récit d'un seul paragraphe les
        // envoie toutes après la page de chapitre, qui resterait sans la photo
        // posée au-dessus de sa carte. Variante : la première photo de la page
        // suivante y remonte.
        const variantes = [affectee];
        const suivante = affectee.recit.findIndex((l, i) => i > 0 && l.length >= 2);
        if (chapitre && caps[0] > 0 && !affectee.recit[0].length && suivante > 0) {
          const recit = affectee.recit.map((l) => [...l]);
          recit[0].push(recit[suivante].shift());
          variantes.push({ recit, fin: affectee.fin });
        }
        for (const r of variantes) {
          const signature = `${k}|${r.recit.map((l) => l.map((p) => p.id).join(",")).join(";")}`;
          if (vus.has(signature)) continue;
          vus.add(signature);
          const qMin = Math.ceil(r.fin.length / MAX_PAGE_PHOTOS);
          for (let q = qMin; q <= Math.min(r.fin.length, qMin + 1); q += 1) {
            const tailles = partsEgales(r.fin.length, q);
            // La page de chapitre compte comme les autres : depuis le 13/10/2026
            // elle porte une photo au-dessus de sa carte.
            const sansPhoto = N ? r.recit.filter((l) => !l.length).length : 0;
            const cout =
              sansPhoto * 15 +
              tailles.reduce((c, t) => c + (t === 1 ? 8 : t === 2 ? 4 : 0), 0) +
              (d.plus && T > 1 ? ETIRER : 0);
            candidats.push({
              pages: d.pages,
              recit: r.recit,
              fin: r.fin,
              tailles,
              chapitreDeux,
              total: k + q,
              scenario: q > 0 ? "B" : "A",
              cout,
              ...(d.serre ? { serre: true } : {}),
            });
          }
        }
      }
    }
    return candidats;
    };

    // Six pages au plus, dont deux de photos (une double page) — à moins que
    // le récit seul n'en demande davantage. Quand les photos n'y tiennent pas,
    // on en écarte, la pire d'abord (`trierPourEcarter`), jusqu'à trouver une
    // structure au nombre de pages pair.
    const maxPages = Math.max(MAX_PAGES_ETAPE, T + (T % 2));
    const admis = (c) => c.total <= maxPages && c.tailles.length <= MAX_PAGES_PHOTOS;
    const pair = (c) => c.total % 2 === 0;
    let gardees = toutes;
    let candidats = candidatsPour(toutes).filter(admis);
    if (!candidats.some(pair)) {
      let essai = toutes;
      for (const pire of trierPourEcarter(toutes)) {
        essai = essai.filter((p) => p !== pire);
        const c = candidatsPour(essai).filter(admis);
        if (c.some(pair)) {
          gardees = essai;
          candidats = c;
          break;
        }
        if (!candidats.length && c.length) {
          gardees = essai;
          candidats = c;
        }
      }
    }
    const ecartees = toutes.filter((p) => !gardees.includes(p));

    const pairs = candidats.filter(pair);
    let valides = pairs.length ? pairs : candidats;
    // Le corps serré, s'il donne une étape paire plus courte que tout le reste.
    if (serre) {
      const serres = candidatsPour(gardees, [{ pages: serre, plus: false, serre: true }]).filter(admis).filter(pair);
      const plusCourt = Math.min(...valides.map((c) => c.total));
      if (serres.some((c) => c.total < plusCourt) || (!pairs.length && serres.length)) valides = serres;
    }
    const moins = Math.min(...valides.map((c) => c.total));
    let parmi = valides.filter((c) => c.total === moins);
    const situation = T <= 1 ? "court" : T % 2 ? "impair" : "pair";
    // A et B possibles au même nombre de pages : on alterne d'une étape à
    // l'autre dans la même situation, en commençant par A.
    if (parmi.some((c) => c.scenario === "A") && parmi.some((c) => c.scenario === "B")) {
      const voulu = memoire.get(situation) === "A" ? "B" : "A";
      parmi = parmi.filter((c) => c.scenario === voulu);
      memoire.set(situation, voulu);
    }
    return { ...parmi.sort((a, b) => a.cout - b.cout)[0], ecartees };
  }

  /**
   * Passe en corps ample (13 pt) les étapes dont chaque page de récit est
   * remplie à moins de 45 %, sans photo, sans encart, sans carte (`CORPS`).
   */
  function corpsAmple(plans) {
    const parEtape = new Map();
    for (const plan of plans) {
      if (plan.genre !== "recit") continue;
      if (!parEtape.has(plan.etape)) parEtape.set(plan.etape, []);
      parEtape.get(plan.etape).push(plan);
    }
    for (const pages of parEtape.values()) {
      const maigres = pages.every(
        (plan) =>
          !plan.taille &&
          !plan.photos.length &&
          !plan.encart &&
          !plan.quiz &&
          !plan.carte &&
          plan.texte.length &&
          signes(plan.texte) < CAPACITE_PAGE.defaut[plan.sorte] * CORPS.ample,
      );
      if (maigres) for (const plan of pages) plan.taille = "ample";
    }
  }

  /* ------------------------------------------- composition des doubles pages */

  /**
   * La composition d'une page, telle qu'on la voit d'un coup d'œil. Deux
   * layouts qui se ressemblent comptent pour un : `layout_split_left` sans fun
   * fact et `layout_collage` à deux photos donnent la même page (récit pleine
   * largeur, deux photos dessous).
   */
  function composition(plan) {
    if (plan.genre === "planche") return plan.colonnes ? "planche+colonnes" : "planche";
    // Un encart change la page : la carte info se voit avant le texte.
    const encart = plan.encart ? "+encart" : "";
    if (plan.layout === "layout_chapter_map") return `carte${encart}`;
    if (plan.layout === "layout_hero_top") return "hero";
    if (plan.layout === "layout_recit_photo") return `recit+photo${encart}`;
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

      // 1. Une page à une photo change de façon de la montrer : grande photo en
      //    tête, récit qui contourne une photo en hauteur, photo flottante.
      let regle = false;
      for (const p of [b, a]) {
        if (p.photos.length !== 1 || p.layout === "layout_chapter_map") continue;
        const avant = p.layout;
        const flottante = p.ouvreLeCarnet ? "layout_story_opener" : "layout_story_facts";
        const autres = [
          heroAdmis(p) ? "layout_hero_top" : null,
          recitPhotoAdmis(p.photos[0], p.texte, p.sorte) ? "layout_recit_photo" : null,
          flottante,
        ].filter((l) => l && l !== avant);
        for (const l of autres) {
          p.layout = l;
          if (composition(a) !== composition(b)) {
            regle = true;
            break;
          }
        }
        if (regle) break;
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
  /**
   * Les notes admises, dans l'ordre où on les essaie : d'abord les fun facts
   * notés 7 et plus ; une place restée vide se contente d'un 5 ou d'un 6.
   * Sous 5, jamais : un encart de remplissage coûte plus qu'il ne rapporte.
   */
  const SEUILS_PERTINENCE = [7, 5];
  /**
   * La promesse faite au voyageur qui allume les fun facts (Hugo, 13/10/2026) :
   * **à peu près un toutes les trois pages**. Deux encarts sont séparés de
   * trois pages, deux au moins et quatre au plus quand le carnet n'offre pas
   * mieux.
   */
  const ECART_ENCARTS = 3;
  const ECART_MIN = 2;
  const ECART_MAX = 4;

  /** Un fun fact proposé par l'analyse, s'il est imprimable. */
  function lireEncart(f) {
    const texte = typeof f?.texte === "string" ? f.texte.replace(/\s+/g, " ").trim() : "";
    const pertinence = Number(f?.pertinence);
    if (!texte || texte.length > MAX_SIGNES_ENCART || !Number.isFinite(pertinence)) return null;
    return {
      texte,
      // Le fun fact est un post-it « Infos », partout (Hugo, 12/10/2026).
      titre: "Infos",
      registre: normaliser(f.registre),
      paragraphe: Number.isInteger(f.paragraphe) ? f.paragraphe : null,
      pertinence,
    };
  }

  /**
   * Les fun facts d'une étape, du mieux noté au moins bon : la liste
   * `funFacts` de l'analyse — ou l'unique `funFact` d'une analyse plus
   * ancienne.
   */
  function encartsDe(analyse) {
    const bruts = Array.isArray(analyse?.funFacts) ? analyse.funFacts : analyse?.funFact ? [analyse.funFact] : [];
    return bruts
      .map(lireEncart)
      .filter((e) => e && e.pertinence >= SEUILS_PERTINENCE[SEUILS_PERTINENCE.length - 1])
      .sort((a, b) => b.pertinence - a.pertinence);
  }

  /** Ce qui a manqué aux fun facts d'une étape pour être imprimés. */
  function raisonSansEncart(analyse) {
    if (!analyse) return "étape pas encore analysée";
    const bruts = Array.isArray(analyse.funFacts) ? analyse.funFacts : analyse.funFact ? [analyse.funFact] : [];
    if (!bruts.length) return "l'analyse n'a proposé aucun fun fact";
    const trop = bruts.filter((f) => String(f?.texte || "").trim().length > MAX_SIGNES_ENCART).length;
    if (trop === bruts.length) return `fun fact trop long (${MAX_SIGNES_ENCART} signes au plus)`;
    return `fun fact(s) noté(s) sous ${SEUILS_PERTINENCE[SEUILS_PERTINENCE.length - 1]}/10`;
  }

  /**
   * La page peut-elle porter un encart sans perdre une ligne de récit ?
   * Plafonds relevés par `calibrate-lengths.ts` :
   *
   * - récit avec 0 ou 1 photo : l'encart se pose dans la zone flottante, à côté
   *   de la photo, sans rien coûter. Une grande photo en tête n'a pas cette
   *   zone : la page passe à la photo flottante ;
   * - deux photos (`layout_split_left`) : la colonne de récit se rétrécit, 230 ;
   * - ouverture de chapitre avec deux photos : 110 ;
   * - trois photos (`layout_collage`, trios) ou carte seule : pas de place
   *   dans la page.
   *
   * Et **à la place d'une photo** (Hugo, 14/10/2026) : le fun fact compte
   * alors comme une photo de plus. La page de k photos prend le gabarit de
   * k + 1, et l'encart occupe l'emplacement qu'aucune photo n'y tient
   * (`caseLibre`) — jamais par-dessus une photo. La planche d'ouverture d'une
   * étape a sa propre carte ; la pleine page, rien.
   *
   * Renvoie `"page"`, `"case"` ou `null`.
   */
  function placeEncart(plan) {
    if (plan.genre === "planche") {
      if (plan.ouverture) return "page";
      return caseLibre(plan) ? "case" : null;
    }
    if (plan.genre !== "recit" || !plan.texte.length) return null;
    // Le quiz a pris la zone flottante du bas : un seul bloc par page.
    if (plan.quiz) return null;
    const n = signes(plan.texte);
    if (plan.layout === "layout_chapter_map") return plan.photos.length === 2 && n <= 110 ? "page" : null;
    if (plan.layout === "layout_recit_photo") return n <= CAPACITE_PAGE.layout_recit_photo.postit[plan.sorte] ? "page" : null;
    if (plan.layout === "layout_trio_portrait" || plan.layout === "layout_trio_landscape") return null;
    if (plan.photos.length <= 1) return "page";
    if (plan.photos.length === 2 && n <= 230) return "page";
    return caseLibre(plan) ? "case" : null;
  }

  /**
   * Le gabarit d'une page quand le fun fact y prend la place d'une photo : la
   * planche de k + 1 photos, ou, sur une page de récit à deux photos, le
   * collage de trois. `null` si la page n'en a pas.
   */
  function gabaritAvecCase(plan) {
    if (plan.genre === "planche") {
      if (plan.pleinePage || plan.colonnes || plan.ouverture) return null;
      return FORMATS_EMPLACEMENTS.layout_photo_page[plan.photos.length + 1] ? "layout_photo_page" : null;
    }
    if (plan.genre === "recit" && plan.layout === "layout_split_left" && plan.photos.length === 2) return "layout_collage";
    return null;
  }

  /**
   * Les photos de la page dans le gabarit de k + 1 emplacements, l'encart
   * dans celui qui les rogne le moins : `{ rendues, caseEncart }`, où
   * `caseEncart` est le rang de l'emplacement de l'encart. `null` si une photo
   * y serait rognée au-delà du plafond — le fun fact ne prend pas une place
   * qui abîmerait une photo.
   */
  function photosAvecCase(plan) {
    const gabarit = gabaritAvecCase(plan);
    if (!gabarit) return null;
    const formats = FORMATS_EMPLACEMENTS[gabarit][plan.photos.length + 1];
    let meilleur = null;
    // À coût égal, le dernier emplacement : le fun fact ferme la bande ou la planche.
    for (let c = formats.length - 1; c >= 0; c -= 1) {
      const reste = formats.filter((_, i) => i !== c);
      const pertes = plan.photos.map((p) => (p.format && !p.groupe ? p.format : null));
      // Le meilleur ordre des photos dans les emplacements restants.
      for (const ordre of permutations(plan.photos.map((_, i) => i))) {
        const rognages = ordre.map((k, i) => (pertes[k] ? rognage(pertes[k], reste[i]) : 0));
        if (rognages.some((r) => r > MAX_ROGNAGE)) continue;
        const cout = rognages.reduce((a, b) => a + b, 0);
        if (!meilleur || cout < meilleur.cout) meilleur = { cout, c, ordre, gabarit };
      }
    }
    return meilleur;
  }

  /** La page a-t-elle un emplacement de photo libre pour le fun fact ? */
  const caseLibre = (plan) => photosAvecCase(plan) !== null;

  /**
   * Quels encarts s'impriment, et sur quelle page (LAYOUT_KB § « Les fun facts
   * — dosage et matière ») : **à peu près un toutes les trois pages**.
   *
   * On avance dans le carnet page par page. La prochaine place visée est trois
   * pages après le dernier encart (le premier, dans les trois premières
   * pages) ; parmi les pages qui peuvent le porter, de deux à quatre pages
   * après, on retient le meilleur couple page × fun fact de l'étape de la
   * page :
   *
   * - la page visée exactement, plutôt qu'une voisine — c'est la fréquence
   *   qu'on a promise ;
   * - la note — 7 et plus, puis 5 et 6 si rien d'autre ne tient ;
   * - la page du passage dont vient le fun fact ;
   * - une page de récit plutôt qu'une page de photos ;
   * - jamais deux encarts du même registre à la suite quand on peut l'éviter.
   *
   * Une étape peut en porter plusieurs : une longue étape en a autant que ses
   * pages en demandent. Faute de page pour le porter dans la fenêtre, on prend
   * la première qui le peut après elle.
   *
   * Pose `plan.encart` sur les pages retenues et renvoie leur nombre.
   */
  function placerEncarts(plans, etapes, journal = () => {}) {
    const restants = etapes.map((etape) => encartsDe(etape.analyse));
    const raisons = [];
    etapes.forEach((etape, e) => {
      if (!restants[e].length) raisons.push(`étape ${e + 1} : ${raisonSansEncart(etape.analyse)}`);
    });

    const hotes = plans
      .map((plan, i) => ({ plan, i, place: placeEncart(plan) }))
      .filter(({ place }) => place);
    const choisir = (candidats, cible, precedent) => {
      let meilleur = null;
      for (const seuil of SEUILS_PERTINENCE) {
        for (const { plan, i, place } of candidats) {
          for (const encart of restants[plan.etape] || []) {
            if (encart.pertinence < seuil) continue;
            // La promesse est une fréquence : une page d'écart à la cible coûte
            // 2,5 points de note — un 9 à côté cède à un 7 pile à sa place.
            // Le passage et la page de récit départagent le reste.
            const score =
              encart.pertinence -
              Math.abs(i - cible) * 2.5 +
              (plan.genre === "recit" && plan.paragraphes?.includes(encart.paragraphe) ? 0.5 : 0) +
              (place === "page" ? 0.2 : 0) -
              (precedent && encart.registre && encart.registre === precedent.registre ? 3 : 0);
            if (!meilleur || score > meilleur.score) meilleur = { plan, i, place, encart, score };
          }
        }
        if (meilleur) return meilleur;
      }
      return null;
    };

    let dernier = -ECART_ENCARTS;
    let precedent = null;
    const poses = [];
    for (;;) {
      const cible = dernier + ECART_ENCARTS;
      const fenetre = hotes.filter(({ i }) => i >= Math.max(0, dernier + ECART_MIN) && i <= dernier + ECART_MAX);
      let choix = choisir(fenetre, cible, precedent);
      if (!choix) {
        // Rien dans la fenêtre : la première page qui peut porter un encart
        // après elle.
        const apres = hotes.filter(({ i }) => i > dernier + ECART_MAX);
        for (const hote of apres) {
          choix = choisir([hote], hote.i, precedent);
          if (choix) break;
        }
      }
      if (!choix) break;
      choix.plan.encart = choix.encart;
      if (choix.place === "case") {
        const avecCase = photosAvecCase(choix.plan);
        choix.plan.caseEncart = avecCase;
        if (choix.plan.genre === "recit") choix.plan.layout = avecCase.gabarit;
      }
      restants[choix.plan.etape] = restants[choix.plan.etape].filter((x) => x !== choix.encart);
      poses.push(choix.i);
      dernier = choix.i;
      precedent = choix.encart;
    }

    for (const { plan } of hotes) {
      if (plan.encart && !plan.caseEncart && plan.layout === "layout_hero_top") {
        plan.layout = plan.ouvreLeCarnet ? "layout_story_opener" : "layout_story_facts";
      }
    }
    if (raisons.length) journal(`fun facts non imprimés — ${raisons.join(" ; ")}.`);
    if (poses.length > 1) {
      const pages = poses[poses.length - 1] - poses[0];
      journal(`fun facts : ${poses.length} encart(s), un toutes les ${(pages / (poses.length - 1)).toFixed(1).replace(".", ",")} pages.`);
    }
    return poses.length;
  }

  /* --------------------------------------------------------------- les quiz --- */

  /**
   * « Quiz intégrés à l'histoire » (Hugo, 15/10/2026) : **environ un quiz
   * toutes les trois étapes**, jamais deux étapes de suite, un par étape au
   * plus. Même mécanique que les encarts, à l'échelle des étapes : la
   * prochaine étape visée est trois étapes après le dernier quiz, et la
   * fenêtre va de deux à quatre.
   */
  const ECART_QUIZ = 3;
  const ECART_QUIZ_MIN = 2;
  const ECART_QUIZ_MAX = 4;

  /** Les bornes d'un quiz imprimable — celles de la rédaction (`QUIZ_LIMITS`, `redaction.ts`). */
  const MAX_SIGNES_QUESTION = 120;
  const MAX_SIGNES_CHOIX = 40;

  /** Pour comparer une réponse et un récit : sans accents, sans casse, espaces simples. */
  const aPlat = (t) =>
    String(t || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();

  /**
   * Le quiz d'une étape, s'il est imprimable, dans la forme du gabarit
   * (`{ question, choices, answer }`) : celui que l'app apporte déjà rédigé
   * (`etape.quiz`), sinon celui de l'analyse d'étape de l'atelier
   * (`analyse.quiz`, `{ question, choix, reponse }`, `consigneAnalyseEtape`).
   */
  function quizDe(etape) {
    const brut = etape?.quiz || etape?.analyse?.quiz;
    if (!brut || typeof brut !== "object") return null;
    const propre = (t) => (typeof t === "string" ? t.replace(/\s+/g, " ").trim() : "");
    const question = propre(brut.question);
    const choices = (Array.isArray(brut.choices) ? brut.choices : Array.isArray(brut.choix) ? brut.choix : []).map(propre);
    const answer = propre(brut.answer ?? brut.reponse);
    const valide =
      question &&
      question.length <= MAX_SIGNES_QUESTION &&
      choices.length >= 2 &&
      choices.length <= 4 &&
      choices.every((c) => c && c.length <= MAX_SIGNES_CHOIX) &&
      new Set(choices.map(aPlat)).size === choices.length &&
      choices.includes(answer);
    return valide ? { question, choices, answer } : null;
  }

  /**
   * La page peut-elle porter le quiz ? Le gabarit ne rend le quiz que sur la
   * page de récit par défaut, **à la place** de la zone flottante du bas
   * (photo et carte info) : seule une page sans photo, sans encart, sans
   * carte et sans champ à remplir l'accueille sans rien perdre. Et jamais la
   * page dont le récit donne la réponse (`agent-transcription-carnet.md` § 1).
   */
  function accueilleQuiz(plan, etape, quiz) {
    if (plan.genre !== "recit" || !plan.texte.length) return false;
    if (plan.layout !== "layout_story_opener" && plan.layout !== "layout_story_facts") return false;
    if (plan.photos.length || plan.encart || plan.carte || plan.quiz) return false;
    if (plan.rang === 0 && etape.promptEnTete) return false;
    return !aPlat(plan.texte.join(" ")).includes(aPlat(quiz.answer));
  }

  /**
   * Quels quiz s'impriment, et sur quelle page : la première page de l'étape
   * qui peut le porter (`accueilleQuiz`), à la cadence d'environ un toutes les
   * trois étapes. Faute de page, ou hors cadence, le quiz ne s'imprime pas —
   * on ne déplace ni photo ni ligne de récit pour lui.
   *
   * Pose `plan.quiz` sur les pages retenues et renvoie leur nombre.
   */
  function placerQuiz(plans, etapes, journal = () => {}) {
    const hotes = etapes.map((etape, e) => {
      const quiz = quizDe(etape);
      const plan = quiz && plans.find((p) => p.etape === e && accueilleQuiz(p, etape, quiz));
      return plan ? { e, plan, quiz } : null;
    }).filter(Boolean);
    const sansPage = etapes.filter((etape, e) => quizDe(etape) && !hotes.some((h) => h.e === e)).length;

    let dernier = -ECART_QUIZ;
    let poses = 0;
    for (;;) {
      const cible = dernier + ECART_QUIZ;
      const dansLaFenetre = hotes.filter(({ e }) => e >= dernier + ECART_QUIZ_MIN && e <= dernier + ECART_QUIZ_MAX);
      // L'étape visée plutôt qu'une voisine ; à égalité, la plus tôt.
      const choix =
        dansLaFenetre.sort((a, b) => Math.abs(a.e - cible) - Math.abs(b.e - cible) || a.e - b.e)[0] ||
        hotes.find(({ e }) => e > dernier + ECART_QUIZ_MAX);
      if (!choix) break;
      choix.plan.quiz = choix.quiz;
      poses += 1;
      dernier = choix.e;
    }
    if (sansPage) journal(`quiz : ${sansPage} étape(s) sans page qui puisse le porter (photo, encart ou carte sur chacune).`);
    return poses;
  }

  /* ------------------------------------------------------------ les décors --- */

  /** Les variantes du tracé pointillé du voyage, tour à tour d'une double page à l'autre. */
  const TRACES = ["a", "b", "c"];

  /** Les emplacements de photos d'une planche : ses photos, et le fun fact qui en prend un. */
  const casesDe = (plan) => plan.photos.length + (plan.caseEncart ? 1 : 0);

  /** La page a-t-elle une bande de photos, derrière laquelle le tracé peut passer ? */
  function porteUnTrace(plan) {
    if (plan.genre === "planche") return !plan.pleinePage && casesDe(plan) <= 2;
    if (plan.layout === "layout_chapter_map") return plan.photos.length >= 2;
    return ["layout_split_left", "layout_collage", "layout_trio_portrait", "layout_trio_landscape"].includes(plan.layout);
  }

  /**
   * La part de la page qu'un récit laisse libre en bas pour un sticker : au
   * plus 60 % de la capacité de la page, il reste une centaine de points sous
   * le texte.
   */
  const PART_LIBRE_STICKER = 0.6;

  /** Un titre d'étape assez court pour laisser, à sa droite, la place d'un petit sticker. */
  const MAX_SIGNES_TITRE_STICKER = 28;

  /**
   * Les places libres d'une page pour un sticker, de la meilleure à la moins
   * bonne — deux au plus (Hugo, 14/10/2026 : le réglage « Décorations »
   * donne le nombre de stickers de l'étape, de 1 à 4). Chaque place
   * est `{ place, album, max, maxH }` : `place`, la classe du gabarit
   * (`mb-sticker--…`), `max` et `maxH` la largeur et la hauteur les plus
   * grandes qu'elle tient, en pt.
   * Jamais par-dessus le récit :
   *
   * - **page d'album** (une ou deux photos) : les coins que les tirages
   *   laissent blancs ;
   * - **planche** de trois photos et plus : les coins extérieurs, à cheval
   *   sur une photo, en petit ;
   * - **page de récit** : à la droite du titre de l'étape s'il est court ; en
   *   bas à gauche, à la place de l'encart, dans la zone flottante ou sous un
   *   récit qui laisse le bas libre ; sur les coins extérieurs de la bande de
   *   photos.
   *
   * `gauche` : la page est une page de gauche (le pli à sa droite).
   */
  function placesSticker(plan, gauche) {
    const ext = gauche ? "left" : "right";
    if (plan.pleinePage || plan.ouverture) return [];
    // La mention « Fun fact rédigé par IA » tient le coin bas droit de la page.
    const sansMention = (places) => (plan.encart ? places.filter((p) => !/^(band|bottom)-right$/.test(p.place)) : places);
    return sansMention(placesDeLaPage(plan, gauche, ext));
  }

  function placesDeLaPage(plan, gauche, ext) {
    if (plan.genre === "planche") {
      const n = casesDe(plan);
      if (n === 1) return [{ place: `bottom-${ext}`, album: true }, { place: `bottom-${gauche ? "right" : "left"}`, album: true }];
      if (n === 2) return [{ place: "top-right", album: true }, { place: "bottom-left", album: true }];
      return [
        { place: `band-${ext}`, album: false, max: 78, maxH: 90 },
        { place: `top-${ext}`, album: false, max: 78, maxH: 90 },
      ];
    }
    if (plan.genre !== "recit") return [];
    const places = [];
    const n = signes(plan.texte);
    const titre = plan.bandeau?.titre || "";
    const avecTitre = ["layout_story_opener", "layout_story_facts", "layout_hero_top", "layout_split_left", "layout_collage", "layout_recit_photo", "layout_story_full"];
    if (plan.bandeau && titre && titre.length <= MAX_SIGNES_TITRE_STICKER && avecTitre.includes(plan.layout)) {
      // Au plus la hauteur de la ligne du titre et de la ligne vide qui la
      // suit, plus la marge au-dessus du bloc : un sticker plus haut mordrait
      // sur le récit.
      places.push({ place: "title", album: false, max: 60, maxH: 50 });
    }
    const libre = (capacite) => n <= capacite * PART_LIBRE_STICKER;
    if (["layout_story_opener", "layout_story_facts"].includes(plan.layout)) {
      // La zone flottante n'existe qu'avec une photo ; sans elle, le bas n'est
      // libre que sous un récit court.
      if (!plan.encart && (plan.photos.length === 1 || libre(CAPACITE_PAGE.defaut[plan.sorte]))) places.push({ place: "bottom-left", album: false });
    } else if (plan.layout === "layout_recit_photo") {
      if (!plan.encart && n <= CAPACITE_PAGE.layout_recit_photo.postit[plan.sorte]) places.push({ place: "bottom-left", album: false });
    } else if (plan.layout === "layout_story_full" || plan.layout === "layout_hero_top") {
      const capacite = (plan.layout === "layout_hero_top" ? CAPACITE_PAGE.layout_hero_top : CAPACITE_PAGE.defaut)[plan.sorte];
      if (!plan.encart && libre(capacite)) places.push({ place: `bottom-${ext}`, album: false });
    } else if (porteUnTrace(plan)) {
      // Une bande de photos en bas de page : ses deux coins extérieurs, en bas
      // de la page et en haut de la bande.
      places.push({ place: `band-${ext}`, album: false, max: 78, maxH: 90 }, { place: `band-top-${ext}`, album: false, max: 70, maxH: 80 });
    }
    return places.slice(0, 2);
  }

  /**
   * Un texte réduit à ses mots : minuscules, sans accent, une espace entre
   * chaque. Tout le texte : `normaliser`, fait pour un nom de lieu, s'arrête à
   * la première virgule — le composeur ne lisait que le début du récit, et la
   * plupart des stickers qu'il appelait passaient inaperçus.
   */
  const enMots = (texte) =>
    ` ${String(texte || "")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim()} `;

  /**
   * Les familles de la bibliothèque et ce que le récit d'une étape en dit :
   * `force` 2 si un mot déclencheur est dans le titre ou le lieu de l'étape,
   * 1 dans son récit ou les scènes de ses photos, 0 sinon. Les stickers
   * réservés (les personnages de dos, à choisir d'après les voyageurs) n'y
   * sont pas.
   */
  function famillesDe(etape, bibliotheque) {
    const fort = enMots([etape.titre, etape.lieu].join(" "));
    const faible = enMots([etape.recit, ...(etape.analyse?.photos || []).map((p) => p.scene)].join(" "));
    const familles = new Map();
    for (const s of bibliotheque) {
      if (s.reserve) continue;
      const famille = s.famille || s.fichier;
      if (!familles.has(famille)) familles.set(famille, { famille, variantes: [], force: 0 });
      const f = familles.get(famille);
      f.variantes.push(s);
      for (const mot of s.mots || []) {
        // Lettres, chiffres et espaces seulement : rien à échapper.
        const m = enMots(mot).trim();
        if (!m) continue;
        const motif = new RegExp(` ${m}[sx]? `);
        if (motif.test(fort)) f.force = Math.max(f.force, 2);
        else if (motif.test(faible)) f.force = Math.max(f.force, 1);
      }
    }
    return familles;
  }

  /**
   * Les stickers de la bibliothèque qui vont à une étape, un par famille, le
   * plus lié d'abord : ceux dont un mot déclencheur apparaît en mot entier
   * (pluriel en s ou x accepté) dans le titre ou le lieu de l'étape (lien
   * fort), sinon dans son récit ou les scènes de ses photos. Les stickers
   * réservés (les personnages de dos, à choisir d'après les voyageurs) ne
   * sont jamais tirés ainsi. Dans une famille, la variante dépend du rang de
   * l'étape : deux carnets n'ont pas tous le même sac à dos.
   */
  function stickersDe(etape, bibliotheque, rang = 0) {
    return [...famillesDe(etape, bibliotheque).values()]
      .filter((f) => f.force > 0)
      .sort((a, b) => b.force - a.force)
      .map((f) => f.variantes[rang % f.variantes.length]);
  }

  /**
   * Les familles qui vont à tout voyage — l'appareil photo, la carte postale,
   * la boussole, le globe, le repère, la carte —, quand le récit n'appelle pas
   * assez de stickers pour le réglage choisi. Sans elles, le récit d'un
   * carnet n'en appelle souvent que trois ou quatre, et « 1 » ou « 4 »
   * donnaient le même carnet (Hugo, 14/10/2026).
   */
  const STICKERS_DE_VOYAGE = ["appareil-photo", "carte-postale", "boussole", "globe", "repere", "carte"];

  /**
   * La largeur d'un sticker sur la page, en points : un sticker découpé reste
   * petit, un dessin peut prendre plus de place dans le blanc d'une page
   * d'album. Jamais plus que sa définition ne le permet (`maxPt`, 150 dpi), ni
   * que sa place (`max`, et `maxH` d'après les proportions du dessin).
   */
  const LARGEUR_STICKER = { sticker: 90, trait: 105, dessin: 120 };
  const LARGEUR_STICKER_ALBUM = { sticker: 100, trait: 120, dessin: 140 };
  function largeurSticker(sticker, album, max = Infinity, maxH = Infinity) {
    const voulu = (album ? LARGEUR_STICKER_ALBUM : LARGEUR_STICKER)[sticker.style] || LARGEUR_STICKER.sticker;
    const proportions = sticker.largeur > 0 && sticker.hauteur > 0 ? sticker.largeur / sticker.hauteur : 1;
    return Math.round(Math.min(voulu, max, maxH * proportions, Number.isFinite(sticker.maxPt) ? sticker.maxPt : Infinity));
  }

  /**
   * Le sticker d'une place : la famille la mieux liée à l'étape de la page —
   * son titre, puis son récit, puis le reste du voyage, puis les familles de
   * voyage —, moins elle a déjà servi, mieux elle vaut. Jamais deux fois la
   * même famille dans une étape ni sur une double page, jamais le même
   * dessin sur deux doubles pages qui se suivent, et de préférence pas la
   * même famille ; dans une famille, la variante qui a le moins servi.
   */
  function choisirSticker(plan, contexte) {
    const { familles, duVoyage, exclues, poses, derniereDouble, derniereFamille, rangDouble } = contexte;
    const f = familles[plan.etape];
    if (!f) return null;
    let meilleur = null;
    for (const famille of f.values()) {
      if (exclues.has(famille.famille)) continue;
      const force = famille.force || (duVoyage.has(famille.famille) ? 0.5 : STICKERS_DE_VOYAGE.includes(famille.famille) ? 0.25 : 0);
      if (!force) continue;
      const libres = famille.variantes.filter((v) => !(derniereDouble.get(v.fichier) >= rangDouble - 1));
      if (!libres.length) continue;
      const score =
        force - 0.6 * (poses.get(famille.famille) || 0) - (derniereFamille.get(famille.famille) === rangDouble - 1 ? 0.5 : 0);
      if (!meilleur || score > meilleur.score) meilleur = { score, famille, libres };
    }
    if (!meilleur) return null;
    // La variante qui a le moins servi, en partant du rang de l'étape.
    const { libres } = meilleur;
    const depart = plan.etape % libres.length;
    const tour = [...libres.slice(depart), ...libres.slice(0, depart)];
    return tour.reduce((a, b) => ((derniereDouble.get(b.fichier) ?? -99) < (derniereDouble.get(a.fichier) ?? -99) ? b : a));
  }

  /**
   * L'ordre où l'on essaie les places d'une étape : la première place de
   * pages réparties sur toute l'étape (la première page d'abord), puis les
   * autres premières places, puis les secondes. Deux stickers sur une étape
   * de six pages ne se serrent pas sur ses deux premières.
   */
  function ordreDesPlaces(pages, quota) {
    const avecPlace = pages.filter((p) => p.places.length);
    const n = avecPlace.length;
    const reparties = [...new Set(Array.from({ length: Math.min(quota, n) }, (_, k) => Math.floor((k * n) / Math.min(quota, n))))];
    const rangs = [...reparties, ...avecPlace.map((_, j) => j).filter((j) => !reparties.includes(j))];
    return [0, 1].flatMap((r) => rangs.map((j) => avecPlace[j].places[r]).filter(Boolean));
  }

  /**
   * Les décors (Hugo, 12/10/2026, et 14/10/2026 pour le nombre de stickers) :
   *
   * - **une étiquette de titre** au plus par double page, sur la photo la
   *   mieux notée qui en a une — celle que le voyageur a écrite passe avant
   *   celles de l'IA ;
   * - **un tracé pointillé** au plus par double page, derrière une bande de
   *   photos, de préférence sur la page de gauche ;
   * - **autant de stickers par étape que le réglage « Décorations »** (1 à 4,
   *   aucun à 0 ; 2 par défaut), deux par page au plus, à leurs places
   *   (`placesSticker`), répartis sur les pages de l'étape (`ordreDesPlaces`) ;
   *   tirés de la bibliothèque d'après le récit, complétés par les familles de
   *   voyage (`choisirSticker`).
   */
  function decorerDoublesPages(plans, pagesAvant, etapes, { stickers = [], decorations = 2 } = {}) {
    const gauche = (i) => (pagesAvant + 1 + i) % 2 === 0;
    const quota = Math.max(0, Math.min(4, Math.round(Number(decorations) || 0)));
    // Le rang de la double page de chaque page.
    const doubleDe = [];
    let tour = 0;
    for (let i = 0, rangDouble = 0; i < plans.length; rangDouble += 1) {
      const double = gauche(i) && i + 1 < plans.length ? [plans[i], plans[i + 1]] : [plans[i]];
      double.forEach((_, k) => (doubleDe[i + k] = rangDouble));
      i += double.length;

      // L'étiquette.
      let meilleure = null;
      for (const plan of double) {
        if (plan.pleinePage) continue;
        for (const photo of plan.photos) {
          if (!photo.legende) continue;
          const note = (photo.etiquetteVoyageur ? 100 : 0) + (Number.isFinite(photo.note) ? photo.note : 5);
          if (!meilleure || note > meilleure.note) meilleure = { plan, photo, note };
        }
      }
      if (meilleure) meilleure.plan.etiquette = meilleure.photo.id;

      // Le tracé.
      const porteur = double.find(porteUnTrace);
      if (porteur) porteur.trace = TRACES[tour++ % TRACES.length];
    }

    // Les stickers, étape par étape.
    if (!quota || !stickers.length) return;
    const familles = etapes.map((etape) => famillesDe(etape, stickers));
    // Les familles que le récit appelle quelque part dans le voyage.
    const duVoyage = new Set(familles.flatMap((f) => [...f.values()].filter((x) => x.force > 0).map((x) => x.famille)));
    const poses = new Map();
    const derniereDouble = new Map();
    const derniereFamille = new Map();
    const surLaDouble = new Map();
    etapes.forEach((_, e) => {
      const pages = plans
        .map((plan, i) => ({ plan, i }))
        .filter(({ plan }) => plan.etape === e)
        .map(({ plan, i }) => ({ places: placesSticker(plan, gauche(i)).map((p) => ({ ...p, plan, rangDouble: doubleDe[i] })) }));
      const surLEtape = new Set();
      let posees = 0;
      for (const place of ordreDesPlaces(pages, quota)) {
        if (posees >= quota) break;
        const deLaDouble = surLaDouble.get(place.rangDouble) ?? new Set();
        const exclues = new Set([...surLEtape, ...deLaDouble]);
        const choix = choisirSticker(place.plan, { familles, duVoyage, exclues, poses, derniereDouble, derniereFamille, rangDouble: place.rangDouble });
        if (!choix) continue;
        const famille = choix.famille || choix.fichier;
        surLEtape.add(famille);
        surLaDouble.set(place.rangDouble, deLaDouble.add(famille));
        poses.set(famille, (poses.get(famille) || 0) + 1);
        derniereDouble.set(choix.fichier, place.rangDouble);
        derniereFamille.set(famille, place.rangDouble);
        (place.plan.stickers ??= []).push({
          url: choix.url || choix.fichier,
          place: place.place,
          largeur: largeurSticker(choix, place.album, place.max, place.maxH),
          famille,
        });
        posees += 1;
      }
    });
  }

  /* ------------------------------------------------------------ le carnet --- */

  const drapeaux = (actif) => ({
    layout_chapter_map: actif === "layout_chapter_map",
    layout_story_full: actif === "layout_story_full",
    layout_photo_wall_intro: actif === "layout_photo_wall_intro",
    layout_story_opener: actif === "layout_story_opener",
    layout_story_facts: actif === "layout_story_facts",
    layout_hero_top: actif === "layout_hero_top",
    layout_split_left: actif === "layout_split_left",
    layout_collage: actif === "layout_collage",
    layout_trio_portrait: actif === "layout_trio_portrait",
    layout_trio_landscape: actif === "layout_trio_landscape",
    layout_recit_photo: actif === "layout_recit_photo",
    layout_photo_page: actif === "layout_photo_page",
  });

  /**
   * Les pages d'étape du carnet, prêtes pour `days[]`.
   *
   * `etapes` : `{ titre, lieu, dateLongue, numero, lieuComplet, recit,
   * photos: [{ id, src, format, groupe }], analyse }` — `analyse` est la réponse
   * de l'analyse d'étape (`consigneAnalyseEtape`), ou `null`.
   * `options` : `{ contours, dessinerCarte, pagesAvant, funFacts, quiz, journal }` —
   * `funFacts` est le réglage « Insérer des Fun facts » du carnet : coupé,
   * aucun encart ; `quiz`, « Quiz intégrés à l'histoire » : coupé, aucun quiz
   * (`placerQuiz`). Une étape apporte son quiz rédigé (`quiz`) ou l'analyse
   * en propose un (`analyse.quiz`).
   *
   * **Le ratio photo / texte** (Hugo, 13/10/2026 : le composeur compose, le
   * ratio dit combien de photos) : `ratio` est le palier du carnet (0, 25, 50,
   * 75 ou 100) et `budgetPhotos(etape, index)` le nombre de photos que le
   * module de ratio (`ratio-photos.js` / `photoRatio.ts`, `photosRequired`)
   * demande pour l'étape. Au-delà, les photos de trop s'écartent dans l'ordre
   * habituel (`trierPourEcarter`). Le palier règle aussi la composition :
   *
   * - **0 %** : aucune photo, le récit prend la feuille (`layout_story_full`) ;
   * - **25 %** : une photo par page de récit au plus ;
   * - **100 %** : aucun récit imprimé — une planche d'ouverture avec le
   *   bandeau et le fun fact (`layout_photo_wall_intro`), puis des planches.
   *
   * L'app compose avec le même code (`backend/src/services/bookComposer.ts`),
   * à partir de son propre payload : une étape peut alors apporter ses
   * `paragraphes` tels quels (au lieu d'un `recit` à découper) et sa `carte`
   * de chapitre (l'objet `map` du gabarit), sans analyse ni contours.
   */
  function composerJours(etapes, options = {}) {
    const {
      contours = null,
      dessinerCarte = null,
      pagesAvant = 1,
      funFacts = false,
      quiz = false,
      stickers = [],
      decorations = 2,
      ratio = 50,
      budgetPhotos = null,
      journal = () => {},
    } = options;
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
    // Le dernier scénario (A ou B) choisi dans chaque situation, pour alterner.
    const memoire = new Map();
    // Les chapitres — une suite d'étapes au même lieu — qui ont déjà leur
    // photo en pleine page.
    let numeroChapitre = 0;
    const pleinesPages = new Set();
    // Les planches de cinq photos alternent entre les rangées et les deux
    // colonnes décalées (maquette du 13/10/2026), en commençant par les
    // colonnes.
    let planchesDeCinq = 0;

    etapes.forEach((etape, index) => {
      const analysePhotos = new Map((etape.analyse?.photos || []).map((ph) => [String(ph.id), ph]));
      const toutesLesPhotos = etape.photos.map((photo) => {
        const lu = analysePhotos.get(String(photo.id)) || {};
        return {
          ...photo,
          paragraphe: Number.isInteger(lu.paragraphe) ? lu.paragraphe : null,
          scene: lu.scene || "",
          // L'étiquette que le voyageur a écrite sous la photo l'emporte sur
          // celle de l'IA.
          legende: String(photo.etiquette || "").trim().slice(0, MAX_SIGNES_ETIQUETTE) || etiquetteDe(lu),
          etiquetteVoyageur: Boolean(String(photo.etiquette || "").trim()),
          // La note « couverture » de l'analyse : ce que vaut la photo.
          note: typeof lu.couverture === "number" && Number.isFinite(lu.couverture) ? lu.couverture : null,
          // Trois visages ou plus : une photo de groupe, qui ne se rogne pas.
          groupe: Boolean(photo.groupe) || Number(lu.personnes) >= 3,
        };
      });

      // Le palier du carnet : à 0 %, aucune photo ; sinon, autant que le
      // module de ratio en demande pour cette étape, les moins bonnes écartées.
      let photos = ratio === 0 ? [] : toutesLesPhotos;
      const budget = budgetPhotos ? budgetPhotos(etape, index) : null;
      if (Number.isFinite(budget) && photos.length > budget) {
        const enTrop = new Set(trierPourEcarter(photos).slice(0, photos.length - Math.max(0, budget)));
        photos = photos.filter((p) => !enTrop.has(p));
        journal(`ratio ${ratio} % — étape ${index + 1} : ${photos.length} photo(s) gardée(s) sur ${toutesLesPhotos.length}.`);
      }

      const paragraphes = Array.isArray(etape.paragraphes)
        ? etape.paragraphes.map((p) => String(p).trim()).filter(Boolean)
        : enParagraphes(etape.recit);
      // Sans récit, une ou deux photos tiennent sur la page à bandeau ; à partir
      // de trois, l'étape n'est faite que de pages de photos.
      // À 100 %, aucun récit n'est imprimé : l'étape n'est faite que de
      // planches, la première portant le bandeau (`layout_photo_wall_intro`).
      const sansRecit = ratio === 100 && photos.length > 0;
      const pages =
        paragraphes.length && !sansRecit ? pagesDeRecit(paragraphes) : photos.length < MIN_PAGE_PHOTOS && !sansRecit ? [[]] : [];

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
      if (nouveauLieu) numeroChapitre += 1;
      // La carte que l'app apporte toute faite (`map`, choisie par l'Agent Mise
      // en page) ouvre le chapitre sans analyse ni contours.
      const carteImposee = etape.carte || null;
      let chapitre = carteImposee
        ? Boolean(pages.length && paragraphes.length)
        : Boolean(nouveauLieu && situe && dessinerCarte && pages.length && paragraphes.length);
      // La carte prend la place d'une colonne : le récit de l'ouverture doit y
      // tenir. Elle ne coûte plus de photo — ce qui n'a pas de place sur les
      // pages de récit va sur les pages de photos de fin d'étape.
      if (chapitre && signes(pages[0]) > CAPACITE_CHAPITRE.sansPhoto) chapitre = false;

      // À 25 %, une photo par page de récit au plus : le récit tient la page.
      const maxParPage = ratio <= 25 ? Math.min(1, photosParPageDeRecit(photos)) : photosParPageDeRecit(photos);
      // La structure de l'étape : récit d'un seul tenant, photos en fin
      // d'étape, nombre de pages pair (`structurerEtape`).
      let structure;
      if (paragraphes.length && pages.length) {
        structure = structurerEtape({ paragraphes, pagesNaturelles: pages, photos, maxParPage, chapitre, memoire });
      } else if (pages.length) {
        structure = { pages, recit: [photos], fin: [], tailles: [], chapitreDeux: false, total: 1 };
      } else {
        // Que des photos : la première planche porte le bandeau, et quatre
        // photos au plus (`layout_photo_wall_intro`).
        let q = Math.ceil(photos.length / MAX_PAGE_PHOTOS);
        while (partsEgales(photos.length, q)[0] > MAX_PHOTOS_OUVERTURE) q += 1;
        if (q % 2 && q < photos.length) q += 1;
        structure = { pages: [], recit: [], fin: photos, tailles: partsEgales(photos.length, q), chapitreDeux: false, total: q };
      }
      if (structure.ecartees?.length) {
        journal(
          `photo(s) écartée(s) — étape ${index + 1} : ${structure.ecartees.length} photo(s) de trop pour six pages ` +
            "(les floues ou sombres d'abord, puis les doublons d'une scène, puis les moins bien notées).",
        );
      }
      if (structure.total % 2) {
        journal(`étape ${index + 1} : ${structure.total} page(s), un nombre impair — l'étape n'a pas de quoi en remplir une de plus.`);
      }

      let carte = "";
      if (chapitre && carteImposee) {
        carte = carteImposee;
      } else if (chapitre) {
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

      const pagesEtape = structure.pages;
      const paragraphesDeLaPage = pagesEtape.map(() => []);
      const pageDuParagraphe = pageDeChaqueParagraphe(paragraphes, pagesEtape);
      pageDuParagraphe.forEach((p, i) => paragraphesDeLaPage[p]?.push(i));

      // Les pages de photos n'ont pas de légende (Hugo, 12/10/2026). Une
      // photo exceptionnelle, seule sur sa page, s'imprime en pleine page —
      // une fois par chapitre au plus.
      const planche = (liste) => {
        const plan = { genre: "planche", etape: index, photos: liste };
        if (liste.length === 1 && !pleinesPages.has(numeroChapitre) && pleinePageAdmise(liste[0])) {
          plan.pleinePage = true;
          pleinesPages.add(numeroChapitre);
        }
        if (liste.length === 5 && planchesDeCinq++ % 2 === 0) plan.colonnes = true;
        return plan;
      };

      pagesEtape.forEach((texte, p) => {
        const plan = {
          genre: "recit",
          etape: index,
          rang: p,
          sorte: p === 0 ? "bandeau" : "suite",
          texte,
          photos: structure.recit[p],
          paragraphes: paragraphesDeLaPage[p],
          capPhotos: p === 0 && chapitre ? (structure.chapitreDeux ? 2 : 1) : maxParPage,
          ouvreLeCarnet: index === 0 && p === 0,
          bandeau: p === 0 ? etape : null,
          carte: p === 0 && chapitre ? carte : "",
          ...(structure.serre ? { taille: "serre" } : {}),
        };
        plan.layout = plan.carte
          ? "layout_chapter_map"
          : ratio === 0
            ? "layout_story_full"
            : layoutDeRecit(plan.photos, texte, plan.sorte, plan.ouvreLeCarnet);
        plans.push(plan);
      });
      // Les pages de photos seules, toujours après le récit. Sans récit, la
      // première ouvre l'étape : bandeau et fun fact.
      let debut = 0;
      for (const taille of structure.tailles) {
        const plan = planche(structure.fin.slice(debut, debut + taille));
        if (!pagesEtape.length && debut === 0) {
          plan.ouverture = true;
          plan.bandeau = etape;
          delete plan.pleinePage;
          delete plan.colonnes;
        }
        plans.push(plan);
        debut += taille;
      }
    });

    const restants = varierDoublesPages(plans, pagesAvant);
    if (restants) journal(`${restants} double(s) page(s) gardent la même composition faute d'alternative.`);

    // Les quiz, puis les encarts : ils se posent sur des pages déjà composées,
    // sans déplacer ni photo ni ligne de récit. Le quiz d'abord, parce qu'il
    // ne tient que sur une page sans rien en bas, quand l'encart en a d'autres.
    if (quiz) journal(`${placerQuiz(plans, etapes, journal)} quiz dans le carnet.`);
    if (funFacts) journal(`${placerEncarts(plans, etapes, journal)} encart(s) « fun fact » dans le carnet.`);

    // Le corps ample, une fois les photos et les encarts à leur place : ce sont
    // eux qui remplissent une page avant le texte.
    corpsAmple(plans);

    // Les décors : une étiquette de titre et un tracé pointillé par double
    // page, les stickers du réglage par étape.
    decorerDoublesPages(plans, pagesAvant, etapes, { stickers, decorations });
    if (stickers.length) {
      const poses = plans.flatMap((plan) => (plan.stickers || []).map((s) => s.famille));
      journal(`stickers : ${poses.length ? `${poses.length} — ${poses.join(", ")}` : "aucun, aucun mot du récit ne les appelle"}.`);
    }

    return plans.map((plan, rangPage) => {
      const decors = {
        trace: plan.trace || "aucun",
        ...(plan.stickers?.length ? { stickers: plan.stickers.map(({ famille, ...s }) => s) } : {}),
      };
      if (plan.genre === "planche" && plan.ouverture) {
        const e = plan.bandeau;
        return {
          title: e.titre,
          date: e.dateLongue,
          city: e.lieu || "",
          country: e.destination || "",
          day_intro: { day_number: e.numero, location: e.lieuComplet, date: e.dateLongue },
          body_html: "",
          ...drapeaux("layout_photo_wall_intro"),
          photos: habillerPhotos(plan, placerPhotos("layout_photo_page", plan.photos), rangPage),
          fun_facts: plan.encart ? [plan.encart.texte] : [],
          ...(plan.encart ? { fun_facts_title: plan.encart.titre, ai_note: "Fun fact rédigé par IA" } : {}),
          sticker_groups: [],
          ...decors,
        };
      }
      if (plan.genre === "planche") {
        // Une photo seule en largeur : l'emplacement de la page d'album se couche.
        const paysage = !plan.pleinePage && !plan.caseEncart && plan.photos.length === 1 && plan.photos[0].format > 1;
        const gabarit = plan.pleinePage
          ? "pleine_page"
          : paysage
            ? "album_paysage"
            : plan.colonnes
              ? "planche_colonnes"
              : "layout_photo_page";
        return {
          title: "",
          body_html: "",
          ...drapeaux("layout_photo_page"),
          ...(plan.pleinePage ? { pleine_page: true } : {}),
          ...(paysage ? { album_paysage: true } : {}),
          ...(plan.colonnes ? { planche_colonnes: true } : {}),
          photos: habillerPhotos(plan, photosRendues(plan, gabarit), rangPage),
          // Le fun fact d'une page de photos prend l'emplacement d'une photo
          // (Hugo, 14/10/2026) : `case_fun_fact` en dit le rang.
          ...(plan.caseEncart ? { case_fun_fact: plan.caseEncart.c } : {}),
          fun_facts: plan.encart ? [plan.encart.texte] : [],
          ...(plan.encart ? { fun_facts_title: plan.encart.titre, ai_note: "Fun fact rédigé par IA" } : {}),
          sticker_groups: [],
          ...decors,
        };
      }
      const jour = {
        ...drapeaux(plan.layout),
        body_html: paragraphesEnHtml(plan.texte),
        photos: habillerPhotos(plan, photosRendues(plan, plan.layout), rangPage),
        ...(plan.caseEncart ? { case_fun_fact: plan.caseEncart.c } : {}),
        fun_facts: plan.encart ? [plan.encart.texte] : [],
        // L'encart est écrit par le modèle : la page le dit, en petit
        // (LAYOUT_KB § « La mention généré par IA »).
        ...(plan.encart ? { fun_facts_title: plan.encart.titre, ai_note: "Fun fact rédigé par IA" } : {}),
        // Le quiz est écrit par le modèle, lui aussi.
        ...(plan.quiz ? { quiz: plan.quiz, ai_note: "Quiz rédigé par IA" } : {}),
        sticker_groups: [],
        ...decors,
        ...(plan.taille ? { taille_texte: plan.taille } : {}),
        ...(plan.carte ? (typeof plan.carte === "string" ? { map_svg: plan.carte } : { map: plan.carte }) : {}),
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
    repartirRecit,
    affecterPhotos,
    structurerEtape,
    placerPhotos,
    varierDoublesPages,
    placerEncarts,
    placerQuiz,
    decorerDoublesPages,
    stickersDe,
    cadreDuVoyage,
    cadreDuPays,
    cadresDesCartes,
    sejourUnique,
    lieuxDuVoyage,
    composition,
    composerJours,
    corpsAmple,
    paragraphesEnHtml,
    rognage,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else racine.MiseEnPage = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
