/*
 * Les styles de couverture — tout ce qui change d'un style à l'autre :
 * palette, polices, textes, et la maquette de la première, du dos et de la
 * quatrième (Hugo, 09/10/2026, spécifications des styles ; 13/10/2026, reprise
 * du chantier).
 *
 * `couverture.js` reste le moteur : géométrie de la fiche Pumbo, faces
 * visibles, dos, et les deux sorties (aperçu SVG / HTML, script InDesign). Un
 * style ne fait que poser des éléments — rectangles, images, textes, blocs de
 * paragraphes, courbes, textes sur tracé — dans le repère de la planche, en
 * millimètres.
 *
 * Les textes de chaque style sont **rédigés par l'IA d'après les récits**
 * (`consigneTextes`), puis **modifiables** par le voyageur dans l'atelier ;
 * ceux que la spécification veut fixes ont une valeur par défaut, modifiable
 * elle aussi.
 *
 * Pour tous les styles, le dos prend la couleur de fond de la quatrième, et
 * ses textes la police et la couleur du corps de texte de la quatrième — ou,
 * s'il n'y en a pas, de son titre.
 *
 * Les styles qui demandent des images générées (Assouline, Aquarelle, Travel
 * book, Photo-dessin) sont listés mais pas encore disponibles : `dispo: false`.
 */
(function (racine) {
  "use strict";

  const enNode = typeof module !== "undefined" && module.exports;
  const C = enNode ? require("./couverture.js") : null;
  /** Le moteur, lu au moment de servir : l'ordre des <script> n'y peut rien. */
  const moteur = () => C || racine.Couverture;

  /** Les maquettes de référence, servies par GitHub à une adresse publique. */
  const REFERENCES = "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/assets/covers/";
  const reference = (face, nom) =>
    `${REFERENCES}${encodeURIComponent(`${face} covers`)}/${encodeURIComponent(`${face} cover_style ${nom}`)}.png`;

  /**
   * Les sept styles du catalogue de l'app (`backend/src/services/coverCatalogue.ts`),
   * dans le même ordre. `id` est celui de l'app, sans le préfixe de face.
   */
  const STYLES = [
    { id: "default", nom: "Par défaut", ref: "par défaut", dispo: true },
    { id: "watercolor", nom: "Aquarelle", ref: "aquarelle", dispo: false },
    { id: "assouline", nom: "Assouline", ref: "assouline", dispo: false },
    { id: "drawing", nom: "Dessin", ref: "dessin", dispo: true },
    { id: "photo-drawing", nom: "Photo-dessin", ref: "photo-dessin", dispo: false },
    { id: "travel-book", nom: "Travel book", ref: "travel book", dispo: false },
    { id: "elegant", nom: "Élégant", ref: "élégant", dispo: true },
  ].map((s) => ({ ...s, recto: reference("front", s.ref), verso: reference("back", s.ref) }));

  const styleDe = (id) => STYLES.find((s) => s.id === id) || STYLES[0];

  /**
   * Hansley n'est pas encore imprimable : sa licence n'est pas vérifiée (Hugo,
   * 13/10/2026). Les titres du style Dessin restent en Gloria Hallelujah
   * jusque-là — changer cette constante suffira.
   */
  const POLICE_TITRE_DESSIN = "Gloria Hallelujah";

  /** Les polices de chaque style : l'aperçu les charge, le mode d'emploi InDesign les nomme. */
  const POLICES = {
    default: ["Playfair Display"],
    elegant: ["Cormorant Garamond", "Cormorant Infant"],
    drawing: [POLICE_TITRE_DESSIN, "Gloria Hallelujah"],
  };

  /**
   * Les fichiers des polices de couverture (`public/fonts/couvertures/`), libres
   * (OFL). Playfair Display et Gloria Hallelujah viennent du gabarit du carnet.
   */
  const FICHIERS_POLICES = [
    { famille: "Cormorant Garamond", fichier: "cormorant-garamond", poids: "300 700" },
    { famille: "Cormorant Infant", fichier: "cormorant-infant", poids: "300 700" },
    { famille: "Black Han Sans", fichier: "black-han-sans", poids: "400", sansExt: true },
    { famille: "Manrope", fichier: "manrope", poids: "200 800" },
    { famille: "Caveat Brush", fichier: "caveat-brush", poids: "400" },
    { famille: "Lilita One", fichier: "lilita-one", poids: "400" },
  ];

  /** Le CSS `@font-face` des polices de couverture, d'après l'adresse du dossier `fonts/couvertures/`. */
  function cssPolices(base) {
    const regle = (p, sous, plage) =>
      `@font-face { font-family: "${p.famille}"; font-style: normal; font-weight: ${p.poids}; font-display: block; ` +
      `src: url("${base}${p.fichier}-${sous}.woff2") format("woff2");${plage ? ` unicode-range: ${plage};` : ""} }`;
    return FICHIERS_POLICES.flatMap((p) => [
      regle(p, "latin", "U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD"),
      ...(p.sansExt ? [] : [regle(p, "latin-ext", "U+0100-02AF, U+1E00-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF")]),
    ]).join("\n");
  }

  /* --------------------------------------------------------- les textes --- */

  /** « 2023 – 2024 », « 2026 ». */
  function annees(debut, fin) {
    const a = String(debut || "").slice(0, 4);
    const b = String(fin || "").slice(0, 4) || a;
    if (!/^\d{4}$/.test(a)) return "";
    return a === b ? a : `${a} – ${b}`;
  }

  /**
   * Les champs de texte de chaque style. `ia` : rédigé par l'IA d'après les
   * récits ; sinon une valeur par défaut, modifiable. `lignes` : un champ sur
   * plusieurs lignes (des paragraphes séparés par une ligne vide).
   */
  const CHAMPS = {
    default: [
      { cle: "titre", label: "Titre", ia: false },
      { cle: "voyageurs", label: "Voyageurs", ia: false },
      { cle: "dates", label: "Dates", ia: false },
    ],
    elegant: [
      { cle: "titre", label: "Titre (1re)", ia: true, max: 16, consigne: "le titre de la première, en majuscules : la destination, en un ou deux mots (« PHILIPPINES »)" },
      { cle: "date", label: "Date (1re)", ia: true, max: 24, consigne: "la date sous la photo, en majuscules : le mois et l'année du voyage (« AOÛT 2026 »)" },
      {
        cle: "resume",
        label: "Texte de la 4e",
        ia: true,
        lignes: true,
        max: 380,
        consigne:
          "le texte de la quatrième : deux courts paragraphes séparés par une ligne vide, 380 signes en tout au plus, au ton d'un beau livre — le voyage en une phrase évocatrice (lieux, paysages, ambiance), puis ce que le carnet garde (paysages, rencontres, moments)",
      },
    ],
    drawing: [
      { cle: "titre", label: "Phrase-titre (1re)", ia: true, max: 40, consigne: "la phrase-titre de la première, à la première personne, comme le début d'une histoire, 40 signes au plus, terminée par un point (« Le jour où j'ai tourné la clé. »)" },
      { cle: "annees", label: "Années (1re)", ia: false },
      { cle: "voyageurs", label: "Voyageurs (1re)", ia: false },
      { cle: "titreVerso", label: "Titre de la 4e", ia: true, max: 28, consigne: "le titre de la quatrième, une courte phrase qui dit que le voyage continue, 28 signes au plus, terminée par des points de suspension (« La route continue… »)" },
      { cle: "texteVerso", label: "Texte de la 4e", ia: false, lignes: true },
    ],
  };

  /** Les textes de chaque style quand rien n'est encore rédigé : tirés du carnet. */
  function textesParDefaut(styleId, voyage) {
    const base = moteur().textesParDefaut(voyage);
    const destination = String(voyage.destination || "").trim() || base.titre;
    if (styleId === "elegant") {
      return {
        titre: destination.toUpperCase(),
        date: base.dates.toUpperCase(),
        resume: `Un voyage ${destination ? `en ${destination}` : ""} raconté au fil des étapes.\n\nUn carnet fait de paysages, de rencontres et de petits moments que l'on aurait aimé ne jamais oublier.`.replace("  ", " "),
        ...dos(base),
      };
    }
    if (styleId === "drawing") {
      return {
        titre: `${destination}, mon voyage.`,
        annees: annees(voyage.debut, voyage.fin),
        voyageurs: base.voyageurs,
        titreVerso: "La route continue…",
        texteVerso:
          `Ce carnet a été composé avec MemoBook, à partir des messages vocaux envoyés pendant le voyage.\n\n` +
          (base.voyageurs ? `Merci à ${base.voyageurs} de nous avoir emmenés avec eux.` : "Merci de nous avoir emmenés avec vous."),
        ...dos(base),
      };
    }
    return base;
  }

  /** Les trois textes du dos, les mêmes dans tous les styles. */
  const dos = (base) => ({ dosTitre: base.titre, dosVoyageurs: base.voyageurs, dosDates: base.dates });

  /**
   * La consigne de rédaction des textes d'un style, d'après les récits.
   * `voyage` : `{ destination, titre, voyageurs, dates, etapes: [{ titre, lieu, extrait }] }`.
   * Le modèle répond en JSON, une clé par champ rédigé.
   */
  function consigneTextes(styleId, voyage) {
    const champs = (CHAMPS[styleId] || []).filter((c) => c.ia);
    if (!champs.length) return null;
    const etapes = (voyage.etapes || [])
      .map((e, i) => `${i + 1}. ${[e.titre, e.lieu].filter(Boolean).join(" — ")} : ${String(e.extrait || "").replace(/\s+/g, " ").slice(0, 280)}`)
      .join("\n");
    return `Tu écris les textes de la couverture d'un carnet de voyage imprimé, style « ${styleDe(styleId).nom} ».

Voyage : ${voyage.destination || "non précisé"} — ${voyage.dates || "dates non précisées"}${voyage.voyageurs ? `, par ${voyage.voyageurs}` : ""}.
Titre du carnet : ${voyage.titre || "non précisé"}.

Les étapes, dans l'ordre, avec le début de leur récit :
${etapes || "(aucun récit)"}

Écris, d'après ces récits et sans rien inventer qui les contredise :
${champs.map((c) => `- "${c.cle}" : ${c.consigne}.`).join("\n")}

En français, sans emoji, sans guillemets autour des textes. Réponds uniquement par un objet JSON, sans texte autour :
{${champs.map((c) => `"${c.cle}":""`).join(",")}}`;
  }

  /** Les textes rédigés, nettoyés et bornés. */
  function lireTextes(styleId, reponse) {
    const sortie = {};
    for (const c of CHAMPS[styleId] || []) {
      if (!c.ia) continue;
      const brut = typeof reponse?.[c.cle] === "string" ? reponse[c.cle].trim() : "";
      if (!brut) continue;
      sortie[c.cle] = c.lignes ? brut.replace(/\n{3,}/g, "\n\n") : brut.replace(/\s+/g, " ");
      if (c.max && sortie[c.cle].length > c.max * 1.15) sortie[c.cle] = sortie[c.cle].slice(0, c.max).replace(/\s+\S*$/, "…");
    }
    return sortie;
  }

  /* ------------------------------------------------------- la géométrie --- */

  const arrondi2 = (v) => Math.round(v * 100) / 100;
  const MM_PAR_PT = 25.4 / 72;

  /** Le cadre commun à tous les styles : plats, faces visibles, fond perdu. */
  function planche(fiche) {
    const f = fiche.fondPerdu;
    const L = fiche.largeurPlat;
    const D = fiche.dos;
    const H = fiche.hauteurPlat;
    const xRecto = L + D;
    return {
      f,
      L,
      D,
      H,
      xRecto,
      faces: moteur().facesVisibles(fiche),
      enveloppe: (elements, couleurs) => ({
        fiche,
        largeur: 2 * L + D,
        hauteur: H,
        fondPerdu: f,
        marge: fiche.marge,
        plats: { verso: [0, L], dos: [L, L + D], recto: [xRecto, xRecto + L] },
        faces: moteur().facesVisibles(fiche),
        elements,
        couleurs,
      }),
    };
  }

  /** Les fonds des trois parties, fond perdu compris. */
  function fonds(p, { verso, dos: fondDos = verso, recto }) {
    return [
      { type: "rect", x: -p.f, y: -p.f, l: p.L + p.f, h: p.H + 2 * p.f, fond: verso, trait: null },
      { type: "rect", x: p.L, y: -p.f, l: p.D, h: p.H + 2 * p.f, fond: fondDos, trait: null },
      { type: "rect", x: p.xRecto, y: -p.f, l: p.L + p.f, h: p.H + 2 * p.f, fond: recto, trait: null },
    ];
  }

  /**
   * Coupe un texte en lignes qui tiennent dans `largeur` mm à `corps` pt
   * (largeur moyenne d'un signe : `facteur` × corps). Au plus `max` lignes.
   */
  function couperLignes(texte, corps, largeur, facteur, max = 3) {
    const mots = String(texte || "").split(/\s+/).filter(Boolean);
    const lignes = [];
    let ligne = "";
    for (const mot of mots) {
      const essai = ligne ? `${ligne} ${mot}` : mot;
      if (ligne && moteur().largeurTexte(essai, corps, facteur) > largeur) {
        lignes.push(ligne);
        ligne = mot;
      } else ligne = essai;
    }
    if (ligne) lignes.push(ligne);
    if (lignes.length > max) return [...lignes.slice(0, max - 1), lignes.slice(max - 1).join(" ")];
    return lignes;
  }

  /** Le plus grand corps (entre `min` et `max`) où le texte tient sur `lignes` lignes. */
  function corpsQuiTient(texte, largeur, facteur, { min, max, lignes = 1 }) {
    for (let c = max; c >= min; c -= 0.5) {
      if (couperLignes(texte, c, largeur, facteur, 99).length <= lignes) return c;
    }
    return min;
  }

  /** Le paragraphe d'un champ « lignes » : un paragraphe par bloc séparé d'une ligne vide. */
  const paragraphes = (texte) =>
    String(texte || "")
      .split(/\n\s*\n/)
      .map((p) => p.replace(/\s+/g, " ").trim())
      .filter(Boolean);

  /* ------------------------------------------------------ style Élégant --- */

  const COULEURS_ELEGANT = () => {
    const C0 = moteur().COULEURS;
    return { beige: C0.beige, noir: C0.noir, beigeFonce: C0.beigeFonce, blanc: C0.blanc };
  };

  /**
   * **Élégant** (Hugo, 09/10/2026) : fonds beige, titre en Cormorant Garamond,
   * le reste en Cormorant Infant, tout en noir typo, logo en beige foncé. Deux
   * photos de paysage du voyageur : une grande sur la première, une bande
   * panoramique en tête de la quatrième.
   */
  function maquetteElegant({ fiche, textes, recto, verso, logo }) {
    const p = planche(fiche);
    const el = fonds(p, { verso: "beige", recto: "beige" });
    const face = p.faces.recto;
    const marge = moteur().CHARNIERE;
    const largeur = face.l - 2 * marge;
    const x = face.x + marge;

    // Première : le titre, en capitales espacées, aussi grand que la largeur le permet.
    const titre = String(textes.titre || "").toUpperCase();
    const corpsTitre = corpsQuiTient(titre, largeur, 0.62, { min: 20, max: 46 });
    const hTitre = arrondi2(corpsTitre * MM_PAR_PT * 1.15);
    el.push({ type: "texte", x, y: arrondi2(face.y + 6), l: largeur, h: hTitre, texte: titre, police: "Cormorant Garamond", style: "Regular", corps: corpsTitre, couleur: "noir", alignement: "centre", vertical: "bas", approche: 40 });
    // La date, en pied.
    const date = String(textes.date || "").toUpperCase();
    const hDate = 7;
    const yDate = face.y + face.h - moteur().RETRAIT - hDate;
    el.push({ type: "texte", x, y: arrondi2(yDate), l: largeur, h: hDate, texte: date, police: "Cormorant Infant", style: "Medium", corps: 13, couleur: "noir", alignement: "centre", vertical: "centre", approche: 80 });
    // La photo, entre les deux.
    const yPhoto = face.y + 6 + hTitre + 5;
    const hPhoto = yDate - 6 - yPhoto;
    if (recto) {
      el.push({ type: "image", x, y: arrondi2(yPhoto), l: arrondi2(largeur), h: arrondi2(hPhoto), fichier: recto.fichier, src: recto.src, px: recto.px, focus: recto.focus || [0.5, 0.45] });
    } else {
      el.push({ type: "rect", x, y: arrondi2(yPhoto), l: arrondi2(largeur), h: arrondi2(hPhoto), fond: "beigeFonce", trait: null });
    }

    // Quatrième : la bande panoramique, le texte au centre, le logo en pied.
    const quatrieme = p.faces.verso;
    const xV = quatrieme.x + marge;
    const lV = quatrieme.l - 2 * marge;
    const hBande = arrondi2(lV * 0.32);
    const yBande = quatrieme.y + 8;
    if (verso) {
      el.push({ type: "image", x: xV, y: yBande, l: arrondi2(lV), h: hBande, fichier: verso.fichier, src: verso.src, px: verso.px, focus: verso.focus || [0.5, 0.5] });
    }
    const hLogo = 14;
    const logoH = logo?.px ? (hLogo * logo.px[1]) / logo.px[0] : hLogo;
    const yLogo = quatrieme.y + quatrieme.h - moteur().RETRAIT - logoH;
    const yTexte = yBande + hBande + 14;
    el.push({
      type: "bloc",
      nom: "Texte de la 4e",
      x: arrondi2(xV + 6),
      y: arrondi2(yTexte),
      l: arrondi2(lV - 12),
      h: arrondi2(yLogo - 14 - yTexte),
      paragraphes: paragraphes(textes.resume),
      police: "Cormorant Infant",
      style: "Medium",
      corps: 12.5,
      interligne: 1.45,
      espace: 5,
      couleur: "noir",
      alignement: "centre",
      vertical: "centre",
    });
    if (logo) {
      el.push({ type: "image", x: arrondi2(quatrieme.x + quatrieme.l / 2 - hLogo / 2), y: arrondi2(yLogo), l: hLogo, h: arrondi2(logoH), fichier: logo.fichier, src: logo.src, px: logo.px, focus: [0.5, 0.5], contenir: true });
    }

    // Dos : le fond de la quatrième, la police et la couleur de son texte.
    el.push(...moteur().elementsDos(fiche, texteDuDos(textes), "noir", { police: "Cormorant Infant", style: "Bold" }));
    return p.enveloppe(el, COULEURS_ELEGANT());
  }

  /** Les trois textes du dos d'un style. */
  const texteDuDos = (textes) => ({ titre: textes.dosTitre, voyageurs: textes.dosVoyageurs, dates: textes.dosDates });

  /* ------------------------------------------------------- style Dessin --- */

  const COULEURS_DESSIN = () => {
    const C0 = moteur().COULEURS;
    return { beige: C0.beige, noir: C0.noir, bleu: C0.bleu };
  };

  /** Un trait pointillé à main levée, qui passe par `points` (en mm). */
  const pointilles = (points) => ({
    type: "courbe",
    ancres: moteur().lisser(points, false),
    ferme: false,
    fond: null,
    trait: { couleur: "noir", epaisseur: 0.6, tirets: [2.2, 1.8] },
  });

  /** Un dessin de la bibliothèque, tenu dans son cadre, sur un disque bleu pâle. */
  function dessinSurDisque(dessin, cx, cy, largeur, { disque = true } = {}) {
    if (!dessin) return [];
    const [pl, ph] = dessin.px || [1, 1];
    const h = (largeur * ph) / pl;
    return [
      ...(disque ? [{ type: "cercle", cx: arrondi2(cx), cy: arrondi2(cy + h * 0.08), r: arrondi2(Math.max(largeur, h) * 0.36), fond: "bleu", trait: null, opacite: 0.45 }] : []),
      { type: "image", x: arrondi2(cx - largeur / 2), y: arrondi2(cy - h / 2), l: arrondi2(largeur), h: arrondi2(h), fichier: dessin.fichier, src: dessin.src, px: dessin.px, focus: [0.5, 0.5], contenir: true },
    ];
  }

  /**
   * **Dessin** (Hugo, 09/10/2026) : fonds beige, titres en Hansley (Gloria
   * Hallelujah tant que sa licence n'est pas vérifiée), le reste en Gloria
   * Hallelujah, tout en noir typo. Des dessins au trait de la bibliothèque
   * (`assets/stickers/`, familles « trait » et « dessin »), choisis d'après
   * les récits, et des pointillés à main levée.
   */
  function maquetteDessin({ fiche, textes, dessins = [] }) {
    const p = planche(fiche);
    const el = fonds(p, { verso: "beige", recto: "beige" });
    const face = p.faces.recto;
    const cx = face.x + face.l / 2;
    const H = p.H;
    const X = p.xRecto;
    const L = p.L;

    // Les pointillés : du haut à gauche, du bas à gauche, et le long du bord droit.
    el.push(pointilles([[X - 2, 30], [X + 22, 24], [X + 52, 16], [X + 78, 6], [X + 96, -4]]));
    el.push(pointilles([[X - 2, H * 0.6], [X + 14, H * 0.7], [X + 20, H * 0.84], [X + 14, H + 4]]));
    el.push(pointilles([[X + L + 4, H * 0.25], [X + L - 18, H * 0.36], [X + L - 10, H * 0.55], [X + L - 26, H * 0.82], [X + L - 18, H + 4]]));

    el.push(...dessinSurDisque(dessins[0], cx, H * 0.21, 52));
    const largeurTitre = face.l - 2 * moteur().CHARNIERE - 6;
    const corpsTitre = corpsQuiTient(textes.titre, largeurTitre, 0.5, { min: 22, max: 34, lignes: 2 });
    const lignes = couperLignes(textes.titre, corpsTitre, largeurTitre, 0.5, 2);
    const hTitre = arrondi2(corpsTitre * MM_PAR_PT * 1.25 * lignes.length);
    el.push({ type: "texte", x: arrondi2(cx - largeurTitre / 2), y: arrondi2(H * 0.4 - hTitre / 2), l: arrondi2(largeurTitre), h: hTitre, texte: lignes.join("\n"), police: POLICE_TITRE_DESSIN, style: "Regular", corps: corpsTitre, couleur: "noir", alignement: "centre", vertical: "centre" });
    if (textes.annees) {
      el.push({ type: "texte", x: arrondi2(cx - 40), y: arrondi2(H * 0.4 + hTitre / 2 + 4), l: 80, h: 7, texte: textes.annees, police: "Gloria Hallelujah", style: "Regular", corps: 12, couleur: "noir", alignement: "centre", vertical: "centre" });
    }
    // Le trait de la route, sous les années.
    el.push({ type: "courbe", ancres: moteur().lisser([[cx - 30, H * 0.63], [cx - 6, H * 0.625], [cx + 18, H * 0.62], [cx + 30, H * 0.61]], false), ferme: false, fond: null, trait: { couleur: "noir", epaisseur: 0.8, tirets: null } });
    el.push(...dessinSurDisque(dessins[1], cx, H * 0.76, 34, { disque: false }));
    if (textes.voyageurs) {
      el.push({ type: "texte", x: arrondi2(cx - 50), y: arrondi2(face.y + face.h - moteur().RETRAIT - 6), l: 100, h: 6, texte: textes.voyageurs, police: "Gloria Hallelujah", style: "Regular", corps: 10, couleur: "noir", alignement: "centre", vertical: "centre" });
    }

    // Quatrième : le titre, un trait sous sa fin, le grand dessin, le texte en pied.
    const q = p.faces.verso;
    const cxV = q.x + q.l / 2;
    const largeurV = q.l - 2 * moteur().CHARNIERE;
    const corpsV = corpsQuiTient(textes.titreVerso, largeurV, 0.5, { min: 20, max: 30 });
    const hV = arrondi2(corpsV * MM_PAR_PT * 1.3);
    const yV = q.y + 14;
    el.push({ type: "texte", x: arrondi2(cxV - largeurV / 2), y: arrondi2(yV), l: arrondi2(largeurV), h: hV, texte: textes.titreVerso, police: POLICE_TITRE_DESSIN, style: "Regular", corps: corpsV, couleur: "noir", alignement: "centre", vertical: "centre" });
    const lTitre = Math.min(largeurV, moteur().largeurTexte(textes.titreVerso, corpsV, 0.5));
    el.push({ type: "courbe", ancres: moteur().lisser([[cxV, yV + hV + 1], [cxV + lTitre * 0.25, yV + hV + 1.8], [cxV + lTitre * 0.45, yV + hV + 0.8]], false), ferme: false, fond: null, trait: { couleur: "noir", epaisseur: 0.9, tirets: null } });
    el.push(...dessinSurDisque(dessins[2] || dessins[0], cxV, H * 0.5, 60));
    const hBloc = 44;
    el.push({
      type: "bloc",
      nom: "Texte de la 4e",
      x: arrondi2(q.x + moteur().CHARNIERE),
      y: arrondi2(q.y + q.h - moteur().RETRAIT - hBloc),
      l: arrondi2(largeurV),
      h: hBloc,
      paragraphes: paragraphes(textes.texteVerso),
      police: "Gloria Hallelujah",
      style: "Regular",
      corps: 9,
      interligne: 1.35,
      espace: 3,
      couleur: "noir",
      alignement: "centre",
      // Centré et non calé en bas : les jambages de Gloria Hallelujah
      // dépassent de la ligne, et l'aperçu croirait le texte trop long.
      vertical: "centre",
    });

    // Dos : le fond de la quatrième, la police et la couleur de son texte.
    el.push(...moteur().elementsDos(fiche, texteDuDos(textes), "noir", { police: "Gloria Hallelujah", style: "Regular" }));
    return p.enveloppe(el, COULEURS_DESSIN());
  }

  /* ---------------------------------------------------------- l'entrée --- */

  /**
   * La maquette d'une couverture dans un style. `contexte` : ce que la
   * maquette par défaut reçoit (`fiche`, `textes`, `recto`, `chiffres`,
   * `carte`, `logo`), plus `verso` (la photo de la quatrième) et `dessins`
   * (les dessins de la bibliothèque retenus pour le voyage).
   */
  function maquette(styleId, contexte) {
    if (styleId === "elegant") return maquetteElegant(contexte);
    if (styleId === "drawing") return maquetteDessin(contexte);
    return moteur().maquette(contexte);
  }

  /** Les familles de dessins qui vont à toute couverture, quand les récits n'en appellent aucun. */
  const DESSINS_DE_SECOURS = ["globe", "boussole", "avion", "carte", "billet-avion", "palmier"];

  /**
   * Les trois dessins du style Dessin : ceux de la bibliothèque que les récits
   * appellent (`MiseEnPage.stickersDe` sur tout le voyage), au trait ou
   * dessinés, jamais un personnage réservé ; complétés par des dessins de
   * voyage génériques. Trois familles différentes.
   */
  function dessinsDuVoyage(bibliotheque, appeles = []) {
    const dessins = (bibliotheque || []).filter((s) => (s.style === "trait" || s.style === "dessin") && !s.reserve);
    const choisis = [];
    const familles = new Set();
    const prendre = (s) => {
      if (!s || familles.has(s.famille) || choisis.length >= 3) return;
      familles.add(s.famille);
      choisis.push(s);
    };
    for (const s of appeles) prendre(dessins.find((d) => d.fichier === s.fichier) || dessins.find((d) => d.famille === s.famille));
    for (const famille of DESSINS_DE_SECOURS) prendre(dessins.find((d) => d.famille === famille && d.style === "trait") || dessins.find((d) => d.famille === famille));
    return choisis;
  }

  const api = {
    STYLES,
    POLICES,
    POLICE_TITRE_DESSIN,
    CHAMPS,
    styleDe,
    cssPolices,
    annees,
    textesParDefaut,
    consigneTextes,
    lireTextes,
    couperLignes,
    corpsQuiTient,
    dessinsDuVoyage,
    maquette,
  };

  if (enNode) module.exports = api;
  else racine.CouvertureStyles = api;
})(typeof window !== "undefined" ? window : globalThis);
