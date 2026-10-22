package com.memobook.feature.bookpreview

import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import com.memobook.core.BookCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.feature.LocalTravellerFirstName

/**
 * Le mot des fondateurs : deux personnes qui parlent, au milieu d'une app.
 * Jumeau de `BookPreview/FoundersNoteSheet.swift`.
 *
 * **Elle s'ouvre toute seule**, une fois, une douzaine de secondes après le
 * premier aperçu d'un carnet — et c'est tout son intérêt. Personne ne va
 * chercher un mot des fondateurs dans un menu ; il n'a de valeur que s'il
 * arrive au moment où l'on vient de voir ce que l'app sait faire.
 *
 * **La maquette du 12/10/2026** (« Claude Import », `3709:17115`) : la photo ne
 * dépasse plus au-dessus de la feuille, elle se pose **sur la ligne du titre**,
 * penchée, cerclée de blanc ; la lettre passe au corps de 14. Trois choses la
 * distinguent toujours des autres feuilles de l'app, et aucune n'est
 * décorative :
 *
 * 1. **La photo est penchée**, cerclée de blanc, avec deux ombres. C'est une
 *    photo collée sur une page, pas un avatar dans une liste.
 * 2. **Une ligne est écrite à la main**, en vert. C'est la promesse de
 *    MemoBook, et c'est la seule phrase manuscrite de l'app.
 * 3. **La signature est un dessin**, pas du texte. Un nom tapé sous un mot
 *    manuscrit annulerait tout ce qui précède.
 *
 * Le prénom du compte, pour le bonjour, vient de la session
 * ([LocalTravellerFirstName]) et non du serveur : la feuille ne doit pas
 * attendre un aller-retour pour dire bonjour.
 */
@Composable
internal fun FoundersNoteSheet(onFeedback: () -> Unit, onContinue: () -> Unit) {
    val firstName = LocalTravellerFirstName.current
    val dismiss = LocalBrandSheetDismiss.current

    BrandSheet(BookCopy.Founders.title, leading = { FoundersPhoto() }) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                FoundersLetter(firstName)
                FoundersSignature()
            }

            // Les deux boutons de 16 sur 48 de la maquette (`Medium`), l'un sous l'autre.
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                // **Le formulaire de l'app, et non un courrier** (Hugo,
                // 19/09/2026). Le bouton ouvrait `mailto:` : on quittait
                // MemoBook pour une app de mail qui n'est pas toujours
                // configurée, avec un message vide et un objet prérempli. Or
                // l'app a déjà un endroit où l'on écrit à l'équipe — celui du
                // support, avec son champ, son envoi et sa confirmation. C'est
                // lui qui s'ouvre, et la feuille se referme d'abord pour qu'il
                // prenne sa place. **Et le message part vraiment** (T226,
                // 06/10/2026) : marqué `founders_note`, avec le voyage du
                // carnet — voir `BookPreviewFlowView`.
                BrandButton(
                    BookCopy.Founders.feedback,
                    style = BrandButton.Style.Secondary,
                    size = BrandButton.Size.Medium,
                    fillsWidth = true,
                ) {
                    dismiss()
                    onFeedback()
                }

                BrandButton(
                    BookCopy.Founders.carryOn,
                    style = BrandButton.Style.Primary,
                    size = BrandButton.Size.Medium,
                    fillsWidth = true,
                ) {
                    dismiss()
                    onContinue()
                }
            }
        }
    }
}

/** Le diamètre de la photo. **Fixe, hors taille de police** : une photo n'est pas du texte, et elle partage sa ligne avec le titre. */
private val PHOTO_SIDE = 84.dp

/** Le carré que la photo penchée occupe sur la ligne : ses coins tournés débordent du cercle (93,7 dans la maquette). */
private val PHOTO_SLOT = 94.dp

/** Le bleu-noir des deux ombres de la maquette. */
private val PHOTO_SHADOW = Color(red = 0.106f, green = 0.165f, blue = 0.212f).copy(alpha = 0.2f)

@Composable
private fun FoundersPhoto() {
    Box(
        Modifier
            .size(PHOTO_SLOT)
            .semantics { contentDescription = BookCopy.Founders.signatureVoice },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.photo_founders),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .rotate(7.1f)
                // Les deux ombres de la maquette : une large et diffuse qui la
                // détache du fond, une courte et décalée qui la pose. C'est le
                // seul endroit de l'app où deux ombres se superposent, parce que
                // c'est le seul objet qui est *collé* sur la page.
                .dropShadow(CircleShape, Shadow(radius = 12.dp, color = PHOTO_SHADOW))
                .dropShadow(CircleShape, Shadow(radius = 3.dp, color = PHOTO_SHADOW, offset = DpOffset(1.5.dp, 3.dp)))
                .size(PHOTO_SIDE)
                .clip(CircleShape)
                .border(0.75.dp, MemoBookColor.surface, CircleShape),
        )
    }
}

/** Le corps de 14 de la maquette, paragraphe après paragraphe — un blanc de 8 entre chacun, la ligne manuscrite prise dans le même pas. */
@Composable
private fun FoundersLetter(firstName: String?) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        FoundersParagraph(BookCopy.Founders.hello(firstName))
        FoundersParagraph(BookCopy.Founders.intro)

        // La ligne manuscrite, légèrement de travers. Un degré d'inclinaison,
        // comme la maquette : c'est ce qui la sort du gabarit sans la rendre
        // difficile à lire. La rotation est **après** le dimensionnement pour
        // que la phrase garde toute la largeur disponible.
        BrandText(
            BookCopy.Founders.promise,
            MemoBookFont.handwriting,
            Modifier
                .fillMaxWidth()
                .rotate(-1f),
            color = MemoBookColor.action,
        )

        BookCopy.Founders.body.forEach { FoundersParagraph(it) }
    }
}

@Composable
private fun FoundersParagraph(text: String) {
    BrandText(text, MemoBookFont.taglineRegular, Modifier.fillMaxWidth(), color = MemoBookColor.ink)
}

@Composable
private fun FoundersSignature() {
    Column(
        Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "${BookCopy.Founders.signatureVoice}, ${BookCopy.Founders.signature}" },
    ) {
        // La signature garde sa taille : c'est un dessin, et un paraphe qui
        // grandit avec le corps de texte devient un logo.
        Image(
            painter = painterResource(R.drawable.illustration_signature),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(width = 114.dp, height = 47.dp),
        )
        BrandText(BookCopy.Founders.signature, MemoBookFont.taglineRegular, color = MemoBookColor.inkMuted)
    }
}

@Preview(locale = "fr-rFR", name = "Mot des fondateurs", heightDp = 900)
@Composable
private fun FoundersNoteSheetPreview() {
    CompositionLocalProvider(LocalTravellerFirstName provides "Margaux") {
        BrandSheetHost(isPresented = true, onDismissRequest = {}) {
            FoundersNoteSheet(onFeedback = {}, onContinue = {})
        }
    }
}

@Preview(locale = "fr-rFR", name = "Mot des fondateurs — AX3", heightDp = 900, fontScale = 2f)
@Composable
private fun FoundersNoteSheetLargePreview() {
    CompositionLocalProvider(LocalTravellerFirstName provides "Margaux") {
        BrandSheetHost(isPresented = true, onDismissRequest = {}) {
            FoundersNoteSheet(onFeedback = {}, onContinue = {})
        }
    }
}
