/*
 * Couverture imprimée — le plat verso (la quatrième), le dos et le plat recto
 * (la première) d'un livre relié Pumbo, d'un seul tenant, au format exact de la
 * commande.
 *
 * Pourquoi un fichier à part : la couverture d'un relié n'est pas une page du
 * carnet. Sa largeur dépend du nombre de pages (le dos), elle a son propre
 * fond perdu, et Pumbo l'imprime sur un autre papier que l'intérieur.
 *
 * Le chemin :
 *
 * 1. **les photos** : `proposerPhotos` retient les trois plus adaptées à chaque
 *    plat — qualité de l'image (résolution à la taille d'impression, netteté,
 *    exposition) et contenu (la note « couverture » de l'analyse d'étape : un
 *    paysage marquant, ou une belle photo des voyageurs). Le voyageur choisit,
 *    ou en prend une autre : `evaluerPhoto` en dit alors les défauts ;
 * 2. **la maquette** (`maquette`) : chaque élément de la couverture, en
 *    millimètres, dans le style par défaut (`assets/covers/`). Rien n'y est
 *    écrit en dur : titre, voyageurs, dates, chiffres et carte viennent du
 *    voyage ;
 * 3. **deux sorties de la même maquette** : `versHtml`, l'aperçu à enregistrer
 *    en PDF, et `versJsx`, le script InDesign qui construit le document — sur
 *    le modèle de la fiche Pumbo, qui est elle-même un script InDesign. Le
 *    tout part dans un `.zip` (`zipper`) avec les photos.
 *
 * Les dimensions viennent de la **fiche technique Pumbo** (le `.jsx` de leur
 * outil de couverture). Sans fiche, celle d'un relié 154 × 216 mm de 48 pages.
 *
 * Règles et schéma : `templates/travel-journal/LAYOUT_KB.md`, § « Couverture
 * imprimée (Pumbo) ».
 */
(function (racine) {
  "use strict";

  const enNode = typeof module !== "undefined" && module.exports;
  // Lus au moment de servir, pas au chargement : l'ordre des <script> n'y peut rien.
  const Carte = enNode ? require("./carte.js") : { get outils() { return racine.Carte.outils; } };
  const Voyage = enNode
    ? require("./voyage.js")
    : { nombreCourt: (n) => racine.Voyage.nombreCourt(n), normaliser: (t) => racine.Voyage.normaliser(t) };

  /**
   * La fiche d'un relié 154 × 216 mm de 48 pages, reçue de Pumbo le 07/10/2026.
   * Plats de 178 × 260 mm : le carton dépasse du bloc et le papier se rabat
   * dessus, d'où des plats plus grands que la page.
   */
  const FICHE_DEFAUT = {
    source: "fiche Pumbo d'un relié 154 × 216 mm de 48 pages",
    largeurPlat: 178,
    hauteurPlat: 260,
    dos: 8,
    fondPerdu: 3,
    marge: 19,
    parDefaut: true,
  };

  /**
   * Distance minimale entre le texte et le dos, sur chaque plat. La fiche ne
   * met aucune marge côté dos, mais un relié a une charnière : la couverture
   * s'y plie, et un mot posé dessus se lit mal et s'use le premier.
   */
  const CHARNIERE = 12;

  /** Sous cette largeur de dos, pas de texte dessus : il ne tiendrait pas lisible. */
  const DOS_MIN_TEXTE = 6;

  /** Résolution visée, et celle sous laquelle on prévient le voyageur. */
  const DPI_CIBLE = 300;
  const DPI_MIN = 200;

  const MM_PAR_PT = 25.4 / 72;

  /** Les couleurs du style par défaut, nommées comme les nuanciers InDesign du script. */
  const COULEURS = {
    encre: { nom: "MemoBook encre", hex: "#2b231b" },
    vert: { nom: "MemoBook vert", hex: "#19532b" },
    papier: { nom: "MemoBook papier", hex: "#fbf8f1" },
    blanc: { nom: "MemoBook blanc", hex: "#ffffff" },
  };

  /* ------------------------------------------------------- la fiche Pumbo --- */

  /**
   * Lit la fiche `.jsx` de Pumbo. Le script InDesign donne, dans cet ordre :
   * le fond perdu (`documentBleedTopOffset`), les trois pages — verso, dos,
   * recto — avec leur largeur et leur hauteur, puis les marges des plats.
   * Renvoie `null` si le fichier n'a pas cette forme.
   */
  function lireFichePumbo(texte) {
    const source = String(texte || "");
    const pages = {};
    for (const m of source.matchAll(
      /pages\.item\((\d)\)\.adjustLayout\(\{\s*width\s*:\s*"([\d.,]+)mm"\s*,\s*height\s*:\s*"([\d.,]+)mm"/g,
    )) {
      pages[m[1]] = { largeur: nombre(m[2]), hauteur: nombre(m[3]) };
    }
    const fond = source.match(/documentBleed\w*Offset\s*:\s*"([\d.,]+)mm"/);
    // Les marges du recto (page 2) : haut, bas et bord extérieur. On garde la
    // plus grande, c'est la zone sûre la plus prudente.
    const marges = source.match(
      /pages\.item\(2\)\.marginPreferences\.properties\s*=\s*\{([^}]*)\}/,
    );
    const valeursMarges = marges
      ? [...marges[1].matchAll(/"([\d.,]+)mm"/g)].map((m) => nombre(m[1])).filter((v) => v > 0)
      : [];

    const verso = pages["0"];
    const dos = pages["1"];
    const recto = pages["2"];
    if (!verso || !dos || !recto) return null;
    return {
      source: "fiche Pumbo importée",
      largeurPlat: recto.largeur,
      hauteurPlat: recto.hauteur,
      dos: dos.largeur,
      fondPerdu: fond ? nombre(fond[1]) : FICHE_DEFAUT.fondPerdu,
      marge: valeursMarges.length ? Math.max(...valeursMarges) : FICHE_DEFAUT.marge,
      parDefaut: false,
    };
  }

  function nombre(texte) {
    return Number(String(texte).replace(",", "."));
  }

  /**
   * La largeur du dos d'un relié Pumbo, d'après le nombre de pages
   * intérieures (barème Pumbo du 08/10/2026) : 8,0 mm de 16 à 56 pages ; au-delà,
   * 3 mm + 0,09 mm par page, arrondi au dixième, 8 mm au moins. 100 pages font
   * 12,0 mm, 200 pages 21,0 mm.
   */
  const DOS_MIN = 8;
  const PAGES_MIN = 16;
  function dosPumbo(pages) {
    const n = Math.max(0, Math.round(Number(pages) || 0));
    if (n <= 56) return DOS_MIN;
    return Math.max(DOS_MIN, Math.round((3 + 0.09 * n) * 10) / 10);
  }

  /**
   * La fiche de la commande : les plats, le fond perdu et les marges de la
   * fiche Pumbo (importée, ou celle par défaut), le dos tiré du nombre de pages
   * du carnet. Sans nombre de pages connu, la fiche telle quelle.
   */
  function ficheDuCarnet(fiche, pages) {
    if (!pages) return fiche;
    const dos = dosPumbo(pages);
    return {
      ...fiche,
      dos,
      pages,
      // Le dos ne dépend plus de la fiche : il n'y a plus rien à signaler.
      parDefaut: false,
      source: `${fiche.source} ; dos de ${String(dos).replace(".", ",")} mm pour ${pages} pages (barème Pumbo)`,
      tropCourt: pages < PAGES_MIN,
    };
  }

  /**
   * Les pages du PDF du carnet tel que le gabarit le rend, une à une :
   * couverture, colophon, introduction, une page par entrée de `days`, page
   * blanche finale, quatrième — le décompte de
   * `templates/travel-journal/index.html`, que `couvertureAtelier.test.ts`
   * vérifie sur le gabarit lui-même. Sur le payload de la **version
   * imprimeur** (`sans_couvertures`), c'est le nombre de pages que Pumbo relie,
   * celui qui fixe le dos.
   */
  function pagesDuPdf(payload) {
    const couvertures = payload.sans_couvertures ? 0 : 1 + (payload.back_cover ? 1 : 0);
    return (
      couvertures +
      1 + // le colophon
      (payload.intro_text ? 1 : 0) +
      (payload.days?.length || 0) +
      (payload.page_blanche_finale ? 1 : 0)
    );
  }

  /** Toutes les cotes de la feuille, en millimètres, origine en haut à gauche du fond perdu. */
  function geometrie(fiche) {
    const f = fiche.fondPerdu;
    const largeur = 2 * f + 2 * fiche.largeurPlat + fiche.dos;
    const hauteur = 2 * f + fiche.hauteurPlat;
    const debutDos = f + fiche.largeurPlat;
    const debutRecto = debutDos + fiche.dos;
    return {
      largeur,
      hauteur,
      verso: { x: 0, largeur: debutDos },
      dos: { x: debutDos, largeur: fiche.dos },
      recto: { x: debutRecto, largeur: largeur - debutRecto },
      // Format d'un plat fond perdu compris : c'est lui qu'une photo doit remplir.
      formatRecto: (largeur - debutRecto) / hauteur,
    };
  }

  /** Part de l'image perdue quand une photo de format `photo` remplit un cadre de format `cadre`. */
  function rognage(photo, cadre) {
    if (!photo || !cadre) return 0;
    return 1 - Math.min(cadre / photo, photo / cadre);
  }

  /** Résolution effective d'une photo étirée sur tout un plat (fond perdu compris). */
  function dpiSurRecto(photo, fiche) {
    if (!photo?.largeur || !photo?.hauteur) return 0;
    const g = geometrie(fiche);
    return Math.round(
      Math.min(photo.largeur / (g.recto.largeur / 25.4), photo.hauteur / (g.hauteur / 25.4)),
    );
  }

  /* ------------------------------------------------------------ les photos --- */

  /**
   * Les seuils du contrôle qualité. La netteté est la variance du laplacien sur
   * une vignette de 512 px (`mesurerPhoto`, `app.js`) : mesurée sur des photos
   * du dépôt, une photo nette donne de 170 à 3 000, la même floutée d'un pixel
   * de 15 à 130, de deux pixels moins de 15.
   */
  const SEUILS = {
    dpi: DPI_MIN,
    nettete: 40,
    sombre: 45,
    clair: 215,
    ecretage: 0.25,
    rognage: 1 / 3,
    // Une photo de groupe se rogne peu : quelqu'un sortirait du cadre.
    rognageGroupe: 0.15,
  };

  const borne = (v) => Math.max(0, Math.min(1, v));

  /**
   * Ce que vaut une photo sur un plat, et ce qui ne va pas.
   *
   * - `qualite` (0–1) : résolution à la taille d'impression (300 dpi visés),
   *   netteté, exposition ;
   * - `contenu` (0–1) : la note « couverture » de l'analyse d'étape (un
   *   paysage marquant, une belle photo des voyageurs), 0,5 sans analyse ;
   * - `score` : 55 % contenu, 45 % qualité ; nul si la photo ne tient pas sur
   *   le plat (trop rognée) ;
   * - `alertes` : ce qu'il faut dire au voyageur qui la choisit.
   *
   * `photo` : `{ largeur, hauteur, groupe }` ; `mesure` : `{ nettete,
   * luminance, ecretage }` ; `analyse` : la photo telle que l'analyse d'étape
   * l'a décrite (`couverture`, `personnes`, `sujet`).
   */
  function evaluerPhoto(photo, { fiche = FICHE_DEFAUT, mesure = null, analyse = null } = {}) {
    const dpi = dpiSurRecto(photo, fiche);
    const format = photo.largeur && photo.hauteur ? photo.largeur / photo.hauteur : 0;
    const perte = format ? rognage(format, geometrie(fiche).formatRecto) : 1;
    const groupe = Boolean(photo.groupe) || Number(analyse?.personnes) >= 3;

    const resolution = borne(dpi / DPI_CIBLE);
    const nettete = mesure && Number.isFinite(mesure.nettete) ? borne(mesure.nettete / 300) : 0.6;
    let exposition = 0.6;
    if (mesure && Number.isFinite(mesure.luminance)) {
      const l = mesure.luminance;
      exposition = l < 70 ? borne((l - 20) / 50) : l > 190 ? borne((240 - l) / 50) : 1;
      if (mesure.ecretage > 0.1) exposition *= borne(1 - (mesure.ecretage - 0.1) * 2);
    }
    const qualite = 0.4 * resolution + 0.4 * nettete + 0.2 * exposition;
    const note = Number(analyse?.couverture);
    const contenu = Number.isFinite(note) ? borne(note / 10) : 0.5;
    const tient = perte <= SEUILS.rognage && !(groupe && perte > SEUILS.rognageGroupe);

    const alertes = [];
    if (dpi && dpi < SEUILS.dpi) {
      alertes.push(`Résolution insuffisante : ${dpi} dpi sur le plat (${DPI_CIBLE} visés, ${DPI_MIN} au minimum). Elle sera floue à l'impression.`);
    }
    if (mesure && mesure.nettete < SEUILS.nettete) alertes.push("La photo est floue : le flou se voit davantage en grand format.");
    if (mesure && mesure.luminance < SEUILS.sombre) alertes.push("La photo est très sombre : l'impression l'assombrira encore.");
    if (mesure && (mesure.luminance > SEUILS.clair || mesure.ecretage > SEUILS.ecretage)) {
      alertes.push("La photo est surexposée : des zones entièrement blanches s'imprimeront sans aucun détail.");
    }
    if (groupe && perte > SEUILS.rognageGroupe) {
      alertes.push(
        `C'est une photo de groupe, et le plat en rogne ${Math.round(perte * 100)} % : quelqu'un risque de sortir du cadre.`,
      );
    } else if (perte > SEUILS.rognage) {
      alertes.push(
        `Le plat rogne ${Math.round(perte * 100)} % de cette photo, au-delà du plafond d'un tiers : une photo en hauteur convient mieux.`,
      );
    }

    return {
      dpi,
      rognage: perte,
      qualite,
      contenu,
      score: tient ? 0.55 * contenu + 0.45 * qualite : 0,
      alertes,
      suffisante: alertes.length === 0,
    };
  }

  /**
   * Les trois photos proposées pour la première de couverture, et trois autres
   * pour la quatrième — six photos différentes. `photos` : `[{ id, largeur,
   * hauteur, groupe, mesure, analyse }]`.
   *
   * Seules les photos qui passent le contrôle qualité sont proposées : une
   * photo floue, trop petite ou trop rognée ne l'est jamais, quitte à en
   * proposer moins de trois. `meilleure` est la mieux notée de toutes, défauts
   * compris : faute de mieux, c'est elle qui fait la couverture, alerte à
   * l'appui, plutôt qu'un aplat.
   */
  function proposerPhotos(photos, { fiche = FICHE_DEFAUT, nombre: n = 3 } = {}) {
    const notees = photos
      .map((photo, rang) => ({ photo, rang, ...evaluerPhoto(photo, { fiche, mesure: photo.mesure, analyse: photo.analyse }) }))
      .sort((a, b) => b.score - a.score || b.qualite - a.qualite || a.rang - b.rang);
    const bonnes = notees.filter((e) => e.suffisante && e.score > 0);
    return { recto: bonnes.slice(0, n), verso: bonnes.slice(n, 2 * n), meilleure: notees[0] || null };
  }

  /* ------------------------------------------------------------ les textes --- */

  const MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];

  /** « février 2026 », « août – septembre 2026 », « décembre 2025 – janvier 2026 ». */
  function moisDuVoyage(debut, fin) {
    const lire = (iso) => {
      const m = String(iso || "").match(/^(\d{4})-(\d{2})/);
      return m ? { annee: Number(m[1]), mois: Number(m[2]) - 1 } : null;
    };
    const a = lire(debut);
    const b = lire(fin) || a;
    if (!a) return "";
    if (a.annee === b.annee && a.mois === b.mois) return `${MOIS[a.mois]} ${a.annee}`;
    if (a.annee === b.annee) return `${MOIS[a.mois]} – ${MOIS[b.mois]} ${a.annee}`;
    return `${MOIS[a.mois]} ${a.annee} – ${MOIS[b.mois]} ${b.annee}`;
  }

  /** « Margaux, Claire et Augustin ». */
  function listeNoms(noms) {
    const liste = (noms || []).map((n) => String(n).trim()).filter(Boolean);
    if (liste.length <= 1) return liste[0] || "";
    return `${liste.slice(0, -1).join(", ")} et ${liste[liste.length - 1]}`;
  }

  /**
   * Les textes de la couverture, tirés du carnet — le voyageur peut les
   * reprendre. Le titre est la destination, comme dans le style par défaut ;
   * à défaut, le titre du carnet.
   */
  function textesParDefaut({ destination, titre, voyageurs, debut, fin }) {
    return {
      titre: String(destination || "").trim() || String(titre || "").trim() || "Carnet de voyage",
      voyageurs: listeNoms(voyageurs),
      dates: moisDuVoyage(debut, fin),
    };
  }

  /**
   * Les trois chiffres de la quatrième. Les jours d'abord, puis les
   * kilomètres quand le récit raconte des trajets, puis les pays quand il y en
   * a plusieurs — sinon les villes : « 1 pays visité » ne dit rien d'un voyage
   * en Grèce, « 4 villes visitées » si.
   */
  function chiffresQuatrieme({ jours, km, pays, villes }) {
    const candidats = [];
    if (jours) candidats.push({ valeur: String(jours), libelle: jours > 1 ? "jours\nde voyage" : "jour\nde voyage" });
    if (km) candidats.push({ valeur: Voyage.nombreCourt(km), libelle: "km\nparcourus" });
    const nPays = pays?.length || 0;
    const nVilles = villes?.length || 0;
    const lieuxPays = nPays ? { valeur: String(nPays), libelle: nPays > 1 ? "pays\nvisités" : "pays\nvisité" } : null;
    const lieuxVilles = nVilles
      ? { valeur: String(nVilles), libelle: nVilles > 1 ? "villes\nvisitées" : "ville\nvisitée" }
      : null;
    if (nPays > 1) candidats.push(lieuxPays, lieuxVilles);
    else candidats.push(lieuxVilles, lieuxPays);
    return candidats.filter(Boolean).slice(0, 3);
  }

  /* ---------------------------------------------------------- la maquette --- */

  /*
   * Une maquette, c'est la couverture décrite élément par élément, en
   * millimètres, dans le repère de la planche : (0, 0) au coin haut gauche du
   * plat verso, au trait de coupe — le fond perdu est en négatif. C'est le
   * repère « planche » d'InDesign (`RulerOrigin.SPREAD_ORIGIN`).
   *
   * - `{ type: "rect", x, y, l, h, fond, trait, rayon }`
   * - `{ type: "image", x, y, l, h, fichier, src, px: [l, h], focus: [fx, fy] }`
   * - `{ type: "texte", x, y, l, h, texte, police, style, corps, couleur,
   *     alignement, vertical, rotation, ombre, approche }`
   * - `{ type: "chemin", points, ferme, trait, fond, courbe }`
   * - `{ type: "cercle", cx, cy, r, fond, trait }`
   *
   * `trait` : `{ couleur, epaisseur (pt), tirets ([pt, pt] ou null) }`.
   */

  const largeurTexte = (texte, corps, facteur = 0.52) => String(texte).length * corps * facteur * MM_PAR_PT;

  /** Le cadre de la carte de quatrième : tous les lieux du voyage, une marge, un degré au moins. */
  function cadreQuatrieme(lieux) {
    if (!lieux?.length) return null;
    let o = Math.min(...lieux.map((l) => l.lon));
    let e = Math.max(...lieux.map((l) => l.lon));
    let s = Math.min(...lieux.map((l) => l.lat));
    let n = Math.max(...lieux.map((l) => l.lat));
    const cosLat = Math.max(0.2, Math.cos((((s + n) / 2) * Math.PI) / 180));
    const elargir = (a, b, min) => {
      const c = (a + b) / 2;
      const demi = Math.max(((b - a) * 1.5) / 2, min / 2);
      return [c - demi, c + demi];
    };
    [s, n] = elargir(s, n, 1);
    [o, e] = elargir(o, e, 1 / cosLat);
    return [o, s, e, n].map((v) => Math.round(v * 1000) / 1000);
  }

  /** Coupe une polyligne au rectangle `[x0, y0, x1, y1]` : les morceaux qui restent dedans (Liang-Barsky). */
  function couperPolyligne(points, [x0, y0, x1, y1]) {
    const morceaux = [];
    let courant = null;
    const egal = (p, q) => Math.abs(p[0] - q[0]) < 1e-9 && Math.abs(p[1] - q[1]) < 1e-9;
    for (let i = 1; i < points.length; i += 1) {
      const a = points[i - 1];
      const b = points[i];
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      let t0 = 0;
      let t1 = 1;
      let dehors = false;
      for (const [p, q] of [
        [-dx, a[0] - x0],
        [dx, x1 - a[0]],
        [-dy, a[1] - y0],
        [dy, y1 - a[1]],
      ]) {
        if (p === 0) {
          if (q < 0) dehors = true;
        } else {
          const t = q / p;
          if (p < 0) t0 = Math.max(t0, t);
          else t1 = Math.min(t1, t);
        }
      }
      if (dehors || t0 > t1) {
        if (courant) morceaux.push(courant);
        courant = null;
        continue;
      }
      const debut = [a[0] + t0 * dx, a[1] + t0 * dy];
      const fin = [a[0] + t1 * dx, a[1] + t1 * dy];
      if (courant && egal(courant[courant.length - 1], debut)) courant.push(fin);
      else {
        if (courant) morceaux.push(courant);
        courant = [debut, fin];
      }
      if (t1 < 1) {
        morceaux.push(courant);
        courant = null;
      }
    }
    if (courant) morceaux.push(courant);
    return morceaux.filter((m) => m.length >= 2);
  }

  const arrondi2 = (v) => Math.round(v * 100) / 100;

  /**
   * La carte de la quatrième : les villes (ou les îles) où le voyage a
   * séjourné, reliées dans l'ordre de visite, chaque trajet au trait de son
   * moyen de transport — `lieux` vient de `Voyage.lieuxDeSejour`. Les côtes en
   * trait fin, sans fond ; les lieux en anneaux verts, leurs noms placés là où
   * ils ne chevauchent rien, au besoin au bout d'un filet.
   */
  function elementsCarte({ lieux, detail }, zone) {
    const elements = [];
    const cadre = cadreQuatrieme(lieux);
    if (!cadre) return elements;
    const { vue, projeter } = Carte.outils.cadrer(cadre, zone.l, zone.h, 0);
    const dans = (p) => [zone.x + p[0], zone.y + p[1]];
    const rect = [zone.x, zone.y, zone.x + zone.l, zone.y + zone.h];

    for (const pays of Object.values(detail || {})) {
      if (!pays?.rings || (pays.bbox && !Carte.outils.seCroisent(pays.bbox, vue))) continue;
      for (const ring of pays.rings) {
        if (!Carte.outils.seCroisent(Carte.outils.boiteDe(ring), vue)) continue;
        const pts = ring.map(([lon, lat]) => dans(projeter(lon, lat)));
        pts.push(pts[0]);
        for (const morceau of couperPolyligne(Carte.outils.simplifier(pts, 0.12), rect)) {
          const [o, s, e, n] = Carte.outils.boiteDe(morceau);
          if (e - o < 0.6 && n - s < 0.6) continue;
          elements.push({
            type: "chemin",
            points: morceau.map((p) => p.map(arrondi2)),
            ferme: false,
            trait: { couleur: "vert", epaisseur: 0.45, tirets: null },
          });
        }
      }
    }

    // Le trajet, dans l'ordre de visite.
    const projetes = lieux.map((l) => {
      const [x, y] = dans(projeter(l.lon, l.lat));
      return { x: arrondi2(x), y: arrondi2(y), mode: l.mode };
    });
    for (const s of Carte.outils.segmentsDuTrajet(projetes, null)) {
      elements.push({
        type: "chemin",
        points: [s.a, s.b],
        courbe: s.c,
        ferme: false,
        trait: {
          couleur: "vert",
          epaisseur: 0.7,
          tirets: s.mode === "terre" ? null : s.mode === "avion" ? [0.5, 1.4] : [1.6, 1.4],
        },
      });
    }

    // Les lieux, une seule fois chacun, et leurs noms.
    const R = 1.1;
    const uniques = [];
    for (const [i, l] of lieux.entries()) {
      if (!uniques.some((u) => Voyage.normaliser(u.nom) === Voyage.normaliser(l.nom))) uniques.push({ ...l, ...projetes[i] });
    }
    const occupes = uniques.map((u) => [u.x - R - 0.3, u.y - R - 0.3, u.x + R + 0.3, u.y + R + 0.3]);
    const libre = (b) =>
      b[0] >= rect[0] && b[1] >= rect[1] && b[2] <= rect[2] && b[3] <= rect[3] &&
      !occupes.some((o) => b[0] < o[2] && o[0] < b[2] && b[1] < o[3] && o[1] < b[3]);
    const CORPS = 6.5;
    const hLigne = CORPS * MM_PAR_PT * 1.25;
    for (const u of uniques) {
      elements.push({ type: "cercle", cx: u.x, cy: u.y, r: R, fond: "papier", trait: { couleur: "vert", epaisseur: 1.1, tirets: null } });
      const l = largeurTexte(u.nom, CORPS, 0.56) + 0.8;
      const candidats = [];
      // Au plus près d'abord, puis au bout d'un filet, dans huit directions.
      candidats.push({ b: [u.x + R + 1.2, u.y - hLigne / 2, u.x + R + 1.2 + l, u.y + hLigne / 2], aligne: "gauche" });
      candidats.push({ b: [u.x - R - 1.2 - l, u.y - hLigne / 2, u.x - R - 1.2, u.y + hLigne / 2], aligne: "droite" });
      candidats.push({ b: [u.x - l / 2, u.y - R - 1 - hLigne, u.x + l / 2, u.y - R - 1], aligne: "centre" });
      candidats.push({ b: [u.x - l / 2, u.y + R + 1, u.x + l / 2, u.y + R + 1 + hLigne], aligne: "centre" });
      for (const d of [9, 14]) {
        for (const angle of [0, 180, -30, -150, 30, 150, -90, 90]) {
          const a = (angle * Math.PI) / 180;
          const ax = u.x + Math.cos(a) * d;
          const ay = u.y + Math.sin(a) * d;
          const cos = Math.cos(a);
          const b =
            cos > 0.3
              ? [ax + 0.6, ay - hLigne / 2, ax + 0.6 + l, ay + hLigne / 2]
              : cos < -0.3
                ? [ax - 0.6 - l, ay - hLigne / 2, ax - 0.6, ay + hLigne / 2]
                : Math.sin(a) < 0
                  ? [ax - l / 2, ay - hLigne, ax + l / 2, ay]
                  : [ax - l / 2, ay, ax + l / 2, ay + hLigne];
          candidats.push({ b, aligne: cos > 0.3 ? "gauche" : cos < -0.3 ? "droite" : "centre", filet: [ax, ay] });
        }
      }
      const choix = candidats.find((c) => libre(c.b));
      if (!choix) continue;
      occupes.push(choix.b);
      if (choix.filet) {
        const [ax, ay] = choix.filet;
        const lf = Math.hypot(ax - u.x, ay - u.y);
        elements.push({
          type: "chemin",
          points: [
            [arrondi2(u.x + ((ax - u.x) / lf) * (R + 0.3)), arrondi2(u.y + ((ay - u.y) / lf) * (R + 0.3))],
            [arrondi2(ax), arrondi2(ay)],
          ],
          ferme: false,
          trait: { couleur: "vert", epaisseur: 0.35, tirets: null },
        });
      }
      elements.push({
        type: "texte",
        x: arrondi2(choix.b[0]),
        y: arrondi2(choix.b[1]),
        l: arrondi2(choix.b[2] - choix.b[0]),
        h: arrondi2(choix.b[3] - choix.b[1]),
        texte: u.nom,
        police: "Playfair Display",
        style: "Bold",
        corps: CORPS,
        couleur: "encre",
        alignement: choix.aligne,
        vertical: "centre",
      });
    }
    return elements;
  }

  /**
   * La couverture dans le style par défaut (`assets/covers/… par défaut.png`) :
   *
   * - **première** : la photo en pleine page, le titre en haut, les voyageurs
   *   et le mois du voyage en bas, en blanc ;
   * - **dos** : le papier beige de la quatrième, le titre et les voyageurs à
   *   l'encre, de bas en haut, à la française ;
   * - **quatrième** : sur le papier, dans un cadre pointillé, la carte des
   *   villes (ou des îles) où le voyage a séjourné, reliées dans l'ordre de
   *   visite, « Mon voyage en quelques chiffres » et le logo. Pas de photo : le
   *   style par défaut n'en a pas en quatrième.
   *
   * `recto` : `{ fichier, src, px: [l, h], focus }` ou `null` (aplat vert) ;
   * `carte` : `{ lieux, detail }` (`Voyage.lieuxDeSejour`, contours détaillés) ;
   * `logo` : `{ fichier, src, px }` ou `null`.
   */
  function maquette({ fiche = FICHE_DEFAUT, textes, recto = null, chiffres = [], carte = null, logo = null }) {
    const f = fiche.fondPerdu;
    const L = fiche.largeurPlat;
    const D = fiche.dos;
    const H = fiche.hauteurPlat;
    const m = fiche.marge;
    const xRecto = L + D;
    const el = [];

    // Quatrième : le papier, fond perdu compris.
    el.push({ type: "rect", x: -f, y: -f, l: L + f, h: H + 2 * f, fond: "papier", trait: null });
    // Dos : le papier de la quatrième, qui se prolonge jusqu'au pli de la première.
    el.push({ type: "rect", x: L, y: -f, l: D, h: H + 2 * f, fond: "papier", trait: null });
    // Première : la photo, fond perdu compris, ou un aplat.
    if (recto) {
      el.push({ type: "image", x: xRecto, y: -f, l: L + f, h: H + 2 * f, fichier: recto.fichier, src: recto.src, px: recto.px, focus: recto.focus || [0.5, 0.35] });
    } else {
      el.push({ type: "rect", x: xRecto, y: -f, l: L + f, h: H + 2 * f, fond: "vert", trait: null });
    }

    // Première : le titre, aussi grand que la largeur le permet (72 pt au plus).
    const largeurUtile = L - m - CHARNIERE;
    const titre = String(textes?.titre || "");
    const corpsTitre = Math.max(28, Math.min(72, (largeurUtile / largeurTexte(titre, 1, 0.55)) * 0.98));
    const lignesTitre = largeurTexte(titre, corpsTitre, 0.55) > largeurUtile ? 2 : 1;
    el.push({
      type: "texte",
      x: xRecto + CHARNIERE,
      y: m,
      l: largeurUtile,
      h: corpsTitre * MM_PAR_PT * 1.15 * lignesTitre,
      texte: titre,
      police: "Playfair Display",
      style: "Bold",
      corps: arrondi2(corpsTitre),
      couleur: "blanc",
      alignement: "centre",
      vertical: "haut",
      ombre: true,
    });
    const bas = [textes?.voyageurs, textes?.dates].filter(Boolean);
    if (bas.length) {
      const corpsBas = 15;
      const h = corpsBas * MM_PAR_PT * 1.3 * bas.length;
      el.push({
        type: "texte",
        x: xRecto + CHARNIERE,
        y: H - m - h,
        l: largeurUtile,
        h,
        texte: bas.join("\n"),
        police: "Playfair Display",
        style: "Regular",
        corps: corpsBas,
        couleur: "blanc",
        alignement: "centre",
        vertical: "bas",
        ombre: true,
      });
    }

    // Dos : de bas en haut, centré dans la largeur.
    if (D >= DOS_MIN_TEXTE) {
      const corpsDos = arrondi2(Math.min(11, (D * 0.45) / MM_PAR_PT));
      const texteDos = [titre, textes?.voyageurs].filter(Boolean).join("  ·  ");
      const longueur = H - 2 * m;
      el.push({
        type: "texte",
        // Le cadre est posé à plat, centré sur le dos, puis tourné de 90°.
        x: arrondi2(L + D / 2 - longueur / 2),
        y: arrondi2(H / 2 - D / 2),
        l: longueur,
        h: D,
        texte: texteDos,
        police: "Playfair Display",
        style: "Bold",
        corps: corpsDos,
        couleur: "encre",
        alignement: "centre",
        vertical: "centre",
        rotation: 90,
      });
    }

    // Quatrième : le cadre pointillé, dans la zone sûre.
    const cx0 = m;
    const cx1 = L - m;
    el.push({
      type: "rect",
      x: cx0,
      y: m,
      l: cx1 - cx0,
      h: H - 2 * m,
      fond: null,
      trait: { couleur: "vert", epaisseur: 0.5, tirets: [1.6, 1.6] },
    });
    const interieur = cx1 - cx0;
    // La carte, sur un peu plus de la moitié haute.
    const zoneCarte = { x: cx0 + 8, y: m + 8, l: interieur - 16, h: (H - 2 * m) * 0.5 };
    if (carte?.lieux?.length) el.push(...elementsCarte(carte, zoneCarte));

    // « Mon voyage en quelques chiffres ».
    const boite = { x: cx0 + 10, y: m + (H - 2 * m) * 0.6, l: interieur - 20, h: 46 };
    if (chiffres.length) {
      el.push({ type: "rect", x: boite.x, y: boite.y, l: boite.l, h: boite.h, fond: null, rayon: 5, trait: { couleur: "vert", epaisseur: 0.75, tirets: null } });
      el.push({
        type: "texte",
        x: boite.x,
        y: boite.y + 5,
        l: boite.l,
        h: 6,
        texte: "Mon voyage en quelques chiffres",
        police: "Playfair Display",
        style: "Bold",
        corps: 11,
        couleur: "encre",
        alignement: "centre",
        vertical: "centre",
      });
      const colonne = boite.l / chiffres.length;
      chiffres.forEach((c, i) => {
        const x = boite.x + i * colonne;
        el.push({
          type: "texte",
          x: arrondi2(x),
          y: boite.y + 14,
          l: arrondi2(colonne),
          h: 12,
          texte: c.valeur,
          police: "Playfair Display",
          style: "Black",
          corps: 30,
          couleur: "encre",
          alignement: "centre",
          vertical: "bas",
        });
        el.push({
          type: "texte",
          x: arrondi2(x),
          y: boite.y + 27,
          l: arrondi2(colonne),
          h: 12,
          texte: c.libelle,
          police: "Playfair Display",
          style: "Regular",
          corps: 10,
          couleur: "encre",
          alignement: "centre",
          vertical: "haut",
        });
      });
    }

    // Le logo, centré sous les chiffres.
    if (logo) {
      const l = 16;
      const h = logo.px ? (l * logo.px[1]) / logo.px[0] : l;
      el.push({ type: "image", x: arrondi2(cx0 + interieur / 2 - l / 2), y: arrondi2(H - m - 6 - h), l, h, fichier: logo.fichier, src: logo.src, px: logo.px, focus: [0.5, 0.5], contenir: true });
    }

    return {
      fiche,
      largeur: 2 * L + D,
      hauteur: H,
      fondPerdu: f,
      marge: m,
      plats: { verso: [0, L], dos: [L, L + D], recto: [xRecto, xRecto + L] },
      elements: el,
    };
  }

  /* ------------------------------------------------- l'aperçu (HTML, SVG) --- */

  const echapper = (t) =>
    String(t ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");

  /** Le placement d'une image qui remplit (ou tient dans) son cadre, point focal compris. */
  function placementImage(e) {
    const [pl, ph] = e.px || [1, 1];
    const echelle = e.contenir ? Math.min(e.l / pl, e.h / ph) : Math.max(e.l / pl, e.h / ph);
    const l = pl * echelle;
    const h = ph * echelle;
    const [fx, fy] = e.focus || [0.5, 0.5];
    return { x: e.x + (e.l - l) * fx, y: e.y + (e.h - h) * fy, l, h };
  }

  /** Les lignes d'un texte, et la position de la première ligne de base. */
  function lignesDe(e) {
    const lignes = String(e.texte).split("\n");
    const corps = e.corps * MM_PAR_PT;
    const interligne = corps * 1.2;
    const hauteurBloc = interligne * (lignes.length - 1) + corps * 0.72;
    const debut =
      e.vertical === "bas" ? e.y + e.h - hauteurBloc + corps * 0.72 - corps * 0.2
        : e.vertical === "centre" ? e.y + (e.h - hauteurBloc) / 2 + corps * 0.72
          : e.y + corps * 0.95;
    return { lignes, interligne, debut };
  }

  const POIDS = { Regular: 400, Bold: 700, Black: 900 };

  function elementSvg(e, i, couleurs) {
    const coul = (nom) => (nom ? couleurs[nom]?.hex || nom : "none");
    const trait = (t) =>
      t
        ? ` stroke="${coul(t.couleur)}" stroke-width="${arrondi2(t.epaisseur * MM_PAR_PT)}"${
            t.tirets ? ` stroke-dasharray="${t.tirets.map((v) => arrondi2(v * MM_PAR_PT)).join(" ")}" stroke-linecap="round"` : ""
          }`
        : "";
    if (e.type === "rect") {
      return `<rect x="${e.x}" y="${e.y}" width="${e.l}" height="${e.h}"${e.rayon ? ` rx="${e.rayon}"` : ""} fill="${coul(e.fond)}"${trait(e.trait)}/>`;
    }
    if (e.type === "image") {
      const p = placementImage(e);
      return (
        `<clipPath id="c${i}"><rect x="${e.x}" y="${e.y}" width="${e.l}" height="${e.h}"/></clipPath>` +
        `<image clip-path="url(#c${i})" href="${echapper(e.src || "")}" x="${arrondi2(p.x)}" y="${arrondi2(p.y)}" width="${arrondi2(p.l)}" height="${arrondi2(p.h)}" preserveAspectRatio="none"/>`
      );
    }
    if (e.type === "cercle") {
      return `<circle cx="${e.cx}" cy="${e.cy}" r="${e.r}" fill="${coul(e.fond)}"${trait(e.trait)}/>`;
    }
    if (e.type === "chemin") {
      const [a, ...reste] = e.points;
      const d = e.courbe
        ? `M${a[0]} ${a[1]}Q${e.courbe[0]} ${e.courbe[1]} ${reste[0][0]} ${reste[0][1]}`
        : `M${e.points.map((p) => p.join(" ")).join("L")}${e.ferme ? "Z" : ""}`;
      return `<path d="${d}" fill="${coul(e.fond)}"${trait(e.trait)} stroke-linejoin="round"/>`;
    }
    if (e.type === "texte") {
      const { lignes, interligne, debut } = lignesDe(e);
      const ancre = e.alignement === "gauche" ? "start" : e.alignement === "droite" ? "end" : "middle";
      const x = e.alignement === "gauche" ? e.x : e.alignement === "droite" ? e.x + e.l : e.x + e.l / 2;
      const tspans = lignes
        .map((l, k) => `<tspan x="${arrondi2(x)}" y="${arrondi2(debut + k * interligne)}">${echapper(l)}</tspan>`)
        .join("");
      const rotation = e.rotation
        ? ` transform="rotate(${-e.rotation} ${arrondi2(e.x + e.l / 2)} ${arrondi2(e.y + e.h / 2)})"`
        : "";
      return (
        `<text font-family="'${e.police}', serif" font-weight="${POIDS[e.style] || 400}" font-size="${arrondi2(e.corps * MM_PAR_PT)}" ` +
        `fill="${coul(e.couleur)}" text-anchor="${ancre}"${e.ombre ? ' filter="url(#ombre)"' : ""}${rotation}>${tspans}</text>`
      );
    }
    return "";
  }

  /** La maquette en SVG, en millimètres, fond perdu compris. */
  function versSvg(mq, { reperes = false } = {}) {
    const f = mq.fondPerdu;
    const W = mq.largeur + 2 * f;
    const H = mq.hauteur + 2 * f;
    const corps = mq.elements.map((e, i) => elementSvg(e, i, COULEURS)).join("\n");
    const m = mq.marge;
    const reperesSvg = reperes
      ? `<g class="reperes" fill="none" stroke-width="0.3">` +
        `<rect x="0" y="0" width="${mq.largeur}" height="${mq.hauteur}" stroke="#e2342d" stroke-dasharray="1.5 1"/>` +
        `<line x1="${mq.plats.dos[0]}" y1="${-f}" x2="${mq.plats.dos[0]}" y2="${mq.hauteur + f}" stroke="#1f7a4d" stroke-dasharray="1.5 1"/>` +
        `<line x1="${mq.plats.dos[1]}" y1="${-f}" x2="${mq.plats.dos[1]}" y2="${mq.hauteur + f}" stroke="#1f7a4d" stroke-dasharray="1.5 1"/>` +
        `<rect x="${m}" y="${m}" width="${mq.plats.verso[1] - 2 * m}" height="${mq.hauteur - 2 * m}" stroke="#1f5fd6" stroke-dasharray="0.6 0.8"/>` +
        `<rect x="${mq.plats.recto[0] + CHARNIERE}" y="${m}" width="${mq.plats.recto[1] - mq.plats.recto[0] - m - CHARNIERE}" height="${mq.hauteur - 2 * m}" stroke="#1f5fd6" stroke-dasharray="0.6 0.8"/>` +
        `</g>`
      : "";
    return (
      `<svg xmlns="http://www.w3.org/2000/svg" width="${arrondi2(W)}mm" height="${arrondi2(H)}mm" viewBox="${-f} ${-f} ${arrondi2(W)} ${arrondi2(H)}">` +
      `<defs><filter id="ombre" x="-5%" y="-20%" width="110%" height="140%"><feDropShadow dx="0.25" dy="0.35" stdDeviation="0.6" flood-color="#000" flood-opacity="0.4"/></filter></defs>` +
      `${corps}${reperesSvg}</svg>`
    );
  }

  /**
   * La page HTML de l'aperçu, prête à enregistrer en PDF au format exact de la
   * feuille. `polices` : `fonts.css` du gabarit (Playfair Display).
   */
  function versHtml(mq, { polices = "", alertes = [], titre = "" } = {}) {
    const f = mq.fondPerdu;
    const W = arrondi2(mq.largeur + 2 * f);
    const H = arrondi2(mq.hauteur + 2 * f);
    // `fonts.css` arrive enveloppé dans ses propres balises `<style>` (c'est la
    // forme qu'attend APITemplate) : posé tel quel dans la nôtre, il la
    // fermerait, et tout le CSS de la couverture partirait en texte.
    const css = String(polices || "").replace(/<\/?style[^>]*>/gi, "");
    return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8" />
<title>Couverture — ${echapper(titre)}</title>
<style>
${css}
@page { size: ${W}mm ${H}mm; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body { background: #6b6259; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.feuille svg { display: block; }
.barre {
  position: sticky; top: 0; z-index: 10;
  padding: 10px 16px; background: #fff; color: #2b231b;
  font: 13px/1.45 system-ui, sans-serif;
  box-shadow: 0 1px 4px rgba(0,0,0,0.2);
}
.barre ul { margin: 6px 0 0; padding-left: 18px; }
.barre .alerte { color: #b3261e; }
.barre button { font: inherit; padding: 4px 10px; margin-right: 8px; cursor: pointer; }
.cadre-ecran { padding: 24px; }
body.sans-reperes .reperes { display: none; }
@media print {
  body { background: none; }
  .barre, .reperes { display: none !important; }
  .cadre-ecran { padding: 0; }
}
</style>
</head>
<body>
<div class="barre">
  <strong>Couverture Pumbo — ${W} × ${H} mm</strong>
  (plats ${mq.fiche.largeurPlat} × ${mq.fiche.hauteurPlat} mm, dos ${mq.fiche.dos} mm, fond perdu ${f} mm ; ${echapper(mq.fiche.source)}).
  <ul>
    <li>Pour le PDF : <em>Imprimer</em> → <em>Enregistrer au format PDF</em>, Marges <em>Aucune</em>, <em>Graphiques d'arrière-plan</em> coché. Le fichier InDesign se télécharge depuis l'atelier.</li>
    <li>Repères (à l'écran seulement) : <span style="color:#e2342d">coupe</span>, <span style="color:#1f7a4d">plis du dos</span>, <span style="color:#1f5fd6">zone sûre</span>.</li>
    ${alertes.map((a) => `<li class="alerte">${echapper(a)}</li>`).join("\n    ")}
  </ul>
  <div style="margin-top:6px">
    <button onclick="window.print()">Enregistrer en PDF…</button>
    <button onclick="document.body.classList.toggle('sans-reperes')">Masquer / montrer les repères</button>
  </div>
</div>
<div class="cadre-ecran"><div class="feuille">${versSvg(mq, { reperes: true })}</div></div>
</body>
</html>`;
  }

  /* -------------------------------------------------- le script InDesign --- */

  /** CMJN approché d'une couleur RVB : un point de départ, que l'imprimeur affinera. */
  function cmjn(hex) {
    const v = hex.replace("#", "");
    const r = parseInt(v.slice(0, 2), 16) / 255;
    const g = parseInt(v.slice(2, 4), 16) / 255;
    const b = parseInt(v.slice(4, 6), 16) / 255;
    const k = 1 - Math.max(r, g, b);
    if (k >= 1) return [0, 0, 0, 100];
    const c = (1 - r - k) / (1 - k);
    const m = (1 - g - k) / (1 - k);
    const y = (1 - b - k) / (1 - k);
    return [c, m, y, k].map((x) => Math.round(x * 100));
  }

  /** Une valeur JavaScript en littéral ES3, en ASCII : ExtendScript lit mal l'UTF-8 sans BOM. */
  const litteral = (valeur) => JSON.stringify(valeur).replace(/[\u007f-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);

  /**
   * Le script InDesign (ExtendScript, donc ES3 : ni `let`, ni fonctions
   * fléchées, ni `JSON`) qui construit la couverture.
   *
   * Il reprend mot pour mot la mise en place de la fiche Pumbo — trois pages
   * verso, dos, recto sur une seule planche, fond perdu, marges —, puis pose
   * chaque élément de la maquette en objets InDesign modifiables : la photo
   * liée depuis le dossier `Liens/` posé à côté du script, les textes en
   * Playfair Display, la carte en tracés vectoriels, les nuances en CMJN.
   */
  function versJsx(mq, { titre = "" } = {}) {
    const fi = mq.fiche;
    const couleurs = Object.fromEntries(Object.entries(COULEURS).map(([cle, c]) => [cle, { nom: c.nom, cmjn: cmjn(c.hex) }]));
    const elements = mq.elements.map((e) => {
      if (e.type !== "image") return e;
      const { src, ...reste } = e;
      return { ...reste, place: placementImage(e) };
    });
    return `//@target indesign
// Couverture MemoBook - ${litteral(titre).slice(1, -1)}
// Produit par l'atelier MemoBook (https://hugo-jouffre.github.io/memo-book/).
// Planche ${mq.largeur + 2 * mq.fondPerdu} x ${mq.hauteur + 2 * mq.fondPerdu} mm, fond perdu compris :
// plats ${fi.largeurPlat} x ${fi.hauteurPlat} mm, dos ${fi.dos} mm, fond perdu ${fi.fondPerdu} mm.
//
// Mode d'emploi : LISEZMOI.txt, dans le meme dossier.

var COULEURS = ${litteral(couleurs)};
var ELEMENTS = ${litteral(elements)};

(function () {
  var dossier = File($.fileName).parent;
  var manquantes = [];
  var absents = [];

  // --- La mise en place de la fiche Pumbo, a l'identique.
  var myDocument = app.documents.add({
    documentPreferences: {
      pagesPerDocument: 3,
      facingPages: false,
      pageOrientation: PageOrientation.portrait,
      documentBleedUniformSize: true,
      documentBleedTopOffset: "${fi.fondPerdu}mm"
    }
  });
  myDocument.spreads.everyItem().allowPageShuffle = false;
  myDocument.pages.item(1).marginPreferences.properties = {top:"0mm",bottom:"0mm",left:"0mm",right:"0mm"};
  myDocument.pages.item(0).adjustLayout({width:"${fi.largeurPlat}mm", height:"${fi.hauteurPlat}mm"});
  myDocument.pages.item(1).adjustLayout({width:"${fi.dos}mm", height:"${fi.hauteurPlat}mm"});
  myDocument.pages.item(2).adjustLayout({width:"${fi.largeurPlat}mm", height:"${fi.hauteurPlat}mm"});
  myDocument.pages.item(1).move(LocationOptions.AFTER, myDocument.pages.item(0));
  myDocument.pages.item(2).move(LocationOptions.AFTER, myDocument.pages.item(1));
  myDocument.pages.item(0).marginPreferences.properties = {top:"${fi.marge}mm",bottom:"${fi.marge}mm",left:"${fi.marge}mm",right:"0mm"};
  myDocument.pages.item(1).marginPreferences.properties = {top:"0mm",bottom:"0mm",left:"0mm",right:"0mm"};
  myDocument.pages.item(2).marginPreferences.properties = {top:"${fi.marge}mm",bottom:"${fi.marge}mm",left:"0mm",right:"${fi.marge}mm"};

  // --- Le repere de la maquette : millimetres, origine en haut a gauche de la planche.
  myDocument.viewPreferences.horizontalMeasurementUnits = MeasurementUnits.MILLIMETERS;
  myDocument.viewPreferences.verticalMeasurementUnits = MeasurementUnits.MILLIMETERS;
  myDocument.viewPreferences.rulerOrigin = RulerOrigin.SPREAD_ORIGIN;
  myDocument.zeroPoint = [0, 0];
  var planche = myDocument.spreads.item(0);

  var calques = {
    fond: myDocument.layers.item(0),
    carte: myDocument.layers.add({name: "Carte"}),
    textes: myDocument.layers.add({name: "Textes"})
  };
  calques.fond.name = "Photo et fonds";

  function aucune() {
    try { var s = myDocument.swatches.itemByName("None"); s.name; return s; }
    catch (e) { return myDocument.swatches.item(0); }
  }
  var vide = aucune();

  var nuances = {};
  for (var cle in COULEURS) {
    if (!COULEURS.hasOwnProperty(cle)) continue;
    nuances[cle] = myDocument.colors.add({
      name: COULEURS[cle].nom,
      model: ColorModel.PROCESS,
      space: ColorSpace.CMYK,
      colorValue: COULEURS[cle].cmjn
    });
  }

  var tirets = {};
  function styleTirets(motif) {
    var nom = "MemoBook tirets " + motif.join("-");
    if (!tirets[nom]) tirets[nom] = myDocument.dashedStrokeStyles.add({name: nom, dashArray: motif});
    return tirets[nom];
  }

  function habiller(objet, e) {
    objet.fillColor = e.fond ? nuances[e.fond] : vide;
    if (e.trait) {
      objet.strokeWeight = e.trait.epaisseur + "pt";
      objet.strokeColor = nuances[e.trait.couleur];
      if (e.trait.tirets) {
        objet.strokeType = styleTirets(e.trait.tirets);
        objet.endCap = EndCap.ROUND_END_CAP;
      }
    } else {
      objet.strokeWeight = 0;
      objet.strokeColor = vide;
    }
  }

  function bornes(e) { return [e.y, e.x, e.y + e.h, e.x + e.l]; }

  function rectangle(e) {
    var r = planche.rectangles.add(calques.fond, undefined, undefined, {geometricBounds: bornes(e)});
    habiller(r, e);
    if (e.rayon) {
      r.topLeftCornerOption = CornerOptions.ROUNDED_CORNER;
      r.topRightCornerOption = CornerOptions.ROUNDED_CORNER;
      r.bottomLeftCornerOption = CornerOptions.ROUNDED_CORNER;
      r.bottomRightCornerOption = CornerOptions.ROUNDED_CORNER;
      r.topLeftCornerRadius = e.rayon + "mm";
      r.topRightCornerRadius = e.rayon + "mm";
      r.bottomLeftCornerRadius = e.rayon + "mm";
      r.bottomRightCornerRadius = e.rayon + "mm";
    }
    return r;
  }

  function image(e) {
    var r = planche.rectangles.add(calques.fond, undefined, undefined, {geometricBounds: bornes(e)});
    habiller(r, {fond: null, trait: null});
    var fichier = File(dossier.fullName + "/" + e.fichier);
    if (!fichier.exists) { absents.push(e.fichier); return r; }
    r.place(fichier);
    var g = r.allGraphics[0];
    // Remplir le cadre, puis caler la photo sur son point focal.
    r.fit(e.contenir ? FitOptions.PROPORTIONALLY : FitOptions.FILL_PROPORTIONALLY);
    var gb = g.geometricBounds;
    g.move(undefined, [e.place.x - gb[1], e.place.y - gb[0]]);
    return r;
  }

  function texte(e) {
    var t = planche.textFrames.add(calques.textes, undefined, undefined, {geometricBounds: bornes(e)});
    t.contents = e.texte.split("\\n").join("\\r");
    var r = t.texts.item(0);
    try { r.appliedFont = e.police; r.fontStyle = e.style; }
    catch (erreur) { manquantes.push(e.police + " " + e.style); }
    r.pointSize = e.corps;
    r.leading = e.corps * 1.2;
    r.fillColor = nuances[e.couleur];
    r.justification = e.alignement === "gauche" ? Justification.LEFT_ALIGN
      : e.alignement === "droite" ? Justification.RIGHT_ALIGN : Justification.CENTER_ALIGN;
    t.textFramePreferences.insetSpacing = [0, 0, 0, 0];
    t.textFramePreferences.verticalJustification = e.vertical === "bas" ? VerticalJustification.BOTTOM_ALIGN
      : e.vertical === "centre" ? VerticalJustification.CENTER_ALIGN : VerticalJustification.TOP_ALIGN;
    if (e.ombre) {
      var ombre = t.transparencySettings.dropShadowSettings;
      ombre.mode = ShadowMode.DROP;
      ombre.opacity = 40;
      ombre.size = 1.2;
      ombre.xOffset = 0.25;
      ombre.yOffset = 0.35;
    }
    if (e.rotation) {
      t.transform(CoordinateSpaces.PASTEBOARD_COORDINATES, AnchorPoint.CENTER_ANCHOR,
        app.transformationMatrices.add({counterclockwiseRotationAngle: e.rotation}));
    }
    return t;
  }

  function chemin(e) {
    var objet = e.ferme ? planche.polygons.add(calques.carte) : planche.graphicLines.add(calques.carte);
    var points = e.points;
    if (e.courbe) {
      // Une courbe quadratique en Bezier : deux points, leurs directions.
      var a = points[0], b = points[1], c = e.courbe;
      var c1 = [a[0] + (c[0] - a[0]) * 2 / 3, a[1] + (c[1] - a[1]) * 2 / 3];
      var c2 = [b[0] + (c[0] - b[0]) * 2 / 3, b[1] + (c[1] - b[1]) * 2 / 3];
      points = [[a, a, c1], [c2, b, b]];
    }
    objet.paths.item(0).entirePath = points;
    habiller(objet, e);
    return objet;
  }

  function cercle(e) {
    var o = planche.ovals.add(calques.carte, undefined, undefined, {geometricBounds: [e.cy - e.r, e.cx - e.r, e.cy + e.r, e.cx + e.r]});
    habiller(o, e);
    return o;
  }

  function construire() {
    for (var i = 0; i < ELEMENTS.length; i++) {
      var e = ELEMENTS[i];
      if (e.type === "rect") rectangle(e);
      else if (e.type === "image") image(e);
      else if (e.type === "texte") texte(e);
      else if (e.type === "chemin") chemin(e);
      else if (e.type === "cercle") cercle(e);
    }
  }

  app.doScript(construire, ScriptLanguage.JAVASCRIPT, undefined, UndoModes.ENTIRE_SCRIPT, "Couverture MemoBook");
  myDocument.layoutWindows[0].zoom(ZoomOptions.FIT_SPREAD);

  var messages = [];
  if (absents.length) messages.push("Images introuvables (le dossier Liens doit rester a cote du script) : " + absents.join(", "));
  if (manquantes.length) messages.push("Polices a installer (Google Fonts, gratuites) : Playfair Display.");
  if (messages.length) alert(messages.join("\\r\\r"));
})();
`;
  }

  /* ----------------------------------------------------------------- zip --- */

  const TABLE_CRC = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n += 1) {
      let c = n;
      for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();

  function crc32(octets) {
    let c = 0xffffffff;
    for (let i = 0; i < octets.length; i += 1) c = TABLE_CRC[(c ^ octets[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  }

  /**
   * Une archive `.zip` sans compression (les photos sont déjà compressées) :
   * `[{ nom, octets: Uint8Array }]` → `Uint8Array`. Noms en UTF-8 (bit 11).
   */
  function zipper(fichiers) {
    const enc = new TextEncoder();
    const locaux = [];
    const centraux = [];
    let decalage = 0;
    for (const { nom, octets } of fichiers) {
      const n = enc.encode(nom);
      const crc = crc32(octets);
      const local = new Uint8Array(30 + n.length);
      const dv = new DataView(local.buffer);
      dv.setUint32(0, 0x04034b50, true);
      dv.setUint16(4, 20, true);
      dv.setUint16(6, 0x0800, true);
      dv.setUint16(8, 0, true);
      dv.setUint16(10, 0, true);
      dv.setUint16(12, 0x21, true);
      dv.setUint32(14, crc, true);
      dv.setUint32(18, octets.length, true);
      dv.setUint32(22, octets.length, true);
      dv.setUint16(26, n.length, true);
      dv.setUint16(28, 0, true);
      local.set(n, 30);
      const central = new Uint8Array(46 + n.length);
      const dc = new DataView(central.buffer);
      dc.setUint32(0, 0x02014b50, true);
      dc.setUint16(4, 20, true);
      dc.setUint16(6, 20, true);
      dc.setUint16(8, 0x0800, true);
      dc.setUint16(10, 0, true);
      dc.setUint16(12, 0, true);
      dc.setUint16(14, 0x21, true);
      dc.setUint32(16, crc, true);
      dc.setUint32(20, octets.length, true);
      dc.setUint32(24, octets.length, true);
      dc.setUint16(28, n.length, true);
      dc.setUint32(42, decalage, true);
      central.set(n, 46);
      locaux.push(local, octets);
      centraux.push(central);
      decalage += local.length + octets.length;
    }
    const tailleCentral = centraux.reduce((t, c) => t + c.length, 0);
    const fin = new Uint8Array(22);
    const df = new DataView(fin.buffer);
    df.setUint32(0, 0x06054b50, true);
    df.setUint16(8, fichiers.length, true);
    df.setUint16(10, fichiers.length, true);
    df.setUint32(12, tailleCentral, true);
    df.setUint32(16, decalage, true);
    const tout = new Uint8Array(decalage + tailleCentral + 22);
    let pos = 0;
    for (const morceau of [...locaux, ...centraux, fin]) {
      tout.set(morceau, pos);
      pos += morceau.length;
    }
    return tout;
  }

  /** Le mode d'emploi du dossier InDesign. */
  function lisezmoi({ titre, fiche }) {
    return [
      `Couverture MemoBook — ${titre}`,
      "",
      `Planche : plats ${fiche.largeurPlat} x ${fiche.hauteurPlat} mm, dos ${fiche.dos} mm, fond perdu ${fiche.fondPerdu} mm (${fiche.source}).`,
      "",
      "1. Installer la police Playfair Display (gratuite) : https://fonts.google.com/specimen/Playfair+Display",
      "2. Dans InDesign : Fenêtre > Utilitaires > Scripts. Clic droit sur « Utilisateur » > Faire apparaître dans le Finder (ou l'Explorateur).",
      "3. Copier ce dossier entier (le script et le dossier Liens) dans le dossier qui s'ouvre.",
      "4. Double-cliquer sur « Couverture MemoBook.jsx » dans le panneau Scripts : le document se construit.",
      "5. Fichier > Enregistrer sous… pour garder le .indd, puis Fichier > Exporter en PDF (PDF/X-4) pour Pumbo.",
      "",
      fiche.pages
        ? `Dos de ${String(fiche.dos).replace(".", ",")} mm pour ${fiche.pages} pages intérieures (barème Pumbo : 8 mm jusqu'à 56 pages, puis 3 mm + 0,09 mm par page). Si le carnet change de nombre de pages, refaire le fichier.`
        : "Le dos dépend du nombre de pages : vérifier qu'il correspond à la commande.",
      "",
    ].join("\r\n");
  }

  const api = {
    FICHE_DEFAUT,
    PAGES_MIN,
    dosPumbo,
    ficheDuCarnet,
    pagesDuPdf,
    CHARNIERE,
    SEUILS,
    COULEURS,
    lireFichePumbo,
    geometrie,
    dpiSurRecto,
    evaluerPhoto,
    proposerPhotos,
    moisDuVoyage,
    listeNoms,
    textesParDefaut,
    chiffresQuatrieme,
    cadreQuatrieme,
    couperPolyligne,
    maquette,
    placementImage,
    versSvg,
    versHtml,
    versJsx,
    cmjn,
    crc32,
    zipper,
    lisezmoi,
  };

  if (enNode) module.exports = api;
  else racine.Couverture = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
