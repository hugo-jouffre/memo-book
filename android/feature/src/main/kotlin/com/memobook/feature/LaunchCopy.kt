package com.memobook.feature

import com.memobook.networking.ApiConfiguration

/** La copie de l'écran de lancement. */
object LaunchCopy {
    const val ACCESSIBILITY_LABEL = "MemoBook, chargement en cours"

    /**
     * La ligne de développeur sous le M : l'adresse retenue, et son secours
     * quand il y en a un — la même « ↪︎ » que la trace réseau d'iOS.
     */
    fun apiAddress(configuration: ApiConfiguration): String =
        "API · ${configuration.baseUrl}" + (configuration.fallbackBaseUrl?.let { " ↪︎ $it" } ?: "")
}
