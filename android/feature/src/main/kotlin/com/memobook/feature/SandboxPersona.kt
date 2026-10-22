package com.memobook.feature

import com.memobook.core.HomeFeed
import com.memobook.core.Traveller
import com.memobook.core.TravellerProfile

// Le jumeau de `SandboxPersona.swift`. Ce fichier expose, au module `:feature`
// seulement, [SandboxPersona] : le personnage joué (`SandboxPersona.current`)
// et ce qu'il retouche de l'accueil, du voyageur et du profil.

/**
 * Le personnage que le bac à sable de l'accueil fait jouer à l'app.
 *
 * **Il ne sert pas dans l'app livrée.** Sur iOS, le fichier entier est sous
 * `#if DEBUG`, comme le panneau qui l'actionne. `:feature` n'a pas de
 * `BuildConfig` pour en faire autant : il est compilé dans les deux builds, et
 * seul le panneau de Debug le pose — sans lui, [current] reste `null` et rien
 * n'est retouché.
 *
 * Il existe parce que l'abonnement se lit sur **plusieurs écrans** : l'accueil,
 * le profil (pastille « Abonné(e) », bouton « Découvrir l'abonnement », ligne
 * « Mon abonnement »), et le crédit du jour que servent la conversation et les
 * réglages du voyage. Chacun a son modèle et sa source, et le profil n'est
 * construit qu'au moment où on l'ouvre — une seconde après avoir appuyé sur le
 * bouton de l'accueil. Il faut donc un endroit qui survive à tous, et c'est
 * celui-ci.
 *
 * Ce n'est pas une seconde source de vérité : le personnage **retouche** ce que
 * la source a rendu, jeu d'essai ou serveur, au lieu de le remplacer. Le reste —
 * nom, adresse, commandes, les deux alertes de l'accueil — continue de venir
 * d'où il venait. Et il prévient le double d'API ([SandboxCredit]), pour que le
 * crédit du jour qu'il sert dise « illimité » à un abonné.
 */
internal enum class SandboxPersona {
    /**
     * Quelqu'un qui paie : il raconte sans limite, le profil porte la pastille
     * « Abonné(e) » et la ligne « Mon abonnement ».
     */
    Subscriber,

    /**
     * Quelqu'un qui n'a pas d'abonnement : il raconte dans le crédit du jour, et
     * le profil lui propose « Découvrir l'abonnement ». Son passé d'abonné, lui,
     * reste celui des données : le jeu d'essai en a un, et le paywall s'ouvre
     * donc sur la version « retour ».
     */
    Free,

    /**
     * Quelqu'un qui n'a **jamais** été abonné (03/10/2026) : sans abonnement, et
     * sans passé d'abonné — le paywall s'ouvre sur la découverte en trois
     * écrans, inatteignable sinon dans le bac à sable (le profil du jeu d'essai
     * démarre abonné).
     */
    NeverSubscribed,
    ;

    private val isUnlimited: Boolean
        get() = when (this) {
            Subscriber -> true
            Free, NeverSubscribed -> false
        }

    /**
     * Retouche le contenu de l'accueil : le voyageur, et le crédit des voyages
     * en cours — illimité pour un abonné, compté sinon.
     */
    fun applied(feed: HomeFeed): HomeFeed {
        val trips = feed.trips.map { trip ->
            val credit = trip.dailyCredit ?: return@map trip
            trip.copy(dailyCredit = credit.copy(isUnlimited = isUnlimited))
        }
        return HomeFeed(
            traveller = applied(feed.traveller),
            trips = trips,
            showcase = feed.showcase,
        )
    }

    /**
     * Le voyageur, abonné ou non — **tout le reste gardé**. La version d'avant
     * reconstruisait le voyageur sans ses deux alertes (`subscriptionEndedOn`,
     * `subscriptionOutlivesTrip`), qui ne se rejouaient donc plus avec un
     * personnage actif.
     */
    fun applied(traveller: Traveller): Traveller {
        val hasSubscribedBefore = when (this) {
            Subscriber -> true
            Free -> traveller.hasSubscribedBefore
            NeverSubscribed -> false
        }
        return traveller.replacing(isUnlimited = isUnlimited, hasSubscribedBefore = hasSubscribedBefore)
    }

    /**
     * Le profil : un abonné actif, ou un compte sans abonnement ni mois payé
     * devant lui — sans quoi le sursis le ferait encore passer pour abonné.
     */
    fun applied(profile: TravellerProfile): TravellerProfile {
        val subscription = profile.subscription
        return profile.copy(
            subscription = when (this) {
                Subscriber -> subscription.updating(isActive = true, cancelledAt = null)
                Free -> subscription.updating(isActive = false, paidThrough = null)
                // Ni abonnement, ni mois payé, ni résiliation, ni passé : un
                // compte qui n'a rien souscrit.
                NeverSubscribed -> subscription.updating(
                    isActive = false,
                    paidThrough = null,
                    cancelledAt = null,
                    hasEndedBefore = false,
                    managedByAppStore = false,
                )
            },
        )
    }

    companion object {
        /**
         * Celui qu'on joue en ce moment. `null` — le cas normal — laisse les
         * données telles qu'elles arrivent. Le poser prévient [SandboxCredit].
         *
         * `@MainActor` sur iOS ; ici, le panneau le pose depuis le fil principal
         * et le double le lit d'ailleurs : `@Volatile` suffit à une valeur seule.
         */
        @Volatile
        var current: SandboxPersona? = null
            set(value) {
                field = value
                SandboxCredit.setUnlimited(value?.isUnlimited)
            }
    }
}
