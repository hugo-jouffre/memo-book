package com.memobook.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Le portrait de quelqu'un : sa photo, ou ses initiales tant qu'il n'y en a
 * pas. Jumeau de `BrandAvatar.swift`.
 *
 * **Les initiales ne sont pas un pis-aller décoratif.** Une invitation partie
 * par lien n'a pas de compte derrière elle, donc pas de photo — et c'est l'état
 * le plus fréquent de la liste des co-voyageurs le jour où on l'ouvre. Le rond
 * de remplacement dit « cette personne existe, elle n'a pas encore posé sa
 * tête » ; un rond vide dirait « il manque quelque chose ».
 *
 * Le nom est dit par la ligne qui porte ce rond : le portrait ne dit rien à
 * TalkBack, sans quoi il lirait le nom deux fois.
 *
 * @param photo la photo, déjà chargée. iOS reçoit une adresse et la charge
 *   lui-même (`AsyncImage`) ; `:design` n'a pas encore de chargeur d'images,
 *   c'est donc l'appelant qui la passe — `null` tant qu'elle n'est pas là, ou
 *   si elle n'a pas pu l'être : les initiales tiennent la place.
 * @param side le diamètre, **fixe** : un portrait n'est pas du texte, et une
 *   liste dont les ronds grandissent avec le corps de texte se transforme en
 *   colonne de pastilles.
 */
@Composable
fun BrandAvatar(
    photo: Painter?,
    initials: String,
    modifier: Modifier = Modifier,
    side: Dp = MemoBookSpacing.avatarSide,
) {
    Box(
        modifier
            .size(side)
            .border(1.dp, MemoBookColor.hairline, CircleShape)
            .clip(CircleShape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        if (photo != null) {
            Image(
                painter = photo,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
        } else {
            Box(
                Modifier
                    .matchParentSize()
                    .background(MemoBookColor.outline.copy(alpha = 0.35f)),
            )
            BrandText(
                initials,
                MemoBookFont.overline,
                Modifier.padding(2.dp),
                color = MemoBookColor.action,
                maxLines = 1,
                minimumScaleFactor = 0.6f,
            )
        }
    }
}

@Preview(locale = "fr-rFR", name = "Portraits")
@Composable
private fun BrandAvatarPreview() {
    Row(
        Modifier
            .background(MemoBookColor.surface)
            .padding(MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandAvatar(photo = null, initials = "MD")
        BrandAvatar(photo = null, initials = "TJ", side = 42.dp)
        BrandAvatar(photo = null, initials = "C", side = 64.dp)
    }
}
