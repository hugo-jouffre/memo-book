package com.memobook.feature.covers

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.BookCover
import com.memobook.core.CoverFace
import com.memobook.core.CoverPhoto
import com.memobook.core.CoverStyle
import com.memobook.design.BrandButton
import com.memobook.design.BrandNotice
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.feature.PhotoFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Les deux carrousels : celui des styles et celui des photos. Jumeau de
 * `Covers/CoverCarouselView.swift`.
 *
 * **Un seul écran pour les deux maquettes.** Elles ne diffèrent que par ce
 * qu'on fait défiler — sept plats dessinés d'un côté, cinq photos et une case
 * d'import de l'autre — et par le sous-titre. Tout le reste est identique :
 * l'en-tête, les onglets, la file au centre, la pastille cochée, le bouton du
 * bas. Deux écrans auraient eu à rester d'accord sur le rythme du défilement, et
 * le second aurait vieilli le premier.
 *
 * **Ce qui est au centre est ce qui est choisi.** Pas de sélection au tapotis
 * séparée du défilement : la maquette agrandit le plat du milieu et le coiffe
 * d'une coche, ce qui dit exactement ça. Toucher un plat voisin l'amène au
 * centre, ce qui revient au même geste.
 *
 * @param onDismiss le retour, une fois « Valider » touché — le `dismiss()` d'iOS.
 */
@Composable
fun CoverCarouselView(kind: CoverCarouselView.Kind, model: CoversModel, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Ce qui est au centre. Un identifiant et non un index : la liste des photos
    // s'allonge quand on en importe une.
    var centred by remember { mutableStateOf<String?>(null) }
    var importProblem by remember { mutableStateOf<String?>(null) }

    // Le plat sur lequel on vient de taper alors qu'il ne porte pas de photo.
    var blockedFace by remember { mutableStateOf<CoverFace?>(null) }

    val listState = rememberLazyListState()
    val items = CoverCarouselView.items(kind, state)

    // Ce plat porte-t-il une photo ? Ouvert par défaut : on ne ferme pas un
    // geste parce qu'on n'a pas encore lu les couvertures.
    fun acceptsPhoto(face: CoverFace): Boolean = state.covers?.acceptsPhoto(face) ?: true

    /**
     * Pose le plat du milieu sur la couverture, sans l'envoyer : c'est
     * « Valider » qui écrit. Faire défiler sept styles ne doit pas écrire sept
     * fois au serveur.
     */
    fun select(id: String?) {
        id ?: return
        when (kind) {
            CoverCarouselView.Kind.Style -> model.styles.firstOrNull { it.id == id }?.let(model::preview)
            // La case d'import ne **retire** pas la photo en cours : on la
            // regarde, on choisit, et c'est le choix qui remplace. Poser `null`
            // ici aurait vidé le plat dès qu'on fait défiler jusqu'au bout.
            CoverCarouselView.Kind.Photo -> if (id != CoverCarouselItem.ImportSlot.id) model.preview(photo = model.covers?.photo(id))
        }
    }

    /** Amène une case au centre, et la choisit. */
    fun centre(id: String?, animated: Boolean) {
        centred = id
        select(id)
        val index = CoverCarouselView.items(kind, model.state.value).indexOfFirst { it.id == id }
        if (index < 0) return
        scope.launch { if (animated) listState.animateScrollToItem(index) else listState.scrollToItem(index) }
    }

    // Le carrousel s'ouvre **sur le plat en cours**, pas au début de la file :
    // arriver sur le premier style donnerait à croire qu'on vient d'en changer.
    //
    // ⚠️ Et il se cale **après** le chargement : avant, la file est vide et il
    // n'y a rien à viser. Posé trop tôt, le carrousel restait sur sa première
    // case et aucune n'était cochée.
    LaunchedEffect(model) {
        model.load()
        centre(CoverCarouselView.currentId(kind, model.state.value), animated = false)
    }
    // Changer de plat recale la file sur le sien, et retire l'explication, qui
    // parlait de l'autre.
    var shownFace by remember { mutableStateOf(state.face) }
    LaunchedEffect(state.face) {
        if (state.face == shownFace) return@LaunchedEffect
        shownFace = state.face
        blockedFace = null
        centre(CoverCarouselView.currentId(kind, model.state.value), animated = false)
    }

    // Le doigt fait défiler la file : ce qui s'arrête au centre est choisi. Les
    // défilements de l'écran lui-même — à l'ouverture, au toucher d'un plat —
    // ne passent pas par ici.
    var isDragging by remember { mutableStateOf(false) }
    val nearestToCentre by remember(listState) { derivedStateOf { CoverCarouselView.nearestToCentre(listState) } }
    val currentItems by rememberUpdatedState(items)
    LaunchedEffect(listState) {
        listState.interactionSource.interactions.collect { if (it is DragInteraction.Start) isDragging = true }
    }
    LaunchedEffect(listState) {
        snapshotFlow { listState.isScrollInProgress }.filter { !it }.collect {
            if (!isDragging) return@collect
            isDragging = false
            val id = currentItems.getOrNull(nearestToCentre ?: return@collect)?.id ?: return@collect
            centred = id
            select(id)
        }
    }
    // Pendant le geste, la coche suit ce qui passe au centre.
    val shownCentre = if (isDragging) nearestToCentre?.let { items.getOrNull(it)?.id } ?: centred else centred

    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        // Envoie la photo importée, la range à côté des autres, et la choisit.
        //
        // Elle est d'abord écrite dans les **caches**, comme les photos du
        // chat : c'est ce qu'on montre pendant que le serveur la reçoit, et ce
        // qui reste en aperçu, où rien ne part. Réduite à 1 600 px de côté avant
        // l'envoi — un carnet se compose sur une image bien plus petite qu'une
        // photo de téléphone (T88, 29/09/2026).
        scope.launch {
            try {
                val data = withContext(Dispatchers.IO) { PhotoFlow.read(context, uri) } ?: return@launch
                val id = "cover-${UUID.randomUUID()}"
                val jpeg = withContext(Dispatchers.Default) { CoverPhotoFile.jpeg(data) } ?: data
                val file = withContext(Dispatchers.IO) { CoverPhotoFile.save(context.cacheDir, jpeg, id) }
                val photo = model.importPhoto(jpeg, fallback = CoverPhoto(id = id, url = file.toURI().toString()))
                model.preview(photo = photo)
                importProblem = null
                centre(photo.id, animated = true)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                importProblem = BookCopy.Covers.importFailed
            }
        }
    }

    CompositionLocalProvider(LocalRefreshCoverPhotos provides { model.refreshPhotoLinks() }) {
        // Une colonne qui défile, et non une simple pile : en taille de texte
        // accessible, l'en-tête sur quatre lignes et les deux boutons pleine
        // largeur dépassent l'écran. Une pile les faisait déborder par le haut au
        // lieu de les laisser défiler. La file des plats, elle, garde son
        // défilement horizontal : les deux ne se marchent pas dessus.
        Column(
            modifier
                .fillMaxSize()
                .background(MemoBookColor.background)
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l)
                .animateContentSize(SwiftMotion.snappy(0.25f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            BrandScreenHeader(
                BookCopy.Covers.title,
                onBack = onDismiss,
                modifier = Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
                subtitle = when (kind) {
                    CoverCarouselView.Kind.Style -> BookCopy.Covers.styleSubtitle
                    CoverCarouselView.Kind.Photo -> BookCopy.Covers.photoSubtitle
                },
            )

            // **Le plat sans photo pâlit dans le rail** (Hugo, 16/09/2026) : un
            // aplat ou un kraft n'en porte aucune, et choisir une image dessus ne
            // changeait rien au plat sans que rien ne le dise. Le segment reste
            // tapable et pose l'explication. Le carrousel des **styles**, lui,
            // n'a rien à fermer : on y va justement pour changer ce style.
            CoverFaceTabs(
                state.face,
                onFaceChange = model::setFace,
                modifier = Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
                isAvailable = { kind == CoverCarouselView.Kind.Style || acceptsPhoto(it) },
                onUnavailable = { blockedFace = it },
            )

            val retainedFace = remember { arrayOfNulls<CoverFace>(1) }
            blockedFace?.let { retainedFace[0] = it }
            AnimatedVisibility(blockedFace != null, enter = fadeIn(), exit = fadeOut()) {
                retainedFace[0]?.let { face ->
                    BrandNotice(
                        BookCopy.Covers.noPhotoHere(face),
                        Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
                        tone = BrandNotice.Tone.Information,
                    )
                }
            }

            Carousel(kind, state, items, listState, shownCentre, onTap = { centre(it, animated = true) })

            importProblem?.let { problem ->
                ErrorBanner(problem, Modifier.padding(horizontal = MemoBookSpacing.screenMargin))
            }

            // Les boutons du bas.
            Column(Modifier.padding(horizontal = MemoBookSpacing.screenMargin), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                // « Choisir la photo » n'apparaît que sur la case d'import : posé
                // en permanence, il ferait concurrence à « Valider » sur les cinq
                // autres plats, où il n'y a rien à choisir.
                AnimatedVisibility(
                    kind == CoverCarouselView.Kind.Photo && shownCentre == CoverCarouselItem.ImportSlot.id,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    // `IconImport` — la flèche qui entre dans le plateau —, et non
                    // `IconTeleverser` : celui-là est bleu, plein, hors de la
                    // grille de 24 (T101), et se lisait comme un partage (Hugo,
                    // 15/09/2026). Importer une photo, c'est ce mot-là, et la case
                    // du carrousel dit déjà « Importer ma photo ».
                    BrandButton(
                        BookCopy.Covers.choosePhoto,
                        icon = painterResource(R.drawable.icon_import),
                        style = BrandButton.Style.Secondary,
                        fillsWidth = true,
                    ) {
                        pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                }

                BrandButton(
                    BookCopy.Covers.validate,
                    fillsWidth = true,
                    enabled = state.covers != null && !(kind == CoverCarouselView.Kind.Photo && !acceptsPhoto(state.face)),
                ) {
                    when (kind) {
                        CoverCarouselView.Kind.Style -> model.commitStyle()
                        CoverCarouselView.Kind.Photo -> model.commitPhoto()
                    }
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - La file

@Composable
private fun Carousel(
    kind: CoverCarouselView.Kind,
    state: CoversModel.State,
    items: List<CoverCarouselItem>,
    listState: LazyListState,
    centred: String?,
    onTap: (String) -> Unit,
) {
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .height(CoverCarouselView.rowHeight)
            .semantics { contentDescription = BookCopy.Covers.Voice.carousel },
    ) {
        // La marge qui amène le premier et le dernier plat **au centre** : sans
        // elle, on ne peut choisir ni l'un ni l'autre, puisqu'aucun des deux ne
        // peut atteindre le milieu de l'écran. Une marge de **contenu**, connue
        // du défilement : le calage au centre la déduit.
        val gutter = max(0f, (maxWidth - CoverCarouselView.plateWidth).value / 2).dp
        LazyRow(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = gutter),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
            verticalAlignment = Alignment.CenterVertically,
            flingBehavior = rememberSnapFlingBehavior(listState, SnapPosition.Center),
        ) {
            items(items, key = { it.id }) { item ->
                CarouselCell(kind, state, item, isSelected = item.id == centred) { onTap(item.id) }
            }
        }
    }
}

@Composable
private fun CarouselCell(
    kind: CoverCarouselView.Kind,
    state: CoversModel.State,
    item: CoverCarouselItem,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    // ⚠️ **L'agrandissement est une transformation de rendu, pas une
    // largeur.** Faire dépendre la largeur de la case du plat sélectionné rend
    // la mise en page circulaire : le plat choisi grandit, ce qui décale toute
    // la file, ce qui change le plat au centre — et le carrousel se cale une
    // case à côté, sans jamais cocher personne. Un `graphicsLayer` ne touche pas
    // au cadre : la file garde son pas, et c'est bien le plat visé qui
    // s'agrandit.
    val scale by animateFloatAsState(if (isSelected) CoverCarouselView.selectedScale else 1f, SwiftMotion.snappy(0.25f), label = "agrandissement")
    // Ce qui n'est pas au centre s'efface : c'est ce qui fait lire le milieu
    // comme le choix, et non comme un plat parmi six.
    val opacity by animateFloatAsState(if (isSelected) 1f else 0.55f, SwiftMotion.snappy(0.25f), label = "effacement")

    val label = when (item) {
        is CoverCarouselItem.StyleItem -> BookCopy.Covers.Voice.style(item.style.name)
        is CoverCarouselItem.PhotoItem -> BookCopy.Covers.Voice.photo
        CoverCarouselItem.ImportSlot -> BookCopy.Covers.importPhoto
    }

    Box(
        Modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                alpha = opacity
            }
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onTap)
            .semantics {
                contentDescription = label
                selected = isSelected
            },
    ) {
        val cover = state.cover
        when (item) {
            is CoverCarouselItem.StyleItem -> Box {
                CarouselPlate(state, style = item.style, photo = cover?.let(state::photo))
                // « Assortie à ta 1ère de couverture » : sur la 4e qui reprend le
                // style **choisi** au devant — et c'est la seule chose que le
                // carrousel dise avec des mots. Elle suit le devant quand on le
                // change (Clara, 17/09/2026), et ne paraît jamais sur les styles
                // de la 1ère (Hugo, 12/10/2026) : `BookCovers.isMatched`.
                if (isSelected && state.covers?.isMatched(item.style, state.face) == true) {
                    MatchedStyleTag(Modifier.align(Alignment.TopCenter).offset(y = -MemoBookSpacing.snug))
                }
            }
            is CoverCarouselItem.PhotoItem -> CarouselPlate(state, style = cover?.let(state::style), photo = item.photo)
            CoverCarouselItem.ImportSlot -> CoverImportSlot(CoverCarouselView.plateWidth)
        }

        // Elle déborde du coin, comme la maquette.
        AnimatedVisibility(
            isSelected,
            modifier = Modifier.align(Alignment.TopEnd).offset(x = MemoBookSpacing.snug, y = -MemoBookSpacing.snug),
            enter = scaleIn() + fadeIn(),
            exit = scaleOut() + fadeOut(),
        ) {
            CoverSelectionBadge()
        }
    }
}

@Composable
private fun CarouselPlate(state: CoversModel.State, style: CoverStyle?, photo: CoverPhoto?) {
    CoverPlate(
        cover = state.cover ?: BookCover(styleId = ""),
        style = style,
        photo = photo,
        face = state.face,
        width = CoverCarouselView.plateWidth,
        stats = if (state.face == CoverFace.Back) state.covers?.statSelection ?: emptyList() else emptyList(),
        companion = state.covers?.get(state.face.opposite),
        gallery = state.covers?.photos ?: emptyList(),
    )
}

/** Les mesures et la file du carrousel, à part du dessin. */
object CoverCarouselView {
    enum class Kind { Style, Photo }

    /**
     * La largeur d'une case de la file : celle d'un plat **au repos**, 13 rem
     * (208), comme la maquette. C'est le pas du carrousel, et il ne change
     * jamais — voir la remarque sur l'agrandissement dans [CarouselCell].
     */
    internal val plateWidth: Dp = 208.dp

    /** De combien le plat choisi grandit. La maquette le dessine à 233 contre 208 : un neuvième de plus. */
    internal const val selectedScale: Float = 232f / 208f

    /**
     * La hauteur réservée à la file. Celle du plat **agrandi**, plus l'air que la
     * pastille cochée prend en débordant du coin haut : sans lui, elle serait
     * rognée par le bord du défilement.
     *
     * Une gouttière **de chaque côté**, et non une pour les deux : la file centre
     * le plat, donc la moitié seulement de l'air va au-dessus de lui. Le haut du
     * rond coché était tranché (Hugo, 15/09/2026).
     */
    internal val rowHeight: Dp get() = plateWidth / CoverPlate.ratio * selectedScale + MemoBookSpacing.m * 2

    /** Ce que la file propose. Les styles pour l'un, les photos plus la case d'import pour l'autre. */
    internal fun items(kind: Kind, state: CoversModel.State): List<CoverCarouselItem> {
        val covers = state.covers ?: return emptyList()
        return when (kind) {
            Kind.Style -> covers.styles(state.face).map { CoverCarouselItem.StyleItem(it) }
            Kind.Photo -> covers.photos.map { CoverCarouselItem.PhotoItem(it) } + CoverCarouselItem.ImportSlot
        }
    }

    /** L'identifiant de ce qui est choisi aujourd'hui sur le plat courant. */
    internal fun currentId(kind: Kind, state: CoversModel.State): String? {
        val cover = state.cover ?: return null
        return when (kind) {
            Kind.Style -> cover.styleId
            Kind.Photo -> cover.photoId ?: CoverCarouselItem.ImportSlot.id
        }
    }

    /** L'index de la case la plus proche du milieu de la file, d'après ce qu'elle a posé. */
    internal fun nearestToCentre(listState: LazyListState): Int? {
        val layout = listState.layoutInfo
        val centre = (layout.viewportStartOffset + layout.viewportEndOffset) / 2
        return layout.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - centre) }?.index
    }
}

// MARK: - Ce que la file propose

/** Une case du carrousel. */
sealed interface CoverCarouselItem {
    val id: String

    data class StyleItem(val style: CoverStyle) : CoverCarouselItem {
        override val id: String get() = style.id
    }

    data class PhotoItem(val photo: CoverPhoto) : CoverCarouselItem {
        override val id: String get() = photo.id
    }

    /** La dernière case du carrousel des photos : « Importer ma photo ». */
    data object ImportSlot : CoverCarouselItem {
        override val id: String get() = "cover.import"
    }
}

/**
 * « Assortie à ta 1ère de couverture », posée au-dessus du plat qui reprend le
 * style choisi de l'autre côté.
 */
@Composable
private fun MatchedStyleTag(modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(percent = 50)
    BrandText(
        BookCopy.Covers.matchedStyle,
        MemoBookFont.mention,
        modifier
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.outline, shape)
            .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs / 2),
        color = MemoBookColor.blueText,
        maxLines = 1,
    )
}

/** La case d'import : un aplat, un pictogramme, et le mot qui dit quoi faire. */
@Composable
private fun CoverImportSlot(width: Dp) {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    Column(
        Modifier
            .size(width, width / CoverPlate.ratio)
            .background(MemoBookColor.separator.copy(alpha = 0.4f), shape)
            .border(1.dp, MemoBookColor.hairline, shape),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            painterResource(R.drawable.icon_picture_frame),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(MemoBookSpacing.l),
        )
        BrandText(
            BookCopy.Covers.importPhoto,
            MemoBookFont.tagline,
            Modifier
                .background(MemoBookColor.surface, RoundedCornerShape(percent = 50))
                .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs),
        )
    }
}

/**
 * Où vit une photo de couverture importée, le temps qu'on la regarde.
 *
 * Dans les caches et non dans les fichiers de l'app, comme `ChatPhotoFile` et
 * pour la même raison : ce n'est que du transit, et rien de tout cela n'a à
 * partir dans une sauvegarde.
 */
internal object CoverPhotoFile {
    /** Le plus grand côté envoyé au serveur. */
    private const val UPLOAD_SIDE = 1600

    /**
     * Réduit la photo choisie en JPEG, à ce dont une couverture a besoin. `null`
     * si ce n'est pas une image lisible.
     *
     * L'orientation EXIF est appliquée, comme le fait `UIImage` en se dessinant :
     * une photo prise en portrait ne doit pas se coucher. Le décodage saute des
     * pixels d'avance (`inSampleSize`) quand l'image est bien plus grande que ce
     * qu'on garde — un garde-fou de mémoire qu'iOS n'a pas à prendre.
     */
    fun jpeg(data: ByteArray): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= UPLOAD_SIDE) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        val upright = decoded.uprighted(runCatching { ExifInterface(ByteArrayInputStream(data)) }.getOrNull())
        val longest = max(upright.width, upright.height)
        val scale = min(1f, UPLOAD_SIDE.toFloat() / max(longest, 1))
        val resized = if (scale < 1f) {
            Bitmap.createScaledBitmap(upright, (upright.width * scale).roundToInt(), (upright.height * scale).roundToInt(), true)
        } else {
            upright
        }
        return ByteArrayOutputStream().use { out ->
            resized.compress(Bitmap.CompressFormat.JPEG, PhotoFlow.JPEG_QUALITY, out)
            out.toByteArray()
        }
    }

    private fun Bitmap.uprighted(exif: ExifInterface?): Bitmap {
        val orientation = exif?.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            ?: ExifInterface.ORIENTATION_NORMAL
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> matrix.apply { postRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> matrix.apply { postRotate(270f); postScale(-1f, 1f) }
            else -> return this
        }
        return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
    }

    private fun directory(cacheDirectory: File) = File(cacheDirectory, "CoverPhotos")

    @Throws(IOException::class)
    fun save(cacheDirectory: File, data: ByteArray, id: String): File {
        val directory = directory(cacheDirectory)
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Impossible de créer ${directory.path}")
        val file = File(directory, "$id.jpg")
        // Écrit à côté puis renommé : le `.atomic` d'iOS.
        val partial = File(directory, "$id.jpg.part")
        partial.writeBytes(data)
        if (!partial.renameTo(file)) {
            partial.delete()
            throw IOException("Impossible d’écrire ${file.path}")
        }
        return file
    }
}

@Preview(locale = "fr-rFR", name = "Couvertures — styles", widthDp = 390, heightDp = 844)
@Composable
private fun CoverCarouselStylePreview() {
    CoverCarouselView(CoverCarouselView.Kind.Style, remember { CoversModel(tripId = "trip-rome") }, onDismiss = {})
}

@Preview(locale = "fr-rFR", name = "Couvertures — photos", widthDp = 390, heightDp = 844)
@Composable
private fun CoverCarouselPhotoPreview() {
    CoverCarouselView(CoverCarouselView.Kind.Photo, remember { CoversModel(tripId = "trip-rome") }, onDismiss = {})
}
