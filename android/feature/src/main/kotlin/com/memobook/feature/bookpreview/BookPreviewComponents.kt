package com.memobook.feature.bookpreview

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import com.memobook.core.BookCopy
import com.memobook.core.BookCovers
import com.memobook.core.CoverFace
import com.memobook.design.BrandButton
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.scaled
import com.memobook.feature.covers.CoverPlate
import com.memobook.feature.trip.dimmedWhileAwaitingServer

// Les blocs que la composition et l'aperçu partagent. Jumeau de
// `BookPreview/BookPreviewComponents.swift`.
//
// Ils sont ici et non dans chaque écran pour une raison de dessin et non de
// rangement : les deux écrans doivent poser **exactement** les mêmes boutons au
// même endroit, sinon le passage de l'un à l'autre les fait sauter. Un
// composant commun est la seule façon d'en être sûr.

/**
 * Les deux appels à l'action du carnet : le personnaliser, ou le commander.
 *
 * Le secondaire au-dessus du primaire, comme la maquette : « Personnaliser »
 * est ce qu'on fait plusieurs fois, « Commander » est ce qu'on fait une fois.
 * Le geste répété se pose donc sous le pouce en premier.
 *
 * @param isComposed le carnet est composé et peut partir à l'impression. **Il
 *   ne dit plus « le PDF est rasterisé ».** Les deux boutons étaient gris tant
 *   que le document n'avait pas de feuilles — c'est-à-dire tant que l'app
 *   n'avait pas fini de dessiner les pages, et *pour toujours* quand le PDF ne
 *   se chargeait pas. On ne pouvait alors ni commander un carnet que le serveur
 *   déclarait prêt, ni même aller changer son style, ce qui ne demande rien du
 *   tout.
 * @param isAwaitingServer le voyage n'est pas encore arrivé au serveur (T239) :
 *   les trois portes pâlissent et restent tapables — c'est à leurs actions de
 *   dire pourquoi. Absent d'iOS, où l'on n'arrive pas ici sans serveur.
 */
@Composable
internal fun BookActionsBlock(
    isComposed: Boolean,
    onCustomise: () -> Unit,
    onOrder: () -> Unit,
    modifier: Modifier = Modifier,
    isAwaitingServer: Boolean = false,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        // **Toujours actif.** Personnaliser son carnet ne demande ni rendu, ni
        // PDF, ni réseau : c'est un écran de réglages, et c'est souvent en
        // attendant la composition qu'on a envie d'y aller.
        BrandButton(
            BookCopy.Preview.customise,
            modifier = Modifier.dimmedWhileAwaitingServer(isAwaitingServer),
            style = BrandButton.Style.Secondary,
            fillsWidth = true,
            action = onCustomise,
        )

        // ⚠️ Il y avait ici « Configurer mes couvertures », en lien sous le
        // bouton de personnalisation. Retiré (Hugo, 19/09/2026) : les
        // couvertures se choisissent **sur la page**, en touchant le voile de
        // la première ou de la dernière — voir `CoverInvitation` —, et ce lien
        // disait une seconde fois ce que la page proposait déjà.

        // Commander demande, lui, un carnet composé : on ne fait pas imprimer
        // ce qui n'existe pas encore.
        BrandButton(
            BookCopy.Preview.order,
            modifier = Modifier.dimmedWhileAwaitingServer(isAwaitingServer),
            icon = painterResource(R.drawable.icon_deliver),
            style = BrandButton.Style.Primary,
            fillsWidth = true,
            enabled = isComposed,
            action = onOrder,
        )

        // **La porte de service**, et seulement quand le bouton du dessus est
        // fermé : elle ouvre quand même le tunnel de commande.
        //
        // Elle est **dans la version livrée** et non réservée au debug (Hugo,
        // 16/09/2026) : le tunnel se teste sur une version de test, qui est un
        // build Release — une porte compilée en debug seulement ne s'ouvre
        // nulle part où l'on en a besoin. Son dessin la range à sa place : un
        // lien souligné, sans fond ni contour. On ne peut pas la confondre avec
        // l'appel à l'action juste au-dessus.
        //
        // **À l'encre, et un cran plus grande** (Hugo, 06/10/2026, T219) : en
        // beige au corps d'une légende, elle était presque invisible pendant la
        // composition — c'est-à-dire justement quand elle sert. 14 au lieu de
        // 12, la graisse courante.
        AnimatedVisibility(
            visible = !isComposed,
            enter = fadeIn(SwiftMotion.snappy(0.25f)) + expandVertically(SwiftMotion.snappy(0.25f)),
            exit = fadeOut(SwiftMotion.snappy(0.25f)) + shrinkVertically(SwiftMotion.snappy(0.25f)),
        ) {
            val interaction = remember { MutableInteractionSource() }
            Box(
                Modifier
                    .fillMaxWidth()
                    // Le dessin fait une ligne, la cible 48 dp : R7.
                    .heightIn(min = MemoBookSpacing.minimumTapTarget)
                    .dimmedWhileAwaitingServer(isAwaitingServer)
                    .clickable(interactionSource = interaction, indication = PlainButtonIndication, role = Role.Button, onClick = onOrder),
                contentAlignment = Alignment.Center,
            ) {
                BrandText(
                    BookCopy.Preview.orderAnyway,
                    MemoBookFont.taglineRegular.copy(textDecoration = TextDecoration.Underline),
                    color = MemoBookColor.ink,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/**
 * Une feuille du carnet : la page du PDF, ou **le plat choisi** quand c'est la
 * première ou la dernière et que les couvertures sont réglées.
 *
 * **Les couvertures se voient dans l'aperçu** (Hugo, 06/10/2026, T223) : le
 * PDF n'imprime pas encore les plats choisis — la génération ignore les
 * couvertures, et c'est assumé tant que cette partie n'est pas écrite —, et
 * l'aperçu montrait donc une couverture par défaut juste après qu'on avait
 * réglé la sienne. Le plat est celui des écrans des couvertures ([CoverPlate]),
 * au même rapport A5 que la page : c'est la même image qui sortira du gabarit
 * le jour où il les rendra.
 *
 * Elle sert l'aperçu, le plein écran et sa bande de miniatures : une même
 * feuille doit y montrer la même chose.
 */
@Composable
internal fun BookSheetFace(
    renderer: BookPageRenderer,
    state: BookPreviewModel.State,
    index: Int,
    modifier: Modifier = Modifier,
) {
    val face = state.coverFace(index)
    val covers = state.covers
    if (face != null && covers != null) {
        BookCoverSheet(covers, face, modifier)
    } else {
        BookSheetImage(renderer, state.document, index, modifier)
    }
}

/** Un plat de couverture qui occupe la place d'une page, centré. */
@Composable
internal fun BookCoverSheet(covers: BookCovers, face: CoverFace, modifier: Modifier = Modifier) {
    // Une image de couverture : TalkBack lit le titre de l'écran et le bouton
    // « Configurer », pas un plat qu'il ne saurait décrire.
    BoxWithConstraints(modifier.clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        // La plus grande largeur qui tienne dans la boîte : le plat garde son
        // rapport A5, comme la page qu'il remplace.
        val width = min(maxWidth, maxHeight * CoverPlate.ratio)
        val cover = covers[face]

        CoverPlate(
            cover = cover,
            style = covers.style(cover.styleId),
            photo = covers.photo(cover.photoId),
            face = face,
            width = width,
            stats = if (face == CoverFace.Back) covers.statSelection else emptyList(),
            companion = covers[face.opposite],
            gallery = covers.photos,
        )
    }
}

/**
 * Une flèche de page : un chevron dans un rond cerclé.
 *
 * Elle **garde sa place quand elle ne sert à rien** — page 1 pour la
 * précédente, dernière page pour la suivante — au lieu de disparaître : les
 * trois éléments de l'indicateur sont centrés ensemble, et en retirer un
 * recentrerait les deux autres à chaque bout du carnet.
 */
@Composable
internal fun BookPageArrow(
    direction: BookPageArrowDirection,
    label: String,
    isEnabled: Boolean,
    action: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val side = scaled(31.dp)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            // La cible reste à 48 dp même quand le rond fait 31 : le dessin
            // est plus petit que le geste (R7).
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = interaction,
                indication = PlainButtonIndication,
                enabled = isEnabled,
                role = Role.Button,
                onClick = action,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(side)
                .border(
                    1.dp,
                    if (isEnabled) MemoBookColor.hairline else MemoBookColor.hairline.copy(alpha = MemoBookColor.hairline.alpha * 0.5f),
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painter = painterResource(R.drawable.icon_chevron),
                contentDescription = null,
                colorFilter = ColorFilter.tint(if (isEnabled) MemoBookColor.ink else MemoBookColor.inkFaint),
                modifier = Modifier
                    .size(side * 0.45f)
                    // Le chevron du design system pointe à droite ; celui de
                    // gauche est le même retourné. Pas deux images pour un miroir.
                    .rotate(if (direction == BookPageArrowDirection.Backward) 180f else 0f),
            )
        }
    }
}

/** Le sens d'une [BookPageArrow] — le `BookPageArrow.Direction` d'iOS. */
internal enum class BookPageArrowDirection { Backward, Forward }

/**
 * La commande qui passe l'aperçu en plein écran, et celle qui en revient.
 *
 * Un rond bleu clair posé sur la page, comme la maquette : la page est du
 * papier, la commande n'en fait pas partie et doit se voir comme ajoutée.
 */
@Composable
internal fun BookScreenModeButton(@DrawableRes icon: Int, label: String, action: () -> Unit, modifier: Modifier = Modifier) {
    val side = min(scaled(36.dp), 52.dp)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = interaction, indication = PlainButtonIndication, role = Role.Button, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(painter = painterResource(icon), contentDescription = null, modifier = Modifier.size(side))
    }
}

