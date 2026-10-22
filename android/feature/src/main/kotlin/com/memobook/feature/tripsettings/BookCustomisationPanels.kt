package com.memobook.feature.tripsettings

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitHorizontalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.BookFontCombo
import com.memobook.core.BookFontRole
import com.memobook.core.BookPageTarget
import com.memobook.design.BrandButton
import com.memobook.design.BrandComingSoon
import com.memobook.design.BrandImages
import com.memobook.design.BrandNotice
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandSlider
import com.memobook.design.BrandText
import com.memobook.design.BrandToggleCard
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.SwiftMotion
import com.memobook.design.brandShadow
import com.memobook.design.scaled
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// Les cinq réglages de la personnalisation du carnet, un par pastille — ce qui
// défile sous les deux pages (V3 de la maquette, 29/09/2026). Jumeau de
// `TripSettings/BookCustomisationPanels.swift`.
//
// **Le réglage part au geste.** Il n'y a plus de bouton « Valider » : les
// feuilles en avaient un qui ne faisait que fermer, et il n'y a plus rien à
// fermer. C'est le contrat des réglages partout dans l'app.
//
// Chaque panneau s'ouvre sur sa phrase d'explication — le gris de la maquette —
// puis sur son contrôle. Les quatre qui proposent des choix les posent dans une
// carte papier (`3595:23854`).
//
// Le `.disabled(model.customisation == nil)` d'iOS est ici `blocksTouches` : le
// doigt s'arrête au panneau tant que les valeurs ne sont pas lues.

// MARK: - Ratio média

/** « Ratio media » — la part de photo dans la page, de 0 à 100 % (`3595:23823`). */
@Composable
internal fun BookRatioPanel(model: BookCustomisationModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val ratio = state.customisation?.photoTextRatio ?: 50

    Column(Modifier.blocksTouches(state.customisation == null), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        BookPanelLead(BookCopy.Ratio.subtitle)

        // « 50 / 50 », et ce que l'équilibre vaut. C'est **ici** qu'on lit ce
        // qu'on règle : le curseur ne fait que le poser.
        Column(
            Modifier.fillMaxWidth().clearAndSetSemantics {},
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs - 2.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Sora à 24 (`3595:23828`). Les chiffres ne dansent pas : sans
            // chasse fixe, la valeur se décale à chaque cran du curseur.
            BrandText(BookCopy.Ratio.value(ratio), MemoBookFont.figure.copy(fontFeatureSettings = "tnum"))

            // **À l'encre**, comme la valeur au-dessus (Hugo, 06/10/2026, T218) :
            // le bleu clair `outline` de la maquette ne se lisait pas sur le crème.
            AnimatedContent(
                BookCopy.Ratio.quality(ratio),
                transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(200)) },
                label = "qualité du ratio",
            ) { quality ->
                BrandText(quality, MemoBookFont.tagline)
            }
        }

        BrandSlider(
            value = ratio,
            onValueChange = model::setPhotoTextRatio,
            bounds = 0..100,
            step = 25,
            ticks = listOf("0%", "25%", "50%", "75%", "100%"),
            voiceLabel = BookCopy.Ratio.title,
            leadingLabel = BookCopy.Ratio.less,
            trailingLabel = BookCopy.Ratio.more,
            voiceValue = { "$it % de photos, ${100 - it} % de texte" },
        )
    }
}

// MARK: - Nombre de pages

/**
 * « Nombre de pages » — quatre paliers, dont les projections suivent la durée
 * du voyage (`3595:23917`).
 *
 * **Deux changements par voyage, une fois une étape écrite** (Hugo,
 * 15/10/2026). Avant, le palier part au geste ; ensuite, le geste ouvre
 * [PageTargetChangeSheet] et rien ne bouge avant qu'on confirme. Les deux
 * changements faits, les paliers pâlissent sans se désactiver : l'appui pose la
 * note orange qui dit pourquoi.
 */
@Composable
internal fun BookPagesPanel(model: BookCustomisationModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    // Le nombre saisi à la main, quand on choisit « Personnalisé ».
    var customPages by rememberSaveable { mutableIntStateOf(60) }
    var isCustomising by rememberSaveable { mutableStateOf(false) }

    val days = state.tripDays
    // Les paliers suivent aussi le ratio (18/10/2026).
    val ratio = state.customisation?.photoTextRatio ?: 50
    val pages = state.customisation?.targetPageCount
    val selection = when {
        pages == null -> BookPageTarget.Standard
        isCustomising -> BookPageTarget.Custom
        else -> BookPageTarget.matching(pageCount = pages, tripDays = days, ratio = ratio)
    }

    fun resyncCustomPages() {
        model.customisation?.targetPageCount?.let { customPages = it }
    }

    /**
     * Demande la cible au modèle. Rien n'a bougé et aucune feuille ne s'est
     * ouverte — la cible verrouillée — : le curseur revient où il était.
     */
    fun request(pages: Int) {
        model.setTargetPageCount(pages)
        if (model.pageTargetChange == null) resyncCustomPages()
    }

    fun choose(target: BookPageTarget) {
        // La cible ne bouge plus : pas même le curseur ne s'ouvre.
        if (model.isPageTargetLocked) {
            model.explainPageTargetLimit()
            return
        }
        isCustomising = target == BookPageTarget.Custom
        // « Personnalisé » n'a pas de valeur à lui : on garde celle qui est déjà
        // posée et on ouvre le curseur dessous.
        val projected = target.pageCount(days, ratio) ?: return
        customPages = projected
        request(projected)
    }

    // L'ouverture du panneau : le curseur part de la cible posée, ouvert si
    // elle ne tombe sur aucun palier. Une fois les valeurs lues, et une seule.
    var hasSynced by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(pages != null) {
        if (pages == null || hasSynced) return@LaunchedEffect
        hasSynced = true
        customPages = pages
        isCustomising = BookPageTarget.matching(pageCount = pages, tripDays = days, ratio = ratio) == BookPageTarget.Custom
    }
    // La feuille refermée sans changement — « Annuler », ou un refus — : le
    // curseur revient sur la cible qui tient toujours.
    val isChangeClosed = state.pageTargetChange == null
    val isReachClosed = state.pageTargetReach == null
    var wasChangeClosed by remember { mutableStateOf(isChangeClosed) }
    var wasReachClosed by remember { mutableStateOf(isReachClosed) }
    LaunchedEffect(isChangeClosed, isReachClosed) {
        if (isChangeClosed && !wasChangeClosed) resyncCustomPages()
        if (isReachClosed && !wasReachClosed && isChangeClosed) resyncCustomPages()
        wasChangeClosed = isChangeClosed
        wasReachClosed = isReachClosed
    }

    Column(
        Modifier
            .blocksTouches(state.customisation == null)
            .animateContentSize(SwiftMotion.snappy(0.25f)),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BookPanelLead(BookCopy.Pages.subtitle)

            // La ligne verte de la maquette : elle dit **sur quoi** les trois
            // projections sont faites. Le nœud écrit « 2 mois » en dur ; ici
            // c'est la durée du voyage qu'on regarde — c'est la note « Logique »
            // du nœud (`3443:10070`).
            bookTripDuration(days)?.let { duration ->
                BrandText(BookCopy.Pages.estimates(duration), MemoBookFont.label, color = MemoBookColor.action)
            }
        }

        // Pâlie, pas désactivée : chaque ligne garde son geste, et c'est le
        // modèle qui répond par la note orange.
        BookPanelCard(Modifier.alpha(if (state.isPageTargetLocked) 0.45f else 1f)) {
            BookPageTarget.entries.forEach { target ->
                BrandOptionRow(
                    target.label(days, ratio),
                    isSelected = selection == target,
                    subtitle = target.detail,
                ) {
                    choose(target)
                }
            }

            AnimatedVisibility(
                isCustomising,
                enter = fadeIn() + expandVertically(expandFrom = Alignment.Top),
                exit = fadeOut() + shrinkVertically(shrinkTowards = Alignment.Top),
            ) {
                CustomPageStepper(
                    pages = customPages,
                    onPagesChange = { customPages = it },
                    onEditingEnded = {
                        // Un nombre posé à la main : hors d'atteinte, la feuille
                        // le dit avant que rien ne change (18/10/2026).
                        model.requestCustomTarget(customPages)
                        if (model.pageTargetChange == null && model.pageTargetReach == null) resyncCustomPages()
                    },
                )
            }
        }

        AnimatedVisibility(state.showsPageTargetLimitNotice, enter = fadeIn(), exit = fadeOut()) {
            BrandNotice(BookCopy.Pages.limitReached, Modifier.revealedWhenShown(state.showsPageTargetLimitNotice), tone = BrandNotice.Tone.Warning)
        }

        // La réécriture laissée « Plus tard » : un lien sous les paliers, tant
        // que le serveur la garde ouverte. Une fois partie, une phrase la
        // remplace.
        AnimatedVisibility(state.hasStartedRewrite, enter = fadeIn(), exit = fadeOut()) {
            BrandNotice(BookCopy.Pages.rewriteStarted)
        }
        AnimatedVisibility(!state.hasStartedRewrite && state.offersRewrite, enter = fadeIn(), exit = fadeOut()) {
            BrandButton(
                BookCopy.Pages.rewriteLink,
                Modifier.padding(horizontal = MemoBookSpacing.xs),
                style = BrandButton.Style.Link,
                isLoading = state.isRewritingWrittenSteps,
            ) {
                scope.launch { model.rewriteWrittenSteps() }
            }
        }
    }
}

/** « 2 mois », « 12 jours » — la durée du voyage, écrite comme on la dit. */
private fun bookTripDuration(days: Int?): String? {
    days ?: return null
    if (days >= 60) return "${days / 30} mois"
    if (days >= 14) return "${days / 7} semaines"
    return if (days == 1) "1 jour" else "$days jours"
}

/**
 * Le nombre exact, quand aucun palier ne convient. Un pas de dix : un carnet se
 * relie par cahiers, et « 63 pages » ne veut rien dire de plus que « 60 ».
 */
@Composable
private fun CustomPageStepper(pages: Int, onPagesChange: (Int) -> Unit, onEditingEnded: () -> Unit) {
    Column(Modifier.padding(horizontal = MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BrandText(BookCopy.Pages.customTitle, MemoBookFont.tagline, color = MemoBookColor.inkMuted)
            Spacer(Modifier.weight(1f).width(MemoBookSpacing.xs))
            BrandText("$pages", MemoBookFont.figure.copy(fontFeatureSettings = "tnum"))
        }

        CustomPagesSlider(pages, onPagesChange, onEditingEnded)
    }
}

/**
 * Le curseur du nombre personnalisé : le `Slider` du système d'iOS, teinté de
 * l'action. Compose Foundation n'en a pas, et celui de Material est hors de
 * l'app : il est redessiné ici, au plus près du curseur d'iOS — un rail fin, la
 * part choisie à l'encre verte, une poignée de papier. Il ne rend la main
 * qu'au doigt levé ([onEditingEnded]), comme `onEditingChanged`.
 */
@Composable
private fun CustomPagesSlider(pages: Int, onPagesChange: (Int) -> Unit, onEditingEnded: () -> Unit) {
    val bounds = 30..180
    val stride = 10
    val currentPages by rememberUpdatedState(pages)
    val onChange by rememberUpdatedState(onPagesChange)
    val onEnded by rememberUpdatedState(onEditingEnded)
    val thumb = 28.dp
    var trackWidth by remember { mutableIntStateOf(0) }
    val fraction = (pages - bounds.first).toFloat() / (bounds.last - bounds.first)

    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .onSizeChanged { trackWidth = it.width }
            .semantics {
                contentDescription = BookCopy.Pages.customTitle
                stateDescription = "$pages pages"
                progressBarRangeInfo = ProgressBarRangeInfo(
                    pages.toFloat(),
                    bounds.first.toFloat()..bounds.last.toFloat(),
                    steps = (bounds.last - bounds.first) / stride - 1,
                )
                setProgress { target ->
                    val next = when {
                        target > pages -> minOf(bounds.last, pages + stride)
                        target < pages -> maxOf(bounds.first, pages - stride)
                        else -> pages
                    }
                    if (next != pages) {
                        onPagesChange(next)
                        onEditingEnded()
                    }
                    next != pages
                }
            }
            .pointerInput(Unit) {
                val side = thumb.toPx()
                fun follow(x: Float) {
                    val travel = size.width - side
                    if (travel <= 0f) return
                    val raw = ((x - side / 2) / travel).coerceIn(0f, 1f)
                    val steps = (raw * (bounds.last - bounds.first) / stride).roundToInt()
                    val next = bounds.first + steps * stride
                    if (next != currentPages) onChange(next)
                }
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    follow(down.position.x)
                    val drag = awaitHorizontalTouchSlopOrCancellation(down.id) { change, _ -> change.consume() }
                    if (drag != null) {
                        follow(drag.position.x)
                        horizontalDrag(drag.id) { change ->
                            follow(change.position.x)
                            change.consume()
                        }
                    }
                    onEnded()
                }
            }
            .drawBehind {
                val track = 4.dp.toPx()
                val top = (size.height - track) / 2
                val capsule = CornerRadius(track / 2)
                val side = thumb.toPx()
                val center = side / 2 + maxOf(0f, size.width - side) * fraction
                drawRoundRect(MemoBookColor.hairline, Offset(0f, top), Size(size.width, track), capsule)
                drawRoundRect(MemoBookColor.action, Offset(0f, top), Size(center, track), capsule)
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            Modifier
                .offset {
                    val travel = maxOf(0, trackWidth - thumb.roundToPx())
                    IntOffset((travel * fraction).roundToInt(), 0)
                }
                .size(thumb)
                .brandShadow(MemoBookShadow.Raised, CircleShape)
                .background(MemoBookColor.surface, CircleShape),
        )
    }
}

// MARK: - Décorations & stickers

/** « Décorations & stickers » — de zéro à quatre stickers par étape (`3595:23965`). */
@Composable
internal fun BookDecorationsPanel(model: BookCustomisationModel) {
    val state by model.state.collectAsStateWithLifecycle()

    Column(Modifier.blocksTouches(state.customisation == null), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        BookPanelLead(BookCopy.Decorations.subtitle)

        BrandSlider(
            value = state.customisation?.decorationQuota ?: 0,
            onValueChange = model::setDecorationQuota,
            bounds = 0..4,
            step = 1,
            ticks = listOf("0", "1", "2", "3", "4"),
            voiceLabel = BookCopy.Decorations.sliderLabel,
            leadingLabel = BookCopy.Decorations.sliderLabel,
            voiceValue = { if (it == 0) "Aucune" else "$it par étape" },
        )
    }
}

// MARK: - Typographies

/**
 * « Typos » — trois assortiments, un seul choisi (`3595:24006`).
 *
 * **On ne compose plus police par police** (Hugo, 16/09/2026) : la plupart des
 * mariages sont laids, et un carnet imprimé ne se rattrape pas. Chaque
 * assortiment s'écrit **dans ses polices** — « Playfair - Hansley - Gloria
 * Hallelujah », chaque nom dessiné dans sa famille —, c'est ce que la maquette
 * montre, et la seule façon de choisir sans connaître la typographie.
 */
@Composable
internal fun BookFontsPanel(model: BookCustomisationModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val customisation = state.customisation

    Column(Modifier.blocksTouches(customisation == null), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BookPanelLead(BookCopy.Fonts.subtitle)

        BookPanelCard {
            BookFontCombo.all.forEach { combo ->
                // Éditorial et Manuscrit ne s'impriment pas encore : la ligne
                // reste, pâlie, sous la pastille des connecteurs, et ne prend pas
                // le geste (`isAvailable`).
                BrandComingSoon(isComingSoon = !combo.isAvailable) {
                    BookFontComboRow(
                        combo,
                        isSelected = customisation?.let(combo::matches) ?: false,
                        isEnabled = combo.isAvailable,
                    ) {
                        model.setFontCombo(combo)
                    }
                }
            }
        }

        // L'interrupteur des pointillés est dans une autre pastille : c'est ici,
        // au geste, qu'on apprend qu'ils viennent de s'éteindre. TalkBack le dit
        // en le voyant paraître — sans quoi il resterait sur la ligne touchée, et
        // la note qui dit ce qu'on vient de perdre serait plus bas, à balayer.
        val withdrawnBy = state.rulesWithdrawnBy
        // La note qui s'efface garde son assortiment, au lieu de se vider en route.
        val retained = remember { arrayOfNulls<BookFontCombo>(1) }
        if (withdrawnBy != null) retained[0] = withdrawnBy
        AnimatedVisibility(withdrawnBy != null, enter = fadeIn(), exit = fadeOut()) {
            val combo = retained[0] ?: return@AnimatedVisibility
            BrandNotice(
                BookCopy.Rules.withdrawn(by = combo),
                Modifier
                    .revealedWhenShown(withdrawnBy != null, key = combo)
                    .semantics { liveRegion = LiveRegionMode.Polite },
                tone = BrandNotice.Tone.Information,
            )
        }
    }
}

/**
 * Un assortiment : ses polices, écrites chacune dans sa police, sa phrase, et
 * le rond de sélection de [BrandOptionRow] — même aplat bleu quand c'est
 * coché, pour que le geste soit le même.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BookFontComboRow(combo: BookFontCombo, isSelected: Boolean, isEnabled: Boolean, action: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    val markSide = scaled(22.dp)
    // La hauteur des noms dessinés : celle d'une ligne de `MemoBookFont.bodySemibold`,
    // avec laquelle ils suivent la taille de police.
    val wordmarkHeight = scaled(15.dp)

    // Les familles de l'assortiment, **sans doublon et dans l'ordre des rôles** :
    // « Playfair - Hansley - Gloria Hallelujah » pour le carnet de voyage,
    // « Hansley - Gloria Hallelujah » pour le manuscrit.
    val families = remember(combo) { BookFontRole.entries.distinctBy { combo.font(it) } }
    val accessibilityLabel = "${families.joinToString(", ") { combo.fontLabel(it) }}. ${combo.detail}"

    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .selectable(
                selected = isSelected,
                enabled = isEnabled,
                role = Role.RadioButton,
                interactionSource = null,
                indication = PlainButtonIndication,
                onClick = action,
            )
            // Une seule annonce : les noms, la phrase — et l'état coché, que
            // `selectable` pose déjà.
            .clearAndSetSemantics { contentDescription = accessibilityLabel }
            .background(if (isSelected) MemoBookColor.outline.copy(alpha = 0.35f) else androidx.compose.ui.graphics.Color.Transparent, shape)
            .border(1.dp, if (isSelected) MemoBookColor.outline else MemoBookColor.hairline, shape)
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.s - 2.dp),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // Une grille qui passe à la ligne : trois noms ne tiennent pas
            // toujours sur une ligne. Centrés sur la ligne : un nom dessiné et un
            // tiret écrit n'ont pas la même hauteur.
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                families.forEachIndexed { index, role ->
                    if (index > 0) BrandText("-", MemoBookFont.bodySemibold)
                    val wordmark = combo.fontWordmark(role)?.let { BrandImages[it] }
                    if (wordmark != null) {
                        Image(
                            painterResource(wordmark),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(MemoBookColor.ink),
                            modifier = Modifier.height(wordmarkHeight),
                        )
                    } else {
                        BrandText(combo.fontLabel(role), MemoBookFont.bodySemibold)
                    }
                }
            }
            BrandText(combo.detail, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }

        // Le rond de sélection.
        Box(
            Modifier
                .size(markSide)
                .border(1.5.dp, if (isSelected) MemoBookColor.blueText else MemoBookColor.separator, CircleShape)
                .padding(5.dp)
                .then(if (isSelected) Modifier.background(MemoBookColor.blueText, CircleShape) else Modifier),
        )
    }
}

// MARK: - Extras

/**
 * « Extras » — cinq interrupteurs (`3595:24049`) : les pointillés et les fun
 * facts, qui étaient deux lignes à feuille, rejoignent le quiz, les zones
 * libres et le mot fléché.
 */
@Composable
internal fun BookExtrasPanel(model: BookCustomisationModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val customisation = state.customisation

    // Les interrupteurs **agissent** : les basculer avant que les valeurs soient
    // là enverrait un état qu'on n'a pas lu.
    BookPanelCard(Modifier.blocksTouches(customisation == null).animateContentSize(SwiftMotion.snappy(0.25f))) {
        // Verrouillés par *Manuscrit* ou *Éditorial* : l'interrupteur pâlit, et
        // l'appui dit pourquoi et comment en sortir.
        BrandToggleCard(
            BookCopy.Rules.toggle,
            BookCopy.Rules.detail,
            isOn = customisation?.rulesEnabled ?: false,
            onIsOnChange = model::setRules,
            isAvailable = !state.isRulesSwitchLocked,
            onUnavailable = model::explainRulesLock,
        )
        AnimatedVisibility(state.showsRulesLockNotice, enter = fadeIn(), exit = fadeOut()) {
            // TalkBack la dit en la voyant paraître — l'annonce d'iOS.
            BrandNotice(
                BookCopy.Rules.locked,
                Modifier
                    .revealedWhenShown(state.showsRulesLockNotice)
                    .semantics { liveRegion = LiveRegionMode.Polite },
                tone = BrandNotice.Tone.Information,
            )
        }
        BrandToggleCard(
            BookCopy.FunFacts.toggle,
            BookCopy.FunFacts.detail,
            isOn = customisation?.funFactsEnabled ?: false,
            onIsOnChange = model::setFunFacts,
        )
        BrandToggleCard(
            BookCopy.Customisation.quizTitle,
            BookCopy.Customisation.quizDetail,
            isOn = customisation?.quizEnabled ?: false,
            onIsOnChange = model::setQuiz,
        )
        BrandToggleCard(
            BookCopy.Customisation.freeZonesTitle,
            BookCopy.Customisation.freeZonesDetail,
            isOn = customisation?.freeZonesEnabled ?: false,
            onIsOnChange = model::setFreeZones,
        )
        BrandToggleCard(
            BookCopy.Customisation.crosswordTitle,
            BookCopy.Customisation.crosswordDetail,
            isOn = customisation?.crosswordEnabled ?: false,
            onIsOnChange = model::setCrossword,
        )
    }
}

// MARK: - Les deux blocs communs

/** La phrase d'explication en tête d'un panneau : le corps de texte, en gris. */
@Composable
private fun BookPanelLead(text: String) {
    BrandText(text, MemoBookFont.body, Modifier.fillMaxWidth(), color = MemoBookColor.inkMuted)
}

/**
 * La carte papier qui porte les choix d'un panneau (`3595:23854`) : un aplat
 * papier, un filet, et les options dedans.
 */
@Composable
private fun BookPanelCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    Column(
        modifier
            .fillMaxWidth()
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        content = content,
    )
}

/**
 * Amène la note à l'écran quand elle paraît — le `proxy.scrollTo(…, anchor:
 * .bottom)` d'iOS. Elle tombe souvent sous le bas de l'écran (sous les trois
 * assortiments, sous les paliers, ou aux grandes tailles de police), et le
 * geste n'aurait l'air de rien.
 */
@Composable
private fun Modifier.revealedWhenShown(isShown: Boolean, key: Any? = null): Modifier {
    val requester = remember { BringIntoViewRequester() }
    LaunchedEffect(isShown, key) {
        if (isShown) requester.bringIntoView()
    }
    return bringIntoViewRequester(requester)
}

@Preview(locale = "fr-rFR", name = "Panneaux du carnet", widthDp = 390, heightDp = 2200)
@Composable
private fun BookCustomisationPanelsPreview() {
    val model = remember { BookCustomisationModel(tripId = "preview") }
    LaunchedEffect(model) { model.load() }
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
    ) {
        BookRatioPanel(model)
        BookPagesPanel(model)
        BookDecorationsPanel(model)
        BookFontsPanel(model)
        BookExtrasPanel(model)
    }
}
