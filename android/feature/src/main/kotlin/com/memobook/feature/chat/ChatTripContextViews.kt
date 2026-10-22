package com.memobook.feature.chat

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.core.ChatCopy
import com.memobook.core.ChatTripContext
import com.memobook.design.BrandRow
import com.memobook.design.BrandRowGroup
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.home.CardPressStyle

/**
 * La pastille « Contexte du voyage 2/5 », posée sous l'en-tête du fil tant que
 * MEMO recueille le contexte. Jumeau de `ChatTripContextBanner`
 * (`ChatTripContextViews.swift`).
 *
 * Elle dit **où on en est** sans rien demander : la question, c'est MEMO qui la
 * pose, une à la fois. Un appui ouvre la fiche — ce que MEMO a compris, ligne à
 * ligne, et ce qui manque encore.
 *
 * Capsule bleue : c'était aussi, jusqu'au 15/10/2026, le dessin de la bannière
 * de l'aperçu ([ChatPreviewBanner]), pour que les deux se lisent comme la même
 * famille d'objets — un état du carnet, pas un message. L'autre est passée au
 * crème, parce qu'elle **flotte sur le fil** et s'y fondait ; celle-ci est
 * posée dans la marge de l'en-tête, et le bleu n'y concurrence aucune bulle.
 * Les deux ne paraissent jamais ensemble.
 */
@Composable
fun ChatTripContextBanner(context: ChatTripContext, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val ringSide = scaled(18.dp)
    val reduceMotion = isReduceMotionEnabled()
    val accessible = isAccessibilityTextSize()
    // Une capsule, qui devient un rectangle arrondi quand elle s'empile : une
    // capsule de trois lignes de haut se lirait comme une pilule.
    val shape = if (accessible) RoundedCornerShape(MemoBookSpacing.largeCornerRadius) else RoundedCornerShape(percent = 50)
    val progress by animateFloatAsState(
        context.progress.toFloat(),
        if (reduceMotion) snap() else SwiftMotion.smooth(0.45f),
        label = "context",
    )
    val label = ChatCopy.TripContext.accessibilityLabel(filled = context.filledCount, of = context.requiredCount)

    val ring: @Composable () -> Unit = { ContextRing(progress, ringSide) }
    val title: @Composable () -> Unit = { BrandText(ChatCopy.TripContext.title, MemoBookFont.label) }
    val count: @Composable () -> Unit = {
        BrandText("${context.filledCount}/${context.requiredCount}", MemoBookFont.tagline.copy(fontFeatureSettings = "tnum"))
    }
    val chevron: @Composable () -> Unit = {
        Image(
            painter = painterResource(R.drawable.icon_chevron),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(scaled(14.dp)),
        )
    }

    val container = modifier
        .background(MemoBookColor.bubbleTraveller.copy(alpha = 0.9f), shape)
        .border(1.dp, MemoBookColor.outline, shape)
        .clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = CardPressStyle,
            role = Role.Button,
            onClick = onOpen,
        )
        .clearAndSetSemantics {
            contentDescription = label
            role = Role.Button
            onClick(label = ChatCopy.TripContext.accessibilityHint) { onOpen(); true }
        }
        .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs + 2.dp)

    // Une ligne d'ordinaire ; aux tailles accessibles, la jauge et le compte
    // au-dessus, le titre en entier dessous — sur une seule ligne, « Contexte »
    // se coupait au milieu du mot.
    if (accessible) {
        Column(container, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                ring()
                count()
                Spacer(Modifier.weight(1f))
                chevron()
            }
            title()
        }
    } else {
        Row(container, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            ring()
            title()
            count()
            chevron()
        }
    }
}

/** La jauge ronde : le filet bleu, et le vert qui avance à chaque ligne remplie. */
@Composable
private fun ContextRing(progress: Float, side: androidx.compose.ui.unit.Dp) {
    Canvas(Modifier.size(side)) {
        val stroke = 2.5.dp.toPx()
        val inset = stroke / 2
        val arcSize = Size(size.width - stroke, size.height - stroke)
        drawArc(MemoBookColor.outline, 0f, 360f, useCenter = false, topLeft = Offset(inset, inset), size = arcSize, style = Stroke(stroke))
        drawArc(
            MemoBookColor.action,
            startAngle = -90f,
            sweepAngle = 360f * progress,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = arcSize,
            style = Stroke(stroke, cap = StrokeCap.Round),
        )
    }
}

/**
 * La fiche du contexte : ce que MEMO a compris, ligne à ligne. Jumeau de
 * `ChatTripContextSheet`.
 *
 * Une lecture, pas un formulaire : on ne corrige pas ici, on le **dit** à MEMO,
 * qui fond la correction avec le reste. Deux endroits pour écrire la même chose
 * finiraient par ne plus dire la même chose.
 *
 * Pas de pastille de compte dans l'en-tête : `badge` est lime, et le lime ne
 * dit que l'abonnement. Les lignes « À raconter » le disent.
 */
@Composable
fun ChatTripContextSheet(context: ChatTripContext) {
    BrandSheet(
        ChatCopy.TripContext.title,
        subtitle = if (context.isGathering) ChatCopy.TripContext.gatheringSubtitle else ChatCopy.TripContext.doneSubtitle,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            BrandRowGroup(rows(context.items.filter { it.isRequired }))

            val extras = context.items.filter { !it.isRequired }
            if (extras.isNotEmpty()) {
                BrandText(
                    ChatCopy.TripContext.extrasTitle.uppercase(),
                    MemoBookFont.overline,
                    Modifier.semantics { heading() },
                    color = MemoBookColor.inkMuted,
                )
                BrandRowGroup(rows(extras))
            }
        }
    }
}

private fun rows(items: List<ChatTripContext.Item>): List<BrandRow> = items.map { item ->
    BrandRow(
        item.label,
        value = item.value ?: ChatCopy.TripContext.missingValue,
        valuePlacement = BrandRow.ValuePlacement.Below,
        valueTone = if (item.isFilled) BrandRow.ValueTone.Plain else BrandRow.ValueTone.Invitation,
        isConfirmed = item.isFilled,
    )
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Contexte — pastille", widthDp = 390)
@Composable
private fun ChatTripContextBannerPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        ChatTripContextBanner(ChatTripContext.fixture, onOpen = {})
        ChatTripContextBanner(
            ChatTripContext(status = ChatTripContext.Status.Gathering, filledCount = 0, requiredCount = 5, items = emptyList()),
            onOpen = {},
        )
    }
}

@Preview(locale = "fr-rFR", name = "Contexte — fiche", widthDp = 390, heightDp = 800)
@Composable
private fun ChatTripContextSheetPreview() {
    Column(Modifier.background(MemoBookColor.background)) {
        ChatTripContextSheet(ChatTripContext.fixture)
    }
}
