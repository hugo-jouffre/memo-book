package com.memobook.design

import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.annotation.DrawableRes
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberOverscrollEffect
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.dismiss
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.util.lerp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.math.PI

/**
 * La feuille modale de MemoBook : elle monte du bas, tient la hauteur de son
 * contenu, et se referme au glissé. Jumeau de `BrandSheet.swift`.
 *
 * **Deux couches, comme sur iOS.** [BrandSheet] est le *dessin* — la poignée,
 * le grand titre Sora, le rond de fermeture, l'aplat et le rayon de 28 —, et
 * [BrandSheetHost] la *présentation*, le jumeau de `.brandSheet(item:)` : il
 * ouvre la fenêtre, pose le voile, fait monter la feuille, la referme au
 * glissé, au retour du système et au toucher hors d'elle, et l'annonce au
 * compteur qui fait reculer l'app. Une vue `…Sheet` appelle [BrandSheet] ;
 * l'écran qui la présente l'enveloppe dans [BrandSheetHost].
 *
 * ```kotlin
 * BrandSheetHost(item = destination, onDismissRequest = { destination = null }) { destination ->
 *     BrandSheet("Adresse postale", subtitle = "Ajoute l’adresse où tu souhaites recevoir ton carnet.") {
 *         // les champs, puis le CTA
 *     }
 * }
 * ```
 *
 * **La hauteur suit le contenu**, plafonnée sous le haut de l'écran
 * ([BrandSheetMetrics.appReveal]) : un contenu plus haut défile. Compose mesure
 * avant de dessiner, il n'y a donc pas de feuille de départ de 240 à déplier.
 *
 * **Elle est posée au bas de l'écran**, ses coins du bas concentriques à ceux
 * de la dalle ([DeviceScreen.cornerRadius]) : elle touche les bords, son
 * ombre tombe derrière elle, et elle rogne ce qu'elle porte.
 *
 * **Un enchaînement de feuilles ne s'empile pas** : une confirmation en
 * plusieurs temps se fait dans une seule feuille dont le contenu change. Une
 * exception voulue, l'aperçu du carnet posé sur la feuille d'abonnement
 * (Hugo, 16/09/2026).
 *
 * @param icon le pictogramme de marque posé **au-dessus** du titre, dans un
 *   disque bleu — le cadenas de « Mot de passe oublié ». Toujours centré.
 * @param badge la pastille qui se glisse **entre** le titre et le sous-titre —
 *   « ABONNÉE ». Elle qualifie le titre, donc elle appartient à l'en-tête.
 * @param topOverflow la hauteur **réservée au-dessus** de l'aplat, pour ce qui
 *   doit le dépasser par le haut. Zéro partout aujourd'hui, depuis que la photo
 *   des fondateurs s'est posée sur la ligne du titre (12/10/2026).
 */
@Composable
fun BrandSheet(
    title: String,
    modifier: Modifier = Modifier,
    @DrawableRes icon: Int? = null,
    badge: String? = null,
    subtitle: String? = null,
    titleAlignment: BrandSheet.TitleAlignment = BrandSheet.TitleAlignment.Leading,
    surface: BrandSheet.Surface = BrandSheet.Surface.Paper,
    topOverflow: Dp = 0.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    BrandSheetLayout(
        title, modifier, icon, badge, listOfNotNull(subtitle), titleAlignment, surface, topOverflow,
        leading = null, content = content,
    )
}

/**
 * Le même en-tête, mais dont le chapeau tient en **plusieurs paragraphes** —
 * les trois feuilles de résiliation. Une liste et non une chaîne à `\n\n` :
 * celle-ci donnerait une ligne vide entière là où la maquette ne veut que
 * l'écart d'un paragraphe, et une ligne vide ne se lit pas à TalkBack.
 */
@Composable
fun BrandSheet(
    title: String,
    paragraphs: List<String>,
    modifier: Modifier = Modifier,
    @DrawableRes icon: Int? = null,
    badge: String? = null,
    titleAlignment: BrandSheet.TitleAlignment = BrandSheet.TitleAlignment.Leading,
    surface: BrandSheet.Surface = BrandSheet.Surface.Paper,
    topOverflow: Dp = 0.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    BrandSheetLayout(
        title, modifier, icon, badge, paragraphs, titleAlignment, surface, topOverflow,
        leading = null, content = content,
    )
}

/**
 * Une illustration **posée devant le titre**, sur sa ligne, le rond de
 * fermeture au bout — la photo des fondateurs (maquette « Un mot des
 * fondateurs », `3709:17115`, Hugo, 12/10/2026). Le titre se centre sur sa
 * hauteur ; en taille de texte accessible, l'illustration prend sa propre
 * ligne au-dessus.
 */
@Composable
fun BrandSheet(
    title: String,
    leading: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    BrandSheetLayout(
        title, modifier, icon = null, badge = null, paragraphs = emptyList(),
        titleAlignment = BrandSheet.TitleAlignment.Leading, surface = BrandSheet.Surface.Paper,
        topOverflow = 0.dp, leading = leading, content = content,
    )
}

/** Les axes de la feuille, sous le nom du composant comme sur iOS (`BrandSheet.TitleAlignment`). */
object BrandSheet {
    /** Comment le titre se pose en tête de la feuille. */
    enum class TitleAlignment {
        /** À gauche, le rond de fermeture au bout de sa ligne : une feuille qui prolonge l'écran qu'elle recouvre. */
        Leading,

        /**
         * Centré. Pour les feuilles qui **ouvrent un choix** plutôt qu'elles ne
         * poursuivent l'écran du dessous — « Nouveau carnet » et ses trois portes.
         */
        Centered,
    }

    /** L'aplat de la feuille. */
    enum class Surface(internal val color: Color) {
        /** Le papier de la marque. Toutes les feuilles, sauf une. */
        Paper(MemoBookColor.surface),

        /**
         * Le bleu de l'écoute — la feuille d'enregistrement, et elle seule :
         * c'est ce changement d'aplat qui dit que l'app est passée en écoute.
         */
        Listening(MemoBookColor.listeningBackground),
    }
}

@Composable
private fun BrandSheetLayout(
    title: String,
    modifier: Modifier,
    @DrawableRes icon: Int?,
    badge: String?,
    paragraphs: List<String>,
    titleAlignment: BrandSheet.TitleAlignment,
    surface: BrandSheet.Surface,
    topOverflow: Dp,
    leading: (@Composable () -> Unit)?,
    content: @Composable ColumnScope.() -> Unit,
) {
    // Le niveau d'empilement de cette feuille, et le compteur partagé : ensemble,
    // ils disent qu'une autre feuille s'est ouverte par-dessus celle-ci.
    val depth = LocalBrandSheetDepth.current
    val presentation = LocalBrandSheetPresentation.current
    val isCoveredByAnotherSheet = (presentation?.count ?: 0) > depth + 1
    val reduceMotion = isReduceMotionEnabled()
    // Elle recule à son tour quand une autre s'ouvre par-dessus : le recul ne
    // s'arrête pas à l'app, il traverse la pile de feuilles.
    val coverScale by animateFloatAsState(
        targetValue = if (isCoveredByAnotherSheet) 0.94f else 1f,
        animationSpec = if (reduceMotion) snap() else SwiftUISpring.smooth(350),
        label = "recul",
    )
    val shape = brandSheetShape()
    val scroll = rememberScrollState()
    val overscroll = rememberOverscrollEffect()

    Column(
        modifier
            .fillMaxWidth()
            // Un contenu trop haut ne pousse pas la feuille jusqu'en haut : il
            // défile. C'est le cas des six connecteurs.
            .heightIn(max = brandSheetCeiling())
            .graphicsLayer {
                scaleX = coverScale
                scaleY = coverScale
                transformOrigin = TransformOrigin(0.5f, 0f)
            }
            // La réserve du haut : un espace transparent au-dessus de l'aplat.
            .padding(top = topOverflow)
            .brandShadow(MemoBookShadow.Raised, shape)
            .clip(shape)
            .background(surface.color)
            .semantics { paneTitle = title },
    ) {
        BrandSheetHandle()
        CompositionLocalProvider(
            // Une feuille présentée par celle-ci sera d'un cran plus profonde.
            LocalBrandSheetDepth provides depth + 1,
            // Les champs savent sur quoi ils sont posés : leur intitulé flottant
            // s'y découpe, et leur contour s'y voit dès le repos.
            LocalBrandFieldBackdrop provides surface.color,
        ) {
            Column(
                Modifier
                    .weight(1f, fill = false)
                    // Une feuille courte ne s'étire pas : le glissé lui appartient
                    // alors, et elle doit pouvoir se refermer.
                    .verticalScroll(scroll, overscrollEffect = if (scroll.maxValue > 0) overscroll else null)
                    .padding(horizontal = MemoBookSpacing.screenMargin)
                    // ⚠️ La barre du système compte déjà dans la marge du bas : on ne
                    // pose que ce qui **manque** pour atteindre la marge d'écran
                    // (58 pt de vide en bas de chaque feuille sur iOS, sinon).
                    .windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom))
                    .padding(bottom = (MemoBookSpacing.screenMargin - DeviceScreen.bottomSafeInset()).coerceAtLeast(0.dp)),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
            ) {
                SheetHeader(title, icon, badge, paragraphs, titleAlignment, leading)
                content()
            }
        }
    }
}

@Composable
private fun SheetHeader(
    title: String,
    @DrawableRes icon: Int?,
    badge: String?,
    paragraphs: List<String>,
    titleAlignment: BrandSheet.TitleAlignment,
    leading: (@Composable () -> Unit)?,
) {
    val accessible = isAccessibilityTextSize()
    val top = Modifier.padding(top = MemoBookSpacing.xs)
    when {
        titleAlignment == BrandSheet.TitleAlignment.Leading && leading != null && accessible ->
            Column(top, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                    leading()
                    Spacer(Modifier.weight(1f))
                    SheetCloseButton()
                }
                SheetTitleBlock(title, icon, badge, paragraphs, centered = false)
            }

        titleAlignment == BrandSheet.TitleAlignment.Leading && leading != null ->
            Row(
                top.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                leading()
                SheetTitleBlock(title, icon, badge, paragraphs, centered = false, modifier = Modifier.weight(1f))
                SheetCloseButton()
            }

        titleAlignment == BrandSheet.TitleAlignment.Leading ->
            Row(
                top.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
                verticalAlignment = Alignment.Top,
            ) {
                SheetTitleBlock(title, icon, badge, paragraphs, centered = false, modifier = Modifier.weight(1f))
                SheetCloseButton()
            }

        // En taille accessible, le rond prend sa propre ligne : le titre a besoin
        // de toute la largeur, sans quoi « Rejoindre » se coupait au milieu.
        accessible ->
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { SheetCloseButton() }
                SheetTitleBlock(title, icon, badge, paragraphs, centered = true)
            }

        // Le rond reste au coin, **posé par-dessus** et non dans la ligne : pris
        // dans une rangée, il déporterait le titre d'une demi-largeur de bouton.
        // C'est donc au titre de garder sa distance — la place d'un rond de
        // chaque côté. Le sous-titre, lui, garde toute la largeur.
        else ->
            Box(Modifier.fillMaxWidth()) {
                SheetTitleBlock(
                    title, icon, badge, paragraphs,
                    centered = true,
                    titleInset = MemoBookSpacing.minimumTapTarget,
                    modifier = Modifier.fillMaxWidth().padding(top = MemoBookSpacing.xs),
                )
                SheetCloseButton(Modifier.align(Alignment.TopEnd))
            }
    }
}

@Composable
private fun SheetTitleBlock(
    title: String,
    @DrawableRes icon: Int?,
    badge: String?,
    paragraphs: List<String>,
    centered: Boolean,
    modifier: Modifier = Modifier,
    titleInset: Dp = 0.dp,
) {
    val textAlign = if (centered) TextAlign.Center else TextAlign.Start
    Column(
        modifier,
        horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        if (icon != null) {
            Box(Modifier.fillMaxWidth().padding(bottom = MemoBookSpacing.xs), contentAlignment = Alignment.Center) {
                BrandIconBadge(icon)
            }
        }
        // **Un titre d'un seul mot se resserre au lieu de se couper** (T161,
        // iPhone SE en AX5 : « Statistiq / ues »). Plusieurs mots passent à la
        // ligne entre deux mots.
        val isOneWord = !title.contains(' ')
        BrandText(
            text = title,
            style = MemoBookFont.h1.copy(letterSpacing = (-0.41).sp),
            textAlign = textAlign,
            maxLines = if (isOneWord) 1 else Int.MAX_VALUE,
            minimumScaleFactor = if (isOneWord) 0.5f else 1f,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = titleInset)
                .semantics { heading() },
        )
        if (badge != null) {
            BrandTagPill(badge, tone = BrandTagPill.Tone.AccentOutlined, isUppercased = true)
        }
        paragraphs.forEach { paragraph ->
            BrandText(paragraph, MemoBookFont.body, color = MemoBookColor.inkMuted, textAlign = textAlign)
        }
    }
}

/**
 * Le rond de fermeture. La feuille se referme aussi au glissé, au retour et au
 * toucher hors d'elle — ce bouton existe pour la main qui ne glisse pas, et pour
 * TalkBack, qui a besoin d'une cible nommée. Il referme toujours, même quand le
 * glissé est retenu (`dismissDisabled`), comme le `dismiss()` d'iOS.
 */
@Composable
private fun SheetCloseButton(modifier: Modifier = Modifier) {
    val dismiss = LocalBrandSheetDismiss.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val pressAlpha by animateFloatAsState(if (pressed) 0.7f else 1f, tween(120), label = "press")
    Box(
        modifier
            .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = dismiss)
            .semantics { contentDescription = "Fermer" },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.icon_cross),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier
                .alpha(pressAlpha)
                // Le noir de la marque à 10 %, pas le crème du fond : sur une
                // feuille déjà claire, le crème ne se détache pas assez pour qu'on
                // voie qu'il y a là un bouton.
                .background(MemoBookColor.hairline, CircleShape)
                .padding(MemoBookSpacing.xs + 2.dp)
                .size(MemoBookSpacing.s + 4.dp),
        )
    }
}

/** La poignée : un trait de 40 sur 5 dans un bandeau de 21. La nôtre, pas celle du système. */
@Composable
internal fun BrandSheetHandle() {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(vertical = MemoBookSpacing.xs)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(width = 40.dp, height = 5.dp)
                .background(MemoBookColor.separator, RoundedCornerShape(percent = 50)),
        )
    }
}

/** Le rayon de 28 en haut ; en bas, celui de la dalle, que la feuille touche. */
@Composable
internal fun brandSheetShape(): Shape {
    val screen = DeviceScreen.cornerRadius()
    return RoundedCornerShape(
        topStart = MemoBookSpacing.sheetCornerRadius,
        topEnd = MemoBookSpacing.sheetCornerRadius,
        bottomStart = screen,
        bottomEnd = screen,
    )
}

/** La hauteur maximale d'une feuille : celle qui laisse voir, au-dessus, la bande d'app de [BrandSheetMetrics.appReveal]. */
@Composable
private fun brandSheetCeiling(): Dp =
    (DeviceScreen.height() - DeviceScreen.topSafeInset() - BrandSheetMetrics.recoilDrop - BrandSheetMetrics.appReveal)
        .coerceAtLeast(0.dp)

// MARK: - Présenter une feuille

/**
 * Présente une feuille pilotée par un booléen — pour une feuille qui n'a qu'un
 * seul état, comme l'ajout d'une carte. Jumeau de `.brandSheet(isPresented:)`.
 *
 * Une fenêtre `Dialog` plein écran : TalkBack y reste enfermé comme VoiceOver
 * dans une feuille, et le retour du système la referme. La feuille suit le
 * doigt — par sa poignée, ou par son contenu arrivé en haut de son défilement —
 * et se referme si le geste la mène au-delà de sa moitié. Le clavier la pousse
 * vers le haut.
 *
 * @param onDismissRequest la demande de fermeture : glissé, retour, toucher
 *   hors de la feuille, rond de fermeture. L'écran remet son état à `false` ;
 *   c'est à cet instant que la feuille descend et que l'app regrandit.
 * @param dismissDisabled le `interactiveDismissDisabled` d'iOS : le temps d'un
 *   appel, la feuille ne se referme ni au glissé, ni au retour, ni au toucher
 *   hors d'elle. Le rond de fermeture, lui, referme toujours.
 */
@Composable
fun BrandSheetHost(
    isPresented: Boolean,
    onDismissRequest: () -> Unit,
    dismissDisabled: Boolean = false,
    content: @Composable () -> Unit,
) {
    SheetPresentation(isPresented, onDismissRequest, dismissDisabled, reportsToCounter = true, content = content)
}

/**
 * Présente une feuille pilotée par une valeur optionnelle — jumeau de
 * `.brandSheet(item:)`, **à employer partout** pour une feuille qui montre
 * quelque chose : la valeur est déjà `null` quand la fermeture commence, et la
 * feuille qui descend garde ce qu'elle montrait au lieu de se vider en route.
 */
@Composable
fun <T : Any> BrandSheetHost(
    item: T?,
    onDismissRequest: () -> Unit,
    dismissDisabled: Boolean = false,
    content: @Composable (T) -> Unit,
) {
    val retained = remember { RetainedItem<T>() }
    if (item != null) retained.value = item
    SheetPresentation(item != null, onDismissRequest, dismissDisabled, reportsToCounter = true) {
        retained.value?.let { content(it) }
    }
}

private class RetainedItem<T : Any> {
    var value: T? = null
}

/**
 * La présentation elle-même. [reportsToCounter] à `false` pour un accessoire
 * qui ne doit pas faire reculer ce qu'il recouvre — le calendrier de
 * [BrandDateField], la « feuille du système » d'iOS.
 */
@Composable
internal fun SheetPresentation(
    isPresented: Boolean,
    onDismissRequest: () -> Unit,
    dismissDisabled: Boolean,
    reportsToCounter: Boolean,
    content: @Composable () -> Unit,
) {
    // Le compteur bascule **quand la valeur change**, c'est-à-dire quand la
    // fermeture commence : l'app regrandit pendant que la feuille descend, d'un
    // même mouvement. Branché sur la fin de l'animation, il ne basculait
    // qu'après coup, d'un coup sec. Quitter l'écran feuille ouverte la retire
    // aussi du compte : l'app ne reste jamais reculée pour rien.
    val presentation = LocalBrandSheetPresentation.current
    DisposableEffect(presentation, isPresented, reportsToCounter) {
        val counts = isPresented && reportsToCounter
        if (counts) presentation?.open()
        onDispose { if (counts) presentation?.close() }
    }

    // 1 : sous le bas de l'écran ; 0 : posée.
    val presence = remember { Animatable(1f) }
    var isShowing by remember { mutableStateOf(false) }
    LaunchedEffect(isPresented) {
        if (isPresented) {
            isShowing = true
            presence.animateTo(0f, SwiftUISpring.smooth(SHEET_MOTION_MS))
        } else if (isShowing) {
            presence.animateTo(1f, SwiftUISpring.smooth(SHEET_MOTION_MS))
            isShowing = false
        }
    }
    if (!isShowing) return

    val requestDismiss by rememberUpdatedState(onDismissRequest)
    val isDismissible by rememberUpdatedState(!dismissDisabled)
    val stillPresented by rememberUpdatedState(isPresented)

    Dialog(
        // Le retour du système.
        onDismissRequest = { if (isDismissible) requestDismiss() },
        properties = DialogProperties(
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        SheetWindowStyle()
        val scope = rememberCoroutineScope()
        val drag = remember(scope) {
            SheetDrag(scope, canDismiss = { isDismissible }, isStillPresented = { stillPresented }, requestDismiss = { requestDismiss() })
        }
        val dismissAction = remember { { requestDismiss() } }
        val dragState = rememberDraggableState { delta -> drag.dragBy(delta) }
        // Lu ici, dans la composition, pour que l'action de TalkBack suive l'écran.
        val offersDismissAction = isDismissible

        Box(Modifier.fillMaxSize()) {
            // Le voile : il s'éteint avec la feuille qui part, et à mesure qu'on
            // la tire vers le bas.
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { alpha = (1f - presence.value) * (1f - drag.pulledFraction) }
                    .background(SCRIM)
                    .pointerInput(Unit) { detectTapGestures { if (isDismissible) requestDismiss() } }
                    .clearAndSetSemantics {},
            )
            BoxWithConstraints(
                Modifier
                    .fillMaxSize()
                    // Le clavier pousse la feuille vers le haut, comme sur iOS.
                    .windowInsetsPadding(WindowInsets.ime),
                contentAlignment = Alignment.BottomCenter,
            ) {
                // Même avec le clavier, la feuille ne monte pas au-dessus de la
                // bande d'app qui doit rester visible.
                val ceiling = (maxHeight - DeviceScreen.topSafeInset() - BrandSheetMetrics.recoilDrop - BrandSheetMetrics.appReveal)
                    .coerceAtLeast(0.dp)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(max = ceiling)
                        .onSizeChanged { drag.height = it.height }
                        .graphicsLayer { translationY = presence.value * size.height + drag.offset }
                        .nestedScroll(drag)
                        .draggable(
                            state = dragState,
                            orientation = Orientation.Vertical,
                            onDragStarted = { drag.cancelSettle() },
                            onDragStopped = { velocity -> drag.release(velocity) },
                        )
                        .semantics {
                            if (offersDismissAction) {
                                dismiss(label = "Fermer") {
                                    requestDismiss()
                                    true
                                }
                            }
                        },
                ) {
                    CompositionLocalProvider(LocalBrandSheetDismiss provides dismissAction, content = content)
                }
            }
        }
    }
}

/**
 * Le doigt sur la feuille : ce dont elle est descendue, et ce qu'elle fait au
 * relâché. Il reçoit aussi ce que le défilement du contenu n'a pas pris — un
 * contenu arrivé en haut passe la main à la feuille, comme sur iOS.
 */
@Stable
private class SheetDrag(
    private val scope: CoroutineScope,
    private val canDismiss: () -> Boolean,
    private val isStillPresented: () -> Boolean,
    private val requestDismiss: () -> Unit,
) : NestedScrollConnection {
    var offset by mutableFloatStateOf(0f)
        private set
    var height by mutableIntStateOf(0)
    private var settling: Job? = null

    /** De 0 à 1, ce que la feuille a été tirée vers le bas : le voile s'éteint d'autant. */
    val pulledFraction: Float get() = if (height > 0) (offset / height).coerceIn(0f, 1f) else 0f

    fun cancelSettle() {
        settling?.cancel()
    }

    fun dragBy(delta: Float) {
        cancelSettle()
        // Une feuille qui ne se referme pas résiste au doigt, puis revient.
        val resisted = if (!canDismiss() && delta > 0f) delta * DISABLED_RESISTANCE else delta
        offset = (offset + resisted).coerceAtLeast(0f)
    }

    fun release(velocity: Float) {
        cancelSettle()
        settling = scope.launch {
            // Où le geste mènerait la feuille s'il continuait sur sa lancée.
            val projected = offset + velocity * FLING_PROJECTION_SECONDS
            if (canDismiss() && height > 0 && projected > height / 2f) {
                requestDismiss()
                // L'écran peut refuser la fermeture : la feuille remonte alors.
                withFrameNanos {}
                withFrameNanos {}
                if (!isStillPresented()) return@launch
            }
            animate(offset, 0f, velocity, SwiftUISpring.smooth(SHEET_MOTION_MS)) { value, _ -> offset = value }
        }
    }

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        // La feuille tirée vers le bas remonte d'abord, avant que le contenu défile.
        if (source != NestedScrollSource.UserInput || available.y >= 0f || offset <= 0f) return Offset.Zero
        cancelSettle()
        val consumed = maxOf(available.y, -offset)
        offset += consumed
        return Offset(0f, consumed)
    }

    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
        if (source != NestedScrollSource.UserInput || available.y <= 0f) return Offset.Zero
        dragBy(available.y)
        return Offset(0f, available.y)
    }

    override suspend fun onPreFling(available: Velocity): Velocity {
        if (offset <= 0f) return Velocity.Zero
        release(available.y)
        return available
    }
}

/**
 * La fenêtre du `Dialog` : pas de voile du système (le nôtre s'anime avec la
 * feuille), pas de bande de contraste sous la barre de navigation, et des
 * icônes sombres sur le papier — l'app ne se retourne pas en sombre.
 */
@Composable
private fun SheetWindowStyle() {
    val view = LocalView.current
    DisposableEffect(view) {
        (view.parent as? DialogWindowProvider)?.window?.let { window ->
            window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isNavigationBarContrastEnforced = false
            useDarkSystemBarIcons(window)
        }
        onDispose {}
    }
}

private fun useDarkSystemBarIcons(window: Window) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
        window.insetsController?.setSystemBarsAppearance(light, light)
    } else {
        useDarkSystemBarIconsLegacy(window)
    }
}

// Avant Android 11, seul `systemUiVisibility` le dit — déprécié depuis.
@Suppress("DEPRECATION")
private fun useDarkSystemBarIconsLegacy(window: Window) {
    val decor = window.decorView
    decor.systemUiVisibility = decor.systemUiVisibility or
        View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
        View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
}

/** Le voile du système sous une feuille iOS : le noir à 40 %. */
private val SCRIM = Color.Black.copy(alpha = 0.4f)

/** Le ressort de la feuille qui monte et qui descend : celui d'iOS, approché. */
private const val SHEET_MOTION_MS = 400

/** La part du mouvement du doigt que suit une feuille qui ne se referme pas. */
private const val DISABLED_RESISTANCE = 0.3f

/** L'élan d'un glissé, projeté sur ce temps-là pour décider s'il referme. */
private const val FLING_PROJECTION_SECONDS = 0.2f

// MARK: - Le recul de l'écran du dessous

/**
 * Combien de feuilles de marque sont ouvertes, en ce moment, dans l'app.
 *
 * L'information remonte — de la feuille vers l'écran qui la présente —, donc
 * elle passe par un objet partagé plutôt que par une valeur descendue. C'est ce
 * qui rend le recul **automatique** : tout [BrandSheetHost] s'y annonce, aucun
 * écran n'a à y penser. `RootView` en tient un et le pose dans
 * [LocalBrandSheetPresentation].
 */
@Stable
class BrandSheetPresentation {
    var count by mutableIntStateOf(0)
        private set

    val isPresenting: Boolean get() = count > 0

    internal fun open() {
        count += 1
    }

    internal fun close() {
        count = maxOf(0, count - 1)
    }
}

/** Le compteur de feuilles ouvertes. `null` dans un aperçu isolé, où personne ne recule. */
val LocalBrandSheetPresentation = staticCompositionLocalOf<BrandSheetPresentation?> { null }

/** Le niveau d'empilement des feuilles à cet endroit de l'arbre. */
val LocalBrandSheetDepth = compositionLocalOf { 0 }

/**
 * Le `dismiss` de l'environnement SwiftUI : referme la feuille où l'on est.
 * [BrandSheetHost] le pose ; hors d'une feuille, il ne fait rien.
 */
val LocalBrandSheetDismiss = staticCompositionLocalOf<() -> Unit> { {} }

/**
 * Les mesures que la feuille et l'écran qui recule partagent : une feuille ne
 * décide de sa hauteur maximale qu'en sachant où le haut de la carte de l'app
 * est allé se poser. Séparées, elles dérivaient.
 */
internal object BrandSheetMetrics {
    /** Le rapport de réduction d'iOS : la carte perd de chaque côté à peu près la marge d'écran. */
    const val RECOIL_SCALE = 0.92f

    /** Ce dont la carte redescend, pour que son haut se pose sous la barre d'état. */
    val recoilDrop: Dp = 12.dp

    /**
     * Ce qu'on voit de la carte de l'app **au-dessus** de toute feuille. Une
     * feuille qui monte jusqu'en haut n'est plus une feuille, c'est un écran —
     * et personne ne pense à la faire glisser vers le bas. La bande se compte
     * depuis la carte, pas depuis le bord de la dalle.
     */
    val appReveal: Dp = 44.dp
}

/**
 * L'écran recule pendant qu'une feuille est ouverte : il rapetisse, ses coins
 * prennent ceux du téléphone, et du noir apparaît tout autour — le geste des
 * Réglages d'iOS. Jumeau de `brandSheetPresenter(isPresented:)`.
 *
 * **À poser tout en haut**, sur la vue qui occupe vraiment l'écran entier :
 * `RootView`, avec `isPresented = sheets.isPresenting`.
 */
@Composable
fun BrandSheetPresenter(isPresented: Boolean, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val reduceMotion = isReduceMotionEnabled()
    // **Deux courbes, pas une.** Le recul s'installe posément derrière la
    // feuille qui monte, et se relâche plus vite qu'elle ne descend : la carte a
    // retrouvé sa taille avant que la feuille ait fini de partir.
    val recoil by animateFloatAsState(
        targetValue = if (isPresented) 1f else 0f,
        animationSpec = if (reduceMotion) snap() else SwiftUISpring.smooth(if (isPresented) 350 else 200),
        label = "recul",
    )
    val screenRadius = DeviceScreen.cornerRadius()
    Box(
        modifier
            // Sous le noir, le crème de l'app — jamais la fenêtre : un liseré de
            // la couleur du fond ne se voit pas.
            .background(MemoBookColor.background)
            // ⚠️ Le noir s'efface avec le recul : posé en dur, il restait derrière
            // la carte qui regrandissait, en deux bandes noires.
            .drawBehind { drawRect(Color.Black.copy(alpha = recoil)) },
        propagateMinConstraints = true,
    ) {
        Box(
            Modifier
                .graphicsLayer {
                    val scale = lerp(1f, BrandSheetMetrics.RECOIL_SCALE, recoil)
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = TransformOrigin(0.5f, 0f)
                    translationY = BrandSheetMetrics.recoilDrop.toPx() * recoil
                    // Le rognage se fait **avant** la réduction : ses coins sont
                    // ceux de l'écran, ramenés avec la carte.
                    shape = RoundedCornerShape(screenRadius * recoil)
                    clip = recoil > 0f
                }
                .background(MemoBookColor.background),
            propagateMinConstraints = true,
        ) {
            content()
        }
    }
}

// MARK: - Les ressorts de SwiftUI

/**
 * Les ressorts nommés de SwiftUI, pour que les durées se recopient telles
 * quelles. `.smooth(duration:)` et `.snappy(duration:)` sont des ressorts à
 * durée perçue : raideur (2π / durée)², amortissement 1 pour `smooth`, 0,85
 * pour `snappy` (son rebond de 0,15, plus `extraBounce`).
 */
internal object SwiftUISpring {
    fun <T> smooth(durationMillis: Int): SpringSpec<T> =
        spring(dampingRatio = 1f, stiffness = stiffness(durationMillis))

    fun <T> snappy(durationMillis: Int, extraBounce: Float = 0f): SpringSpec<T> =
        spring(dampingRatio = 1f - (0.15f + extraBounce), stiffness = stiffness(durationMillis))

    private fun stiffness(durationMillis: Int): Float {
        val omega = 2f * PI.toFloat() / (durationMillis / 1000f)
        return omega * omega
    }
}

// MARK: - Aperçus

@Preview(name = "Feuille, titre à gauche", widthDp = 390, heightDp = 520)
@Composable
private fun BrandSheetLeadingPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        BrandSheet("Adresse postale", subtitle = "Ajoute l’adresse où tu souhaites recevoir ton carnet.") {
            BrandButton("Enregistrer", fillsWidth = true) {}
        }
    }
}

@Preview(name = "Feuille centrée, icône et pastille", widthDp = 390, heightDp = 620)
@Composable
private fun BrandSheetCenteredPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        BrandSheet(
            "Mot de passe oublié",
            paragraphs = listOf("Indique ton adresse e-mail.", "On t’envoie un lien pour le changer."),
            icon = R.drawable.icon_locker,
            badge = "Abonnée",
            titleAlignment = BrandSheet.TitleAlignment.Centered,
        ) {
            BrandButton("Envoyer le lien", fillsWidth = true) {}
        }
    }
}

@Preview(name = "Feuille, illustration devant le titre", widthDp = 390, heightDp = 420)
@Composable
private fun BrandSheetLeadingArtworkPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        BrandSheet("Un mot des fondateurs", leading = { BrandIconBadge(R.drawable.icon_bubble) }) {
            BrandText("Merci d’être là.", MemoBookFont.body)
        }
    }
}

@Preview(name = "Feuille d’écoute", widthDp = 390, heightDp = 420)
@Composable
private fun BrandSheetListeningPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        BrandSheet("Je t’écoute", surface = BrandSheet.Surface.Listening) {
            BrandText("Raconte-moi ta journée.", MemoBookFont.body, color = MemoBookColor.inkMuted)
        }
    }
}
