#!/usr/bin/env node
/**
 * Atelier carnet — serveur local.
 *
 *   node tools/atelier/server.mjs            puis http://127.0.0.1:4173
 *   ./scripts/atelier.sh                     idem, et ouvre le navigateur
 *
 * Ce serveur existe pour trois choses que la page ne peut pas faire seule :
 *
 *  1. appeler l'API OpenAI sans exposer la clé au CORS ni au cache du
 *     navigateur ;
 *  2. écrire les vocaux sur le disque pour que `scripts/transcribe-whatsapp.sh`
 *     les transcrive — c'est bien le script du dépôt qui travaille, pas une
 *     seconde implémentation qui divergerait de lui ;
 *  3. relayer l'appel de découpage vers OpenAI ou Anthropic.
 *
 * Il écoute sur 127.0.0.1 uniquement : c'est un outil d'établi, pas un service.
 */
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { readFile, writeFile, mkdir, utimes, rm, stat } from "node:fs/promises";
import { createReadStream, existsSync } from "node:fs";
import { join, resolve, dirname, basename, extname, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { randomUUID } from "node:crypto";
import partage from "./public/partage.js";

// Le renommage des vocaux, le format du fichier groupé et la consigne de
// découpage sont partagés avec le mode navigateur : une seule copie, une seule
// vérité. Voir `public/partage.js`.
const { normaliserNomAudio, decouperTexteGroupe, extraireJson, consigneDecoupage } = partage;

const ICI = dirname(fileURLToPath(import.meta.url));
const PUBLIC = join(ICI, "public");
const RACINE = resolve(ICI, "..", "..");
const SCRIPT = join(RACINE, "scripts", "transcribe-whatsapp.sh");
const TRAVAIL = join(RACINE, ".atelier");

const DEFAUTS = {
  modeleTranscription: "gpt-4o-transcribe",
  langue: "fr",
  // Mêmes valeurs que backend/src/env.ts : l'atelier ne doit pas inventer un
  // troisième jeu de modèles à côté du pipeline et du script.
  modeleOpenai: "gpt-4o",
  modeleAnthropic: "claude-opus-5",
};

/* ------------------------------------------------------------------ clés --- */

/**
 * Même résolution que le script : variable d'environnement, puis `.env`, puis
 * `backend/.env`. Le fichier n'est jamais sourcé — un `rm -rf` glissé dans un
 * .env ne doit pas s'exécuter parce qu'on cherchait une clé.
 */
async function lireCleFichier(chemin, nom) {
  if (!existsSync(chemin)) return null;
  const contenu = await readFile(chemin, "utf8");
  const ligne = contenu
    .split(/\r?\n/)
    .find((l) => new RegExp(`^\\s*(export\\s+)?${nom}\\s*=`).test(l));
  if (!ligne) return null;
  const valeur = ligne.slice(ligne.indexOf("=") + 1).trim().replace(/^["']|["']$/g, "");
  return valeur || null;
}

async function cleServeur(nom) {
  if (process.env[nom]) return { cle: process.env[nom], source: "environnement" };
  for (const candidat of [".env", "backend/.env"]) {
    const cle = await lireCleFichier(join(RACINE, candidat), nom);
    if (cle) return { cle, source: candidat };
  }
  return { cle: null, source: null };
}

/** La clé du navigateur gagne ; sinon on retombe sur celle de la machine. */
async function resoudreCle(nom, fournieParLaPage) {
  const depuisLaPage = (fournieParLaPage || "").trim();
  if (depuisLaPage) return { cle: depuisLaPage, source: "la page" };
  return cleServeur(nom);
}

/* --------------------------------------------------------------- fichiers --- */

/**
 * Ajoute « (2) », « (3) »… avant l'extension tant que le nom est pris.
 *
 * Un fichier de même nom **et de même taille** est le même vocal redéposé :
 * on l'écrase. Sans cette exception, relancer une transcription clonerait tout
 * le dossier en « Voice message (2).ogg », et le script les transcrirait comme
 * des vocaux neufs.
 */
async function nomLibre(dossier, nom, octets) {
  const chemin = join(dossier, nom);
  const existant = await stat(chemin).catch(() => null);
  if (!existant) return nom;
  if (existant.size === octets) return nom;

  const ext = extname(nom);
  const base = nom.slice(0, nom.length - ext.length);
  for (let i = 2; ; i++) {
    const essai = `${base} (${i})${ext}`;
    const autre = await stat(join(dossier, essai)).catch(() => null);
    if (!autre || autre.size === octets) return essai;
  }
}

function developperTilde(chemin) {
  const p = String(chemin || "").trim();
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return join(homedir(), p.slice(2));
  return p;
}

function dossierSession(session) {
  // Le nom de session vient du navigateur : on n'en garde que de l'hexadécimal
  // pour qu'aucun « ../ » ne sorte de .atelier/.
  const propre = String(session || "").replace(/[^a-f0-9-]/gi, "").slice(0, 40);
  if (!propre) throw new ErreurHttp(400, "Session invalide");
  return join(TRAVAIL, "vocaux", propre);
}

/* ------------------------------------------------------------------ http --- */

class ErreurHttp extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

async function lireCorps(req, maxOctets = 64 * 1024 * 1024) {
  const morceaux = [];
  let taille = 0;
  for await (const morceau of req) {
    taille += morceau.length;
    if (taille > maxOctets) throw new ErreurHttp(413, "Fichier trop gros (64 Mo max)");
    morceaux.push(morceau);
  }
  return Buffer.concat(morceaux);
}

async function lireJson(req) {
  const corps = await lireCorps(req, 32 * 1024 * 1024);
  if (!corps.length) return {};
  try {
    return JSON.parse(corps.toString("utf8"));
  } catch {
    throw new ErreurHttp(400, "Corps JSON illisible");
  }
}

function repondreJson(res, code, donnees) {
  const corps = JSON.stringify(donnees);
  res.writeHead(code, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(corps);
}

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".ttf": "font/ttf",
  ".woff2": "font/woff2",
};

function servirStatique(res, chemin) {
  const fichier = join(PUBLIC, chemin === "/" ? "index.html" : normalize(chemin));
  if (!fichier.startsWith(PUBLIC) || !existsSync(fichier)) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("Introuvable");
    return;
  }
  res.writeHead(200, {
    "content-type": TYPES[extname(fichier)] || "application/octet-stream",
    "cache-control": "no-store",
  });
  createReadStream(fichier).pipe(res);
}

/* ----------------------------------------------------------- transcription --- */

/**
 * Dépose un vocal dans le dossier de session, sous son nom normalisé.
 *
 * La date de modification est celle du fichier d'origine : le script trie par
 * date (`--sort time`) parce que WhatsApp appelle tous les vocaux « Voice
 * message », et un tri alphabétique placerait (10) avant (2). Perdre la date à
 * l'upload casserait cet ordre — donc on la repose.
 */
async function deposerVocal(req, res, session) {
  const dossier = dossierSession(session);
  await mkdir(dossier, { recursive: true });

  const nomBrut = Buffer.from(req.headers["x-nom-fichier"] || "", "base64").toString("utf8");
  const modifieLe = Number(req.headers["x-modifie-le"] || 0);
  const octets = await lireCorps(req);
  if (!octets.length) throw new ErreurHttp(400, "Fichier vide");

  const nomNormalise = await nomLibre(dossier, normaliserNomAudio(nomBrut), octets.length);
  const cible = join(dossier, nomNormalise);

  await writeFile(cible, octets);
  if (modifieLe > 0) {
    const date = new Date(modifieLe);
    await utimes(cible, date, date);
  }

  repondreJson(res, 200, {
    nomOrigine: nomBrut,
    nom: nomNormalise,
    renomme: nomNormalise !== basename(nomBrut),
    octets: octets.length,
  });
}

/**
 * Lance `scripts/transcribe-whatsapp.sh` et renvoie sa sortie au fil de l'eau.
 *
 * Le script gère déjà le cache par vocal, les reprises, les 429 et la limite de
 * 25 Mo. Le réécrire en JavaScript aurait donné deux comportements à maintenir
 * et deux factures à débuguer.
 */
async function transcrire(req, res) {
  const corps = await lireJson(req);
  const { cle, source } = await resoudreCle("OPENAI_API_KEY", corps.cleOpenai);
  if (!cle) {
    throw new ErreurHttp(
      400,
      "Aucune clé OpenAI : colle-la dans le champ « Clé API OpenAI », ou pose OPENAI_API_KEY dans .env",
    );
  }

  const cible = corps.dossier
    ? developperTilde(corps.dossier)
    : dossierSession(corps.session);
  if (!existsSync(cible)) throw new ErreurHttp(400, `Introuvable : ${cible}`);

  await mkdir(join(TRAVAIL, "sorties"), { recursive: true });
  const sortie = join(TRAVAIL, "sorties", `${randomUUID()}.txt`);

  const args = [
    SCRIPT,
    cible,
    "--out",
    sortie,
    "--sort",
    corps.tri === "name" ? "name" : "time",
    "--model",
    corps.modele || DEFAUTS.modeleTranscription,
    "--language",
    corps.langue || DEFAUTS.langue,
  ];
  if (corps.prompt?.trim()) args.push("--prompt", corps.prompt.trim());
  if (corps.force) args.push("--force");
  if (corps.dryRun) args.push("--dry-run");

  res.writeHead(200, {
    "content-type": "application/x-ndjson; charset=utf-8",
    "cache-control": "no-store",
    "x-accel-buffering": "no",
  });
  const envoyer = (objet) => res.write(`${JSON.stringify(objet)}\n`);

  envoyer({ type: "debut", dossier: cible, cle: source, script: "scripts/transcribe-whatsapp.sh" });

  // `spawn` sans shell : un dossier nommé « ; rm -rf ~ » reste un dossier.
  const enfant = spawn("bash", args, {
    cwd: RACINE,
    env: { ...process.env, OPENAI_API_KEY: cle },
  });

  const brancher = (flux, canal) => {
    let reste = "";
    flux.setEncoding("utf8");
    flux.on("data", (morceau) => {
      const lignes = (reste + morceau).split(/\r?\n/);
      reste = lignes.pop() ?? "";
      for (const ligne of lignes) if (ligne.trim()) envoyer({ type: "ligne", canal, texte: ligne });
    });
    flux.on("end", () => {
      if (reste.trim()) envoyer({ type: "ligne", canal, texte: reste });
    });
  };
  brancher(enfant.stdout, "out");
  brancher(enfant.stderr, "err");

  const code = await new Promise((ok) => {
    enfant.on("error", (e) => {
      envoyer({ type: "ligne", canal: "err", texte: `Échec du lancement : ${e.message}` });
      ok(127);
    });
    enfant.on("close", ok);
  });

  // Le script sort en 1 dès qu'un vocal échoue, mais il a quand même écrit le
  // fichier groupé pour les autres : on rend ce qui existe.
  const texteGroupe = existsSync(sortie) ? await readFile(sortie, "utf8") : "";
  await rm(sortie, { force: true });

  envoyer({
    type: "fin",
    code,
    partiel: code !== 0 && texteGroupe.trim().length > 0,
    texteGroupe,
    blocs: decouperTexteGroupe(texteGroupe),
  });
  res.end();
}

/* ------------------------------------------------------------- découpage --- */

async function appelerAnthropic(cle, modele, consigne) {
  const reponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": cle,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: modele,
      max_tokens: 4000,
      messages: [{ role: "user", content: consigne }],
    }),
  });
  const donnees = await reponse.json();
  if (!reponse.ok) {
    throw new ErreurHttp(reponse.status, donnees?.error?.message || "Anthropic a refusé l'appel");
  }
  return donnees.content
    .filter((bloc) => bloc.type === "text")
    .map((bloc) => bloc.text)
    .join("\n");
}

async function appelerOpenai(cle, modele, consigne) {
  const base = process.env.OPENAI_API_BASE || "https://api.openai.com/v1";
  const reponse = await fetch(`${base}/chat/completions`, {
    method: "POST",
    headers: { authorization: `Bearer ${cle}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: modele,
      messages: [{ role: "user", content: consigne }],
      response_format: { type: "json_object" },
    }),
  });
  const donnees = await reponse.json();
  if (!reponse.ok) {
    throw new ErreurHttp(reponse.status, donnees?.error?.message || "OpenAI a refusé l'appel");
  }
  return donnees.choices?.[0]?.message?.content || "";
}

async function decouper(req, res) {
  const corps = await lireJson(req);
  const blocs = Array.isArray(corps.blocs) ? corps.blocs : [];
  if (blocs.length === 0) throw new ErreurHttp(400, "Aucun bloc à découper");

  const veutAnthropic = corps.fournisseur === "anthropic";
  const nomCle = veutAnthropic ? "ANTHROPIC_API_KEY" : "OPENAI_API_KEY";
  const { cle, source } = await resoudreCle(
    nomCle,
    veutAnthropic ? corps.cleAnthropic : corps.cleOpenai,
  );
  if (!cle) throw new ErreurHttp(400, `Aucune clé ${veutAnthropic ? "Anthropic" : "OpenAI"}`);

  const modele =
    corps.modele || (veutAnthropic ? DEFAUTS.modeleAnthropic : DEFAUTS.modeleOpenai);
  const consigne = consigneDecoupage(blocs, corps.indications, corps.dejaTitrees, corps.dejaConnus);
  const brut = veutAnthropic
    ? await appelerAnthropic(cle, modele, consigne)
    : await appelerOpenai(cle, modele, consigne);

  const donnees = extraireJson(brut);
  const etapes = Array.isArray(donnees) ? donnees : donnees.etapes || [];
  repondreJson(res, 200, {
    carnet: Array.isArray(donnees) ? {} : donnees.carnet || {},
    etapes,
    modele,
    cle: source,
  });
}

/* --------------------------------------------------------------- routage --- */

async function router(req, res) {
  const url = new URL(req.url, "http://127.0.0.1");
  const chemin = url.pathname;

  if (req.method === "GET" && chemin === "/api/config") {
    const openai = await cleServeur("OPENAI_API_KEY");
    const anthropic = await cleServeur("ANTHROPIC_API_KEY");
    return repondreJson(res, 200, {
      racine: RACINE,
      script: existsSync(SCRIPT) ? "scripts/transcribe-whatsapp.sh" : null,
      defauts: DEFAUTS,
      cleServeur: {
        openai: openai.source,
        anthropic: anthropic.source,
      },
    });
  }

  const depot = chemin.match(/^\/api\/vocaux\/([^/]+)$/);
  if (req.method === "POST" && depot) return deposerVocal(req, res, depot[1]);
  if (req.method === "DELETE" && depot) {
    await rm(dossierSession(depot[1]), { recursive: true, force: true });
    return repondreJson(res, 200, { efface: true });
  }

  if (req.method === "POST" && chemin === "/api/transcrire") return transcrire(req, res);
  if (req.method === "POST" && chemin === "/api/decouper") return decouper(req, res);

  if (req.method === "GET") return servirStatique(res, chemin);

  throw new ErreurHttp(405, "Méthode non gérée");
}

const serveur = createServer((req, res) => {
  router(req, res).catch((erreur) => {
    const code = erreur instanceof ErreurHttp ? erreur.code : 500;
    if (res.headersSent) {
      // Le flux NDJSON est déjà parti : on glisse l'erreur dedans.
      res.write(`${JSON.stringify({ type: "erreur", message: erreur.message })}\n`);
      res.end();
      return;
    }
    repondreJson(res, code, { erreur: erreur.message });
  });
});

const port = Number(process.argv.find((a) => a.startsWith("--port="))?.slice(7) || process.env.PORT || 4173);

serveur.listen(port, "127.0.0.1", async () => {
  const openai = await cleServeur("OPENAI_API_KEY");
  console.log(`Atelier carnet — http://127.0.0.1:${port}`);
  console.log(
    openai.source
      ? `Clé OpenAI trouvée dans ${openai.source} — le champ de la page reste prioritaire.`
      : "Aucune clé OpenAI sur la machine : colle-la dans le champ « Clé API OpenAI » de la page.",
  );
  if (!existsSync(SCRIPT)) {
    console.warn(`Attention : ${SCRIPT} est introuvable, la transcription échouera.`);
  }
});
