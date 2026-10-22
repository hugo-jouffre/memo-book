package com.memobook.feature.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.feature.LaunchCopy
import com.memobook.design.R as DesignR

/**
 * L'écran de lancement : le M de MemoBook sur le crème, **le signe seul**
 * (Hugo, 18/09/2026). Le jumeau de `Onboarding/LaunchView.swift`.
 *
 * Le M s'écrira d'un trait, sur la courbe du fichier de marque, quand
 * `BrandMarkBackdrop` sera porté (phase A2) ; il est posé, ici, à l'opacité où
 * le tracé s'arrête.
 */
@Composable
fun LaunchView(developerDetails: String? = null) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .semantics { contentDescription = LaunchCopy.ACCESSIBILITY_LABEL },
    ) {
        Image(
            painter = painterResource(DesignR.drawable.brand_mark),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.action.copy(alpha = 0.5f)),
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = MemoBookSpacing.xl),
        )
        if (developerDetails != null) {
            BasicText(
                text = developerDetails,
                style = MemoBookFont.caption.copy(color = MemoBookColor.inkMuted, textAlign = TextAlign.Center),
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(MemoBookSpacing.screenMargin),
            )
        }
    }
}

@Preview(widthDp = 360, heightDp = 640)
@Composable
private fun LaunchViewPreview() {
    LaunchView(developerDetails = "API · http://10.0.2.2:3000 ↪︎ production")
}
