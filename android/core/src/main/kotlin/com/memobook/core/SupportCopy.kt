package com.memobook.core

/**
 * Tout ce que l'écran « Support et retours » et ses trois feuilles écrivent.
 * Le jumeau de `MemoBookCore/SupportCopy.swift`.
 *
 * Le **contenu** des réponses, lui, vit dans [Faq] : c'est de la copie
 * rédactionnelle qui se relit et se corrige toute seule, et elle a sa propre
 * source de vérité (la page Notion « FAQ in-app MemoBook »).
 *
 * Mêmes conventions typographiques que `BookCopy` : apostrophe `’` (U+2019),
 * espace insécable avant `?` et `!`, points de suspension `…` (U+2026).
 *
 * Les trois coquilles de la maquette — « tu ne trouve », « Ecris », « bref
 * délais par whatsapp » — sont corrigées dans Figma et ici (Hugo, 17/09/2026,
 * T92).
 */
object SupportCopy {
    const val title = "Support et retours"

    /**
     * « Hello Margaux, » — le prénom vient du compte, comme pour le mot des
     * fondateurs. Sans prénom, la phrase se contente du bonjour.
     */
    fun hello(firstName: String?): String {
        if (firstName.isNullOrEmpty()) return "Hello,"
        return "Hello $firstName,"
    }

    /** Les deux paragraphes de présentation, sous la photo. */
    val intro = listOf(
        "Nous sommes Paul & Hugo, les développeurs de MemoBook. On adore voyager et on veut rendre la création des carnets de voyage rapide, intelligente et authentique.",
        "Voici notre foire aux questions, en espérant que celle-ci réponde à tes interrogations. Tu auras la possibilité de nous écrire si tu ne trouves pas de réponse.",
    )

    // La recherche

    /**
     * Ce que le champ propose quand il est vide. Il dit **où** l'on cherche.
     *
     * ⚠️ **Aucune maquette ne dessine ce champ** (Hugo, 16/09/2026) : c'est le
     * point 2 de la page Notion — « recherche interne » — qui attendait un
     * écran. Il est écrit sur le motif des autres champs de l'app, au
     * tutoiement, et reste à dessiner dans Figma.
     */
    const val searchPlaceholder = "Rechercher une question"

    /** Ce que la recherche a trouvé, annoncé sous le champ. */
    fun searchResults(count: Int): String =
        if (count == 1) "1 question trouvée" else "$count questions trouvées"

    /**
     * Rien ne répond. **La phrase ne s'arrête pas au constat** : la règle de
     * rédaction de la page Notion vaut ici aussi — aucune limite sans une
     * sortie, et la sortie est la ligne juste en dessous.
     */
    fun searchEmpty(query: String): String =
        "Aucune question ne parle de « $query ». **Écris-nous** : on te répond, et la réponse rejoindra cette page."

    /**
     * Le chapeau de la seconde section. « Sujets courants », qui coiffait la
     * première, est parti (Clara, 17/09/2026) : les titres des paquets
     * suffisent à dire ce qu'on parcourt. La maquette écrit ces chapeaux en
     * minuscules et les dessine en capitales : c'est une casse d'affichage,
     * pas une casse de copie — TalkBack lit, il n'épelle pas.
     */
    const val contactSection = "Nous contacter"

    /**
     * La ligne qui ouvre directement le formulaire, sous les deux questions de
     * la section. Sans elle, « nous écrire » — que l'intro promet deux
     * paragraphes plus haut — ne serait atteignable qu'après avoir lu une
     * réponse, ce qui est exactement l'inverse de ce qu'on cherche quand on
     * n'a rien trouvé.
     */
    const val writeToUs = "Écris à notre équipe"

    /**
     * Le pied de page. Le numéro de version vient de l'app : l'écrire ici le
     * figerait à la première version qui l'a affiché.
     */
    fun legal(version: String): String = "MemoBook v$version | Tous droits réservés"

    // La feuille d'une réponse

    object Answer {
        /**
         * La question posée au lecteur sous la réponse. C'est elle que la page
         * Notion appelle la mesure : « Consultations et clics *cette réponse
         * t'a-t-elle aidé* par identifiant, pour repérer les questions mal
         * formulées et les frictions produit. »
         */
        const val helpful = "Est-ce utile ?"
        const val helpfulYes = "Cette réponse m’a aidé"
        const val helpfulNo = "Cette réponse ne m’a pas aidé"

        /**
         * Ce qu'on répond à quelqu'un qui vient de voter. Deux mots, et la
         * question disparaît : laisser les deux pouces actifs invite à voter
         * deux fois.
         */
        const val thanks = "Merci !"

        /**
         * Le vote n'est pas parti : les pouces reviennent, et cette ligne
         * dit pourquoi (T226).
         */
        const val voteOffline = "Pas de réseau : ton avis n’est pas parti. Réessaie une fois connecté."
        const val voteFailed = "Ton avis n’a pas pu partir. Réessaie dans un instant."

        const val stillStuck = "J’ai encore une question"
        const val understood = "Compris"
    }

    // La feuille « Nous contacter »

    object Contact {
        const val title = "Écris à notre équipe"

        const val message =
            "Nous reviendrons vers toi dans les plus brefs délais par mail ou par WhatsApp si tu as renseigné ton numéro."

        /**
         * Le chapeau du formulaire quand on y arrive par une des deux
         * questions de « Nous contacter » — plus court que la réponse qu'elles
         * ouvraient : **les trois lignes de la section ouvrent le formulaire**
         * (Hugo, 17/09/2026), et l'explication tient en une phrase.
         *
         * Les deux chapeaux sont ceux de la page Notion (29/09/2026), au
         * caractère près, variables résolues à l'affichage — « Notre
         * application est {{statut_developpement}} ».
         */
        fun brief(
            entryId: String,
            variables: FaqVariables = FaqVariables.current,
        ): String? = when (entryId) {
            "faq.aide.probleme" ->
                "Décris nous ton problème. Nous reviendrons vers toi dans les plus brefs délais par mail ou par Whatsapp si tu as renseigné ton numéro."
            "faq.aide.suggestion" ->
                variables.resolve(
                    "Notre application est {{statut_developpement}}. N’hésite pas à nous envoyer tes retours. On travaille en continu pour rendre ton expérience plus fluide. Les demandes récurrentes orientent directement les prochaines évolutions."
                )
            else -> null
        }

        /**
         * Sous le champ, sur les deux entrées comme sur le formulaire seul :
         * c'est le même envoi.
         */
        const val diagnosticMention =
            "Un diagnostic technique est joint automatiquement à ton message, sans le contenu de tes souvenirs."

        const val placeholder = "Ton message…"
        const val send = "Envoyer"

        const val confirmation = "Nous avons bien reçu ton message"

        /**
         * Ce que TalkBack annonce à la place du rond lime : une coche
         * décorative ne dit rien que le titre ne dise déjà, mais son
         * apparition, elle, mérite d'être signalée.
         */
        const val confirmationVoice = "Message envoyé"

        /**
         * Le message n'est pas parti. L'écrire là où le formulaire était, et
         * garder le texte saisi : le perdre serait pire que l'échec.
         */
        const val sendFailed =
            "Ton message n’a pas pu partir. Réessaie dans un instant."

        /** Pas de réseau : le message reste dans le champ (T226). */
        const val sendOffline =
            "Pas de réseau : ton message n’est pas parti. Il reste ici, réessaie une fois connecté."

        /**
         * Plus de vingt messages en vingt-quatre heures
         * (`429 support_rate_limited`).
         */
        const val sendRateLimited =
            "Tu nous as déjà beaucoup écrit aujourd’hui. On lit tout : réessaie demain si tu as encore quelque chose à nous dire."
    }
}
