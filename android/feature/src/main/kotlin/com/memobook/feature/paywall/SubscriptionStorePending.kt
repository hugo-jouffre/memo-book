package com.memobook.feature.paywall

// À brancher : MemoBookPayments/SubscriptionStore.swift
//
// Le lot de l'argent porte le magasin de l'abonnement (Google Play Billing)
// dans `:payments`, et avec lui ces deux issues. Elles sont déclarées ici sous
// leur nom Swift, pour que `SubscriptionPurchase` et le paywall compilent ;
// l'intégrateur supprime ce fichier et importe celles de `com.memobook.payments`.

/** Ce qu'un achat rend. */
sealed interface PurchaseOutcome {
    /** Payé, et le serveur l'a appris : l'abonnement est ouvert. */
    data object Subscribed : PurchaseOutcome

    /**
     * Payé au store, mais le serveur n'a pas répondu. **Ce n'est pas un
     * échec** : l'achat repartira seul, et le store notifiera le serveur de son
     * côté. L'écran se comporte comme pour [Subscribed].
     */
    data object AwaitingServer : PurchaseOutcome

    /** Il faut une validation de plus — un parent, ou la banque. */
    data object Pending : PurchaseOutcome

    /** La personne a fermé la feuille du store. Un choix, pas une erreur. */
    data object Cancelled : PurchaseOutcome

    data class Failed(val message: String) : PurchaseOutcome
}

/** Ce que « Restaurer mes achats » rend. */
enum class RestoreOutcome {
    Restored,
    NothingToRestore,

    /** La personne a refermé la demande du store. */
    Cancelled,
}
