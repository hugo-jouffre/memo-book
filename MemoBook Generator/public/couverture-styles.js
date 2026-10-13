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
 * Les styles Assouline, Aquarelle et Travel book font générer leurs
 * illustrations (`imagesDuStyle`, OpenAI `gpt-image-1`, la couverture de
 * référence du style en entrée) ; Photo-dessin fait tracer le contour des
 * voyageurs sur la photo par un appel « vision » (`CONSIGNE_CONTOUR`).
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
    { id: "watercolor", nom: "Aquarelle", ref: "aquarelle", dispo: true },
    { id: "assouline", nom: "Assouline", ref: "assouline", dispo: true },
    { id: "drawing", nom: "Dessin", ref: "dessin", dispo: true },
    { id: "photo-drawing", nom: "Photo-dessin", ref: "photo-dessin", dispo: true },
    { id: "travel-book", nom: "Travel book", ref: "travel book", dispo: true },
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
    assouline: ["Black Han Sans", "Playfair Display"],
    watercolor: ["Black Han Sans", "Manrope"],
    "travel-book": ["Lilita One"],
    "photo-drawing": ["Caveat Brush"],
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
    assouline: [
      { cle: "titre", label: "Titre (1re)", ia: true, max: 16, consigne: "le titre de la première, en majuscules : la destination, en un ou deux mots (« PHILIPPINES »)" },
      { cle: "annee", label: "Année (1re)", ia: false },
      { cle: "titreVerso", label: "Titre de la 4e (les voyageurs)", ia: false },
      {
        cle: "resume",
        label: "Texte de la 4e",
        ia: true,
        lignes: true,
        max: 820,
        consigne:
          "le texte de la quatrième, à la première personne du pluriel, comme la préface du carnet : une courte accroche (« Notre aventure commence ici »), puis trois paragraphes, chacun séparé par une ligne vide, 820 signes en tout au plus — l'envie de partir, ce que fut le voyage (lieux, paysages), ce que garde le carnet ; mets en gras, entre **doubles astérisques**, trois ou quatre groupes de mots forts",
      },
    ],
    watercolor: [
      { cle: "titre", label: "Titre (1re)", ia: true, max: 16, consigne: "le titre de la première, en majuscules : la destination, en un ou deux mots (« ÉCOSSE »)" },
      { cle: "date", label: "Date (4e)", ia: false },
      {
        cle: "resume",
        label: "Les trois paragraphes de la 4e",
        ia: true,
        lignes: true,
        max: 540,
        consigne:
          "les trois paragraphes de la quatrième, séparés par une ligne vide, 180 signes chacun au plus : trois moments marquants du voyage, dans l'ordre, chacun avec son lieu — une illustration accompagnera chacun",
      },
    ],
    "travel-book": [
      { cle: "titre", label: "Titre (1re)", ia: false },
      { cle: "dates", label: "Dates (1re)", ia: false },
      { cle: "voyageurs", label: "Voyageurs (1re)", ia: false },
    ],
    "photo-drawing": [
      { cle: "titre", label: "Titre (1re)", ia: true, max: 14, consigne: "le titre de la première, en majuscules : le pays ou la région du voyage, en un mot si possible (« ISLANDE »)" },
      { cle: "voyageurs", label: "Voyageurs (1re)", ia: false },
      { cle: "annee", label: "Année (1re)", ia: false },
      { cle: "texteVerso", label: "Texte de la 4e", ia: false },
    ],
  };

  /** Le texte fixe de la quatrième de Photo-dessin (Hugo, 09/10/2026), modifiable. */
  const MERCI_PHOTO_DESSIN = "Merci d'avoir suivi mon aventure !";

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
    if (styleId === "assouline") {
      return {
        titre: destination.toUpperCase(),
        annee: annees(voyage.debut, voyage.fin),
        titreVerso: (base.voyageurs || destination).toUpperCase(),
        resume: `Un voyage ${destination ? `en **${destination}**` : ""} raconté au fil des étapes.\n\nUn carnet fait de paysages, de rencontres et de petits moments que l'on aurait aimé ne jamais oublier.`.replace("  ", " "),
        ...dos(base),
      };
    }
    if (styleId === "watercolor") {
      return {
        titre: destination.toUpperCase(),
        date: base.dates.toUpperCase(),
        resume: (voyage.etapes || [])
          .slice(0, 3)
          .map((e) => [e.titre, e.lieu].filter(Boolean).join(", "))
          .filter(Boolean)
          .join("\n\n"),
        ...dos(base),
      };
    }
    if (styleId === "travel-book") {
      return { titre: destination, dates: base.dates, voyageurs: base.voyageurs, ...dos(base) };
    }
    if (styleId === "photo-drawing") {
      return { titre: destination.toUpperCase(), voyageurs: base.voyageurs, annee: annees(voyage.debut, voyage.fin), texteVerso: MERCI_PHOTO_DESSIN, ...dos(base) };
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

  /* ------------------------------------------------------- les couleurs --- */

  const versRvb = (hex) => {
    const v = String(hex).replace("#", "");
    return [0, 2, 4].map((i) => parseInt(v.slice(i, i + 2), 16) || 0);
  };
  const versHex = (rvb) => `#${rvb.map((c) => Math.max(0, Math.min(255, Math.round(c))).toString(16).padStart(2, "0")).join("")}`;

  /** La luminance relative (WCAG 2) d'une couleur. */
  function luminance(hex) {
    const [r, g, b] = versRvb(hex).map((c) => {
      const s = c / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /** Le contraste (WCAG 2) entre deux couleurs : 1 à 21. */
  function contraste(a, b) {
    const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (l1 + 0.05) / (l2 + 0.05);
  }

  /** Teinte (0–360), saturation et lumière (0–1). */
  function tsl(hex) {
    const [r, g, b] = versRvb(hex).map((c) => c / 255);
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min) return [0, 0, l];
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    const t = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return [t * 60, s, l];
  }

  function depuisTsl(t, s, l) {
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((t / 60) % 2) - 1));
    const m = l - c / 2;
    const [r, g, b] = t < 60 ? [c, x, 0] : t < 120 ? [x, c, 0] : t < 180 ? [0, c, x] : t < 240 ? [0, x, c] : t < 300 ? [x, 0, c] : [c, 0, x];
    return versHex([(r + m) * 255, (g + m) * 255, (b + m) * 255]);
  }

  /** La même teinte, plus sombre, jusqu'à tenir `minimum` de contraste sur `fond`. */
  function assombrirJusqua(hex, fond, minimum = 3) {
    let [t, s, l] = tsl(hex);
    let c = hex;
    while (contraste(c, fond) < minimum && l > 0.08) {
      l -= 0.04;
      c = depuisTsl(t, s, l);
    }
    return c;
  }

  /**
   * **Assouline** : le fond « qui s'accorde le mieux » avec l'illustration,
   * entre le vert, le bleu et le beige de la marque. Une illustration verte
   * se pose sur le bleu (l'exemple des Philippines), une bleue sur le beige ;
   * une chaude sur le beige, ou sur le vert si elle y manque de contraste.
   * Les titres prennent la couleur dominante de l'illustration, assombrie au
   * besoin pour se lire (contraste 3 au moins).
   */
  function couleursAssouline(dominante) {
    const P = moteur().COULEURS;
    const [t, s] = tsl(dominante || P.vertMarque.hex);
    let fond = "beige";
    if (s > 0.12 && t >= 70 && t < 175) fond = "bleu";
    else if (s > 0.12 && t >= 175 && t < 265) fond = "beige";
    else if (contraste(dominante, P.beige.hex) < 2.5) fond = "vertMarque";
    const titre = assombrirJusqua(dominante || P.vertMarque.hex, P[fond].hex, 3);
    return { fond, titre };
  }

  /**
   * **Photo-dessin** : la couleur des textes et du contour vient de la
   * palette de la photo — sa teinte dominante, très claire, ou très sombre si
   * la photo est claire —, avec un contraste suffisant sur la photo. La
   * quatrième prend cette couleur en fond ; ses textes, la teinte de la marque
   * la plus lisible dessus.
   */
  function couleursPhotoDessin(dominante, luminanceMoyenne = 0.3) {
    const P = moteur().COULEURS;
    const [t, s] = tsl(dominante || "#4aa3a0");
    const fondPhoto = versHex([luminanceMoyenne * 255, luminanceMoyenne * 255, luminanceMoyenne * 255]);
    let texte = depuisTsl(t, Math.min(0.75, Math.max(0.35, s)), 0.86);
    if (contraste(texte, fondPhoto) < 2.2) texte = depuisTsl(t, Math.min(0.7, Math.max(0.35, s)), 0.2);
    const candidats = ["vertMarque", "bleu", "beige", "blancMarque"];
    const ecriture = candidats.reduce((a, b) => (contraste(P[b].hex, texte) > contraste(P[a].hex, texte) ? b : a));
    return { texte, ecriture };
  }

  /* ---------------------------------------------- les images générées --- */

  /**
   * Les images que chaque style fait générer (`genererImage`, OpenAI
   * `gpt-image-1`), avec la couverture de référence du style en entrée pour en
   * tenir le style. `pour` : la face où l'image se pose. Le coût est estimé
   * au tarif « high » de `gpt-image-1` (≈ 0,17 $ en carré, 0,25 $ en
   * portrait ou paysage).
   */
  function imagesDuStyle(styleId, voyage, textes = {}) {
    const lieu = voyage.destination || "le pays du voyage";
    const motifs = (voyage.etapes || [])
      .map((e) => [e.titre, e.lieu].filter(Boolean).join(" à "))
      .filter(Boolean)
      .slice(0, 10)
      .join(" ; ");
    const S0 = styleDe(styleId);
    if (styleId === "assouline") {
      return [
        {
          cle: "illustration",
          pour: "recto",
          taille: "1024x1024",
          transparent: true,
          reference: S0.recto,
          prompt:
            `Une seule illustration centrale, emblématique de ${lieu} et du voyage raconté (${motifs || lieu}) : une plante, un animal ou un objet ` +
            "typique du lieu. Exactement le style de l'illustration centrale de l'image de référence (la feuille de palmier) : aplats peints, " +
            "léger grain, formes nettes, deux ou trois tons d'une même couleur. Centrée, entière, sans texte, sans cadre, fond transparent.",
        },
      ];
    }
    if (styleId === "watercolor") {
      const paras = paragraphes(textes.resume).slice(0, 3);
      return [
        {
          cle: "recto",
          pour: "recto",
          taille: "1024x1536",
          transparent: false,
          reference: S0.recto,
          prompt:
            `Une illustration à l'aquarelle, en hauteur, d'un paysage marquant de ${lieu} tiré du voyage (${motifs || lieu}), avec quelques ` +
            "petits personnages. Exactement le style de l'image de référence : aquarelle lumineuse, traits d'encre légers, papier visible. Sans texte.",
        },
        ...[0, 1, 2].map((i) => ({
          cle: `vignette${i + 1}`,
          pour: "verso",
          taille: "1024x1024",
          transparent: true,
          reference: S0.verso,
          prompt:
            `Une petite vignette à l'aquarelle illustrant : ${paras[i] || motifs || lieu}. Comme peinte directement sur un papier beige : ` +
            "pas de contour net, les bords bavent et se fondent dans le papier, comme les vignettes de l'image de référence. Sans texte, fond transparent.",
        })),
      ];
    }
    if (styleId === "travel-book") {
      return [
        {
          cle: "timbres",
          pour: "recto",
          taille: "1536x1024",
          transparent: true,
          reference: S0.recto,
          prompt:
            `Un collage de cinq ou six timbres-poste et autocollants vintage, qui se chevauchent légèrement, illustrant le voyage en ${lieu} : ` +
            `${motifs || lieu}. Exactement le style des timbres de l'image de référence : bords dentelés, couleurs douces, illustrations rétro, ` +
            "un ou deux autocollants à bord blanc. Fond transparent, aucun cadre autour du collage.",
        },
        {
          cle: "tampon",
          pour: "recto",
          taille: "1024x1024",
          transparent: true,
          reference: "silhouette",
          prompt:
            `Un tampon postal rond à l'encre bordeaux, comme celui de l'image de référence de couverture : le nom « ${String(lieu).toUpperCase()} » ` +
            "écrit deux fois en arc dans l'anneau, des étoiles, et au centre la silhouette du pays fournie en image. Encre un peu irrégulière. Fond transparent.",
        },
      ];
    }
    return [];
  }

  /** Le coût estimé des images d'un style, en dollars. */
  const coutImages = (images) => images.reduce((s, i) => s + (i.taille === "1024x1024" ? 0.17 : 0.25), 0);

  /**
   * La consigne de l'appel « vision » du style Photo-dessin : le contour
   * approximatif des personnes sur la photo, pour les entourer d'un trait.
   */
  const CONSIGNE_CONTOUR =
    "Sur cette photo de voyage, repère les personnes (les voyageurs). Donne le contour approximatif du groupe qu'elles forment, " +
    "avec une petite marge autour : 16 à 24 points, dans le sens des aiguilles d'une montre, en coordonnées normalisées (0 à 1, " +
    "x de gauche à droite, y de haut en bas). Sans personne visible, renvoie une liste vide. Réponds uniquement par un objet JSON, " +
    'sans texte autour : {"contour":[[0.4,0.3],[0.6,0.3]]}';

  /** Le contour lu, ou une ellipse au centre de la photo si l'appel n'a rien donné. */
  function lireContour(reponse) {
    const points = (Array.isArray(reponse?.contour) ? reponse.contour : [])
      .filter((p) => Array.isArray(p) && p.length === 2 && p.every((v) => Number.isFinite(v)))
      .map(([x, y]) => [Math.max(0, Math.min(1, x)), Math.max(0, Math.min(1, y))]);
    if (points.length >= 6) return points;
    return Array.from({ length: 18 }, (_, i) => {
      const a = (i / 18) * 2 * Math.PI;
      return [0.5 + 0.2 * Math.cos(a), 0.58 + 0.16 * Math.sin(a)];
    });
  }

  /**
   * Les anneaux à main levée autour des personnes (Photo-dessin), comme sur la
   * référence : le contour, puis d'autres à pas réguliers (`pas` mm), un peu
   * irréguliers, en mm dans le cadre `zone` de la photo. L'ensemble tient dans
   * `cadre` (la face visible, moins la place du titre au-dessus) : un contour
   * trop large est resserré autour de son centre, puis l'ensemble est ramené
   * dans le cadre. Renvoie les anneaux, du plus serré au plus large.
   */
  function anneauxAutour(contour, zone, { n = 4, pas = 8, cadre = null, reserveHaut = 0 } = {}) {
    const pts = contour.map(([x, y]) => [zone.x + x * zone.l, zone.y + y * zone.h]);
    const cx = pts.reduce((s, p) => s + p[0], 0) / pts.length;
    const cy = pts.reduce((s, p) => s + p[1], 0) / pts.length;
    const construire = (f, d) =>
      Array.from({ length: n }, (_, k) =>
        pts.map(([x, y], i) => {
          const dx = (x - cx) * f;
          const dy = (y - cy) * f;
          const r = Math.hypot(dx, dy) || 1;
          const ecart = k * d * (1 + 0.12 * Math.sin(i * 2.3 + k * 1.7));
          return [cx + dx + (dx / r) * ecart, cy + dy + (dy / r) * ecart];
        }),
      );
    const boite = (anneau) => {
      const xs = anneau.map((p) => p[0]);
      const ys = anneau.map((p) => p[1]);
      return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
    };
    let anneaux = construire(1, pas);
    if (cadre) {
      const H = cadre.h - reserveHaut;
      for (let f = 1, d = pas; f > 0.2; f -= 0.05, d = Math.max(pas * 0.6, d - 0.25)) {
        anneaux = construire(f, d);
        const b = boite(anneaux[n - 1]);
        if (b.x1 - b.x0 <= cadre.l && b.y1 - b.y0 <= H) break;
      }
      // Ramené dans le cadre, titre compris.
      const b = boite(anneaux[n - 1]);
      const dx = Math.max(0, cadre.x - b.x0) - Math.max(0, b.x1 - (cadre.x + cadre.l));
      const dy = Math.max(0, cadre.y + reserveHaut - b.y0) - Math.max(0, b.y1 - (cadre.y + cadre.h));
      anneaux = anneaux.map((a) => a.map(([x, y]) => [x + dx, y + dy]));
    }
    return anneaux.map((a) => a.map(([x, y]) => [arrondi2(x), arrondi2(y)]));
  }

  /** L'arc du haut d'un anneau, de gauche à droite : le tracé qui porte le titre. */
  function arcDuHaut(anneau) {
    const cy = anneau.reduce((s, p) => s + p[1], 0) / anneau.length;
    return anneau.filter((p) => p[1] <= cy).sort((a, b) => a[0] - b[0]);
  }

  /* ---------------------------------------------------- style Assouline --- */

  /**
   * **Assouline** (Hugo, 09/10/2026) : fond choisi entre le vert, le bleu et
   * le beige selon l'illustration ; titres de la première et de la quatrième
   * en Black Han Sans, couleur dominante de l'illustration ; résumé et
   * chiffres en Playfair Display, noir typo ; encadré des chiffres blanc,
   * bordé de la couleur des titres. Tout est rédigé par l'IA.
   */
  function maquetteAssouline({ fiche, textes, images = {}, chiffres = [] }) {
    const p = planche(fiche);
    const P = moteur().COULEURS;
    const { fond, titre: couleurTitre } = couleursAssouline(images.illustration?.dominante);
    const couleurs = { [fond]: P[fond], noir: P.noir, blanc: P.blanc, accent: { nom: "MemoBook accent", hex: couleurTitre } };
    const el = fonds(p, { verso: fond, recto: fond });
    const face = p.faces.recto;
    const marge = moteur().CHARNIERE;
    const largeur = face.l - 2 * marge;
    const titre = String(textes.titre || "").toUpperCase();
    const corps = corpsQuiTient(titre, largeur, 0.72, { min: 24, max: 58 });
    const hT = arrondi2(corps * MM_PAR_PT * 1.1);
    el.push({ type: "texte", x: face.x + marge, y: arrondi2(face.y + 10), l: largeur, h: hT, texte: titre, police: "Black Han Sans", style: "Regular", corps, couleur: "accent", alignement: "centre", vertical: "centre" });
    if (images.illustration) {
      const cote = Math.min(largeur, face.h * 0.62);
      el.push({ type: "image", x: arrondi2(face.x + face.l / 2 - cote / 2), y: arrondi2(face.y + 10 + hT + 8), l: arrondi2(cote), h: arrondi2(cote), fichier: images.illustration.fichier, src: images.illustration.src, px: images.illustration.px, focus: [0.5, 0.5], contenir: true });
    }
    el.push({ type: "texte", x: face.x + marge, y: arrondi2(face.y + face.h - moteur().RETRAIT - 9), l: largeur, h: 9, texte: String(textes.annee || ""), police: "Black Han Sans", style: "Regular", corps: 20, couleur: "accent", alignement: "centre", vertical: "centre" });

    // Quatrième : les voyageurs en titre, le résumé, l'encadré des chiffres.
    const q = p.faces.verso;
    const xV = q.x + marge;
    const lV = q.l - 2 * marge;
    const titreV = String(textes.titreVerso || "").toUpperCase();
    const corpsV = corpsQuiTient(titreV, lV, 0.68, { min: 16, max: 26, lignes: 2 });
    const lignesV = couperLignes(titreV, corpsV, lV, 0.68, 2);
    const hV = arrondi2(corpsV * MM_PAR_PT * 1.2 * lignesV.length);
    el.push({ type: "texte", x: xV, y: arrondi2(q.y + 8), l: lV, h: hV, texte: lignesV.join("\n"), police: "Black Han Sans", style: "Regular", corps: corpsV, couleur: "accent", alignement: "centre", vertical: "centre" });
    const hBoite = chiffres.length ? 42 : 0;
    const yBoite = q.y + q.h - moteur().RETRAIT - hBoite;
    const yResume = q.y + 8 + hV + 8;
    el.push({ type: "bloc", nom: "Résumé de la 4e", x: xV, y: arrondi2(yResume), l: lV, h: arrondi2(yBoite - 8 - yResume), paragraphes: paragraphes(textes.resume), police: "Playfair Display", style: "Regular", styleGras: "Bold", corps: 10, interligne: 1.4, espace: 3.5, couleur: "noir", alignement: "centre", vertical: "haut" });
    if (chiffres.length) {
      el.push({ type: "rect", x: xV, y: arrondi2(yBoite), l: lV, h: hBoite, fond: "blanc", rayon: 5, trait: { couleur: "accent", epaisseur: 0.9, tirets: null } });
      el.push({ type: "texte", x: xV, y: arrondi2(yBoite + 5), l: lV, h: 6, texte: "Notre voyage en quelques chiffres", police: "Playfair Display", style: "Bold", corps: 10, couleur: "noir", alignement: "centre", vertical: "centre" });
      const col = lV / chiffres.length;
      chiffres.forEach((c, i) => {
        el.push({ type: "texte", x: arrondi2(xV + i * col), y: arrondi2(yBoite + 13), l: arrondi2(col), h: 12, texte: c.valeur, police: "Playfair Display", style: "Black", corps: 26, couleur: "noir", alignement: "centre", vertical: "bas" });
        el.push({ type: "texte", x: arrondi2(xV + i * col), y: arrondi2(yBoite + 26), l: arrondi2(col), h: 12, texte: c.libelle, police: "Playfair Display", style: "Regular", corps: 9, couleur: "noir", alignement: "centre", vertical: "haut" });
      });
    }
    // Dos : le fond de la quatrième, la police et la couleur de son corps de texte.
    el.push(...moteur().elementsDos(fiche, texteDuDos(textes), "noir", { police: "Playfair Display", style: "Bold" }));
    return p.enveloppe(el, couleurs);
  }

  /* ---------------------------------------------------- style Aquarelle --- */

  /**
   * **Aquarelle** (Hugo, 09/10/2026) : fonds beige ; titres en Black Han
   * Sans, le reste en Manrope, en noir typo ; sur la quatrième, le motif M de
   * MemoBook en beige foncé à 20 % et le logo en beige foncé. Les illustrations
   * sont générées d'après les récits, celles de la quatrième sans contour net.
   */
  function maquetteAquarelle({ fiche, textes, images = {}, logo }) {
    const p = planche(fiche);
    const el = fonds(p, { verso: "beige", recto: "beige" });
    const face = p.faces.recto;
    const marge = moteur().CHARNIERE;
    const titre = String(textes.titre || "").toUpperCase();
    const corps = corpsQuiTient(titre, face.l - 2 * marge, 0.72, { min: 24, max: 56 });
    const hBande = arrondi2(corps * MM_PAR_PT * 1.1 + 14);
    // L'illustration, bord à bord sous la bande du titre, fond perdu compris.
    if (images.recto) {
      el.push({ type: "image", x: p.xRecto, y: arrondi2(face.y + hBande), l: arrondi2(p.L + p.f), h: arrondi2(p.H + p.f - face.y - hBande), fichier: images.recto.fichier, src: images.recto.src, px: images.recto.px, focus: [0.5, 0.5] });
    }
    el.push({ type: "texte", x: face.x + marge, y: arrondi2(face.y + 4), l: face.l - 2 * marge, h: arrondi2(hBande - 6), texte: titre, police: "Black Han Sans", style: "Regular", corps, couleur: "noir", alignement: "centre", vertical: "centre" });

    // Quatrième : le motif M, la date, trois vignettes et leurs paragraphes, le logo.
    const q = p.faces.verso;
    if (logo) {
      const cote = q.l * 1.05;
      el.push({ type: "image", x: arrondi2(q.x - cote * 0.12), y: arrondi2(q.y + q.h * 0.18), l: arrondi2(cote), h: arrondi2(cote), fichier: logo.fichier, src: logo.src, px: logo.px, focus: [0.5, 0.5], contenir: true, opacite: 0.2 });
    }
    const xV = q.x + marge;
    const lV = q.l - 2 * marge;
    el.push({ type: "texte", x: xV, y: arrondi2(q.y + 8), l: lV, h: 10, texte: String(textes.date || ""), police: "Black Han Sans", style: "Regular", corps: 18, couleur: "noir", alignement: "centre", vertical: "centre" });
    const paras = paragraphes(textes.resume).slice(0, 3);
    const hLogo = 14;
    const logoH = logo?.px ? (hLogo * logo.px[1]) / logo.px[0] : hLogo;
    const yLogo = q.y + q.h - moteur().RETRAIT - logoH;
    const haut = q.y + 24;
    const pas = (yLogo - 8 - haut) / 3;
    const lImg = lV * 0.34;
    paras.forEach((texte, i) => {
      const gauche = i % 2 === 0;
      const y = haut + i * pas;
      const vignette = images[`vignette${i + 1}`];
      if (vignette) {
        el.push({ type: "image", x: arrondi2(gauche ? xV : xV + lV - lImg), y: arrondi2(y + 2), l: arrondi2(lImg), h: arrondi2(pas - 6), fichier: vignette.fichier, src: vignette.src, px: vignette.px, focus: [0.5, 0.5], contenir: true });
      }
      el.push({ type: "bloc", nom: `Paragraphe ${i + 1} de la 4e`, x: arrondi2(gauche ? xV + lImg + 5 : xV), y: arrondi2(y), l: arrondi2(lV - lImg - 5), h: arrondi2(pas - 2), paragraphes: [texte], police: "Manrope", style: "Regular", corps: 9, interligne: 1.4, couleur: "noir", alignement: "gauche", vertical: "centre" });
    });
    if (logo) {
      el.push({ type: "image", x: arrondi2(q.x + q.l / 2 - hLogo / 2), y: arrondi2(yLogo), l: hLogo, h: arrondi2(logoH), fichier: logo.fichier, src: logo.src, px: logo.px, focus: [0.5, 0.5], contenir: true });
    }
    el.push(...moteur().elementsDos(fiche, texteDuDos(textes), "noir", { police: "Manrope", style: "SemiBold" }));
    const P = moteur().COULEURS;
    return p.enveloppe(el, { beige: P.beige, noir: P.noir, beigeFonce: P.beigeFonce });
  }

  /* -------------------------------------------------- style Travel book --- */

  /** Un cadre au bord déchiré, autour de la zone : un trait épais et irrégulier. */
  function cadreDechire(zone, couleur) {
    const pts = [];
    const pas = 2.2;
    const bord = (x0, y0, x1, y1) => {
      const n = Math.max(2, Math.round(Math.hypot(x1 - x0, y1 - y0) / pas));
      for (let i = 0; i < n; i += 1) {
        const t = i / n;
        const j = Math.sin(i * 7.1 + x0 * 0.3 + y0 * 0.7) * 0.7;
        pts.push([arrondi2(x0 + (x1 - x0) * t + (y1 !== y0 ? j : 0)), arrondi2(y0 + (y1 - y0) * t + (x1 !== x0 ? j : 0))]);
      }
    };
    const { x, y, l, h } = zone;
    bord(x, y, x + l, y);
    bord(x + l, y, x + l, y + h);
    bord(x + l, y + h, x, y + h);
    bord(x, y + h, x, y);
    return { type: "chemin", points: pts, ferme: true, fond: null, trait: { couleur, epaisseur: 5, tirets: null } };
  }

  /**
   * **Travel book** (Hugo, 09/10/2026) : Lilita One, texte vert sur fond
   * beige ; sur la première, un tampon du pays et des timbres et autocollants
   * générés d'après les récits ; sur la quatrième, une photo dans un cadre
   * vert déchiré, choisie comme pour le style par défaut, et le logo.
   */
  function maquetteTravelBook({ fiche, textes, images = {}, verso, logo }) {
    const p = planche(fiche);
    const el = fonds(p, { verso: "beige", recto: "beige" });
    const face = p.faces.recto;
    const marge = moteur().CHARNIERE;
    const lignes = [String(textes.titre || "").toUpperCase(), String(textes.dates || "").toUpperCase()].filter(Boolean);
    const lT = face.l * 0.62;
    const corps = Math.min(...lignes.map((l) => corpsQuiTient(l, lT, 0.6, { min: 14, max: 24 })));
    el.push({ type: "texte", x: face.x + marge, y: arrondi2(face.y + 14), l: arrondi2(lT), h: arrondi2(corps * MM_PAR_PT * 1.2 * lignes.length), texte: lignes.join("\n"), police: "Lilita One", style: "Regular", corps, couleur: "vertMarque", alignement: "gauche", vertical: "haut" });
    if (images.tampon) {
      const cote = face.l * 0.26;
      el.push({ type: "image", x: arrondi2(face.x + face.l - marge - cote), y: arrondi2(face.y + 6), l: arrondi2(cote), h: arrondi2(cote), fichier: images.tampon.fichier, src: images.tampon.src, px: images.tampon.px, focus: [0.5, 0.5], contenir: true });
    }
    if (images.timbres) {
      const l = face.l - 2 * marge;
      el.push({ type: "image", x: face.x + marge, y: arrondi2(face.y + face.h * 0.26), l: arrondi2(l), h: arrondi2(face.h * 0.52), fichier: images.timbres.fichier, src: images.timbres.src, px: images.timbres.px, focus: [0.5, 0.5], contenir: true });
    }
    if (textes.voyageurs) {
      el.push({ type: "texte", x: face.x + marge, y: arrondi2(face.y + face.h - moteur().RETRAIT - 8), l: face.l - 2 * marge, h: 8, texte: String(textes.voyageurs).toUpperCase(), police: "Lilita One", style: "Regular", corps: 15, couleur: "vertMarque", alignement: "centre", vertical: "centre" });
    }

    const q = p.faces.verso;
    const zone = { x: q.x + marge, y: q.y + 10, l: q.l - 2 * marge, h: (q.h - 2 * marge) * 0.78 };
    if (verso) el.push({ type: "image", ...zone, fichier: verso.fichier, src: verso.src, px: verso.px, focus: verso.focus || [0.5, 0.4] });
    el.push(cadreDechire(zone, "vertMarque"));
    if (logo) {
      const hLogo = 16;
      const logoH = logo.px ? (hLogo * logo.px[1]) / logo.px[0] : hLogo;
      el.push({ type: "image", x: arrondi2(q.x + q.l / 2 - hLogo / 2), y: arrondi2(q.y + q.h - moteur().RETRAIT - logoH), l: hLogo, h: arrondi2(logoH), fichier: logo.fichier, src: logo.src, px: logo.px, focus: [0.5, 0.5], contenir: true });
    }
    // La quatrième n'a pas de corps de texte : le dos prend la police et la couleur du titre.
    el.push(...moteur().elementsDos(fiche, texteDuDos(textes), "vertMarque", { police: "Lilita One", style: "Regular" }));
    const P = moteur().COULEURS;
    return p.enveloppe(el, { beige: P.beige, vertMarque: P.vertMarque, blanc: P.blanc });
  }

  /* ------------------------------------------------- style Photo-dessin --- */

  /**
   * **Photo-dessin** (Hugo, 09/10/2026) : sur la première, une photo où l'on
   * voit les voyageurs, entourés d'un contour grossier, et le nom du pays qui
   * suit la plus large ligne du contour ; Caveat Brush partout ; la couleur des
   * textes et du contour vient de la photo. La quatrième prend cette couleur
   * en fond, ses textes (fixes) la teinte de la marque la plus lisible.
   */
  function maquettePhotoDessin({ fiche, textes, recto, contour, couleurPhoto = null, luminancePhoto = 0.35, logo }) {
    const p = planche(fiche);
    const P = moteur().COULEURS;
    const { texte: couleurTexte, ecriture } = couleursPhotoDessin(couleurPhoto, luminancePhoto);
    const couleurs = { encre: { nom: "MemoBook encre photo", hex: couleurTexte }, [ecriture]: P[ecriture] };
    const el = fonds(p, { verso: "encre", recto: "encre" });
    const face = p.faces.recto;
    const plat = { x: p.xRecto, y: -p.f, l: p.L + p.f, h: p.H + 2 * p.f };
    if (recto) el.push({ type: "image", ...plat, fichier: recto.fichier, src: recto.src, px: recto.px, focus: recto.focus || [0.5, 0.5] });
    // Le contour : sur la photo telle qu'elle est cadrée — l'image remplit le plat.
    const place = recto ? moteur().placementImage({ ...plat, px: recto.px, focus: recto.focus || [0.5, 0.5] }) : plat;
    const titre = String(textes.titre || "").toUpperCase();
    // Le corps du titre : il couvre à peu près la largeur de la face, sans dépasser 54 pt.
    const corps = arrondi2(Math.max(24, Math.min(54, (face.l * 0.85) / Math.max(4, titre.length) / (0.5 * MM_PAR_PT))));
    const hTitre = corps * MM_PAR_PT;
    const cadre = { x: face.x + 4, y: face.y + 14, l: face.l - 8, h: face.h - 14 - 16 };
    const anneaux = anneauxAutour(lireContour({ contour }), place, { cadre, reserveHaut: hTitre + 4 });
    for (const a of anneaux) el.push({ type: "courbe", ancres: moteur().lisser(a, true, 0.9), ferme: true, fond: null, trait: { couleur: "encre", epaisseur: 1.6, tirets: null } });
    // Le titre suit l'arc du haut de l'anneau le plus large, juste au-dessus.
    const arc = arcDuHaut(anneaux[anneaux.length - 1]).map(([x, y]) => [x, arrondi2(y - 3)]);
    if (arc.length >= 3 && titre) {
      // Le titre tient sur l'arc : sinon le texte sur tracé serait coupé.
      const longueur = arc.slice(1).reduce((t, q2, i) => t + Math.hypot(q2[0] - arc[i][0], q2[1] - arc[i][1]), 0);
      const largeurA = (c) => moteur().largeurTexte(titre, c, 0.55) + titre.length * 0.04 * c * MM_PAR_PT;
      let corpsArc = corps;
      while (corpsArc > 14 && largeurA(corpsArc) > longueur * 0.92) corpsArc -= 1;
      el.push({ type: "texteChemin", ancres: moteur().lisser(arc, false), texte: titre, police: "Caveat Brush", style: "Regular", corps: arrondi2(corpsArc), couleur: "encre", approche: 40, x: face.x, y: face.y, l: face.l, h: 20 });
    }
    if (textes.voyageurs) {
      el.push({ type: "texte", x: face.x + 10, y: arrondi2(face.y + 4), l: face.l - 20, h: 9, texte: String(textes.voyageurs).toUpperCase(), police: "Caveat Brush", style: "Regular", corps: 15, couleur: "encre", alignement: "centre", vertical: "centre" });
    }
    if (textes.annee) {
      el.push({ type: "texte", x: arrondi2(face.x + face.l - 50), y: arrondi2(face.y + face.h - 12), l: 40, h: 11, texte: String(textes.annee), police: "Caveat Brush", style: "Regular", corps: 26, couleur: "encre", alignement: "droite", vertical: "centre" });
    }

    // Quatrième : des vagues dans le coin haut gauche, le merci, le logo.
    const q = p.faces.verso;
    for (let k = 0; k < 4; k += 1) {
      const d = k * 7;
      el.push({ type: "courbe", ancres: moteur().lisser([[-p.f, 14 + d], [20, 26 + d * 1.1], [44, 20 + d], [64, 8 + d * 0.8], [80 + d * 0.6, -p.f]], false), ferme: false, fond: null, trait: { couleur: ecriture, epaisseur: 1.6, tirets: null } });
    }
    const merci = String(textes.texteVerso || "").toUpperCase();
    const lMerci = Math.min(q.l - 2 * moteur().CHARNIERE - 16, 78);
    const lignesMerci = couperLignes(merci, 19, lMerci, 0.5, 3);
    el.push({ type: "texte", x: arrondi2(q.x + q.l / 2 - lMerci / 2), y: arrondi2(q.y + q.h * 0.4), l: arrondi2(lMerci), h: arrondi2(19 * MM_PAR_PT * 1.6 * lignesMerci.length), texte: lignesMerci.join("\n"), police: "Caveat Brush", style: "Regular", corps: 19, couleur: ecriture, alignement: "centre", vertical: "centre" });
    if (logo) {
      const hLogo = 16;
      const logoH = logo.px ? (hLogo * logo.px[1]) / logo.px[0] : hLogo;
      el.push({ type: "image", x: arrondi2(q.x + q.l / 2 - hLogo / 2), y: arrondi2(q.y + q.h - moteur().RETRAIT - logoH), l: hLogo, h: arrondi2(logoH), fichier: logo.fichier, src: logo.src, px: logo.px, focus: [0.5, 0.5], contenir: true });
    }
    el.push(...moteur().elementsDos(fiche, texteDuDos(textes), ecriture, { police: "Caveat Brush", style: "Regular" }));
    return p.enveloppe(el, couleurs);
  }

  /* ---------------------------------------------------------- l'entrée --- */

  /**
   * La maquette d'une couverture dans un style. `contexte` : ce que la
   * maquette par défaut reçoit (`fiche`, `textes`, `recto`, `chiffres`,
   * `carte`, `logo`), plus `verso` (la photo de la quatrième), `dessins`
   * (les dessins de la bibliothèque retenus pour le voyage), `images` (les
   * illustrations générées, `{ cle: { fichier, src, px, dominante } }`) et,
   * pour Photo-dessin, `contour`, `couleurPhoto` et `luminancePhoto`.
   */
  function maquette(styleId, contexte) {
    if (styleId === "elegant") return maquetteElegant(contexte);
    if (styleId === "drawing") return maquetteDessin(contexte);
    if (styleId === "assouline") return maquetteAssouline(contexte);
    if (styleId === "watercolor") return maquetteAquarelle(contexte);
    if (styleId === "travel-book") return maquetteTravelBook(contexte);
    if (styleId === "photo-drawing") return maquettePhotoDessin(contexte);
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
    MERCI_PHOTO_DESSIN,
    contraste,
    couleursAssouline,
    couleursPhotoDessin,
    imagesDuStyle,
    coutImages,
    CONSIGNE_CONTOUR,
    lireContour,
  };

  if (enNode) module.exports = api;
  else racine.CouvertureStyles = api;
})(typeof window !== "undefined" ? window : globalThis);
