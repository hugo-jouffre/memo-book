package com.memobook.core

// Tout ce que le parcours « carnet » écrit : les paramètres du voyage, la
// composition du PDF, son aperçu et son partage. Le jumeau de
// `MemoBookCore/BookCopy.swift`.
//
// Un seul fichier pour ces écrans, comme `ChatCopy` en tient un pour le
// chat : ils se relisent d'un trait, et R8 (« tous les libellés passent par des
// constantes localisables ») n'a qu'un endroit à tenir.
//
// **Les conventions typographiques de l'app** : apostrophe typographique `’`
// (U+2019) partout, espace insécable avant `?` et `!`, points de suspension `…`
// (U+2026), guillemets français `«  »`.
//
// ⚠️ **Le vouvoiement de la maquette est corrigé ici, et plus recopié**
// (Hugo, 16/09/2026). R8 dit « la copie de Figma au caractère près », R9 dit
// « on tutoie l'utilisateur, toujours » : les deux s'opposaient sur une dizaine
// de phrases du carnet et du voyage, qui vouvoyaient au milieu
// d'une app qui tutoie. R9 l'emporte, comme il l'emportait déjà sur les cinq
// feuilles de l'abonnement (`SubscriptionCopy`). Chaque phrase corrigée le dit
// dans son commentaire, et la liste des écarts vit dans la fiche écran pour que
// Clara les reprenne **à la source**.
//
// Les trois coquilles qui restaient — « grace », « Prévisulation », « Défini »
// — sont corrigées dans Figma et ici (Hugo, 17/09/2026, T67). Et l'ordinal
// s'abrège « 1ère » partout, comme la maquette (T91).
//
// Les liens (`URL` en Swift) sont ici du texte : ce sont ceux que le serveur sert
// (`BookPreview.shareUrl`), recopiés tels quels — `absoluteString` d'iOS.
object BookCopy {

    // MARK: - Paramètres du voyage

    object Settings {
        const val title = "Paramètres du voyage"

        const val adventureSection = "Gère ton aventure"
        const val quickAccessSection = "Accès rapide"

        const val name = "Nom de l’aventure"
        const val dates = "Dates du voyage"
        const val pace = "Rythme du récit"
        const val notifications = "Notifications"
        const val manageNotifications = "Gérer mes notifications"
        const val companions = "Co-voyageur(s)"
        const val theme = "Thème de l’aventure"
        const val publicGallery = "Partager sur la galerie de la communauté"
        const val style = "Style du carnet"

        const val tricountTitle = "Connecte ton Tricount"
        const val tricountMessage =
            "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes dépenses"

        const val pdfPreview = "Prévisualisation PDF"
        const val pdfPreviewDetail = "Aperçu et partage"

        const val order = "Commander le carnet"
        const val help = "Besoin d’aide ?"

        /**
         * Le lien à l'encre juste au-dessus du rouge, sur le même dessin que
         * « Me déconnecter » sur le profil : on efface le fil, pas le voyage
         * (Hugo, 17/09/2026).
         */
        const val clearConversation = "Supprimer la conversation"

        /**
         * Le lien rouge tout en bas de l'écran, sous « Besoin d'aide ? » —
         * le même dessin que « Supprimer mon compte » sur le profil.
         */
        const val delete = "Supprimer ce voyage"

        /**
         * La feuille de confirmation, sur le modèle de celle du voyage. Elle
         * dit ce qui reste autant que ce qui part : le mot d'accueil de MEMO
         * revient, et les souvenirs déjà dans le carnet n'y sont pour rien.
         */
        object ClearConversation {
            const val title = "Supprimer la conversation ?"
            const val body = "Les messages échangés avec MEMO dans ce voyage seront effacés, et la conversation repartira de son mot d’accueil. Les souvenirs déjà enregistrés dans ton carnet sont conservés. C’est immédiat et sans retour."
            const val keep = "Garder la conversation"

            /**
             * La notice sous le lien pâli, pour un co-voyageur : la cause et
             * la sortie (`docs/conversation.md` § 7).
             */
            const val ownerOnly = "Seul le propriétaire du voyage peut supprimer la conversation. Tu peux continuer à raconter, et lui demander si tu veux repartir de zéro."
            const val confirm = "Supprimer la conversation"
        }

        /**
         * La feuille de confirmation, sur le modèle de celle du compte : ce
         * que la suppression emporte, et les deux issues.
         */
        object Delete {
            const val title = "Tu es sûr de vouloir supprimer ce voyage ?"

            /**
             * Ce qui part, dit avant plutôt qu'après. Les commandes passées
             * pour ce carnet partent avec lui — c'est ce que fait
             * `services/deletion.ts`.
             *
             * Sans nom — les réglages n'ont pas chargé, ou le voyage n'en a
             * pas —, la phrase dit « Ce voyage » plutôt que d'ouvrir des
             * guillemets sur du vide, ce qu'elle faisait (Hugo, 16/09/2026).
             */
            fun body(trip: String?): String {
                val trimmed = trip?.trim() ?: ""
                val subject = if (trimmed.isEmpty()) "Ce voyage" else "« $trimmed »"
                return "$subject sera effacé pour toi comme pour tes co-voyageurs : ses souvenirs, ses photos, son carnet et les commandes passées pour lui. C’est immédiat et sans retour."
            }

            const val keep = "Garder ce voyage"
            const val confirm = "Supprimer définitivement ce voyage"
        }

        // MARK: Personnalisations du carnet

        /**
         * La valeur d'une ligne dont le voyage n'a rien à dire. Un tiret cadratin
         * et non une chaîne vide : une ligne sans valeur se lirait comme une
         * valeur qui n'a pas chargé.
         */
        const val noValue = "—"
    }

    // MARK: - Personnalisations du carnet

    object Customisation {
        const val title = "Personnalisations du carnet"

        /**
         * **Corrigée** : la maquette vouvoie (« Ajuster les différents
         * options … votre carnet vous ressemble »), avec un infinitif là où il
         * faut un impératif et un accord manquant. R9 — « on tutoie
         * l'utilisateur, toujours » — l'emporte ici sur R8, tranché par Hugo
         * le 16/09/2026 pour toute la copie du carnet et du voyage. L'écart
         * est à reprendre à la source dans Figma.
         */
        const val intro =
            "Ajuste les différentes options de MemoBook pour que ton carnet te ressemble de plus en plus."

        const val covers = "Couvertures (1ère & 4e)"
        const val coversDetail = "Aperçu et personnalisation"

        const val photoTextRatio = "Ratio photo / texte"
        const val targetPageCount = "Nombre de page cible"

        const val funFacts = "Fun facts"
        const val rules = "Pointillés"
        const val decorations = "Décorations & stickers"

        /**
         * **Une seule ligne pour les quatre polices** (Hugo, 16/09/2026),
         * rangée avec les décors : on règle l'allure du carnet d'un bloc.
         * Elle remplace « Typographie des titres » et ses trois sœurs.
         */
        const val fonts = "Typographies"

        /**
         * L'état d'un décor qu'on active ou non. Deux mots, pas un
         * interrupteur : la maquette en fait une ligne qui **mène** à un choix,
         * et le réglage aura plus de deux valeurs le jour où le gabarit les
         * acceptera.
         */
        fun toggleValue(isOn: Boolean): String = if (isOn) "Activé" else "Désactivé"

        const val extrasSection = "Extras"

        /**
         * Les cinq pastilles de la tête de l'écran (V3, `3595:23807`), **au
         * caractère près** : « Typos » est une abréviation de la maquette, pas
         * la nôtre (R8). « Nmb de pages » en était une aussi ; elle s'écrit
         * en entier depuis le 06/10/2026 (Hugo, T214).
         */
        const val categoryRatio = "Ratio media"
        const val categoryPages = "Nombre de pages"
        const val categoryDecorations = "Décorations & stickers"
        const val categoryFonts = "Typos"
        const val categoryExtras = "Extras"

        const val quizTitle = "Quiz intégrés à l’histoire"
        const val quizDetail =
            "MemoBook génère des mini quiz au fur et à mesure du récit. Découvre-les et réponds lors de la réception de ton carnet."

        const val freeZonesTitle = "Zones libres"
        const val freeZonesDetail =
            "Ajoute 1 zone blanche à la fin de chaque étape et 3 pages blanches à la fin du carnet"

        const val crosswordTitle = "Mot fléché à la fin du livre"
        const val crosswordDetail =
            "MemoBook génère une grille de mot fléché automatiquement à partir de tes récits, au moment de commander ton livre et la place à la fin du carnet."
    }

    // MARK: - Les couvertures

    /**
     * Ce qu'écrit le parcours des deux plats : le choix, le style, la photo,
     * les textes et les chiffres du dos.
     *
     * [matchedStyle] vouvoyait dans la maquette — « Assortie à votre 1e de
     * couverture » ; elle tutoie depuis, et l'ordinal s'écrit « 1ère » comme
     * partout dans l'app (Hugo, 17/09/2026, T91).
     */
    object Covers {
        const val title = "Couvertures"

        /**
         * Le sous-titre de l'en-tête, différent à chaque étape : il dit ce
         * qu'on est en train de changer.
         */
        const val styleSubtitle = "Changer le style graphique"
        const val photoSubtitle = "Changer la photo de couverture"
        const val textsSubtitle = "Modifier le titre et sous-titre"

        /**
         * Le titre du dos « Dessin » : celui de la maquette de Hugo
         * (`assets/covers`, 08/10/2026). Le dos n'a pas de titre qu'on écrit
         * — seulement son texte de quatrième.
         */
        const val drawingBackHeading = "La route continue…"

        /**
         * Les trois lignes de l'écran d'accueil des couvertures. La première
         * dit « Changer **de** style », la ligne de l'en-tête « Changer **le**
         * style » : c'est la maquette, et les deux se lisent bien.
         */
        const val changeStyle = "Changer de style graphique"
        const val changePhoto = "Changer la photo de couverture"
        const val editTexts = "Modifier les textes"

        const val validate = "Valider"
        const val choosePhoto = "Choisir la photo"
        const val importPhoto = "Importer ma photo"

        const val matchedStyle = "Assortie à ta 1ère de couverture"

        /**
         * La photo choisie n'a pas pu être lue. Aucune maquette ne dessine cet
         * état ; la phrase dit ce qui s'est passé et ce qu'on peut faire,
         * plutôt que de laisser le carrousel inchangé sans explication.
         */
        const val importFailed =
            "Cette photo n’a pas pu être ouverte. Choisis-en une autre."

        // MARK: Ce qu'un style ne permet pas

        /**
         * Pourquoi ce plat n'a pas de texte à écrire.
         *
         * **Elle nomme la cause et donne la sortie**, dans cet ordre : sans le
         * second bout, on comprend qu'on ne peut pas sans savoir quoi faire —
         * et le geste qui débloque est deux écrans plus haut.
         */
        fun noTextHere(face: CoverFace): String =
            "Le style choisi pour ta ${face.title} **ne porte aucun texte** : la photo occupe tout le plat. Change son style graphique pour pouvoir y écrire."

        /** Pourquoi ce plat n'a pas de photo à choisir. */
        fun noPhotoHere(face: CoverFace): String =
            "Le style choisi pour ta ${face.title} **ne porte aucune photo** : c’est un aplat. Change son style graphique pour en ajouter une."

        /**
         * Le titre par défaut d'une première de couverture qu'on n'a pas encore
         * écrite. Le nom du voyage, et non un texte d'invite : un plat vide se
         * lirait comme un carnet raté.
         */
        fun defaultTitle(trip: String): String = trip

        object Voice {
            const val carousel = "Couvertures proposées"
            const val selected = "Couverture sélectionnée"
            const val photo = "Photo de couverture"
            fun style(name: String): String = "Style $name"
            const val editTitle = "Modifier le titre"
            const val editSubtitle = "Modifier le sous-titre"
            const val editStats = "Modifier les chiffres du voyage"
            const val previousCover = "Couverture précédente"
            const val nextCover = "Couverture suivante"
        }

        // MARK: Les chiffres du dos

        object Stats {
            const val title = "Choix des statistiques"

            /**
             * « Choisis-en 3 ou 4 ». Les deux bornes viennent du gabarit —
             * voir [BookCovers.statRange].
             */
            const val message = "Choisis-en 3 ou 4"

            /** Ce qui s'imprime au-dessus des chiffres, sur le plat. */
            const val heading = "Mon voyage en quelques chiffres"
        }
    }

    // MARK: - On compose ton Carnet

    object Composition {
        const val title = "On compose ton carnet"
        const val message =
            "Images, souvenirs, cartes et petits détails trouvent leur place dans une mise en page unique"

        /**
         * Ce que TalkBack annonce pendant la composition. L'animation, elle,
         * est purement décorative et masquée : décrire une page qui se monte
         * morceau par morceau ne dirait rien de plus que cette phrase.
         */
        const val voiceOverStatus = "Composition du carnet en cours"

        /**
         * Sous la phrase de la phase, sur la page qui se monte (08/10/2026) :
         * sans elle, une page qui se remonte pour la troisième fois se lirait
         * comme une boucle cassée. **Sans maquette** : à relire (T253).
         */
        const val patience = "Ça peut prendre quelques minutes."

        /**
         * La composition n'a pas bougé depuis plusieurs minutes : l'écran
         * cesse d'attendre et propose de réessayer (19/10/2026). Le serveur
         * relance de lui-même une composition restée en plan quand on
         * réessaie. **Sans maquette** : à relire par Clara.
         */
        const val tooLong =
            "La composition prend plus de temps que prévu. Réessaie dans un moment."

        /**
         * Ce que la composition fait en ce moment, sur la page qui se monte
         * (06/10/2026 ; en carte par-dessus la page depuis le 08/10/2026). Une
         * composition dure plusieurs minutes — la mise en page attend jusqu'à
         * trois minutes les souvenirs encore en rédaction —, et une page montée
         * en 2,6 s puis immobile se lirait comme un écran figé. **Sans
         * maquette** : à relire par Clara (T143).
         *
         * `null` avant le premier sondage, et sur un serveur qui ne dit pas la
         * phase : la ligne reprend alors la plus générale.
         */
        fun phase(phase: BookRenderPhase?, pendingMemories: Int): String = when (phase) {
            BookRenderPhase.Queued -> "Ton carnet attend son tour…"
            BookRenderPhase.Writing -> when {
                pendingMemories == 1 -> "On attend la fin de la rédaction d’un souvenir…"
                pendingMemories > 1 -> "On attend la fin de la rédaction de $pendingMemories souvenirs…"
                else -> "On met tes souvenirs en pages…"
            }
            BookRenderPhase.Composing, BookRenderPhase.Ready -> "On fabrique le PDF de ton carnet…"
            BookRenderPhase.Failed, is BookRenderPhase.Unknown, null -> "La composition de ton carnet est lancée…"
        }
    }

    // MARK: - Aperçu PDF

    object Preview {
        const val title = "Aperçu PDF"

        /**
         * Le titre de la **feuille** d'aperçu, celle qu'ouvre la pastille
         * « Voir un aperçu » du paywall.
         *
         * Différent de [title], et c'est la maquette qui le veut : l'écran
         * annonce un format (« Aperçu PDF »), la feuille annonce un geste
         * (« Prévisualisation »). On ne vend pas un PDF, on montre un carnet.
         */
        const val sheetTitle = "Prévisualisation"

        /**
         * Le retour, quand l'aperçu est une **étape** d'une autre feuille — la
         * feuille d'abonnement. On est venu voir ce qu'on achète, on repart
         * d'où l'on venait.
         */
        const val backToOffer = "Revenir à l’offre"

        /**
         * « Rome et la Dolce Vita - 10 pages composées ».
         *
         * ⚠️ Le tiret entouré d'espaces est celui de la maquette (R8). Le
         * pluriel, lui, est accordé : un carnet d'une seule page arrive au
         * premier souvenir raconté.
         */
        fun subtitle(title: String, pages: Int): String {
            val composed = if (pages == 1) "1 page composée" else "$pages pages composées"
            return "$title - $composed"
        }

        /** « Page 4 / 10 ». */
        fun pageIndicator(index: Int, of: Int): String = "Page $index / $of"

        /**
         * « 1 sur 24 » — le compteur de l'aperçu plein écran. Il compte les
         * **feuilles du PDF**, là où l'indicateur du bas compte les pages du
         * carnet : les deux diffèrent dès qu'une page tient sur deux feuilles.
         */
        fun sheetIndicator(index: Int, of: Int): String = "$index sur $of"

        const val customise = "Personnaliser mon carnet"

        /**
         * La porte vers les couvertures, **toujours là** sous les boutons :
         * l'invitation sur la page ne s'affiche que tant qu'elles ne sont pas
         * choisies, et l'aperçu n'offrait plus aucun chemin pour y revenir
         * (Clara, 17/09/2026). Aucune maquette : un lien vert, au corps des
         * boutons, comme « Besoin d'aide ? ».
         * ⚠️ Plus de bouton « Configurer mes couvertures » sous l'aperçu
         * (Hugo, 19/09/2026) : les couvertures se choisissent en touchant le
         * voile de la première ou de la dernière page. La phrase reste, elle
         * intitule l'invitation posée sur la page.
         */
        const val configureCovers = "Configurer mes couvertures"

        /**
         * Le titre d'un aperçu en pages blanches, quand le serveur n'a
         * rien dit du carnet — voir `BookPreviewModel.showsBlankPages`.
         * Debug seulement : Swift le garde sous `#if DEBUG` ; `:core` n'a pas de
         * drapeau de build, c'est l'écran qui ne le lit que sous `BuildConfig.DEBUG`.
         */
        const val blankTitle = "Carnet sans contenu"

        /**
         * Sous l'en-tête de l'aperçu, tant qu'une étape validée recompose le
         * carnet en fond — voir `BookPreviewModel.isRecomposing`. Léger et
         * temporaire : les pages déjà là restent feuilletables pendant ce
         * temps.
         */
        const val recomposing = "On remet à jour ton carnet…"

        /**
         * Ce qu'on lit dans le PDF d'attente, celui que l'app compose quand le
         * carnet du serveur n'est pas chargé — voir `BookPreviewModel`. Les
         * treize espaces du milieu sont ceux de la chaîne Swift, au caractère près.
         */
        const val placeholderPdfBody =
            "Ce carnet n’est pas encore composé : ce fichier tient sa place,             le temps que MemoBook mette en page tes souvenirs."
        const val order = "Commander ce carnet"

        /**
         * La porte de service, sous le bouton grisé : commander alors que le
         * carnet n'est pas composé.
         *
         * ⚠️ **Elle est dans la version livrée**, et pas seulement en debug
         * (Hugo, 16/09/2026) : le tunnel de commande ne se teste pas de bout
         * en bout autrement — il faut un TestFlight, et un TestFlight ne
         * compile pas `#if DEBUG`. Elle est écrite en **lien souligné**, à
         * l'encre depuis le 06/10/2026 (T219 : le beige ne se lisait pas),
         * pour que personne ne la prenne pour l'appel à l'action, et elle dit
         * ce qu'elle fait plutôt que « Commander quand même ».
         */
        const val orderAnyway = "Commander sans attendre la composition"

        const val configureCover = "Définis maintenant\nta 1ère et 4ème de couverture"
        const val configureCoverAction = "Configurer"

        object Voice {
            const val previousPage = "Page précédente"
            const val nextPage = "Page suivante"
            const val enterFullScreen = "Afficher en plein écran"
            const val exitFullScreen = "Quitter le plein écran"
            const val share = "Partager mon carnet"
        }

        /**
         * Le PDF n'a pas pu se charger. Le carnet existe, c'est le
         * téléchargement qui a échoué : on propose donc de réessayer, pas de
         * recomposer.
         */
        const val loadFailed = "L’aperçu n’a pas pu se charger."
        const val retry = "Réessayer"
    }

    // MARK: - Un mot des fondateurs

    object Founders {
        const val title = "Un mot des fondateurs"

        /**
         * « Hello Margaux, » — le prénom vient du compte. Sans prénom, la
         * phrase se contente du bonjour : « Hello , » serait pire que rien.
         */
        fun hello(firstName: String?): String {
            if (firstName.isNullOrEmpty()) return "Hello,"
            return "Hello $firstName,"
        }

        const val intro = "On a créé MemoBook avec une idée très simple :"

        /**
         * La ligne manuscrite, en vert. C'est **la** phrase du mot, celle qui
         * justifie d'avoir embarqué une police d'écriture à la main.
         */
        const val promise =
            "Tes souvenirs ont trop de valeur pour rester oubliés dans ton téléphone !"

        /**
         * Les quatre paragraphes du mot, séparés par un blanc.
         *
         * Une liste et non une chaîne à `\n\n`, pour la même raison que
         * `BrandSheet` : une ligne vide ne se lit pas à TalkBack.
         */
        val body: List<String> = listOf(
            "On espère que ce premier aperçu te donnera le sourire.",
            "Notre application est encore en plein développement.",
            "N’hésite pas à nous envoyer tes retours. On travaille en continu pour rendre ton expérience plus fluide.",
            "Merci de faire partie de l’aventure !",
            "À très vite,",
        )

        const val signature = "Co-fondateurs de MemoBook"
        const val signatureVoice = "Paul et Hugo"

        const val feedback = "Partager mes retours"
        const val carryOn = "Continuer à découvrir mon carnet"

        /**
         * L'adresse où partent les retours. Un `mailto:` et non un formulaire :
         * il n'y a pas de back-end derrière, et le courrier électronique laisse
         * une trace des deux côtés.
         */
        const val feedbackAddress = "hello@memobook.fr"
        const val feedbackSubject = "Mes retours sur MemoBook"
    }

    // MARK: - Partager son MemoBook

    object Share {
        const val title = "Partager ton MemoBook"
        const val message =
            "Partage un fichier PDF accessible hors connexion et sur l’outil de ton choix ou partage un lien de prévisualisation permettant de suivre l’avancée de ton carnet en direct."

        const val sharePdf = "Partager le fichier pdf"
        const val shareLink = "Partager le lien de prévisualisation"

        /**
         * Le message pré-rempli dans WhatsApp, Messages ou Snapchat.
         *
         * Il dit trois choses, dans cet ordre : ce qu'on prépare, où on en
         * est, et où le suivre. Il demandait d'aider à financer la version
         * imprimée, par la cagnotte ; elle est partie (Hugo, 06/10/2026,
         * T230), et le lien ne mène plus qu'au carnet.
         *
         * **Il compte des pages, et le dit** (07/10/2026). Il annonçait « mes
         * 10 premières étapes » en comptant les pages du carnet : l'aperçu et
         * la commande ne connaissent pas les étapes, seulement les pages
         * composées. Sans page — un carnet pas encore composé —, la phrase du
         * compte se tait plutôt que d'annoncer « 0 page ».
         *
         * Le titre du carnet est entre guillemets **français** ; la
         * spécification de Hugo employait des guillemets anglais fermants des
         * deux côtés, ce qui est une glissade de clavier. Signalé.
         */
        fun invitation(title: String, pages: Int, link: String): String {
            val opening = "Je prépare le carnet de mon voyage « $title »."
            val follow = "Tu peux suivre son avancée en direct sur ce lien : $link"
            if (pages <= 0) return "$opening $follow"
            val count = if (pages == 1) "1 page" else "$pages pages"
            return "$opening Il compte déjà $count ! $follow"
        }

        /**
         * Le sujet, quand l'app de destination en demande un — le courrier
         * électronique, essentiellement.
         */
        fun subject(title: String): String = "Mon carnet de voyage « $title »"

        /**
         * Les deux gestes que la feuille du système ajoute à ses apps
         * (`3551:26331`), recopiés tels quels (R8).
         */
        const val orderAction = "Commander"
        const val whatsAppAction = "Partager sur Whatsapp"

        /**
         * Le lien de prévisualisation n'existe pas encore et n'a pas pu se
         * créer. On le dit sans jargon : ce n'est pas la faute de
         * l'utilisateur, et le PDF reste partageable.
         */
        const val linkFailed =
            "Le lien de prévisualisation n’a pas pu se créer. Le fichier PDF, lui, reste partageable."
    }

    // MARK: - Les feuilles des réglages du voyage
    //
    // Copie reprise des nœuds de la page « 🤖 Claude Import » (section « Trip
    // settings ») — R8 pour tout ce qui n'est pas une adresse à la personne, et
    // R9 pour ce qui l'est : les phrases qui vouvoyaient sont **corrigées** et
    // le disent, au lieu d'être recopiées (voir l'en-tête du fichier).

    /** « Dates » — `3443:9881`. */
    object Dates {
        const val title = "Dates"
        const val start = "Date de début"
        const val end = "Date de fin (optionnel)"
    }

    /** « Rythme du récit » — `3443:9841`. */
    object Pace {
        const val title = "Rythme du récit"

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val subtitle =
            "Ajuste le style de narration généré par l’IA pour refléter au mieux tes émotions et ta personnalité."
    }

    /** « Notifications » — `3443:9895`. */
    object Notifications {
        const val title = "Notifications"

        /**
         * **Corrigée au tutoiement** — voir [Customisation.intro]. Le nom
         * du voyage est glissé dedans : la maquette écrit « Rome » en dur,
         * l'app met celui qu'on regarde.
         */
        fun subtitle(trip: String): String =
            "Active ou désactive les alertes d’écriture du voyage à « $trip » pour ne rien rater sans être dérangé non plus."

        /**
         * Le second paragraphe du chapeau, sur un voyage partagé : ces
         * alertes ne valent que pour qui les règle (D13, Hugo, 19/10/2026).
         * Elles valaient pour tout le monde, et couper la sienne coupait
         * celle des autres sans qu'ils le sachent.
         *
         * ⚠️ **Pas dans la maquette** — texte à relire par Clara.
         */
        const val personalNote =
            "Ces réglages ne valent que pour toi : tes co-voyageurs choisissent les leurs."

        const val writingReminder = "Rappel d’écriture"
        const val writingReminderDetail = "Alerte selon le rythme du récit choisi"
        const val newStory = "Nouveau récit"
        const val newStoryDetail = "Lorsqu’un proche alimente le carnet"
        const val weeklyDigest = "Résumé hebdomadaire"
        const val weeklyDigestDetail = "Un point sur les souvenirs capturés"
        const val tripEnd = "Rappel de fin de voyage"
        const val tripEndDetail = "Alerte pour valider l’impression finale"

        /**
         * Ce que la feuille dit quand l'interrupteur maître est baissé : les
         * quatre alertes restent lisibles, mais aucune ne partira.
         */
        const val mutedNotice =
            "Les notifications de ce voyage sont coupées : ces alertes reprendront quand tu les rallumeras."

        /**
         * Ce que la feuille dit quand le système refuse tout — la personne a dit
         * non à la question du système, ou a tout coupé dans les Réglages. Les
         * alertes s'enregistrent, mais aucune n'arrivera.
         *
         * ⚠️ **Pas dans la maquette** : la feuille `3023:15042` ne dessine que
         * les quatre cartes. Texte à relire par Clara. La phrase dit « iPhone »
         * comme sur iOS : la copie est partagée, à reprendre pour Android.
         */
        const val systemDeniedNotice =
            "Les notifications de MemoBook sont coupées dans les réglages de ton iPhone : aucune de ces alertes ne t’arrivera."
        const val openSettings = "Ouvrir les réglages"
    }

    /** « Thème de l’aventure » — `3443:9937`. */
    object Theme {
        const val title = "Thème de l’aventure"

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val subtitle =
            "Le thème ajuste le vocabulaire de l’IA et l’agencement graphique de tes souvenirs imprimés."

        const val placeholder = "Trek entre amis"
        const val validate = "Valider"
    }

    /** « Inviter un proche » — `3443:9805`. */
    object Invite {
        const val title = "Inviter un proche"

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val subtitle =
            "Invite tes proches à participer au récit, à ajouter leurs médias et à co-valider les étapes."

        const val listTitle = "Co-voyageur(s) actuels"

        /** Sous la ligne de **celui qui lit**, propriétaire ou non (18/10/2026). */
        const val me = "Moi"

        /** Sous les autres lignes, propriétaire compris. */
        const val companion = "Co-voyageur"
        const val owner = "Propriétaire\ndu voyage"
        const val pending = "Invitation envoyée"

        /** Le message d'invitation : le lien, puis le code pour l'entrer à la main. */
        fun invitation(tripTitle: String, code: String, link: String?): String {
            val intro = "Rejoins-moi sur MemoBook pour raconter « $tripTitle »."
            if (link == null) return "$intro Code d’accès : $code"
            return "$intro $link\nCode d’accès : $code"
        }

        /** Un lien d'invitation dont le code ne mène à aucun voyage. */
        const val linkNotFound =
            "Ce lien d’invitation ne mène à aucun voyage. Demande à celui qui t’a invité de te le renvoyer."

        fun accessCode(code: String): String = "Code d’accès : $code"
        const val copied = "Code copié"
        const val whatsapp = "Partager via Whatsapp"
        const val share = "Partager"

        const val remove = "Retirer"
        const val resend = "Renvoyer"
        fun resent(name: String): String = "Invitation renvoyée à $name."

        /**
         * Ce que la liste dit quand on voyage seul. La maquette ne le dessine
         * pas — écart signalé, et une liste vide sous un titre se lirait comme
         * un chargement qui n'a pas abouti.
         */
        const val empty = "Tu racontes ce voyage seul pour l’instant."

        fun removeConfirmation(name: String): String = "Retirer $name de ce voyage ?"
        const val removeMessage =
            "Cette personne ne pourra plus raconter ni ajouter de photos. Ses souvenirs, eux, restent dans le carnet."
        const val cancel = "Annuler"

        /**
         * Le geste que la note « Logique » décrit : maintenir ou glisser vers
         * la gauche ouvre les deux actions.
         */
        const val gestureHint = "Glisse une ligne vers la gauche pour la retirer."
    }

    // MARK: - Les feuilles de la personnalisation du carnet

    /** « Ratio média » — `3443:10212`. */
    object Ratio {
        const val title = "Ratio média"

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val subtitle =
            "Détermine l’importance visuelle des images par rapport aux textes générés au sein des chapitres."

        const val more = "Plus de photos"
        const val less = "Plus de texte"

        /** « 50 / 50 », la valeur en grand au-dessus du curseur. */
        fun value(photos: Int): String = "$photos / ${100 - photos}"

        /**
         * La ligne bleue sous la valeur. Elle **qualifie** l'équilibre choisi
         * plutôt que de le répéter en chiffres.
         */
        fun quality(photos: Int): String = when {
            photos < 25 -> "Le récit avant tout"
            photos < 50 -> "Surtout du texte"
            photos == 50 -> "Équilibre parfait"
            photos <= 75 -> "Surtout des photos"
            else -> "Un album avant tout"
        }
    }

    /** « Nombre de page » — `3443:10177`. */
    object Pages {
        // MARK: La cible hors d'atteinte (Hugo, 18/10/2026)

        const val reachTitle = "Cette cible est hors d’atteinte"

        /** Ce que le carnet peut faire aujourd'hui, avec les réglages du moment. */
        fun reachToday(reach: PageTargetReach): String =
            "Avec tes réglages actuels (${reach.ratio} % de photos), ton carnet peut faire entre " +
                "${reach.range.min} et ${reach.range.max} pages. ${reach.target} pages ne sont pas atteignables pour l’instant."

        /** Comment aller chercher la cible voulue. */
        fun reachLevers(reach: PageTargetReach): String {
            if (reach.isTooLong) {
                val ratio = reach.ratioThatReaches?.let { ", ou monte le ratio photo / texte à $it %" } ?: ""
                return "Pour atteindre ${reach.target} pages : raconte plus de souvenirs, envoie plus de photos quand je te les demande$ratio."
            }
            return "Pour descendre à ${reach.target} pages : raconte moins d’étapes, ou des souvenirs plus courts. " +
                "Le texte que tu as validé n’est jamais coupé."
        }

        fun chooseReachable(pages: Int): String = "Choisir $pages pages"
        fun raiseRatio(ratio: Int): String = "Passer à $ratio % de photos"
        fun keepAnyway(pages: Int): String = "Garder $pages pages quand même"

        const val title = "Nombre de page"

        /**
         * La phrase de la V3 (`3595:23920`), telle quelle : elle tutoie
         * désormais dans Figma. « plus de page » au singulier est celui de la
         * maquette (R8).
         */
        const val subtitle =
            "Gère le niveau de détails de ton carnet en permettant à notre outil d’utiliser plus de page."

        /**
         * La ligne verte sous le chapeau. Elle dit **sur quoi** les
         * projections sont faites — la maquette écrit « 2 mois » en dur, l'app
         * met la durée du voyage qu'on regarde.
         */
        fun estimates(duration: String): String = "Estimations pour un voyage de $duration"

        const val customTitle = "Nombre de pages cible"
        const val validate = "Valider"

        // MARK: Changer la cible (Hugo, 15/10/2026)

        /**
         * Le titre de la feuille qui accompagne un changement de cible — une
         * seule feuille, dont le contenu change d'étape en étape.
         */
        const val changeTitle = "Nombre de pages cible"

        /**
         * Ce qu'on dit **avant** de changer, quand le changement compte. Les
         * deux phrases de Hugo : la règle quand on a encore les deux, et ce
         * qui reste quand il n'y en a plus qu'un. Sans balisage : c'est le
         * chapeau d'une `BrandSheet`, qui ne lit pas le gras.
         */
        fun changeWarning(changesLeft: Int): String =
            if (changesLeft <= 1) {
                "Il ne te reste plus qu’un seul changement de nombre de pages cible pour ce voyage."
            } else {
                "Tu peux changer le nombre de pages cible deux fois pendant ce voyage : chaque changement peut réécrire tout ton carnet."
            }

        const val confirmChange = "Changer le nombre de pages cible"
        const val cancelChange = "Annuler"

        /**
         * Les deux changements sont faits. Dit à l'orange, sur la feuille
         * comme sous les paliers pâlis.
         */
        const val limitReached =
            "Tu as utilisé tes deux changements : **le nombre de pages cible ne peut plus changer** pour ce voyage."
        const val understood = "Compris"

        /**
         * Sans date de fin, l'app ne sait pas où en est le voyage : elle le
         * demande.
         */
        const val stageTitle = "À quel stade de ton voyage en es-tu ?"
        const val stageBeginning = "Plutôt au début"
        const val stageMiddle = "Environ à la moitié"
        const val stageEnd = "Plutôt à la fin"

        const val doneTitle = "C’est noté"

        /**
         * « récit compact », « récit de 70 pages » — le nom du récit qu'une
         * cible donne, pour la phrase de [doneSummary].
         *
         * `withPageCount` ajoute le nombre au palier nommé (« récit détaillé
         * de 40 pages ») : face à une cible personnalisée, le nom seul peut
         * contredire le sens — 60 pages vers « Détaillé » sur un voyage de
         * trois semaines, c'est condenser.
         */
        fun storyName(pageCount: Int, tripDays: Int?, ratio: Int = 50, withPageCount: Boolean = false): String {
            val name = when (BookPageTarget.matching(pageCount, tripDays, ratio)) {
                BookPageTarget.Compact -> "récit compact"
                BookPageTarget.Standard -> "récit standard"
                BookPageTarget.Detailed -> "récit détaillé"
                BookPageTarget.Custom -> return "récit de $pageCount pages"
            }
            return if (withPageCount) "$name de $pageCount pages" else name
        }

        /**
         * « On passe d'un récit compact à un récit détaillé. Les prochaines
         * étapes seront donc plus étoffées. » Le sens se lit dans les
         * nombres, pas dans les noms : deux cibles personnalisées n'ont pas
         * d'ordre à elles.
         */
        fun doneSummary(from: Int, to: Int, tripDays: Int?, ratio: Int = 50): String {
            val custom = listOf(from, to).any { BookPageTarget.matching(it, tripDays, ratio) == BookPageTarget.Custom }
            val before = storyName(from, tripDays, ratio, withPageCount = custom)
            val after = storyName(to, tripDays, ratio, withPageCount = custom)
            val next = if (to > from) "plus étoffées" else "moins étoffées"
            return "On passe d’un $before à un $after. Les prochaines étapes seront donc $next."
        }

        /**
         * Vers la fin du voyage seulement : ce qui est écrit pèse plus que
         * ce qui reste, et le carnet serait coupé en deux.
         */
        fun rewriteOffer(isLonger: Boolean): String {
            val verb = if (isLonger) "étoffe" else "condense"
            return "Si tu veux que l’on $verb le récit des étapes déjà écrites pour qu’il soit homogène avec la suite de ton carnet, c’est juste en dessous."
        }

        fun rewriteAction(isLonger: Boolean): String =
            if (isLonger) "Étoffer les étapes déjà écrites" else "Condenser les étapes déjà écrites"

        const val later = "Plus tard"
        const val ok = "OK"

        /**
         * Le lien sous les paliers, tant que la réécriture reste ouverte —
         * pour qui a répondu « Plus tard ». Il ne sait plus dans quel sens la
         * cible a bougé : il dit ce qu'il fait, sans le sens.
         */
        const val rewriteLink = "Mettre les étapes déjà écrites à la nouvelle cible"

        /** Ce que dit le panneau une fois la réécriture lancée. */
        const val rewriteStarted =
            "**On réécrit les étapes déjà écrites** à ton nouveau nombre de pages. Ça se fait en arrière-plan : tu peux continuer."
    }

    /** « Fun Facts » — `3443:10105`. */
    object FunFacts {
        const val title = "Fun facts"
        const val toggle = "Insérer des Fun facts"

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val detail =
            "Encarts de culture générale toutes les 3 pages pour agrémenter tes récits."
    }

    /** « Pointillés » — `3443:10126`. */
    object Rules {
        const val title = "Pointillés"
        const val toggle = "Pointillés"

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val detail = "Lignes en pointillé sous le texte dans ton carnet"

        /**
         * Ce que dit l'interrupteur grisé quand on le touche : la cause, et la
         * sortie (Hugo, 02/10/2026). Il nomme l'assortiment par défaut et la
         * pastille des typographies — un test vérifie que les deux noms
         * suivent [BookFontCombo.travelJournal] et [Customisation.categoryFonts].
         */
        const val locked =
            "Les pointillés ne s’impriment qu’avec la typographie Carnet de voyage. Choisis-la dans Typos pour les retrouver."

        /**
         * Ce que dit la feuille des typographies, quand l'assortiment qu'on
         * vient de choisir a éteint des pointillés allumés (Hugo, 02/10/2026).
         * L'interrupteur est dans une autre pastille : sans cette phrase, le
         * voyageur ne saurait pas qu'il a perdu quelque chose.
         */
        fun withdrawn(by: BookFontCombo): String =
            "${by.name} s’imprime sans pointillés : on les a retirés. Ils reviendront si tu repasses sur ${BookFontCombo.travelJournal.name}."
    }

    /**
     * « Typographies du carnet » — l'héritière de « Titres du carnet »
     * (`3443:10073`).
     *
     * ⚠️ **L'écran ne suit plus la maquette ici** (Hugo, 16/09/2026) : celle-ci
     * dessine une feuille par rôle, où l'on marie librement trois familles. On
     * propose désormais quatre assortiments — voir [BookFontCombo] — parce
     * qu'un carnet imprimé ne se rattrape pas et que la plupart des mariages
     * libres sont ratés. À reprendre dans Figma.
     */
    object Fonts {
        const val title = "Typographies du carnet"

        /** La phrase de la V3 (`3595:24009`). */
        const val subtitle =
            "Choisis la typographie de tes titres, sous-titres, paragraphes et fun facts"

        /**
         * Ce que la ligne de l'écran affiche quand le carnet ne porte aucun
         * des quatre assortiments — un carnet composé police par police avant
         * cette feuille. On ne coche pas de force, on le nomme.
         */
        const val custom = "Personnalisé"
    }

    /** « Décorations & stickers » — `3443:10147`. */
    object Decorations {
        const val title = "Décorations\n& stickers "

        /** **Corrigée au tutoiement** — voir [Customisation.intro]. */
        const val subtitle = "Détermine la quantité de décorations dans tes pages"

        /**
         * « par étape » et non plus « par paragraphe ou image » : c'est ce
         * que le carnet compte (Hugo, 14/10/2026).
         */
        const val sliderLabel = "Quantité de décorations par étape"
    }
}
