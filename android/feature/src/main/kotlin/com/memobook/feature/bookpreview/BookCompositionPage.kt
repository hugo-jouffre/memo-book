package com.memobook.feature.bookpreview

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.core.BookCopy
import com.memobook.core.BookRenderPhase
import com.memobook.design.ActivitySpinner
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.brandShadow
import com.memobook.design.isReduceMotionEnabled
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlin.math.max
import kotlin.math.min
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Une page de carnet **en train de se monter** : ses morceaux arrivent chacun
 * de son côté et se posent à leur place. Jumeau de
 * `BookPreview/BookCompositionPage.swift`.
 *
 * C'est le cœur de l'écran « On compose ton Carnet », et son seul travail est
 * de faire passer une attente pour un travail. La composition réelle se fait
 * côté serveur (OpenAI structure le récit, APITemplate le met en page) et dure
 * quelques dizaines de secondes ; montrer une roue qui tourne pendant ce
 * temps-là serait exact et décourageant. Une page qui se remplit dit la même
 * chose et la rend supportable.
 *
 * **Ce ne sont pas les vraies pièces du carnet** : ce sont les blocs de la
 * maquette du squelette — un signet, deux bandeaux, une frise de pictogrammes,
 * des lignes de texte, une photo, une carte et un rond. Ils ne prétendent pas à
 * la ressemblance ; ils prétendent au **rythme**.
 *
 * @param progress de 0 à 1 : où en est l'arrivée des morceaux. C'est l'écran
 *   qui la fait monter, pas cette vue — elle doit pouvoir être figée à 1 pour
 *   une capture, et à 0 pour un aperçu. **La valeur elle-même est animée**, et
 *   non le dessin qui en sort comme le fait SwiftUI : c'est ce qui fait partir
 *   chaque morceau à son tour, la cascade que décrit [BookCompositionPiece].
 */
@Composable
internal fun BookCompositionPage(progress: Float, modifier: Modifier = Modifier) {
    val reduceMotion = isReduceMotionEnabled()
    val shape = RoundedCornerShape(MemoBookSpacing.pageCornerRadius)

    // Les positions sont **relatives** : la page se dessine à 252 × 357 sur la
    // maquette, mais elle occupe ce qu'on lui donne. Aucune coordonnée en dp
    // ici — c'est ce qui la rend juste sur un petit téléphone comme sur un
    // grand (R5).
    BoxWithConstraints(
        modifier
            .clip(shape)
            .background(MemoBookColor.paper)
            .border(1.dp, MemoBookColor.hairline, shape)
            // Une page en construction n'a rien à dire à TalkBack que le titre
            // de l'écran ne dise déjà — voir `BookCopy.Composition.voiceOverStatus`.
            .clearAndSetSemantics {},
    ) {
        val width = maxWidth
        val height = maxHeight
        val density = LocalDensity.current
        val travelX = with(density) { width.toPx() }
        val travelY = with(density) { height.toPx() }

        for (piece in BookCompositionPiece.all) {
            val settled = BookCompositionPiece.settled(piece, progress)
            // Sous « Supprimer les animations », les morceaux ne voyagent plus :
            // ils se révèlent sur place. La promesse de l'écran — « ça
            // travaille » — tient toujours, sans mouvement.
            val remaining = if (reduceMotion) 0f else 1f - settled
            val (dx, dy) = piece.entry.direction

            Box(
                Modifier
                    .offset(x = width * piece.x, y = height * piece.y)
                    .size(width * piece.width, height * piece.height)
                    .graphicsLayer {
                        translationX = dx * travelX * remaining
                        translationY = dy * travelY * remaining
                        rotationZ = piece.rotation * settled
                        // Le morceau grandit d'un cheveu en arrivant : il **se
                        // pose** au lieu de glisser jusqu'à sa place.
                        val scale = if (reduceMotion) 1f else 0.88f + 0.12f * settled
                        scaleX = scale
                        scaleY = scale
                        // L'opacité se remplit plus vite que la course : la
                        // pièce est déjà franche à mi-chemin, ce qui évite
                        // l'impression de brouillard.
                        alpha = min(settled * 2.2f, 1f)
                    },
            ) {
                PieceShape(piece.kind)
            }
        }
    }
}

/** Le dessin d'un morceau. Il n'y en a que six : au-delà, ce ne serait plus un squelette mais une contrefaçon de la page. */
@Composable
private fun PieceShape(kind: BookCompositionPiece.Kind) {
    when (kind) {
        BookCompositionPiece.Kind.Bookmark -> Box(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.ink.copy(alpha = 0.45f), RoundedCornerShape(bottomStart = 3.dp, bottomEnd = 3.dp)),
        )
        BookCompositionPiece.Kind.Bar -> Box(Modifier.fillMaxSize().background(MemoBookColor.ink.copy(alpha = 0.12f), CircleShape))
        BookCompositionPiece.Kind.Glyph -> Box(Modifier.fillMaxSize().background(MemoBookColor.ink.copy(alpha = 0.18f), CircleShape))
        BookCompositionPiece.Kind.Photo -> Box(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.ink.copy(alpha = 0.22f), RoundedCornerShape(2.dp)),
        )
        BookCompositionPiece.Kind.Card -> {
            val shape: Shape = RoundedCornerShape(2.dp)
            Column(
                Modifier
                    .fillMaxSize()
                    .brandShadow(MemoBookShadow.Soft, shape)
                    .background(MemoBookColor.surface, shape)
                    .clip(shape)
                    .border(0.5.dp, MemoBookColor.ink.copy(alpha = 0.12f), shape),
            ) {
                // Le bandeau vert d'une carte « Fun fact » du carnet — c'est le
                // seul endroit du squelette où une couleur apparaît, et c'est ce
                // qui fait qu'on la remarque.
                Box(Modifier.fillMaxWidth().weight(1f).background(MemoBookColor.valid.copy(alpha = 0.35f)))
                Box(Modifier.fillMaxWidth().weight(1f).background(MemoBookColor.ink.copy(alpha = 0.08f)))
            }
        }
        BookCompositionPiece.Kind.Stamp -> Box(Modifier.fillMaxSize().background(MemoBookColor.separator.copy(alpha = 0.55f), CircleShape))
    }
}

/**
 * Un morceau de la page en construction : où il finit, d'où il vient, et à
 * quel moment il part.
 *
 * Une **description** et non une vue : la liste se relit d'un coup d'œil, et
 * c'est elle qui porte la chorégraphie. Régler le rythme de l'écran, c'est
 * changer des nombres ici, pas du code ailleurs.
 *
 * @property x la place finale, en fractions de la page — origine en haut à
 *   gauche, comme [y], [width] et [height].
 * @property rotation l'inclinaison finale, en degrés. Zéro pour tout ce qui est
 *   imprimé ; seuls les éléments *collés* penchent.
 * @property delay quand ce morceau part, de 0 à 1 de l'avancement global.
 */
internal data class BookCompositionPiece(
    val id: Int,
    val kind: Kind,
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    val entry: Entry,
    val rotation: Float,
    val delay: Float,
) {
    /**
     * D'où arrive le morceau. Six directions, et pas quatre : deux pièces qui
     * entrent par le même bord au même instant se lisent comme un seul bloc.
     *
     * @property direction le vecteur de départ, en **fractions de la page**.
     *   Au-delà de 1, le morceau part de hors-cadre — ce qui est le but.
     */
    enum class Entry(val direction: Pair<Float, Float>) {
        Top(0f to -1.15f),
        Bottom(0f to 1.15f),
        Leading(-1.15f to 0f),
        Trailing(1.15f to 0f),
        TopLeading(-0.9f to -0.9f),
        BottomTrailing(0.9f to 0.9f),
    }

    /** Ce que le morceau est. */
    enum class Kind {
        /** Le signet qui pend du bord haut. */
        Bookmark,

        /** Un bandeau d'en-tête, ou une ligne de texte. */
        Bar,

        /** Un pictogramme de la frise météo. */
        Glyph,

        /** Une photo collée. */
        Photo,

        /** Une carte posée de travers, avec son bandeau de couleur. */
        Card,

        /** Le rond d'un tampon. */
        Stamp,
    }

    companion object {
        /**
         * La chorégraphie, relevée sur le nœud `Skeleton - Prévisualisation
         * PDF` (3335:10208).
         *
         * Les positions sont des **fractions** de la page de 252 × 357 de la
         * maquette. L'ordre des départs raconte quelque chose : la page se
         * monte comme on monte une page — la structure d'abord (signet,
         * bandeaux), le texte ensuite, et les éléments collés en dernier, parce
         * que c'est bien ainsi qu'on colle une photo dans un carnet.
         */
        val all: List<BookCompositionPiece> = buildList {
            fun add(
                kind: Kind,
                x: Float,
                y: Float,
                width: Float,
                height: Float,
                from: Entry,
                delay: Float,
                rotation: Float = 0f,
            ) {
                add(BookCompositionPiece(size, kind, x, y, width, height, from, rotation, delay))
            }

            // 1. La structure de l'en-tête.
            add(Kind.Bookmark, 0.06f, 0.0f, 0.12f, 0.13f, from = Entry.Top, delay = 0.0f)
            add(Kind.Bar, 0.28f, 0.045f, 0.31f, 0.035f, from = Entry.Trailing, delay = 0.04f)
            add(Kind.Bar, 0.63f, 0.045f, 0.31f, 0.035f, from = Entry.Trailing, delay = 0.07f)

            // 2. La frise de pictogrammes, un par un et de la gauche : c'est
            //    une ligne, elle s'écrit dans le sens de la lecture.
            for (index in 0 until 6) {
                add(
                    Kind.Glyph,
                    0.30f + index * 0.072f,
                    0.125f,
                    0.038f,
                    0.027f,
                    from = Entry.Leading,
                    delay = 0.10f + index * 0.018f,
                )
            }

            // 3. Le texte. Huit lignes, du haut, décalées : la page « s'écrit ».
            //    La dernière est plus courte, comme une fin de paragraphe.
            val lineWidths = listOf(0.80f, 0.80f, 0.80f, 0.80f, 0.80f, 0.80f, 0.80f, 0.52f)
            lineWidths.forEachIndexed { index, width ->
                add(
                    Kind.Bar,
                    0.10f,
                    0.225f + index * 0.027f,
                    width,
                    0.012f,
                    from = if (index % 2 == 0) Entry.Leading else Entry.Trailing,
                    delay = 0.24f + index * 0.022f,
                )
            }

            // 4. Ce qu'on colle par-dessus, en dernier et de travers.
            add(Kind.Card, 0.36f, 0.50f, 0.56f, 0.17f, from = Entry.Trailing, delay = 0.46f, rotation = -4f)
            add(Kind.Photo, 0.06f, 0.61f, 0.39f, 0.23f, from = Entry.BottomTrailing, delay = 0.56f, rotation = 2f)
            add(Kind.Stamp, 0.62f, 0.72f, 0.26f, 0.18f, from = Entry.Bottom, delay = 0.66f)
        }

        /**
         * Le départ du dernier morceau. Les fenêtres se calculent dessus pour
         * que la page soit **exactement** finie à `progress == 1` : une pièce
         * encore en vol à la fin ferait sauter le passage à l'aperçu.
         */
        private val lastDelay: Float = all.maxOf { it.delay }

        /**
         * De 0 à 1 pour **ce morceau-là** : sa part de l'avancement global.
         *
         * Chaque pièce occupe une fenêtre de l'avancement, décalée par son
         * rang. C'est ce décalage qui fait la cascade : sans lui, les morceaux
         * arriveraient ensemble et la page apparaîtrait d'un bloc.
         */
        fun settled(piece: BookCompositionPiece, progress: Float): Float {
            val window = 1f - lastDelay
            val local = (progress - piece.delay) / max(window, 0.001f)
            return local.coerceIn(0f, 1f)
        }
    }
}

/**
 * Le rythme de [BookCompositionLoop] — ses constantes, sous son nom comme
 * `BrandButton.Style` : une fonction `@Composable` n'a pas de membres.
 */
internal object BookCompositionLoop {
    /** Combien de temps une page posée reste sous les yeux avant de tourner. */
    val hold: Duration = 1.6.seconds

    /**
     * Combien de temps une page met à se monter — la première comme les
     * suivantes, pour garder le même rythme. C'est aussi le plancher de
     * l'attente du modèle (`BookPreviewModel.Pacing.compositionDuration`).
     */
    val assembly: Duration = 4.2.seconds

    /** Le temps de tourner la page. */
    val turn: Duration = 0.6.seconds
}

/**
 * La page qui se monte, **puis la suivante, et ainsi de suite** tant que le
 * carnet se compose (Hugo, 08/10/2026).
 *
 * Une composition dure des minutes ; la cascade, quelques secondes. Une page
 * montée puis immobile pendant tout le reste « semble cassée ». Une fois la
 * première page posée, celle-ci s'en va donc comme on tourne une page — vers
 * la gauche, en pâlissant —, et une page blanche se monte à sa place, en
 * miroir pour que deux pages de suite ne se ressemblent pas. C'est ce qui se
 * passe pour de vrai : le carnet se compose page après page.
 *
 * La **première** page suit l'avancement du modèle ([firstPass]) : c'est lui
 * qui décide du plancher de l'attente — voir `BookPreviewModel.compositionProgress`.
 * Les suivantes sont à la vue seule : elles n'ont rien à dire au modèle, et
 * s'arrêtent avec elle.
 *
 * La boucle part quand la première page est **posée**, et non dès que le
 * modèle en pose la cible : SwiftUI la lançait au premier instant de la
 * cascade, et la première page tournait avant d'être finie.
 *
 * Sous « Supprimer les animations », une seule page, posée : la boucle se tait,
 * et c'est la ligne d'état par-dessus ([BookCompositionStatus]) qui dit que ça
 * travaille.
 *
 * @param firstPass l'avancement de la première page, tenu par le modèle : la
 *   **cible** (0 ou 1), que la vue anime en `easeOut` sur
 *   [BookCompositionLoop.assembly]. `easeOut` et non un ressort : les morceaux
 *   doivent **se poser**, et un ressort les ferait rebondir tous ensemble à la
 *   fin de la cascade.
 */
@Composable
internal fun BookCompositionLoop(firstPass: Double, modifier: Modifier = Modifier) {
    val reduceMotion = isReduceMotionEnabled()
    val first = remember { Animatable(firstPass.toFloat()) }
    val next = remember { Animatable(0f) }
    // Le rang de la page en cours de montage. Zéro : la première.
    var page by remember { mutableIntStateOf(0) }

    LaunchedEffect(firstPass) {
        val target = firstPass.toFloat()
        if (target <= first.value) {
            first.snapTo(target)
        } else {
            first.animateTo(target, tween(BookCompositionLoop.assembly.inWholeMilliseconds.toInt(), easing = SwiftMotion.easeOut))
        }
    }

    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        snapshotFlow { first.value >= 1f }.first { it }
        while (true) {
            delay(BookCompositionLoop.hold)
            // La page blanche arrive à zéro, sans animation : c'est l'ancienne
            // qui s'en va, pas la nouvelle qui se fond.
            next.snapTo(0f)
            page += 1
            delay(BookCompositionLoop.turn / 2)
            next.animateTo(1f, tween(BookCompositionLoop.assembly.inWholeMilliseconds.toInt(), easing = SwiftMotion.easeOut))
        }
    }

    val slide = with(LocalDensity.current) { 40.dp.roundToPx() }
    AnimatedContent(
        targetState = page,
        modifier = modifier,
        transitionSpec = {
            val turn = BookCompositionLoop.turn.inWholeMilliseconds.toInt()
            EnterTransition.None togetherWith
                (
                    slideOutHorizontally(tween(turn, easing = SwiftMotion.easeInOut)) { -slide } +
                        fadeOut(tween(turn, easing = SwiftMotion.easeInOut)) +
                        scaleOut(tween(turn, easing = SwiftMotion.easeInOut), targetScale = 0.94f)
                    )
        },
        label = "page",
    ) { shown ->
        // La page qui s'en va reste montée : on ne tourne qu'une page finie.
        val progress = when {
            shown == 0 -> first.value
            shown == page -> next.value
            else -> 1f
        }
        BookCompositionPage(
            progress = progress,
            modifier = Modifier
                .fillMaxSize()
                // Une page sur deux en miroir : ses morceaux arrivent de l'autre
                // côté, et la page suivante ne rejoue pas la même.
                .graphicsLayer { scaleX = if (shown % 2 == 0) 1f else -1f },
        )
    }
}

/**
 * Ce que fait la composition **en ce moment**, posé sur la page qui se monte
 * (Hugo, 08/10/2026 : « agrandir le texte qui explique que la création est en
 * cours, le mettre peut-être par-dessus l'animation, un loader »).
 *
 * Une carte crème, un sablier qui tourne, la phrase de la phase en corps de
 * texte — et non plus en légende grise sous la page, où on ne la lisait pas.
 * La seconde ligne dit le temps que ça prend : sans elle, une page qui se
 * remonte pour la troisième fois se lirait encore comme une boucle cassée.
 *
 * La phrase change d'un coup : en fondu, l'ancienne et la nouvelle se
 * superposaient le temps du passage, illisibles quand elles n'ont pas le même
 * nombre de lignes.
 */
@Composable
internal fun BookCompositionStatus(phase: BookRenderPhase?, pendingMemories: Int, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val sentence = BookCopy.Composition.phase(phase, pendingMemories)
    Row(
        modifier
            .fillMaxWidth()
            .brandShadow(MemoBookShadow.Soft, shape)
            .background(MemoBookColor.surface.copy(alpha = 0.94f), shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug)
            .clearAndSetSemantics { contentDescription = "$sentence ${BookCopy.Composition.patience}" },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Le `ProgressView` de taille courante d'iOS.
        ActivitySpinner(MemoBookColor.action, size = 20.dp)

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrandText(sentence, MemoBookFont.bodySemibold, color = MemoBookColor.ink)
            BrandText(BookCopy.Composition.patience, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }
    }
}

@Preview(locale = "fr-rFR", name = "Page en composition", widthDp = 390, heightDp = 600)
@Composable
private fun BookCompositionPagePreview() {
    // L'aperçu rejoue la cascade en boucle : c'est le seul moyen de régler un
    // rythme sans relancer l'app entre deux essais.
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        while (true) {
            progress.snapTo(0f)
            progress.animateTo(1f, tween(2400, easing = SwiftMotion.easeOut))
            delay(1000)
        }
    }
    Box(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.l),
        contentAlignment = Alignment.Center,
    ) {
        BookCompositionPage(progress.value, Modifier.fillMaxWidth().aspectRatio(252f / 357f))
    }
}
