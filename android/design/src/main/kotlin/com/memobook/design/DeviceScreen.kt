package com.memobook.design

import android.os.Build
import android.view.RoundedCorner
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Ce que l'app doit savoir de la dalle sur laquelle elle est posée. Jumeau de
 * `DeviceScreen.swift`, avec une différence qui l'arrange : là où iOS
 * **déduit** le rayon des coins du format de l'écran, faute d'API publique,
 * Android le donne (`RoundedCorner`, Android 12+).
 *
 * C'est ce rayon qui permet à une feuille modale d'être **concentrique** au
 * téléphone : ses coins suivent la courbe du verre au lieu de la couper.
 */
object DeviceScreen {
    /**
     * Rayon des coins de l'écran. Avant Android 12, ou sur une dalle aux angles
     * droits, 0 — comme le SE sur iOS.
     */
    @Composable
    fun cornerRadius(): Dp {
        val insets = LocalView.current.rootWindowInsets ?: return 0.dp
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0.dp
        val radius = insets.getRoundedCorner(RoundedCorner.POSITION_BOTTOM_LEFT)?.radius ?: return 0.dp
        return with(LocalDensity.current) { radius.toDp() }
    }

    /** Hauteur de la fenêtre. Sert à borner une feuille pour qu'elle ne monte jamais jusqu'en haut. */
    @Composable
    fun height(): Dp = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.height.toDp() }

    /** Largeur de la fenêtre. */
    @Composable
    fun width(): Dp = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() }

    /** Ce que la barre de navigation du système prend en bas — le pendant de l'indicateur d'accueil. */
    @Composable
    fun bottomSafeInset(): Dp = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }

    /**
     * Ce que la barre d'état et la découpe de la caméra prennent en haut. Tout
     * ce qui doit se poser « juste sous le haut » s'y réfère.
     */
    @Composable
    fun topSafeInset(): Dp = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
}
