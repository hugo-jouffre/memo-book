package com.memobook.core

// Les mots du tunnel de commande, au mot près de la maquette. Le jumeau de
// `MemoBookCore/OrderCopy.swift`.
//
// Sur iOS, ils sont rangés sous `BookCopy.Order` comme les autres écrans du
// carnet : le tunnel est une étape du carnet, pas un produit à part. Kotlin ne
// sait pas ajouter un `object` imbriqué à un `object` depuis un autre fichier ;
// ils vivent donc ici, sous le nom du fichier : `BookCopy.Order.Copies.quiz`
// d'iOS est `OrderCopy.Copies.quiz`.

object OrderCopy {
    /**
     * Le titre porté par les sept étapes. Il ne change pas en cours de route :
     * c'est le sous-titre qui dit où on en est.
     */
    const val title = "Commander mon carnet"

    const val help = "Besoin d’aide ?"
    const val next = "Continuer"
    const val retry = "Réessayer"

    // MARK: Étape 1 — Démarrage

    object Start {
        const val cta = "Commencer la commande"

        /** Le carnet n'a jamais été composé : il n'y a rien à commander. */
        const val notComposed = "Ce carnet n’est pas encore généré."
        const val notComposedDetail =
            "Prévisualise-le d’abord : on ne commande pas un carnet qu’on n’a pas vu."

        /** La porte de service de la boîte ci-dessus — voir `OrderModel.ordersWithoutRender`. */
        const val orderAnyway = "Commander ce carnet malgré tout"
    }

    // MARK: Étape 2 — Livraison

    object Shipping {
        const val title = "Adresse de livraison"
        const val name = "Nom complet"
        const val line1 = "Adresse"
        const val line2 = "Complément d’adresse"
        const val postalCode = "Code postal"
        const val city = "Ville"
        const val country = "Pays"

        /**
         * L'invite de **tous** les champs vides de l'adresse, en gris. Le code
         * postal et la ville proposaient « 75015 » et « Paris », qu'on prenait
         * pour des valeurs déjà remplies (Hugo, 06/10/2026).
         */
        const val placeholder = "Clique ici"
    }

    // MARK: Étape 3 — Exemplaires

    object Copies {
        const val title = "Nombre d’exemplaires"
        const val subtitle = "Plusieurs carnets pour offrir à tes proches"
        const val unitPrice = "Prix unitaire"

        /** Au tutoiement (Hugo, 06/10/2026, T211) : la maquette vouvoie, R9 l'emporte. */
        const val customiseTitle = "Personnaliser tes carnets"
        const val customiseSubtitle = "Rends chaque carnet unique"

        const val decorations = "Décorations & stickers"
        const val quiz = "Quiz intégrés à l’histoire"
        const val freeZones = "Zones libres"
        const val crossword = "Mot fléché à la fin du livre"

        const val sameAsFirst = "Par défaut, nous appliquons la même version que ton 1er carnet"
        const val differentFromFirst = "Choisir une version différente du 1er carnet"
        const val backToSameAsFirst = "Reprendre la version du 1er carnet"

        /** Le rang, dit comme la maquette le dit — « 1er Carnet ». */
        fun copyTitle(position: Int): String = if (position == 1) "1er carnet" else "${position}e carnet"

        const val minimumReached = "Il faut au moins un exemplaire."
        const val maximumReached = "Vingt exemplaires au maximum par commande."
    }

    // MARK: Étape 4 — Rapidité

    object Speed {
        const val title = "Rapidité de livraison"
        const val included = "Inclus"
        const val cta = "Voir le récapitulatif"
    }

    // MARK: Étape 5 — Récapitulatif

    object Summary {
        const val title = "Vérifications finales avant impression"
        const val total = "Total"

        /** Le libellé de la ligne qui ferme un groupe (T216). */
        const val subtotal = "Sous-total"
        const val cta = "Valider la commande"

        /** « Carnet - Rome et la Dolce Vita ». */
        fun book(title: String): String = "Carnet - $title"

        /**
         * Ce qui coiffe la description du produit, posée sous son prix. Elle ne
         * se choisit pas : c'est une fabrication et une seule.
         */
        const val specifications = "Ton carnet, en un seul format"
        const val pricedByPages = "Le prix ne dépend que du nombre de pages."

        /** « Carnet · 80 pages », quand le serveur n'a pas donné de libellé. */
        fun bookLine(pages: Int): String = if (pages <= 1) "Carnet · $pages page" else "Carnet · $pages pages"
    }

    // MARK: Étape 6 — Paiement

    object Payment {
        const val title = "Méthode de paiement"

        /** Ce que dit l'étape à la place d'un choix de carte : il se fait dans la feuille de Stripe, en payant. */
        const val inStripeSheet =
            "Tu choisis ta carte en payant, dans la fenêtre sécurisée de Stripe : " +
                "**tes cartes enregistrées y sont**, et tu peux en ajouter une."
        const val address = "Adresse de livraison"
        const val total = "Total"
        const val cta = "Payer"

        /**
         * « Payer » sur un carnet qu'aucune composition n'a encore rendu (Hugo,
         * 06/10/2026, T224). Le bouton ne faisait **rien, sans rien dire** : le
         * tunnel s'ouvre sans rendu — « Commander sans attendre la
         * composition » —, mais on ne paie pas l'impression d'un carnet qui
         * n'existe pas encore. La phrase de Hugo, au mot près.
         */
        const val noRender =
            "Aucun rendu de ton carnet n’a encore été généré, tu ne peux donc pas encore payer ton carnet physique. Retourne dans la conversation de ton voyage pour commencer à générer ton carnet."

        const val failure = "Le paiement a échoué, merci de choisir une autre option."

        /**
         * Le serveur a enregistré la commande mais n'a pas donné de quoi
         * l'encaisser — il lui manque ses clés Stripe.
         *
         * Une panne de configuration, pas un geste à refaire : réessayer n'y
         * changera rien tant que l'API déployée n'a pas ses clés. On le dit donc
         * sans inviter à recommencer, et la commande reste en brouillon,
         * reprenable telle quelle.
         */
        const val unavailable =
            "Le paiement est momentanément indisponible. Ta commande est " +
                "gardée : tu pourras la régler dès que possible."
    }

    // MARK: Étape 7 — Confirmation

    object Confirmation {
        const val title = "Ton carnet prend la route"
        const val delivery = "Livraison"

        // MARK: Le suivi par WhatsApp

        const val whatsapp = "Être informé par whatsapp"
        const val whatsappOn = "Tu seras informé par whatsapp"
        const val whatsappStop = "Ne plus être informé"

        const val whatsappSheetTitle = "Ton numéro WhatsApp"
        const val whatsappSheetSubtitle =
            "On te préviendra quand ton carnet part à l’impression, puis quand il prend la route."
        const val whatsappField = "Numéro de téléphone"
        const val whatsappPlaceholder = "+33 6 12 34 56 78"
        const val whatsappConfirm = "Me prévenir"

        /**
         * ⚠️ Ce que l'écran **ne promet pas**. Aucun message n'est encore
         * envoyé : la commande retient qui prévenir, l'envoi viendra avec le
         * suivi de l'imprimeur. Le dire, plutôt que de laisser croire qu'un
         * message arrive demain.
         */
        const val whatsappNotLiveYet =
            "On garde ton numéro pour ce carnet. Les messages partiront dès que l’imprimeur nous donnera le suivi."

        const val giftTitle = "Envie de l’offrir ?"
        const val giftDetail = "Tu peux recommander un exemplaire depuis ton carnet à tout moment"

        const val share = "Partager le lien de prévisualisation"
        const val home = "Retour à l’accueil"

        /**
         * « Nous préparons Rome et la Dolce Vita avec soin. Tu recevras un email
         * de confirmation sur ton email margaux@gmail.com »
         *
         * L'adresse est optionnelle : un compte entré par Apple peut ne pas en
         * avoir donné, et promettre un email qu'on n'enverra nulle part serait
         * pire que de ne rien promettre.
         */
        fun detail(book: String, email: String?): String {
            val opening = "Nous préparons $book avec soin."
            if (email == null || email.isBlank()) {
                return "$opening Tu recevras un email de confirmation."
            }
            return "$opening Tu recevras un email de confirmation sur ton email $email"
        }

        /** « 2 exemplaires - 50 pages ». Accordé des deux côtés. */
        fun summary(copies: Int, pages: Int?): String {
            val books = if (copies <= 1) "1 exemplaire" else "$copies exemplaires"
            if (pages == null) return books
            return if (pages <= 1) "$books - $pages page" else "$books - $pages pages"
        }
    }
}
