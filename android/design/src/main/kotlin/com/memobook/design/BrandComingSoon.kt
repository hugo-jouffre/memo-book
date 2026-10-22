package com.memobook.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * La pastille « À venir », franche, posée à cheval sur le coin d'une carte qui
 * annonce **ce qui n'est pas encore là**. Jumeau de `BrandComingSoonBadge`
 * (`BrandComingSoon.swift`) ; le traitement complet de la carte est
 * [BrandComingSoon].
 *
 * À l'encre pleine sur le blanc : la pastille ne pâlit pas avec la carte. Elle
 * ne dit rien à TalkBack — c'est la carte qui annonce son état.
 */
@Composable
fun BrandComingSoonBadge(modifier: Modifier = Modifier, label: String = BrandComingSoonBadge.defaultLabel) {
    val capsule = RoundedCornerShape(percent = 50)
    BrandText(
        label,
        MemoBookFont.overline,
        modifier
            .wrapContentWidth(unbounded = true)
            .background(MemoBookColor.surface, capsule)
            .border(1.dp, MemoBookColor.separator, capsule)
            .padding(horizontal = MemoBookSpacing.xs, vertical = MemoBookSpacing.xs / 2)
            .clearAndSetSemantics {},
        color = MemoBookColor.ink,
        maxLines = 1,
    )
}

object BrandComingSoonBadge {
    /** « À venir ». */
    const val defaultLabel: String = "À venir"
}

/**
 * Pose le traitement « À venir » sur une carte : son contenu à demi effacé, et
 * la pastille [BrandComingSoonBadge] à cheval sur son coin. Jumeau de
 * `.brandComingSoon(_:label:)` ; ici une enveloppe, parce qu'elle pose une vue
 * par-dessus.
 *
 * C'est le parti pris de la carte « Bientôt disponible » de la feuille
 * « Nouveau carnet », devenu un motif (Hugo, 08/10/2026 : les connecteurs du
 * profil et le Tricount des réglages du voyage « en “À venir”, un peu fade
 * out, pour montrer que ce n'est pas encore disponible ») :
 *
 * - **La carte pâlit d'un bloc**, à 45 % : assez pour qu'on ne la confonde pas
 *   avec une carte qui marche, pas assez pour qu'on cesse de lire ce qu'elle
 *   annonce.
 * - **La pastille reste franche**, posée par-dessus le voile : c'est la seule
 *   chose de la carte qu'on doit lire à coup sûr.
 * - **Elle ne répond pas au doigt**, et TalkBack la lit comme une annonce, son
 *   état dit par [label]. Un geste qui n'ouvrirait rien se lirait comme une
 *   panne.
 *
 * Les marques d'un tiers s'effacent avec le reste, sans teinte : une marque
 * repeinte n'est plus la marque.
 *
 * ⚠️ Compose ne sait pas retirer à un enfant son rôle de bouton : une carte
 * dont la racine est un `clickable` garde son action pour TalkBack. Elle passe
 * donc `enabled = !isComingSoon` à son `clickable` — le doigt, lui, est arrêté
 * ici quoi qu'il arrive.
 *
 * @param isComingSoon faux, la carte reste telle quelle. Le jour où la
 *   fonctionnalité arrive, c'est ce booléen qui bascule.
 * @param label le libellé de la pastille, et ce que TalkBack ajoute.
 */
@Composable
fun BrandComingSoon(
    modifier: Modifier = Modifier,
    isComingSoon: Boolean = true,
    label: String = BrandComingSoonBadge.defaultLabel,
    content: @Composable () -> Unit,
) {
    Box(
        if (isComingSoon) {
            modifier.semantics(mergeDescendants = true) { stateDescription = label }
        } else {
            modifier
        },
    ) {
        Box(Modifier.alpha(if (isComingSoon) CONTENT_OPACITY else 1f)) { content() }
        if (isComingSoon) {
            // Le doigt s'arrête ici : posée par-dessus, cette couche prend le
            // toucher avant la carte, sans rien en faire.
            Box(
                Modifier
                    .matchParentSize()
                    .pointerInput(Unit) {
                        awaitPointerEventScope {
                            while (true) awaitPointerEvent()
                        }
                    },
            )
            // Sur le coin haut droit, à cheval sur le filet : dans la carte,
            // elle se serait lue comme une ligne de plus.
            BrandComingSoonBadge(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(end = MemoBookSpacing.snug)
                    .offset(y = -MemoBookSpacing.xs),
                label,
            )
        }
    }
}

/** Le voile de la carte : celui de « Bientôt disponible ». */
private const val CONTENT_OPACITY = 0.45f

@Preview(locale = "fr-rFR", name = "À venir", widthDp = 390, heightDp = 300)
@Composable
private fun BrandComingSoonPreview() {
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
    ) {
        BrandComingSoon {
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(MemoBookColor.surface, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
                    .padding(MemoBookSpacing.s),
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(40.dp)
                        .background(MemoBookColor.action, RoundedCornerShape(8.dp)),
                )
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    BrandText("Strava", MemoBookFont.bodySemibold)
                    BrandText("MemoBook pourra lire tes sorties.", MemoBookFont.body, color = MemoBookColor.inkMuted)
                }
            }
        }
    }
}
