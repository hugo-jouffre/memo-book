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
    ...meta,
  };
}

/* ------------------------------------------------------------------- état --- */

const MODELE_PAR_FOURNISSEUR = { openai: "gpt-4o", anthropic: "claude-opus-5" };

const REGLAGES_DEFAUT = {
  cleOpenai: "",
  cleAnthropic: "",
  retenirCles: true,
  modeleTranscription: "gpt-4o-transcribe",
  langue: "fr",
  vocabulaire: "",
  fournisseurDecoupage: "openai",
  modeleDecoupage: "gpt-4o",
  dossierDisque: "",
  cleApitemplate: "",
  templateApitemplate: "7a177b23210099d6",
  baseApitemplate: "https://rest-de.apitemplate.io/v2",
};

function chargerReglages() {
  let reglages = { ...REGLAGES_DEFAUT };
  try {
    reglages = { ...reglages, ...JSON.parse(localStorage.getItem("atelier-reglages") || "{}") };
  } catch {
    /* réglages illisibles : on repart des défauts */
  }
  // Un réglage vide vaut « pas de choix », pas « champ vide » : une session
  // enregistrée avant que le modèle ait un défaut ne doit pas rester creuse.
  if (!reglages.modeleDecoupage?.trim()) {
    reglages.modeleDecoupage = MODELE_PAR_FOURNISSEUR[reglages.fournisseurDecoupage] || "gpt-4o";
  }
  return reglages;
}

function sauverReglages() {
  const aGarder = { ...etat.reglages };
  if (!aGarder.retenirCles) {
    aGarder.cleOpenai = "";
    aGarder.cleAnthropic = "";
    aGarder.cleApitemplate = "";
  }
  try {
    localStorage.setItem("atelier-reglages", JSON.stringify(aGarder));
  } catch {
    /* navigation privée : tant pis, les réglages ne survivront pas */
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
  carnet: { titre: "", destination: "", dateDebut: "", dateFin: "", voyageurs: "" },
  /** Un champ touché à la main n'est plus jamais réécrit par la déduction. */
  carnetManuel: {},
  carnetDeduit: {},
  /** Prénoms croisés en chemin, cumulés vocal après vocal. */
  rencontres: [],
  /** Dernier PDF rendu par APITemplate, pour garder le lien sous la main. */
  pdf: null,
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

/* --------------------------------------------------- déplacer et modifier --- */

const conteneur = (id) => etat.etapes.find((e) => e.id === id);

function deplacer(genre, itemId, deId, versId) {
  if (deId === versId) return;
  const source = conteneur(deId);
  const item = source?.[genre].find((x) => x.id === itemId);
  if (!item) return;
  source[genre] = source[genre].filter((x) => x.id !== itemId);
  conteneur(versId)?.[genre].push(item);
  apresChangement();
}

function modifier(genre, itemId, conteneurId, patch) {
  const item = conteneur(conteneurId)?.[genre].find((x) => x.id === itemId);
  if (item) Object.assign(item, patch);
}

function retirer(genre, itemId, conteneurId) {
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

  return {
    etapes: etat.etapes.length,
    jours,
    lieux: lieux.length,
    listeLieux: lieux,
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
    tuile(nombre(s.lieux), s.lieux > 1 ? "lieux" : "lieu", {
      detail: s.listeLieux.join(", "),
    }),
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

/** Découpe un récit en paragraphes qui tiennent dans une page du carnet. */
function enParagraphes(texte, maxSignes = 400) {
  const phrases = String(texte || "")
    .replace(/\s+/g, " ")
    .trim()
    .split(/(?<=[.!?…])\s+/)
    .filter(Boolean);
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

const enHtml = (texte) =>
  enParagraphes(texte)
    .map((t) => `<p>${echapperHtml(t)}</p>`)
    .join("");

/**
 * Choix de la mise en page, repris de la table de
 * `templates/travel-journal/LAYOUT_KB.md` : c'est elle qui dit combien de
 * photos chaque gabarit sait tenir.
 */
function layoutPour(nbPhotos, premiere) {
  if (premiere) return "layout_story_opener";
  if (nbPhotos === 0) return "layout_story_facts";
  if (nbPhotos === 1) return "layout_hero_top";
  if (nbPhotos === 2) return "layout_split_left";
  if (nbPhotos === 3) return "layout_collage";
  return "layout_photo_page";
}

const MOIS = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];

function dateLongue(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
  return m ? `${Number(m[3])} ${MOIS[Number(m[2]) - 1]} ${m[1]}` : "";
}

/**
 * Traduit l'état de l'atelier vers le contrat attendu par le template, décrit
 * par `templates/travel-journal/data.json`. Conversion **mécanique** : elle
 * n'écrit pas à la place du voyageur, elle habille son texte.
 */
function construirePayloadCarnet() {
  const toutesPhotos = etat.etapes.flatMap((e) => e.photos.map((p) => p.data).filter(Boolean));
  const dates = etat.etapes.flatMap((e) => [e.dateDebut, e.dateFin]).filter(Boolean).sort();
  const premiere = dates[0];
  const derniere = dates[dates.length - 1];

  return {
    render_profile: "preview",
    book_title: etat.carnet.titre || "Carnet de voyage",
    book_subtitle: "Un carnet de voyage raconté à l'oral",
    authors: listeVoyageurs().join(" et "),
    date_range:
      premiere && derniere && premiere !== derniere
        ? `${dateLongue(premiere)} – ${dateLongue(derniere)}`
        : dateLongue(premiere) || "",
    cover_photo: toutesPhotos[0] || "",
    brand_name: "MemoBook",
    year: String(new Date().getFullYear()),
    footer_tagline: "Racontez. Revivez. Partagez.",
    intro_text: "",
    days: etat.etapes.map((etape, index) => {
      const photos = etape.photos.map((p) => p.data).filter(Boolean);
      const recit = etape.souvenirs.map((s) => s.texte.trim()).filter(Boolean).join(" ");
      const layout = layoutPour(photos.length, index === 0);
      return {
        title: etape.titre || `Étape ${index + 1}`,
        date: dateLongue(etape.dateDebut),
        city: etape.lieu || "",
        country: etat.carnet.destination || "",
        day_intro: {
          day_number: String(index + 1).padStart(2, "0"),
          location: [etape.lieu, etat.carnet.destination].filter(Boolean).join(", "),
          date: dateLongue(etape.dateDebut),
          weather_key: "sun",
        },
        // Un seul gabarit est vrai à la fois : le template lit des booléens.
        layout_story_opener: layout === "layout_story_opener",
        layout_story_facts: layout === "layout_story_facts",
        layout_hero_top: layout === "layout_hero_top",
        layout_split_left: layout === "layout_split_left",
        layout_collage: layout === "layout_collage",
        layout_photo_page: layout === "layout_photo_page",
        opener_kicker: index === 0 ? etape.lieu || "" : "",
        opener_body_html: index === 0 ? enHtml(recit) : "",
        opener_photos: index === 0 ? photos.slice(0, 2) : [],
        body_html: enHtml(recit),
        fun_facts: [],
        highlights: etape.photos.map((p) => p.legende).filter(Boolean).slice(0, 3),
        photos,
        tag: etape.lieu || "",
      };
    }),
    back_cover: {
      closing_text: "À suivre.",
      closing_subtext: `Carnet composé avec MemoBook Generator${
        etat.rencontres.length
          ? `, ${etat.rencontres.length} rencontre${etat.rencontres.length > 1 ? "s" : ""} en chemin`
          : ""
      }.`,
      cta: "memobook.fr",
      logo_url: "",
    },
  };
}

/**
 * Envoie le carnet à APITemplate et ouvre le PDF.
 *
 * Beta assumée : la conversion vers le contrat du template est mécanique, et
 * les photos partent en base64 dans la requête — au-delà de quelques dizaines,
 * APITemplate refusera la charge. Le pipeline du back-end reste la voie
 * sérieuse ; ceci sert à voir tout de suite à quoi le carnet ressemble.
 */
async function genererCarnet(bouton) {
  if (bouton.disabled) return;
  if (!etat.etapes.length) {
    etat.erreur = "Aucune étape : il n'y a rien à mettre en page.";
    rendreColonne();
    return;
  }
  const cle = (etat.reglages.cleApitemplate || "").trim();
  if (!cle) {
    etat.erreur = "Aucune clé APITemplate : colle-la dans « Clés et réglages » pour générer le PDF.";
    etat.boites.reglages = true;
    rendreColonne();
    return;
  }

  const contenu = [...bouton.childNodes];
  bouton.disabled = true;
  bouton.textContent = "Génération en cours…";
  etat.erreur = "";
  etat.pdf = null;

  try {
    const payload = construirePayloadCarnet();
    const poids = JSON.stringify(payload).length;
    if (poids > 20 * 1024 * 1024) {
      throw new Error(
        `la charge fait ${(poids / 1024 / 1024).toFixed(1)} Mo, trop de photos en base64 pour un envoi direct`,
      );
    }

    const url = new URL(
      `${etat.reglages.baseApitemplate || "https://rest-de.apitemplate.io/v2"}/create-pdf`,
    );
    url.searchParams.set("template_id", etat.reglages.templateApitemplate || "7a177b23210099d6");

    const reponse = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", "X-API-KEY": cle },
      body: JSON.stringify(payload),
    });
    const donnees = await reponse.json().catch(() => null);

    if (!reponse.ok || donnees?.status !== "success") {
      throw new Error(donnees?.message || `APITemplate a refusé le rendu (HTTP ${reponse.status})`);
    }
    if (!donnees.download_url) {
      throw new Error("APITemplate a répondu « success » sans lien de téléchargement");
    }

    etat.pdf = { url: donnees.download_url, quand: new Date() };
    window.open(donnees.download_url, "_blank", "noopener");
  } catch (erreur) {
    etat.erreur = `Le carnet n'a pas pu être généré : ${erreur.message}`;
  } finally {
    bouton.disabled = false;
    bouton.replaceChildren(...contenu);
    rendreResultatPdf();
    rendreColonne();
  }
}

/** Le lien vers le dernier PDF rendu, sous les boutons de l'en-tête. */
function rendreResultatPdf() {
  let zone = $("resultat-carnet");
  if (!zone) {
    zone = h("p", { class: "resultat-carnet", id: "resultat-carnet" });
    $("champs-carnet").before(zone);
  }
  zone.replaceChildren();
  zone.hidden = !etat.pdf;
  if (!etat.pdf) return;
  zone.append(
    "Carnet généré à ",
    etat.pdf.quand.toLocaleTimeString("fr-FR"),
    " — ",
    h("a", { href: etat.pdf.url, target: "_blank", rel: "noopener" }, "ouvrir le PDF"),
  );
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
    etat.carnet = { ...etat.carnet, ...(lu.carnet || {}) };
    etat.carnetManuel = lu.carnetManuel || {};
    etat.carnetDeduit = lu.carnetDeduit || {};
    etat.rencontres = lu.rencontres || [];
    etat.texteGroupe = lu.texteGroupe || "";
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
        placeholder: "Légende",
        oninput: (ev) => modifier("photos", p.id, conteneurId, { legende: ev.target.value }),
      }),
      h(
        "div",
        { class: "rangee" },
        selecteurDeplacement("photos", p.id, conteneurId),
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

function rendreReglages() {
  const r = etat.reglages;
  const enregistrer = (nom) => (ev) => {
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
  });

  const champCleApitemplate = h("input", {
    type: "password",
    value: r.cleApitemplate,
    placeholder: "clé APITemplate",
    autocomplete: "off",
    spellcheck: false,
    oninput: enregistrer("cleApitemplate"),
  });

  const champCleAnthropic = h("input", {
    type: "password",
    value: r.cleAnthropic,
    placeholder: "sk-ant-…",
    autocomplete: "off",
    spellcheck: false,
    oninput: enregistrer("cleAnthropic"),
  });

  const blocAnthropic = h(
    "label",
    { class: "champ", hidden: r.fournisseurDecoupage !== "anthropic" },
    h("span", {}, "Clé API Anthropic"),
    champCleAnthropic,
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
    h("label", { class: "champ" }, h("span", {}, "Clé API OpenAI"), champCle),
    h(
      "label",
      { class: "champ", style: { marginTop: "0.5rem" } },
      h("span", {}, "Clé API APITemplate"),
      champCleApitemplate,
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
    h(
      "div",
      { class: "rangee" },
      bouton("Afficher", {
        petit: true,
        surClic: (ev) => {
          const cache = champCle.type === "password";
          champCle.type = cache ? "text" : "password";
          champCleAnthropic.type = cache ? "text" : "password";
          champCleApitemplate.type = cache ? "text" : "password";
          ev.target.textContent = cache ? "Masquer" : "Afficher";
        },
      }),
      h(
        "label",
        { class: "case" },
        h("input", {
          type: "checkbox",
          checked: r.retenirCles,
          onchange: (ev) => {
            r.retenirCles = ev.target.checked;
            sauverReglages();
          },
        }),
        "Retenir sur ce navigateur",
      ),
    ),
    h(
      "p",
      { class: "aide" },
      etat.mode === "navigateur"
        ? "Ta clé reste dans ce navigateur et part directement chez OpenAI : elle ne transite par aucun serveur, et ce site n'en garde rien."
        : surServeur
          ? `Une clé est déjà lue dans ${surServeur} : laisse le champ vide pour l'utiliser.`
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
    h("div", { class: "vignettes-attente", id: "attente-photos", hidden: true }),
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
      etat.photosAttente.map((p) =>
        p.data
          ? h("img", { src: p.data, alt: p.nomFichier, title: p.nomFichier })
          : h("span", { class: "vide" }, p.nomFichier || "photo manquante"),
      ),
    );
  }
  const aide = $("aide-photos");
  if (aide) {
    aide.textContent = etat.photosAttente.length
      ? "Ces photos attendent une étape dont la date les accueille. Crée une étape, ou fais-les glisser toi-même."
      : "Chaque photo rejoint l'étape qui couvre sa date de fichier, ou la plus proche.";
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
    oninput: (ev) => {
      etat.texteGroupe = ev.target.value;
      etat.groupeModifie = true;
      $("etat-groupe").textContent = "modifications non appliquées";
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
        { class: "rangee" },
        bouton("Appliquer aux étapes", {
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

demarrer();
