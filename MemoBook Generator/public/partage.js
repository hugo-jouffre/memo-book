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

  /**
   * Consigne de l'analyse d'une étape, pour la mise en page du carnet.
   *
   * Le modèle reçoit le récit de l'étape découpé en paragraphes numérotés et
   * les photos de l'étape, chacune précédée de son identifiant. Il ne réécrit
   * rien et ne choisit aucun layout : il dit seulement
   *
   * - où se trouve le lieu de l'étape (pays et coordonnées), pour la carte de
   *   chapitre — `null` s'il n'en est pas sûr : une épingle au hasard se voit ;
   * - les autres lieux où le récit emmène le voyageur, pour cadrer la carte sur
   *   la zone que le voyage parcourt, et leur genre (ville, île ou site) ;
   * - les trajets racontés et leur moyen de transport, pour les tracer sur les
   *   cartes et compter les kilomètres (`voyage.js`) ;
   * - ce que vaudrait chaque photo en couverture ;
   * - quel paragraphe chaque photo illustre, pour qu'elle tombe sur la même
   *   page que le passage qui en parle ;
   * - quelles photos ont été prises au même endroit (même arrière-plan), pour
   *   qu'elles restent ensemble ;
   * - un encart (« fun fact ») tiré du récit, noté sur 10, ou rien. C'est la
   *   mise en page qui décide lesquels s'impriment : un toutes les trois pages
   *   au plus, les mieux notés d'abord.
   *
   * La mise en page reste un calcul de l'atelier (`mise-en-page.js`) : le
   * modèle décrit, il ne compose pas. Voir LAYOUT_KB § « Associer les photos au
   * récit » et § « Les fun facts — dosage et matière ».
   */
  function consigneAnalyseEtape({ lieu, destination, paragraphes, photos }) {
    const texte = (paragraphes || [])
      .map((p, i) => `[${i}] ${String(p).replace(/\s+/g, " ").trim()}`)
      .join("\n");
    const ids = (photos || []).map((p) => p.id).join(", ");

    return `Tu prépares la mise en page d'une étape de carnet de voyage. Tu ne réécris pas le récit et tu ne choisis aucune mise en page : tu décris, et tu proposes au plus un encart.

Lieu de l'étape : ${lieu || "non précisé"}
Destination du voyage : ${destination || "non précisée"}

Récit de l'étape, en paragraphes numérotés :
${texte || "(pas de récit)"}

Les photos de l'étape suivent, chacune précédée de son identifiant (${ids || "aucune"}).

1. **Le lieu.** Le pays (code ISO 3166-1 alpha-2) et les coordonnées du lieu principal de l'étape, justes au centième de degré, et le nom court à écrire sur une carte (« Paros », pas « Paros, Cyclades, Grèce »). Si tu n'es pas sûr du lieu ou de ses coordonnées, mets null : une épingle mal placée se voit immédiatement.
   "genre" : "ville" pour une ville ou un village, "ile" pour une île entière (« Paros », « Naxos » : quand l'étape se passe sur l'île sans s'attacher à une ville), "site" pour tout le reste (une plage, un musée, un parc, un quartier). Il sert à compter les villes et les îles visitées.
   "lieux" : les autres endroits où le récit emmène le voyageur pendant l'étape — une excursion, un village, une plage, une île d'escale, et dans une ville le musée, le quartier, le marché — avec leur pays et leurs coordonnées, dans l'ordre où il y passe. Pas ceux qui sont seulement cités (la ville de départ du vol, un pays dont on parle). Ils cadrent la carte et y tracent ses déplacements : un lieu en ville se situe au millième de degré, sinon il tombe dans la mauvaise rue. N'en mets que ceux que tu sais situer, et une liste vide si aucun. Chacun porte aussi son "genre".

   "trajets" : les déplacements que le récit raconte, dans l'ordre — y compris le voyage aller depuis la maison et le retour. Pour chacun, le lieu de départ et le lieu d'arrivée (nom, pays, coordonnées) et le "mode" : "avion", "bateau" (ferry, bateau, navette maritime) ou "terre" (voiture, bus, train, scooter, à pied). Seulement ce qui est raconté : on ne devine pas comment le voyageur est passé d'une île à l'autre s'il ne le dit pas. Une liste vide si aucun.

2. **Chaque photo.** Pour chaque identifiant :
   - "paragraphe" : le numéro du paragraphe dont la photo illustre le contenu — la plage pour le passage sur la plage, le plat pour le passage sur le restaurant. Juge sur ce que montre la photo et ce que raconte le texte, pas sur l'ordre des photos. null si aucun paragraphe ne s'y rattache ;
   - "scene" : un court libellé du lieu de prise de vue, identique pour toutes les photos prises au même endroit, devant le même arrière-plan (« terrasse du restaurant au port », « plage de sable blanc », « ruelle blanchie à la chaux »). Deux photos d'un même lieu portent exactement le même libellé ;
   - "sujet" : ce que montre la photo, en quelques mots ;
   - "personnes" : le nombre de personnes dont on voit le visage ;
   - "couverture" : de 0 à 10, ce que vaudrait la photo en couverture du carnet. 8 et plus pour un paysage marquant du voyage ou une belle photo où l'on voit les voyageurs, nette, lumineuse, bien cadrée. Sous 4 : un plat, un document, un intérieur sombre, une photo floue ou de travers, un détail sans contexte.

3. **L'encart (« fun fact »).** Au plus un, et seulement s'il en vaut la peine :
   - son sujet vient du récit. Le voyageur raconte un trajet en jeepney : l'encart parle des jeepneys, pas du PIB du pays ;
   - deux matières possibles. Le meilleur cas : un épisode cocasse réellement raconté, résumé en une phrase. Sinon, un fait sûr qui éclaire ce qui est raconté (histoire, origine d'un nom, usage local, tradition culinaire…), écrit à la troisième personne ;
   - 140 caractères au plus, texte nu, sans emoji ;
   - seulement des faits stables et sûrs : jamais de prix, d'horaire, de population à l'unité, de « plus grand du monde ». Rien qui contredise le voyageur, rien de polémique, de morbide ou de moralisateur ;
   - le test : le lecteur pourra-t-il le raconter à quelqu'un le soir même ? « Paros est une île grecque » échoue ;
   - "titre" : « Fun fact », « Infos », « Culture générale » ou « Chiffres clés », selon le registre ;
   - "registre" : vecu, histoire, nom-de-lieu, record, usage-local, cuisine, litterature-cinema ou echelle ;
   - "paragraphe" : le numéro du paragraphe d'où vient le sujet ;
   - "pertinence" : de 0 à 10. 8 et plus pour un fait qu'on a envie de raconter et qui tient directement au récit ; sous 5, ne propose rien.
   "funFact" vaut null s'il n'y a rien de sûr et de pertinent : c'est un résultat normal.

Réponds uniquement par un objet JSON, sans texte autour :
{"lieu":{"nom":"","pays":"","lat":0,"lon":0,"genre":"ville"},"lieux":[{"nom":"","pays":"","lat":0,"lon":0,"genre":"site"}],"trajets":[{"depart":{"nom":"","pays":"","lat":0,"lon":0},"arrivee":{"nom":"","pays":"","lat":0,"lon":0},"mode":"avion"}],"photos":[{"id":"","paragraphe":0,"scene":"","sujet":"","personnes":0,"couverture":0}],"funFact":{"texte":"","titre":"Fun fact","registre":"","paragraphe":0,"pertinence":0}}`;
  }

  /**
   * Le contenu du message d'analyse : la consigne, puis chaque photo précédée
   * d'une ligne « Photo <id> », au format du fournisseur. Les images sont des
   * vignettes JPEG en data URL (`data:image/jpeg;base64,…`).
   */
  function messagesAnalyse(consigne, images, anthropic) {
    const contenu = [{ type: "text", text: consigne }];
    for (const image of images || []) {
      contenu.push({ type: "text", text: `Photo ${image.id}` });
      if (anthropic) {
        const [entete, base64] = String(image.data).split(",");
        const media = (entete.match(/data:([^;]+)/) || [])[1] || "image/jpeg";
        contenu.push({ type: "image", source: { type: "base64", media_type: media, data: base64 } });
      } else {
        contenu.push({ type: "image_url", image_url: { url: image.data, detail: "low" } });
      }
    }
    return contenu;
  }

  const api = {
    MAX_OCTETS,
    normaliserNomAudio,
    decouperTexteGroupe,
    construireTexteGroupe,
    extraireJson,
    consigneDecoupage,
    consigneAnalyseEtape,
    messagesAnalyse,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else Object.assign(racine, api);
})(typeof globalThis !== "undefined" ? globalThis : this);
