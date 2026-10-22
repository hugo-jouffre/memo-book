package com.memobook.feature

import androidx.compose.runtime.Composable
import com.memobook.feature.debug.DesignCatalogueView
import com.memobook.feature.onboarding.LaunchView

/**
 * La racine de l'app, comme `RootView.swift` : les écrans annoncent une
 * intention, et c'est ici qu'elle devient une destination. Pour l'instant, il
 * n'y a que l'écran de lancement — la session, l'entrée et l'accueil arrivent
 * avec la phase A4 (`docs/android.md`).
 *
 * @param showsDeveloperDetails Vrai dans un build Debug seulement : l'écran dit
 *   alors à quelle adresse l'app parle.
 * @param opensDesignCatalogue l'interrupteur `designCatalogue` d'un lancement
 *   Debug : l'app s'ouvre sur l'écran-catalogue du design system.
 */
@Composable
fun RootView(dependencies: AppDependencies, showsDeveloperDetails: Boolean, opensDesignCatalogue: Boolean = false) {
    if (opensDesignCatalogue) {
        DesignCatalogueView()
        return
    }
    LaunchView(
        developerDetails = if (showsDeveloperDetails) LaunchCopy.apiAddress(dependencies.apiConfiguration) else null,
    )
}
