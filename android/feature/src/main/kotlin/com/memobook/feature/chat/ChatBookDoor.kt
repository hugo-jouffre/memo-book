package com.memobook.feature.chat

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.keyframes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.ChatBookPreview
import com.memobook.core.ChatCopy
import com.memobook.design.BrandMarkDrawing
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.brandShadow
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.home.CardPressStyle
import kotlin.math.min

/**
 * **Le petit livre qui dépasse du bord** — T297. Jumeau de `ChatBookDoor`
 * (`ChatBookDoor.swift`).
 *
 * « Un petit livre dépasse du bord, en haut à droite, et sautille quand
 * l'aperçu se met à jour — la porte d'entrée du PDF, à la manière des stories
 * dans les messages d'Instagram » (Hugo, 28/11/2026).
 *
 * **Il remplace la capsule « Ton carnet prend forme »** (choix de Hugo, le
 * même jour) : deux portes vers le même écran, à vingt points l'une de
 * l'autre, se lisent comme une seule. L'imprimante de l'en-tête reste.
 *
 * **Et il reste là** : la capsule allait et venait au défilement parce qu'elle
 * était large et bavarde ; un livre qui ne montre que les trois quarts de son
 * plat n'a pas besoin de disparaître pour se faire oublier.
 *
 * **Deux âges**, et c'est le serveur qui tranche ([ChatBookPreview]) : nu,
 * avec l'étiquette qui décompte les étapes illustrées qui le séparent de sa
 * couverture ; puis couvert, la photo sur le plat et le livre épaissi.
 */
@Composable
fun ChatBookDoor(preview: ChatBookPreview, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val plateWidth = scaled(60.dp)
    val plateHeight = plateWidth * 1.41f
    // **Ce qui dépasse, et ce qui reste visible** : le quart du plat sort du
    // bord droit. Assez pour qu'on voie qu'il continue, assez peu pour que la
    // part visible reste une cible honnête — 45 dp, au-dessus des 48 de la
    // marque une fois la tranche comptée.
    val hidden = plateWidth / 4
    // Les feuillets : deux au début, cinq quand le carnet est épais. Le livre
    // grossit avec ce qui est **composé**, pas avec ce qui est raconté.
    val leaves = min(5, 2 + preview.pageCount / 16)
    val shape = RoundedCornerShape(4.dp)
    val description = remember(preview.coverUrl, preview.memoryCount, preview.pageCount) {
        val state = if (preview.coverUrl == null) ChatCopy.BookDoor.bareBook else ChatCopy.previewTitle
        "$state. ${ChatCopy.previewSubtitle(memories = preview.memoryCount, pages = preview.pageCount)}"
    }

    // **Le sautillement** (T297) : le livre tressaute quand une page de plus
    // est composée, et pas une fois de plus — le fil se relit toutes les trois
    // secondes, et un livre qui sautille à chaque sondage deviendrait un
    // clignotant. En Reduce Motion, il ne bouge pas : c'est un signe, pas une
    // information.
    val isStill = isReduceMotionEnabled()
    val angle = remember { Animatable(0f) }
    val lift = remember { Animatable(0f) }
    LaunchedEffect(preview.pageCount, isStill) {
        if (isStill) return@LaunchedEffect
        angle.animateTo(
            0f,
            keyframes {
                durationMillis = 480
                -6f at 120
                4f at 240
                -2f at 340
                0f at 480
            },
        )
    }
    LaunchedEffect(preview.pageCount, isStill) {
        if (isStill) return@LaunchedEffect
        lift.animateTo(
            0f,
            keyframes {
                durationMillis = 380
                -5f at 140
                0f at 380
            },
        )
    }

    Box(
        modifier
            .offset(x = hidden)
            .graphicsLayer {
                transformOrigin = TransformOrigin(0.5f, 1f)
                rotationZ = angle.value
                translationY = lift.value * density
            }
            .brandShadow(MemoBookShadow.Raised, shape)
            .clip(shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = CardPressStyle,
                onClickLabel = ChatCopy.Voice.openPreview,
                onClick = onOpen,
            )
            .semantics { contentDescription = description },
        contentAlignment = Alignment.TopEnd,
    ) {
        // **Les feuillets derrière le plat** : c'est ce qui en fait un livre
        // et non une carte. À soixante points, une tranche de filets d'un
        // point et demi ne se voit pas.
        for (leaf in 1 until leaves) {
            Box(
                Modifier
                    .offset(x = -(leaf * 2.5).dp, y = (leaf * 2.5).dp)
                    .size(plateWidth, plateHeight)
                    .background(MemoBookColor.surface, shape)
                    .border(0.5.dp, MemoBookColor.hairline, shape),
            )
        }
        Box(
            Modifier
                .size(plateWidth, plateHeight)
                .background(MemoBookColor.surface, shape)
                .clip(shape)
                .border(1.dp, MemoBookColor.outline, shape),
            contentAlignment = Alignment.Center,
        ) {
            val cover = preview.coverUrl
            if (cover != null) {
                AsyncImage(
                    model = cover.toString(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(plateWidth, plateHeight),
                )
            } else {
                // Le plat nu porte le signe de la marque, en très pâle : un
                // rectangle crème seul se lit comme une image qui n'a pas
                // chargé.
                BrandMarkDrawing(
                    progress = 1f,
                    modifier = Modifier.size(plateWidth * 0.42f, plateWidth * 0.42f).alpha(0.6f),
                    color = MemoBookColor.outline,
                )
            }
        }
    }
}

/**
 * L'étiquette posée sous le livre, tant qu'il n'a pas de couverture.
 *
 * Elle **décompte** — « après 2 étapes avec photos » —, et elle disparaît
 * d'elle-même quand la photo arrive : c'est ce qui en fait une étiquette et
 * non une consigne. Le serveur décide du nombre ; l'app l'écrit.
 */
@Composable
fun ChatBookDoorCaption(steps: Int, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(10.dp)
    BrandText(
        ChatCopy.BookDoor.coverAfter(steps),
        MemoBookFont.caption,
        // **Opaque, et cernée** : elle flotte au-dessus du fil comme le livre,
        // et un verre translucide posé sur une fiche se lisait comme une tache
        // sur elle, pas comme une étiquette.
        modifier
            .widthIn(max = 150.dp)
            .brandShadow(MemoBookShadow.Raised, shape)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(horizontal = MemoBookSpacing.xs, vertical = 5.dp),
        color = MemoBookColor.inkMuted,
        textAlign = TextAlign.End,
    )
}
