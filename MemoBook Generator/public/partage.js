/*
 * Code partagé entre les deux façons de faire tourner l'atelier :
 *
 *  - en local, `server.mjs` l'importe (Node le lit comme un module CommonJS) ;
 *  - en ligne, la page le charge par un `<script>` avant `app.js`.
 *
 * Tout ce qui devait rester identique des deux côtés vit ici : le renommage
 * des vocaux, le format du fichier groupé, et la consigne de découpage. Deux
 * copies de la consigne auraient dérivé à la première retouche.
 */
(function (racine) {
  "use strict";

  /** Limite de l'API OpenAI : 25 Mo par fichier. */
  const MAX_OCTETS = 26214400;

  /**
   * « Voice message.ogg.oga » → « Voice message.ogg ».
   *
   * Le double suffixe vient du téléchargement WhatsApp, pas du format : le
   * fichier est de l'Opus dans un conteneur Ogg. L'API accepte les deux
   * extensions, mais un seul nom lisible évite les surprises côté modèle comme
   * côté humain qui relit le dossier.
   */
  function normaliserNomAudio(nom) {
    const propre = String(nom || "").split(/[/\\]/).pop().trim() || "vocal";
    const double = propre.match(
      /^(.*)\.(ogg|opus|m4a|mp3|wav|aac|amr|mp4|webm|flac|mpga|mpeg)\.(oga|ogg|opus)$/i,
    );
    return double ? `${double[1]}.${double[2].toLowerCase()}` : propre;
  }

  /** Découpe le fichier groupé en blocs, un par vocal. */
  function decouperTexteGroupe(texte) {
    const lignes = String(texte || "").split(/\r?\n/);
    const blocs = [];
    let courant = null;

    for (const ligne of lignes) {
      const titre = ligne.match(/^##\s+(?:(\d+)\s+—\s+)?(.*)$/);
      if (titre) {
        if (courant) blocs.push(courant);
        courant = { nom: titre[2].trim(), date: "", lignes: [] };
        continue;
      }
      if (!courant) continue; // en-tête « # … » du script
      const date = ligne.match(/^date-fichier:\s*(\d{4}-\d{2}-\d{2})/);
      if (date && !courant.date && !courant.lignes.join("").trim()) {
        courant.date = date[1];
        continue;
      }
      courant.lignes.push(ligne);
    }
    if (courant) blocs.push(courant);

    if (!blocs.length) {
      // Un vocal seul : le script écrit le texte nu, sans cérémonie de lot.
      const nu = String(texte || "").trim();
      return nu ? [{ index: 0, nom: "", date: "", texte: nu }] : [];
    }

    return blocs
      .map((bloc, index) => ({
        index,
        nom: bloc.nom,
        date: bloc.date,
        texte: bloc.lignes.join("\n").trim(),
      }))
      .filter((bloc) => bloc.texte && bloc.texte !== "(transcription manquante)");
  }

  /**
   * Reconstruit le fichier groupé au format exact du script, pour que le mode
   * navigateur et le mode local produisent le même texte relisible.
   */
  function construireTexteGroupe(pieces, entete) {
    const lignes = [];
    for (const ligne of entete || []) lignes.push(`# ${ligne}`);
    pieces.forEach((piece, i) => {
      lignes.push("", "", `## ${String(i + 1).padStart(2, "0")} — ${piece.nom}`);
      lignes.push(`date-fichier: ${piece.dateLisible || piece.date || "inconnue"}`, "");
      lignes.push(piece.texte || "(transcription manquante)");
    });
    lignes.push("");
    return lignes.join("\n");
  }

  /** Le modèle encadre parfois sa réponse malgré la consigne : on la dégage. */
  function extraireJson(texte) {
    const nu = String(texte || "").replace(/```json|```/g, "").trim();
    try {
      return JSON.parse(nu);
    } catch (erreur) {
      const debut = nu.indexOf("{");
      const fin = nu.lastIndexOf("}");
      if (debut < 0 || fin <= debut) throw new Error("Réponse du modèle illisible");
      return JSON.parse(nu.slice(debut, fin + 1));
    }
  }

  function consigneDecoupage(blocs, indications, dejaTitrees, dejaConnus) {
    const lignes = blocs
      .map(
        (b, i) =>
          `${i} | ${b.date || "date inconnue"} | ${b.nom || "message"} | ${String(b.texte || "")
            .replace(/\s+/g, " ")
            .slice(0, 1200)}`,
      )
      .join("\n");

    // Un titre écrit à la main ne se fait pas écraser par une relance : le
    // modèle le reçoit et on lui demande de le garder tel quel.
    const rappelTitres = (dejaTitrees || [])
      .filter((e) => e.titre || e.lieu)
      .map(
        (e) => `- blocs ${e.debut} à ${e.fin} : « ${e.titre || ""} »${e.lieu ? ` (${e.lieu})` : ""}`,
      )
      .join("\n");

    return `Tu découpes le récit d'un voyageur en étapes de carnet de voyage.

Une étape est une unité de récit : un moment que le voyageur raconte comme un tout. Ce peut être une journée, une traversée, une ville, une rencontre, une semaine entière sur un voyage long.

Règles de découpage :
- L'horodatage est un indice, jamais la règle. Un vocal envoyé le soir raconte souvent la journée entière. Un vocal envoyé le lendemain matin raconte souvent la veille. Un vocal de trois minutes peut couvrir trois jours.
- Coupe quand le récit change de moment, de lieu ou de séquence : « le lendemain », « après deux jours à », « on est arrivés à », un changement de ville, un trajet, un réveil.
- Regroupe les blocs qui racontent la même chose, même espacés de plusieurs heures ou envoyés le lendemain.
- Ne coupe jamais au milieu d'un récit qui se poursuit d'un bloc au suivant.
- Les segments sont contigus, sans trou ni chevauchement, et couvrent tous les indices de 0 à ${blocs.length - 1}.

Pour chaque étape, donne un titre court dans la voix du voyageur, pas un titre de guide touristique, le lieu s'il est identifiable, et les dates réellement racontées, qui ne sont pas forcément celles des fichiers.

Tu ne réécris rien : le texte du voyageur est repris tel quel plus loin dans la chaîne. Tu ne fais que le découper et le titrer.

Déduis aussi ce que tu peux du voyage dans son ensemble : un titre de carnet dans la voix du voyageur, la destination, les dates de début et de fin.

Deux listes de prénoms, à ne pas confondre :
- **voyageurs** : celles et ceux qui font le voyage. Le narrateur, et les personnes dont on parle comme d'un compagnon de route — « on a marché », « Clara a voulu », quelqu'un présent d'un bout à l'autre du récit.
- **rencontres** : les personnes croisées en chemin et nommées. L'hôte d'une chambre, un guide, une famille rencontrée sur un bateau, d'autres voyageurs. Une même personne ne compte qu'une fois, même citée dans trois étapes. Ne compte pas les gens simplement évoqués depuis la maison, ni les personnages d'une histoire racontée.

Un prénom sans certitude n'entre dans aucune des deux listes : mieux vaut un blanc qu'un nom deviné.
${
      dejaConnus
        ? `\nDéjà repérés dans les vocaux précédents, à reprendre et compléter, pas à recommencer :\nvoyageurs : ${(dejaConnus.voyageurs || []).join(", ") || "aucun"}\nrencontres : ${(dejaConnus.rencontres || []).join(", ") || "aucune"}\n`
        : ""
    }${
      rappelTitres
        ? `\nTitres déjà écrits à la main, à reprendre mot pour mot si le découpage ne change pas :\n${rappelTitres}\n`
        : ""
    }${indications ? `\nIndications du voyageur, prioritaires sur tout le reste :\n${indications}\n` : ""}
Blocs, format « indice | date | source | texte » :
${lignes}

Réponds uniquement par un objet JSON, sans texte autour et sans balises de code :
{"carnet":{"titre":"","destination":"","date_debut":"AAAA-MM-JJ","date_fin":"AAAA-MM-JJ","voyageurs":["",""],"rencontres":["",""]},
 "etapes":[{"titre":"","lieu":"","date_debut":"AAAA-MM-JJ","date_fin":"AAAA-MM-JJ","debut":0,"fin":4}]}`;
  }

  const api = {
    MAX_OCTETS,
    normaliserNomAudio,
    decouperTexteGroupe,
    construireTexteGroupe,
    extraireJson,
    consigneDecoupage,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else Object.assign(racine, api);
})(typeof globalThis !== "undefined" ? globalThis : this);
