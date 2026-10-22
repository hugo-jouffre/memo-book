package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview

/**
 * La vignette d'un sujet : un pictogramme de marque dans un disque du bleu
 * `outline`, le seul aplat qui dise « information » sans tirer vers l'action.
 * Jumeau de `BrandIconBadge.swift`.
 *
 * Elle ouvre les écrans et les feuilles qui parlent d'**une** chose — le
 * cadenas de « Mot de passe oublié ». Le glyphe se dessine à `contentIcon`, le
 * disque lui laisse un anneau de 12.
 *
 * @param icon une icône du catalogue (`R.drawable.icon_locker`), là où iOS
 *   reçoit son nom.
 */
@Composable
fun BrandIconBadge(@DrawableRes icon: Int, modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(icon),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.ink),
        modifier = modifier
            .background(MemoBookColor.outline, CircleShape)
            .padding(MemoBookSpacing.snug)
            .size(MemoBookSpacing.contentIcon)
            .clearAndSetSemantics {},
    )
}

@Preview(locale = "fr-rFR")
@Composable
private fun BrandIconBadgePreview() {
    BrandIconBadge(R.drawable.icon_locker)
}
