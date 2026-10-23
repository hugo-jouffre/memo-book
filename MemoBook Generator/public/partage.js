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

  /**
   * La fiche de cohérence d'un carnet qui commence — même forme que
   * `EMPTY_COHERENCE_SHEET` (`backend/src/services/redaction.ts`) : c'est
   * l'écrivain qui la remplit, étape après étape.
   */
  const FICHE_COHERENCE_VIDE = {
    people: [],
    places: [],
    lexicon: [],
    narration: { person: "", tense: "" },
    figures: [],
    voice: [],
  };

  /**
   * Le barème des tailles d'étape, repris de `STEP_SIZES`
   * (`backend/src/services/payloadValidator.ts`) : la mise en page de
   * l'atelier compte sur les mêmes bornes (`SIGNES_PAR_PARAGRAPHE`, 379).
   */
  const BAREME_ETAPE =
    "S 200–379 (1 paragraphe), M 380–559 (2 paragraphes), L 560–899 (3 paragraphes), XL 900–1440 (4 paragraphes)";

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
   * La rédaction d'une étape — l'écrivain de MemoBook, dans l'atelier.
   *
   * Jusqu'ici l'atelier ne réécrivait rien : le texte du carnet était la
   * transcription brute, avec ses reprises et ses tics (Hugo, 23/10/2026).
   * Cette consigne branche la même rédaction que le backend, avec le même
   * prompt système — `agents/agent-transcription.md`, chargé tel quel — et le
   * même message : le carnet, la fiche de cohérence, les étapes déjà écrites,
   * puis la transcription. Voir `backend/src/services/redaction.ts`
   * (`buildRedactionPrompt`), dont ceci est la version de l'atelier.
   *
   * Deux différences assumées avec le backend, parce que l'atelier n'a pas la
   * même chaîne :
   *
   * - **pas d'encart ni de quiz ici.** Ils viennent de l'analyse d'étape
   *   (`consigneAnalyseEtape`), que la mise en page lit déjà ; les demander
   *   deux fois donnerait deux séries de fun facts dans le même carnet ;
   * - **une étape = tous ses vocaux**, là où le backend rédige un vocal à la
   *   fois. Les vocaux arrivent donc groupés, chacun daté, et l'écrivain en
   *   fait une page d'un tenant.
   *
   * `regles` est le contenu du fichier d'agent, qui devient le prompt système.
   * Renvoie `{ systeme, message }`.
   */
  function consigneRedactionEtape({ regles, carnet, etape, numero, total, vocaux, fiche, precedentes, titresEmployes }) {
    const systeme = [
      "Tu es l'écrivain de MemoBook. D'un souvenir raconté à l'oral, tu fais la page de",
      "carnet de voyage que le voyageur aurait écrite lui-même : tu comprends d'abord ce",
      "qu'il a vécu et ce qu'il voulait en dire, puis tu l'écris.",
      "",
      "Les règles ci-dessous font autorité et s'appliquent intégralement, sans exception.",
      "Elles priment sur tes habitudes de rédaction. En cas de conflit entre deux règles,",
      "la hiérarchie des quatre principes tranche.",
      "",
      "Tu réponds uniquement par l'objet JSON demandé.",
      "",
      "---",
      "",
      String(regles || "").trim(),
    ].join("\n");

    const lignes = ["## Le carnet"];
    if (carnet?.titre) lignes.push(`Titre : ${carnet.titre}`);
    if (carnet?.destination) lignes.push(`Destination : ${carnet.destination}`);
    const sejour = [carnet?.dateDebut, carnet?.dateFin].filter(Boolean);
    if (sejour.length) lignes.push(`Dates du voyage : ${sejour.join(" → ")}`);
    if (carnet?.voyageurs?.length) lignes.push(`Voyageurs : ${carnet.voyageurs.join(", ")}`);
    if (carnet?.rencontres?.length) lignes.push(`Rencontres déjà repérées : ${carnet.rencontres.join(", ")}`);

    lignes.push(
      "",
      "## Qui raconte",
      carnet?.voyageurs?.length
        ? `Le narrateur est l'un d'eux — le plus souvent ${carnet.voyageurs[0]}. S'il parle de lui à la troisième personne, c'est de lui-même (§ 1.3).`
        : "Le narrateur : prénom inconnu. N'en invente pas.",
    );

    lignes.push(
      "",
      "## Fiche de cohérence",
      precedentes?.length
        ? "Relis-la avant d'écrire, complète-la après. Ne change aucune graphie déjà fixée."
        : "Première étape du carnet : la fiche est vide, c'est toi qui l'ouvres. Les choix que tu fais ici (personne, temps, appellations) engagent tout le carnet.",
      "```json",
      JSON.stringify(fiche || FICHE_COHERENCE_VIDE, null, 2),
      "```",
    );

    const titres = (titresEmployes || []).filter(Boolean);
    if (titres.length) {
      lignes.push(
        "",
        "## Ce que le carnet a déjà employé",
        `Titres, dans l'ordre : ${titres.map((t) => `« ${t} »`).join(" · ")}`,
      );
    }

    const recentes = (precedentes || []).slice(-3);
    if (recentes.length) {
      lignes.push(
        "",
        recentes.length === 1
          ? "## L'étape précédente, déjà écrite"
          : `## Les ${recentes.length} étapes précédentes, déjà écrites`,
        "Elles donnent le ton, le rythme et la voix à tenir, et les fils qui restent ouverts.",
        "Ne les résume pas, ne les reprends pas : enchaîne. La dernière phrase de la dernière",
        "étape et la première phrase de la tienne ne doivent pas se recouvrir.",
      );
      for (const voisine of recentes) {
        lignes.push("", `### ${voisine.titre || "(sans titre)"}${voisine.lieu ? ` — ${voisine.lieu}` : ""}`, voisine.texte);
      }
    }

    const jours = [etape?.dateDebut, etape?.dateFin].filter(Boolean);
    lignes.push(
      "",
      "## L'étape à rédiger",
      `Étape n°${numero} sur ${total}${etape?.titre ? ` — « ${etape.titre} »` : ""}${jours.length ? `, ${[...new Set(jours)].join(" → ")}` : ""}`,
      etape?.lieu ? `Lieu : ${etape.lieu}` : "Lieu : non précisé par le voyageur",
      "",
      (vocaux || []).length > 1
        ? "Ses vocaux, dans l'ordre. Ils racontent **une seule** étape : fais-en une page d'un tenant, sans marquer les coutures."
        : "Son vocal.",
      "Transcription brute, faite par une machine qui entend mal les noms propres et l'argot (§ 1.2) :",
    );
    for (const vocal of vocaux || []) {
      lignes.push(
        "",
        `### ${vocal.nom || "vocal"}${vocal.date ? ` — envoyé le ${vocal.date}` : ""}`,
        "```",
        String(vocal.texte || "").trim(),
        "```",
      );
    }

    lignes.push(
      "",
      "## Rappels",
      "- Lis d'abord, écris ensuite : `understanding` se remplit avant `text`, et c'est lui qui décide",
      "  de la page — son cœur, son ton, ce que veut dire chaque passage (§ 1).",
      `- \`text\` : une taille du barème — ${BAREME_ETAPE} —, et **379 caractères au plus par`,
      "  paragraphe**, séparés par une ligne vide. Un dépassement casse la mise en page.",
      "- Texte nu dans `text` : ni HTML, ni Markdown, ni emoji.",
      "- Tout ce que tu écris dans `text` se retrouve dans la transcription. La culture générale",
      "  n'entre pas dans le récit : dans cet atelier, les encarts et le quiz sont écrits ailleurs,",
      "  ne les produis pas ici.",
      "- `title` : le titre de l'étape, dans la voix du voyageur. Reprends celui qui est déjà posé",
      "  s'il tient, propose mieux sinon.",
      "- Un mot que tu n'as pas compris ne s'imprime pas et n'entre pas dans la fiche : il va dans",
      "  `doubts`, que tu laisses vide quand tout est clair.",
      "",
      "Réponds uniquement par un objet JSON, sans texte autour et sans balises de code :",
      '{"understanding":{"heart":"","tone":"","readings":[{"heard":"","meaning":""}]},',
      ' "title":"","text":"",',
      ' "coherenceSheet":{"people":[{"canonicalName":"","notes":""}],"places":[{"canonicalName":"","notes":""}],"lexicon":[{"term":"","notes":""}],"narration":{"person":"","tense":""},"figures":[{"label":"","value":""}],"voice":[""]},',
      ' "doubts":[""]}',
    );

    return { systeme, message: lignes.join("\n") };
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
   * - des encarts (« fun facts ») tirés du récit, notés sur 10 — jusqu'à
   *   `maxEncarts`, de quoi tenir la promesse d'environ un toutes les trois
   *   pages (Hugo, 13/10/2026). C'est la mise en page qui décide lesquels
   *   s'impriment, les mieux notés d'abord ;
   * - un quiz tiré du récit ou d'un fait sûr du lieu, ou `null`. La mise en
   *   page en imprime environ un toutes les trois étapes (`placerQuiz`) : le
   *   modèle propose, il ne règle pas la cadence (Hugo, 15/10/2026).
   *
   * La mise en page reste un calcul de l'atelier (`mise-en-page.js`) : le
   * modèle décrit, il ne compose pas. Voir LAYOUT_KB § « Associer les photos au
   * récit » et § « Les fun facts — dosage et matière ».
   */
  function consigneAnalyseEtape({ lieu, destination, paragraphes, photos, maxEncarts = 2 }) {
    const encarts = Math.max(1, Math.min(4, Math.round(maxEncarts) || 1));
    const texte = (paragraphes || [])
      .map((p, i) => `[${i}] ${String(p).replace(/\s+/g, " ").trim()}`)
      .join("\n");
    const ids = (photos || []).map((p) => p.id).join(", ");

    return `Tu prépares la mise en page d'une étape de carnet de voyage. Tu ne réécris pas le récit et tu ne choisis aucune mise en page : tu décris, et tu proposes des encarts et un quiz.

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
   - "legende" : une étiquette de titre à poser sur la photo, comme on l'écrirait dans un carnet — un nom de lieu ou de moment, 30 signes au plus (« Rizières de Banaue », « Coucher de soleil à Oia »). Seulement si le récit ou la photo le dit clairement ; sinon une chaîne vide ;
   - "personnes" : le nombre de personnes dont on voit le visage ;
   - "couverture" : de 0 à 10, ce que vaudrait la photo en couverture du carnet. 8 et plus pour un paysage marquant du voyage ou une belle photo où l'on voit les voyageurs, nette, lumineuse, bien cadrée. Sous 4 : un plat, un document, un intérieur sombre, une photo floue ou de travers, un détail sans contexte.

3. **Les encarts (« fun facts »).** Jusqu'à ${encarts}, chacun sur un sujet différent du récit et, autant que possible, d'un registre différent. Seulement ceux qui en valent la peine :
   - son sujet vient du récit. Le voyageur raconte un trajet en jeepney : l'encart parle des jeepneys, pas du PIB du pays ;
   - deux matières possibles. Le meilleur cas : un épisode cocasse réellement raconté, résumé en une phrase. Sinon, un fait sûr qui éclaire ce qui est raconté (histoire, origine d'un nom, usage local, tradition culinaire…), écrit à la troisième personne ;
   - 120 caractères au plus (140 est la limite dure : au-delà, l'encart est jeté), texte nu, sans emoji ;
   - seulement des faits stables et sûrs : jamais de prix, d'horaire, de population à l'unité, de « plus grand du monde ». Rien qui contredise le voyageur, rien de polémique, de morbide ou de moralisateur ;
   - le test : le lecteur pourra-t-il le raconter à quelqu'un le soir même ? « Paros est une île grecque » échoue ;
   - "titre" : « Fun fact », « Infos », « Culture générale » ou « Chiffres clés », selon le registre ;
   - "registre" : vecu, histoire, nom-de-lieu, record, usage-local, cuisine, litterature-cinema ou echelle ;
   - "paragraphe" : le numéro du paragraphe d'où vient le sujet ;
   - "pertinence" : de 0 à 10. 8 et plus pour un fait qu'on a envie de raconter et qui tient directement au récit ; sous 5, ne le propose pas.
   "funFacts" est une liste, du meilleur au moins bon ; vide s'il n'y a rien de sûr et de pertinent : c'est un résultat normal.

4. **Le quiz.** Un petit jeu imprimé dans la page, réponse à l'envers. Au plus un, et seulement s'il en vaut la peine :
   - la question porte sur **ce que le récit raconte** — un lieu, un plat, une rencontre, un chiffre que le voyageur donne — ou sur un fait sûr et vérifiable du lieu de l'étape. Jamais sur un sujet générique, jamais sur un détail que le récit ne dit pas : rien ne s'invente, rien ne se devine ;
   - "question" : une ligne, 120 caractères au plus, terminée par un point d'interrogation ;
   - "choix" : trois propositions courtes (40 caractères au plus), une seule juste, les deux autres plausibles et fausses sans ambiguïté. Une couleur se nomme en toutes lettres ;
   - "reponse" : la bonne proposition, recopiée à l'identique ;
   - rien de polémique, de morbide ou de moralisateur, rien qui contredise le voyageur.
   "quiz" est null quand l'étape n'offre rien de sûr ou d'amusant à demander : c'est un résultat normal.

Réponds uniquement par un objet JSON, sans texte autour :
{"lieu":{"nom":"","pays":"","lat":0,"lon":0,"genre":"ville"},"lieux":[{"nom":"","pays":"","lat":0,"lon":0,"genre":"site"}],"trajets":[{"depart":{"nom":"","pays":"","lat":0,"lon":0},"arrivee":{"nom":"","pays":"","lat":0,"lon":0},"mode":"avion"}],"photos":[{"id":"","paragraphe":0,"scene":"","sujet":"","legende":"","personnes":0,"couverture":0}],"funFacts":[{"texte":"","titre":"Fun fact","registre":"","paragraphe":0,"pertinence":0}],"quiz":{"question":"","choix":["","",""],"reponse":""}}`;
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

  /** Une image en data URL, en Blob pour un envoi multipart. */
  function dataUrlEnBlob(dataUrl) {
    const [entete, base64] = String(dataUrl).split(",");
    const type = (entete.match(/data:([^;]+)/) || [])[1] || "image/png";
    const binaire = atob(base64 || "");
    const octets = new Uint8Array(binaire.length);
    for (let i = 0; i < binaire.length; i += 1) octets[i] = binaire.charCodeAt(i);
    return new Blob([octets], { type });
  }

  /**
   * Une illustration de couverture, générée par OpenAI (`gpt-image-1`, le
   * modèle de `docs/sticker-generation.yaml`) — le même appel depuis le
   * serveur local et depuis la page.
   *
   * `references` : des images (data URLs) que le modèle reçoit en entrée — la
   * couverture de référence du style, pour en tenir le style, ou la silhouette
   * d'un pays pour un tampon. Avec elles, l'appel passe par `images/edits`.
   * `transparent` : un PNG sans fond, pour une image posée sur un aplat.
   * Renvoie `{ data }`, l'image en data URL PNG.
   */
  async function genererImage({ cle, base = "https://api.openai.com/v1", prompt, taille = "1024x1536", transparent = false, qualite = "high", references = [] }) {
    if (!cle) throw new Error("Aucune clé OpenAI");
    const commun = { model: "gpt-image-1", prompt, size: taille, quality: qualite, ...(transparent ? { background: "transparent" } : {}) };
    let reponse;
    if (references.length) {
      const formulaire = new FormData();
      for (const [cle2, valeur] of Object.entries(commun)) formulaire.append(cle2, valeur);
      references.forEach((r, i) => formulaire.append("image[]", dataUrlEnBlob(r.data || r), r.nom || `reference-${i + 1}.png`));
      reponse = await fetch(`${base}/images/edits`, { method: "POST", headers: { authorization: `Bearer ${cle}` }, body: formulaire });
    } else {
      reponse = await fetch(`${base}/images/generations`, {
        method: "POST",
        headers: { authorization: `Bearer ${cle}`, "content-type": "application/json" },
        body: JSON.stringify({ ...commun, output_format: "png" }),
      });
    }
    const donnees = await reponse.json().catch(() => ({}));
    if (!reponse.ok) throw new Error(donnees?.error?.message || `OpenAI a refusé l'image (HTTP ${reponse.status})`);
    const b64 = donnees?.data?.[0]?.b64_json;
    if (!b64) throw new Error("OpenAI n'a renvoyé aucune image");
    return { data: `data:image/png;base64,${b64}` };
  }

  const api = {
    MAX_OCTETS,
    dataUrlEnBlob,
    genererImage,
    normaliserNomAudio,
    decouperTexteGroupe,
    construireTexteGroupe,
    extraireJson,
    consigneDecoupage,
    consigneRedactionEtape,
    consigneAnalyseEtape,
    FICHE_COHERENCE_VIDE,
    messagesAnalyse,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else Object.assign(racine, api);
})(typeof globalThis !== "undefined" ? globalThis : this);
