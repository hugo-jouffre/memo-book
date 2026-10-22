package com.memobook.feature.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandBackdrop
import com.memobook.design.BrandBubbleShape
import com.memobook.design.BrandChatBubble
import com.memobook.design.BrandSkeleton
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookSpacing

/**
 * Ce que le chat montre pendant qu'il charge. Jumeau de `ChatSkeleton.swift`.
 *
 * **Il ne dessine que ce qu'il sait déjà** : qu'il y aura un en-tête, une
 * bannière d'aperçu, une première bulle de MEMO et une barre en bas. C'est la
 * maquette « Chat - Skeleton », et c'est aussi la seule limite qu'un squelette
 * doit respecter — dessiner des cartes d'étapes ou des vignettes promettrait un
 * contenu qu'on ne connaît pas encore.
 *
 * Les mesures viennent de [ChatMetrics], partagées avec l'écran réel : c'est ce
 * qui fait que le passage de l'un à l'autre ne saute pas.
 */
@Composable
fun ChatSkeleton(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .clearAndSetSemantics { contentDescription = "Chargement de la conversation" },
    ) {
        BrandBackdrop(Modifier.fillMaxSize())
        Column(Modifier.fillMaxSize()) {
            SkeletonHeader()
            SkeletonContent()
            Spacer(Modifier.weight(1f))
            SkeletonBar()
        }
    }
}

/**
 * Les longueurs des lignes de texte simulées, en fraction de la largeur.
 *
 * Écrites à la main plutôt que tirées au sort : un squelette qui change de
 * dessin à chaque lancement n'est plus comparable à la maquette, et deux
 * captures d'écran ne se superposent plus.
 */
private val PARAGRAPHS = listOf(
    listOf(0.34f, 0.92f, 0.86f, 0.28f),
    listOf(0.96f, 0.88f),
    listOf(0.94f, 0.9f, 0.95f, 0.3f),
    listOf(0.93f, 0.97f, 0.82f, 0.86f),
)

private val LINE_HEIGHT = 12.dp

@Composable
private fun SkeletonHeader() {
    Row(
        Modifier
            .fillMaxWidth()
            .background(ChatMetrics.barMaterial)
            .statusBarsPadding()
            .padding(horizontal = MemoBookSpacing.s)
            .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HeaderIcon()
        Spacer(Modifier.weight(1f))
        BrandSkeleton(width = MemoBookSpacing.l, height = MemoBookSpacing.l, cornerRadius = MemoBookSpacing.avatarSide)
        BrandSkeleton(width = 84.dp, height = MemoBookSpacing.sectionGap, cornerRadius = MemoBookSpacing.s)
        Spacer(Modifier.weight(1f))
        HeaderIcon()
        HeaderIcon()
    }
}

/** Une des pastilles carrées de l'en-tête. */
@Composable
private fun HeaderIcon() {
    BrandSkeleton(width = MemoBookSpacing.m, height = MemoBookSpacing.m, cornerRadius = ChatMetrics.control)
}

@Composable
private fun SkeletonContent() {
    Column(
        Modifier
            .padding(horizontal = MemoBookSpacing.snug)
            .padding(top = MemoBookSpacing.m),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        SkeletonBanner()
        SkeletonBubble()
    }
}

/** La bannière d'aperçu : sa pastille d'icône, ses trois lignes, sa flèche. */
@Composable
private fun SkeletonBanner() {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.hairline, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
            .padding(MemoBookSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandSkeleton(width = MemoBookSpacing.xl, height = MemoBookSpacing.xl, cornerRadius = MemoBookSpacing.snug)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandSkeleton(width = 96.dp, height = LINE_HEIGHT)
            BrandSkeleton(height = LINE_HEIGHT)
            BrandSkeleton(height = LINE_HEIGHT)
        }
        BrandSkeleton(width = MemoBookSpacing.sectionGap, height = MemoBookSpacing.sectionGap, cornerRadius = MemoBookSpacing.s)
    }
}

/** La grande bulle de MEMO, avec ses quatre paragraphes. */
@Composable
private fun SkeletonBubble() {
    Column(
        Modifier
            .widthIn(max = BrandChatBubble.maximumContentWidth())
            .background(MemoBookColor.surface, BrandBubbleShape(BrandBubbleShape.Side.Leading))
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        PARAGRAPHS.forEach { lines ->
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                lines.forEach { fraction ->
                    BrandSkeleton(Modifier.fillMaxWidth(fraction), height = LINE_HEIGHT)
                }
            }
        }
    }
}

/** Les trois commandes de la barre d'envoi. */
@Composable
private fun SkeletonBar() {
    Row(
        Modifier
            .fillMaxWidth()
            .background(ChatMetrics.barMaterial)
            .navigationBarsPadding()
            .padding(horizontal = MemoBookSpacing.snug)
            .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandSkeleton(width = MemoBookSpacing.sectionGap, height = MemoBookSpacing.snug, cornerRadius = MemoBookSpacing.xs)
        repeat(3) {
            BrandSkeleton(Modifier.weight(1f), height = MemoBookSpacing.xl + MemoBookSpacing.xs, cornerRadius = MemoBookSpacing.m)
        }
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Chat — squelette", widthDp = 390, heightDp = 844)
@Composable
private fun ChatSkeletonPreview() {
    ChatSkeleton()
}
