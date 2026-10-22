package com.memobook.feature

import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.ViewModelStoreOwner

// Ce que `RootView` descend à tous les écrans — les `@Entry` de
// `EnvironmentValues` qu'iOS déclare çà et là (`RootView.swift`,
// `FoundersNoteSheet.swift`…). Un écran les lit ; seul `RootView` les pose.

/**
 * Le prénom du compte, pour les deux écrans qui s'adressent à la personne : le
 * mot des fondateurs et le support. `null` hors session et dans un aperçu.
 */
val LocalTravellerFirstName = staticCompositionLocalOf<String?> { null }

/**
 * Les voyages créés hors ligne que le serveur n'a pas encore reçus : leurs
 * réglages, leur aperçu et leur commande pâlissent partout où on les ouvre (T239).
 */
val LocalTripsAwaitingServer = compositionLocalOf<Set<String>> { emptySet() }

/**
 * Monte quand l'accueil doit se relire — une feuille du store refermée, une
 * transaction remise hors du paywall. L'accueil a son modèle à lui, que
 * `RootView` ne tient pas : il écoute ce compteur.
 */
val LocalHomeReloadRequest = compositionLocalOf { 0 }

/**
 * Le tracé du M couvre encore l'écran. L'accueil retarde sa cascade
 * d'apparition jusqu'à ce que le voile se lève.
 */
val LocalLaunchOverlayIsVisible = compositionLocalOf { false }

/**
 * Le magasin des modèles **de la session** — ceux que plusieurs destinations
 * partagent, et que `RootView` tient sur iOS : le support (un seul pour la
 * session, ses votes déjà donnés ne se redemandent pas), les deux plats du
 * carnet partagés par les quatre écrans des couvertures.
 *
 * ```kotlin
 * val support = viewModel(LocalSessionViewModelStoreOwner.current, key = "support") { dependencies.supportModel() }
 * ```
 *
 * Vidé à chaque changement de compte. `null` dans un aperçu : l'écran prend
 * alors le magasin de sa destination.
 */
val LocalSessionViewModelStoreOwner = staticCompositionLocalOf<ViewModelStoreOwner?> { null }
