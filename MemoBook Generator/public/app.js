/* Atelier carnet — version locale.
   Reprise de l'artefact `atelier-carnet.jsx`, débarrassée de ses contraintes :
   la transcription Whisper tourne vraiment, le découpage aussi, et les
   téléchargements aboutissent.

   Il n'y a plus de boîte « à classer » : dès qu'un vocal est transcrit, il est
   rangé dans une étape, et tout ce qui peut être déduit du voyage l'est. */

/* ------------------------------------------------------------------ outils --- */

const uid = () => Math.random().toString(36).slice(2, 10);

function h(tag, props, ...enfants) {
  const el = document.createElement(tag);
  for (const [cle, valeur] of Object.entries(props || {})) {
    if (valeur == null || valeur === false) continue;
    if (cle === "class") el.className = valeur;
    else if (cle === "style") Object.assign(el.style, valeur);
    else if (cle.startsWith("on")) el.addEventListener(cle.slice(2).toLowerCase(), valeur);
    else if (cle in el) el[cle] = valeur;
    else el.setAttribute(cle, valeur === true ? "" : valeur);
  }
  for (const enfant of enfants.flat(Infinity)) {
    if (enfant == null || enfant === false || enfant === "") continue;
    el.append(enfant.nodeType ? enfant : document.createTextNode(String(enfant)));
  }
  return el;
}

const $ = (id) => document.getElementById(id);

function remplir(hote, ...enfants) {
  const el = typeof hote === "string" ? $(hote) : hote;
  if (el) el.replaceChildren(...enfants.flat(Infinity).filter(Boolean));
  return el;
}

const nombre = (n) => Number(n || 0).toLocaleString("fr-FR");

/* ------------------------------------------------- lecture des messages --- */

const MSG_RE =
  /^\[?\s*(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})[,]?\s+(?:à\s+)?(\d{1,2})[:h](\d{2})(?::\d{2})?\s*(?:AM|PM|am|pm)?\s*\]?\s*(?:-\s*)?([^:\n]{1,40}?)\s*:\s*([\s\S]*)$/;

const ATTACH_RE = /((?:IMG|VID|PTT|AUD|STK)[-_]?\d{6,8}[-_]?WA\d{3,5}\.\w{3,4})/i;

/* WhatsApp nomme les vocaux « Voice message.ogg.oga », « PTT-…-WA….opus »,
   ou « Message audio.opus » selon la plateforme et la langue. */
const AUDIO_EXT_RE = /\.(ogg|oga|opus|m4a|mp3|wav|aac|amr)$/i;
const estAudio = (nom = "") =>
  AUDIO_EXT_RE.test(nom) ||
  /^(PTT|AUD)[-_]/i.test(nom) ||
  /^(voice message|message audio|audio)/i.test(nom);

const OMITTED_RE =
  /(image omise|images omises|médias omis|medias omis|fichier joint|pièce jointe|piece jointe|<attached:|image absente)/i;

function toISO(d, m, y) {
  let annee = parseInt(y, 10);
  if (annee < 100) annee += 2000;
  return `${annee}-${String(parseInt(m, 10)).padStart(2, "0")}-${String(parseInt(d, 10)).padStart(2, "0")}`;
}

function parseWhatsapp(brut) {
  const lignes = brut.replace(/ |‎/g, " ").split(/\r?\n/);
  const messages = [];
  for (const ligne of lignes) {
    const m = ligne.match(MSG_RE);
    if (m) {
      messages.push({
        date: toISO(m[1], m[2], m[3]),
        heure: `${m[4].padStart(2, "0")}:${m[5]}`,
        auteur: m[6].trim(),
        texte: m[7].trim(),
      });
    } else if (messages.length && ligne.trim()) {
      messages[messages.length - 1].texte += "\n" + ligne.trim();
    }
  }

  if (!messages.length) {
    // pas de format WhatsApp détecté : on découpe sur les lignes vides
    return {
      souvenirs: brut
        .split(/\n\s*\n/)
        .map((t) => t.trim())
        .filter(Boolean)
        .map((t) => ({ id: uid(), texte: t, date: "", heure: "", auteur: "" })),
      photos: [],
    };
  }

  const souvenirs = [];
  const photos = [];
  for (const msg of messages) {
    const att = msg.texte.match(ATTACH_RE);
    if (att && estAudio(att[1])) {
      souvenirs.push({
        id: uid(),
        texte: "",
        date: msg.date,
        heure: msg.heure,
        auteur: msg.auteur,
        audioNom: normaliserNomAudio(att[1]),
      });
      continue;
    }
    if (att) {
      // « IMG-20260827-WA0003.jpg » date mieux la photo que l'heure d'envoi.
      const duNom = dateDepuisNom(att[1]);
      photos.push(
        photoVide({
          nomFichier: att[1],
          date: duNom.date || msg.date,
          heure: duNom.heure,
          dateSource: duNom.date ? "nom de fichier" : "message",
        }),
      );
      const reste = msg.texte.replace(ATTACH_RE, "").replace(/[<>()]/g, "").trim();
      if (reste && !OMITTED_RE.test(reste)) {
        souvenirs.push({
          id: uid(),
          texte: reste,
          date: msg.date,
          heure: msg.heure,
          auteur: msg.auteur,
        });
      }
      continue;
    }
    if (OMITTED_RE.test(msg.texte) && msg.texte.length < 60) {
      photos.push(photoVide({ nomFichier: "", date: msg.date, dateSource: "message" }));
      continue;
    }
    if (/^(https?:\/\/\S+)$/.test(msg.texte)) continue;
    souvenirs.push({
      id: uid(),
      texte: msg.texte,
      date: msg.date,
      heure: msg.heure,
      auteur: msg.auteur,
    });
  }
  return { souvenirs, photos };
}

/**
 * Extrait la date d'un nom de fichier photo.
 *
 * WhatsApp réécrit la date de modification au moment du téléchargement : une
 * photo prise en juillet arrive datée d'aujourd'hui. Le nom, lui, porte
 * presque toujours la vraie date — « Nom conv WhatsApp - 2026-08-27 11.26.10 »,
 * « IMG-20260827-WA0003.jpg », « PXL_20260827_112610.jpg », « Photo
 * 27-08-2026 à 11.26 ». C'est donc lui qui fait foi, et la métadonnée ne sert
 * que de secours.
 */
function dateDepuisNom(nom) {
  const texte = String(nom || "");

  // Année en tête : 2026-08-27, 2026_08_27, 20260827, éventuellement suivie
  // d'une heure séparée par un espace, un tiret ou un souligné.
  let m = texte.match(
    /(20\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])(?:[ _T-]+(?:at\s+|à\s+)?([01]\d|2[0-3])[-_.h]?([0-5]\d))?/,
  );
  if (m) return { date: `${m[1]}-${m[2]}-${m[3]}`, heure: m[4] ? `${m[4]}:${m[5]}` : "" };

  // Jour en tête : 27-08-2026, 27.08.2026 — la forme française des exports iOS.
  m = texte.match(
    /(0[1-9]|[12]\d|3[01])[-_.](0[1-9]|1[0-2])[-_.](20\d{2})(?:[ _]+(?:à\s*)?([01]\d|2[0-3])[-_.h]?([0-5]\d))?/,
  );
  if (m) return { date: `${m[3]}-${m[2]}-${m[1]}`, heure: m[4] ? `${m[4]}:${m[5]}` : "" };

  return { date: "", heure: "" };
}

function photoVide(meta) {
  return {
    id: uid(),
    nomFichier: "",
    legende: "",
    date: "",
    heure: "",
    /** « nom de fichier » ou « métadonnée » : d'où vient la date retenue. */
    dateSource: "",
    data: null,
    largeur: 0,
    hauteur: 0,
    orientation: "",
    /** Photo de groupe : jamais rognée, seulement réduite (LAYOUT_KB § « Rognage des photos »). */
    groupe: false,
    /** Désignée pour la couverture par le voyageur. Une seule à la fois. */
    couverture: false,
    ...meta,
  };
}

/* ------------------------------------------------------------------- état --- */

const MODELE_PAR_FOURNISSEUR = { openai: "gpt-4o", anthropic: "claude-opus-5" };

const REGLAGES_DEFAUT = {
  cleOpenai: "",
  cleAnthropic: "",
  modeleTranscription: "gpt-4o-transcribe",
  langue: "fr",
  vocabulaire: "",
  fournisseurDecoupage: "openai",
  modeleDecoupage: "gpt-4o",
  dossierDisque: "",
  cleApitemplate: "",
  templateApitemplate: "7a177b23210099d6",
  /**
   * Le template APITemplate de la version imprimeur : une copie du premier
   * dont la feuille fait 154 × 216 mm, soit 3 mm de fond perdu sur chaque bord
   * (LAYOUT_KB § « Fond perdu »). Le format de la feuille se règle dans le
   * panneau d'APITemplate, pas dans le code : un même template ne peut pas
   * sortir l'aperçu en A5 et l'intérieur à imprimer avec fond perdu.
   */
  templateApitemplateImprimeur: "",
  /** Rendu pour l'imprimeur (Pumbo) : sans couverture ni quatrième, nombre de pages pair. */
  versionImprimeur: false,
  baseApitemplate: "https://rest-de.apitemplate.io/v2",
};

function chargerReglages() {
  let reglages = { ...REGLAGES_DEFAUT };
  try {
    reglages = { ...reglages, ...JSON.parse(localStorage.getItem("atelier-reglages") || "{}") };
  } catch {
    /* réglages illisibles : on repart des défauts */
  }
  // Les clés sont toujours retenues : l'ancienne case « Retenir sur ce
  // navigateur » décochée n'a plus d'effet.
  delete reglages.retenirCles;
  // Un réglage vide vaut « pas de choix », pas « champ vide » : une session
  // enregistrée avant que le modèle ait un défaut ne doit pas rester creuse.
  if (!reglages.modeleDecoupage?.trim()) {
    reglages.modeleDecoupage = MODELE_PAR_FOURNISSEUR[reglages.fournisseurDecoupage] || "gpt-4o";
  }
  return reglages;
}

/**
 * Tout est retenu, clés comprises : c'est un outil de poste de travail, et
 * une clé perdue au rechargement fait retomber le serveur local sur celle de
 * `backend/.env` — qui n'est pas forcément la bonne.
 */
function sauverReglages() {
  try {
    localStorage.setItem("atelier-reglages", JSON.stringify(etat.reglages));
  } catch (erreur) {
    console.warn("[atelier] réglages non enregistrés (navigation privée ?)", erreur);
  }
}

function chargerBoites() {
  try {
    return JSON.parse(localStorage.getItem("atelier-boites") || "{}");
  } catch {
    return {};
  }
}

const etat = {
  /** Les messages de la mise en page déjà portés au journal visible (fun facts, photos écartées). */
  rapportsCarnet: new Set(),
  /**
   * Les réglages de personnalisation de l'app, avec ses défauts
   * (`reglagesDuCarnet`) : `funFacts` (« Insérer des Fun facts »),
   * `ratioPhotos` (ratio photo / texte, en %), `reglure` (« Pointillés »),
   * `decorations` (« Décorations & stickers » : le nombre de stickers par
   * étape, 2 par défaut — Hugo, 14/10/2026),
   * `zonesLibres` (« Zones libres » : trois pages réglées en fin de carnet),
   * `quiz` (« Quiz intégrés à l'histoire » : environ un toutes les trois étapes),
   * `formatPages` (« Nombre de pages » : compact, standard, détaillé — tirés
   * de la durée du voyage comme dans l'app, `pagesDuFormat` — ou perso) et
   * `pagesCible` (le nombre choisi en perso). Le carnet tient la cible à
   * ± 5 pages par ses planches de photos.
   */
  carnet: {
    titre: "",
    destination: "",
    dateDebut: "",
    dateFin: "",
    voyageurs: "",
    funFacts: true,
    ratioPhotos: 50,
    reglure: true,
    decorations: 2,
    zonesLibres: true,
    quiz: true,
    formatPages: "standard",
    pagesCible: null,
  },
  /** Un champ touché à la main n'est plus jamais réécrit par la déduction. */
  carnetManuel: {},
  carnetDeduit: {},
  /** Prénoms croisés en chemin, cumulés vocal après vocal. */
  rencontres: [],
  /** Dernier PDF rendu par APITemplate, pour garder le lien sous la main. */
  pdf: null,
  /** Contours des pays (`assets/maps/countries.json`), chargés à la première carte. */
  contoursCarte: null,
  /** Le panneau « Couverture du livre » : ouvert ou non, textes repris par le voyageur. */
  couverture: {
    ouverte: false,
    statut: "",
    textes: {},
    autre: { recto: false, verso: false },
    // Le style de couverture (`CouvertureStyles.STYLES`), et les textes de
    // chaque style : rédigés par l'IA, repris par le voyageur.
    style: "default",
    textesStyle: {},
    // Les illustrations générées, par style puis par image (`imagesDuStyle`) :
    // `{ data, px, dominante }`. Gardées dans l'avancement.
    images: {},
    // Photo-dessin : par photo, le contour des voyageurs et ses couleurs.
    photosDessin: {},
  },
  /** Le logo rastérisé pour le fichier InDesign. */
  logoPng: null,
  /** Contours détaillés par pays (`assets/maps/detail/`), chargés pour les cartes cadrées sur le voyage. */
  contoursDetail: null,
  indexDetail: null,
  /** Les rues et l'eau des cartes de ville (OpenStreetMap), par clé de vue (`Carte.cleDeVue`). */
  ruesDesVilles: {},
  /** Message sous « Générer le carnet » : { type: "info" | "erreur", texte }. */
  carnetStatut: null,
  etapes: [],
  /** Vocaux déposés mais pas encore transcrits — ils vivent dans leur boîte. */
  vocauxAttente: [],
  /** Photos qu'aucune étape ne réclame encore (pas de date, ou pas d'étape). */
  photosAttente: [],
  reglages: chargerReglages(),
  boites: chargerBoites(),
  session: crypto.randomUUID(),
  raw: "",
  texteGroupe: "",
  groupeModifie: false,
  journal: [],
  transcriptionEnCours: false,
  classementEnCours: false,
  erreur: "",
  info: "",
  montrerExport: false,
  avecPhotos: true,
  config: null,
  /**
   * « local » quand le serveur Node répond — la transcription passe alors par
   * scripts/transcribe-whatsapp.sh. « navigateur » sur l'hébergement statique :
   * la page appelle les APIs elle-même, avec la clé du visiteur.
   */
  mode: "local",
};

/** La fiche du carnet d'un voyage neuf : ce que reprend un avancement qui ne dit rien. */
const CARNET_DEFAUT = structuredClone(etat.carnet);

/* --------------------------------------------------- déplacer et modifier --- */

const conteneur = (id) => etat.etapes.find((e) => e.id === id);

// Les photos ont une deuxième « étape » possible : `null` désigne la boîte
// d'attente (`etat.photosAttente`), pour qu'une photo puisse y retourner.
const listePhotos = (id) => (id ? conteneur(id)?.photos : etat.photosAttente);

function deplacer(genre, itemId, deId, versId) {
  if (deId === versId) return;
  const source = genre === "photos" ? listePhotos(deId) : conteneur(deId)?.[genre];
  const index = source ? source.findIndex((x) => x.id === itemId) : -1;
  if (index === -1) return;
  const cible = genre === "photos" ? listePhotos(versId) : conteneur(versId)?.[genre];
  if (!cible) return;
  cible.push(source.splice(index, 1)[0]);
  apresChangement();
}

function modifier(genre, itemId, conteneurId, patch) {
  const liste = genre === "photos" ? listePhotos(conteneurId) : conteneur(conteneurId)?.[genre];
  const item = liste?.find((x) => x.id === itemId);
  if (item) Object.assign(item, patch);
}

function retirer(genre, itemId, conteneurId) {
  if (genre === "photos" && !conteneurId) {
    etat.photosAttente = etat.photosAttente.filter((x) => x.id !== itemId);
    apresChangement();
    return;
  }
  const c = conteneur(conteneurId);
  if (!c) return;
  c[genre] = c[genre].filter((x) => x.id !== itemId);
  apresChangement();
}

/* ------------------------------------------------------- dates déduites --- */

/**
 * Les bornes du voyage, telles que les étapes les racontent.
 *
 * On lit les dates des **étapes**, pas celles des fichiers : la date d'un
 * vocal est celle de son téléchargement WhatsApp, pas celle de la journée
 * racontée. Les dates de fichier ne servent que de secours.
 */
function bornesDuVoyage() {
  const dates = [];
  for (const etape of etat.etapes) {
    if (etape.dateDebut) dates.push(etape.dateDebut);
    if (etape.dateFin) dates.push(etape.dateFin);
  }
  if (!dates.length) {
    for (const s of etat.etapes.flatMap((e) => e.souvenirs)) if (s.date) dates.push(s.date);
  }
  dates.sort();
  return { premiere: dates[0], derniere: dates[dates.length - 1] };
}

/**
 * Le retour du carnet suit la dernière étape enregistrée, tant que personne
 * n'a écrit de date à la main : un voyage en cours avance tout seul.
 *
 * Les dates d'étape déjà posées — par le modèle ou par la main — ne sont pas
 * touchées ; on ne remplit que les trous.
 */
function majDatesAuto() {
  for (const etape of etat.etapes) {
    const dates = etape.souvenirs.map((s) => s.date).filter(Boolean).sort();
    if (!dates.length) continue;
    if (!etape.dateDebut) etape.dateDebut = dates[0];
    if (!etape.dateFin) etape.dateFin = dates[dates.length - 1];
  }

  const { premiere, derniere } = bornesDuVoyage();
  if (!derniere) return;
  if (!etat.carnetManuel.dateFin) {
    etat.carnetDeduit.dateFin = etat.carnet.dateFin !== derniere || etat.carnetDeduit.dateFin;
    etat.carnet.dateFin = derniere;
  }
  if (!etat.carnetManuel.dateDebut && !etat.carnet.dateDebut && premiere) {
    etat.carnet.dateDebut = premiere;
    etat.carnetDeduit.dateDebut = true;
  }
}

/**
 * Réunit deux listes de prénoms sans doublon, à la casse près, en gardant
 * l'orthographe rencontrée la première fois.
 */
function fusionnerNoms(existants, nouveaux) {
  const vus = new Map();
  for (const brut of [...(existants || []), ...(nouveaux || [])]) {
    const propre = String(brut || "").trim().replace(/^["'«»]|["'«»]$/g, "");
    if (!propre || propre.length > 40) continue;
    const cle = propre.toLocaleLowerCase("fr");
    if (!vus.has(cle)) vus.set(cle, propre);
  }
  return [...vus.values()];
}

const listeVoyageurs = () =>
  etat.carnet.voyageurs.split(",").map((v) => v.trim()).filter(Boolean);

/**
 * Applique ce que le modèle a compris du voyage, sans écraser la main.
 *
 * Voyageurs et rencontres se **cumulent** : quelqu'un nommé dans le premier
 * vocal et jamais recité ne doit pas disparaître au douzième.
 */
function appliquerCarnetDeduit(suggere) {
  const poser = (champ, valeur) => {
    if (etat.carnetManuel[champ] || !valeur) return;
    etat.carnet[champ] = valeur;
    etat.carnetDeduit[champ] = true;
  };
  poser("titre", suggere.titre);
  poser("destination", suggere.destination);
  poser("dateDebut", suggere.date_debut);
  poser("dateFin", suggere.date_fin);

  if (!etat.carnetManuel.voyageurs) {
    const fusion = fusionnerNoms(listeVoyageurs(), suggere.voyageurs);
    if (fusion.length) poser("voyageurs", fusion.join(", "));
  }

  // Une personne devenue compagnon de route quitte la liste des rencontres.
  const voyageurs = new Set(listeVoyageurs().map((v) => v.toLocaleLowerCase("fr")));
  etat.rencontres = fusionnerNoms(etat.rencontres, suggere.rencontres).filter(
    (nom) => !voyageurs.has(nom.toLocaleLowerCase("fr")),
  );
}

/* ---------------------------------------------------------------- imports --- */

function importerTexte() {
  if (!etat.raw.trim()) return;
  const { souvenirs, photos } = parseWhatsapp(etat.raw);
  etat.photosAttente.push(...photos);
  etat.raw = "";
  majBoiteWhatsapp();
  if (souvenirs.length) classer(souvenirs);
  else apresChangement();
}

function importerPhotos(liste) {
  const fichiers = Array.from(liste || []).filter((f) => f.type.startsWith("image/"));
  fichiers.forEach((fichier) => {
    const lecteur = new FileReader();
    lecteur.onload = () => {
      const data = lecteur.result;
      const img = new Image();
      img.onload = () => {
        const meta = {
          nomFichier: fichier.name,
          data,
          largeur: img.naturalWidth,
          hauteur: img.naturalHeight,
          orientation:
            img.naturalWidth > img.naturalHeight
              ? "paysage"
              : img.naturalWidth === img.naturalHeight
                ? "carre"
                : "portrait",
          ...datePhoto(fichier),
        };
        // un emplacement vide qui porte déjà ce nom de fichier se remplit
        const attendue = [...etat.photosAttente, ...etat.etapes.flatMap((e) => e.photos)].find(
          (ph) => !ph.data && ph.nomFichier === fichier.name,
        );
        if (attendue) Object.assign(attendue, meta);
        else etat.photosAttente.push(photoVide(meta));
        rangerPhotos();
      };
      img.src = data;
    };
    lecteur.readAsDataURL(fichier);
  });
}

/** Le nom du fichier d'abord, la métadonnée seulement s'il ne dit rien. */
function datePhoto(fichier) {
  const duNom = dateDepuisNom(fichier.name);
  if (duNom.date) return { ...duNom, dateSource: "nom de fichier" };
  return {
    date: fichier.lastModified
      ? new Date(fichier.lastModified).toISOString().slice(0, 10)
      : "",
    heure: "",
    dateSource: fichier.lastModified ? "métadonnée" : "",
  };
}

/** Mesure la durée d'un audio pour la statistique « temps de voix ». */
function mesurerDuree(entree) {
  const sonde = new Audio(entree.url);
  sonde.addEventListener("loadedmetadata", () => {
    if (Number.isFinite(sonde.duration)) {
      entree.duree = sonde.duration;
      const souvenir = tousLesSouvenirs().find((s) => s.audioNom === entree.nom);
      if (souvenir) souvenir.duree = sonde.duration;
      majStats();
      rendreStats();
    }
  });
}

function importerAudios(liste) {
  const fichiers = Array.from(liste || [])
    .filter((f) => f.type.startsWith("audio") || estAudio(f.name))
    // Le tri numérique remet « (2) » avant « (10) ». Le serveur, lui, repose
    // les dates de fichier et laisse le script trier par date : c'est cet
    // ordre-là qui fait foi dans la transcription.
    .sort((a, b) => a.name.localeCompare(b.name, "fr", { numeric: true }));

  for (const fichier of fichiers) {
    const nom = normaliserNomAudio(fichier.name);
    if (etat.vocauxAttente.some((v) => v.nomOrigine === fichier.name)) continue;
    const entree = {
      id: uid(),
      fichier,
      nom,
      nomOrigine: fichier.name,
      url: URL.createObjectURL(fichier),
      date: fichier.lastModified
        ? new Date(fichier.lastModified).toISOString().slice(0, 10)
        : "",
      duree: 0,
      etat: "en attente",
    };
    etat.vocauxAttente.push(entree);
    mesurerDuree(entree);
  }
  majBoiteVocaux();
  majStats();
}

/* --------------------------------------------------------------- réseau --- */

/** Le serveur relaie en local ; en ligne la page appelle l'API elle-même. */
async function appelDecoupage(corps) {
  if (etat.mode === "navigateur") return MoteurNavigateur.decouper(corps);
  return appelJson("/api/decouper", corps);
}

async function appelJson(url, corps) {
  const reponse = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(corps),
  });
  const donnees = await reponse.json().catch(() => ({}));
  if (!reponse.ok) throw new Error(donnees.erreur || `Erreur ${reponse.status}`);
  return donnees;
}

function noter(texte, canal = "out") {
  Journal.log(canal === "err" ? "erreur" : "info", "atelier", texte);
  etat.journal.push({ texte, canal });
  majJournal();
}

async function transcrireVocaux({ force = false } = {}) {
  // Un vocal déjà transcrit reste dans la liste — pour être réécouté, ou
  // repassé en `--force` — mais il n'est pas redéposé pour rien.
  const vocaux = etat.vocauxAttente.filter((v) => v.fichier && (force || v.etat !== "transcrit"));
  if (etat.transcriptionEnCours) return;
  if (!vocaux.length && !etat.vocauxAttente.length) return;

  etat.transcriptionEnCours = true;
  etat.erreur = "";
  etat.info = "";
  etat.journal = [];
  majBoiteVocaux();
  noter(
    vocaux.length
      ? etat.mode === "navigateur"
        ? `Transcription de ${vocaux.length} vocal(aux), depuis ce navigateur…`
        : `Envoi de ${vocaux.length} vocal(aux) au serveur local…`
      : "Rien de neuf à envoyer — relecture des transcriptions déjà en cache.",
  );

  try {
    for (const entree of etat.mode === "navigateur" ? [] : vocaux) {
      entree.etat = "envoi";
      majBoiteVocaux();
      const reponse = await fetch(`/api/vocaux/${etat.session}`, {
        method: "POST",
        headers: {
          "content-type": "application/octet-stream",
          "x-nom-fichier": btoa(
            String.fromCharCode(...new TextEncoder().encode(entree.fichier.name)),
          ),
          "x-modifie-le": String(entree.fichier.lastModified || 0),
        },
        body: entree.fichier,
      });
      const donnees = await reponse.json();
      if (!reponse.ok) throw new Error(donnees.erreur || "Dépôt refusé");
      entree.nom = donnees.nom;
      entree.etat = "déposé";
      if (donnees.renomme) noter(`  ${donnees.nomOrigine} → ${donnees.nom}`);
    }
    majBoiteVocaux();
    if (etat.mode === "navigateur") await transcrireIci(vocaux, force);
    else await lancerScript({ session: etat.session, force });
  } catch (erreur) {
    etat.erreur = erreur.message;
    noter(erreur.message, "err");
    for (const v of etat.vocauxAttente) if (v.etat !== "transcrit") v.etat = "en attente";
  } finally {
    etat.transcriptionEnCours = false;
    majBoiteVocaux();
    apresChangement();
  }
}

async function transcrireDossier() {
  const dossier = etat.reglages.dossierDisque.trim();
  if (!dossier || etat.transcriptionEnCours) return;
  etat.transcriptionEnCours = true;
  etat.erreur = "";
  etat.info = "";
  etat.journal = [];
  majBoiteVocaux();
  try {
    await lancerScript({ dossier });
  } catch (erreur) {
    etat.erreur = erreur.message;
    noter(erreur.message, "err");
  } finally {
    etat.transcriptionEnCours = false;
    majBoiteVocaux();
    apresChangement();
  }
}

/**
 * Version sans serveur : la page transcrit elle-même, puis rejoint la même
 * suite de traitement que le script. Le journal reste identique, ligne pour
 * ligne, pour qu'un dépannage se lise pareil des deux côtés.
 */
async function transcrireIci(vocaux, force) {
  const resultat = await MoteurNavigateur.transcrire({
    vocaux: etat.vocauxAttente.filter((v) => v.fichier),
    reglages: etat.reglages,
    force,
    noter,
  });
  if (!resultat.texteGroupe.trim() || !resultat.blocs.length) {
    throw new Error("Aucune transcription produite — voir le journal ci-dessus.");
  }
  if (resultat.partiel) {
    noter(
      `${resultat.echecs} vocal(aux) en échec — relance, les réussites ne seront pas refacturées.`,
      "err",
    );
  }
  await integrerTranscriptions(resultat.blocs);
}

/**
 * Appelle `/api/transcrire` et lit le flux NDJSON du script au fil de l'eau :
 * les `[03/12] Voice message (2).ogg` s'affichent pendant que ça tourne.
 */
async function lancerScript(options) {
  const reponse = await fetch("/api/transcrire", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      ...options,
      cleOpenai: etat.reglages.cleOpenai,
      modele: etat.reglages.modeleTranscription,
      langue: etat.reglages.langue,
      prompt: etat.reglages.vocabulaire,
    }),
  });

  if (!reponse.ok) {
    const donnees = await reponse.json().catch(() => ({}));
    throw new Error(donnees.erreur || `Erreur ${reponse.status}`);
  }

  const lecteur = reponse.body.getReader();
  const decodeur = new TextDecoder();
  let tampon = "";
  let fin = null;

  for (;;) {
    const { done, value } = await lecteur.read();
    if (done) break;
    tampon += decodeur.decode(value, { stream: true });
    const lignes = tampon.split("\n");
    tampon = lignes.pop() ?? "";
    for (const ligne of lignes) {
      if (!ligne.trim()) continue;
      const evenement = JSON.parse(ligne);
      if (evenement.type === "debut") {
        noter(`${evenement.script} sur ${evenement.dossier}`);
        if (evenement.cle) noter(`Clé OpenAI : ${evenement.cle}`);
      } else if (evenement.type === "ligne") {
        noter(evenement.texte, evenement.canal);
      } else if (evenement.type === "erreur") {
        throw new Error(evenement.message);
      } else if (evenement.type === "fin") {
        fin = evenement;
      }
    }
  }

  if (!fin) throw new Error("Le script s'est interrompu sans rendre de résultat.");
  if (!fin.texteGroupe.trim()) {
    throw new Error("Aucune transcription produite — voir le journal ci-dessus.");
  }
  if (fin.partiel) {
    noter("Transcription partielle : certains vocaux ont échoué, relance pour les reprendre.", "err");
  }

  await integrerTranscriptions(fin.blocs);
}

/**
 * Chaque transcription devient un souvenir, puis part se faire classer.
 * C'est le cœur de la boucle : on dépose, on transcrit, et l'étape existe.
 */
async function integrerTranscriptions(blocs) {
  const nouveaux = [];
  const existants = tousLesSouvenirs();

  for (const bloc of blocs) {
    if (!bloc.texte) continue;
    const entree = etat.vocauxAttente.find((v) => v.nom === bloc.nom);
    const deja = bloc.nom && existants.find((s) => s.audioNom === bloc.nom);
    if (deja) {
      deja.texte = bloc.texte;
      if (!deja.date && bloc.date) deja.date = bloc.date;
      if (entree) entree.etat = "transcrit";
      continue;
    }
    nouveaux.push({
      id: uid(),
      texte: bloc.texte,
      date: bloc.date || entree?.date || "",
      heure: "",
      auteur: "",
      audioNom: bloc.nom || undefined,
      audioUrl: entree?.url || null,
      duree: entree?.duree || 0,
    });
    if (entree) entree.etat = "transcrit";
  }

  noter(`${blocs.length} transcription(s) — classement en cours…`);
  await classer(nouveaux);
}

/* ------------------------------------------------------------- classement --- */

const tousLesSouvenirs = () => etat.etapes.flatMap((e) => e.souvenirs);

/**
 * Range des souvenirs dans des étapes, en repassant tout le récit au modèle :
 * un vocal arrivé après coup peut appartenir à une étape déjà écrite, ou la
 * couper en deux. Les titres, lieux et dates écrits à la main sont conservés.
 *
 * Sans clé ou en cas d'échec, on retombe sur un découpage par date : le vocal
 * est rangé quand même, l'outil ne reste jamais bloqué.
 */
async function classer(nouveaux) {
  const anciens = etat.etapes.map((e) => ({ etape: e, souvenirs: e.souvenirs }));
  const tous = [...tousLesSouvenirs(), ...nouveaux].sort((a, b) =>
    `${a.date || "9999"}${a.heure || ""}`.localeCompare(`${b.date || "9999"}${b.heure || ""}`),
  );
  if (!tous.length) return apresChangement();

  etat.classementEnCours = true;
  etat.erreur = "";
  rendreEtapes();

  const blocs = tous.map((s, i) => ({
    index: i,
    nom: s.audioNom || "",
    date: `${s.date || ""} ${s.heure || ""}`.trim(),
    texte: s.texte.trim() || "[vocal pas encore transcrit]",
  }));

  // Ce que le modèle doit reprendre tel quel : les étapes déjà titrées à la main.
  const dejaTitrees = [];
  for (const { etape, souvenirs } of anciens) {
    if (!etape.manuel?.titre && !etape.manuel?.lieu) continue;
    const indices = souvenirs.map((s) => tous.indexOf(s)).filter((i) => i >= 0);
    if (indices.length) {
      dejaTitrees.push({
        titre: etape.titre,
        lieu: etape.lieu,
        debut: Math.min(...indices),
        fin: Math.max(...indices),
      });
    }
  }

  try {
    const reponse = await appelDecoupage({
      fournisseur: etat.reglages.fournisseurDecoupage,
      modele: etat.reglages.modeleDecoupage.trim() || undefined,
      cleOpenai: etat.reglages.cleOpenai,
      cleAnthropic: etat.reglages.cleAnthropic,
      dejaTitrees,
      dejaConnus: { voyageurs: listeVoyageurs(), rencontres: etat.rencontres },
      blocs,
    });

    const pris = new Set();
    const nouvelles = [];
    for (const segment of reponse.etapes || []) {
      const debut = Math.max(0, Math.min(tous.length - 1, segment.debut ?? 0));
      const finSeg = Math.max(debut, Math.min(tous.length - 1, segment.fin ?? debut));
      const dedans = [];
      for (let i = debut; i <= finSeg; i++) {
        if (!pris.has(i)) {
          pris.add(i);
          dedans.push(tous[i]);
        }
      }
      if (!dedans.length) continue;
      nouvelles.push(construireEtape(segment, dedans, anciens));
    }
    // Un bloc oublié par le modèle rejoint l'étape précédente plutôt que de
    // disparaître : perdre un souvenir serait le pire des échecs.
    tous.forEach((s, i) => {
      if (pris.has(i)) return;
      const hote = nouvelles[nouvelles.length - 1];
      if (hote) hote.souvenirs.push(s);
    });
    if (!nouvelles.length) throw new Error("aucun segment exploitable");

    etat.etapes = nouvelles;
    appliquerCarnetDeduit(reponse.carnet || {});
    etat.info = `${nouvelles.length} étape(s) — classement par ${reponse.modele}.`;
  } catch (erreur) {
    etat.etapes = classerParDate(tous, anciens);
    etat.erreur = `Classement automatique indisponible (${erreur.message}) — rangé par date.`;
  } finally {
    recupererPhotosOrphelines(anciens);
    etat.classementEnCours = false;
    etat.groupeModifie = false;
    apresChangement();
  }
}

/**
 * Une étape que le nouveau découpage n'a pas reprise emporterait ses photos
 * avec elle. On les remet en attente : elles se rerangeront par date.
 */
function recupererPhotosOrphelines(anciens) {
  const vivantes = new Set(etat.etapes.map((e) => e.id));
  for (const { etape } of anciens) {
    if (vivantes.has(etape.id)) continue;
    etat.photosAttente.push(...etape.photos);
  }
  if (etat.photosAttente.length && etat.etapes.length) {
    const restantes = [];
    for (const photo of etat.photosAttente) {
      const cible = photo.date
        ? etat.etapes.find(
            (e) =>
              e.dateDebut && photo.date >= e.dateDebut && photo.date <= (e.dateFin || e.dateDebut),
          ) || etapeLaPlusProche(photo.date)
        : null;
      if (cible) cible.photos.push(photo);
      else restantes.push(photo);
    }
    etat.photosAttente = restantes;
  }
  majBoitePhotos();
}

/** Reprend ce qu'une étape précédente avait de manuel sur le même contenu. */
function construireEtape(segment, souvenirs, anciens) {
  const reprise = anciens.find(
    (a) => !a.consommee && a.souvenirs.some((s) => souvenirs.includes(s)),
  );
  if (reprise) reprise.consommee = true;
  const ancienne = reprise?.etape;
  const manuel = ancienne?.manuel || {};
  const dates = souvenirs.map((s) => s.date).filter(Boolean).sort();
  return {
    id: ancienne?.id || uid(),
    titre: manuel.titre ? ancienne.titre : segment?.titre || ancienne?.titre || "",
    lieu: manuel.lieu ? ancienne.lieu : segment?.lieu || ancienne?.lieu || "",
    dateDebut: manuel.dateDebut ? ancienne.dateDebut : segment?.date_debut || dates[0] || "",
    dateFin: manuel.dateFin
      ? ancienne.dateFin
      : segment?.date_fin || dates[dates.length - 1] || "",
    manuel: { ...manuel },
    souvenirs,
    photos: ancienne?.photos ? [...ancienne.photos] : [],
  };
}

/** Le filet déterministe : une étape par journée. */
function classerParDate(souvenirs, anciens) {
  const parJour = new Map();
  for (const s of souvenirs) {
    const cle = s.date || "sans date";
    if (!parJour.has(cle)) parJour.set(cle, []);
    parJour.get(cle).push(s);
  }
  return [...parJour.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([, liste]) => construireEtape(null, liste, anciens));
}

/**
 * Chaque photo rejoint l'étape qui couvre sa date ; à défaut, l'étape dont la
 * date est la plus proche. Sans étape ni date, elle patiente dans sa boîte.
 */
function rangerPhotos() {
  if (!etat.etapes.length) {
    majBoitePhotos();
    apresChangement();
    return;
  }
  const restantes = [];
  for (const photo of etat.photosAttente) {
    if (!photo.date) {
      restantes.push(photo);
      continue;
    }
    const couvre = etat.etapes.find(
      (e) => e.dateDebut && photo.date >= e.dateDebut && photo.date <= (e.dateFin || e.dateDebut),
    );
    const cible = couvre || etapeLaPlusProche(photo.date);
    if (cible) cible.photos.push(photo);
    else restantes.push(photo);
  }
  etat.photosAttente = restantes;
  majBoitePhotos();
  apresChangement();
}

function etapeLaPlusProche(date) {
  const jour = (d) => new Date(`${d}T00:00:00Z`).getTime();
  let meilleure = null;
  let ecart = Infinity;
  for (const etape of etat.etapes) {
    const ref = etape.dateDebut || etape.dateFin;
    if (!ref) continue;
    const d = Math.min(
      Math.abs(jour(date) - jour(ref)),
      etape.dateFin ? Math.abs(jour(date) - jour(etape.dateFin)) : Infinity,
    );
    if (d < ecart) {
      ecart = d;
      meilleure = etape;
    }
  }
  return meilleure;
}

/* ----------------------------------------------------------------- étapes --- */

function ajouterEtape() {
  etat.etapes.push({
    id: uid(),
    titre: "",
    lieu: "",
    dateDebut: "",
    dateFin: "",
    manuel: {},
    souvenirs: [],
    photos: [],
  });
  apresChangement();
}

function supprimerEtape(id) {
  const etape = etat.etapes.find((e) => e.id === id);
  if (!etape) return;
  // Les photos ne disparaissent pas avec l'étape : elles retournent en attente.
  etat.photosAttente.push(...etape.photos);
  etat.etapes = etat.etapes.filter((e) => e.id !== id);
  majBoitePhotos();
  apresChangement();
}

/**
 * Copie une étape juste en dessous. Souvenirs et photos sont recopiés avec de
 * nouveaux identifiants : sans ça, modifier la copie modifierait l'original,
 * et un glisser-déposer déplacerait les deux à la fois.
 */
function dupliquerEtape(id) {
  const index = etat.etapes.findIndex((e) => e.id === id);
  if (index < 0) return;
  const source = etat.etapes[index];
  const copie = {
    ...source,
    id: uid(),
    titre: source.titre ? `${source.titre} (copie)` : "",
    manuel: { ...(source.manuel || {}) },
    souvenirs: source.souvenirs.map((s) => ({ ...s, id: uid() })),
    photos: source.photos.map((p) => ({ ...p, id: uid() })),
  };
  etat.etapes.splice(index + 1, 0, copie);
  apresChangement();
}

function deplacerEtape(id, sens) {
  const i = etat.etapes.findIndex((e) => e.id === id);
  const j = i + sens;
  if (i < 0 || j < 0 || j >= etat.etapes.length) return;
  [etat.etapes[i], etat.etapes[j]] = [etat.etapes[j], etat.etapes[i]];
  apresChangement();
}

/* --------------------------------------------------------- étapes groupées --- */

/**
 * Le grand champ du haut est la vue d'ensemble du carnet : uniquement ce qui
 * est dans les étapes, dans leur ordre. Les crochets marquent la source de
 * chaque souvenir, ce qui permet de relire le texte puis de le réappliquer.
 */
function construireTexteEtapes() {
  const morceaux = [];
  etat.etapes.forEach((etape, i) => {
    const dates = [etape.dateDebut, etape.dateFin].filter(Boolean);
    const entete = [
      `${String(i + 1).padStart(2, "0")}`,
      etape.titre || "Étape sans titre",
      etape.lieu,
      dates.length === 2 && dates[0] !== dates[1] ? `${dates[0]} → ${dates[1]}` : dates[0],
    ].filter(Boolean);
    morceaux.push(`## ${entete.join(" · ")}`);
    for (const s of etape.souvenirs) {
      morceaux.push(`[${s.audioNom || ""}]`);
      morceaux.push(s.texte.trim());
      morceaux.push("");
    }
    morceaux.push("");
  });
  return morceaux.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

/** Relit ce même format et réapplique les corrections aux étapes. */
function appliquerTexteEtapes() {
  const lignes = etat.texteGroupe.split(/\r?\n/);
  const sections = [];
  let section = null;
  let souvenir = null;

  for (const ligne of lignes) {
    const titre = ligne.match(/^##\s*(.*)$/);
    if (titre) {
      const parts = titre[1].split("·").map((p) => p.trim());
      if (/^\d+$/.test(parts[0])) parts.shift();
      const dates = (parts[parts.length - 1] || "").match(
        /(\d{4}-\d{2}-\d{2})(?:\s*→\s*(\d{4}-\d{2}-\d{2}))?/,
      );
      if (dates) parts.pop();
      section = {
        titre: parts[0] === "Étape sans titre" ? "" : parts[0] || "",
        lieu: parts[1] || "",
        dateDebut: dates?.[1] || "",
        dateFin: dates?.[2] || dates?.[1] || "",
        souvenirs: [],
      };
      sections.push(section);
      souvenir = null;
      continue;
    }
    const source = ligne.match(/^\[(.*)\]\s*$/);
    if (source && section) {
      souvenir = { nom: source[1].trim(), lignes: [] };
      section.souvenirs.push(souvenir);
      continue;
    }
    if (souvenir) souvenir.lignes.push(ligne);
  }

  if (!sections.length) {
    etat.erreur = "Aucune étape reconnue : garde les lignes « ## … » en tête de chaque étape.";
    rendreGroupe();
    return;
  }

  const parNom = new Map();
  for (const s of tousLesSouvenirs()) if (s.audioNom) parNom.set(s.audioNom, s);
  const anciens = etat.etapes.map((e) => ({ etape: e, souvenirs: e.souvenirs }));
  const restants = tousLesSouvenirs();

  etat.etapes = sections.map((sec, i) => {
    const souvenirs = sec.souvenirs.map((bloc) => {
      const texte = bloc.lignes.join("\n").trim();
      const existant = bloc.nom && parNom.get(bloc.nom);
      if (existant) {
        existant.texte = texte;
        return existant;
      }
      // Pas de nom : on reprend le souvenir de même rang s'il existe encore.
      const libre = restants.find((s) => !s.audioNom && !s.repris);
      if (libre) {
        libre.repris = true;
        libre.texte = texte;
        return libre;
      }
      return { id: uid(), texte, date: "", heure: "", auteur: "" };
    });
    const ancienne = anciens[i]?.etape;
    return {
      id: ancienne?.id || uid(),
      titre: sec.titre,
      lieu: sec.lieu,
      dateDebut: sec.dateDebut,
      dateFin: sec.dateFin,
      manuel: { ...(ancienne?.manuel || {}), titre: true, lieu: true },
      souvenirs,
      photos: ancienne?.photos ? [...ancienne.photos] : [],
    };
  });

  for (const s of tousLesSouvenirs()) delete s.repris;
  etat.groupeModifie = false;
  etat.info = "Modifications appliquées aux étapes.";
  apresChangement();
}

/** Redemande un découpage au modèle, en repartant de zéro sur les étapes. */
async function redecouper() {
  if (etat.classementEnCours) return;
  const souvenirs = tousLesSouvenirs();
  if (!souvenirs.length) return;
  // Les photos repassent en attente : elles se rerangeront sur les nouvelles
  // étapes plutôt que de disparaître avec les anciennes.
  etat.photosAttente.push(...photosDesEtapes());
  etat.etapes = [];
  etat.groupeModifie = false;
  await classer(souvenirs);
  rangerPhotos();
}

const photosDesEtapes = () => etat.etapes.flatMap((e) => e.photos);

/* ---------------------------------------------------------- statistiques --- */

function statistiquesVoyage() {
  const souvenirs = tousLesSouvenirs();
  const photos = photosDesEtapes();
  const lieux = [...new Set(etat.etapes.map((e) => e.lieu.trim()).filter(Boolean))];
  const signes = souvenirs.reduce((n, s) => n + s.texte.length, 0);
  const mots = souvenirs.reduce(
    (n, s) => n + (s.texte.trim() ? s.texte.trim().split(/\s+/).length : 0),
    0,
  );
  const duree = souvenirs.reduce((n, s) => n + (s.duree || 0), 0);
  const vocaux = souvenirs.filter((s) => s.audioNom).length;

  // Les jours se comptent sur les dates racontées par les étapes, pas sur les
  // dates de fichier : trois vocaux téléchargés le même soir peuvent couvrir
  // une semaine de voyage.
  const { premiere, derniere } = bornesDuVoyage();
  let jours = premiere ? 1 : 0;
  if (premiere && derniere && premiere !== derniere) {
    const ms = new Date(`${derniere}T00:00:00Z`) - new Date(`${premiere}T00:00:00Z`);
    jours = Math.round(ms / 86400000) + 1;
  }

  // Kilomètres, pays et villes : tirés des récits par l'analyse d'étape
  // (`voyage.js`). Avant elle, on ne sait pas.
  const tires = Voyage.chiffresDuVoyage(etapesPourMiseEnPage(() => ""));

  return {
    etapes: etat.etapes.length,
    jours,
    lieux: lieux.length,
    listeLieux: lieux,
    km: tires.km,
    pays: tires.pays,
    villes: tires.villes,
    analysees: tires.analysees,
    rencontres: etat.rencontres.length,
    listeRencontres: etat.rencontres,
    voyageurs: listeVoyageurs().length,
    vocaux,
    duree,
    photos: photos.length,
    signes,
    mots,
    aTranscrire: etat.vocauxAttente.filter((v) => v.etat !== "transcrit").length,
  };
}

function formatDuree(secondes) {
  if (!secondes) return "—";
  const min = Math.round(secondes / 60);
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)} h ${String(min % 60).padStart(2, "0")}`;
}

function rendreStats() {
  const bandeau = $("bandeau-stats");
  const s = statistiquesVoyage();
  bandeau.hidden = etat.etapes.length === 0;
  if (bandeau.hidden) return;

  const tuile = (valeur, etiquette, options = {}) =>
    h(
      "div",
      {
        class: `tuile${options.pleine ? " pleine" : ""}`,
        title: options.detail || "",
      },
      h("span", { class: "valeur" }, valeur),
      h("span", { class: "etiquette-tuile" }, etiquette),
    );

  remplir(
    bandeau,
    tuile(nombre(s.etapes), s.etapes > 1 ? "étapes" : "étape", { pleine: true }),
    tuile(nombre(s.jours), s.jours > 1 ? "jours" : "jour"),
    ...(() => {
      // Avant l'analyse des étapes, les récits n'ont pas encore dit où ils
      // vont ni comment : on l'écrit plutôt que d'afficher zéro.
      const attente = "Calculé à l'analyse des étapes (Générer le carnet, ou Générer la couverture).";
      const connu = s.analysees > 0;
      return [
        tuile(s.km === null ? "—" : nombre(s.km), "km parcourus", {
          detail: connu
            ? s.km === null
              ? "Aucun trajet raconté dans les récits analysés."
              : "Somme des trajets racontés : vol d'oiseau en avion et en bateau, 1,3 fois par la route ou le rail."
            : attente,
        }),
        tuile(connu ? nombre(s.pays.length) : "—", "pays", {
          detail: connu ? s.pays.join(", ") : attente,
        }),
        tuile(connu ? nombre(s.villes.length) : "—", s.villes.length > 1 ? "villes" : "ville", {
          detail: connu ? s.villes.join(", ") : attente,
        }),
      ];
    })(),
    tuile(nombre(s.rencontres), "rencontrées", {
      detail: s.listeRencontres.length
        ? s.listeRencontres.join(", ")
        : "Personne nommée dans les vocaux pour l'instant.",
    }),
    tuile(nombre(s.vocaux), "vocaux"),
    tuile(formatDuree(s.duree), "de voix"),
    tuile(nombre(s.photos), "photos"),
    tuile(nombre(s.mots), "mots"),
  );
}

function majStats() {
  const s = statistiquesVoyage();
  remplir(
    "stats",
    `${nombre(s.etapes)} étapes · ${nombre(s.mots)} mots`,
    s.aTranscrire > 0
      ? h("span", { class: "accent" }, ` · ${s.aTranscrire} vocaux à transcrire`)
      : null,
  );
}

/* ----------------------------------------------------------------- export --- */

function construireJson() {
  return JSON.stringify(
    {
      carnet: {
        titre: etat.carnet.titre,
        destination: etat.carnet.destination,
        date_debut: etat.carnet.dateDebut,
        date_fin: etat.carnet.dateFin,
        voyageurs: listeVoyageurs(),
        rencontres: etat.rencontres,
      },
      etapes: etat.etapes.map((e, i) => ({
        numero: i + 1,
        titre: e.titre,
        lieu: e.lieu,
        date_debut: e.dateDebut,
        date_fin: e.dateFin || e.dateDebut,
        souvenirs: e.souvenirs.map((s) => ({
          texte: s.texte,
          date: s.date,
          auteur: s.auteur,
          ...(s.audioNom ? { audio: s.audioNom } : {}),
          ...(s.duree ? { duree_secondes: Math.round(s.duree) } : {}),
        })),
        photos: e.photos.map((p) => ({
          nom_fichier: p.nomFichier,
          legende: p.legende,
          date: p.date,
          orientation: p.orientation,
          largeur: p.largeur,
          hauteur: p.hauteur,
          ...(etat.avecPhotos ? { image: p.data } : {}),
        })),
      })),
    },
    null,
    2,
  );
}

/** Petites icônes au trait, pour les boutons qui n'ont pas la place d'un mot. */
const TRACES = {
  sauvegarder: "M12 3v12m0 0 4-4m-4 4-4-4M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2",
  ouvrir: "M12 21V9m0 0 4 4m-4-4-4 4M4 7V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2",
  dupliquer: "M9 9h10v10a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V9Zm-2 6H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v2",
  monter: "m6 15 6-6 6 6",
  descendre: "m6 9 6 6 6-6",
  supprimer: "M4 7h16M10 11v6m4-6v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3",
  oeil: "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Zm10-3a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z",
  oeilBarre:
    "M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.2M6.6 6.6C3.9 8.3 2 12 2 12s3.5 7 10 7c1.8 0 3.4-.5 4.8-1.3M9.9 9.9a3 3 0 0 0 4.2 4.2",
};

function icone(nom) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "1.8");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  svg.setAttribute("aria-hidden", "true");
  const trace = document.createElementNS("http://www.w3.org/2000/svg", "path");
  trace.setAttribute("d", TRACES[nom]);
  svg.append(trace);
  return svg;
}

/**
 * Propose une vraie fenêtre « Enregistrer sous » quand le navigateur la
 * connaît, et retombe sur un téléchargement classique sinon. Chrome et Edge
 * ouvrent le sélecteur ; Firefox et Safari déposent dans les téléchargements.
 *
 * Rend `false` si la personne a annulé — pour ne pas annoncer un enregistrement
 * qui n'a pas eu lieu.
 */
async function enregistrerFichier(contenu, nom, type, description) {
  const extension = `.${nom.split(".").pop()}`;
  if (window.showSaveFilePicker) {
    let poignee;
    try {
      poignee = await window.showSaveFilePicker({
        suggestedName: nom,
        types: [{ description, accept: { [type]: [extension] } }],
      });
    } catch (erreur) {
      if (erreur.name === "AbortError") return false;
      poignee = null; // navigateur qui refuse le sélecteur : on retombe
    }
    if (poignee) {
      const flux = await poignee.createWritable();
      await flux.write(new Blob([contenu], { type }));
      await flux.close();
      return true;
    }
  }
  telecharger(contenu, nom, type);
  return true;
}

function telecharger(contenu, nom, type) {
  const blob = new Blob([contenu], { type });
  const url = URL.createObjectURL(blob);
  const lien = h("a", { href: url, download: nom });
  document.body.append(lien);
  lien.click();
  lien.remove();
  URL.revokeObjectURL(url);
}

const nomDeFichier = (extension) =>
  `carnet-${(etat.carnet.destination || "beta").toLowerCase().replace(/\s+/g, "-")}.${extension}`;

/* ------------------------------------------- génération du JSON et du PDF --- */

/**
 * Le bouton reste dans son état « en cours » jusqu'à ce que la fenêtre
 * d'enregistrement se soit ouverte et refermée : c'est le seul moment où l'on
 * sait que le fichier est bien parti.
 */
async function genererJson(bouton) {
  if (bouton.disabled) return;
  const libelle = bouton.textContent;
  bouton.disabled = true;
  bouton.textContent = "Génération en cours…";
  try {
    await preparerMiseEnPage((texte) => (bouton.textContent = texte.split("…")[0] + "…"));
    const json = construireJson();
    const enregistre = await enregistrerFichier(
      json,
      nomDeFichier("json"),
      "application/json",
      "JSON du carnet",
    );
    // On montre ce qui vient d'être écrit, plutôt que de laisser un doute.
    if (enregistre) {
      etat.montrerExport = true;
      rendreExport();
    }
  } catch (erreur) {
    etat.erreur = `L'enregistrement a échoué : ${erreur.message}`;
    rendreColonne();
  } finally {
    bouton.disabled = false;
    bouton.textContent = libelle;
  }
}

// La mise en page des étapes (pagination, photos, chapitres, doubles pages)
// vit dans `mise-en-page.js` : sans DOM ni réseau, elle se teste depuis le
// back-end. Ici ne restent que la collecte des données et l'envoi.

/**
 * Le lieu affiché dans le bandeau : celui de l'étape, complété par la
 * destination du carnet.
 *
 * Les deux se recoupent le plus souvent — une étape à « Paros, Grèce » dans un
 * carnet dont la destination est « Paros, Grèce » — et les coller bout à bout
 * écrivait « Paros, Grèce, Paros, Grèce » sur deux lignes dans l'encart. On
 * compare donc composante par composante, sans tenir compte de la casse ni des
 * accents, et on ne garde chaque nom qu'une fois.
 */
function lieuComplet(lieu, destination) {
  const normaliser = (t) =>
    t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
  const vus = new Set();
  return [lieu, destination]
    .filter(Boolean)
    .flatMap((valeur) => String(valeur).split(","))
    .map((part) => part.trim())
    .filter((part) => {
      if (!part) return false;
      const cle = normaliser(part);
      if (vus.has(cle)) return false;
      vus.add(cle);
      return true;
    })
    .join(", ");
}

const MOIS = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];

function dateLongue(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
  return m ? `${Number(m[3])} ${MOIS[Number(m[2]) - 1]} ${m[1]}` : "";
}

/**
 * Traduit l'état de l'atelier vers le contrat attendu par le template, décrit
 * par `MemoBook Generator/templates/travel-journal/data.json`. Conversion **mécanique** : elle
 * n'écrit pas à la place du voyageur, elle habille son texte.
 */
/** « 22 août 2026 – 5 septembre 2026 », tiré des étapes : le même sur la couverture et dans le carnet. */
function plageDates() {
  const dates = etat.etapes.flatMap((e) => [e.dateDebut, e.dateFin]).filter(Boolean).sort();
  const premiere = dates[0];
  const derniere = dates[dates.length - 1];
  return premiere && derniere && premiere !== derniere
    ? `${dateLongue(premiere)} – ${dateLongue(derniere)}`
    : dateLongue(premiere) || "";
}

/** Le sous-titre du carnet, sur la couverture intérieure comme sur la couverture imprimée. */
const SOUS_TITRE = "Un carnet de voyage raconté à l'oral";

/** La fiche Pumbo importée, ou celle du relié de 48 pages par défaut. */
const fichePumbo = () => etat.reglages.fichePumbo || Couverture.FICHE_DEFAUT;

/** La photo de couverture : celle que le voyageur a choisie pour la première, sinon la mieux notée. */
const photoDeCouverture = () => photoDuPlat("recto");

/** Une seule photo en couverture : en désigner une retire l'étoile des autres. */
function designerCouverture(photoId) {
  for (const p of [...etat.photosAttente, ...etat.etapes.flatMap((e) => e.photos)]) {
    p.couverture = p.id === photoId ? !p.couverture : false;
  }
  apresChangement();
  rendreCouverture();
}

/**
 * Les étapes telles que les lit `MiseEnPage.composerJours` : le récit d'un
 * tenant, les photos avec leur format, et l'analyse d'étape si elle a été faite
 * (`analyserEtapes`) et qu'elle correspond encore au contenu de l'étape.
 */
function etapesPourMiseEnPage(photoDe) {
  return etat.etapes.map((etape, index) => ({
    titre: etape.titre || `Étape ${index + 1}`,
    lieu: etape.lieu || "",
    destination: etat.carnet.destination || "",
    numero: String(index + 1).padStart(2, "0"),
    lieuComplet: lieuComplet(etape.lieu, etat.carnet.destination),
    dateLongue: dateLongue(etape.dateDebut),
    recit: recitDe(etape),
    photos: etape.photos
      .filter((p) => p.data)
      .map((p) => ({
        id: p.id,
        src: photoDe(p.data),
        format: p.largeur && p.hauteur ? p.largeur / p.hauteur : 0,
        largeur: p.largeur || 0,
        hauteur: p.hauteur || 0,
        groupe: Boolean(p.groupe),
        // L'étiquette écrite sous la photo par le voyageur.
        etiquette: p.legende || "",
        // Netteté et exposition mesurées dans le navigateur (`mesurerPhoto`) :
        // c'est d'elles que dépend l'ordre des photos écartées.
        mesure: p.mesure || null,
      }))
      .filter((p) => p.src),
    analyse: etape.analyse?.cle === cleAnalyse(etape) ? etape.analyse.resultat : null,
  }));
}

const recitDe = (etape) => etape.souvenirs.map((s) => s.texte.trim()).filter(Boolean).join(" ");

/**
 * Les pages du livre tel qu'il part chez Pumbo : celles du PDF **en version
 * imprimeur** — sans couverture ni quatrième, imprimées sur la couverture
 * rigide —, page blanche finale comprise. Compté sur ce PDF-là quel que soit
 * le réglage « Version imprimeur » : c'est lui que Pumbo relie.
 */
function pagesDuLivre() {
  if (!etat.etapes.length) return 0;
  return Couverture.pagesDuPdf(construirePayloadCarnet((data) => data, { imprimeur: true }));
}

/** La fiche de la couverture : les plats de la fiche Pumbo, le dos tiré du nombre de pages. */
const ficheCouverture = () => Couverture.ficheDuCarnet(fichePumbo(), pagesDuLivre());

/**
 * Les réglages de personnalisation du carnet, sous les noms du serveur
 * (`backend/src/services/bookSettings.ts`), qui applique les mêmes au PDF de
 * l'app :
 *
 * - **ratio photo / texte** : les cinq paliers. C'est `RatioPhotos`
 *   (`ratio-photos.js`, généré depuis `backend/src/services/photoRatio.ts`)
 *   qui recompose chaque étape — nombre de pages, layout, répartition des
 *   photos, hauteur des bandes. Le même module que l'app : un carnet composé
 *   ici et un carnet composé par l'app doivent tomber sur le même PDF ;
 * - **pointillés** coupés : `rules_enabled: false`, pas de réglure ;
 * - **décorations** à 0 : `decoration_quota: 0`, ni tracé pointillé ni
 *   sticker (le scotch des photos reste) ;
 * - **zones libres** : sans effet depuis le 15/10/2026 — les pages réglées de
 *   fin de carnet sont retirées (`pages_libres: 0`) ;
 * - **quiz** (allumé par défaut) : le composeur en place environ un toutes les
 *   trois étapes (`placerQuiz`) ; coupé, aucun ;
 * - **nombre de pages cible** (vide par défaut) : le carnet entier — colophon et
 *   pages libres compris — y tient à ± 5 pages, par ses seules planches de
 *   photos (`recalerSurLaCible`) ; hors d'atteinte, le journal le dit.
 */
/**
 * Le nombre de pages du carnet, comme l'app iOS (`BookCustomisation.swift`,
 * `pageCount(forTripDays:)`, et `backend/src/services/pageTarget.ts`) : le
 * format standard vaut la durée du voyage arrondie à la dizaine, entre 30 et
 * 180 pages ; sans date de retour, 60. Compact en fait les deux tiers,
 * détaillé les quatre tiers — 40 / 60 / 80 sans date de fin.
 */
const FORMATS_PAGES = {
  compact: { libelle: "Compact", facteur: 2 / 3 },
  standard: { libelle: "Standard", facteur: 1 },
  detaille: { libelle: "Détaillé", facteur: 4 / 3 },
};
const PAGES_PERSO = { min: 30, max: 180, pas: 10, defaut: 60 };

const arrondiDizaine = (v) => Math.round(v / 10) * 10;

/** La durée du voyage en jours, bornes comprises ; `null` sans date de départ ou de retour. */
function joursDuVoyage(c = etat.carnet) {
  if (!c.dateDebut || !c.dateFin) return null;
  const debut = Date.parse(`${c.dateDebut}T00:00:00Z`);
  const fin = Date.parse(`${c.dateFin}T00:00:00Z`);
  if (!Number.isFinite(debut) || !Number.isFinite(fin)) return null;
  return Math.max(1, Math.round((fin - debut) / 86400000) + 1);
}

function pagesStandard(jours) {
  if (!jours || jours <= 0) return 60;
  return Math.min(Math.max(arrondiDizaine(jours), 30), 180);
}

function pagesDuFormat(c = etat.carnet, format = c.formatPages || "standard") {
  if (format === "perso") {
    const n = Number(c.pagesCible);
    return n > 0 ? Math.round(n) : PAGES_PERSO.defaut;
  }
  const standard = pagesStandard(joursDuVoyage(c));
  return arrondiDizaine(standard * (FORMATS_PAGES[format] || FORMATS_PAGES.standard).facteur);
}

/**
 * Un avancement enregistré avant les formats n'avait qu'un `pagesCible`, et
 * souvent un 16 venu du minimum de l'ancien champ, pas d'un choix : sous le
 * minimum de l'app (30), on repart du format standard.
 */
function migrerFormatPages(carnet) {
  if (carnet.formatPages) return carnet;
  const n = Number(carnet.pagesCible);
  return n >= PAGES_PERSO.min
    ? { ...carnet, formatPages: "perso", pagesCible: Math.round(n) }
    : { ...carnet, formatPages: "standard", pagesCible: null };
}

function reglagesDuCarnet() {
  const c = etat.carnet;
  const ratio = Number(c.ratioPhotos);
  const quota = Number(c.decorations);
  return {
    funFactsEnabled: c.funFacts !== false,
    quizEnabled: c.quiz !== false,
    photoTextRatio: Number.isFinite(ratio) ? ratio : 50,
    rulesEnabled: c.reglure !== false,
    decorationQuota: Number.isFinite(quota) ? quota : 2,
    freeZonesEnabled: c.zonesLibres !== false,
    targetPageCount: pagesDuFormat(c),
  };
}

/** Les pages libres de fin de carnet : aucune depuis le 15/10/2026 (`bookSettings.ts`). */
const PAGES_LIBRES_FIN = 0;

/** Le template de la version imprimeur, s'il est renseigné. */
function templateImprimeur() {
  return (etat.reglages.templateApitemplateImprimeur || "").trim();
}

function construirePayloadCarnet(photoDe = (data) => data, { imprimeur = Boolean(etat.reglages.versionImprimeur) } = {}) {
  const reglages = reglagesDuCarnet();
  // Ratio à 0 % : les photos sortent avant la composition, le récit prend leur place.
  const etapes = etapesPourMiseEnPage(photoDe).map((e) => (reglages.photoTextRatio > 0 ? e : { ...e, photos: [] }));
  // Le colophon, puis l'introduction s'il y en a une (l'atelier n'en écrit pas).
  const intro = "";
  const avant = 1 + (intro ? 1 : 0);
  const libresAvant = avant % 2 === 0 ? 1 : 0;
  // Le bilan de ratio de chaque étape, rempli par `appliquerRatio` et lu par
  // l'inspecteur de mise en page.
  const plansDeRatio = [];
  // La même photo que sur la couverture imprimée : le carnet s'ouvre sur ce
  // qu'on a vu en le prenant en main.
  const couverture = photoDeCouverture();

  const payload = {
    render_profile: "preview",
    // Version imprimeur : le relié a sa couverture à part (`couverture.js`), et
    // s'imprime en feuillets — un nombre de pages pair.
    ...(imprimeur ? { sans_couvertures: true } : {}),
    // Et avec 3 mm de fond perdu, dès qu'un template imprimeur (feuille de
    // 154 × 216 mm) est renseigné : sur le template A5, la page ne tiendrait
    // plus dans sa feuille.
    ...(imprimeur && templateImprimeur() ? { fond_perdu: true } : {}),
    book_title: etat.carnet.titre || "Carnet de voyage",
    book_subtitle: SOUS_TITRE,
    authors: listeVoyageurs().join(" et "),
    date_range: plageDates(),
    cover_photo: couverture ? photoDe(couverture.data) : "",
    brand_name: "MemoBook",
    year: String(new Date().getFullYear()),
    footer_tagline: "Racontez. Revivez. Partagez.",
    intro_text: intro,
    // Une étape commence toujours sur une page de gauche : le colophon (page 1,
    // à droite) et l'introduction doivent faire un nombre impair de pages.
    pages_libres_avant: libresAvant,
    // Les pages d'étape : récit réparti sur ses pages, photos auprès du passage
    // qu'elles illustrent, chapitres sur une carte, doubles pages variées.
    // Voir `mise-en-page.js` et LAYOUT_KB.
    rules_enabled: reglages.rulesEnabled,
    decoration_quota: reglages.decorationQuota,
    // Plus de pages réglées pour écrire à la main en fin de carnet (Hugo,
    // 15/10/2026).
    pages_libres: PAGES_LIBRES_FIN,
    days: MiseEnPage.composerJours(etapes, {
      contours: etat.contoursCarte,
      dessinerCarte: etat.contoursCarte ? dessinerCarteChapitre : null,
      // Le colophon est la page 1 du livre imprimé : la première page d'étape
      // est à gauche.
      pagesAvant: avant + libresAvant,
      funFacts: reglages.funFactsEnabled,
      quiz: reglages.quizEnabled,
      stickers: etat.stickers || [],
      decorations: reglages.decorationQuota,
      ratio: RatioPhotos.normaliserRatio(reglages.photoTextRatio),
      budgetPhotos: budgetDuRatio(reglages, plansDeRatio),
      // Les pages hors des étapes comptent dans la cible : colophon,
      // introduction, page libre d'avant, pages libres de fin.
      ...(reglages.targetPageCount
        ? {
            pagesCible: reglages.targetPageCount,
            pagesFixes: avant + libresAvant + PAGES_LIBRES_FIN,
          }
        : {}),
      journal: (texte) => {
        debugCarnet(texte);
        // Pourquoi un fun fact manque, quelles photos sont écartées : dans le
        // journal visible, une fois — le payload se recompose souvent (nombre
        // de pages, couverture).
        if (/^(fun facts non imprimés|quiz :|photo\(s\) écartée\(s\)|stickers :|pages cible :)/.test(texte) && !etat.rapportsCarnet.has(texte)) {
          etat.rapportsCarnet.add(texte);
          noter(texte);
        }
      },
    }),
    back_cover: {
      closing_text: "À suivre.",
      // Pas de `closing_subtext` : « Carnet composé avec MemoBook Generator,
      // N rencontres en chemin » parlait de l'outil interne et d'un mot de
      // l'atelier, pas du voyage. La quatrième garde « À suivre. » et l'adresse.
      cta: "memobook.fr",
      logo_url: "",
    },
  };
  if (imprimeur && Couverture.pagesDuPdf(payload) % 2 === 1) payload.page_blanche_finale = true;
  // Le bilan par étape reste accessible à l'inspecteur après la construction.
  etat.ratioParEtape = plansDeRatio;
  return payload;
}

/**
 * Le nombre de photos que le ratio texte / photo demande pour chaque étape.
 *
 * Le composeur compose, le ratio dit combien de photos (Hugo, 13/10/2026) :
 * `composerJours` garde, étape par étape, les `photosRequired(...).photos`
 * meilleures photos et les met en page avec ses propres règles — étapes
 * paires, photos en fin d'étape, planches, décors. L'app fait exactement la
 * même chose (`backend/src/services/bookComposer.ts`).
 *
 * `RatioPhotos` est **généré** depuis `backend/src/services/photoRatio.ts`
 * (`npm run ratio:build`) : c'est le même code que celui qui annonce au
 * voyageur, dans le chat de l'app, le nombre de photos qu'il lui faut. Les
 * plans calculés vont à l'inspecteur (`plans`).
 */
function budgetDuRatio(reglages, plans) {
  const ratio = RatioPhotos.normaliserRatio(reglages.photoTextRatio);
  return (etape) => {
    const plan = RatioPhotos.photosRequired({ body_html: MiseEnPage.paragraphesEnHtml(MiseEnPage.enParagraphes(etape.recit)) }, ratio, "a5", {
      funFacts: reglages.funFactsEnabled,
      decorations: reglages.decorationQuota > 0,
    });
    plans.push(plan);
    debugCarnet(
      `ratio étape ${plans.length} : cible ${plan.ratioCible} %, ${plan.photos} photo(s) demandée(s) — ${plan.raison}`,
    );
    return plan.photos;
  };
}

/* ------------------------------------------------ envoi vers APITemplate --- */

/**
 * Plafonds de charge d'APITemplate, requête ET réponse comprises
 * (README officiel du client JavaScript, section « Regional API endpoints ») :
 *   rest(-de|-us).apitemplate.io      → 1 Mo, 100 s de délai
 *   rest-alt(-de|-us).apitemplate.io  → 6 Mo, 30 s de délai
 * Au-delà, le serveur coupe sans en-têtes CORS : le navigateur ne voit qu'un
 * « Failed to fetch ». C'est ce qui faisait échouer le bouton en silence dès
 * qu'une étape portait quelques photos en base64 pleine résolution.
 * On garde une marge pour les en-têtes et l'enveloppe JSON.
 */
const PLAFOND_STANDARD = 0.9 * 1024 * 1024;
const PLAFOND_ALTERNATIF = 5.5 * 1024 * 1024;

/**
 * Paliers de compression, du plus fin au plus léger. `cote` est le plus grand
 * côté en pixels. Le template imprime en A5 et le rendu est en profil
 * « preview » : 1600 px suffisent largement, 500 px restent lisibles.
 */
const PALIERS_PHOTOS = [
  { cote: 1600, qualite: 0.8 },
  { cote: 1200, qualite: 0.72 },
  { cote: 900, qualite: 0.66 },
  { cote: 700, qualite: 0.6 },
  { cote: 500, qualite: 0.55 },
];

/** En dessous de ce palier, on préfère l'endpoint alternatif (6 Mo) pour garder de la qualité. */
const COTE_MINI_STANDARD = 900;

/** Cache : une photo n'est recompressée qu'une fois par palier, même si on regénère. */
const cachePhotos = new Map();

const debugCarnet = (...args) => console.debug("[carnet]", ...args);

/** Transforme `rest-de.apitemplate.io/v2` en `rest-alt-de.apitemplate.io/v2`. */
function baseAlternative(base) {
  const url = new URL(base);
  if (!url.hostname.includes("-alt")) {
    url.hostname = url.hostname.replace(/^rest(-|\.)/, (_, sep) => (sep === "." ? "rest-alt." : "rest-alt-"));
  }
  return url.toString().replace(/\/$/, "");
}

/** Redimensionne et réencode une photo en JPEG. Renvoie une data URL. */
function compresserPhoto(dataUrl, { cote, qualite }) {
  const cle = `${cote}|${qualite}|${dataUrl.length}|${dataUrl.slice(-64)}`;
  if (cachePhotos.has(cle)) return Promise.resolve(cachePhotos.get(cle));
  return new Promise((resoudre) => {
    const img = new Image();
    img.onload = () => {
      const ratio = Math.min(1, cote / Math.max(img.naturalWidth, img.naturalHeight));
      const largeur = Math.max(1, Math.round(img.naturalWidth * ratio));
      const hauteur = Math.max(1, Math.round(img.naturalHeight * ratio));
      const toile = document.createElement("canvas");
      toile.width = largeur;
      toile.height = hauteur;
      const ctx = toile.getContext("2d");
      // Fond blanc : un PNG transparent passé en JPEG virerait au noir.
      ctx.fillStyle = "#fff";
      ctx.fillRect(0, 0, largeur, hauteur);
      ctx.drawImage(img, 0, 0, largeur, hauteur);
      const sortie = toile.toDataURL("image/jpeg", qualite);
      cachePhotos.set(cle, sortie);
      resoudre(sortie);
    };
    // Une image illisible ne bloque pas le carnet : elle est simplement omise.
    img.onerror = () => {
      debugCarnet("photo illisible, ignorée");
      resoudre("");
    };
    img.src = dataUrl;
  });
}

/** Compresse toutes les photos des étapes à un palier donné. Map data d'origine → data compressée. */
async function photosAuPalier(palier) {
  const originales = [
    ...new Set(etat.etapes.flatMap((e) => e.photos.map((p) => p.data)).filter(Boolean)),
  ];
  const table = new Map();
  for (const data of originales) table.set(data, await compresserPhoto(data, palier));
  return table;
}

/**
 * Cherche la meilleure qualité qui passe. Deux passes :
 * 1. un palier ≥ 900 px qui tient dans 1 Mo → endpoint standard (délai de 100 s) ;
 * 2. sinon le meilleur palier qui tient dans 5,5 Mo → endpoint alternatif (30 s).
 */
async function preparerEnvoi() {
  const baseStandard = (etat.reglages.baseApitemplate || "https://rest-de.apitemplate.io/v2").replace(/\/$/, "");
  const sansPhoto = !etat.etapes.some((e) => e.photos.some((p) => p.data));

  if (sansPhoto) {
    const payload = construirePayloadCarnet();
    const poids = new Blob([JSON.stringify(payload)]).size;
    debugCarnet("aucune photo, poids", poids, "octets");
    return { payload, poids, base: poids <= PLAFOND_STANDARD ? baseStandard : baseAlternative(baseStandard), palier: null };
  }

  const essais = [];
  for (const palier of PALIERS_PHOTOS) {
    const table = await photosAuPalier(palier);
    const payload = construirePayloadCarnet((data) => table.get(data) || "");
    const poids = new Blob([JSON.stringify(payload)]).size;
    essais.push({ palier, payload, poids });
    debugCarnet(`palier ${palier.cote}px q${palier.qualite} → ${(poids / 1024).toFixed(0)} Ko`);
    if (poids <= PLAFOND_STANDARD && palier.cote >= COTE_MINI_STANDARD) {
      return { payload, poids, base: baseStandard, palier };
    }
  }

  const alternatif = essais.find((e) => e.poids <= PLAFOND_ALTERNATIF);
  if (alternatif) return { ...alternatif, base: baseAlternative(baseStandard) };

  const plusLeger = essais[essais.length - 1];
  throw new Error(
    `même compressées, les photos pèsent ${(plusLeger.poids / 1024 / 1024).toFixed(1)} Mo ` +
      "et APITemplate refuse au-delà de 6 Mo. Retire des photos de quelques étapes et relance.",
  );
}

/** Traduit les erreurs réseau opaques en quelque chose d'actionnable. */
function messageLisible(erreur, statut) {
  const brut = String(erreur?.message || erreur || "");
  if (brut.startsWith("synchronisation du gabarit")) return brut;
  if (/failed to fetch|networkerror|load failed/i.test(brut)) {
    return "APITemplate n'a pas répondu (charge trop lourde, délai dépassé ou coupure réseau). Relance ; si ça persiste, retire des photos.";
  }
  if (statut === 401) return "clé APITemplate refusée. Vérifie qu'elle correspond bien au compte de la région choisie (DE par défaut).";
  if (statut === 403) return "la clé est valide mais n'a pas accès à ce template.";
  if (statut === 413) return "charge trop lourde pour APITemplate. Retire des photos et relance.";
  if (statut === 429) return "trop de demandes d'affilée. Attends dix secondes et relance.";
  return brut;
}

/**
 * Envoie le carnet à APITemplate et ouvre le PDF.
 *
 * Beta assumée : la conversion vers le contrat du template est mécanique. Le
 * pipeline du back-end reste la voie sérieuse ; ceci sert à voir tout de
 * suite à quoi le carnet ressemble.
 *
 * Trois corrections par rapport à la première version :
 * - les erreurs s'affichent sous le bouton (avant, elles n'apparaissaient que
 *   dans la carte « Étapes groupées », cachée quand il n'y a pas d'étape) ;
 * - les photos sont compressées pour tenir dans le plafond d'APITemplate ;
 * - l'onglet du PDF est ouvert au clic, avant tout `await`, sinon Safari et
 *   Chrome le bloquent comme une popup.
 */
/* ------------------------------------------------- couverture du livre --- */

/*
 * Le panneau « Couverture du livre » : trois photos proposées pour chaque plat,
 * le choix d'une autre avec son contrôle qualité, les textes et les chiffres
 * du voyage, puis l'aperçu à imprimer en PDF et le fichier InDesign.
 * Voir `couverture.js` et LAYOUT_KB § « Couverture imprimée (Pumbo) ».
 */

const DRAPEAU_PLAT = { recto: "couverture", verso: "couvertureVerso" };

/** Les photos du carnet telles que les note `Couverture.evaluerPhoto` : format, mesure, analyse. */
function photosPourCouverture() {
  return etat.etapes.flatMap((etape) => {
    const analyse = etape.analyse?.cle === cleAnalyse(etape) ? etape.analyse.resultat : null;
    const parId = new Map((analyse?.photos || []).map((p) => [String(p.id), p]));
    return etape.photos
      .filter((p) => p.data)
      .map((p) => ({
        id: p.id,
        data: p.data,
        largeur: p.largeur,
        hauteur: p.hauteur,
        groupe: Boolean(p.groupe),
        mesure: p.mesure || null,
        analyse: parId.get(String(p.id)) || null,
      }));
  });
}

const propositionsCouverture = () => Couverture.proposerPhotos(photosPourCouverture(), { fiche: fichePumbo() });

/** La photo d'un plat : celle que le voyageur a choisie, sinon la première proposée. */
function photoDuPlat(plat) {
  const toutes = photosDesEtapes().filter((p) => p.data);
  const choisie = toutes.find((p) => p[DRAPEAU_PLAT[plat]]);
  if (choisie) return choisie;
  const propositions = propositionsCouverture();
  const proposee = propositions[plat][0] || (plat === "recto" ? propositions.meilleure : null);
  return proposee ? toutes.find((p) => p.id === proposee.photo.id) || null : null;
}

function choisirPhotoDuPlat(plat, photoId) {
  for (const p of [...etat.photosAttente, ...photosDesEtapes()]) p[DRAPEAU_PLAT[plat]] = p.id === photoId;
  etat.couverture.autre[plat] = false;
  apresChangement();
  rendreCouverture();
}

/**
 * Ce que l'atelier mesure lui-même sur une photo, sur une vignette de 512 px :
 * la netteté (variance du laplacien), la luminance moyenne, et la part de
 * pixels brûlés ou bouchés. Gardé sur la photo : la mesure ne change pas.
 */
async function mesurerPhoto(photo) {
  if (photo.mesure || !photo.data) return;
  const img = new Image();
  img.src = photo.data;
  await img.decode();
  const k = Math.min(1, 512 / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.max(3, Math.round(img.naturalWidth * k));
  const h = Math.max(3, Math.round(img.naturalHeight * k));
  const toile = document.createElement("canvas");
  toile.width = w;
  toile.height = h;
  const ctx = toile.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, w, h);
  const d = ctx.getImageData(0, 0, w, h).data;
  const g = new Float32Array(w * h);
  let somme = 0;
  let extremes = 0;
  for (let i = 0; i < w * h; i += 1) {
    g[i] = 0.299 * d[i * 4] + 0.587 * d[i * 4 + 1] + 0.114 * d[i * 4 + 2];
    somme += g[i];
    if (g[i] > 250 || g[i] < 5) extremes += 1;
  }
  let s = 0;
  let s2 = 0;
  let n = 0;
  for (let y = 1; y < h - 1; y += 1) {
    for (let x = 1; x < w - 1; x += 1) {
      const i = y * w + x;
      const l = 4 * g[i] - g[i - 1] - g[i + 1] - g[i - w] - g[i + w];
      s += l;
      s2 += l * l;
      n += 1;
    }
  }
  photo.mesure = {
    nettete: Math.round(s2 / n - (s / n) ** 2),
    luminance: Math.round(somme / (w * h)),
    ecretage: Math.round((extremes / (w * h)) * 100) / 100,
  };
}

/** Les chiffres du voyage : les jours comptés sur les dates, le reste tiré des récits analysés. */
function chiffresDuVoyage() {
  const chiffres = Voyage.chiffresDuVoyage(etapesPourMiseEnPage(() => ""));
  return { ...chiffres, jours: statistiquesVoyage().jours };
}

/** Les contours de la carte de quatrième : le détail chargé pour elle, à défaut ceux du monde. */
function contoursQuatrieme() {
  return etat.contoursDetail && Object.keys(etat.contoursDetail).length ? etat.contoursDetail : etat.contoursCarte;
}

/** Les villes (ou les îles) où le voyage a séjourné : ce que la carte de quatrième montre, et compte. */
function lieuxQuatrieme() {
  return Couverture.lieuxDeQuatrieme(Voyage.lieuxDeSejour(etapesPourMiseEnPage(() => "")), contoursQuatrieme());
}

/** Les chiffres de la quatrième : les lieux comptés sont ceux de sa carte. */
function chiffresQuatrieme() {
  return Couverture.chiffresQuatrieme({ ...chiffresDuVoyage(), sejours: lieuxQuatrieme() });
}

/** Les textes de la couverture : ceux que le voyageur a repris, sinon ceux tirés du carnet. */
function textesCouverture() {
  const { premiere, derniere } = bornesDuVoyage();
  const defaut = Couverture.textesParDefaut({
    destination: etat.carnet.destination,
    titre: etat.carnet.titre,
    voyageurs: listeVoyageurs(),
    debut: premiere,
    fin: derniere,
  });
  const repris = etat.couverture.textes || {};
  return {
    titre: repris.titre ?? defaut.titre,
    voyageurs: repris.voyageurs ?? defaut.voyageurs,
    dates: repris.dates ?? defaut.dates,
    defaut,
  };
}

/**
 * Le logo en PNG haute définition : InDesign place mal le SVG selon les
 * versions. `couleur` : une autre teinte que le vert de la marque — le style
 * Élégant le veut en beige foncé.
 */
async function logoEnPng(couleur = null) {
  if (couleur) {
    etat.logosPng ??= {};
    if (etat.logosPng[couleur]) return etat.logosPng[couleur];
    const svg = (await (await fetch("./logo-memobook.svg")).text()).replace(/#28654b/gi, couleur);
    etat.logosPng[couleur] = await svgEnPng(svg);
    return etat.logosPng[couleur];
  }
  if (etat.logoPng) return etat.logoPng;
  etat.logoPng = await svgEnPng(await (await fetch("./logo-memobook.svg")).text());
  return etat.logoPng;
}

async function svgEnPng(svg, largeur = 1200) {
  const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    const hauteur = Math.round((largeur * (img.naturalHeight || 1)) / (img.naturalWidth || 1));
    const toile = document.createElement("canvas");
    toile.width = largeur;
    toile.height = hauteur;
    toile.getContext("2d").drawImage(img, 0, 0, largeur, hauteur);
    return { data: toile.toDataURL("image/png"), px: [largeur, hauteur] };
  } finally {
    URL.revokeObjectURL(url);
  }
}

const extensionDe = (dataUrl) => (/^data:image\/png/.test(dataUrl) ? "png" : "jpg");

/** Le voyage tel que le lisent les textes de couverture. */
function voyagePourCouverture() {
  const { premiere, derniere } = bornesDuVoyage();
  return {
    destination: etat.carnet.destination,
    titre: etat.carnet.titre,
    voyageurs: listeVoyageurs(),
    debut: premiere,
    fin: derniere,
    // Le code ISO du pays où le voyage séjourne le plus : le titre d'Aquarelle
    // et les légendes des timbres du Travel book en tirent son nom.
    pays: paysDuVoyage(),
    // Les étapes : les paragraphes par défaut du style Aquarelle en partent.
    etapes: etat.etapes.map((e) => ({ titre: e.titre, lieu: e.lieu })),
  };
}

/**
 * Les textes d'un style : ceux tirés du carnet, puis ceux que l'IA a rédigés
 * ou que le voyageur a repris (`etat.couverture.textesStyle`). Le dos garde
 * les trois textes du style par défaut — titre, voyageurs, dates.
 */
function textesDuStyle(style) {
  const base = textesCouverture();
  const defaut = CouvertureStyles.textesParDefaut(style, voyagePourCouverture());
  return {
    ...defaut,
    dosTitre: base.titre,
    dosVoyageurs: base.voyageurs,
    dosDates: base.dates,
    ...(etat.couverture.textesStyle[style] || {}),
    defaut,
  };
}

/**
 * La couleur du logo d'un style, quand ce n'est pas le vert de la marque :
 * beige foncé pour Élégant et Aquarelle, la teinte des textes de la quatrième
 * pour Photo-dessin.
 */
function couleurDuLogo(style) {
  if (style === "elegant" || style === "watercolor") return Couverture.COULEURS.beigeFonce.hex;
  if (style === "photo-drawing") {
    const c = couleursPhotoDessin();
    return Couverture.COULEURS[CouvertureStyles.couleursPhotoDessin(c?.dominante, c?.luminance).ecriture].hex;
  }
  return null;
}

/** Les couleurs de la photo de Photo-dessin, si elles sont déjà mesurées. */
function couleursPhotoDessin() {
  const photo = photoAvecVoyageurs();
  return (photo && etat.couverture.photosDessin?.[photo.id]?.couleurs) || null;
}

/** Le logo du style, dans sa couleur (`couleurDuLogo`). */
function logoDuStyle(style) {
  const couleur = couleurDuLogo(style);
  const png = couleur ? etat.logosPng?.[couleur] : etat.logoPng;
  return png
    ? { fichier: `Liens/logo-memobook${couleur ? `-${couleur.slice(1)}` : ""}.png`, src: png.data, px: png.px }
    : { fichier: "Liens/logo-memobook.png", src: "./logo-memobook.svg", px: [160, 160] };
}

/**
 * Faute de photo qui passe le contrôle qualité pour la quatrième : la plus
 * grande photo en largeur du carnet, autre que celle de la première. Le
 * contrôle qualité s'affiche quand même dans le panneau.
 */
function photoDeRepli(recto) {
  return (
    photosDesEtapes()
      .filter((p) => p.data && p.id !== recto?.id && p.largeur >= p.hauteur)
      .sort((a, b) => b.largeur * b.hauteur - a.largeur * a.hauteur)[0] || null
  );
}

/** Une photo de plat, prête pour la maquette. */
function photoPourMaquette(photo, nom, focus) {
  return photo
    ? { fichier: `Liens/${nom}.${extensionDe(photo.data)}`, src: photo.data, px: [photo.largeur, photo.hauteur], focus }
    : null;
}

/** La maquette de la couverture, dans le style choisi. */
function maquetteCouverture() {
  const fiche = ficheCouverture();
  const style = etat.couverture.style;
  // Les villes (ou les îles) où le voyage a séjourné, pas chaque site visité.
  const lieux = lieuxQuatrieme();
  const detail = contoursQuatrieme();
  const recto = style === "photo-drawing" ? photoAvecVoyageurs() : photoDuPlat("recto");
  const photoDessin = style === "photo-drawing" && recto ? etat.couverture.photosDessin?.[recto.id] || {} : {};
  return CouvertureStyles.maquette(style, {
    fiche,
    textes: style === "default" ? textesCouverture() : textesDuStyle(style),
    recto: photoPourMaquette(recto, "recto", style === "default" ? [0.5, 0.35] : style === "photo-drawing" ? null : [0.5, 0.45]),
    verso: photoPourMaquette(photoDuPlat("verso") || photoDeRepli(recto), "verso", [0.5, 0.5]),
    dessins: etat.dessinsCouverture || [],
    images: imagesCouverture(style),
    contour: photoDessin.trace || null,
    couleurPhoto: photoDessin.couleurs?.dominante || null,
    luminancePhoto: photoDessin.couleurs?.luminance ?? 0.35,
    chiffres: chiffresQuatrieme(),
    carte: lieux.length && detail ? { lieux, detail } : null,
    logo: logoDuStyle(style),
    motif: etat.motifPng ? { fichier: "Liens/motif-memobook-beige.png", src: etat.motifPng.data, px: etat.motifPng.px } : null,
  });
}

/**
 * Le motif M de MemoBook, en beige foncé, tourné d'un quart de tour comme sur
 * la quatrième d'Aquarelle (« MemoBook — Product », `3792:5773`), en PNG haute
 * définition pour InDesign. La maquette lui donne ses 20 %.
 */
async function motifEnPng() {
  if (etat.motifPng) return etat.motifPng;
  const svg = (await (await fetch("./motif-memobook.svg")).text()).replace(/#28654b/gi, Couverture.COULEURS.beigeFonce.hex);
  etat.motifPng = await svgEnPng(svg, 2400);
  return etat.motifPng;
}

/**
 * Les trois dessins du style Dessin : ceux de la bibliothèque que les récits
 * du voyage appellent, complétés par des dessins de voyage — chargés en
 * données pour partir dans le dossier InDesign.
 */
async function preparerDessinsCouverture() {
  await chargerStickers();
  const etapes = etapesPourMiseEnPage(() => "");
  const voyage = {
    titre: etat.carnet.titre,
    lieu: etat.carnet.destination,
    recit: etapes.map((e) => e.recit).join(" "),
    analyse: { photos: etapes.flatMap((e) => e.analyse?.photos || []) },
  };
  const appeles = MiseEnPage.stickersDe(voyage, etat.stickers || []);
  const choisis = CouvertureStyles.dessinsDuVoyage(etat.stickers || [], appeles);
  etat.dessinsCouverture = await Promise.all(
    choisis.map(async (d) => {
      const blob = await (await fetch(d.url)).blob();
      const data = await new Promise((resolu, rejete) => {
        const lecteur = new FileReader();
        lecteur.onload = () => resolu(lecteur.result);
        lecteur.onerror = () => rejete(lecteur.error);
        lecteur.readAsDataURL(blob);
      });
      return { fichier: `Liens/${d.fichier}`, src: data, px: [d.largeur, d.hauteur], famille: d.famille };
    }),
  );
}

/**
 * Les textes du style, rédigés par l'IA d'après les récits
 * (`CouvertureStyles.consigneTextes`), avec le modèle et la clé de l'analyse
 * des étapes. Le voyageur les reprend ensuite à la main.
 */
async function redigerTextesCouverture(style) {
  const etapes = etapesPourMiseEnPage(() => "");
  const voyage = {
    ...voyagePourCouverture(),
    voyageurs: listeVoyageurs().join(", "),
    dates: textesCouverture().dates,
    etapes: etapes.map((e) => ({ titre: e.titre, lieu: e.lieu, extrait: e.recit })),
  };
  const consigne = CouvertureStyles.consigneTextes(style, voyage);
  if (!consigne) return;
  etat.couverture.statut = "Rédaction des textes de la couverture…";
  rendreCouverture();
  try {
    const reponse = await appelAnalyse({
      fournisseur: etat.reglages.fournisseurDecoupage,
      modele: etat.reglages.modeleDecoupage,
      cleOpenai: etat.reglages.cleOpenai,
      cleAnthropic: etat.reglages.cleAnthropic,
      consigne,
      images: [],
    });
    etat.couverture.textesStyle = {
      ...etat.couverture.textesStyle,
      [style]: { ...(etat.couverture.textesStyle[style] || {}), ...CouvertureStyles.lireTextes(style, reponse) },
    };
    etat.couverture.statut = "";
  } catch (erreur) {
    etat.couverture.statut = `Rédaction impossible (${erreur.message}) : les textes tirés du carnet restent en place.`;
    debugCarnet("rédaction des textes de couverture impossible", erreur);
  }
  apresChangement();
  rendreCouverture();
}

/* ------------------------------------------ couverture : illustrations --- */

/** Le serveur relaie en local ; en ligne la page appelle l'API elle-même. */
async function appelImage(corps) {
  if (etat.mode === "navigateur") return MoteurNavigateur.image(corps);
  return appelJson("/api/image", corps);
}

/**
 * Une image (data URL ou adresse) en PNG data URL de `max` px au plus côté,
 * avec ses dimensions. `rogner` : la part à garder, `[x0, y0, x1, y1]` en
 * fractions de l'image.
 */
async function imageEnPng(source, max = 1024, rogner = null) {
  const img = new Image();
  img.crossOrigin = "anonymous";
  img.src = source;
  await img.decode();
  const [x0, y0, x1, y1] = rogner || [0, 0, 1, 1];
  const sl = img.naturalWidth * (x1 - x0);
  const sh = img.naturalHeight * (y1 - y0);
  const k = Math.min(1, max / Math.max(sl, sh));
  const toile = document.createElement("canvas");
  toile.width = Math.max(1, Math.round(sl * k));
  toile.height = Math.max(1, Math.round(sh * k));
  toile.getContext("2d").drawImage(img, img.naturalWidth * x0, img.naturalHeight * y0, sl, sh, 0, 0, toile.width, toile.height);
  return { data: toile.toDataURL("image/png"), px: [toile.width, toile.height] };
}

/**
 * Retire d'une illustration générée le fond que le modèle a peint autour du
 * sujet (`CouvertureStyles.detourerFond`) : sur Assouline, il laissait un
 * cadre fin autour de l'illustration. Renvoie la nouvelle data URL.
 */
async function detourerIllustration(source) {
  const img = new Image();
  img.src = source;
  await img.decode();
  const toile = document.createElement("canvas");
  toile.width = img.naturalWidth;
  toile.height = img.naturalHeight;
  const ctx = toile.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0);
  const pixels = ctx.getImageData(0, 0, toile.width, toile.height);
  const part = CouvertureStyles.detourerFond(pixels.data, toile.width, toile.height);
  if (!part) return source;
  ctx.putImageData(pixels, 0, 0);
  debugCarnet(`fond retiré : ${Math.round(part * 100)} % de l'illustration`);
  return toile.toDataURL("image/png");
}

/**
 * Le collage des six timbres du Travel book (`CouvertureStyles.svgTimbres`) :
 * les illustrations générées, mises en timbres avec leurs légendes, en PNG
 * pour la maquette et le dossier InDesign. Refait quand une illustration ou
 * une légende change.
 */
async function composerTimbres() {
  const plan = CouvertureStyles.planTimbres(voyagePourCouverture());
  const gardees = etat.couverture.images["travel-book"] || {};
  if (!plan.some((t) => gardees[t.cle])) return null;
  const signature = JSON.stringify(plan.map((t) => [t.cle, t.legende, gardees[t.cle]?.data?.length || 0]));
  if (etat.timbresComposes?.signature === signature) return etat.timbresComposes;
  etat.policeTimbres ??= await (async () => {
    const blob = await (await fetch("./fonts/couvertures/lilita-one-latin.woff2")).blob();
    const data = await new Promise((resolu, rejete) => {
      const lecteur = new FileReader();
      lecteur.onload = () => resolu(lecteur.result);
      lecteur.onerror = () => rejete(lecteur.error);
      lecteur.readAsDataURL(blob);
    });
    return `@font-face { font-family: "Lilita One"; src: url("${data}") format("woff2"); }`;
  })();
  const zone = CouvertureStyles.zoneDesTimbres(ficheCouverture());
  const illustrations = Object.fromEntries(plan.filter((t) => gardees[t.cle]).map((t) => [t.cle, { src: gardees[t.cle].data }]));
  const svg = CouvertureStyles.svgTimbres(plan, illustrations, { zone, police: etat.policeTimbres, pxParMm: 1 });
  // 24 px par mm : 600 dpi pour les légendes.
  const png = await svgEnPng(svg, Math.round(zone.l * 24));
  etat.timbresComposes = { signature, ...png };
  return etat.timbresComposes;
}

/**
 * La couleur dominante d'une image, sa luminance moyenne (0–1) et ses
 * dimensions. Les couleurs se mesurent sur une réduction de 48 px : les
 * pixels transparents ne comptent pas ; parmi les pixels colorés, la teinte
 * la plus représentée (douze secteurs) donne la couleur moyenne de son
 * secteur. Sans pixel coloré, la couleur moyenne.
 */
async function couleursDe(source) {
  const img = new Image();
  img.src = source;
  await img.decode();
  const k = Math.min(1, 48 / Math.max(img.naturalWidth, img.naturalHeight));
  const w = Math.max(1, Math.round(img.naturalWidth * k));
  const hh = Math.max(1, Math.round(img.naturalHeight * k));
  const toile = document.createElement("canvas");
  toile.width = w;
  toile.height = hh;
  const ctx = toile.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(img, 0, 0, w, hh);
  const { data } = ctx.getImageData(0, 0, w, hh);
  const secteurs = Array.from({ length: 12 }, () => ({ n: 0, r: 0, v: 0, b: 0 }));
  const tout = { n: 0, r: 0, v: 0, b: 0 };
  let lum = 0;
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 128) continue;
    const [r, v, b] = [data[i], data[i + 1], data[i + 2]];
    const max = Math.max(r, v, b);
    const min = Math.min(r, v, b);
    lum += (0.2126 * r + 0.7152 * v + 0.0722 * b) / 255;
    Object.assign(tout, { n: tout.n + 1, r: tout.r + r, v: tout.v + v, b: tout.b + b });
    if (max - min < 40 || max < 40) continue;
    const d = max - min;
    const t = max === r ? ((v - b) / d + 6) % 6 : max === v ? (b - r) / d + 2 : (r - v) / d + 4;
    const s = secteurs[Math.floor(t * 2) % 12];
    Object.assign(s, { n: s.n + 1, r: s.r + r, v: s.v + v, b: s.b + b });
  }
  const meilleur = secteurs.reduce((a, b) => (b.n > a.n ? b : a));
  const choix = meilleur.n >= Math.max(4, tout.n * 0.08) ? meilleur : tout;
  const hex = (c) => Math.round(c / Math.max(1, choix.n)).toString(16).padStart(2, "0");
  return {
    dominante: `#${hex(choix.r)}${hex(choix.v)}${hex(choix.b)}`,
    luminance: tout.n ? lum / tout.n : 0.5,
    px: [img.naturalWidth, img.naturalHeight],
  };
}

/** Une adresse en data URL (les couvertures de référence, servies par GitHub). */
async function enDataUrl(url) {
  const reponse = await fetch(url);
  if (!reponse.ok) throw new Error(`HTTP ${reponse.status} pour ${url}`);
  const blob = await reponse.blob();
  return new Promise((resolu, rejete) => {
    const lecteur = new FileReader();
    lecteur.onload = () => resolu(lecteur.result);
    lecteur.onerror = () => rejete(lecteur.error);
    lecteur.readAsDataURL(blob);
  });
}

/** Le pays du voyage : celui où il séjourne le plus souvent (code ISO à deux lettres). */
function paysDuVoyage() {
  const compte = new Map();
  for (const l of Voyage.lieuxDeSejour(etapesPourMiseEnPage(() => ""))) compte.set(l.pays, (compte.get(l.pays) || 0) + 1);
  return [...compte.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || null;
}

/**
 * La silhouette noire du pays du voyage, en PNG, d'après les contours de
 * carte (`assets/maps/countries.json`) : l'image d'entrée du tampon du style
 * Travel book. Les terres lointaines (territoires d'outre-mer) sont laissées
 * de côté : seuls comptent les contours proches du plus grand.
 */
async function silhouetteDuPays() {
  await chargerContoursCarte();
  const pays = paysDuVoyage();
  const contours = pays && etat.contoursCarte?.[pays]?.rings;
  if (!contours?.length) return null;
  const centre = (anneau) => anneau.reduce((s, [x, y]) => [s[0] + x / anneau.length, s[1] + y / anneau.length], [0, 0]);
  const principal = [...contours].sort((a, b) => b.length - a.length)[0];
  const [cx, cy] = centre(principal);
  const gardes = contours.filter((a) => {
    const [x, y] = centre(a);
    return Math.hypot(x - cx, y - cy) < 25;
  });
  const k = Math.cos((cy * Math.PI) / 180);
  const pts = gardes.flat();
  const [x0, x1] = [Math.min(...pts.map((p) => p[0] * k)), Math.max(...pts.map((p) => p[0] * k))];
  const [y0, y1] = [Math.min(...pts.map((p) => -p[1])), Math.max(...pts.map((p) => -p[1]))];
  const echelle = 900 / Math.max(x1 - x0, y1 - y0);
  const chemin = gardes
    .map((a) => `M${a.map(([x, y]) => `${((x * k - x0) * echelle + 62).toFixed(1)} ${((-y - y0) * echelle + 62).toFixed(1)}`).join("L")}Z`)
    .join("");
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#fff"/><path d="${chemin}" fill="#000"/></svg>`;
  return svgEnPng(svg);
}

/** Les illustrations d'un style, telles que la maquette les lit. */
function imagesCouverture(style) {
  const gardees = { ...(etat.couverture.images[style] || {}) };
  if (style === "travel-book") {
    // L'ancien collage généré d'un seul tenant (des mots qui n'existent pas)
    // cède la place aux timbres composés.
    delete gardees.timbres;
    if (etat.timbresComposes) gardees.timbres = etat.timbresComposes;
  }
  return Object.fromEntries(
    Object.entries(gardees).map(([cle, img]) => [cle, { fichier: `Liens/${style}-${cle}.png`, src: img.data, px: img.px, dominante: img.dominante }]),
  );
}

/** Les images à générer pour le style choisi (`CouvertureStyles.imagesDuStyle`). */
function imagesAGenerer(style) {
  return CouvertureStyles.imagesDuStyle(style, voyagePourCouverture(), textesDuStyle(style));
}

/**
 * Génère les illustrations du style (toutes celles qui manquent, ou une
 * seule avec `cle`), avec la couverture de référence du style en entrée. Le
 * résultat est gardé dans l'avancement : rien n'est régénéré sans le demander.
 */
async function genererIllustrations(style, cle = null) {
  const toutes = imagesAGenerer(style);
  const gardees = etat.couverture.images[style] || {};
  const aFaire = toutes.filter((i) => (cle ? i.cle === cle : !gardees[i.cle]));
  if (!aFaire.length) return;
  if (etat.mode === "navigateur" && !etat.reglages.cleOpenai) {
    etat.couverture.statut = "Les illustrations demandent une clé OpenAI : renseigne-la dans les réglages.";
    rendreCouverture();
    return;
  }
  const references = {};
  let faites = 0;
  for (const image of aFaire) {
    etat.couverture.statut = `Génération des illustrations… ${faites + 1} / ${aFaire.length} (une minute environ chacune)`;
    rendreCouverture();
    try {
      const cleReference = `${image.reference}|${image.rognerReference || ""}`;
      if (image.reference && !(cleReference in references)) {
        references[cleReference] =
          image.reference === "silhouette"
            ? await silhouetteDuPays()
            : await imageEnPng(await enDataUrl(image.reference), 1024, image.rognerReference || null);
      }
      const reference = image.reference ? references[cleReference] : null;
      const silhouetteManquante = image.reference === "silhouette" && !reference;
      const brute = await appelImage({
        cleOpenai: etat.reglages.cleOpenai,
        // Sans contours de carte pour le pays, le modèle dessine la silhouette lui-même.
        prompt: silhouetteManquante ? `${image.prompt} (Aucune image fournie : dessine toi-même la silhouette du pays.)` : image.prompt,
        taille: image.taille,
        qualite: image.qualite,
        transparent: image.transparent,
        references: reference ? [{ data: reference.data, nom: `${image.reference === "silhouette" ? "silhouette" : "reference"}.png` }] : [],
      });
      const data = image.detourer ? await detourerIllustration(brute.data) : brute.data;
      const { dominante, px } = await couleursDe(data);
      etat.couverture.images = {
        ...etat.couverture.images,
        [style]: { ...(etat.couverture.images[style] || {}), [image.cle]: { data, px, dominante, ...(image.detourer ? { detouree: true } : {}) } },
      };
      faites += 1;
    } catch (erreur) {
      console.error(`[couverture] illustration « ${image.cle} » impossible`, erreur);
      etat.couverture.statut = `Illustration « ${image.cle} » impossible (${erreur.message}).`;
      apresChangement();
      rendreCouverture();
      return;
    }
  }
  if (style === "travel-book") await composerTimbres().catch((erreur) => debugCarnet("timbres impossibles à composer", erreur));
  etat.couverture.statut = "";
  apresChangement();
  rendreCouverture();
}

/**
 * Les illustrations déjà générées qui gardent leur fond peint (avant le
 * détourage) : on le leur retire une fois, sans rien régénérer.
 */
async function detourerIllustrationsGardees(style) {
  const aDetourer = CouvertureStyles.imagesDuStyle(style, voyagePourCouverture(), textesDuStyle(style)).filter((i) => i.detourer);
  const gardees = etat.couverture.images[style] || {};
  let change = false;
  for (const image of aDetourer) {
    const img = gardees[image.cle];
    if (!img || img.detouree) continue;
    const data = await detourerIllustration(img.data);
    const { dominante, px } = await couleursDe(data);
    gardees[image.cle] = { data, px, dominante, detouree: true };
    change = true;
  }
  if (change) {
    etat.couverture.images = { ...etat.couverture.images, [style]: { ...gardees } };
    apresChangement();
  }
}

/**
 * La photo de la première du style Photo-dessin : celle que le voyageur a
 * choisie, sinon la mieux notée des propositions où l'on voit des personnes
 * (`personnes` de l'analyse d'étape), sinon la photo proposée d'ordinaire.
 */
function photoAvecVoyageurs() {
  const toutes = photosDesEtapes().filter((p) => p.data);
  const choisie = toutes.find((p) => p[DRAPEAU_PLAT.recto]);
  if (choisie) return choisie;
  const avecGens = propositionsCouverture().recto.find((e) => (e.photo.analyse?.personnes || 0) > 0);
  return (avecGens && toutes.find((p) => p.id === avecGens.photo.id)) || photoDuPlat("recto");
}

/**
 * Le contour des voyageurs sur la photo de Photo-dessin, par un appel
 * « vision » (`CouvertureStyles.CONSIGNE_CONTOUR`), et ses couleurs. Gardés par
 * photo : changer de photo relance, revenir à la précédente non.
 */
async function preparerPhotoDessin({ force = false } = {}) {
  const photo = photoAvecVoyageurs();
  if (!photo) return;
  etat.couverture.photosDessin ??= {};
  const garde = etat.couverture.photosDessin[photo.id] || {};
  if (!garde.couleurs) garde.couleurs = await couleursDe(photo.data);
  // `trace` : la forme lue (`CouvertureStyles.lireContour`). Les anciens
  // `contour` (une liste de points, souvent l'ellipse de repli) sont refaits.
  delete garde.contour;
  if (!garde.trace || force) {
    etat.couverture.statut = "Repérage du sujet de la photo…";
    rendreCouverture();
    try {
      const reponse = await appelAnalyse({
        fournisseur: etat.reglages.fournisseurDecoupage,
        modele: etat.reglages.modeleDecoupage,
        cleOpenai: etat.reglages.cleOpenai,
        cleAnthropic: etat.reglages.cleAnthropic,
        consigne: CouvertureStyles.CONSIGNE_CONTOUR,
        images: [{ id: "recto", data: await vignette(photo.data) }],
      });
      const trace = CouvertureStyles.lireContour(reponse);
      if (trace.trouve) {
        garde.trace = trace;
        etat.couverture.statut = "";
      } else {
        // Le repli (une ellipse au centre) n'est pas gardé : on retentera.
        delete garde.trace;
        debugCarnet("tracé de Photo-dessin illisible", reponse);
        etat.couverture.statut =
          "Le modèle n'a pas rendu de tracé utilisable pour cette photo : un cercle au centre en attendant. « Repérer à nouveau » pour réessayer.";
      }
    } catch (erreur) {
      delete garde.trace;
      debugCarnet("tracé de Photo-dessin impossible", erreur);
      etat.couverture.statut = `Repérage du sujet impossible (${erreur.message}) : un cercle au centre en attendant. « Repérer à nouveau » pour réessayer.`;
    }
  }
  etat.couverture.photosDessin[photo.id] = garde;
  await logoEnPng(couleurDuLogo("photo-drawing")).catch((erreur) => debugCarnet("logo indisponible", erreur));
  apresChangement();
  rendreCouverture();
}

/** Ce que chaque style prépare avant sa maquette : dessins, logo coloré, contour. */
async function preparerStyle(style) {
  const couleur = couleurDuLogo(style);
  if (couleur) await logoEnPng(couleur).catch((erreur) => debugCarnet("logo indisponible", erreur));
  if (style === "drawing" && !etat.dessinsCouverture) await preparerDessinsCouverture().catch((erreur) => debugCarnet("dessins de couverture indisponibles", erreur));
  if (style === "photo-drawing") await preparerPhotoDessin();
  if (style === "watercolor") await motifEnPng().catch((erreur) => debugCarnet("motif M indisponible", erreur));
  if (["assouline", "watercolor", "travel-book"].includes(style)) {
    await detourerIllustrationsGardees(style).catch((erreur) => debugCarnet("détourage impossible", erreur));
  }
  if (style === "travel-book") await composerTimbres().catch((erreur) => debugCarnet("timbres impossibles à composer", erreur));
}

/** Ce qu'il faut dire avant d'envoyer la couverture. */
function alertesCouverture() {
  const fiche = ficheCouverture();
  const alertes = [];
  if (fiche.tropCourt) {
    alertes.push(`Pumbo relie ${Couverture.PAGES_MIN} pages au moins : le carnet n'en a que ${fiche.pages}.`);
  }
  if (fiche.parDefaut) {
    alertes.push(
      `Dimensions de la ${fiche.source} (dos de ${fiche.dos} mm). Le dos dépend du nombre de pages : ` +
        "importe la fiche Pumbo de cette commande dans les réglages avant d'envoyer le fichier.",
    );
  }
  const recto = photoDuPlat("recto");
  if (!recto) alertes.push("Aucune photo : la première de couverture sera un aplat vert.");
  else {
    const p = photosPourCouverture().find((x) => x.id === recto.id);
    alertes.push(...Couverture.evaluerPhoto(p, { fiche, mesure: p.mesure, analyse: p.analyse }).alertes);
  }
  if (!Voyage.lieuxDeSejour(etapesPourMiseEnPage(() => "")).length) {
    alertes.push("Aucun lieu situé : la carte de la quatrième restera vide. Analyse les étapes (clé de modèle dans les réglages).");
  }
  if (etat.couverture.style === "watercolor") {
    if (!textesDuStyle("watercolor").pays) alertes.push("Aquarelle : aucun pays pour le titre de la première. Écris-le dans les textes du style.");
    alertes.push(...CouvertureStyles.controleAquarelle(maquetteCouverture()).map((f) => `Aquarelle : ${f[0].toLowerCase()}${f.slice(1)}`));
  }
  return alertes;
}

/**
 * Ouvre le panneau : analyse les étapes (lieux, trajets, note des photos),
 * charge les contours de la carte et mesure les photos. Tout est gardé : la
 * seconde ouverture est immédiate.
 */
async function ouvrirCouverture() {
  etat.couverture.ouverte = true;
  rendreCouverture();
  $("carte-couverture")?.scrollIntoView({ behavior: "smooth", block: "start" });
  try {
    await preparerMiseEnPage((texte) => {
      etat.couverture.statut = texte;
      rendreCouverture();
    });
    const photos = photosDesEtapes().filter((p) => p.data && !p.mesure);
    for (const [i, p] of photos.entries()) {
      etat.couverture.statut = `Mesure des photos… ${i + 1} / ${photos.length}`;
      rendreCouverture();
      try {
        await mesurerPhoto(p);
      } catch (erreur) {
        debugCarnet("photo illisible pour la mesure", erreur);
      }
    }
    await logoEnPng().catch((erreur) => debugCarnet("logo indisponible", erreur));
    await logoEnPng(Couverture.COULEURS.beigeFonce.hex).catch((erreur) => debugCarnet("logo beige indisponible", erreur));
    await preparerDessinsCouverture().catch((erreur) => debugCarnet("dessins de couverture indisponibles", erreur));
    await preparerStyle(etat.couverture.style);
  } finally {
    etat.couverture.statut = "";
    apresChangement();
    rendreCouverture();
  }
}

/**
 * L'aperçu à imprimer en PDF, dans un nouvel onglet. L'onglet s'ouvre **avant**
 * tout `await` : ouvert plus tard, hors du geste du clic, il serait bloqué par
 * le navigateur comme une fenêtre surgissante.
 */
async function apercuCouverture() {
  const onglet = window.open("", "_blank");
  if (!onglet) {
    etat.erreur = "Le navigateur a bloqué l'onglet de la couverture : autorise les fenêtres pour cette page.";
    rendreColonne();
    return;
  }
  onglet.document.write('<p style="font:15px system-ui,sans-serif;padding:2rem">Composition de la couverture…</p>');
  // Les polices du carnet, pour que la couverture parle comme l'intérieur.
  let polices = "";
  try {
    polices = await recupererFichierTemplate("fonts.css");
  } catch (erreur) {
    debugCarnet("polices du gabarit indisponibles pour la couverture", erreur);
  }
  await preparerStyle(etat.couverture.style).catch((erreur) => debugCarnet("style de couverture incomplet", erreur));
  // Et celles des styles de couverture (Cormorant, Manrope…), servies par l'atelier.
  polices += `\n<style>${CouvertureStyles.cssPolices(new URL("./fonts/couvertures/", location.href).href)}</style>`;
  const html = Couverture.versHtml(maquetteCouverture(), {
    polices,
    alertes: alertesCouverture(),
    titre: textesCouverture().titre,
  });
  onglet.document.open();
  onglet.document.write(html);
  onglet.document.close();
}

const octetsDe = (dataUrl) => {
  const binaire = atob(String(dataUrl).split(",")[1] || "");
  const octets = new Uint8Array(binaire.length);
  for (let i = 0; i < binaire.length; i += 1) octets[i] = binaire.charCodeAt(i);
  return octets;
};

/**
 * Le fichier InDesign : un dossier zippé — le script qui construit le document
 * (sur le modèle de la fiche Pumbo), les photos en pleine résolution dans
 * `Liens/`, et le mode d'emploi.
 */
async function fichierInDesign() {
  await logoEnPng().catch((erreur) => debugCarnet("logo indisponible", erreur));
  await logoEnPng(Couverture.COULEURS.beigeFonce.hex).catch((erreur) => debugCarnet("logo beige indisponible", erreur));
  await preparerStyle(etat.couverture.style).catch((erreur) => debugCarnet("style de couverture incomplet", erreur));
  const mq = maquetteCouverture();
  const textes = textesCouverture();
  const style = CouvertureStyles.styleDe(etat.couverture.style);
  const dossier = "Couverture MemoBook";
  const enc = new TextEncoder();
  const fichiers = [
    { nom: `${dossier}/Couverture MemoBook.jsx`, octets: enc.encode(Couverture.versJsx(mq, { titre: textes.titre })) },
    {
      nom: `${dossier}/LISEZMOI.txt`,
      octets: enc.encode(
        Couverture.lisezmoi({
          titre: textes.titre,
          fiche: mq.fiche,
          polices: [...new Set(CouvertureStyles.POLICES[style.id] || ["Playfair Display"])],
          style: style.id === "default" ? "" : style.nom,
        }),
      ),
    },
  ];
  for (const e of mq.elements) {
    if (e.type === "image" && e.src?.startsWith("data:") && !fichiers.some((f) => f.nom === `${dossier}/${e.fichier}`)) {
      fichiers.push({ nom: `${dossier}/${e.fichier}`, octets: octetsDe(e.src) });
    }
  }
  const zip = Couverture.zipper(fichiers);
  const lien = document.createElement("a");
  lien.href = URL.createObjectURL(new Blob([zip], { type: "application/zip" }));
  lien.download = `couverture-${(textes.titre || "carnet").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-")}.zip`;
  document.body.append(lien);
  lien.click();
  lien.remove();
  setTimeout(() => URL.revokeObjectURL(lien.href), 10000);
}

function rendreCouverture() {
  const section = $("carte-couverture");
  if (!section) return;
  section.hidden = !etat.couverture.ouverte;
  if (section.hidden) return;

  const fiche = fichePumbo();
  const toutes = photosPourCouverture();
  const propositions = Couverture.proposerPhotos(toutes, { fiche });
  const pourcent = (v) => `${Math.round(v * 100)}`;

  const plat = (face, titre, note) => {
    const choisie = photoDuPlat(face);
    const proposees = propositions[face];
    const horsPropositions = choisie && !proposees.some((e) => e.photo.id === choisie.id);
    const evaluee = choisie && toutes.find((p) => p.id === choisie.id);
    const evaluation = evaluee && Couverture.evaluerPhoto(evaluee, { fiche, mesure: evaluee.mesure, analyse: evaluee.analyse });
    const vignette = (photo, e, petite) =>
      h(
        "button",
        {
          class: `vignette-couv${petite ? " petite" : ""}${choisie?.id === photo.id ? " choisie" : ""}`,
          title: e ? `Note ${pourcent(e.score)} / 100 — qualité ${pourcent(e.qualite)}, contenu ${pourcent(e.contenu)}, ${e.dpi} dpi` : "",
          onclick: () => choisirPhotoDuPlat(face, photo.id),
        },
        h("img", { src: photo.data, alt: "" }),
        e && !petite ? h("span", { class: "note-couv" }, `${pourcent(e.score)} · ${e.dpi} dpi`) : null,
      );
    return h(
      "div",
      { class: "plat-couv" },
      h("h3", {}, titre),
      note ? h("p", { class: "aide" }, note) : null,
      h(
        "div",
        { class: "propositions-couv" },
        proposees.length
          ? proposees.map((e) => vignette(e.photo, e))
          : h(
              "p",
              { class: "aide" },
              "Aucune photo du carnet ne passe le contrôle qualité pour ce plat (résolution, netteté, exposition, format). Choisis-en une quand même avec « Autre photo… » : ses défauts s'afficheront.",
            ),
        horsPropositions ? vignette(evaluee, evaluation) : null,
        bouton(etat.couverture.autre[face] ? "Fermer" : "Autre photo…", {
          petit: true,
          surClic: () => {
            etat.couverture.autre[face] = !etat.couverture.autre[face];
            rendreCouverture();
          },
        }),
      ),
      etat.couverture.autre[face]
        ? h("div", { class: "toutes-couv" }, toutes.map((p) => vignette(p, null, true)))
        : null,
      evaluation && !evaluation.suffisante
        ? h(
            "div",
            { class: "alerte-couv" },
            h("strong", {}, horsPropositions ? "Contrôle qualité — cette photo pose problème :" : "À savoir :"),
            h("ul", {}, evaluation.alertes.map((a) => h("li", {}, a))),
          )
        : horsPropositions
          ? h("p", { class: "aide" }, "Contrôle qualité : rien à signaler.")
          : null,
    );
  };

  const t = textesCouverture();
  const poser = (cle) => (v) => {
    etat.couverture.textes = { ...etat.couverture.textes, [cle]: v };
  };
  const c = chiffresDuVoyage();
  const quatrieme = chiffresQuatrieme();
  const style = CouvertureStyles.styleDe(etat.couverture.style);

  // Le choix du style : les sept du catalogue de l'app, avec leur première de
  // référence. Un style que l'atelier ne sait pas encore faire reste « À venir ».
  const choixDuStyle = h(
    "div",
    { class: "styles-couv" },
    CouvertureStyles.STYLES.map((s) =>
      h(
        "button",
        {
          class: `style-couv${s.id === style.id ? " choisi" : ""}${s.dispo ? "" : " a-venir"}`,
          disabled: !s.dispo,
          title: s.dispo ? `Style ${s.nom}` : "Pas encore disponible : ce style demande des images générées",
          onclick: () => {
            etat.couverture.style = s.id;
            apresChangement();
            rendreCouverture();
            preparerStyle(s.id).then(rendreCouverture, (erreur) => debugCarnet("style de couverture incomplet", erreur));
          },
        },
        h("img", { src: s.recto, alt: "", loading: "lazy" }),
        h("span", { class: "nom-style-couv" }, s.nom),
        s.dispo ? null : h("span", { class: "pastille-a-venir" }, "À venir"),
      ),
    ),
  );

  // Les textes du style : rédigés par l'IA, puis modifiables.
  const textesStyle = () => {
    if (style.id === "default") return null;
    const valeurs = textesDuStyle(style.id);
    const poserStyle = (cle) => (v) => {
      etat.couverture.textesStyle = {
        ...etat.couverture.textesStyle,
        [style.id]: { ...(etat.couverture.textesStyle[style.id] || {}), [cle]: v },
      };
    };
    const champs = CouvertureStyles.CHAMPS[style.id] || [];
    return [
      h(
        "div",
        { class: "rangee" },
        h("h3", {}, `Textes — ${style.nom}`),
        champs.some((ch) => ch.ia)
          ? bouton("Rédiger avec l'IA", { petit: true, surClic: () => redigerTextesCouverture(style.id) })
          : null,
      ),
      h(
        "p",
        { class: "aide" },
        "Rédigés d'après les récits (✦), puis à reprendre à la main : ce que tu écris ici passe avant. Un paragraphe par bloc séparé d'une ligne vide.",
      ),
      h(
        "div",
        { class: "grille-champs" },
        champs.map((ch) =>
          ch.lignes
            ? h(
                "label",
                { class: "champ champ-large" },
                h("span", {}, ch.label, ch.ia ? h("span", { class: "puce-ia", title: "Rédigé par l'IA" }, "✦") : null),
                h("textarea", { rows: 5, value: valeurs[ch.cle] ?? "", oninput: (ev) => poserStyle(ch.cle)(ev.target.value) }),
              )
            : champ({ label: ch.label, valeur: valeurs[ch.cle], placeholder: valeurs.defaut?.[ch.cle], puce: ch.ia, surSaisie: poserStyle(ch.cle) }),
        ),
      ),
    ];
  };
  // Les illustrations générées du style : coût estimé, génération, et
  // « Régénérer » image par image.
  const illustrations = () => {
    const prevues = imagesAGenerer(style.id);
    if (!prevues.length) return null;
    const gardees = etat.couverture.images[style.id] || {};
    const manquantes = prevues.filter((i) => !gardees[i.cle]);
    const dollars = (v) => `${v.toFixed(2).replace(".", ",")} $`;
    const enCours = etat.couverture.statut.startsWith("Génération");
    return [
      h(
        "div",
        { class: "rangee" },
        h("h3", {}, `Illustrations — ${style.nom}`),
        manquantes.length
          ? bouton(`Générer ${manquantes.length > 1 ? `les ${manquantes.length} illustrations` : "l'illustration"} (≈ ${dollars(CouvertureStyles.coutImages(manquantes))})`, {
              petit: true,
              desactive: enCours,
              surClic: () => genererIllustrations(style.id),
            })
          : null,
      ),
      h(
        "p",
        { class: "aide" },
        "Générées par OpenAI (gpt-image-1, clé OpenAI des réglages) d'après les récits et les textes ci-dessus, avec la couverture de référence du style en entrée quand elle sert. " +
          `Coût estimé : ${dollars(CouvertureStyles.coutImages(prevues))} pour les ${prevues.length}, ${dollars(0.04)} à ${dollars(0.25)} par image régénérée. ` +
          "Elles sont gardées dans l'avancement.",
      ),
      h(
        "div",
        { class: "illustrations-couv" },
        prevues.map((i) =>
          h(
            "figure",
            { class: "illustration-couv" },
            gardees[i.cle] ? h("img", { src: gardees[i.cle].data, alt: "" }) : h("div", { class: "illustration-vide" }, "À générer"),
            h(
              "figcaption",
              {},
              h("span", {}, `${i.cle} · ${i.pour === "recto" ? "1re" : "4e"}`),
              gardees[i.cle]
                ? bouton("Régénérer", { petit: true, desactive: enCours, surClic: () => genererIllustrations(style.id, i.cle) })
                : null,
            ),
          ),
        ),
      ),
    ];
  };
  const notes = {
    default: { recto: null, verso: "Le style par défaut n'a pas de photo en quatrième (la carte et les chiffres) : ce choix servira aux styles qui en ont une." },
    elegant: { recto: "Une photo de paysage, en grand sous le titre.", verso: "Une photo de paysage, en bande panoramique en tête de la quatrième." },
    drawing: {
      recto: "Le style Dessin n'a pas de photo : des dessins de la bibliothèque, choisis d'après les récits" +
        (etat.dessinsCouverture?.length ? ` (${etat.dessinsCouverture.map((d) => d.famille).join(", ")}).` : "."),
      verso: null,
    },
    assouline: { recto: "Pas de photo sur la première : l'illustration générée, et le fond choisi d'après sa couleur.", verso: null },
    watercolor: {
      recto: "Pas de photo : une aquarelle générée d'après le pays, sous son nom en Poppins Black ; trois vignettes sur la quatrième, sur le motif M.",
      verso: null,
    },
    "travel-book": {
      recto:
        "Pas de photo sur la première : six timbres — six illustrations générées sans un mot, chacune dans son ton, mises en timbres avec " +
        "les lieux du voyage pour légendes — et le tampon du pays.",
      verso: "La photo de la quatrième, dans le cadre vert déchiré.",
    },
    "photo-drawing": {
      recto:
        "Une photo où l'on voit les voyageurs (ou ce qui domine la photo) : des traits au feutre épousent le sujet de cette photo-là, " +
        "le titre suit le trait du haut. La photo est cadrée sur le sujet ; les couleurs des textes viennent d'elle.",
      verso: null,
    },
  }[style.id] || {};
  // Les styles sans photo sur un plat n'en proposent pas le choix.
  const sansPhotoRecto = ["drawing", "assouline", "watercolor", "travel-book"].includes(style.id);
  const sansPhotoVerso = ["drawing", "assouline", "watercolor", "photo-drawing"].includes(style.id);

  remplir(
    section,
    h(
      "div",
      { class: "contenu" },
      h(
        "div",
        { class: "rangee entete-couv" },
        h("h2", {}, "Couverture du livre"),
        (() => {
          const f = ficheCouverture();
          return h(
            "span",
            { class: "aide" },
            `Style ${style.nom} · plats ${f.largeurPlat} × ${f.hauteurPlat} mm · dos ${String(f.dos).replace(".", ",")} mm` +
              (f.pages ? ` pour ${f.pages} pages (barème Pumbo)` : ""),
          );
        })(),
        bouton("Fermer", {
          petit: true,
          surClic: () => {
            etat.couverture.ouverte = false;
            rendreCouverture();
          },
        }),
      ),
      etat.couverture.statut ? h("p", { class: "aide accent" }, etat.couverture.statut) : null,
      h("h3", {}, "Style"),
      choixDuStyle,
      sansPhotoRecto ? h("p", { class: "aide" }, notes.recto) : plat("recto", "1re de couverture", notes.recto),
      style.id === "photo-drawing"
        ? h(
            "div",
            { class: "rangee" },
            h(
              "span",
              { class: "aide" },
              (() => {
                const photo = photoAvecVoyageurs();
                const trace = photo && etat.couverture.photosDessin?.[photo.id]?.trace;
                if (!trace) return "Sujet pas encore repéré sur la photo : le tracé est un cercle au centre.";
                return trace.forme === "ligne"
                  ? "Sujet repéré : les traits passent au-dessus de sa silhouette, d'un bord à l'autre."
                  : "Sujet repéré : petit et entier, il est entouré d'anneaux.";
              })(),
            ),
            bouton("Repérer à nouveau", { petit: true, surClic: () => preparerPhotoDessin({ force: true }) }),
          )
        : null,
      sansPhotoVerso ? null : plat("verso", "4e de couverture", notes.verso),
      textesStyle(),
      illustrations(),
      h("h3", {}, style.id === "default" ? "Textes" : "Dos"),
      h(
        "div",
        { class: "grille-champs" },
        champ({ label: "Titre", valeur: t.titre, placeholder: t.defaut.titre, surSaisie: poser("titre") }),
        champ({ label: "Voyageurs", valeur: t.voyageurs, placeholder: t.defaut.voyageurs, surSaisie: poser("voyageurs") }),
        champ({ label: "Dates", valeur: t.dates, placeholder: t.defaut.dates, surSaisie: poser("dates") }),
      ),
      h("h3", {}, "Chiffres du voyage"),
      h(
        "p",
        { class: "aide" },
        `${nombre(c.jours)} jours · ${c.km === null ? "km inconnus (aucun trajet raconté)" : `${nombre(c.km)} km parcourus`} · ` +
          `${c.pays.length} pays (${c.pays.join(", ") || "—"}) · ${c.villes.length} villes (${c.villes.join(", ") || "—"}). ` +
          `En quatrième : ${quatrieme.map((q) => `${q.valeur} ${q.libelle.replace("\n", " ")}`).join(", ")}.` +
          (c.analysees < c.etapes ? ` ${c.etapes - c.analysees} étape(s) pas encore analysée(s).` : ""),
      ),
      h(
        "div",
        { class: "rangee" },
        bouton("Aperçu à imprimer (PDF)", { surClic: apercuCouverture }),
        bouton("Fichier InDesign (.zip)", { ton: "solide", surClic: fichierInDesign }),
      ),
    ),
  );
}

/** Lit la fiche `.jsx` de Pumbo choisie dans les réglages, et la garde pour les prochaines couvertures. */
async function importerFichePumbo(fichier) {
  if (!fichier) return;
  const fiche = Couverture.lireFichePumbo(await fichier.text());
  if (!fiche) {
    etat.erreur = `« ${fichier.name} » n'est pas une fiche de couverture Pumbo : il faut le script .jsx de leur outil de couverture.`;
  } else {
    etat.reglages.fichePumbo = { ...fiche, source: `fiche Pumbo « ${fichier.name} »` };
    sauverReglages();
    etat.erreur = "";
    etat.info = `Fiche Pumbo importée : plats ${fiche.largeurPlat} × ${fiche.hauteurPlat} mm, dos ${fiche.dos} mm.`;
  }
  rendreColonne();
}

/* ------------------------------------------- analyse d'étape et cartes --- */

const CONTOURS_CARTE_URL =
  "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/assets/maps/countries.json";

/**
 * La clé d'une analyse : ce qui, s'il change, la rend caduque — le lieu, le
 * récit, les photos. Une étape inchangée n'est pas réanalysée d'une génération
 * à l'autre ; l'analyse voyage avec l'étape dans le fichier d'avancement.
 */
function cleAnalyse(etape) {
  const contenu = [
    // La version de la consigne : une analyse faite avant l'encart n'en a pas.
    VERSION_ANALYSE,
    etape.lieu || "",
    etat.carnet.destination || "",
    recitDe(etape),
    ...etape.photos.filter((p) => p.data).map((p) => `${p.id}:${p.largeur}x${p.hauteur}`),
  ].join("|");
  let h = 0;
  for (let i = 0; i < contenu.length; i += 1) h = (Math.imul(31, h) + contenu.charCodeAt(i)) | 0;
  return `${contenu.length}-${(h >>> 0).toString(36)}`;
}

/** À changer quand `consigneAnalyseEtape` demande autre chose : les analyses gardées se refont. */
const VERSION_ANALYSE = "7-quiz";

/** Vignette JPEG de 512 px au plus côté : assez pour reconnaître une scène, léger à envoyer. */
async function vignette(dataUrl) {
  const img = new Image();
  img.src = dataUrl;
  await img.decode();
  const ratio = Math.min(1, 512 / Math.max(img.naturalWidth, img.naturalHeight));
  const toile = document.createElement("canvas");
  toile.width = Math.max(1, Math.round(img.naturalWidth * ratio));
  toile.height = Math.max(1, Math.round(img.naturalHeight * ratio));
  toile.getContext("2d").drawImage(img, 0, 0, toile.width, toile.height);
  return toile.toDataURL("image/jpeg", 0.7);
}

/** Le serveur relaie en local ; en ligne la page appelle l'API elle-même. */
async function appelAnalyse(corps) {
  if (etat.mode === "navigateur") return MoteurNavigateur.analyser(corps);
  return appelJson("/api/analyser", corps);
}

/**
 * Analyse chaque étape qui ne l'a pas encore été : le lieu (pour la carte de
 * chapitre), le passage que chaque photo illustre et les photos prises au même
 * endroit (pour les mettre sur la même page). Voir `consigneAnalyseEtape` et
 * LAYOUT_KB § « Associer les photos au récit ».
 *
 * Sans clé, ou si le modèle échoue, le carnet se fait quand même : photos dans
 * l'ordre du voyage, pas de carte. On le dit, sans bloquer.
 */
async function analyserEtapes(statut = () => {}) {
  const fournisseur = etat.reglages.fournisseurDecoupage;
  const anthropic = fournisseur === "anthropic";
  const avecCle =
    (anthropic ? etat.reglages.cleAnthropic : etat.reglages.cleOpenai)?.trim() ||
    (anthropic ? etat.config?.cleServeur?.anthropic : etat.config?.cleServeur?.openai);
  const aFaire = etat.etapes.filter((e) => e.analyse?.cle !== cleAnalyse(e));
  if (!aFaire.length) return { faites: 0, echecs: 0 };
  if (!avecCle) {
    statut("Pas de clé de modèle : photos placées dans l'ordre du voyage, ni carte de chapitre ni fun fact.");
    noter("Pas de clé de modèle : aucune étape analysée — ni carte de chapitre, ni kilomètres, ni fun fact.", "err");
    return { faites: 0, echecs: aFaire.length };
  }

  let faites = 0;
  let echecs = 0;
  let premiereErreur = null;
  const unePasse = async (etape) => {
    const photos = etape.photos.filter((p) => p.data);
    try {
      const images = await Promise.all(photos.map(async (p) => ({ id: p.id, data: await vignette(p.data) })));
      const consigne = consigneAnalyseEtape({
        lieu: etape.lieu,
        destination: etat.carnet.destination,
        paragraphes: MiseEnPage.enParagraphes(recitDe(etape)),
        photos,
        // De quoi tenir environ un fun fact toutes les trois pages : une étape
        // fait à peu près une page par 700 signes de récit, plus ses planches.
        maxEncarts: 1 + Math.ceil(recitDe(etape).length / 1400) + (photos.length > 6 ? 1 : 0),
      });
      const resultat = await appelAnalyse({
        fournisseur,
        modele: etat.reglages.modeleDecoupage,
        cleOpenai: etat.reglages.cleOpenai,
        cleAnthropic: etat.reglages.cleAnthropic,
        consigne,
        images,
      });
      etape.analyse = { cle: cleAnalyse(etape), resultat };
      faites += 1;
    } catch (erreur) {
      echecs += 1;
      premiereErreur ||= erreur;
      debugCarnet(`analyse de l'étape « ${etape.titre || etape.lieu} » impossible`, erreur);
    }
    statut(`Analyse des étapes et des photos… ${faites + echecs} / ${aFaire.length}`);
  };

  // Trois à la fois : assez pour aller vite, pas assez pour se faire limiter.
  statut(`Analyse des étapes et des photos… 0 / ${aFaire.length}`);
  for (let i = 0; i < aFaire.length; i += 3) await Promise.all(aFaire.slice(i, i + 3).map(unePasse));
  // Sans analyse, pas de lieux situés (cartes, kilomètres), pas de fun facts,
  // et les photos suivent l'ordre du voyage : ça doit se voir.
  if (echecs) {
    noter(
      `Analyse impossible pour ${echecs} étape(s) sur ${aFaire.length} — sans elle, ni cartes, ni kilomètres, ni fun facts : ${premiereErreur?.message || premiereErreur}`,
      "err",
    );
  }
  return { faites, echecs };
}

/** Les contours des pays, lus une fois sur GitHub pour dessiner les cartes de chapitre. */
async function chargerContoursCarte() {
  if (etat.contoursCarte) return;
  try {
    const reponse = await fetch(CONTOURS_CARTE_URL);
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    etat.contoursCarte = await reponse.json();
  } catch (erreur) {
    debugCarnet("contours de carte indisponibles : pas de carte de chapitre", erreur);
  }
}

const CONTOURS_DETAIL_URL =
  "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/assets/maps/detail/";

/**
 * La bibliothèque de stickers dessinés (`assets/stickers/stickers.json`) : un
 * sticker par fichier, et les mots du récit qui le déclenchent. Chaque fichier
 * est servi par GitHub à une adresse publique, que le moteur PDF peut charger.
 */
const STICKERS_URL = "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/assets/stickers/";

/**
 * La bibliothèque de stickers (`assets/stickers/stickers.json`), celle de
 * `main` : APITemplate rend le PDF à partir d'adresses publiques, une
 * bibliothèque n'apparaît donc dans le carnet qu'une fois fusionnée.
 */
async function chargerStickers() {
  if (etat.stickers) return;
  try {
    const reponse = await fetch(`${STICKERS_URL}stickers.json`);
    if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
    const index = await reponse.json();
    etat.stickers = (Array.isArray(index.stickers) ? index.stickers : []).map((s) => ({
      ...s,
      url: `${STICKERS_URL}${encodeURIComponent(s.fichier)}`,
    }));
  } catch (erreur) {
    etat.stickers = [];
    debugCarnet("bibliothèque de stickers indisponible", erreur);
  }
}

/**
 * Les contours détaillés (Natural Earth 10 m, un fichier par pays) des pays
 * qui touchent le cadre d'une carte de chapitre : ceux de 110 m n'ont pas les
 * petites îles, et une carte cadrée sur les Cyclades n'y montrerait que la mer.
 * Chargés une fois par pays ; sans eux, la carte retombe sur le pays entier.
 */
async function chargerContoursDetail() {
  if (!etat.contoursCarte) return;
  const etapes = etapesPourMiseEnPage(() => "");
  // Les cartes de chapitre, et celle de la quatrième de couverture.
  const cadres = [
    ...MiseEnPage.cadresDesCartes(etapes, etat.contoursCarte),
    Couverture.cadreQuatrieme(Voyage.lieuxDeSejour(etapes)),
  ].filter(Boolean);
  if (!cadres.length) return;
  etat.contoursDetail ||= {};
  try {
    if (!etat.indexDetail) {
      const reponse = await fetch(`${CONTOURS_DETAIL_URL}index.json`);
      if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
      etat.indexDetail = await reponse.json();
    }
    // Les pays qui touchent un cadre, élargi d'un degré : la carte s'élargit
    // au format de la page.
    const touche = (b, c) => b[0] <= c[2] + 1 && c[0] - 1 <= b[2] && b[1] <= c[3] + 1 && c[1] - 1 <= b[3];
    const codes = Object.entries(etat.indexDetail)
      .filter(([code, { bbox }]) => !etat.contoursDetail[code] && cadres.some((c) => touche(bbox, c)))
      .map(([code]) => code);
    await Promise.all(
      codes.map(async (code) => {
        const reponse = await fetch(`${CONTOURS_DETAIL_URL}${code}.json`);
        if (!reponse.ok) throw new Error(`${code} : HTTP ${reponse.status}`);
        etat.contoursDetail[code] = await reponse.json();
      }),
    );
  } catch (erreur) {
    debugCarnet("contours détaillés indisponibles : cartes du pays entier", erreur);
  }
}

/**
 * L'API Overpass : les grands axes et les cours d'eau des cartes de ville,
 * tirés d'OpenStreetMap. Le back-end lit la sienne dans `OVERPASS_URL`.
 */
const OVERPASS_URL = "https://overpass-api.de/api/interpreter";

/**
 * Les rues et l'eau des cartes de ville, demandées une fois par vue. Overpass
 * en panne ou trop lent (une minute) : la carte de ville reste sobre.
 */
async function chargerRuesDesVilles() {
  if (!etat.contoursCarte) return;
  const etapes = etapesPourMiseEnPage(() => "");
  const vues = MiseEnPage.cadresDesVilles(etapes, etat.contoursCarte).map((cadre) => Carte.vueDeVille(cadre));
  // Une vue après l'autre : Overpass n'accorde que deux créneaux par adresse,
  // et des requêtes en parallèle finissaient en 429 ou en délai dépassé.
  const aCharger = vues.filter((vue) => !etat.ruesDesVilles[Carte.cleDeVue(vue)]);
  if (aCharger.length) Journal.info("atelier", `OpenStreetMap : ${aCharger.length} carte(s) de ville à charger (jusqu'à une minute chacune)`);
  for (const vue of aCharger) {
    try {
      const reponse = await fetch(OVERPASS_URL, {
        method: "POST",
        body: new URLSearchParams({ data: Carte.requeteOverpass(vue) }),
        signal: AbortSignal.timeout(60_000),
      });
      if (!reponse.ok) throw new Error(`HTTP ${reponse.status}`);
      const json = await reponse.json();
      if (json.remark && /error/i.test(json.remark)) throw new Error(json.remark);
      etat.ruesDesVilles[Carte.cleDeVue(vue)] = Carte.ruesDOverpass(json, vue);
    } catch (erreur) {
      debugCarnet("rues OpenStreetMap indisponibles : carte de ville sobre", erreur);
    }
  }
}

/** La carte d'un chapitre : cadrée sur le voyage si les contours détaillés de son pays sont là. */
function dessinerCarteChapitre(requete) {
  if (requete.cadre && etat.contoursDetail?.[requete.regions[0]]) {
    if (requete.ville) {
      const vue = Carte.vueDeVille(requete.cadre, requete.widthPt, requete.heightPt);
      requete = { ...requete, rues: etat.ruesDesVilles[Carte.cleDeVue(vue)] || null };
    }
    return Carte.renderCarteCadreeDataUri(etat.contoursDetail, requete);
  }
  return Carte.renderMapDataUri(etat.contoursCarte, requete);
}

/** Ce qui précède la mise en page : l'analyse des étapes et les contours de carte. */
async function preparerMiseEnPage(statut) {
  await Promise.all([analyserEtapes(statut), chargerContoursCarte(), chargerStickers()]);
  await Promise.all([chargerContoursDetail(), chargerRuesDesVilles()]);
  // La netteté et l'exposition de chaque photo : quand une étape en a trop,
  // les floues et les sombres sont écartées les premières.
  const aMesurer = photosDesEtapes().filter((p) => p.data && !p.mesure);
  for (const [i, p] of aMesurer.entries()) {
    statut(`Mesure des photos… ${i + 1} / ${aMesurer.length}`);
    try {
      await mesurerPhoto(p);
    } catch (erreur) {
      debugCarnet("photo illisible pour la mesure", erreur);
    }
  }
}

async function genererCarnet(bouton) {
  if (bouton.disabled) return;
  debugCarnet("clic sur Générer le carnet", {
    etapes: etat.etapes.length,
    photos: etat.etapes.reduce((n, e) => n + e.photos.length, 0),
    mode: etat.mode,
  });

  if (!etat.etapes.length) {
    etat.carnetStatut = { type: "erreur", texte: "Aucune étape : dépose et transcris des vocaux avant de générer le carnet." };
    rendreResultatPdf();
    return;
  }
  const cle = (etat.reglages.cleApitemplate || "").trim();
  if (!cle) {
    etat.carnetStatut = { type: "erreur", texte: "Aucune clé APITemplate : colle-la dans « Clés et réglages », puis relance." };
    etat.boites.reglages = true;
    rendreResultatPdf();
    rendreColonne();
    return;
  }

  // Ouvert tout de suite, pendant que le geste de l'utilisateur est encore « frais ».
  const onglet = window.open("", "_blank");
  if (onglet) {
    onglet.opener = null;
    onglet.document.title = "Carnet en cours de génération";
    onglet.document.body.style.cssText = "font-family:system-ui,sans-serif;padding:2rem;color:#2d231a";
    onglet.document.body.textContent = "Génération du carnet en cours, cet onglet affichera le PDF dès qu'il sera prêt.";
  } else {
    debugCarnet("onglet bloqué par le navigateur, le lien restera sous le bouton");
  }

  const contenu = [...bouton.childNodes];
  bouton.disabled = true;
  bouton.textContent = "Génération en cours…";
  etat.pdf = null;
  etat.carnetStatut = { type: "info", texte: "Préparation des photos…" };
  rendreResultatPdf();

  let statut = 0;
  const templateId = (etat.reglages.templateApitemplate || "").trim() || "7a177b23210099d6";
  const annoncer = (texte) => {
    etat.carnetStatut = { type: "info", texte };
    Journal.info("atelier", texte);
    rendreResultatPdf();
  };
  try {
    try {
      await synchroniserTemplate({ cle, templateId, statut: annoncer });
    } catch (erreur) {
      throw new Error(`synchronisation du gabarit impossible, rien n'a été envoyé — ${erreur.message}`);
    }
    await preparerMiseEnPage(annoncer);
    const { payload, poids, base, palier } = await preparerEnvoi();
    debugCarnet("envoi", { base, poids, palier });

    etat.carnetStatut = {
      type: "info",
      texte: `Envoi à APITemplate (${(poids / 1024).toFixed(0)} Ko${palier ? `, photos en ${palier.cote} px` : ""})… compte 10 à 40 secondes.`,
    };
    rendreResultatPdf();

    const url = new URL(`${base}/create-pdf`);
    const imprimeur = Boolean(etat.reglages.versionImprimeur);
    if (imprimeur && !templateImprimeur()) {
      noter("version imprimeur sans fond perdu : renseigne le template imprimeur (feuille 154 × 216 mm) dans les réglages.");
    }
    url.searchParams.set("template_id", (imprimeur && templateImprimeur()) || templateId);

    const debut = performance.now();
    const reponse = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", "X-API-KEY": cle },
      body: JSON.stringify(payload),
    });
    statut = reponse.status;
    const donnees = await reponse.json().catch(() => null);
    debugCarnet("réponse", { statut, duree_ms: Math.round(performance.now() - debut), donnees });

    if (!reponse.ok || donnees?.status !== "success") {
      throw new Error(donnees?.message || `APITemplate a refusé le rendu (HTTP ${statut})`);
    }
    if (!donnees.download_url) {
      throw new Error("APITemplate a répondu « success » sans lien de téléchargement");
    }

    etat.pdf = { url: donnees.download_url, quand: new Date() };
    // Les pages du PDF en version imprimeur fixent la largeur du dos.
    const pages = pagesDuLivre();
    etat.carnetStatut = {
      type: "info",
      texte:
        `${pages} pages en version imprimeur (sans couverture ni quatrième) : ` +
        `dos de ${String(Couverture.dosPumbo(pages)).replace(".", ",")} mm (barème Pumbo), repris par la couverture.`,
    };
    if (onglet && !onglet.closed) onglet.location.href = donnees.download_url;
  } catch (erreur) {
    console.error("[carnet] échec", erreur);
    etat.carnetStatut = { type: "erreur", texte: `Le carnet n'a pas pu être généré : ${messageLisible(erreur, statut)}` };
    if (onglet && !onglet.closed) onglet.close();
  } finally {
    bouton.disabled = false;
    bouton.replaceChildren(...contenu);
    rendreResultatPdf();
  }
}

/** Sous les boutons de l'en-tête : l'avancement, l'erreur, ou le lien vers le dernier PDF. */
function rendreResultatPdf() {
  let zone = $("resultat-carnet");
  if (!zone) {
    zone = h("p", { class: "resultat-carnet", id: "resultat-carnet", role: "status", "aria-live": "polite" });
    $("champs-carnet").before(zone);
  }
  zone.replaceChildren();
  zone.classList.toggle("erreur", etat.carnetStatut?.type === "erreur");
  zone.hidden = !etat.pdf && !etat.carnetStatut;
  if (etat.carnetStatut) {
    zone.append(etat.carnetStatut.texte);
    return;
  }
  if (!etat.pdf) return;
  zone.append(
    "Carnet généré à ",
    etat.pdf.quand.toLocaleTimeString("fr-FR"),
    ", ",
    h("a", { href: etat.pdf.url, target: "_blank", rel: "noopener" }, "ouvrir le PDF"),
  );
}

/**
 * Le gabarit tel que GitHub le sert, branche `main`. `raw.githubusercontent.com`
 * répond avec des en-têtes CORS permissifs : pas besoin de passer par un
 * serveur pour le lire depuis le navigateur.
 */
const GITHUB_TEMPLATE_BASE =
  "https://raw.githubusercontent.com/hugo-jouffre/memo-book/main/MemoBook%20Generator/templates/travel-journal";

async function recupererFichierTemplate(nom) {
  const reponse = await fetch(`${GITHUB_TEMPLATE_BASE}/${nom}`, { cache: "no-store" });
  if (!reponse.ok) throw new Error(`${nom} : GitHub a répondu HTTP ${reponse.status}`);
  return reponse.text();
}

/**
 * Pousse le gabarit de `MemoBook Generator/templates/travel-journal/` (sur
 * GitHub, branche main) vers APITemplate via `POST /update-template`, pour
 * que le rendu utilise exactement ces fichiers-là au lieu d'une version
 * éditée à la main dans leur tableau de bord.
 *
 * Appelé **avant chaque génération du carnet**, et bloquant : un carnet rendu
 * sur un gabarit périmé se trompe sans le dire. Même logique que
 * `.github/workflows/sync-apitemplate.yml`, qui fait ce même appel côté CI —
 * mais celui-ci est gardé par un secret GitHub qui n'est pas toujours posé.
 *
 * `css` est la concaténation de `fonts.css` puis `style.css`, dans cet ordre
 * — comme `loadTemplateCss()` côté back-end. Envoyer `style.css` seul ferait
 * perdre toutes les polices, sans la moindre erreur visible.
 */
async function synchroniserTemplate({ cle, templateId, statut = () => {} }) {
  statut("Synchronisation du gabarit : récupération sur GitHub…");
  const [html, style, fonts] = await Promise.all([
    recupererFichierTemplate("index.html"),
    recupererFichierTemplate("style.css"),
    recupererFichierTemplate("fonts.css"),
  ]);

  statut("Synchronisation du gabarit : envoi à APITemplate…");
  const base = (etat.reglages.baseApitemplate || "https://rest-de.apitemplate.io/v2").replace(/\/$/, "");
  // Le template d'aperçu, puis celui de la version imprimeur s'il existe :
  // les deux portent toujours le même gabarit, seule leur feuille diffère.
  const cibles = [templateId, templateImprimeur()].filter(Boolean);
  for (const cible of cibles) {
    const reponse = await fetch(`${base}/update-template`, {
      method: "POST",
      headers: { "content-type": "application/json", "X-API-KEY": cle },
      body: JSON.stringify({ template_id: cible, body: html, css: `${fonts}\n${style}` }),
    });
    const donnees = await reponse.json().catch(() => null);
    // Ce point de terminaison ne renvoie pas de champ `status` : le 2xx fait foi,
    // exactement comme le vérifie déjà le workflow de synchronisation.
    if (!reponse.ok) {
      throw new Error(donnees?.message || `APITemplate a refusé la mise à jour de ${cible} (HTTP ${reponse.status})`);
    }
  }
  const quand = new Date().toLocaleTimeString("fr-FR");
  Journal.succes("atelier", `Gabarit synchronisé avec APITemplate (${cibles.join(", ")})`);
  const aide = $("statut-template");
  if (aide) aide.textContent = `Gabarit synchronisé avec APITemplate à ${quand} (${cibles.length} template${cibles.length > 1 ? "s" : ""}).`;
}

/* ---------------------------------------- sauvegarde et reprise du travail --- */

/**
 * Tout ce qu'il faut pour reprendre exactement où on en était. Les clés d'API
 * en sont **volontairement absentes** : ce fichier a vocation à circuler, pas
 * elles. Les vocaux non plus — seul leur texte compte à ce stade, et les
 * embarquer ferait un fichier de plusieurs dizaines de mégaoctets.
 */
function construireAvancement() {
  return JSON.stringify(
    {
      format: "memobook-generator",
      version: 1,
      enregistreLe: new Date().toISOString(),
      carnet: etat.carnet,
      carnetManuel: etat.carnetManuel,
      carnetDeduit: etat.carnetDeduit,
      rencontres: etat.rencontres,
      texteGroupe: etat.texteGroupe,
      couverture: etat.couverture.textes,
      couvertureStyle: {
        style: etat.couverture.style,
        textes: etat.couverture.textesStyle,
        images: etat.couverture.images,
        photosDessin: etat.couverture.photosDessin,
      },
      etapes: etat.etapes.map((e) => ({
        ...e,
        souvenirs: e.souvenirs.map(({ audioUrl, fichier, ...reste }) => reste),
      })),
    },
    null,
    2,
  );
}

async function sauvegarderAvancement(bouton) {
  bouton.disabled = true;
  try {
    await enregistrerFichier(
      construireAvancement(),
      nomDeFichier("memobook.json"),
      "application/json",
      "Avancement MemoBook",
    );
  } catch (erreur) {
    etat.erreur = `La sauvegarde a échoué : ${erreur.message}`;
    rendreColonne();
  } finally {
    bouton.disabled = false;
  }
}

async function ouvrirAvancement(fichier) {
  if (!fichier) return;
  try {
    const lu = JSON.parse(await fichier.text());
    if (lu.format !== "memobook-generator") {
      throw new Error("ce fichier n'est pas un avancement MemoBook");
    }
    // Les défauts d'abord : un réglage absent du fichier ne garde pas la
    // valeur de la session en cours.
    etat.carnet = migrerFormatPages({ ...CARNET_DEFAUT, ...(lu.carnet || {}) });
    etat.carnetManuel = lu.carnetManuel || {};
    etat.carnetDeduit = lu.carnetDeduit || {};
    etat.rencontres = lu.rencontres || [];
    etat.texteGroupe = lu.texteGroupe || "";
    etat.couverture.textes = lu.couverture || {};
    etat.couverture.style = lu.couvertureStyle?.style || "default";
    etat.couverture.textesStyle = lu.couvertureStyle?.textes || {};
    etat.couverture.images = lu.couvertureStyle?.images || {};
    etat.couverture.photosDessin = lu.couvertureStyle?.photosDessin || {};
    etat.etapes = (lu.etapes || []).map((e) => ({
      ...e,
      souvenirs: (e.souvenirs || []).map((s) => ({ ...s, audioUrl: null, fichier: null })),
      photos: e.photos || [],
    }));
    etat.erreur = "";
    etat.info = `Avancement repris : ${etat.etapes.length} étape(s). Le texte est là ; les vocaux ne sont plus écoutables.`;
    rendreChampsCarnet();
    rendreGroupe();
    apresChangement();
  } catch (erreur) {
    etat.erreur = `Fichier illisible : ${erreur.message}`;
    rendreColonne();
  }
}

/* ------------------------------------------------------- glisser-déposer --- */

function debutGlisser(ev, genre, itemId, deId) {
  ev.dataTransfer.setData("text/plain", JSON.stringify({ genre, itemId, deId }));
  ev.dataTransfer.effectAllowed = "move";
}

function zoneDepot(element, versId) {
  element.addEventListener("dragover", (ev) => {
    ev.preventDefault();
    element.classList.add("survol");
  });
  element.addEventListener("dragleave", () => element.classList.remove("survol"));
  element.addEventListener("drop", (ev) => {
    ev.preventDefault();
    element.classList.remove("survol");
    try {
      const { genre, itemId, deId } = JSON.parse(ev.dataTransfer.getData("text/plain"));
      deplacer(genre, itemId, deId, versId);
    } catch {
      /* dépôt non reconnu */
    }
  });
  return element;
}

function zoneFichiers(element, surFichiers) {
  element.addEventListener("dragover", (ev) => {
    ev.preventDefault();
    element.classList.add("survol");
  });
  element.addEventListener("dragleave", () => element.classList.remove("survol"));
  element.addEventListener("drop", (ev) => {
    ev.preventDefault();
    element.classList.remove("survol");
    surFichiers(ev.dataTransfer.files);
  });
  return element;
}

/* ------------------------------------------------------------ composants --- */

function champ({ label, valeur, surSaisie, placeholder, type = "text", puce }) {
  return h(
    "label",
    { class: "champ" },
    h(
      "span",
      {},
      label,
      puce && h("span", { class: "puce-ia", title: "Déduit par l'IA" }, "✦"),
    ),
    h("input", {
      type,
      value: valeur ?? "",
      placeholder: placeholder || "",
      oninput: (ev) => surSaisie(ev.target.value),
    }),
  );
}

function bouton(texte, options = {}) {
  const classes = ["btn"];
  if (options.petit) classes.push("btn-petit");
  if (options.icone) classes.push("btn-icone");
  if (options.ton === "solide") classes.push("btn-solide");
  if (options.ton === "lime") classes.push("btn-lime");
  if (options.ton === "danger") classes.push("btn-danger");
  return h(
    "button",
    {
      class: classes.join(" "),
      title: options.titre || "",
      disabled: Boolean(options.desactive),
      onclick: options.surClic,
      id: options.id,
    },
    texte,
  );
}

/** Une boîte repliable, dont l'état d'ouverture survit au rechargement. */
function boite(cle, titre, { ouverteParDefaut = true } = {}) {
  const ouverte = etat.boites[cle] ?? ouverteParDefaut;
  const badge = h("span", { class: "badge", hidden: true });
  const section = h(
    "section",
    { class: `carte boite${ouverte ? " ouverte" : ""}` },
    h(
      "button",
      {
        class: "tete-boite",
        onclick: () => {
          section.classList.toggle("ouverte");
          etat.boites[cle] = section.classList.contains("ouverte");
          try {
            localStorage.setItem("atelier-boites", JSON.stringify(etat.boites));
          } catch {
            /* pas grave : la boîte s'ouvrira comme avant au prochain lancement */
          }
        },
      },
      h("h2", {}, titre),
      badge,
      h("span", { class: "chevron" }, "▶"),
    ),
    h("div", { class: "contenu" }),
  );
  section.badge = badge;
  section.contenu = section.querySelector(".contenu");
  return section;
}

function majBadge(section, texte, actif) {
  if (!section) return;
  section.badge.hidden = !texte;
  section.badge.textContent = texte || "";
  section.badge.classList.toggle("actif", Boolean(actif));
}

function listeZones(saufId) {
  return etat.etapes
    .map((e, i) => ({ id: e.id, label: `${i + 1}. ${e.titre || e.lieu || "Étape sans titre"}` }))
    .filter((z) => z.id !== saufId);
}

function selecteurDeplacement(genre, itemId, conteneurId) {
  const zones = listeZones(conteneurId);
  const select = h(
    "select",
    {
      disabled: !zones.length,
      onchange: (ev) => {
        if (ev.target.value) deplacer(genre, itemId, conteneurId, ev.target.value);
      },
    },
    h("option", { value: "" }, "Déplacer"),
    zones.map((z) => h("option", { value: z.id }, z.label)),
  );
  select.value = "";
  return select;
}

/**
 * Le menu qui associe une photo à son étape. Contrairement à
 * `selecteurDeplacement`, il affiche l'étape actuelle (ou « En attente ») au
 * lieu de revenir à un intitulé neutre : c'est une affectation, pas un geste
 * ponctuel.
 */
function selecteurEtapePhoto(photoId, etapeIdActuelle) {
  const select = h(
    "select",
    {
      title: "Étape associée à cette photo",
      onchange: (ev) => deplacer("photos", photoId, etapeIdActuelle, ev.target.value || null),
    },
    h("option", { value: "" }, "En attente"),
    etat.etapes.map((e, i) =>
      h("option", { value: e.id }, `${i + 1}. ${e.titre || e.lieu || "Étape sans titre"}`),
    ),
  );
  select.value = etapeIdActuelle || "";
  return select;
}

function carteSouvenir(s, conteneurId) {
  return h(
    "div",
    {
      class: "souvenir",
      draggable: true,
      ondragstart: (ev) => debutGlisser(ev, "souvenirs", s.id, conteneurId),
    },
    h(
      "div",
      { class: "souvenir-meta" },
      h("span", { class: "poignee" }, "⠿"),
      s.auteur && h("span", {}, s.auteur),
      s.date && h("span", {}, s.date),
      s.heure && h("span", {}, s.heure),
      s.audioNom && h("span", { class: "etiquette etiquette-fichier" }, s.audioNom),
      s.duree ? h("span", {}, formatDuree(s.duree)) : null,
      h(
        "span",
        { class: "fin" },
        selecteurDeplacement("souvenirs", s.id, conteneurId),
        h(
          "button",
          {
            class: "icone-supprimer",
            title: "Supprimer ce souvenir",
            onclick: () => retirer("souvenirs", s.id, conteneurId),
          },
          "×",
        ),
      ),
    ),
    s.audioUrl ? h("audio", { controls: true, src: s.audioUrl }) : null,
    h("textarea", {
      value: s.texte,
      rows: Math.min(14, Math.max(2, Math.ceil((s.texte.length || 0) / 70))),
      oninput: (ev) => {
        // Pas de rendu ici : le DOM affiche déjà la frappe, et re-rendre
        // volerait le curseur au milieu d'une phrase.
        modifier("souvenirs", s.id, conteneurId, { texte: ev.target.value });
        majStats();
        marquerGroupePerime();
      },
    }),
  );
}

function cartePhoto(p, conteneurId) {
  return h(
    "div",
    {
      class: "photo",
      draggable: true,
      ondragstart: (ev) => debutGlisser(ev, "photos", p.id, conteneurId),
    },
    h(
      "div",
      { class: "vignette" },
      p.data
        ? h("img", { src: p.data, alt: p.nomFichier, draggable: false })
        : h("span", { class: "vide" }, p.nomFichier || "photo manquante"),
    ),
    h(
      "div",
      { class: "bas" },
      p.date &&
        h(
          "span",
          { class: "date-photo", title: `Date lue dans : ${p.dateSource || "inconnu"}` },
          p.heure ? `${p.date} · ${p.heure}` : p.date,
          p.dateSource === "métadonnée" ? " ~" : "",
        ),
      h("input", {
        value: p.legende,
        placeholder: "Étiquette sur la photo (sinon l'IA)",
        maxlength: 30,
        title:
          "Le titre posé sur la photo dans le carnet (« Rizières de Banaue »), 30 signes au plus. " +
          "Une seule étiquette par double page : celle du voyageur passe avant celles de l'IA.",
        oninput: (ev) => modifier("photos", p.id, conteneurId, { legende: ev.target.value }),
      }),
      h(
        "label",
        {
          class: "case-groupe",
          title:
            "Une photo de groupe n'est jamais rognée dans le carnet : elle est seulement réduite, " +
            "pour que personne ne sorte du cadre.",
        },
        h("input", {
          type: "checkbox",
          checked: Boolean(p.groupe),
          onchange: (ev) => modifier("photos", p.id, conteneurId, { groupe: ev.target.checked }),
        }),
        " Photo de groupe, ne pas rogner",
      ),
      h(
        "div",
        { class: "rangee" },
        selecteurEtapePhoto(p.id, conteneurId),
        h(
          "button",
          {
            class: `etoile-couverture${p.couverture ? " active" : ""}`,
            title: p.couverture
              ? "Photo de couverture — cliquer pour revenir au choix automatique"
              : "Mettre cette photo en couverture (sinon, l'atelier choisit la plus adaptée)",
            onclick: () => designerCouverture(p.id),
          },
          p.couverture ? "★" : "☆",
        ),
        h(
          "button",
          {
            class: "icone-supprimer",
            title: "Retirer cette photo",
            onclick: () => retirer("photos", p.id, conteneurId),
          },
          "×",
        ),
      ),
    ),
  );
}

/* -------------------------------------------------------------- colonne --- */

let boiteReglages;
let boiteVocaux;
let boitePhotos;
let boiteWhatsapp;

function rendreColonne() {
  const sansCle = !etat.reglages.cleOpenai && !etat.config?.cleServeur?.openai;
  boiteReglages = boite("reglages", "Clés et réglages", { ouverteParDefaut: sansCle });
  boiteVocaux = boite("vocaux", "Messages vocaux");
  boitePhotos = boite("photos", "Photos");
  boiteWhatsapp = boite("whatsapp", "Messages WhatsApp", { ouverteParDefaut: false });

  remplir("colonne", boiteVocaux, boitePhotos, boiteWhatsapp, boiteReglages);

  rendreReglages();
  rendreBoiteVocaux();
  rendreBoitePhotos();
  majBoiteWhatsapp();
}

/** Un champ de clé, avec son œil pour l'afficher ou la masquer. */
function champSecret(input) {
  const oeil = h(
    "button",
    {
      type: "button",
      class: "oeil",
      title: "Afficher la clé",
      "aria-label": "Afficher la clé",
      onclick: () => {
        const cache = input.type === "password";
        input.type = cache ? "text" : "password";
        oeil.title = cache ? "Masquer la clé" : "Afficher la clé";
        oeil.setAttribute("aria-label", oeil.title);
        oeil.replaceChildren(icone(cache ? "oeilBarre" : "oeil"));
      },
    },
    icone("oeil"),
  );
  return h("span", { class: "champ-secret" }, input, oeil);
}

function rendreReglages() {
  const r = etat.reglages;
  // `change` en plus d'`input` : un gestionnaire de mots de passe qui remplit
  // le champ ne déclenche pas toujours le second.
  const enregistrer = (nom) => (ev) => {
    if (r[nom] === ev.target.value) return;
    r[nom] = ev.target.value;
    sauverReglages();
  };

  const champCle = h("input", {
    type: "password",
    value: r.cleOpenai,
    placeholder: "sk-…",
    autocomplete: "off",
    spellcheck: false,
    oninput: (ev) => {
      enregistrer("cleOpenai")(ev);
      majBoiteVocaux();
    },
    onchange: enregistrer("cleOpenai"),
  });

  const champCleApitemplate = h("input", {
    type: "password",
    value: r.cleApitemplate,
    placeholder: "clé APITemplate",
    autocomplete: "off",
    spellcheck: false,
    oninput: enregistrer("cleApitemplate"),
    onchange: enregistrer("cleApitemplate"),
  });

  const champCleAnthropic = h("input", {
    type: "password",
    value: r.cleAnthropic,
    placeholder: "sk-ant-…",
    autocomplete: "off",
    spellcheck: false,
    oninput: enregistrer("cleAnthropic"),
    onchange: enregistrer("cleAnthropic"),
  });

  const blocAnthropic = h(
    "label",
    { class: "champ", hidden: r.fournisseurDecoupage !== "anthropic" },
    h("span", {}, "Clé API Anthropic"),
    champSecret(champCleAnthropic),
  );

  const champModele = h("input", {
    value: r.modeleDecoupage,
    oninput: enregistrer("modeleDecoupage"),
  });

  const selectFournisseur = h(
    "select",
    {
      onchange: (ev) => {
        r.fournisseurDecoupage = ev.target.value;
        r.modeleDecoupage = MODELE_PAR_FOURNISSEUR[ev.target.value] || "";
        champModele.value = r.modeleDecoupage;
        sauverReglages();
        blocAnthropic.hidden = ev.target.value !== "anthropic";
      },
    },
    h("option", { value: "openai" }, "OpenAI (même clé)"),
    h("option", { value: "anthropic" }, "Anthropic (comme le pipeline)"),
  );
  selectFournisseur.value = r.fournisseurDecoupage;

  const selectModeleTranscription = h(
    "select",
    { onchange: enregistrer("modeleTranscription") },
    h("option", { value: "gpt-4o-transcribe" }, "gpt-4o-transcribe (défaut)"),
    h("option", { value: "gpt-4o-mini-transcribe" }, "gpt-4o-mini-transcribe (moitié prix)"),
    h("option", { value: "whisper-1" }, "whisper-1 (horodatages)"),
  );
  selectModeleTranscription.value = r.modeleTranscription;

  const surServeur = etat.config?.cleServeur?.openai;

  remplir(
    boiteReglages.contenu,
    h("label", { class: "champ" }, h("span", {}, "Clé API OpenAI"), champSecret(champCle)),
    h(
      "label",
      { class: "champ", style: { marginTop: "0.5rem" } },
      h("span", {}, "Clé API APITemplate"),
      champSecret(champCleApitemplate),
    ),
    champ({
      label: "Identifiant du template",
      valeur: r.templateApitemplate,
      placeholder: "7a177b23210099d6",
      surSaisie: (v) => {
        r.templateApitemplate = v;
        sauverReglages();
      },
    }),
    champ({
      label: "Template imprimeur (fond perdu 3 mm)",
      valeur: r.templateApitemplateImprimeur,
      placeholder: "copie du template, feuille 154 × 216 mm",
      surSaisie: (v) => {
        r.templateApitemplateImprimeur = v;
        sauverReglages();
      },
    }),
    h(
      "p",
      { class: "aide", id: "statut-template" },
      "Le gabarit (templates/travel-journal, branche main sur GitHub) est poussé vers APITemplate avant chaque génération du carnet.",
    ),
    h(
      "label",
      { class: "champ", style: { marginTop: "0.5rem" } },
      h("span", {}, "Fiche couverture Pumbo (.jsx)"),
      h("input", {
        type: "file",
        accept: ".jsx,.js,.txt",
        onchange: (ev) => importerFichePumbo(ev.target.files?.[0]),
      }),
    ),
    h(
      "p",
      { class: "aide" },
      (() => {
        const f = fichePumbo();
        return (
          `Facultatif. Donne les plats (${f.largeurPlat} × ${f.hauteurPlat} mm), le fond perdu (${f.fondPerdu} mm) ` +
          `et la zone de pliage (${f.marge} mm) de la couverture — ${f.parDefaut ? "à défaut, ceux du relié 154 × 216 mm" : f.source}. ` +
          "À n'importer que pour un autre format de livre. Le dos, lui, se calcule tout seul d'après le nombre de pages " +
          "(barème Pumbo : 8 mm jusqu'à 56 pages, puis 3 mm + 0,09 mm par page)."
        );
      })(),
    ),
    h(
      "label",
      { class: "case", style: { marginTop: "0.5rem" } },
      h("input", {
        type: "checkbox",
        checked: Boolean(r.versionImprimeur),
        onchange: (ev) => {
          r.versionImprimeur = ev.target.checked;
          sauverReglages();
        },
      }),
      " Version imprimeur : sans couverture ni quatrième (imprimées sur la couverture rigide)",
    ),
    h(
      "p",
      { class: "aide" },
      "Les clés sont retenues dans ce navigateur. ",
      etat.mode === "navigateur"
        ? "Ta clé part directement chez OpenAI : elle ne transite par aucun serveur, et ce site n'en garde rien."
        : surServeur
          ? `Champ OpenAI vide : le serveur prend la clé de ${surServeur}. Une clé collée ici passe devant.`
          : "Sans clé ici, le serveur cherche OPENAI_API_KEY dans l'environnement, .env puis backend/.env.",
    ),
    h("label", { class: "champ" }, h("span", {}, "Modèle de transcription"), selectModeleTranscription),
    champ({
      label: "Langue forcée",
      valeur: r.langue,
      placeholder: "fr",
      surSaisie: (v) => {
        r.langue = v;
        sauverReglages();
      },
    }),
    h(
      "label",
      { class: "champ" },
      h("span", {}, "Vocabulaire soufflé au modèle"),
      h("textarea", {
        rows: 2,
        value: r.vocabulaire,
        placeholder: "Cebu, Moalboal, Siquijor, Maÿlis, jeepney",
        oninput: enregistrer("vocabulaire"),
      }),
    ),
    h("label", { class: "champ" }, h("span", {}, "Découpage en étapes"), selectFournisseur),
    blocAnthropic,
    h("label", { class: "champ" }, h("span", {}, "Modèle de découpage"), champModele),
  );
}

function rendreBoiteVocaux() {
  const entree = h("input", {
    type: "file",
    accept: "audio/*,.ogg,.oga,.opus,.m4a,.amr",
    multiple: true,
    class: "cache",
    onchange: (ev) => importerAudios(ev.target.files),
  });
  const forcer = h("input", { type: "checkbox" });

  remplir(
    boiteVocaux.contenu,
    zoneFichiers(
      h(
        "div",
        { class: "depot", onclick: () => entree.click() },
        "Dépose les vocaux ici, y compris les ",
        h("br"),
        "Voice message.ogg.oga",
      ),
      importerAudios,
    ),
    entree,
    h("div", { class: "attente", id: "attente-vocaux" }),
    h(
      "div",
      { class: "rangee" },
      bouton("Transcrire", {
        petit: true,
        ton: "lime",
        id: "btn-transcrire",
        titre: "Envoie les vocaux à scripts/transcribe-whatsapp.sh, puis les classe",
        surClic: () => transcrireVocaux({ force: forcer.checked }),
      }),
      h("label", { class: "case" }, forcer, "Refaire les vocaux déjà transcrits"),
    ),
    h(
      "p",
      { class: "aide" },
      "Les « .ogg.oga » sont renommés en « .ogg » avant l'envoi. Une fois transcrit, chaque vocal est rangé tout seul dans une étape.",
    ),
    // Viser un dossier du disque demande un shell : hors du mode local, la
    // page n'a aucun moyen de lire les fichiers sans qu'on les lui donne.
    etat.mode === "local" &&
      h(
        "label",
        { class: "champ" },
        h("span", {}, "Ou un dossier déjà sur le disque"),
        h("input", {
          value: etat.reglages.dossierDisque,
          placeholder: "~/Downloads/vocaux",
          oninput: (ev) => {
            etat.reglages.dossierDisque = ev.target.value;
            sauverReglages();
            majBoiteVocaux();
          },
        }),
      ),
    etat.mode === "local" &&
      h(
        "div",
        { class: "rangee" },
        bouton("Transcrire le dossier", {
          petit: true,
          id: "btn-dossier",
          surClic: transcrireDossier,
        }),
      ),
    h("div", { class: "journal", id: "journal", hidden: true }),
  );
  majBoiteVocaux();
}

function majBoiteVocaux() {
  const liste = $("attente-vocaux");
  if (liste) {
    liste.hidden = etat.vocauxAttente.length === 0;
    remplir(
      liste,
      etat.vocauxAttente.map((v) =>
        h(
          "div",
          { class: "ligne" },
          h("span", { class: "nom", title: v.nomOrigine }, v.nom),
          v.duree ? h("span", {}, formatDuree(v.duree)) : null,
          h("span", { class: "etat" }, v.etat),
          h(
            "button",
            {
              class: "icone-supprimer",
              title: "Retirer ce vocal",
              onclick: () => {
                etat.vocauxAttente = etat.vocauxAttente.filter((x) => x.id !== v.id);
                majBoiteVocaux();
                majStats();
              },
            },
            "×",
          ),
        ),
      ),
    );
  }

  const restants = etat.vocauxAttente.filter((v) => v.etat !== "transcrit").length;
  majBadge(boiteVocaux, etat.vocauxAttente.length ? `${etat.vocauxAttente.length}` : "", restants > 0);

  const btn = $("btn-transcrire");
  if (btn) {
    btn.disabled = etat.transcriptionEnCours || etat.vocauxAttente.length === 0;
    btn.textContent = etat.transcriptionEnCours
      ? "Transcription…"
      : `Transcrire${restants ? ` (${restants})` : ""}`;
  }
  const dossier = $("btn-dossier");
  if (dossier) {
    dossier.disabled = etat.transcriptionEnCours || !etat.reglages.dossierDisque.trim();
  }
}

function majJournal() {
  const zone = $("journal");
  if (!zone) return;
  zone.hidden = etat.journal.length === 0;
  remplir(
    zone,
    etat.journal.map((l) => h("div", { class: l.canal === "err" ? "err" : "" }, l.texte)),
  );
  zone.scrollTop = zone.scrollHeight;
}

function rendreBoitePhotos() {
  const entree = h("input", {
    type: "file",
    accept: "image/*",
    multiple: true,
    class: "cache",
    onchange: (ev) => importerPhotos(ev.target.files),
  });
  remplir(
    boitePhotos.contenu,
    zoneFichiers(
      h(
        "div",
        { class: "depot", onclick: () => entree.click() },
        "Dépose les photos ici ou clique pour les choisir",
      ),
      importerPhotos,
    ),
    entree,
    h("div", { class: "grille-photos", id: "attente-photos", hidden: true }),
    h("p", { class: "aide", id: "aide-photos" }),
  );
  majBoitePhotos();
}

function majBoitePhotos() {
  const zone = $("attente-photos");
  if (zone) {
    zone.hidden = etat.photosAttente.length === 0;
    remplir(
      zone,
      etat.photosAttente.map((p) => cartePhoto(p, null)),
    );
  }
  const aide = $("aide-photos");
  if (aide) {
    aide.textContent = etat.photosAttente.length
      ? "Choisis une étape dans le menu de chaque photo, ou attends qu'une étape corresponde à sa date."
      : "Chaque photo rejoint l'étape qui couvre sa date de fichier, ou la plus proche ; le menu sur chaque photo permet de changer.";
  }
  majBadge(boitePhotos, etat.photosAttente.length ? `${etat.photosAttente.length}` : "", true);
}

function majBoiteWhatsapp() {
  const zone = h("textarea", {
    rows: 7,
    value: etat.raw,
    placeholder:
      "Colle ici la conversation exportée.\n\n[14/07/2026, 09:12] Camille : Réveil face à l'océan, on entend les mouettes depuis le lit.",
    oninput: (ev) => {
      etat.raw = ev.target.value;
      importer.disabled = !etat.raw.trim();
    },
  });
  const importer = bouton("Importer et classer", {
    petit: true,
    ton: "solide",
    desactive: !etat.raw.trim(),
    surClic: importerTexte,
  });

  remplir(
    boiteWhatsapp.contenu,
    zone,
    h("div", { class: "rangee" }, importer),
    h(
      "p",
      { class: "aide" },
      "Les horodatages sont reconnus automatiquement. Les messages rejoignent directement les étapes.",
    ),
  );
}

/* -------------------------------------------------------------- rendus --- */

function rendreChampsCarnet() {
  const poser = (nom) => (v) => {
    etat.carnet[nom] = v;
    etat.carnetManuel[nom] = true;
    etat.carnetDeduit[nom] = false;
    marquerGroupePerime();
  };
  remplir(
    "champs-carnet",
    champ({
      label: "Titre du carnet",
      valeur: etat.carnet.titre,
      placeholder: "Deux semaines au Portugal",
      puce: etat.carnetDeduit.titre,
      surSaisie: poser("titre"),
    }),
    champ({
      label: "Destination",
      valeur: etat.carnet.destination,
      placeholder: "Portugal",
      puce: etat.carnetDeduit.destination,
      surSaisie: poser("destination"),
    }),
    champ({
      label: "Départ",
      type: "date",
      valeur: etat.carnet.dateDebut,
      puce: etat.carnetDeduit.dateDebut,
      surSaisie: poser("dateDebut"),
    }),
    champ({
      label: "Retour",
      type: "date",
      valeur: etat.carnet.dateFin,
      puce: etat.carnetDeduit.dateFin,
      surSaisie: poser("dateFin"),
    }),
    champ({
      label: "Voyageurs",
      valeur: etat.carnet.voyageurs,
      placeholder: "Hugo, Clara",
      puce: etat.carnetDeduit.voyageurs,
      surSaisie: poser("voyageurs"),
    }),
    // Les réglages de la personnalisation du carnet dans l'app : les mêmes,
    // appliqués de la même façon au PDF de l'atelier et à celui de l'app
    // (`reglagesDuCarnet`, `backend/src/services/bookSettings.ts`).
    panneauPersonnalisation(),
  );
}

/**
 * Le panneau « Personnalisation » : un réglage par ligne, comme l'écran de
 * l'app. Ceux que le carnet ne sait pas encore imprimer sont là, grisés et
 * marqués « À venir » — on voit ce qui existera sans croire l'avoir réglé.
 *
 * Il se replie (Hugo, 13/10/2026 : ouvert, il prenait presque tout l'écran) :
 * fermé par défaut, sa ligne de titre résume les réglages en cours, et son
 * état ouvert ou fermé est retenu comme celui des boîtes (`etat.boites`).
 */
function resumePersonnalisation(c) {
  return [
    `${c.ratioPhotos ?? 50} % de photos`,
    c.funFacts !== false ? "fun facts" : "sans fun facts",
    c.quiz !== false ? "quiz" : "sans quiz",
    c.reglure !== false ? "pointillés" : "sans pointillés",
    (c.decorations ?? 2) ? `${c.decorations ?? 2} sticker(s) par étape` : "sans décor",
    c.zonesLibres !== false ? "zones libres" : null,
    `${pagesDuFormat(c)} pages visées`,
  ]
    .filter(Boolean)
    .join(" · ");
}

function panneauPersonnalisation() {
  const c = etat.carnet;
  let resume;
  const poser = (cle, conv = (v) => v) => (ev) => {
    c[cle] = conv(ev.target.type === "checkbox" ? ev.target.checked : ev.target.value);
    resume.textContent = resumePersonnalisation(c);
  };
  const ligne = (libelle, controle, aide) =>
    h("div", { class: "perso-ligne" }, h("label", {}, libelle, " ", controle), aide ? h("p", { class: "aide" }, aide) : null);
  const aVenir = (libelle, aide) =>
    h(
      "div",
      { class: "perso-ligne a-venir", title: "Pas encore imprimé dans le carnet" },
      h("label", {}, h("input", { type: "checkbox", disabled: true }), " ", libelle, h("span", { class: "pastille-a-venir" }, "À venir")),
      aide ? h("p", { class: "aide" }, aide) : null,
    );
  const options = (valeurs, actuelle, libelle = (v) => String(v)) =>
    valeurs.map((v) => h("option", { value: String(v), selected: String(actuelle) === String(v) }, libelle(v)));

  resume = h("span", { class: "perso-resume" }, resumePersonnalisation(c));
  return h(
    "details",
    {
      class: "perso",
      style: { gridColumn: "1 / -1" },
      open: etat.boites.perso === true,
      ontoggle: (ev) => {
        etat.boites.perso = ev.target.open;
        try {
          localStorage.setItem("atelier-boites", JSON.stringify(etat.boites));
        } catch {
          /* pas grave : le panneau s'ouvrira fermé au prochain lancement */
        }
      },
    },
    h("summary", {}, h("span", { class: "perso-titre" }, "Personnalisation du carnet"), resume),
    ligne(
      "Typographies",
      h(
        "select",
        {},
        h("option", { selected: true }, "Carnet de voyage — Playfair Display · Gloria Hallelujah"),
        h("option", { disabled: true }, "Éditorial — à venir"),
        h("option", { disabled: true }, "Manuscrit — à venir"),
      ),
      "Les sous-titres restent en Gloria Hallelujah tant que la licence de Hansley n'est pas vérifiée.",
    ),
    ligne(
      "Ratio photo / texte",
      h("select", { onchange: poser("ratioPhotos", Number) }, options([0, 25, 50, 75, 100], c.ratioPhotos ?? 50, (v) => `${v} % de photos`)),
      "La part de surface qu'occupent les photos, sur l'ensemble des pages d'une étape. 0 % : aucune photo. 100 % : aucun récit imprimé — bandeau, fun facts et légendes. C'est le nombre de photos et de pages qui s'adapte, jamais ton texte.",
    ),
    ligne(
      "Fun facts",
      h("input", { type: "checkbox", checked: c.funFacts !== false, onchange: poser("funFacts") }),
      "Un encart tiré du récit, à peu près une page sur trois — dans la page, ou à la place d'une photo quand la page en a un emplacement libre —, et seulement quand il en vaut la peine.",
    ),
    ligne(
      "Pointillés",
      h("input", { type: "checkbox", checked: c.reglure !== false, onchange: poser("reglure") }),
      "La réglure sous le récit.",
    ),
    ligne(
      "Décorations & stickers",
      h("select", { onchange: poser("decorations", Number) }, options([0, 1, 2, 3, 4], c.decorations ?? 2, (v) => (v ? `${v} par étape` : "Aucune"))),
      "Le nombre de stickers de chaque étape, répartis sur ses pages, jamais sur le récit. À 0, ni tracé pointillé ni sticker ; le scotch des photos reste. Les stickers viennent de la bibliothèque dessinée.",
    ),
    ligne(
      "Zones libres",
      h("input", { type: "checkbox", checked: c.zonesLibres !== false, onchange: poser("zonesLibres") }),
      "Trois pages réglées en fin de carnet, pour écrire à la main.",
    ),
    (() => {
      const jours = joursDuVoyage(c);
      const perso = h("input", {
        type: "number",
        min: PAGES_PERSO.min,
        max: PAGES_PERSO.max,
        step: PAGES_PERSO.pas,
        value: pagesDuFormat(c, "perso"),
        hidden: c.formatPages !== "perso",
        style: { width: "5.5em" },
        onchange: (ev) => {
          const n = Math.round(Number(ev.target.value) / PAGES_PERSO.pas) * PAGES_PERSO.pas;
          c.pagesCible = Math.min(Math.max(n || PAGES_PERSO.defaut, PAGES_PERSO.min), PAGES_PERSO.max);
          ev.target.value = c.pagesCible;
          resume.textContent = resumePersonnalisation(c);
        },
      });
      const choix = h(
        "select",
        {
          onchange: (ev) => {
            c.formatPages = ev.target.value;
            if (c.formatPages === "perso" && !(Number(c.pagesCible) > 0)) c.pagesCible = pagesDuFormat(c, "standard");
            perso.value = pagesDuFormat(c, "perso");
            perso.hidden = c.formatPages !== "perso";
            resume.textContent = resumePersonnalisation(c);
          },
        },
        Object.entries(FORMATS_PAGES).map(([cle, f]) =>
          h("option", { value: cle, selected: (c.formatPages || "standard") === cle }, `${f.libelle} — ${pagesDuFormat(c, cle)} pages`),
        ),
        h("option", { value: "perso", selected: c.formatPages === "perso" }, "Personnalisé"),
      );
      return ligne(
        "Nombre de pages",
        h("span", { class: "rangee", style: { display: "inline-flex" } }, choix, perso),
        `${
          jours
            ? `D'après la durée du voyage (${jours} jour${jours > 1 ? "s" : ""}), comme dans l'app.`
            : "Sans date de retour, l'app propose 40, 60 ou 80 pages."
        } Le carnet entier, colophon compris, tient dans la cible à ± 5 pages : la mise en page ajoute ou retire des planches de photos, sans jamais toucher au récit ni au nombre de photos du ratio. Hors d'atteinte — pas assez de photos, ou trop de récit —, le journal le dit.`,
      );
    })(),
    ligne(
      "Quiz intégrés à l'histoire",
      h("input", { type: "checkbox", checked: c.quiz !== false, onchange: poser("quiz") }),
      "Une question sur ton voyage, trois réponses et la bonne imprimée à l'envers — environ une étape sur trois, sur une page sans photo en bas. Écrite par l'IA d'après ton récit ou un fait sûr du lieu, jamais inventée.",
    ),
    aVenir("Mot fléché à la fin du livre"),
  );
}

function rendreEtapes() {
  const zone = $("zone-etapes");
  zone.replaceChildren();

  if (!etat.etapes.length) {
    zone.append(
      h(
        "div",
        { class: "vide-etapes" },
        h(
          "p",
          {},
          etat.classementEnCours
            ? "Lecture du récit en cours…"
            : "Aucune étape pour l'instant. Dépose des vocaux et transcris-les : ils se rangeront tout seuls.",
        ),
        bouton("Ajouter une étape", { ton: "solide", surClic: ajouterEtape }),
      ),
    );
    return;
  }

  etat.etapes.forEach((e, i) => {
    const poser = (nom) => (v) => {
      e[nom] = v;
      e.manuel = { ...e.manuel, [nom]: true };
      marquerGroupePerime();
    };
    const section = h(
      "section",
      { class: "carte simple" },
      h(
        "div",
        { class: "etape-tete" },
        h("div", { class: "pastille" }, String(i + 1)),
        h(
          "div",
          { class: "etape-champs" },
          champ({
            label: "Titre de l'étape",
            valeur: e.titre,
            placeholder: "Premiers pas à Lisbonne",
            puce: !e.manuel?.titre && e.titre,
            surSaisie: poser("titre"),
          }),
          champ({
            label: "Lieu",
            valeur: e.lieu,
            placeholder: "Lisbonne",
            puce: !e.manuel?.lieu && e.lieu,
            surSaisie: poser("lieu"),
          }),
          champ({ label: "Du", type: "date", valeur: e.dateDebut, surSaisie: poser("dateDebut") }),
          champ({ label: "Au", type: "date", valeur: e.dateFin, surSaisie: poser("dateFin") }),
        ),
        h(
          "div",
          { class: "etape-outils" },
          bouton(icone("monter"), {
            petit: true,
            icone: true,
            titre: "Monter cette étape",
            surClic: () => deplacerEtape(e.id, -1),
          }),
          bouton(icone("descendre"), {
            petit: true,
            icone: true,
            titre: "Descendre cette étape",
            surClic: () => deplacerEtape(e.id, 1),
          }),
          bouton(icone("dupliquer"), {
            petit: true,
            icone: true,
            titre: "Dupliquer cette étape, juste en dessous",
            surClic: () => dupliquerEtape(e.id),
          }),
          bouton(icone("supprimer"), {
            petit: true,
            icone: true,
            ton: "danger",
            titre: "Supprimer l'étape ; ses photos retournent en attente",
            surClic: () => supprimerEtape(e.id),
          }),
        ),
      ),
      e.photos.length > 0 &&
        h("div", { class: "grille-photos" }, e.photos.map((p) => cartePhoto(p, e.id))),
      h("div", { class: "pile" }, e.souvenirs.map((s) => carteSouvenir(s, e.id))),
      !e.souvenirs.length &&
        !e.photos.length &&
        h("p", { class: "aide" }, "Fais glisser ici les souvenirs et les photos de cette étape."),
    );
    zone.append(zoneDepot(section, e.id));
  });

  // Le bouton a quitté l'en-tête pour laisser la place à « Générer le carnet »,
  // mais poser une étape à la main reste utile.
  zone.append(
    h(
      "div",
      { class: "ajout-etape" },
      bouton("+ Ajouter une étape", { petit: true, surClic: ajouterEtape }),
    ),
  );
}

/** Le texte groupé n'est plus à jour : on le signale sans écraser une relecture. */
function marquerGroupePerime() {
  if (!etat.groupeModifie) {
    etat.texteGroupe = construireTexteEtapes();
    const zone = $("texte-groupe");
    if (zone && zone !== document.activeElement) zone.value = etat.texteGroupe;
  }
}

function rendreGroupe() {
  const carte = $("carte-groupe");
  carte.hidden = etat.etapes.length === 0;
  if (carte.hidden) return;

  if (!etat.groupeModifie) etat.texteGroupe = construireTexteEtapes();

  const zone = h("textarea", {
    id: "texte-groupe",
    value: etat.texteGroupe,
    spellcheck: true,
    // Ne touche qu'au strict nécessaire : reconstruire toute la carte comme
    // `rendreGroupe()` le ferait couperait le curseur au milieu de la frappe.
    oninput: (ev) => {
      etat.texteGroupe = ev.target.value;
      etat.groupeModifie = true;
      $("etat-groupe").textContent = "modifications non appliquées";
      const appliquer = $("btn-appliquer-groupe");
      if (appliquer) appliquer.disabled = false;
      if (!$("btn-annuler-groupe")) {
        $("actions-groupe")?.append(
          bouton("Annuler mes modifications", {
            id: "btn-annuler-groupe",
            surClic: () => {
              etat.groupeModifie = false;
              rendreGroupe();
            },
          }),
        );
      }
    },
  });

  remplir(
    carte,
    h(
      "div",
      { class: "contenu" },
      h(
        "div",
        { class: "groupe-tete" },
        h("h2", {}, "Étapes groupées"),
        h(
          "span",
          { class: "stats", id: "etat-groupe" },
          etat.groupeModifie
            ? "modifications non appliquées"
            : `${etat.etapes.length} étape(s) · ${nombre(etat.texteGroupe.length)} signes`,
        ),
        h(
          "span",
          { class: "fin" },
          bouton("Copier", {
            petit: true,
            surClic: () => navigator.clipboard?.writeText(etat.texteGroupe).catch(() => {}),
          }),
          bouton("Télécharger", {
            petit: true,
            surClic: () => telecharger(etat.texteGroupe, nomDeFichier("txt"), "text/plain"),
          }),
        ),
      ),
      h(
        "p",
        { class: "aide" },
        "Le carnet tel qu'il est, étape par étape. Corrige ici puis applique : les crochets « [Voice message.ogg] » rattachent chaque texte à son vocal.",
      ),
      zone,
      h(
        "div",
        { class: "rangee", id: "actions-groupe" },
        bouton("Appliquer aux étapes", {
          id: "btn-appliquer-groupe",
          ton: "lime",
          desactive: !etat.groupeModifie,
          titre: "Réécrit les étapes à partir du texte relu",
          surClic: appliquerTexteEtapes,
        }),
        bouton(etat.classementEnCours ? "Lecture du récit…" : "Redécouper avec l'IA", {
          desactive: etat.classementEnCours,
          titre: "Redemande un découpage complet au modèle",
          surClic: redecouper,
        }),
        etat.groupeModifie &&
          bouton("Annuler mes modifications", {
            id: "btn-annuler-groupe",
            surClic: () => {
              etat.groupeModifie = false;
              rendreGroupe();
            },
          }),
      ),
      etat.erreur && h("p", { class: "erreur" }, etat.erreur),
      etat.info && h("p", { class: "aide" }, etat.info),
    ),
  );
}

function rendreExport() {
  const carte = $("carte-export");
  carte.hidden = !etat.montrerExport;
  if (carte.hidden) return;

  const json = construireJson();
  const apercu = etat.avecPhotos
    ? json.replace(/("image": "data:image\/\w+;base64,)[^"]{40,}/g, "$1…tronqué à l'affichage…")
    : json;

  remplir(
    carte,
    h(
      "div",
      { class: "groupe-tete" },
      h("h2", {}, "JSON du carnet"),
      h(
        "label",
        { class: "case" },
        h("input", {
          type: "checkbox",
          checked: etat.avecPhotos,
          onchange: (ev) => {
            etat.avecPhotos = ev.target.checked;
            rendreExport();
          },
        }),
        "Inclure les images en base64",
      ),
      h("span", { class: "stats" }, `${(json.length / 1024 / 1024).toFixed(2)} Mo`),
      h(
        "span",
        { class: "fin" },
        bouton("Copier", {
          petit: true,
          surClic: () => navigator.clipboard?.writeText(json).catch(() => {}),
        }),
        bouton("Télécharger", {
          petit: true,
          ton: "solide",
          surClic: () => telecharger(json, nomDeFichier("json"), "application/json"),
        }),
      ),
    ),
    h("textarea", { readOnly: true, value: apercu }),
    h(
      "p",
      { class: "aide" },
      "L'aperçu tronque les images pour rester lisible. Le fichier téléchargé contient bien les données complètes.",
    ),
  );
}

/** Le point de passage unique après toute modification du carnet. */
function apresChangement() {
  majDatesAuto();
  rendreChampsCarnet();
  majStats();
  rendreStats();
  rendreEtapes();
  rendreGroupe();
  rendreExport();
  majBoiteVocaux();
}

/* -------------------------------------------------------------- démarrage --- */

document.addEventListener("click", (ev) => {
  const bouton = ev.target.closest("[data-action]");
  const action = bouton?.dataset.action;
  if (action === "ajouter-etape") ajouterEtape();
  if (action === "generer-json") genererJson(bouton);
  if (action === "generer-carnet") genererCarnet(bouton);
  if (action === "generer-couverture") ouvrirCouverture();
  if (action === "sauvegarder") sauvegarderAvancement(bouton);
  if (action === "ouvrir") $("fichier-avancement").click();
});

/** Les boutons à icône de l'en-tête, garnis une fois le DOM prêt. */
function garnirEntete() {
  document.querySelector('[data-action="sauvegarder"]').append(icone("sauvegarder"));
  document.querySelector('[data-action="ouvrir"]').append(icone("ouvrir"));
  $("fichier-avancement").addEventListener("change", (ev) => {
    ouvrirAvancement(ev.target.files?.[0]);
    // Remis à zéro : réouvrir le même fichier doit redéclencher l'événement.
    ev.target.value = "";
  });
  rendreResultatPdf();
}

async function demarrer() {
  // Un serveur local répond ; un hébergement statique renvoie une 404. C'est
  // la seule différence entre les deux, et elle se découvre toute seule.
  try {
    const reponse = await fetch("./api/config", { cache: "no-store" });
    etat.config = reponse.ok ? await reponse.json() : null;
  } catch {
    etat.config = null;
  }
  etat.mode = etat.config ? "local" : "navigateur";
  garnirEntete();
  rendreColonne();
  apresChangement();
}

// En local, le marqueur n'est pas remplacé : on le dit plutôt que de l'afficher.
{
  const version = document.getElementById("version");
  if (version && version.textContent.includes("VERSION")) version.textContent = "version locale";
  else if (version) version.textContent = `version ${version.textContent}`;
}

demarrer();
