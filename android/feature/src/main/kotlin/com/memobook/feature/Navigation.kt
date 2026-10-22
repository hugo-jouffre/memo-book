package com.memobook.feature

import com.memobook.core.LegalDocument
import com.memobook.feature.recording.RecordingHandoff

// Les destinations et les intentions de l'app, en un seul fichier.
//
// Sur iOS, chaque intention est déclarée à côté de l'écran qui l'émet
// (`HomeIntent` dans `HomeModel.swift`…) et chaque route dans `RootView.swift`.
// Ici elles sont réunies : ce sont **le contrat** entre les écrans et
// `RootView`, et un écran porté ne doit pas pouvoir le changer en passant. Les
// noms et les cas sont ceux d'iOS, cas pour cas.

/**
 * Ce que l'écran d'entrée peut pousser. Jumeau de `SignedOutRoute`.
 */
sealed interface SignedOutRoute {
    /** Inscription et connexion par e-mail, sous leur sélecteur. */
    data object Email : SignedOutRoute

    /** Les conditions d'utilisation, par le lien de la mention légale (T151). */
    data object TermsOfUse : SignedOutRoute
}

/**
 * Les destinations que l'accueil peut pousser. Jumeau de `HomeRoute`.
 *
 * L'accueil lui-même n'en est pas une, comme sur iOS : c'est la racine de la
 * pile, sous toutes les autres.
 */
sealed interface HomeRoute {
    data object Profile : HomeRoute

    /** Le profil, « Mon abonnement » ouvert dessus — « Résilier » de la ligne « Crédit du jour » (18/10/2026). */
    data object ManageSubscription : HomeRoute

    data class Trip(val id: String) : HomeRoute

    /** La conversation avec MEMO. `stepId` la pose sur une étape précise ; `null` sur le voyage entier. */
    data class Chat(val tripId: String, val stepId: String? = null) : HomeRoute

    /** Les carnets de la communauté, ouverts par la carte de découverte. */
    data object Gallery : HomeRoute

    /** Les six étapes de « Créer un voyage ». */
    data object TripCreation : HomeRoute

    /** Les réglages d'un voyage. `opening` : la feuille à ouvrir en arrivant. */
    data class TripSettings(val id: String, val opening: TripSettingsSheet? = null) : HomeRoute

    /**
     * L'aperçu du carnet. L'identifiant est celui du **carnet** (`memos`).
     * `sharing` ouvre l'aperçu **sur sa feuille de partage**.
     */
    data class BookPreview(val memoId: String, val sharing: Boolean = false) : HomeRoute

    /** Les sept étapes de « Commander mon Carnet ». On n'y arrive **que par l'aperçu**. */
    data class Order(val memoId: String) : HomeRoute

    /** Les personnalisations du carnet, ouvertes par « Style du carnet ». */
    data class BookCustomisation(val tripId: String) : HomeRoute

    /** Les deux plats du carnet. */
    data class Covers(val tripId: String) : HomeRoute

    /** Les trois écrans qui changent un plat — trois destinations, pour que le retour ramène au choix. */
    data class CoverStyle(val tripId: String) : HomeRoute
    data class CoverPhoto(val tripId: String) : HomeRoute
    data class CoverTexts(val tripId: String) : HomeRoute

    /** Le support, ouvert par tous les « Besoin d'aide ? » de l'app. */
    data object Support : HomeRoute

    /** Un document légal, depuis le groupe légal du profil. */
    data class Legal(val document: LegalRoute) : HomeRoute
}

/** Les documents légaux que l'app sait ouvrir — un nom, pas onze chapitres de texte. */
enum class LegalRoute {
    TermsOfUse,
    PrivacyPolicy,
    ;

    val content: LegalDocument
        get() = when (this) {
            TermsOfUse -> com.memobook.core.TermsOfUse.document
            PrivacyPolicy -> com.memobook.core.PrivacyPolicy.document
        }
}

/** Les feuilles que les réglages d'un voyage savent ouvrir d'eux-mêmes. Jumeau de `TripSettingsSheet`. */
enum class TripSettingsSheet {
    Dates,
    Pace,
    Notifications,
    Theme,
    Companions,
    DailyCredit,
}

// MARK: - Les intentions

/** Ce que l'accueil demande. Jumeau de `HomeIntent` (`HomeModel.swift`). */
sealed interface HomeIntent {
    data object OpenProfile : HomeIntent
    data class OpenTrip(val id: String) : HomeIntent
    data class OrderPrint(val tripId: String) : HomeIntent
    data class ShareTrip(val id: String) : HomeIntent
    data object OpenGallery : HomeIntent
    data object CreateTrip : HomeIntent
    data object ImportFromPolarsteps : HomeIntent
    data object OpenHelp : HomeIntent

    /** On arrive dans la conversation du voyage, le vocal déjà posé dans le fil. */
    data class OpenConversation(val tripId: String, val handoff: RecordingHandoff) : HomeIntent
}

/** Ce que l'accueil d'un voyage demande. Jumeau de `TripIntent` (`TripHomeModel.swift`). */
sealed interface TripIntent {
    data class TellMore(val tripId: String) : TripIntent
    data class OpenStep(val tripId: String, val stepId: String) : TripIntent
    data class InviteCompanions(val tripId: String) : TripIntent
    data object OpenHelp : TripIntent
    data class OpenSettings(val tripId: String) : TripIntent
    data class OpenBookPreview(val tripId: String) : TripIntent
}

/** Ce que le profil demande. Jumeau de `ProfileIntent`. */
sealed interface ProfileIntent {
    data class OpenTrip(val id: String) : ProfileIntent
    data object OpenGallery : ProfileIntent
    data object OpenHelp : ProfileIntent
    data object OpenTermsOfUse : ProfileIntent
    data object OpenPrivacyPolicy : ProfileIntent
    data class OrderBook(val memoId: String) : ProfileIntent
}

/** L'unique intention d'un document légal. Jumeau de `LegalIntent`. */
sealed interface LegalIntent {
    data object OpenHelp : LegalIntent
}

/** Ce que la conversation demande. Jumeau de `ChatIntent`. */
sealed interface ChatIntent {
    data class OpenSettings(val tripId: String) : ChatIntent
    data class OpenBookPreview(val memoId: String) : ChatIntent
}

/** Ce que les réglages d'un voyage demandent. Jumeau de `TripSettingsIntent`. */
sealed interface TripSettingsIntent {
    data object OpenCustomisation : TripSettingsIntent
    data object ConnectTricount : TripSettingsIntent
    data object ManageSubscription : TripSettingsIntent
    data object OpenBookPreview : TripSettingsIntent
    data object OrderBook : TripSettingsIntent
    data object OpenHelp : TripSettingsIntent
    data object TripDeleted : TripSettingsIntent
}

/** Ce que les personnalisations du carnet demandent. Jumeau de `BookCustomisationIntent`. */
sealed interface BookCustomisationIntent {
    data object OpenCovers : BookCustomisationIntent
    data object OpenBookPreview : BookCustomisationIntent
    data object OpenHelp : BookCustomisationIntent
}

/** Ce que le parcours des couvertures demande. Jumeau de `CoversIntent`. */
sealed interface CoversIntent {
    data object OpenStyle : CoversIntent
    data object OpenPhoto : CoversIntent
    data object OpenTexts : CoversIntent
    data object OpenCustomisation : CoversIntent
}

/** Ce que l'aperçu du carnet demande. Jumeau de `BookPreviewIntent`. */
sealed interface BookPreviewIntent {
    data object Customise : BookPreviewIntent
    data object Order : BookPreviewIntent
    data object ConfigureCovers : BookPreviewIntent
    data object ShareFeedback : BookPreviewIntent
}

/** Ce que le tunnel de commande demande. Jumeau de `OrderIntent`. */
sealed interface OrderIntent {
    data object OpenHelp : OrderIntent
    data object Finish : OrderIntent
}
