package com.memobook.feature.covers

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.BookCover
import com.memobook.core.CoverFace
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandNotice
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandTextBox
import com.memobook.design.BrandTextField
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.brandShadow

/**
 * Les textes des couvertures : le titre et la signature du devant, le texte de
 * quatrième et les chiffres du dos. Jumeau de `Covers/CoverTextsView.swift`.
 *
 * **Le plat reste la pièce principale**, et les crayons se posent dessus : on
 * modifie ce qu'on regarde. C'est ce que dessine la maquette, et c'est ce qui
 * distingue cet écran d'un formulaire — un titre de couverture ne se juge pas
 * dans un champ, il se juge sur le plat.
 *
 * ⚠️ **La maquette ne dessine pas l'état « en train d'écrire ».** Elle pose les
 * crayons et s'arrête là. Plutôt que d'inventer une feuille (R3), le crayon
 * **ouvre le champ sous le plat** et lui donne le focus : le plat se met à jour
 * à mesure qu'on tape, donc on ne perd jamais de vue ce qu'on compose, et le
 * clavier a de la place pour monter. Signalé (T89).
 *
 * @param onDismiss le retour, une fois « Valider » touché — le `dismiss()` d'iOS.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CoverTextsView(model: CoversModel, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()

    // Le champ **ouvert** par un crayon, s'il y en a un.
    //
    // ⚠️ **Distinct du focus, et c'est ce qui manquait sur iOS.** Le crayon
    // posait directement le focus ; or le champ n'existe à l'écran *que*
    // lorsqu'il est ouvert, et un crayon sur deux ne faisait rien (Hugo,
    // 15/09/2026). On ouvre donc le champ, et c'est lui qui prend le focus en
    // apparaissant — `BrandTextField` le demande dès qu'il est composé.
    var editing by remember { mutableStateOf<CoverTextField?>(null) }

    // Le focus du champ du titre. Il suit `editing`, il ne le décide pas.
    var focus by remember { mutableStateOf<CoverTextField?>(null) }

    // Le focus du cadre de texte, qui ne connaît qu'un booléen.
    var isWritingSubtitle by remember { mutableStateOf(false) }

    var title by rememberSaveable { mutableStateOf("") }
    var subtitle by rememberSaveable { mutableStateOf("") }
    var isChoosingStats by remember { mutableStateOf(false) }

    // Le plat sur lequel on vient de taper alors qu'il n'a pas de texte. `null`
    // le reste du temps — voir `CoverFaceTabs`.
    var blockedFace by remember { mutableStateOf<CoverFace?>(null) }

    // Ce plat porte-t-il un texte ? Ouvert par défaut : on ne ferme pas un geste
    // parce qu'on n'a pas encore lu les couvertures.
    fun acceptsText(face: CoverFace): Boolean = state.covers?.acceptsText(face) ?: true

    // Ce plat imprime-t-il les chiffres du voyage ?
    fun acceptsStats(face: CoverFace): Boolean = state.covers?.acceptsStats(face) ?: (face == CoverFace.Back)

    // Il y a quelque chose à écrire sur ce plat — un texte, ou le choix des
    // chiffres : le dos « Par défaut » n'a pas de texte de quatrième, mais ses
    // chiffres se choisissent ici.
    fun hasSomethingToWrite(face: CoverFace): Boolean = acceptsText(face) || acceptsStats(face)

    fun readTexts() {
        val cover = model.cover ?: return
        title = cover.title
        subtitle = cover.subtitle
    }

    /**
     * Ouvre le champ d'un crayon. Un second appui sur le même crayon rend le
     * focus au champ déjà ouvert plutôt que de le refermer et le rouvrir.
     */
    fun open(field: CoverTextField) {
        editing = field
        when (field) {
            CoverTextField.Title -> focus = CoverTextField.Title
            CoverTextField.Subtitle -> isWritingSubtitle = true
        }
    }

    fun close() {
        focus = null
        isWritingSubtitle = false
        editing = null
    }

    LaunchedEffect(model) {
        model.load()
        readTexts()
    }
    LaunchedEffect(state.cover?.title) { readTexts() }
    // Changer de plat ferme le champ ouvert : le titre du devant et le texte du
    // dos ne se corrigent pas dans le même champ. Et l'explication, qui parlait
    // de l'autre plat.
    var shownFace by remember { mutableStateOf(state.face) }
    LaunchedEffect(state.face) {
        if (state.face == shownFace) return@LaunchedEffect
        shownFace = state.face
        close()
        readTexts()
        blockedFace = null
    }

    // **Ce qu'on tape ne passe jamais sous le clavier.** Le champ s'ouvre sous
    // le plat, tout en bas de l'écran : sans ça, le clavier montait par-dessus et
    // on écrivait à l'aveugle (Hugo, 16/09/2026). **On écoute le clavier**
    // (Hugo, 06/10/2026, T138) au lieu d'attendre au jugé : c'est quand il a pris
    // sa place qu'on amène le champ — et de nouveau quand on passe du titre au
    // texte, le clavier déjà monté.
    val fieldsRequester = remember { BringIntoViewRequester() }
    val isKeyboardShown = WindowInsets.isImeVisible
    LaunchedEffect(isKeyboardShown, editing) {
        if (editing == null || !isKeyboardShown) return@LaunchedEffect
        // Après la passe en cours : un champ qui vient d'apparaître n'a pas
        // encore sa place.
        withFrameNanos {}
        fieldsRequester.bringIntoView()
    }

    CompositionLocalProvider(LocalRefreshCoverPhotos provides { model.refreshPhotoLinks() }) {
        Column(
            modifier
                .fillMaxSize()
                .background(MemoBookColor.background)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l)
                .animateContentSize(SwiftMotion.snappy(0.25f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            BrandScreenHeader(BookCopy.Covers.title, onBack = onDismiss, subtitle = BookCopy.Covers.textsSubtitle)

            // **Le plat sans texte pâlit dans le rail** (Hugo, 16/09/2026) : une
            // quatrième de couverture en photo pleine page n'a rien à écrire, et
            // l'écran n'y proposait aucun crayon sans jamais dire pourquoi. Le
            // segment reste tapable et pose l'explication.
            CoverFaceTabs(
                state.face,
                onFaceChange = model::setFace,
                isAvailable = ::hasSomethingToWrite,
                onUnavailable = { blockedFace = it },
            )

            TextsPlate(
                state = state,
                model = model,
                draft = { cover -> cover.copy(title = title, subtitle = subtitle) },
                acceptsText = acceptsText(state.face),
                acceptsStats = acceptsStats(state.face),
                onEditTitle = { open(CoverTextField.Title) },
                onEditSubtitle = { open(CoverTextField.Subtitle) },
                onEditStats = { isChoosingStats = true },
            )

            val retainedFace = remember { arrayOfNulls<CoverFace>(1) }
            blockedFace?.let { retainedFace[0] = it }
            AnimatedVisibility(blockedFace != null, enter = fadeIn(), exit = fadeOut()) {
                retainedFace[0]?.let { BrandNotice(BookCopy.Covers.noTextHere(it), tone = BrandNotice.Tone.Information) }
            }

            // Le champ ouvert par un crayon.
            //
            // Un seul à la fois, et seulement pendant qu'on écrit : deux champs
            // posés en permanence auraient fait de cet écran un formulaire avec
            // une vignette, alors que c'est une couverture avec des crayons.
            //
            // Le titre est une **valeur** — un mot, deux au plus — donc un
            // `BrandTextField`. Le sous-titre est un **texte** — la signature au
            // devant, le paragraphe de quatrième au dos — donc un `BrandTextBox`.
            Box(Modifier.bringIntoViewRequester(fieldsRequester)) {
                when (editing) {
                    // L'icône « clavier bas », comme sur le texte : sans elle,
                    // rien ne rangeait le clavier ouvert sur le titre (Clara,
                    // 17/09/2026). `BrandTextBox` porte déjà la sienne.
                    CoverTextField.Title -> BrandKeyboardDismissBar {
                        BrandTextField(
                            BookCopy.Covers.Voice.editTitle,
                            value = title,
                            onValueChange = { title = it },
                            field = CoverTextField.Title,
                            focus = focus,
                            // Refermer le clavier referme le champ, sinon il reste
                            // ouvert et vide sous le plat. Chaque champ ne referme
                            // que **le sien** : quand on passe du titre à la
                            // signature, le focus du premier retombe à `null`
                            // pendant que le second s'ouvre, et ce n'est pas une
                            // fermeture.
                            onFocusChange = { field ->
                                focus = field
                                if (field == null && editing == CoverTextField.Title) editing = null
                            },
                            labelPlacement = BrandTextField.LabelPlacement.Above,
                        )
                    }
                    CoverTextField.Subtitle -> BrandTextBox(
                        BookCopy.Covers.Voice.editSubtitle,
                        value = subtitle,
                        onValueChange = { subtitle = it },
                        isFocused = isWritingSubtitle,
                        onFocusChange = { isWriting ->
                            isWritingSubtitle = isWriting
                            if (!isWriting && editing == CoverTextField.Subtitle) editing = null
                        },
                        // La signature du devant tient en deux lignes, le texte de
                        // quatrième en dix : le cadre part de la bonne hauteur
                        // plutôt que d'en imposer une aux deux.
                        minimumHeight = if (state.face == CoverFace.Front) 72.dp else 133.dp,
                        lineSpan = if (state.face == CoverFace.Front) 2..4 else 4..10,
                    )
                    null -> Unit
                }
            }

            BrandButton(
                BookCopy.Covers.validate,
                fillsWidth = true,
                enabled = state.covers != null && hasSomethingToWrite(state.face),
            ) {
                model.setTexts(title = title, subtitle = subtitle)
                onDismiss()
            }
        }
    }

    BrandSheetHost(isPresented = isChoosingStats, onDismissRequest = { isChoosingStats = false }) {
        CoverStatsSheet(model, onDismiss = { isChoosingStats = false })
    }
}

/** Le champ qu'un crayon ouvre. */
private enum class CoverTextField { Title, Subtitle }

/**
 * Le plat, et ses crayons. 260 de large, en fraction de l'écran plutôt qu'en
 * points sur un petit téléphone.
 */
@Composable
private fun TextsPlate(
    state: CoversModel.State,
    model: CoversModel,
    draft: (BookCover) -> BookCover,
    acceptsText: Boolean,
    acceptsStats: Boolean,
    onEditTitle: () -> Unit,
    onEditSubtitle: () -> Unit,
    onEditStats: () -> Unit,
) {
    val plateWidth = 260.dp
    BoxWithConstraints(Modifier.fillMaxWidth().height(plateWidth / CoverPlate.ratio), contentAlignment = Alignment.Center) {
        val width = minOf(maxWidth, plateWidth)
        val cover = state.cover
        if (cover != null) {
            CoverPlate(
                // Le plat lit le **brouillon**, pas la valeur enregistrée : c'est
                // ce qui fait qu'on voit son titre se composer pendant qu'on le
                // tape.
                cover = draft(cover),
                style = model.style(of = cover),
                photo = model.photo(of = cover),
                face = state.face,
                width = width,
                stats = if (state.face == CoverFace.Back) state.covers?.statSelection ?: emptyList() else emptyList(),
                companion = state.covers?.get(state.face.opposite),
                gallery = state.covers?.photos ?: emptyList(),
                titleBadge = if (state.face == CoverFace.Front) {
                    { Pencil(BookCopy.Covers.Voice.editTitle, onEditTitle) }
                } else {
                    null
                },
                // **Le texte de dos a son crayon aussi**, en haut à droite du
                // texte (Hugo, 17/09/2026, T90) : la maquette n'en posait qu'un,
                // sur le bandeau des chiffres, mais la FAQ promet « titre, visuel
                // et texte de dos ». Il ne se pose pas sur un plat qui n'a pas de
                // texte — la photo pleine page —, le plat pâlit alors et
                // l'explique.
                subtitleBadge = if (acceptsText) {
                    { Pencil(BookCopy.Covers.Voice.editSubtitle, onEditSubtitle) }
                } else {
                    null
                },
                // Les chiffres, sur les dos qui les impriment : deux gabarits sur
                // sept (08/10/2026).
                statsBadge = if (acceptsStats) {
                    { Pencil(BookCopy.Covers.Voice.editStats, onEditStats) }
                } else {
                    null
                },
            )
        } else {
            BrandSkeleton(width = width, height = width / CoverPlate.ratio, cornerRadius = MemoBookSpacing.snug)
        }
    }
}

/**
 * Le crayon posé sur une zone du plat.
 *
 * Il **déborde** du bloc qu'il commande, comme la maquette : posé dedans, il se
 * serait confondu avec le dessin de la couverture. Le dessin fait 32, la cible
 * 48 (R7).
 */
@Composable
private fun Pencil(label: String, action: () -> Unit) {
    val side = 32.dp
    Box(
        Modifier
            .offset(x = side / 2, y = -side / 4)
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(side)
                .brandShadow(MemoBookShadow.Soft, CircleShape)
                .background(MemoBookColor.surface, CircleShape)
                .border(1.5.dp, MemoBookColor.outline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(R.drawable.icon_pen),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.action),
                modifier = Modifier.size(MemoBookSpacing.s),
            )
        }
    }
}

@Preview(locale = "fr-rFR", name = "Couvertures — textes", widthDp = 390, heightDp = 844)
@Composable
private fun CoverTextsViewPreview() {
    CoverTextsView(remember { CoversModel(tripId = "trip-rome") }, onDismiss = {})
}

@Preview(locale = "fr-rFR", name = "Couvertures — textes — police à 200 %", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun CoverTextsViewLargeTextPreview() {
    CoverTextsView(remember { CoversModel(tripId = "trip-rome") }, onDismiss = {})
}
