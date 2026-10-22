package com.memobook.feature.debug

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.memobook.design.BrandButton
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing

/**
 * La place d'un écran pas encore porté : son nom, et le fichier Swift d'où il
 * viendra. Il disparaît écran par écran ; il ne doit plus en rester à la recette.
 */
@Composable
fun PortPending(
    title: String,
    swiftFile: String,
    onBack: (() -> Unit)? = null,
    actions: List<Pair<String, () -> Unit>> = emptyList(),
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .statusBarsPadding()
            .padding(horizontal = MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        if (onBack != null) BrandScreenHeader(title, onBack = onBack) else BrandText(title, MemoBookFont.h2)
        BrandText("Écran à porter depuis $swiftFile.", MemoBookFont.body, color = MemoBookColor.inkMuted)
        actions.forEach { (label, action) -> BrandButton(label, fillsWidth = true, action = action) }
    }
}
