package com.memobook.feature.tripcreation

import android.content.ClipData
import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLocale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.memobook.core.BookCopy
import com.memobook.core.InviteLink
import com.memobook.core.NarrationPace
import com.memobook.core.TripTheme
import com.memobook.design.BrandButton
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandRangeCalendar
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandSlider
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.DateRangeSelection
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.home.TripDates
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs
import kotlin.math.max

/**
 * Les champs de la création. Le focus appartient à l'écran, pas au champ —
 * voir `ios/CLAUDE.md`, « Design system ».
 */
enum class TripCreationField { FreeTheme, Title }

/**
 * Le milieu de l'écran : ce que l'étape courante demande, et rien d'autre.
 * Jumeau de `TripCreation/TripCreationSteps.swift`.
 *
 * Une seule vue pour les six cas plutôt que six fichiers : elles partagent la
 * même largeur, la même colonne et le même modèle, et les mettre côte à côte
 * est la seule façon de voir qu'elles se ressemblent autant.
 *
 * @param inviteBase l'adresse de production, d'où part le lien d'invitation
 *   (`InviteLink.url`) — `dependencies.productionApiBaseUrl`. `null` en aperçu :
 *   le message part avec le code seul.
 * @param onAdvance valider l'étape depuis son contenu — le rythme des relances
 *   avance dès qu'une option est choisie (Hugo, 29/09/2026), sans passer par le
 *   bouton.
 */
@Composable
internal fun TripCreationStepContent(
    model: TripCreationModel,
    state: TripCreationModel.State,
    step: TripCreationStep,
    focus: TripCreationField?,
    onFocusChange: (TripCreationField?) -> Unit,
    inviteBase: URI?,
    modifier: Modifier = Modifier,
    onAdvance: () -> Unit = {},
) {
    Box(modifier) {
        when (step) {
            TripCreationStep.Theme -> ThemeStep(model, state, focus, onFocusChange)
            TripCreationStep.Name -> NameStep(model, state, focus, onFocusChange)
            TripCreationStep.Dates -> DatesStep(model, state)
            TripCreationStep.Notifications -> NotificationsStep(model, state, onAdvance)
            TripCreationStep.Ratio -> RatioStep(model, state)
            TripCreationStep.Companions -> CompanionsStep(state, inviteBase)
        }
    }
}

// MARK: - 1. Contexte

/**
 * La rangée d'émojis, et le champ libre quand on choisit « Autre ».
 *
 * Le champ n'apparaît **que** derrière « Autre », et c'est exactement l'état
 * que montre la maquette : un thème choisi et un thème écrit sont deux
 * réponses à la même question, les afficher ensemble laisserait croire qu'on
 * peut donner les deux.
 */
@Composable
private fun ThemeStep(
    model: TripCreationModel,
    state: TripCreationModel.State,
    focus: TripCreationField?,
    onFocusChange: (TripCreationField?) -> Unit,
) {
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        if (state.themes.isEmpty()) {
            // Les thèmes viennent du serveur : le temps qu'ils arrivent, la
            // rangée tient sa place — une barre d'attente, pas des émojis
            // inventés. Si la lecture a échoué, on le dit, et « Passer »
            // reste là.
            val failure = state.themesFailure
            if (failure != null) {
                ErrorBanner(failure, retry = { scope.launch { model.loadThemes() } })
            } else {
                TripThemePickerPlaceholder()
            }
        } else {
            TripThemePicker(
                themes = state.themes,
                selection = state.selectedTheme,
                onSelectionChange = { model.selectedTheme = it },
                onSelect = { theme -> if (!theme.isOther) onFocusChange(null) },
                // La rangée va **jusqu'aux bords de l'écran**, contrairement au
                // reste de l'étape : c'est ce qui permet à la première et à la
                // dernière pastille d'atteindre le milieu, et au défilement de
                // sortir de la colonne de texte au lieu de s'y arrêter.
                modifier = Modifier.bleedingPastMargins(MemoBookSpacing.screenMargin),
            )
        }

        // Il **arrive**, il n'apparaît pas : le champ se déplie sous la rangée
        // en même temps que « Autre » grossit, et repart de même. Sans
        // transition, il claque à l'écran au milieu d'un mouvement.
        AnimatedVisibility(
            visible = state.isFreeThemeChosen,
            enter = expandVertically(SwiftMotion.smooth(0.3f), expandFrom = Alignment.Top) + fadeIn(SwiftMotion.smooth(0.3f)),
            exit = shrinkVertically(SwiftMotion.smooth(0.3f), shrinkTowards = Alignment.Top) + fadeOut(SwiftMotion.smooth(0.3f)),
        ) {
            BrandTextField(
                "Thème de ton voyage",
                state.freeTheme,
                { model.freeTheme = it },
                field = TripCreationField.FreeTheme,
                focus = focus,
                onFocusChange = onFocusChange,
                labelPlacement = BrandTextField.LabelPlacement.Hidden,
                placeholder = "Entre le thème de ton voyage ici",
            )
        }
    }
}

/**
 * Élargit une vue de [margin] de chaque côté : la marge négative d'iOS
 * (`.padding(.horizontal, -margin)`), que Compose n'a pas.
 */
private fun Modifier.bleedingPastMargins(margin: Dp): Modifier = layout { measurable, constraints ->
    val extra = (margin * 2).roundToPx()
    val maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + extra else constraints.maxWidth
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.minWidth + extra, maxWidth = maxWidth))
    layout(placeable.width - extra, placeable.height) { placeable.place(-extra / 2, 0) }
}

// MARK: - 2. Nom

@Composable
private fun NameStep(
    model: TripCreationModel,
    state: TripCreationModel.State,
    focus: TripCreationField?,
    onFocusChange: (TripCreationField?) -> Unit,
) {
    BrandTextField(
        "Nom de ton voyage",
        state.draft.title,
        { title -> model.editDraft { it.copy(title = title) } },
        field = TripCreationField.Title,
        focus = focus,
        onFocusChange = onFocusChange,
        labelPlacement = BrandTextField.LabelPlacement.Hidden,
        placeholder = "Entre le nom de ton voyage ici",
    )
}

// MARK: - 3. Dates

/**
 * Deux cases, « Départ » et « Retour », et un seul calendrier qui se déplie
 * dessous.
 *
 * Une seule ligne « Du … au … » promettait deux dates, et le retour n'est pas
 * exigé : la case « Retour » dit « Facultatif » tant qu'elle est vide, l'écran
 * le dit lui-même. Le calendrier s'ouvre **sous** les cases plutôt que dans une
 * feuille : ce qu'on vient de poser reste lisible au-dessus.
 */
@Composable
private fun DatesStep(model: TripCreationModel, state: TripCreationModel.State) {
    TripDateRangeRow(
        start = state.draft.startDate,
        end = state.draft.endDate,
        onChange = { start, end -> model.editDraft { it.copy(startDate = start, endDate = end) } },
    )
}

// MARK: - 4. Notifications

/** Le rythme des relances proposé à la création. */
internal val TRIP_CREATION_PACES: List<NarrationPace> get() = listOf(NarrationPace.Daily, NarrationPace.EveryTwoDays, NarrationPace.Weekly)

/**
 * Le rythme des relances — **les mêmes que les réglages du voyage**
 * (`NarrationPace`), dont on ne propose ici que trois : on va vite à la
 * création, on ajuste finement plus tard (Hugo, 17/09/2026, T122). C'est la
 * clé du rythme qui part en base, comme depuis la feuille des réglages ; trois
 * libellés libres y écrivaient une autre langue.
 *
 * **Choisir, c'est valider** (Hugo, 29/09/2026) : la carte touchée se cerne le
 * temps qu'on la voie cochée, puis l'étape passe à la suivante. Le bouton
 * « Valider » reste là pour qui a déjà une option cochée en revenant en
 * arrière.
 *
 * **C'est ici que l'app demande l'autorisation des notifications** — le « au
 * bon moment » de l'onboarding : on vient de dire à quel rythme on veut être
 * relancé, la question d'Android en est la suite logique. Android 13 et plus
 * la posent ; Android ne la repose plus après deux refus. Passer l'étape ne
 * demande rien. Voir `docs/notifications.md`.
 */
@Composable
private fun NotificationsStep(model: TripCreationModel, state: TripCreationModel.State, onAdvance: () -> Unit) {
    val scope = rememberCoroutineScope()
    // Qui demande l'autorisation d'envoyer des notifications — `null` dans un
    // aperçu, où aucune question système ne doit s'ouvrir.
    val pushNotifications = LocalPushNotifications.current
    val askSystem = rememberNotificationPermissionRequest()
    val advance by rememberUpdatedState(onAdvance)

    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 4.dp)) {
        TRIP_CREATION_PACES.forEach { pace ->
            TripCreationCard(
                isSelected = state.draft.narrationPace == pace.rawValue,
                onClick = {
                    model.editDraft { it.copy(narrationPace = pace.rawValue) }
                    scope.launch {
                        delay(BrandOptionRow.lingerBeforeDismiss)
                        // L'étape attend la réponse : la question du système se
                        // pose sur l'écran qui l'a amenée, pas sur le suivant.
                        pushNotifications?.requestAuthorization(askSystem)
                        advance()
                    }
                },
            ) {
                BrandText(pace.displayName, MemoBookFont.body, Modifier.fillMaxWidth(), color = MemoBookColor.ink)
            }
        }
    }
}

// MARK: - 5. Ratio image / texte

/**
 * Un curseur entre deux bornes nommées, et le pourcentage sous la poignée.
 *
 * Par pas de 10 : la maquette montre « 50 % », et le réglage pilote le choix
 * des gabarits de page, pas une largeur au pixel. Un curseur continu donnerait
 * « 47 % », qui ne veut rien dire de plus que « 50 % ».
 *
 * Le `Slider` du système sur iOS ; ici [BrandSlider], sans ses crans écrits :
 * la ligne du dessous dit les bornes et la valeur, comme sur iOS.
 */
@Composable
private fun RatioStep(model: TripCreationModel, state: TripCreationModel.State) {
    val ratio = state.draft.photoTextRatio
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandSlider(
            value = ratio,
            onValueChange = { value -> model.editDraft { it.copy(photoTextRatio = value) } },
            bounds = 0..100,
            step = 10,
            ticks = (0..100 step 10).map { "" },
            voiceLabel = TripCreationStep.Ratio.title,
            voiceValue = { "$it %" },
        )

        // Les deux bornes disent ce que le curseur fait : elles se lisent d'un
        // coup d'œil, pas en s'approchant de l'écran.
        Row(verticalAlignment = Alignment.Top) {
            BrandText("Beaucoup\nde texte", MemoBookFont.body, color = MemoBookColor.inkMuted, textAlign = TextAlign.Start)
            Spacer(Modifier.weight(1f))
            // La valeur du réglage, et donc ce qu'on lit en poussant le
            // curseur : elle prend le corps d'un titre. En légende, on ne
            // voyait pas ce qu'on était en train de changer. Les chiffres ne
            // dansent pas : sans chasse fixe, la valeur se décale à chaque pas.
            BrandText("$ratio %", MemoBookFont.h2.copy(fontFeatureSettings = "tnum"), color = MemoBookColor.action)
            Spacer(Modifier.weight(1f))
            BrandText("Beaucoup\nd’image", MemoBookFont.body, color = MemoBookColor.inkMuted, textAlign = TextAlign.End)
        }
    }
}

// MARK: - 6. Co-voyageurs

/**
 * Le code d'accès, et de quoi l'envoyer. Rien à valider ici : le voyage existe
 * déjà, c'est la validation de l'étape précédente qui l'a créé.
 *
 * **L'étape se dessine pendant que le voyage part** (Hugo, 29/09/2026) — et
 * même sans réseau du tout (01/10/2026) : tout ce qu'elle montre est sur le
 * téléphone, sauf le code, que seul le serveur tire. Le code porte donc la
 * seule barre d'attente de l'écran, et « Partager » reste gris tant qu'il n'y
 * a rien à partager. Hors ligne, l'attente dure jusqu'au retour du réseau ;
 * « Commencer ! », lui, ouvre le voyage tout de suite.
 */
@Composable
private fun CompanionsStep(state: TripCreationModel.State, inviteBase: URI?) {
    TripAccessCode(
        code = state.accessCode,
        tripTitle = state.trip?.title ?: state.draft.title,
        inviteBase = inviteBase,
        waitingNote = if (state.awaitsReconnection) "Ton code arrivera dès ta reconnexion" else null,
    )
}

// MARK: - Le carrousel des thèmes

/**
 * Les thèmes, en rangée qui défile : celui du milieu est **celui qu'on
 * choisit**, plus gros et à pleine encre ; ses voisins s'effacent à 60 %.
 *
 * **C'est un carrousel et non une barre de pastilles**, et c'est ce que dit la
 * maquette : les thèmes ne tiennent pas côte à côte à une taille lisible, et
 * celui qui est choisi y est presque deux fois plus grand que ses voisins. La
 * rangée se fait donc glisser, et le choix se pose au centre — d'où les marges
 * latérales, qui valent la moitié de ce qui reste : sans elles, ni le premier
 * ni le dernier thème ne pourraient atteindre le milieu.
 *
 * **Glisser choisit.** La rangée s'arrête d'elle-même sur un thème (la
 * mise au centre de `rememberSnapFlingBehavior`, le `viewAligned` d'iOS), et
 * celui qui s'arrête au centre est le choix — Hugo, 14/09/2026 : « l'émoji qui
 * se retrouve au centre est celui sélectionné ». Toucher un thème l'amène au
 * centre, ce qui revient au même. La position ne se pose qu'à l'arrêt : un
 * survol ne remplit pas `memos.theme` de tout ce qu'on a dépassé.
 *
 * **Le nom du thème s'écrit sous la rangée**, en entier et centré, et non sous
 * chaque émoji : dans la boîte d'un émoji, « Vacances au soleil » et « Voyage
 * d'affaires » se faisaient rogner (Hugo, 14/09/2026).
 *
 * Le même carrousel sert la feuille « Thème » des réglages du voyage.
 *
 * @param themes les thèmes, dans l'ordre du serveur — « Autre » en dernier.
 * @param onSelectionChange la sélection, que l'écran garde — le `Binding` d'iOS.
 * @param onSelect prévenu du thème choisi, pour que l'étape range son clavier
 *   quand le champ libre disparaît. En dernier : c'est la fermeture finale
 *   d'iOS (`TripThemePicker(…) { theme in … }`).
 */
@Composable
internal fun TripThemePicker(
    themes: List<TripTheme>,
    selection: TripTheme?,
    onSelectionChange: (TripTheme) -> Unit,
    modifier: Modifier = Modifier,
    onSelect: (TripTheme) -> Unit,
) {
    // La largeur d'une pastille. Fixe, parce que c'est elle qui règle le
    // centrage : la marge latérale vaut la moitié de ce qui reste quand une
    // pastille est au milieu.
    val itemWidth = scaled(72.dp)
    // La hauteur de la rangée : l'émoji au plus gros. Elle ne bouge pas avec la
    // sélection, sinon toute l'étape sauterait à chaque glissé.
    val rowHeight = scaled(54.dp)
    // La boîte du nom, réservée qu'il soit écrit ou non : le libellé arrive et
    // repart sans décaler ce qui est dessous.
    val labelBox = scaled(20.dp)

    val currentSelection by rememberUpdatedState(selection)
    val select by rememberUpdatedState { theme: TripTheme ->
        onSelect(theme)
        onSelectionChange(theme)
    }

    // La rangée s'ouvre sur le thème choisi, ou sur son **milieu** — c'est le
    // cadrage de la maquette, celui qui montre des thèmes des deux côtés au
    // lieu d'une moitié d'écran vide — et ce qui est au milieu devient le
    // choix, comme pour n'importe quel glissé. « Autre » étant dernier, le
    // milieu est toujours un thème précis.
    val opening = (themes.indexOf(selection).takeIf { it >= 0 } ?: (themes.size / 2)).coerceAtLeast(0)
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = opening)
    val scope = rememberCoroutineScope()

    Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(rowHeight)) {
            // Ce qu'il faut de chaque côté pour qu'une pastille de bord puisse
            // venir au milieu.
            val inset = max(0f, ((maxWidth - itemWidth) / 2).value).dp
            LazyRow(
                state = listState,
                contentPadding = PaddingValues(horizontal = inset),
                flingBehavior = rememberSnapFlingBehavior(listState, SnapPosition.Center),
                modifier = Modifier.fillMaxWidth().height(rowHeight),
            ) {
                itemsIndexed(themes, key = { _, theme -> theme.id }) { index, theme ->
                    TripThemeButton(
                        theme = theme,
                        isSelected = selection == theme,
                        modifier = Modifier.width(itemWidth),
                    ) {
                        // Toucher un thème l'amène au centre ; c'est l'arrêt au
                        // centre qui choisit, le même chemin que le glissé.
                        scope.launch { listState.animateScrollToItem(index) }
                        select(theme)
                    }
                }
            }
        }

        Crossfade(selection?.label ?: " ", animationSpec = SwiftMotion.smooth(0.3f), label = "thème") { label ->
            // Le corps des intitulés (14) et non celui des légendes (12) :
            // c'est le seul mot qui nomme ce qu'on vient de choisir, il se lit
            // sans se pencher.
            BrandText(
                label,
                MemoBookFont.label,
                Modifier
                    .fillMaxWidth()
                    .height(labelBox)
                    .clearAndSetSemantics {},
                color = MemoBookColor.inkMuted,
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }

    // Le thème arrêté au centre de la rangée : c'est la position de
    // défilement elle-même, lue à l'arrêt — et dès la première mise en page,
    // qui pose le cadrage d'ouverture ; la sélection la suit.
    LaunchedEffect(listState, themes) {
        snapshotFlow { if (listState.isScrollInProgress) null else listState.centeredIndex() }
            .filterNotNull()
            .distinctUntilChanged()
            .collect { index ->
                val theme = themes.getOrNull(index) ?: return@collect
                if (theme != currentSelection) select(theme)
            }
    }

    // La sélection peut changer sans la rangée — revenir sur l'étape après
    // « Passer », par exemple : la rangée la rejoint.
    LaunchedEffect(selection) {
        val index = themes.indexOf(selection ?: return@LaunchedEffect)
        if (index >= 0 && listState.centeredIndex() != index && !listState.isScrollInProgress) {
            listState.animateScrollToItem(index)
        }
    }
}

/** La pastille la plus proche du milieu de la rangée, `null` avant la première mise en page. */
private fun LazyListState.centeredIndex(): Int? {
    val layout = layoutInfo
    val center = (layout.viewportStartOffset + layout.viewportEndOffset) / 2
    return layout.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - center) }?.index
}

/**
 * La rangée, le temps que les thèmes arrivent : cinq ronds effacés à la place
 * des émojis, et une barre à la place du nom. Les mêmes hauteurs que la vraie
 * rangée, pour que rien ne saute quand elle se remplit.
 */
@Composable
internal fun TripThemePickerPlaceholder(modifier: Modifier = Modifier) {
    val rowHeight = scaled(54.dp)
    val dot = scaled(25.dp)
    val labelBox = scaled(20.dp)

    Column(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "Chargement des thèmes" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        Row(
            Modifier.height(rowHeight),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            repeat(5) { index ->
                val side = if (index == 2) dot * 1.7f else dot
                Box(
                    Modifier
                        .size(side)
                        .background(MemoBookColor.ink.copy(alpha = if (index == 2) 0.12f else 0.07f), CircleShape),
                )
            }
        }

        Box(Modifier.height(labelBox), contentAlignment = Alignment.Center) {
            BrandSkeleton(width = 120.dp)
        }
    }
}

// MARK: - Un émoji de thème

/**
 * Un thème : son émoji, gros et à pleine encre quand il est choisi, plus petit
 * et effacé sinon. Son nom, lui, s'écrit sous la rangée — voir
 * [TripThemePicker]. TalkBack, en revanche, entend toujours le nom : sans quoi
 * la rangée serait onze boutons sans étiquette.
 *
 * L'agrandissement est une échelle et non un changement de corps : une taille
 * de police ne s'anime pas, elle saute d'une valeur à l'autre.
 */
@Composable
internal fun TripThemeButton(theme: TripTheme, isSelected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    // Le rapport entre le thème choisi et ses voisins. Il est franc — presque
    // du simple au double — parce que c'est, avec l'opacité, ce qui dit lequel
    // est choisi : il n'y a ni pastille, ni contour, ni coche.
    val scale by animateFloatAsState(if (isSelected) 1.7f else 1f, SwiftMotion.smooth(0.3f), label = "échelle")
    // L'opacité des voisins : 60 %, la valeur de la maquette (Hugo,
    // 14/09/2026). Le choisi est à 100 %.
    val opacity by animateFloatAsState(if (isSelected) 1f else 0.6f, SwiftMotion.smooth(0.3f), label = "opacité")
    val side = with(LocalDensity.current) { scaled(25.dp).toSp() }
    // La boîte de l'émoji : la taille du plus gros, avec de quoi loger la
    // hauteur de ligne que les polices d'émoji ajoutent autour du dessin.
    val emojiBox = scaled(46.dp)

    Box(
        modifier
            // La place du plus gros, toujours, et **la même pour tous** : c'est
            // cette boîte, et non la hauteur du glyphe, qui pose la ligne
            // médiane de la rangée. Sans elle, un émoji haut comme la bulle
            // remontait ses voisins.
            .height(emojiBox)
            .fillMaxWidth()
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = theme.label
                selected = isSelected
            },
        contentAlignment = Alignment.Center,
    ) {
        BrandText(
            theme.emoji,
            MemoBookFont.body.copy(fontSize = if (side.value > 0f) side else 25.sp),
            Modifier.graphicsLayer {
                scaleX = scale
                scaleY = scale
                alpha = opacity
            },
            maxLines = 1,
        )
    }
}

// MARK: - Une ligne blanche

/**
 * La ligne des étapes qui listent : un aplat blanc, un grand rayon, aucun
 * contour.
 *
 * ⚠️ La maquette ne montre **aucune ligne choisie** — ni coche, ni teinte. Le
 * vert et le contour de l'état sélectionné sont ajoutés ici : sans eux, on ne
 * verrait pas ce qu'on vient de toucher. À confirmer avec Clara.
 */
@Composable
internal fun TripCreationCard(
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.fieldHeight)
            .clip(shape)
            .background(MemoBookColor.surface, shape)
            .border(1.5.dp, if (isSelected) MemoBookColor.action else Color.Transparent, shape)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onClick)
            .semantics { selected = isSelected }
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.s - 2.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        label()
    }
}

// MARK: - Les dates

/**
 * « Départ · 18 sept. 2026 » et « Retour · Facultatif », côte à côte, et le
 * calendrier de plage qui se déplie dessous.
 *
 * La case cerclée de vert est celle que le prochain jour touché remplit.
 * Toucher une case la choisit : on revient corriger le départ sans perdre le
 * retour. Toucher la case déjà en cours replie le calendrier.
 *
 * Le calendrier travaille sur des jours (`LocalDate`) ; le brouillon garde deux
 * instants, le début du jour dans le fuseau du téléphone. La conversion fait le
 * pont dans les deux sens.
 */
@Composable
internal fun TripDateRangeRow(start: Instant?, end: Instant?, onChange: (Instant?, Instant?) -> Unit) {
    var isOpen by remember { mutableStateOf(false) }
    // La case en cours — celle que le calendrier remplit. Elle vit ici et non
    // dans le brouillon : c'est un état de l'écran, pas du voyage.
    var editing by remember { mutableStateOf(DateRangeSelection.Slot.Start) }
    val zone = ZoneId.systemDefault()

    val selection = DateRangeSelection(start = start?.atZone(zone)?.toLocalDate(), end = end?.atZone(zone)?.toLocalDate(), editing = editing)
    fun apply(picked: DateRangeSelection) {
        editing = picked.editing
        onChange(picked.start?.startOfDay(zone), picked.end?.startOfDay(zone))
    }

    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        val slots: @Composable (Modifier) -> Unit = { slotModifier ->
            DateSlot(DateRangeSelection.Slot.Start, "Départ", start, "À choisir", isActive = isOpen && editing == DateRangeSelection.Slot.Start, slotModifier,
                onToggle = { if (isOpen && editing == DateRangeSelection.Slot.Start) isOpen = false else { editing = DateRangeSelection.Slot.Start; isOpen = true } },
                onClear = { apply(selection.clear(DateRangeSelection.Slot.Start)) },
            )
            DateSlot(DateRangeSelection.Slot.End, "Retour", end, "Facultatif", isActive = isOpen && editing == DateRangeSelection.Slot.End, slotModifier,
                onToggle = { if (isOpen && editing == DateRangeSelection.Slot.End) isOpen = false else { editing = DateRangeSelection.Slot.End; isOpen = true } },
                onClear = { apply(selection.clear(DateRangeSelection.Slot.End)) },
            )
        }
        // Deux cases côte à côte, empilées aux tailles accessibles.
        if (isAccessibilityTextSize()) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) { slots(Modifier.fillMaxWidth()) }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) { slots(Modifier.weight(1f)) }
        }

        AnimatedVisibility(
            visible = isOpen,
            enter = expandVertically(SwiftMotion.smooth(0.25f)) + fadeIn(SwiftMotion.smooth(0.25f)),
            exit = shrinkVertically(SwiftMotion.smooth(0.25f)) + fadeOut(SwiftMotion.smooth(0.25f)),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                BrandRangeCalendar(selection, onSelectionChange = ::apply)

                Crossfade(hint(selection), label = "consigne") { text ->
                    BrandText(text, MemoBookFont.caption, Modifier.fillMaxWidth(), color = MemoBookColor.inkMuted, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

/** Ce qu'il reste à faire, dit sous le calendrier. */
private fun hint(selection: DateRangeSelection): String = when {
    selection.editing == DateRangeSelection.Slot.Start -> "Touche ton jour de départ"
    selection.start == null -> "Touche d’abord ton jour de départ"
    selection.end == null -> "Touche ton jour de retour — ou valide sans"
    else -> "Touche une case pour corriger une date"
}

private fun LocalDate.startOfDay(zone: ZoneId): Instant = atStartOfDay(zone).toInstant()

/** Remonte une vue de [distance] sur ce qui la précède — le `.padding(.top, -distance)` d'iOS. */
private fun Modifier.pulledUp(distance: Dp): Modifier = layout { measurable, constraints ->
    val shift = distance.roundToPx()
    val placeable = measurable.measure(constraints)
    layout(placeable.width, (placeable.height - shift).coerceAtLeast(0)) { placeable.place(0, -shift) }
}

/** Une case. */
@Composable
private fun DateSlot(
    slot: DateRangeSelection.Slot,
    title: String,
    date: Instant?,
    placeholder: String,
    isActive: Boolean,
    modifier: Modifier,
    onToggle: () -> Unit,
    onClear: () -> Unit,
) {
    val locale = LocalLocale.current.platformLocale
    val zone = ZoneId.systemDefault()
    val longDate = date?.let { DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale).format(it.atZone(zone)) }

    TripCreationCard(
        isSelected = isActive,
        onClick = onToggle,
        modifier = modifier.semantics {
            contentDescription = if (slot == DateRangeSelection.Slot.Start) "Date de départ" else "Date de retour"
            stateDescription = longDate ?: if (slot == DateRangeSelection.Slot.Start) "Non définie" else "Facultative, non définie"
        },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                BrandText(title, MemoBookFont.overline, color = if (isActive) MemoBookColor.action else MemoBookColor.inkMuted)

                // Sur une ligne, quoi qu'il arrive : « 20 sept. 2026 » et la
                // croix tiennent tout juste dans une demi-largeur, et une date
                // qui se replie sur deux lignes déséquilibre les deux cases.
                BrandText(
                    date?.let { TripDates.day(it, locale, zone) } ?: placeholder,
                    MemoBookFont.body,
                    color = if (date == null) MemoBookColor.inkMuted else MemoBookColor.ink,
                    maxLines = 1,
                    minimumScaleFactor = 0.8f,
                )
            }

            if (date != null) {
                Box(
                    Modifier
                        .size(MemoBookSpacing.m + 4.dp)
                        .clip(CircleShape)
                        .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onClear)
                        .semantics { contentDescription = if (slot == DateRangeSelection.Slot.Start) "Effacer les dates" else "Effacer le retour" },
                    contentAlignment = Alignment.Center,
                ) {
                    Image(
                        painterResource(R.drawable.icon_cross),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
    }
}

// MARK: - Le code d'accès

/**
 * « Code d'accès : JHKFDA », et de quoi l'envoyer.
 *
 * Le code se **copie** d'un geste — c'est ce que dit le petit pictogramme de la
 * maquette — et se partage par la feuille du système. **Un seul bouton,
 * « Partager »** (Hugo, 29/09/2026) : il disait « Partager via WhatsApp » et
 * ouvrait WhatsApp directement, avec un second bouton pour tout le reste sur
 * la feuille « Inviter un proche ». La feuille de partage d'Android propose
 * WhatsApp parmi les autres, et c'est le même geste partout dans l'app.
 *
 * Le même bloc sert la dernière étape de la création et « Inviter un proche » :
 * c'est le même code d'accès, le même presse-papiers et la même invitation.
 *
 * @param code le code, ou `null` tant que le voyage n'est pas revenu du
 *   serveur : la ligne porte alors une barre d'attente et « Partager » reste
 *   gris.
 * @param inviteBase l'adresse de production, d'où part le lien d'invitation —
 *   `dependencies.productionApiBaseUrl`. `null` : le message part avec le code
 *   seul.
 * @param waitingNote ce qu'on dit sous la barre d'attente, quand on sait
 *   pourquoi elle dure — hors ligne, « Ton code arrivera dès ta reconnexion »
 *   (T240). `null` ailleurs : la barre seule suffit à une attente d'un instant.
 */
@Composable
internal fun TripAccessCode(
    code: String?,
    tripTitle: String,
    inviteBase: URI?,
    waitingNote: String? = null,
    modifier: Modifier = Modifier,
) {
    var hasCopied by remember { mutableStateOf(false) }
    val clipboard = LocalClipboard.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Le message partagé : le lien d'invitation d'abord (18/10/2026) — il
    // ouvre l'app sur le voyage, ou le Play Store —, le code ensuite, pour
    // l'entrer à la main après l'installation.
    fun invitation(): String = BookCopy.Invite.invitation(
        tripTitle = tripTitle,
        code = code.orEmpty(),
        link = code?.let { InviteLink.url(it, base = inviteBase)?.toString() },
    )

    Column(
        modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
    ) {
        Row(
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                // Pas désactivée : elle pâlirait aussi « Code d’accès : », et
                // seule la barre d'attente doit dire qu'on attend (Hugo,
                // 01/10/2026). Sans code, la ligne ne répond simplement pas au
                // doigt.
                .clickable(enabled = code != null, interactionSource = null, indication = PlainButtonIndication, role = Role.Button) {
                    val current = code ?: return@clickable
                    scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Code d’accès", current))) }
                    hasCopied = true
                }
                .clearAndSetSemantics {
                    contentDescription = code?.let { "Copier le code d’accès $it" } ?: "Code d’accès en cours de création"
                },
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (code != null) {
                BrandText("Code d’accès : $code", MemoBookFont.body, color = MemoBookColor.inkMuted)
                Image(
                    painterResource(if (hasCopied) R.drawable.icon_lucide_check else R.drawable.icon_lucide_copy),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(if (hasCopied) MemoBookColor.valid else MemoBookColor.inkMuted),
                    modifier = Modifier.size(15.dp),
                )
            } else {
                BrandText("Code d’accès :", MemoBookFont.body, color = MemoBookColor.inkMuted)
                BrandSkeleton(width = 88.dp)
            }
        }

        // Sous la barre d'attente, et seulement hors ligne : pourquoi elle
        // dure, et quand elle cessera (T240, Hugo, 06/10/2026).
        AnimatedVisibility(visible = code == null && waitingNote != null, enter = fadeIn(), exit = fadeOut()) {
            BrandText(
                waitingNote.orEmpty(),
                MemoBookFont.caption,
                Modifier.pulledUp(MemoBookSpacing.s),
                color = MemoBookColor.inkMuted,
                textAlign = TextAlign.Center,
            )
        }

        BrandButton(
            "Partager",
            icon = painterResource(R.drawable.icon_share_system),
            style = BrandButton.Style.Primary,
            fillsWidth = true,
            enabled = code != null,
        ) {
            if (code == null) return@BrandButton
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, invitation())
            }
            context.startActivity(Intent.createChooser(send, null))
        }
    }
}
