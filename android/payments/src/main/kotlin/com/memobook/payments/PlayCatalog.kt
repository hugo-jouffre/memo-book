package com.memobook.payments

/**
 * Les produits Google Play de l'abonnement — le jumeau de `StoreKitCatalog`
 * (`MemoBookPayments/SubscriptionStore.swift`).
 *
 * **Le même identifiant que sur l'App Store** : le serveur reconnaît le produit
 * quel que soit le store qui l'a vendu (`backend/src/services/subscriptionCatalog.ts`),
 * et l'illimité pend du compte, pas du store. Un abonné de l'iPhone est donc
 * abonné sur Android, et inversement.
 *
 * L'ancien abonnement à la semaine n'a jamais été vendu sur Google Play : il
 * n'a rien à faire ici.
 */
object PlayCatalog {
    /** Le seul produit que l'app vend : 4,99 € par mois, récit illimité. */
    const val MONTHLY_SUBSCRIPTION = "com.memobook.app.subscription.monthly"

    /** Les produits dont l'app remet les achats au serveur. */
    val acceptedSubscriptions: Set<String> = setOf(MONTHLY_SUBSCRIPTION)
}
