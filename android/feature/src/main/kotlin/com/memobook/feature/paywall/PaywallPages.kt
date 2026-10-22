package com.memobook.feature.paywall

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.memobook.design.BrandButton
import com.memobook.design.BrandSquiggleDown
import com.memobook.design.BrandSquiggleUp
import com.memobook.design.BrandTagPill
import com.memobook.design.BrandText
import com.memobook.design.BrandUnderline
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.brandFooterScrim
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.design.trimmed
import com.memobook.feature.LegalRoute
import kotlinx.coroutines.delay
import kotlin.math.max
import kotlin.math.min

// Les trois écrans du paywall, et la barre qui les compte. Jumeau de
// `Paywall/PaywallPages.swift`.

/**
 * Où en est la barre de l'écran courant.
 *
 * **Une date de départ, pas une animation.** Sur iOS, la barre se remplissait
 * par une animation linéaire de six secondes posée sur un `progress` : une
 * animation en vol, qu'un changement de page devait couper — et qui, sur
 * l'iPhone de Hugo, survivait et remplissait deux segments à la fois
 * (15/09/2026). Ici rien n'est en vol : à chaque image, le segment lit l'heure
 * et calcule sa part. Tourner la page ne coupe rien, il n'y a rien à couper.
 *
 * Les dates sont des millisecondes de l'horloge monotone ([PaywallClock]).
 */
sealed interface PaywallFill {
    /** Elle se remplit depuis cette date, sur la durée d'un écran. */
    data class Running(val sinceMillis: Long) : PaywallFill

    /**
     * Elle est arrêtée à cette valeur — pleine sur le dernier écran, figée
     * pendant qu'une feuille est ouverte, à zéro l'instant d'un changement de
     * page.
     */
    data class Held(val value: Double) : PaywallFill

    val isRunning: Boolean get() = this is Running

    /** La part remplie, de 0 à 1, à cet instant. */
    fun value(atMillis: Long, durationMillis: Long): Double = when (this) {
        is Running -> fraction(sinceMillis, atMillis, durationMillis)
        is Held -> value
    }

    companion object {
        fun fraction(sinceMillis: Long, atMillis: Long, durationMillis: Long): Double {
            if (durationMillis <= 0) return 1.0
            return min(1.0, max(0.0, (atMillis - sinceMillis).toDouble() / durationMillis))
        }
    }
}

/** L'horloge de la barre : monotone, que l'heure du téléphone ne fait pas sauter. */
internal object PaywallClock {
    fun now(): Long = System.nanoTime() / 1_000_000
}

/** La barre de stories : un segment par écran, celui du moment se remplit. */
@Composable
fun PaywallStoriesBar(pageCount: Int, page: Int, fill: PaywallFill, durationMillis: Long, modifier: Modifier = Modifier) {
    // La barre se redessine à chaque image **tant qu'elle se remplit**, et plus
    // du tout ensuite : figée ou pleine, elle ne coûte rien. L'heure n'est lue
    // qu'au dessin — elle ne recompose rien.
    var now by remember { mutableLongStateOf(PaywallClock.now()) }
    LaunchedEffect(fill) {
        now = PaywallClock.now()
        if (fill !is PaywallFill.Running) return@LaunchedEffect
        while (true) withFrameMillis { now = PaywallClock.now() }
    }
    Row(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "Écran ${page + 1} sur $pageCount" },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        repeat(pageCount) { index ->
            // **Rien ne s'anime ici.** Le remplissage continu est piloté image
            // par image, et les sauts — la barre qu'on quitte passe à 1, celle
            // qu'on rouvre retombe à 0 — sont **instantanés** (Clara,
            // 17/09/2026) : deux barres qui bougent ensemble ne se lisent plus
            // comme une suite d'écrans.
            Canvas(
                Modifier
                    .weight(1f)
                    .height(PaywallMetrics.storyBarHeight),
            ) {
                val share = when {
                    index < page -> 1.0
                    index > page -> 0.0
                    else -> fill.value(now, durationMillis)
                }
                val radius = CornerRadius(size.height / 2)
                drawRoundRect(MemoBookColor.outline, cornerRadius = radius)
                if (share > 0) {
                    drawRoundRect(MemoBookColor.action, size = Size(size.width * share.toFloat(), size.height), cornerRadius = radius)
                }
            }
        }
    }
}

/**
 * Le trait qui **s'écrit** à l'arrivée de l'écran — l'animation que Figma
 * décrit sur ces nœuds (`path-trim`) : 0,117 s d'attente, puis 0,79 s de tracé
 * qui ralentit. Rien ne bouge en Reduce Motion : le trait est là, entier, tout
 * de suite.
 */
@Composable
internal fun rememberSquiggleDrawing(): State<Float> {
    val reduceMotion = isReduceMotionEnabled()
    val drawn = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            drawn.snapTo(1f)
            return@LaunchedEffect
        }
        delay(117)
        drawn.animateTo(1f, tween(790, easing = SwiftMotion.easeOut))
    }
    return drawn.asState()
}

/**
 * Le trait bleu qui se trace à l'arrivée de l'écran.
 *
 * @param path le tracé de `BrandStrokes`, rapporté au cadre reçu.
 * @param bleedRatio de combien le trait dépasse **de chaque côté**, en part de
 *   sa largeur. Un trait qui s'arrête pile au bord de l'écran montre ses deux
 *   bouts arrondis, et se lit alors comme un objet posé là plutôt que comme un
 *   geste qui traverse la page. Douze pour cent de chaque côté suffisent à les
 *   sortir du cadre sur tous les formats.
 */
@Composable
fun PaywallSquiggle(
    path: (Size) -> Path,
    lineWidthRatio: Float,
    aspectRatio: Float,
    modifier: Modifier = Modifier,
    bleedRatio: Float = PaywallSquiggle.bleed,
) {
    val drawn by rememberSquiggleDrawing()
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(aspectRatio)
            .clearAndSetSemantics {}
            .drawWithCache {
                // **Le débordement est dans le chemin**, pas dans une mise à
                // l'échelle : étirer un trait déjà tracé en écrase l'épaisseur
                // d'un côté et ovalise ses bouts ronds. Le chemin est construit
                // dans un cadre élargi **à l'origine**, puis décalé de la moitié
                // du débordement — les tracés de `BrandStrokes` ne lisent que la
                // taille du cadre (Hugo, 19/09/2026). Le `trim` porte sur le
                // tracé entier : le trait entre **par le hors-champ**.
                val margin = size.width * bleedRatio
                val full = path(Size(size.width + margin * 2, size.height)).apply { translate(Offset(-margin, 0f)) }
                val stroke = Stroke(width = size.height * lineWidthRatio, cap = StrokeCap.Round)
                onDrawBehind { drawPath(full.trimmed(to = drawn), MemoBookColor.outline, style = stroke) }
            },
    )
}

object PaywallSquiggle {
    /** De combien le trait dépasse de chaque côté — voir [PaywallSquiggle]. */
    const val bleed = 0.12f
}

/**
 * Sort un bloc des marges de l'écran, de [amount] de chaque côté — la marge
 * négative de SwiftUI (`.padding(.horizontal, -PaywallMetrics.margin)`), que
 * Compose n'a pas. La place que le bloc prend dans sa colonne ne change pas.
 */
internal fun Modifier.horizontalBleed(amount: Dp): Modifier = layout { measurable, constraints ->
    val inset = amount.roundToPx()
    val widened = if (constraints.hasBoundedWidth) {
        constraints.copy(minWidth = 0, maxWidth = constraints.maxWidth + inset * 2)
    } else {
        constraints.copy(minWidth = 0)
    }
    val placeable = measurable.measure(widened)
    val width = (placeable.width - inset * 2).coerceIn(constraints.minWidth, constraints.maxWidth.takeIf { it != Constraints.Infinity } ?: Int.MAX_VALUE)
    layout(width, placeable.height) { placeable.place(-inset, 0) }
}

/**
 * Une zone de la page sous le doigt — le geste des stories d'Instagram (Hugo,
 * 02/10/2026) : **bref, il tourne la page ; posé, il arrête le temps**.
 *
 * **La barre se fige dès que le doigt se pose**, et repart d'où elle s'était
 * arrêtée quand il se lève : on relit un écran aussi longtemps qu'on veut, il
 * ne tourne pas sous le doigt. Et un doigt qui s'est attardé au-delà de
 * [PaywallMetrics.holdDelayMillis] **ne tourne pas la page en se levant** : il
 * voulait lire, pas avancer.
 *
 * ⚠️ **Jamais dans le contenu d'un défilement.** Un appui posé là prend le
 * doigt avant lui, et la page ne défile plus. C'est pourquoi l'offre n'arrête
 * pas le temps sous le doigt : elle ne tourne jamais toute seule, sa barre se
 * remplit puis reste pleine.
 *
 * Le geste finit toujours par dire qu'il s'arrête — levé, glissé hors de la
 * zone ou interrompu —, et ce qui recouvre la page la retire sous le doigt :
 * la barre ne peut pas rester figée.
 *
 * Posée **sous** le contenu : les boutons et les pastilles reçoivent le doigt
 * les premiers ; le texte des pages, qui n'a pas de geste, le laisse traverser
 * — le `paywallProse()` d'iOS n'a pas lieu d'être ici.
 *
 * @param onTap ce que fait un tapotis ; `null` pour une zone qui ne tourne rien,
 *   où le doigt ne fait qu'arrêter le temps.
 * @param onHold le doigt se pose (`true`) ou se lève (`false`).
 */
@Composable
internal fun PaywallStoryTouchZone(modifier: Modifier, onTap: (() -> Unit)?, onHold: (Boolean) -> Unit) {
    val tap by rememberUpdatedState(onTap)
    val hold by rememberUpdatedState(onHold)
    DisposableEffect(Unit) { onDispose { hold(false) } }
    Box(
        modifier.pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                hold(true)
                val up = try {
                    waitForUpOrCancellation()
                } finally {
                    hold(false)
                }
                if (up != null && up.uptimeMillis - down.uptimeMillis < PaywallMetrics.holdDelayMillis) {
                    tap?.let {
                        up.consume()
                        it()
                    }
                }
            }
        },
    )
}

// MARK: - Écran 1 — « On adore t'écouter ! »

/**
 * Le premier écran de la découverte. Il s'ouvre **sur une envie**, pas sur une
 * limite (Hugo, 03/10/2026) : on arrive souvent ici parce que le crédit du jour
 * vient de tomber, et l'écran dit ce que ça veut dire — qu'on avait beaucoup à
 * raconter.
 */
@Composable
fun PaywallStoriesToTell(onContinue: () -> Unit) {
    PaywallStoryPage(onContinue) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            PaywallEyebrow(PaywallCopy.storiesEyebrow)
            PaywallTitle(lead = PaywallCopy.storiesTitleLead, strong = PaywallCopy.storiesTitleStrong)
            PaywallLeadStrong(PaywallCopy.storiesBodyLead, PaywallCopy.storiesBodyStrong)
        }
        PaywallSquiggle(
            BrandSquiggleDown::path,
            lineWidthRatio = BrandSquiggleDown.lineWidthRatio,
            aspectRatio = BrandSquiggleDown.size.width / BrandSquiggleDown.size.height,
            modifier = Modifier.horizontalBleed(PaywallMetrics.margin),
        )
    }
}

// MARK: - Écran 2 — « Les détails s'effacent en quelques jours »

/**
 * Pourquoi raconter tout de suite, et ce que chaque formule permet. Il garde la
 * pastille « Voir un aperçu → » : montrer le carnet reste le meilleur argument.
 *
 * @param onPreview ouvre la feuille « Prévisualisation ». L'écran ne la
 *   présente pas lui-même : elle doit se poser **par-dessus le paywall
 *   entier**, et c'est [PaywallView] qui l'occupe.
 */
@Composable
fun PaywallFadingDetails(onContinue: () -> Unit, onPreview: () -> Unit) {
    PaywallStoryPage(
        onContinue,
        footnote = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
                PaywallCopy.detailsFootnote.forEach { line ->
                    BrandText(line, MemoBookFont.taglineRegular, color = MemoBookColor.inkMuted, textAlign = TextAlign.Center)
                }
            }
        },
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            PaywallEyebrow(PaywallCopy.detailsEyebrow)
            PaywallTitle(lead = PaywallCopy.detailsTitleLead, strong = PaywallCopy.detailsTitleStrong, isUnderlined = true)
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                PaywallCopy.detailsBody.forEach { line ->
                    BrandText(line, MemoBookFont.taglineRegular, textAlign = TextAlign.Center)
                }
                // La pastille **ouvre** la feuille du nœud « Modale - Paywall
                // Previsualisation ». Elle garde son dessin de pastille, comme
                // la maquette : c'est une proposition posée dans une phrase, pas
                // l'appel à l'action de l'écran — celui-là est le bouton bleu du
                // bas. La cible tactile monte à 48 même si la pastille est plus
                // courte : le dessin est plus petit que le geste.
                Box(
                    Modifier
                        .heightIn(min = MemoBookSpacing.minimumTapTarget)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = PlainButtonIndication,
                            role = Role.Button,
                            onClick = onPreview,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    BrandTagPill(PaywallCopy.previewPill, tone = BrandTagPill.Tone.AccentOutlined, isUppercased = true)
                }
            }
        }
        PaywallSquiggle(
            BrandSquiggleUp::path,
            lineWidthRatio = BrandSquiggleUp.lineWidthRatio,
            aspectRatio = BrandSquiggleUp.size.width / BrandSquiggleUp.size.height,
            modifier = Modifier.horizontalBleed(PaywallMetrics.margin),
        )
    }
}

// MARK: - Le mot de retour

/**
 * L'écran qui ouvre le paywall d'un ancien abonné.
 *
 * **Il remplace deux écrans à lui seul.** La version de découverte dit l'envie
 * de raconter puis explique les deux formules ; celui-ci ne réexplique rien, et
 * le dit : « on ne t'embête pas plus ». C'est le seul écran de l'app dont la
 * raison d'être est d'en économiser un autre.
 */
@Composable
fun PaywallReturning(onContinue: () -> Unit) {
    PaywallStoryPage(onContinue) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            PaywallEyebrow(PaywallCopy.returnEyebrow)
            PaywallTitle(lead = PaywallCopy.returnTitleLead, strong = PaywallCopy.returnTitleStrong, isUnderlined = true)
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
                PaywallCopy.returnBody.forEach { line ->
                    BrandText(line, MemoBookFont.taglineRegular, textAlign = TextAlign.Center)
                }
            }
        }
        PaywallSquiggle(
            BrandSquiggleDown::path,
            lineWidthRatio = BrandSquiggleDown.lineWidthRatio,
            aspectRatio = BrandSquiggleDown.size.width / BrandSquiggleDown.size.height,
            modifier = Modifier.horizontalBleed(PaywallMetrics.margin),
        )
    }
}

/**
 * La charpente des trois écrans qui tournent : un ressort, le texte et son
 * trait, un ressort, puis la mention et « Continuer » en bas.
 */
@Composable
private fun PaywallStoryPage(
    onContinue: () -> Unit,
    footnote: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .padding(bottom = MemoBookSpacing.l),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        content()
        Spacer(Modifier.weight(1f))
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), horizontalAlignment = Alignment.CenterHorizontally) {
            footnote?.invoke()
            BrandButton(PaywallCopy.cont, style = BrandButton.Style.Blue, fillsWidth = true, action = onContinue)
        }
    }
}

// MARK: - Écran 3 — l'offre

/**
 * L'offre.
 *
 * @param price le prix, tel que le store le facture — « 4,99 € ».
 * @param period la période qu'il paie — « mois » —, lue sur le produit.
 * @param title le titre, qui change avec la version — voir [offerTitle]. Le
 *   surtitre, les arguments et le bouton, eux, sont les mêmes : c'est la
 *   **même offre**, pas une seconde.
 * @param isPurchasing la feuille du store est ouverte, ou le serveur n'a pas
 *   encore répondu.
 * @param isRestoring la restauration est en cours.
 * @param onRestore « Restaurer mes achats » — exigé sur l'écran d'achat.
 * @param onShowLegal les conditions ou la politique de confidentialité, exigées
 *   à côté du bouton d'un abonnement.
 * @param onBack le tapotis sur la moitié gauche : **reculer d'un écran**, comme
 *   sur les deux premiers (T132, T135). Le défilement prend le doigt avant les
 *   zones que le paywall pose sous lui ; la zone vit donc **dans** son contenu,
 *   derrière les cartes, qui laissent passer le tapotis.
 */
@Composable
fun PaywallOffer(
    price: String,
    period: String,
    onSubscribe: () -> Unit,
    title: Pair<String, String> = PaywallCopy.offerTitleLead to PaywallCopy.offerTitleStrong,
    isPurchasing: Boolean = false,
    isRestoring: Boolean = false,
    onRestore: () -> Unit = {},
    onShowLegal: (LegalRoute) -> Unit = {},
    onBack: () -> Unit = {},
) {
    // La hauteur du pied, mesurée : c'est elle qu'il faut retirer de la page
    // pour centrer le contenu dans ce qu'on **voit**. Centré sur la page
    // entière, le contenu laissait un vide en haut et cachait sa dernière carte
    // sous le pied.
    var footerHeight by remember { mutableIntStateOf(0) }
    val footerHeightDp = with(LocalDensity.current) { footerHeight.toDp() }

    // **Un défilement, et non une colonne qui répartit l'espace.** Les cartes,
    // un titre de deux lignes et le pied ne tiennent pas sur un petit
    // téléphone — ni sur un grand en taille de texte agrandie —, et la colonne
    // faisait remonter le tout **sous** la barre de stories, jusque sur
    // « Besoin d'aide ? » (Hugo, 15/09/2026). Le pied — la mention et le
    // bouton — reste posé en bas sur le voile de la marque, et les cartes
    // défilent dessous.
    //
    // La page sort des marges de l'écran, pour que le voile du pied aille d'un
    // bord à l'autre et jusqu'au bas de la dalle ; elle remet la marge sur son
    // propre contenu. Et elle laisse un souffle sous la barre de stories, que
    // le contenu ne vient pas toucher.
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .padding(top = MemoBookSpacing.xs)
            .horizontalBleed(PaywallMetrics.margin),
    ) {
        val viewport = maxHeight
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    // Assez haut pour que le contenu se centre dans la zone
                    // visible quand il y tient ; au-delà, il défile.
                    .heightIn(min = (viewport - footerHeightDp).coerceAtLeast(0.dp)),
            ) {
                // La moitié gauche recule d'un écran ; la droite ne fait rien,
                // c'est le dernier. Derrière le contenu, pour que les boutons
                // gagnent toujours. Un simple tapotis, et pas
                // `PaywallStoryTouchZone` : l'appui empêchait de faire défiler.
                Row(Modifier.matchParentSize().clearAndSetSemantics {}) {
                    Box(
                        Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .pointerInput(Unit) { detectTapGestures { onBack() } },
                    )
                    Spacer(Modifier.weight(1f))
                }
                Column(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = (viewport - footerHeightDp).coerceAtLeast(0.dp))
                        .padding(horizontal = PaywallMetrics.margin)
                        .padding(top = MemoBookSpacing.s),
                    verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l, Alignment.CenterVertically),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                        PaywallEyebrow(PaywallCopy.offerEyebrow)
                        PaywallTitle(lead = title.first, strong = title.second, isUnderlined = true)
                    }

                    // Les cartes se chevauchent de 4 et penchent chacune de son
                    // côté : c'est une pile de papiers posés à la main, pas une
                    // liste. Des cartes de décor : elles laissent passer le
                    // tapotis jusqu'à la zone de retour.
                    Column(verticalArrangement = Arrangement.spacedBy((-4).dp)) {
                        PaywallCopy.arguments.forEach { PaywallArgumentCard(it) }
                    }

                    PaywallStoreSection(isPurchasing, isRestoring, onRestore, onShowLegal)
                }
            }
            Spacer(Modifier.height(footerHeightDp))
        }

        // Le voile du haut : ce qui remonte sous la barre de stories s'y
        // **dissout** au lieu d'être tranché net au ras de la barre. Court,
        // pour ne toucher que ce qui défile, jamais le surtitre au repos.
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .height(MemoBookSpacing.s)
                .background(Brush.verticalGradient(listOf(MemoBookColor.background, MemoBookColor.background.copy(alpha = 0f))))
                .clearAndSetSemantics {},
        )

        PaywallOfferFooter(
            price = price,
            period = period,
            isPurchasing = isPurchasing,
            onSubscribe = onSubscribe,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .onSizeChanged { footerHeight = it.height },
        )
    }
}

/**
 * La mention de renouvellement et le bouton, sur le voile — voir
 * `BrandFooterScrim` : ce qui défile dessous s'y dissout, et les deux restent
 * lisibles.
 */
@Composable
private fun PaywallOfferFooter(price: String, period: String, isPurchasing: Boolean, onSubscribe: () -> Unit, modifier: Modifier) {
    // **Le pied entier s'arrête à la première taille accessible**, et plus
    // seulement son bouton (recette du 03/10/2026) : en très grand texte, la
    // mention seule prenait 40 % de l'écran, le prix se coupait sur deux
    // lignes et les cartes se lisaient sous le voile. Au-delà, une barre
    // ancrée en bas cache ce qu'elle sert à vendre ; les cartes, elles,
    // grandissent et défilent dessus. (Le `...accessibility1` d'iOS : ×1,5 ici,
    // le seuil des tailles accessibles d'Android.)
    val density = LocalDensity.current
    val capped = Density(density.density, fontScale = min(density.fontScale, PaywallMetrics.footerFontScaleCap))
    CompositionLocalProvider(LocalDensity provides capped) {
        Column(
            modifier
                .fillMaxWidth()
                .brandFooterScrim()
                .navigationBarsPadding()
                .padding(horizontal = PaywallMetrics.margin)
                .padding(top = MemoBookSpacing.s, bottom = MemoBookSpacing.xs),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
                val renewal = PaywallCopy.offerFootnotePrice(price = price, period = period)
                PaywallLeadStrong(renewal.lead, renewal.price, trail = renewal.trail)
                // En petit, comme une mention : elle est là pour être trouvée,
                // pas pour disputer le prix au regard.
                BrandText(
                    PaywallCopy.offerFootnoteDetail(period),
                    MemoBookFont.caption,
                    color = MemoBookColor.inkMuted,
                    textAlign = TextAlign.Center,
                )
            }

            BrandButton(
                PaywallCopy.offerCallToAction,
                icon = painterResource(R.drawable.icon_arrow_forward),
                iconPlacement = BrandButton.IconPlacement.Trailing,
                isLoading = isPurchasing,
                fillsWidth = true,
                action = onSubscribe,
            )
        }
    }
}

/**
 * **Sous les cartes** (Hugo, 01/10/2026) : « Restaurer mes achats », puis les
 * conditions et la confidentialité en petit. C'est ce que les stores cherchent
 * sur l'écran d'un abonnement : un moyen de retrouver un abonnement déjà payé —
 * sur un autre téléphone, après une réinstallation —, et les deux documents
 * qu'on accepte en s'abonnant. Posés dans la page et non dans le pied, ils ne
 * disputent pas le bouton de l'offre et ne font pas grandir le voile.
 */
@Composable
private fun PaywallStoreSection(
    isPurchasing: Boolean,
    isRestoring: Boolean,
    onRestore: () -> Unit,
    onShowLegal: (LegalRoute) -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = MemoBookSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandButton(
            PaywallCopy.Purchase.restore,
            style = BrandButton.Style.Secondary,
            size = BrandButton.Size.Medium,
            isLoading = isRestoring,
            enabled = !isPurchasing,
            action = onRestore,
        )

        // En très grand texte seulement, la ligne ne tient plus : les deux liens
        // s'empilent (le `ViewThatFits` d'iOS).
        val links: @Composable () -> Unit = {
            PaywallLegalLink(PaywallCopy.Purchase.terms) { onShowLegal(LegalRoute.TermsOfUse) }
            PaywallLegalLink(PaywallCopy.Purchase.privacy) { onShowLegal(LegalRoute.PrivacyPolicy) }
        }
        if (isAccessibilityTextSize()) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) { links() }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) { links() }
        }
    }
}

/** Souligné pour se lire comme un lien, et aussi haut qu'un doigt : le dessin est plus petit que le geste. */
@Composable
private fun PaywallLegalLink(title: String, action: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            ),
        contentAlignment = Alignment.Center,
    ) {
        BrandText(title, MemoBookFont.taglineRegular.copy(textDecoration = TextDecoration.Underline))
    }
}

/** Une des promesses de l'offre : une pastille d'icône et deux lignes. */
@Composable
fun PaywallArgumentCard(argument: PaywallCopy.Argument) {
    val badgeSide = scaled(34.dp)
    // Presque la plaque entière : le glyphe du jeu de marque n'occupe qu'une
    // part de sa boîte — voir `MemoBookSpacing.contentIcon`.
    val iconSide = scaled(28.dp)
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Row(
        Modifier
            .rotate(argument.tilt)
            .fillMaxWidth()
            .background(MemoBookColor.background, shape)
            .border(1.dp, MemoBookColor.outline, shape)
            .padding(horizontal = MemoBookSpacing.xs)
            // 10 et non 14 : les cartes empilées prenaient assez de hauteur
            // pour pousser le titre hors de l'écran sur un petit téléphone, et
            // l'offre se lit d'un bloc ou ne se lit pas (Hugo, 19/09/2026).
            .padding(vertical = MemoBookSpacing.xs + 2.dp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                // La pastille se redresse : la carte penche, pas son icône.
                .rotate(-argument.tilt)
                .size(badgeSide)
                .background(MemoBookColor.outline.copy(alpha = 0.3f), RoundedCornerShape(MemoBookSpacing.snug + 1.dp))
                .clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(argument.icon),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                modifier = Modifier.size(iconSide),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            BrandText(argument.title, MemoBookFont.tagline)
            BrandText(argument.detail, MemoBookFont.caption)
        }
    }
}

// MARK: - Morceaux communs

/** Le surtitre : une ligne de Sora, au-dessus du titre. */
@Composable
fun PaywallEyebrow(title: String) {
    BrandText(title, MemoBookFont.eyebrow, textAlign = TextAlign.Center)
}

/**
 * Le titre des trois écrans : une phrase où **la fin pèse**, et se souligne
 * parfois d'un trait tracé à la main.
 *
 * **Les mots forts sur leur propre ligne.** Ils étaient dans la même phrase que
 * l'amorce, et le trait qui les souligne se posait donc sous une ligne dont ils
 * n'occupent que la fin. Sur leur ligne, la question ne se pose plus : le trait
 * fait leur largeur, sous eux (Hugo, 19/09/2026). Et la phrase se lit mieux —
 * c'est bien la fin qui pèse.
 *
 * Le trait **derrière** les mots, et non par-dessus : posé en surcouche, il
 * recouvrait les jambages qui descendent le plus — « en quelques jours » se
 * lisait « en quelaues iours » (recette du 03/10/2026).
 */
@Composable
fun PaywallTitle(lead: String, strong: String, isUnderlined: Boolean = false) {
    val tracking = (-0.41).sp
    val drawn by rememberSquiggleDrawing()
    val underlineOffset = with(LocalDensity.current) { (MemoBookSpacing.xs + 2.dp).toPx() }
    Column(
        Modifier.clearAndSetSemantics { contentDescription = lead + strong },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BrandText(lead, MemoBookFont.h1Light.copy(letterSpacing = tracking), textAlign = TextAlign.Center)
        BrandText(
            strong,
            MemoBookFont.h1.copy(letterSpacing = tracking),
            textAlign = TextAlign.Center,
            modifier = if (!isUnderlined) {
                Modifier
            } else {
                // Le trait sous les derniers mots : leur largeur exacte, sans
                // débordement — un soulignement n'a pas à sortir de l'écran,
                // contrairement aux grands gestes qui traversent les pages. Il
                // se pose sous les jambages, pas dedans : le « p » et le « g »
                // descendent sous la ligne de base.
                Modifier.drawWithCache {
                    val ratio = BrandUnderline.size.width / BrandUnderline.size.height
                    val box = Size(size.width, size.width / ratio)
                    val path = BrandUnderline.path(box).apply { translate(Offset(0f, size.height + underlineOffset)) }
                    val stroke = Stroke(width = box.height * BrandUnderline.lineWidthRatio, cap = StrokeCap.Round)
                    onDrawBehind { drawPath(path.trimmed(to = drawn), MemoBookColor.outline, style = stroke) }
                }
            },
        )
    }
}

/** Une phrase en General Sans 14, dont une partie se lit en demi-gras. */
@Composable
private fun PaywallLeadStrong(lead: String, strong: String, trail: String = "") {
    val text = remember(lead, strong, trail) {
        buildAnnotatedString {
            append(lead)
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(strong) }
            append(trail)
        }
    }
    BasicText(text, style = MemoBookFont.taglineRegular.copy(color = MemoBookColor.ink, textAlign = TextAlign.Center))
}
