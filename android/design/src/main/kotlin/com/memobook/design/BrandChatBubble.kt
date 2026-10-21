package com.memobook.design

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.memobook.core.ChatAuthor
import kotlin.math.max
import kotlin.math.min

/**
 * La forme d'une bulle de conversation : un rectangle arrondi, et **une queue**
 * qui l'accroche à son côté. Jumeau de `BrandBubbleShape` (`BrandChatBubble.swift`).
 *
 * La queue est ce qui fait la différence entre une bulle et une carte. Sans
 * elle, une suite de blocs alternés à gauche et à droite se lit comme une
 * liste ; avec elle, chaque bloc désigne celui qui l'a dit.
 *
 * **La queue est comptée dans le cadre**, elle n'en sort pas. Un tracé qui
 * dépasse de son rectangle se fait rogner dès qu'on l'emploie en `clip`, et
 * fausse toutes les marges du contenu. [BrandChatBubble] réserve donc la place
 * correspondante avant de poser le texte — voir [spur] et [drop].
 *
 * @param side le côté auquel la bulle est accrochée.
 */
class BrandBubbleShape(
    private val side: Side,
    private val cornerRadius: Dp = MemoBookSpacing.bubbleCornerRadius,
) : Shape {
    /** Le côté auquel la bulle est accrochée. */
    enum class Side { Leading, Trailing }

    companion object {
        /** Ce que la queue prend en largeur, à l'intérieur du cadre. */
        val spur: Dp = 7.dp

        /**
         * Ce qu'elle prend en hauteur : la pointe descend un peu sous la
         * bulle, comme une goutte. La maquette la pose 2,74 pt plus bas que le bloc.
         */
        val drop: Dp = 3.dp
    }

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        with(density) {
            Outline.Generic(path(size, spur.toPx(), drop.toPx(), cornerRadius.toPx()))
        }

    /**
     * Le tracé accroché à gauche, ou son reflet à droite. Le miroir est écrit
     * à la main, coordonnée par coordonnée (`x' = largeur − x`), plutôt que
     * par une matrice dont l'ordre de composition se lit mal.
     */
    private fun path(size: Size, spur: Float, drop: Float, cornerRadius: Float): Path {
        val mirrored = side == Side.Trailing
        fun x(value: Float) = if (mirrored) size.width - value else value
        fun arc(path: Path, center: Offset, radius: Float, startDegrees: Float) {
            val box = Rect(center, radius)
            if (mirrored) {
                path.arcTo(Rect(x(box.right), box.top, x(box.left), box.bottom), 180f - startDegrees, -90f, false)
            } else {
                path.arcTo(box, startDegrees, 90f, false)
            }
        }

        // Le corps de la bulle : le cadre, moins la place de la queue.
        val body = Rect(spur, 0f, spur + max(0f, size.width - spur), max(0f, size.height - drop))
        val radius = min(cornerRadius, min(body.width, body.height) / 2)
        val path = Path()
        if (radius <= 0f) {
            path.moveTo(x(body.left), body.top)
            path.lineTo(x(body.right), body.top)
            path.lineTo(x(body.right), body.bottom)
            path.lineTo(x(body.left), body.bottom)
            path.close()
            return path
        }

        // Le haut, puis le côté droit : trois coins arrondis sur quatre.
        path.moveTo(x(body.left + radius), body.top)
        path.lineTo(x(body.right - radius), body.top)
        arc(path, Offset(body.right - radius, body.top + radius), radius, -90f)
        path.lineTo(x(body.right), body.bottom - radius)
        arc(path, Offset(body.right - radius, body.bottom - radius), radius, 0f)

        // Le bas, jusqu'à l'aplomb de la queue.
        path.lineTo(x(body.left + radius), body.bottom)

        // La queue : deux courbes, une qui descend vers la pointe et une qui
        // remonte le long du bord. C'est ce retour concave qui la fait
        // ressembler à de l'encre plutôt qu'à un triangle collé.
        path.quadraticTo(x(body.left), body.bottom + drop, x(0f), size.height)
        path.quadraticTo(x(body.left + spur / 2), body.bottom - drop, x(body.left), body.bottom - radius)

        // Le côté gauche, et le quatrième coin.
        path.lineTo(x(body.left), body.top + radius)
        arc(path, Offset(body.left + radius, body.top + radius), radius, 180f)
        path.close()
        return path
    }

    override fun equals(other: Any?): Boolean =
        other is BrandBubbleShape && other.side == side && other.cornerRadius == cornerRadius

    override fun hashCode(): Int = 31 * side.hashCode() + cornerRadius.hashCode()
}

/**
 * **La** bulle de conversation de l'app : le fond, la queue, les marges et la
 * largeur maximale, une fois pour toutes. Jumeau de `BrandChatBubble.swift`.
 *
 * Quatre contenus la portent — le texte de MEMO, le texte du voyageur, un
 * vocal, une fiche de retranscription — et c'est précisément pour ça qu'elle
 * est un composant : quatre dessins écrits chacun de son côté divergeraient sur
 * le rayon avant la fin de l'écran.
 *
 * ```kotlin
 * BrandChatBubble(ChatAuthor.Memo) { BrandText(message, MemoBookFont.bubble) }
 * ```
 *
 * **La bulle épouse son texte, bornée par ce qui l'entoure.** Elle ne s'étire
 * pas sur toute la largeur — « Ça me convient » posé sur 300 dp ne se lit plus
 * comme une réplique — et elle ne peut pas non plus pousser hors de l'écran
 * les deux commandes qui l'accompagnent. Voir [BrandChatBubble.maximumContentWidth].
 *
 * **Elle ne décide pas de son alignement** : c'est la rangée qui la place, à
 * gauche ou à droite, avec ses commandes de l'autre côté.
 *
 * @param author décide du côté, de la couleur et du sens de la queue. C'est la
 *   seule question que la bulle pose.
 * @param fill pour un fond qui n'est pas celui de l'auteur — la fiche de
 *   retranscription, par exemple, qui est blanche mais s'étend plus large.
 *   `null` prend le fond de l'auteur.
 */
@Composable
fun BrandChatBubble(
    author: ChatAuthor,
    modifier: Modifier = Modifier,
    fill: Color? = null,
    content: @Composable () -> Unit,
) {
    val traveller = author.isTraveller
    val shape = remember(traveller) {
        BrandBubbleShape(if (traveller) BrandBubbleShape.Side.Trailing else BrandBubbleShape.Side.Leading)
    }
    Box(
        modifier
            .background(fill ?: BrandChatBubble.fill(author), shape)
            // La place de la queue, réservée du côté où elle s'accroche.
            .padding(
                start = if (traveller) 0.dp else BrandBubbleShape.spur,
                end = if (traveller) BrandBubbleShape.spur else 0.dp,
                bottom = BrandBubbleShape.drop,
            )
            .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs)
            .widthIn(max = BrandChatBubble.maximumContentWidth()),
    ) {
        content()
    }
}

object BrandChatBubble {
    fun fill(author: ChatAuthor): Color =
        if (author.isTraveller) MemoBookColor.bubbleTraveller else MemoBookColor.bubbleMemo

    /**
     * La largeur maximale du **contenu** d'une bulle.
     *
     * Elle se déduit de ce qui l'entoure au lieu d'être une fraction ronde :
     * la gouttière du fil, la colonne des deux commandes posées à côté de la
     * bulle, et ce qui doit rester visible du fond de l'autre côté — c'est ce
     * dernier reste qui dit « quelqu'un d'autre parle de ce côté-là ». Une
     * fraction en dur ferait déborder les commandes hors d'un petit écran.
     *
     * Aux tailles accessibles, on rend cette respiration au texte : à ce
     * corps-là, la garder ne laisserait que trois mots par ligne.
     *
     * Les commandes font 48 dp ici (44 pt sur iOS) : la bulle est d'autant plus
     * étroite, et c'est voulu — c'est la cible tactile d'Android qui s'applique.
     */
    fun maximumContentWidth(screenWidth: Dp, isAccessibilitySize: Boolean): Dp {
        val gutters = MemoBookSpacing.snug * 2
        val actions = MemoBookSpacing.minimumTapTarget * 2
        val breathing = if (isAccessibilitySize) 0.dp else MemoBookSpacing.s
        return screenWidth - gutters - actions - breathing
    }

    /** [maximumContentWidth] pour l'écran et la taille de police du moment. */
    @Composable
    fun maximumContentWidth(): Dp = maximumContentWidth(DeviceScreen.width(), isAccessibilityTextSize())
}

/** Une bulle posée du bon côté, pour les aperçus ci-dessous. */
@Composable
private fun BubbleRow(author: ChatAuthor, text: String) {
    Row(Modifier.fillMaxWidth()) {
        if (author.isTraveller) Spacer(Modifier.weight(1f).widthIn(min = MemoBookSpacing.s))
        BrandChatBubble(author) { BrandText(text, MemoBookFont.bubble) }
        if (!author.isTraveller) Spacer(Modifier.weight(1f).widthIn(min = MemoBookSpacing.s))
    }
}

@Preview(name = "Bulles", widthDp = 390, heightDp = 500)
@Composable
private fun BrandChatBubblePreview() {
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BubbleRow(ChatAuthor.Memo, "Comment ça se passe à Trastevere ?")
        BubbleRow(ChatAuthor.Traveller, "On a marché jusqu’au marché, et on a pris un café debout au comptoir.")
        BubbleRow(ChatAuthor.Memo, "Trastevere, je note. Qu’est-ce qui t’a marqué là-bas ?")
    }
}

@Preview(name = "Bulles — police à 200 %", widthDp = 390, heightDp = 500)
@Composable
private fun BrandChatBubbleLargeTextPreview() {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.background)
                .padding(MemoBookSpacing.screenMargin),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            BubbleRow(ChatAuthor.Memo, "Comment ça se passe à Trastevere ?")
            BubbleRow(ChatAuthor.Traveller, "Ça me convient")
        }
    }
}
