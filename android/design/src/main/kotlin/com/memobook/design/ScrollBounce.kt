package com.memobook.design

import androidx.compose.foundation.LocalOverscrollFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/**
 * Retire l'effet de bout de course des listes qu'il enveloppe : le contenu
 * **s'arrête** à ses deux bouts. Jumeau de `brandScrollWithoutBounce()`.
 *
 * Sur iOS, c'est l'élastique ; sur Android, l'étirement. Sur l'écran d'entrée,
 * tirer la carte découvrait ce qu'il y a sous elle (Clara, 17/09/2026). Une
 * seule vue s'en sert, et c'est voulu.
 */
@Composable
fun BrandScrollWithoutBounce(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalOverscrollFactory provides null, content = content)
}
