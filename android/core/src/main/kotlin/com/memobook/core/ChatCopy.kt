package com.memobook.core

// Tout ce que le chat écrit : les libellés de l'interface **et** les phrases de
// MEMO, dans un seul fichier. Le jumeau de `MemoBookCore/ChatCopy.swift`.
//
// Les deux ensemble, et non deux fichiers, parce que la frontière ne tient pas :
// « Ça me convient » est un libellé de puce que le voyageur envoie comme
// message, et « Retranscription du contexte » est un titre de fiche que le
// répondeur produit. Un seul endroit, donc, pour que la voix de MEMO se relise
// d'un trait — et pour que R8 (« tous les libellés passent par des constantes
// localisables ») ait un endroit unique à tenir.
//
// **Les conventions typographiques de l'app**, vérifiées dans les écrans déjà
// livrés : apostrophe typographique `’` (U+2019) partout, espace simple avant
// `?` et `!`, points de suspension `…` (U+2026).
//
// Les deux coquilles de la maquette dans `opening` — « pourrais tu » sans
// trait d'union, « tous le long » — sont **corrigées** dans l'app (Hugo,
// 17/09/2026, T49) ; Figma reste à reprendre.
//
// Le vouvoiement de `greetingMessage`, lui, est **corrigé** : Hugo a tranché
// (D9), et R9 l'emportait de toute façon sur R8 pour cette phrase.
object ChatCopy {

    // MARK: - La bannière « Aperçu en direct »

    /** « Votre Carnet » dans la maquette : tutoyé, comme tout le reste (R9). */
    const val previewTitle = "Ton carnet prend forme"

    /**
     * « 5 Souvenirs - 10 pages composées ».
     *
     * ⚠️ Le S majuscule de « Souvenirs » et le tiret entouré d'espaces sont
     * ceux de la maquette (R8). Les pluriels, en revanche, sont accordés : la
     * maquette ne montre qu'un carnet bien rempli, et « 1 Souvenirs » se verrait
     * au premier lancement.
     */
    fun previewSubtitle(memories: Int, pages: Int): String {
        val souvenirs = if (memories == 1) "1 Souvenir" else "$memories Souvenirs"
        val composed = if (pages == 1) "1 page composée" else "$pages pages composées"
        return "$souvenirs - $composed"
    }

    // MARK: - Hors ligne

    /**
     * Le fil s'est ouvert sans le serveur — voir `ChatModel.isOffline`. Même
     * phrase que la boîte de l'accueil, et le même gras : ce qui est garanti
     * malgré la panne.
     */
    const val offline =
        "Tu sembles hors ligne. **Ce que tu racontes est gardé sur ton téléphone**, et partira dès ta reconnexion."

    /**
     * Au-dessus de la barre d'envoi, dès qu'un message part dans la file au
     * lieu du serveur (Hugo, 12/10/2026) : on peut continuer, rien n'est
     * perdu, et ça partira tout seul.
     */
    const val queuedOffline =
        "Tu es hors ligne, mais tu peux continuer à raconter : **tes messages sont gardés sur ton téléphone**, et partiront dès que la connexion reviendra."

    // MARK: - La mention de confidentialité

    /**
     * Le premier mot du fil, en gris au-dessus de toute bulle (01/10/2026) :
     * on y raconte des choses intimes, et il faut le savoir à l'abri.
     *
     * ⚠️ **« Et tes co-voyageurs », pas « toi seul ».** Sur un voyage partagé,
     * le fil est commun — chaque bulle y porte le prénom de celui qui parle
     * (FAQ, `ChatContext.memberCount`) —, et un fil solo le devient dès
     * qu'on invite quelqu'un. La phrase reste vraie dans les deux cas.
     */
    const val privacyNote =
        "Ta conversation est privée : seuls toi et tes co-voyageurs pouvez la lire."

    // MARK: - L'accueil d'une conversation vide

    /**
     * « Nouveau voyage à Rome ! 🇮🇹 » — le drapeau vient de `Destination.flag`,
     * jamais d'un emoji écrit en dur.
     */
    fun greetingTitle(place: String, flag: String?): String {
        val title = "Nouveau voyage à $place !"
        return flag?.let { "$title $it" } ?: title
    }

    /**
     * Le voyage n'a pas de destination nommée. La maquette ne le dessine pas —
     * écart signalé dans la fiche écran.
     */
    const val greetingTitleWithoutPlace = "Nouveau carnet de voyage !"

    /**
     * La maquette vouvoyait sur la dernière phrase (« Comment souhaitez-vous
     * commencer aujourd’hui ? ») au milieu d'un paragraphe qui tutoie.
     * **Corrigé sur arbitrage de Hugo** (D9) : R9 ne souffre pas d'exception,
     * et la phrase se contredisait elle-même. À reprendre dans Figma.
     */
    const val greetingMessage =
        "Je suis là pour transformer tes anecdotes, photos et enregistrements " +
            "vocaux en un magnifique récit structuré. Comment souhaites-tu " +
            "commencer aujourd’hui ?"

    // MARK: - L'ouverture de MEMO

    /**
     * La première bulle blanche, celle que la maquette dessine en entier.
     *
     * Deux coquilles de la maquette corrigées ici (T49) : « pourrais-tu » et
     * « tout le long ».
     */
    const val opening =
        "Bonjour 👋\n" +
            "Je suis MEMO, ton assistant pour t’aider à construire ton carnet de voyage.\n" +
            "\n" +
            "Je suis là pour transformer ce que tu me racontes en un récit fluide.\n" +
            "\n" +
            "Je m’adapte à ton style : tu peux me dicter ta journée, ta semaine, ton " +
            "expérience à l’oral ou l’écrire, comme tu préfères.\n" +
            "\n" +
            "Avant de commencer pourrais-tu me faire un contexte global de ton " +
            "voyage ? Cela m’aidera à garder de la cohérence tout le long du récit."

    /**
     * La réponse à « Je te raconte le contexte de mon voyage » — au caractère
     * près de `tripContext.ts` (`CONTEXT_INVITATION`).
     */
    const val contextInvitation =
        "Avec plaisir ! Raconte-moi ton voyage comme à un ami : d’où tu pars, à combien vous " +
            "êtes et leurs prénoms, les dates, et quel genre de voyage c’est. À l’oral ou au " +
            "clavier, comme tu préfères."

    /**
     * La réponse à « Commencer mon carnet » : une invitation à raconter, sans
     * reproposer les puces d'ouverture à qui vient de commencer.
     */
    const val openingWithoutPrompt =
        "Raconte-moi ta journée, à l’oral ou au clavier. Je m’occupe du reste."

    // MARK: - La fiche de retranscription

    /**
     * L'intitulé d'une fiche que le serveur n'a pas numérotée (jeu d'essai,
     * moteur local). Le vrai fil dit « Retranscription étape 2 » —
     * `transcriptTitle` dans `backend/src/services/conversationCopy.ts`.
     */
    const val transcriptTitle = "Retranscription étape 1"

    /** La mention « généré par IA » qu'exige `docs/reglages-utilisateur.md`. */
    const val transcriptFootnote = "Texte proposé par MEMO — tu peux le corriger."

    /**
     * La fiche s'affiche avec ce qu'on sait (date, lieu, durée) même sans
     * récit : on ne cache pas une fiche réelle derrière une attente.
     */
    const val transcriptPending = "J’écoute ton vocal…"

    /**
     * Le brut est arrivé, la rédaction écrit — la fiche montre la transcription
     * en gris pendant ce temps (`docs/conversation.md` § 5).
     */
    const val transcriptWriting = "Je rédige…"

    /** La transcription ou la rédaction a échoué ; le brut reste s'il existe. */
    const val transcriptFailed =
        "Je n’ai pas réussi à finir cette fiche. Tu peux la corriger à la main, ou réenregistrer."

    /**
     * Ce que le voyageur « dit » en envoyant une correction au clavier : la
     * bulle bleue d'une commande silencieuse, à laquelle MEMO accuse réception.
     */
    const val editedByHand = "J’ai retouché le texte à la main."

    const val transcriptUnavailable =
        "Je n’ai pas encore la transcription de ce vocal. Tu peux me le réécrire " +
            "ici, ou attendre que je l’aie."

    const val seeMore = "Voir plus"
    const val seeLess = "Voir moins"

    /** La relance qui suit une fiche remplie. */
    const val afterTranscript =
        "Voilà ce que j’ai compris de ton vocal. Je le garde tel quel pour ton " +
            "carnet, ou tu veux le retoucher ?"

    // MARK: - Les relances de MEMO, par famille
    //
    // Une famille = un signal détecté dans le message du voyageur. La priorité
    // qui les départage vit dans `LocalMemoResponder` ; ici, seulement les
    // mots. Chaque phrase se termine par **une** question : `agents/agent-
    // conversation.md` interdit le formulaire déguisé.

    /**
     * Le voyageur ne veut plus répondre. « Ne jamais insister » est la règle la
     * plus dure du contrat de l'agent.
     */
    const val refusal =
        "Très bien, on s’arrête là. Ce que tu m’as raconté est gardé, tu " +
            "reprendras quand tu voudras."

    const val acknowledged = "C’est enregistré. Ton carnet compte une étape de plus."

    const val handingOver =
        "Je te laisse la main. Ta version fait autorité sur la mienne, je n’y " +
            "retouche plus."

    const val listening = "Je t’écoute. Reprends-le comme tu le dirais à quelqu’un."

    /**
     * Les six sujets sur lesquels MEMO sait légitimement répondre, plus le
     * repli honnête. Répondre à une question par une question est le pire des
     * aveux : il prouve que rien n'a été lu.
     */
    object Answer {
        const val book =
            "Ton carnet se met en page tout seul à partir de ce que tu racontes. " +
                "Tu le relis en aperçu, et rien ne part à l’impression sans que tu " +
                "l’aies validé."

        /**
         * La réponse à toute question sur le prix, l'abonnement ou la limite
         * du jour. **La même phrase que le serveur** (`ANSWERS.subscription`,
         * `conversationCopy.ts`), au caractère près (Hugo, 03/10/2026) : elle
         * renvoie à « Découvrir l’abonnement », la ligne que tout le monde a
         * dans son profil — « Mon abonnement » n'existait que pour un abonné.
         */
        const val subscription =
            "Chaque voyage a 5 minutes de récit par jour, partagées entre les " +
                "co-voyageurs qui ne sont pas abonnés : l’écrit compte aussi, pas les " +
                "photos, et le crédit se recharge à minuit. L’abonnement, à 4,99 € par " +
                "mois, rend ton récit illimité ; tu le trouves dans ton profil, à " +
                "« Découvrir l’abonnement »."

        const val photos =
            "Ajoute tes photos quand tu veux : je les range avec le souvenir du jour."

        const val corrections =
            "Tout se corrige. Tu relis chaque texte avant l’impression, et ta " +
                "version fait autorité sur la mienne."

        const val pace =
            "Je te relance au rythme réglé pour ce voyage. Tu le changes dans les " +
                "paramètres du voyage."

        const val unknown =
            "Je ne sais pas répondre à ça pour l’instant. Ce que je sais faire, " +
                "c’est écouter ton voyage et en tirer ton carnet — tu me racontes la " +
                "suite ?"
    }

    /**
     * Une émotion difficile s'accuse **avant** toute demande, et la demande
     * reste optionnelle.
     */
    val negativeMood: List<String> = listOf(
        "Ça n’a pas dû être simple. Si tu veux le garder dans le carnet, " +
            "raconte-moi ce qui t’a remis d’aplomb.",
        "Je note la journée telle qu’elle a été, sans l’enjoliver. Tu veux qu’on " +
            "s’arrête là pour aujourd’hui ?",
    )

    const val positiveMood =
        "On sent que tu y étais. Donne-moi le détail qui rendra bien à " +
            "l’impression : une odeur, un bruit, une phrase que quelqu’un a dite."

    /**
     * Un message trop court : MEMO **dit** qu'il n'a pas compris, en
     * recopiant ce qu'il a reçu, et demande la suite sans en choisir le sujet
     * (Hugo, 08/10/2026) — le jumeau de `tooShort` dans
     * `backend/src/services/conversationCopy.ts`.
     */
    fun tooShort(received: String): List<String> {
        val quote = shortQuote(received)
        return listOf(
            "« $quote » : c’est un peu court, je n’ai pas compris ce que tu voulais me dire. Tu peux m’en dire un peu plus ?",
            "Je n’ai pas réussi à en tirer un souvenir : « $quote », c’est trop court pour moi. Raconte-moi ce qui s’est passé, avec tes mots.",
        )
    }

    /**
     * Quarante signes au plus, les espaces resserrés. Les signes se comptent en
     * graphèmes, comme `String.count` d'iOS.
     */
    private fun shortQuote(received: String): String {
        val words = mutableListOf<String>()
        val current = StringBuilder()
        for (character in received) {
            if (character.isWhitespace()) {
                if (current.isNotEmpty()) words.add(current.toString())
                current.clear()
            } else {
                current.append(character)
            }
        }
        if (current.isNotEmpty()) words.add(current.toString())
        val trimmed = words.joinToString(" ")
        if (ChatGraphemes.count(trimmed) <= 40) return trimmed
        return ChatGraphemes.prefix(trimmed, 39).trim { it == ' ' || it == '\t' || Character.isSpaceChar(it) } + "…"
    }

    const val missingPlace = "Tu me dis où ça se passait ? Un quartier ou un nom de rue me suffit."

    /**
     * Le lieu est recopié **verbatim** du message : MEMO ne complète pas un nom
     * propre, il le répète.
     */
    fun foundPlace(place: String): String =
        "$place, je note. Qu’est-ce qui t’a marqué là-bas ?"

    const val missingDate = "Ça date de quand ? Si c’était hier, je le range à la bonne journée du carnet."

    /**
     * Première apparition d'un prénom dans le fil. **Tournure sans genre** : le
     * moteur ne sait pas si Camille est une femme ou un homme, et un accord
     * faux se voit immédiatement.
     */
    fun newPerson(name: String): String =
        "$name apparaît pour la première fois dans ton carnet. Tu me dis en deux mots qui c’est ?"

    fun knownPerson(name: String): String =
        "Et $name ? Raconte-moi ce que vous avez fait ensemble."

    /**
     * Le chiffre est recopié tel quel. MEMO ne convertit ni n'additionne : une
     * métadonnée fausse est pire qu'absente.
     */
    fun figure(figure: String): String =
        "$figure, c’est noté : ça ira dans les compteurs du voyage. Ça t’a pris combien de temps ?"

    /**
     * Des photos viennent d'arriver. MEMO recompte ce qu'il a reçu — un
     * chiffre se recopie — et demande ce qu'on y voit : il n'a pas regardé les
     * images, et prétendre le contraire serait inventer un fait.
     */
    fun photosReceived(count: Int): String =
        if (count == 1) {
            "Une photo, je la range avec le souvenir du jour. Qu’est-ce qu’on y voit ?"
        } else {
            "$count photos, je les range avec le souvenir du jour. Qu’est-ce qu’on y voit ?"
        }

    const val longMessage =
        "Il y a de quoi faire deux pages là-dedans. Je découpe en deux étapes, ou " +
            "tu préfères que ça reste d’un seul tenant ?"

    /**
     * La rotation neutre, quand aucun signal ne ressort.
     *
     * Les trois premières sont la rose, l'épine et la graine, que
     * `docs/reglages-utilisateur.md` veut « demandé dans le chat, pas imprimé
     * comme bloc à remplir » ; les quatrième et cinquième sont recopiées mot
     * pour mot des exemples de relances d'`agents/agent-conversation.md` ; les
     * cinq dernières les complètent.
     *
     * **Dix et pas cinq**, parce que c'est le nombre de soirs ternes qu'un
     * voyage peut compter. Le moteur écarte toute relance déjà dite dans le
     * fil et descend d'un cran : une liste trop courte le force à se répéter
     * avant la fin de la semaine, et rien ne trahit plus vite une machine.
     */
    val rotation: List<String> = listOf(
        "Le meilleur moment de ta journée, c’était lequel ?",
        "Et ce qui t’a agacé aujourd’hui, tu veux qu’on le garde ou qu’on le laisse de côté ?",
        "Qu’est-ce que tu attends le plus, pour demain ?",
        "Tu as une photo de ce moment-là, ou on en cherche une qui lui ressemble dans ta pellicule ?",
        "On regroupe ce souvenir avec la journée d’avant, ou il mérite sa propre page ?",
        "Qu’est-ce que tu as mangé, et où ? Ça donne toujours de bonnes pages.",
        "Tu as croisé quelqu’un dont tu te souviendras ?",
        "Si tu devais donner un titre à cette journée, ce serait quoi ?",
        "Qu’est-ce qui t’a surpris, par rapport à ce que tu imaginais ?",
        "Il te reste quelque chose à raconter sur aujourd’hui, ou on s’arrête là ?",
    )

    // MARK: - Les suggestions
    //
    // Une puce n'est pas un raccourci d'interface : c'est une phrase que le
    // voyageur envoie, et la maquette la montre bien posée en bulle bleue dans
    // le fil. Ce qui change d'une intention à l'autre, c'est l'outil qu'elle
    // ouvre derrière. Deux ou trois par tour, jamais quatre, et aucune
    // ponctuation finale.

    /** La pastille et la fiche du contexte du voyage — [ChatTripContext]. */
    object TripContext {
        const val title = "Contexte du voyage"
        const val gatheringSubtitle =
            "Ce que MEMO a compris de ton voyage. Raconte-lui ce qui manque dans la conversation."
        const val doneSubtitle =
            "Ce que MEMO sait de ton voyage. Pour corriger une ligne, dis-le-lui dans la conversation."
        const val extrasTitle = "En plus"
        const val missingValue = "À raconter"
        const val accessibilityHint = "Montre ce que MEMO a compris de ton voyage"

        fun accessibilityLabel(filled: Int, of: Int): String = "$title, $filled sur $of"
    }

    object Suggest {
        // **Chaque proposition porte un émoji devant** — c'est la maquette de
        // Hugo (`3520:35958`), et il est porté à part du libellé : il ne part
        // pas dans le message envoyé, et TalkBack ne le lit pas.

        /** Le trio de la maquette, sous une fiche qui porte du **vrai** texte. */
        const val accept = "Ça me convient"
        const val acceptSymbol = "👌"
        const val editByHand = "J’aimerais faire des modifications à la main"
        const val editByHandSymbol = "✍️"
        const val editByVoice = "J’aimerais faire des modifications à l’oral"
        const val editByVoiceSymbol = "🎙"

        /** Sous une fiche sans récit : le trio n'a rien à valider. */
        const val rewrite = "Je te le réécris ici"
        const val rewriteSymbol = "✍️"
        const val recordAgain = "Je réenregistre"
        const val recordAgainSymbol = "🎙"

        /**
         * L'écran vide, tel que la maquette l'écrit — emoji de tête compris,
         * porté séparément pour qu'il ne parte pas dans le message.
         */
        const val start = "Commencer mon carnet"
        const val startSymbol = "🚀"

        /**
         * **La** puce d'ouverture tant que le contexte du voyage n'est pas
         * posé : on raconte d'où l'on part, avec qui, quand, et quel genre
         * de voyage, avant la première étape (Paul, 28/09/2026). Au
         * caractère près de `conversationCopy.ts`.
         */
        const val tellContext = "Je te raconte le contexte de mon voyage"
        const val tellContextSymbol = "🧭"
        const val contextLater = "Je compléterai plus tard"
        const val contextLaterSymbol = "⏭️"
        const val importPhotos = "Importer des photos"
        const val importPhotosSymbol = "📷"
        const val dictate = "Raconter à l’oral"
        const val dictateSymbol = "🎙"

        const val tellByVoice = "Je te raconte à l’oral"
        const val tellByVoiceSymbol = "🎙"
        const val preferWriting = "Je préfère écrire"
        const val preferWritingSymbol = "✍️"
        const val later = "Plus tard"
        const val laterSymbol = "⏰"
        const val tomorrow = "On en reparle demain"
        const val tomorrowSymbol = "🌙"
        const val somethingElse = "Je te raconte autre chose"
        const val somethingElseSymbol = "💬"
        const val clear = "C’est clair, merci"
        const val clearSymbol = "👍"
        const val anotherQuestion = "J’ai une autre question"
        const val anotherQuestionSymbol = "❓"
        const val resume = "Je reprends mon récit"
        const val resumeSymbol = "📖"
        const val splitInTwo = "Découpe en deux étapes"
        const val splitInTwoSymbol = "✂️"
        const val keepAsOne = "Garde d’un seul tenant"
        const val keepAsOneSymbol = "🧩"
    }

    // MARK: - Les commandes de l'écran

    const val backToBottom = "Retourner en bas"

    /**
     * « Record » dans la maquette, en anglais au milieu d'une app française :
     * traduit (Hugo, 17/09/2026, T51).
     */
    const val record = "Enregistrer"

    const val composerPlaceholder = "Raconte-moi…"

    // MARK: - Le crédit du jour

    /**
     * Ce que la barre du chat dit du crédit du jour, en plus de
     * [DailyCreditCopy] — les phrases que la barre seule prononce (Hugo,
     * 03/10/2026).
     */
    object Credit {
        /**
         * Le rappel discret sous une minute de crédit, au-dessus du champ.
         * « Environ » : le compte se fait en scalaires Unicode, et personne
         * ne compte ainsi ses lettres.
         */
        fun charactersLeft(count: Int): String =
            "Encore environ ${DailyCreditCopy.characters(count)} aujourd’hui"

        /**
         * Ce que TalkBack annonce quand l'enregistrement s'arrête net : ce
         * qui a été dit est gardé, il faut le savoir sans le voir. « Gardé »,
         * pas « envoyé » : hors ligne, il attend encore dans la file.
         */
        const val stoppedAnnouncement =
            "Limite du jour atteinte. Ton vocal est gardé."

        /** L'indice du bandeau « Crédit du jour épuisé », qui ouvre l'offre. */
        const val exhaustedHint = "Ouvre l’offre illimitée"

        /**
         * Ce que TalkBack annonce quand le micro ou le clavier pâlis sont
         * touchés : le bandeau paraît ailleurs dans la pile, et rien ne le
         * dirait sans cette annonce. À chaque toucher, pas seulement au
         * premier (03/10/2026).
         */
        val exhaustedAnnouncement: String
            get() = "${DailyCreditCopy.exhaustedTitle}. ${DailyCreditCopy.exhaustedDetail}"
    }

    // MARK: - Le bouton sous une bulle de MEMO

    /** La carte d'appel à l'action — [ChatCallToAction]. */
    object CallToAction {
        /** L'étoile manuscrite devant l'en-tête de la carte (maquette `3653:17090`). */
        const val star = "✦"
        const val dismiss = "Ignorer"

        /** Ce que TalkBack dit d'un bouton déjà touché, passé au bleu. */
        const val followed = "Déjà ouvert"
    }

    // MARK: - Les photos

    /**
     * Ce que le sélecteur de photos propose. Les libellés d'une
     * `confirmationDialog` iOS, en français comme le reste de l'app.
     */
    object Photos {
        const val title = "Ajouter une photo"
        const val takeOne = "Prendre une photo"

        /** Retirer la photo de profil — la feuille de choix du profil seulement. */
        const val remove = "Supprimer la photo"
        const val fromLibrary = "Choisir dans la galerie"
        const val cancel = "Annuler"

        /** L'appareil photo n'existe pas — un émulateur, une tablette sans caméra. */
        const val cameraUnavailable =
            "Cet appareil n’a pas d’appareil photo. Choisis une image dans ta galerie."

        /**
         * L'accès aux photos a été refusé. Comme pour le micro, le système ne
         * redemande pas : le seul recours est l'app Paramètres. (Le sélecteur
         * de photos d'Android ne demande aucune permission : ce texte ne
         * s'affiche que si un fabricant l'exige.)
         */
        const val libraryDenied =
            "MemoBook a besoin de tes photos pour les ranger dans ton carnet. " +
                "Autorise l’accès dans les Paramètres du téléphone."

        const val cameraDenied =
            "MemoBook a besoin de l’appareil photo pour prendre une photo. " +
                "Autorise l’accès dans les Paramètres du téléphone."
    }

    // MARK: - Les échecs

    /**
     * Les images choisies n'ont pas pu être écrites sur l'appareil — disque
     * plein, ou fichier illisible.
     */
    const val photosUnreadable =
        "Je n’ai pas réussi à ouvrir ces photos. Réessaie, ou choisis-en d’autres."

    const val notSent = "Non envoyé"
    const val retry = "Réessayer"

    /**
     * Sous une bulle que le serveur a refusée faute de crédit du jour : elle
     * attend sur le téléphone et repart toute seule à minuit. Gris, sans
     * « Réessayer » : il n'y a rien à faire (Hugo, 03/10/2026).
     */
    const val leavesTomorrow = "Partira demain"

    /**
     * Sous une bulle qui coûte plus qu'une journée entière de crédit — un
     * vocal de plus de 5 minutes, un texte de plus de 4 000 caractères :
     * demain n'y changerait rien. Tapable, suivi de
     * `DailyCreditCopy.unlimitedCallToAction` : elle ouvre l'offre, et la
     * bulle part dès que le compte raconte sans limite (03/10/2026).
     */
    const val tooLongForADay = "Trop long pour une journée"

    /**
     * « Supprimer », à côté de « Passer en illimité » sous une bulle « Trop
     * long pour une journée » (03/10/2026) : sans abonnement, rien ne la
     * ferait jamais partir, et elle se reposait à chaque ouverture du fil.
     * Une confirmation d'abord — c'est un souvenir qui n'existe encore que
     * sur ce téléphone.
     */
    object DiscardWaiting {
        const val action = "Supprimer"
        const val voiceTitle = "Supprimer ce vocal ?"
        const val textTitle = "Supprimer ce message ?"
        const val body =
            "Il n’est pas encore parti : supprimé, il ne rejoindra jamais ton carnet. C’est sans retour."
        const val confirm = "Supprimer"
        const val keep = "Le garder"

        /** Ce que TalkBack dit du lien, en plus de son libellé. */
        const val hint = "Le retire de ton téléphone sans l’envoyer"
    }

    // MARK: - Ce que TalkBack annonce
    //
    // Tout élément interactif sans libellé visible en porte un, en français et
    // en tutoiement (R7, R9).

    /** La photo du fil en plein écran — `ChatPhotoViewer`. */
    object PhotoViewer {
        const val close = "Fermer la photo"
        const val photo = "Photo envoyée dans le fil"
        const val hint = "Ouvre les photos en plein écran"

        /** « 2 / 5 » — la photo regardée, parmi celles de la bulle. */
        fun position(index: Int, of: Int): String = "$index / $of"
    }

    object Voice {
        const val back = "Revenir au voyage"
        const val settings = "Paramètres du voyage"
        const val map = "Voir le voyage sur la carte"
        const val openPreview = "Ouvrir l’aperçu de ton carnet"
        const val readAloud = "Lire ce message à voix haute"
        const val stopReading = "Arrêter la lecture à voix haute"
        const val copy = "Copier ce message"
        const val copied = "Message copié"
        const val edit = "Modifier ce message"

        /** La bulle en retrait : ce que TalkBack dit à la place de la transparence. */
        const val sending = "Envoi en cours"

        /**
         * La coche seule sous un message à soi : il est gardé sur le
         * téléphone, pas encore arrivé (08/10/2026).
         */
        const val storedOnPhone = "Gardé sur ton téléphone"

        /** Les deux coches : le serveur l'a reçu, la retranscription commence. */
        const val delivered = "Bien reçu"

        /** La bulle « Partira demain », dite en entier. */
        const val leavesTomorrow =
            "Gardé sur ton téléphone : partira demain, quand le crédit du jour se rechargera"

        /** La bulle « Trop long pour une journée », dite en entier. */
        const val tooLongForADay =
            "Trop long pour le crédit d’une journée. Gardé sur ton téléphone : il partira dès que tu passeras en illimité"
        const val collapse = "Revenir aux trois boutons"
        const val camera = "Ajouter une photo"
        const val keyboard = "Écrire au clavier"
        const val microphone = "Enregistrer un vocal"
        // « Paramètres » et non « Réglages » : le nom de l'app sur Android.
        const val microphoneDenied = "Micro refusé — ouvrir les Paramètres"
        const val pauseRecording = "Mettre l’enregistrement en pause"
        const val resumeRecording = "Reprendre l’enregistrement"
        const val discardRecording = "Jeter cet enregistrement"
        const val stopRecording = "Arrêter l’enregistrement"
        const val send = "Envoyer"
        const val thinking = "MEMO réfléchit"
        const val play = "Écouter ce vocal"
        const val pause = "Mettre ce vocal en pause"
        const val validated = "Souvenir validé"

        fun voiceNote(duration: String): String = "Vocal de $duration"

        fun transcript(title: String, day: String): String = "$title, $day"

        fun photos(count: Int): String = if (count == 1) "Une photo" else "$count photos"
    }
}
