package com.memobook.feature.covers

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.CoverFace
import com.memobook.design.BrandHeaderAction
import com.memobook.design.BrandNotice
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSegmentedPicker
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.scaled
import com.memobook.feature.CoversIntent
import com.memobook.feature.tripsettings.blocksTouches
import kotlinx.coroutines.launch

/**
 * Le choix des couvertures : le plat qu'on a, et les trois façons d'en changer.
 * Jumeau de `Covers/CoversView.swift`.
 *
 * **On y arrive de deux endroits**, et c'est voulu : par la commande d'en-tête
 * des personnalisations, et par la pastille « Définis maintenant ta 1ère et 4ème
 * de couverture » posée sur la première et la dernière page de l'aperçu PDF. Le
 * second chemin est le plus important — c'est en regardant son carnet qu'on se
 * rend compte qu'il n'a pas de couverture.
 *
 * L'écran ne fait presque rien lui-même : il montre le plat en grand et ouvre
 * les trois écrans qui le changent. C'est son rôle — **voir avant de régler**.
 */
@Composable
fun CoversView(model: CoversModel, onIntent: (CoversIntent) -> Unit, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    // L'explication posée par une ligne qui ne mène nulle part. `null` le reste
    // du temps — voir les deux lignes qui pâlissent.
    var blockedMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(model) { model.load() }
    // Changer de plat referme l'explication : elle parlait de l'autre.
    LaunchedEffect(state.face) { blockedMessage = null }

    val covers = state.covers
    val acceptsPhoto = covers?.acceptsPhoto(state.face) ?: true
    val acceptsText = covers?.acceptsText(state.face) ?: true

    CompositionLocalProvider(LocalRefreshCoverPhotos provides { model.refreshPhotoLinks() }) {
        Column(
            modifier
                .fillMaxSize()
                .background(MemoBookColor.background)
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            // **Le chemin vers les personnalisations** (Hugo, 19/10/2026) : les
            // couvertures et le reste du style se règlent ensemble, et chacun
            // des deux écrans mène à l'autre par l'angle supérieur droit. Le
            // signe est celui de la pastille « Décorations » des
            // personnalisations, pas l'engrenage des réglages du voyage.
            BrandScreenHeader(BookCopy.Covers.title, onBack = onBack, trailing = {
                BrandHeaderAction(R.drawable.icon_category_decorations, BookCopy.Preview.customise) {
                    onIntent(CoversIntent.OpenCustomisation)
                }
            })

            CoverFaceTabs(state.face, onFaceChange = model::setFace)

            CoverPlateBlock(model, state, plateWidth = 300.dp)

            // Les trois façons d'en changer.
            Column(
                Modifier
                    .blocksTouches(covers == null)
                    .animateContentSize(SwiftMotion.snappy(0.25f)),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            ) {
                CoverActionRow(R.drawable.icon_layers, BookCopy.Covers.changeStyle) {
                    onIntent(CoversIntent.OpenStyle)
                }

                // **Les deux lignes suivantes pâlissent** quand le style du plat
                // qu'on regarde ne les porte pas : un aplat n'a pas de photo, une
                // photo pleine page au dos n'a pas de texte. Elles restent
                // tapables et posent l'explication.
                CoverActionRow(R.drawable.icon_picture_frame, BookCopy.Covers.changePhoto, isAvailable = acceptsPhoto) {
                    if (!acceptsPhoto) {
                        blockedMessage = BookCopy.Covers.noPhotoHere(state.face)
                        return@CoverActionRow
                    }
                    onIntent(CoversIntent.OpenPhoto)
                }

                CoverActionRow(R.drawable.icon_pen, BookCopy.Covers.editTexts, isAvailable = acceptsText) {
                    if (!acceptsText) {
                        blockedMessage = BookCopy.Covers.noTextHere(state.face)
                        return@CoverActionRow
                    }
                    onIntent(CoversIntent.OpenTexts)
                }

                val retained = remember { arrayOfNulls<String>(1) }
                blockedMessage?.let { retained[0] = it }
                AnimatedVisibility(blockedMessage != null, enter = fadeIn(), exit = fadeOut()) {
                    retained[0]?.let { BrandNotice(it, tone = BrandNotice.Tone.Information) }
                }
            }

            state.errorMessage?.let { message ->
                ErrorBanner(message = message, retry = { scope.launch { model.reload() } })
            }
        }
    }
}

/**
 * Le plat en grand, ou sa place tant qu'il n'est pas lu.
 *
 * 300 de large sur la maquette, sur l'écran du choix. En fraction de l'écran
 * plutôt qu'en points : sur un petit téléphone, 300 dp ne laissent que 30 dp de
 * marge de chaque côté et le plat touche presque les bords. La hauteur est
 * connue avant la mesure, pour que rien ne saute sous lui.
 */
@Composable
private fun CoverPlateBlock(model: CoversModel, state: CoversModel.State, plateWidth: Dp) {
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .height(plateWidth / CoverPlate.ratio),
        contentAlignment = Alignment.Center,
    ) {
        val width = minOf(maxWidth, plateWidth)
        val cover = state.cover
        if (cover != null) {
            CoverPlate(
                cover = cover,
                style = model.style(of = cover),
                photo = model.photo(of = cover),
                face = state.face,
                width = width,
                stats = if (state.face == CoverFace.Back) state.covers?.statSelection ?: emptyList() else emptyList(),
                companion = state.covers?.get(state.face.opposite),
                gallery = state.covers?.photos ?: emptyList(),
            )
        } else {
            BrandSkeleton(width = width, height = width / CoverPlate.ratio, cornerRadius = MemoBookSpacing.snug)
        }
    }
}

// MARK: - Les deux onglets

/**
 * « 1ère de couverture » / « 4e de couverture ».
 *
 * Partagé par les quatre écrans du parcours : c'est le même rail, au même
 * endroit, et c'est ce qui fait qu'on ne perd pas le plat qu'on regardait en
 * passant du style à la photo.
 *
 * **Un plat que l'écran ne sait pas régler pâlit au lieu de disparaître** (Hugo,
 * 16/09/2026) : sur l'écran des textes, une quatrième de couverture en photo
 * pleine page n'a pas de texte à écrire ; sur celui des photos, un plat en aplat
 * n'a pas de photo à choisir. Le segment reste lisible et **tapable**, et son
 * appui pose l'explication — la retirer ou la désactiver laisserait chercher
 * pourquoi.
 *
 * @param isAvailable ce plat se règle-t-il sur cet écran. Tout est ouvert par
 *   défaut : les écrans du choix et du style n'ont rien à fermer.
 * @param onUnavailable ce qu'on fait de l'appui sur un plat fermé. `null` sur les
 *   écrans où aucun ne l'est.
 */
@Composable
internal fun CoverFaceTabs(
    face: CoverFace,
    onFaceChange: (CoverFace) -> Unit,
    modifier: Modifier = Modifier,
    isAvailable: (CoverFace) -> Boolean = { true },
    onUnavailable: ((CoverFace) -> Unit)? = null,
) {
    BrandSegmentedPicker(
        CoverFace.entries,
        selection = face,
        onSelectionChange = onFaceChange,
        modifier = modifier,
        size = BrandSegmentedPicker.Size.Compact,
        isAvailable = isAvailable,
        onUnavailable = onUnavailable,
    ) { it.title }
}

// MARK: - Une ligne d'action

/**
 * Une carte qui mène ailleurs : un pictogramme, un libellé, un chevron.
 *
 * Ce n'est pas une `BrandRow` : celles-ci vivent **groupées** dans une coque
 * commune, séparées par un filet, et portent une valeur à droite. Ces trois-ci
 * sont trois cartes distinctes, espacées, avec un pictogramme à gauche et rien à
 * droite — c'est ce que dessine la maquette, et les deux motifs ne se
 * confondent pas.
 *
 * @param isAvailable la ligne mène-t-elle quelque part. **Pâlie et non
 *   désactivée** quand elle ne le fait pas : elle doit rester tapable pour
 *   pouvoir expliquer.
 */
@Composable
private fun CoverActionRow(@DrawableRes icon: Int, title: String, isAvailable: Boolean = true, action: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius)
    val iconSide = scaled(MemoBookSpacing.contentIcon)
    val chevronSide = scaled(14.dp)

    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = action)
            .semantics { if (!isAvailable) stateDescription = "Non disponible" }
            // Figma dessine #E6DAD0 ; `hairline` est l'encre à 10 %, qui tombe à
            // #E6DFD8 sur le crème — trois points d'écart sur un canal. Même
            // arbitrage que les cartes d'extras.
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val dim = Modifier.alpha(if (isAvailable) 1f else 0.45f)
        Image(
            painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = dim.size(iconSide),
        )
        BrandText(title, MemoBookFont.tagline, dim.weight(1f))
        // Le chevron dit « ça mène quelque part » : il part quand ce n'est pas le
        // cas, plutôt que de pâlir en promettant.
        Image(
            painterResource(R.drawable.icon_chevron),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
            modifier = Modifier.size(chevronSide).alpha(if (isAvailable) 1f else 0f),
        )
    }
}

@Preview(locale = "fr-rFR", name = "Choix des couvertures", widthDp = 390, heightDp = 844)
@Composable
private fun CoversViewPreview() {
    CoversView(remember { CoversModel(tripId = "trip-rome") }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Choix des couvertures — police à 200 %", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun CoversViewLargeTextPreview() {
    CoversView(remember { CoversModel(tripId = "trip-rome") }, onIntent = {}, onBack = {})
}
