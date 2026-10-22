package com.memobook.payments

// Le jumeau de `MemoBookPayments/PaymentOutcome.swift`.

/** Ce qu'une feuille de paiement rend. */
sealed interface PaymentOutcome {
    /**
     * Le paiement est parti chez Stripe.
     *
     * ⚠️ **Ce n'est pas « la commande est validée ».** C'est le webhook côté
     * serveur qui fait foi : l'app peut être tuée à la seconde suivante, et la
     * commande n'en sera pas moins payée. L'écran doit donc relire l'état
     * auprès du serveur, jamais conclure depuis ce cas.
     */
    data object Succeeded : PaymentOutcome

    /**
     * La personne a fermé la feuille. Sans conséquence, et sans message
     * d'erreur : ce n'est pas un échec, c'est un choix.
     */
    data object Cancelled : PaymentOutcome

    data class Failed(val message: String) : PaymentOutcome
}

sealed class PaymentError : Exception() {
    /**
     * Aucune fenêtre pour présenter la feuille. En pratique : l'app est passée
     * en arrière-plan entre la demande et la présentation — ou, sur Android,
     * `PaymentSheetsHost` n'est pas posé dans la composition, ou l'activité se
     * recrée à cet instant (une rotation).
     */
    data object NoPresenter : PaymentError()

    /**
     * La feuille a rendu [PaymentOutcome.Failed].
     *
     * Un cas relayé et non reformulé : le message vient de Stripe, qui est le
     * seul à savoir si la carte a été refusée, si le plafond est atteint ou si
     * l'authentification a échoué. Le réécrire ici perdrait ce que la personne
     * a besoin de lire pour s'en sortir.
     */
    data class Refused(val reason: String) : PaymentError()

    /** La phrase à montrer — le `errorDescription` d'iOS. */
    val errorDescription: String
        get() = when (this) {
            NoPresenter -> "Impossible d’ouvrir le paiement pour le moment. Réessaie."
            is Refused -> reason
        }

    override val message: String get() = errorDescription
}
