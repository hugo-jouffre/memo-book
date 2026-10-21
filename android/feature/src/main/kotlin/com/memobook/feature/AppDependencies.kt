package com.memobook.feature

import com.memobook.networking.ApiConfiguration

/**
 * Le seul point d'assemblage de l'app, comme `AppDependencies.swift` : construit
 * une fois par `MemoBookApplication`, puis descendu aux écrans. Pas de
 * singleton, pas de framework d'injection.
 *
 * Il grandira avec les phases du portage — le client d'API, la file des envois,
 * le cache — dans le même ordre que sur iOS.
 */
class AppDependencies(
    val apiConfiguration: ApiConfiguration,
)
