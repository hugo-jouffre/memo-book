/*
 * Moteur « navigateur » — l'atelier sans serveur, pour la version en ligne.
 *
 * En local, c'est `scripts/transcribe-whatsapp.sh` qui transcrit, et le
 * serveur qui relaie les appels de modèle. Sur un hébergement statique, il n'y
 * a ni shell ni serveur : la page appelle les APIs directement, avec la clé du
 * visiteur, qui ne quitte jamais son navigateur.
 *
 * Ce fichier réimplémente donc le strict nécessaire du script — renommage,
 * ordre, limite de 25 Mo, cache, réessais — et rien de plus. Le script reste la
 * référence : quand les deux divergent, c'est lui qui a raison.
 */
(function () {
  "use strict";

  const BASE_OPENAI = "https://api.openai.com/v1";
  const BASE_ANTHROPIC = "https://api.anthropic.com/v1";

  const attendre = (ms) => new Promise((ok) => setTimeout(ok, ms));

  function dateLisible(horodatage) {
    if (!horodatage) return "inconnue";
    const d = new Date(horodatage);
    const deuxChiffres = (n) => String(n).padStart(2, "0");
    return (
      `${d.getFullYear()}-${deuxChiffres(d.getMonth() + 1)}-${deuxChiffres(d.getDate())} ` +
      `${deuxChiffres(d.getHours())}:${deuxChiffres(d.getMinutes())}`
    );
  }

  /**
   * Trois tentatives : les 429 (débit) et les 5xx passent presque toujours au
   * deuxième essai, et une transcription à moitié perdue coûte une relance
   * complète du lot. Même politique que le script.
   */
  async function avecReessais(appel, noter) {
    let delai = 2000;
    for (let tentative = 1; tentative <= 3; tentative++) {
      const reponse = await appel();
      if (reponse.ok) return reponse;
      const recuperable = reponse.status === 429 || reponse.status >= 500;
      if (!recuperable || tentative === 3) return reponse;
      noter(`    HTTP ${reponse.status} — nouvelle tentative dans ${delai / 1000}s (${tentative}/3)`, "err");
      await attendre(delai);
      delai *= 2;
    }
    throw new Error("inatteignable");
  }

  async function messageErreur(reponse) {
    const brut = await reponse.text().catch(() => "");
    try {
      return JSON.parse(brut)?.error?.message || `HTTP ${reponse.status}`;
    } catch {
      return brut.slice(0, 200) || `HTTP ${reponse.status}`;
    }
  }

  /**
   * Transcrit une liste de vocaux et rend le fichier groupé au format du
   * script, pour que la suite de la chaîne ne sache pas qui a travaillé.
   */
  async function transcrire({ vocaux, reglages, force, noter }) {
    const cle = (reglages.cleOpenai || "").trim();
    if (!cle) throw new Error("Aucune clé OpenAI : colle-la dans le champ « Clé API OpenAI ».");

    // WhatsApp nomme tous les vocaux « Voice message » : le tri par date de
    // fichier suit l'ordre réel des téléchargements, là où l'alphabétique
    // placerait (10) avant (2). C'est le `--sort time` du script.
    const tries = [...vocaux].sort(
      (a, b) => (a.fichier?.lastModified || 0) - (b.fichier?.lastModified || 0),
    );

    noter(`${tries.length} fichier(s) audio — modèle ${reglages.modeleTranscription}, langue ${reglages.langue}, tri par date`);

    let echecs = 0;
    const pieces = [];

    for (const [index, entree] of tries.entries()) {
      const numero = `[${String(index + 1).padStart(2, "0")}/${tries.length}]`;
      const octets = entree.fichier?.size || 0;
      noter(`${numero} ${entree.nom} (${Math.round(octets / 1024)} ko, ${dateLisible(entree.fichier?.lastModified)})`);

      if (octets > globalThis.MAX_OCTETS) {
        noter(`    Ignoré : ${Math.round(octets / 1024 / 1024)} Mo dépasse la limite de 25 Mo de l'API.`, "err");
        echecs += 1;
        pieces.push({ nom: entree.nom, dateLisible: dateLisible(entree.fichier?.lastModified), texte: "" });
        continue;
      }

      // Le cache du script, en mémoire : relancer ne refacture pas ce qui est
      // déjà transcrit. Il ne survit pas au rechargement de la page, lui.
      if (entree.texte && !force) {
        noter("    Déjà transcrit, ignoré (« Refaire les transcrits » pour refaire).");
        pieces.push({ nom: entree.nom, dateLisible: dateLisible(entree.fichier?.lastModified), texte: entree.texte });
        continue;
      }

      const formulaire = new FormData();
      // C'est ici que le renommage compte : le fichier part sous « .ogg ».
      formulaire.append("file", entree.fichier, entree.nom);
      formulaire.append("model", reglages.modeleTranscription);
      formulaire.append("language", reglages.langue);
      formulaire.append("response_format", "text");
      if (reglages.vocabulaire?.trim()) formulaire.append("prompt", reglages.vocabulaire.trim());

      let reponse;
      try {
        reponse = await avecReessais(
          () =>
            fetch(`${BASE_OPENAI}/audio/transcriptions`, {
              method: "POST",
              headers: { authorization: `Bearer ${cle}` },
              body: formulaire,
            }),
          noter,
        );
      } catch (erreur) {
        noter(`    Réseau injoignable : ${erreur.message}`, "err");
        echecs += 1;
        pieces.push({ nom: entree.nom, dateLisible: dateLisible(entree.fichier?.lastModified), texte: "" });
        continue;
      }

      if (!reponse.ok) {
        noter(`    Échec : ${await messageErreur(reponse)}`, "err");
        echecs += 1;
        pieces.push({ nom: entree.nom, dateLisible: dateLisible(entree.fichier?.lastModified), texte: "" });
        continue;
      }

      const texte = (await reponse.text()).trim();
      entree.texte = texte;
      noter(`    → ${texte.length} caractères`);
      pieces.push({ nom: entree.nom, dateLisible: dateLisible(entree.fichier?.lastModified), texte });
    }

    const texteGroupe = globalThis.construireTexteGroupe(pieces, [
      `Transcriptions — ${pieces.length} fichier(s)`,
      `modèle ${reglages.modeleTranscription}, langue ${reglages.langue}, tri par date`,
      `Généré le ${dateLisible(Date.now())}`,
      "",
      "Les dates sont celles des fichiers (téléchargement WhatsApp),",
      "pas forcément celles de l'enregistrement.",
    ]);

    return {
      texteGroupe,
      blocs: globalThis.decouperTexteGroupe(texteGroupe),
      partiel: echecs > 0,
      echecs,
    };
  }

  /** Le découpage, appelé directement chez le fournisseur choisi. */
  async function decouper(corps) {
    const anthropic = corps.fournisseur === "anthropic";
    const cle = ((anthropic ? corps.cleAnthropic : corps.cleOpenai) || "").trim();
    if (!cle) throw new Error(`Aucune clé ${anthropic ? "Anthropic" : "OpenAI"}`);

    const modele = corps.modele || (anthropic ? "claude-opus-5" : "gpt-4o");
    const consigne = globalThis.consigneDecoupage(
      corps.blocs,
      corps.indications,
      corps.dejaTitrees,
      corps.dejaConnus,
    );

    const reponse = anthropic
      ? await fetch(`${BASE_ANTHROPIC}/messages`, {
          method: "POST",
          headers: {
            "x-api-key": cle,
            "anthropic-version": "2023-06-01",
            // Sans cet en-tête, l'API refuse les appels venus d'une page.
            "anthropic-dangerous-direct-browser-access": "true",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            model: modele,
            max_tokens: 4000,
            messages: [{ role: "user", content: consigne }],
          }),
        })
      : await fetch(`${BASE_OPENAI}/chat/completions`, {
          method: "POST",
          headers: { authorization: `Bearer ${cle}`, "content-type": "application/json" },
          body: JSON.stringify({
            model: modele,
            messages: [{ role: "user", content: consigne }],
            response_format: { type: "json_object" },
          }),
        });

    if (!reponse.ok) throw new Error(await messageErreur(reponse));
    const donnees = await reponse.json();
    const brut = anthropic
      ? donnees.content.filter((b) => b.type === "text").map((b) => b.text).join("\n")
      : donnees.choices?.[0]?.message?.content || "";

    const lu = globalThis.extraireJson(brut);
    return {
      carnet: Array.isArray(lu) ? {} : lu.carnet || {},
      etapes: Array.isArray(lu) ? lu : lu.etapes || [],
      modele,
      cle: "la page",
    };
  }

  globalThis.MoteurNavigateur = { transcrire, decouper };
})();
