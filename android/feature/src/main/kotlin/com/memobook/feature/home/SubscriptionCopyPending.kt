package com.memobook.feature.home

// À brancher : Profile/SubscriptionSheet.swift (`SubscriptionCopy`).
//
// Les phrases de l'abonnement que l'accueil emploie — ses deux alertes. Elles
// appartiennent à `SubscriptionCopy`, que le lot du profil porte avec la
// feuille d'abonnement ; ce fichier n'en recopie que ce que l'accueil lit, au
// caractère près, et disparaît à la fusion.

/** Les mots des deux alertes de l'accueil — voir `SubscriptionCopy` (`SubscriptionSheet.swift`). */
internal object SubscriptionCopy {
    // — L'alerte du système, quand le sursis s'achève

    /**
     * Le titre de l'alerte qui s'ouvre le jour où le mois payé s'achève.
     *
     * **Une alerte et non une feuille de la marque**, et c'est voulu : elle
     * n'arrive pas au bout d'un geste qu'on vient de faire, elle tombe à
     * l'ouverture de l'app, des jours plus tard. Une feuille qui monte toute
     * seule se lit comme un écran de l'app ; une alerte se lit comme une
     * nouvelle.
     */
    const val endedTitle = "Ton abonnement MemoBook s’est arrêté"

    /**
     * On ne perd rien : on retrouve le crédit du jour, et l'illimité est à un
     * geste (Hugo, 03/10/2026).
     *
     * **La période sans la nommer** (03/10/2026) : l'accueil, qui ouvre
     * l'alerte, ne sait pas si l'abonné payait le mois ou la semaine de
     * l'ancienne formule — « Ton mois réglé est terminé » mentait à ce dernier.
     */
    fun endedMessage(tripTitle: String?): String {
        val opening = if (!tripTitle.isNullOrEmpty()) {
            "La période que tu avais réglée est terminée, et l’abonnement de « $tripTitle » ne s’est pas renouvelé."
        } else {
            "La période que tu avais réglée est terminée, et l’abonnement ne s’est pas renouvelé."
        }
        return "$opening Tu retrouves 5 minutes par jour et par voyage. Pour raconter sans compter, réabonne-toi."
    }

    const val endedDismiss = "D’accord"

    // — Le rappel de fin de voyage, sur l'accueil
    const val tripEndTitle = "Ton voyage est terminé"
    const val tripEndMessage =
        "Ton abonnement MemoBook va se renouveler, alors que tu n’en as pas besoin entre deux voyages. Tu peux le résilier maintenant, tes carnets restent à toi."
    const val tripEndCancel = "Résilier mon abonnement"
    const val tripEndKeep = "Le garder"
    const val endedResubscribe = "Me réabonner"
}
