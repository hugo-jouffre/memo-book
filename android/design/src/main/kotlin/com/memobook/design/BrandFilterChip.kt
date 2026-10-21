package com.memobook.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * Une pastille de filtre : ce sur quoi on trie la liste d'en dessous. Jumeau
 * de `BrandFilterChip.swift`.
 *
 * Elle ne porte **pas** l'action, dans aucune de ses deux formes : c'est le
 * contenu d'un menu déroulant ou d'un bouton, et c'est lui qui apporte le
 * geste et TalkBack sans qu'on ait à les redessiner.
 *
 * ```kotlin
 * // Une liste déroulante — les filtres d'un voyage.
 * BrandFilterChip("Pays", Modifier.clickable { … }, icon = flag, isActive = country != null)
 * // Un choix parmi une barre — les catégories de la galerie.
 * BrandFilterChip(item.name, Modifier.clickable { … }, icon = item.icon, kind = BrandFilterChip.Kind.Toggle)
 * ```
 *
 * Deux états, et deux seulement : au repos elle est un contour sur le crème,
 * active elle prend le vert de la marque. Un filtre posé doit se voir de loin,
 * sinon on cherche pourquoi la liste est courte.
 *
 * **La capsule et le libellé changent de taille du même pas.** Une pastille
 * change de largeur en même temps que d'état : « Étapes » devient « Etape
 * n°1 ». Sur iOS, sans `geometryGroup()`, l'aplat vert traînait derrière son
 * libellé et s'arrêtait au milieu du mot ; ici le fond est dessiné sur la
 * taille animée elle-même, il ne peut pas prendre de retard.
 *
 * @param icon teintée par l'état de la pastille, quelles que soient les
 *   couleurs du fichier source.
 */
@Composable
fun BrandFilterChip(
    title: String,
    modifier: Modifier = Modifier,
    icon: Painter? = null,
    kind: BrandFilterChip.Kind = BrandFilterChip.Kind.Menu,
    isActive: Boolean = false,
) {
    val iconSide = scaled(16.dp)
    val chevronSide = scaled(10.dp)
    // Une durée à nous plutôt que celle, variable, de la liste qui se
    // referme : deux pastilles voisines doivent s'allumer de la même façon,
    // qu'on ait choisi dans un menu ou tapé dans une barre.
    val foreground by animateColorAsState(
        if (isActive) MemoBookColor.onAction else MemoBookColor.ink,
        SwiftMotion.snappy(0.22f),
        label = "foreground",
    )
    val background by animateColorAsState(
        if (isActive) MemoBookColor.action else MemoBookColor.surface,
        SwiftMotion.snappy(0.22f),
        label = "background",
    )
    val border by animateColorAsState(
        if (isActive) MemoBookColor.action else MemoBookColor.separator,
        SwiftMotion.snappy(0.22f),
        label = "border",
    )
    val capsule = RoundedCornerShape(percent = 50)

    Row(
        modifier
            .background(background, capsule)
            .border(1.dp, border, capsule)
            .animateContentSize(SwiftMotion.snappy(0.22f))
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .padding(horizontal = MemoBookSpacing.s - 2.dp, vertical = MemoBookSpacing.xs + 2.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            Image(
                painter = it,
                contentDescription = null,
                colorFilter = ColorFilter.tint(foreground),
                modifier = Modifier.size(iconSide),
            )
        }
        BrandText(title, MemoBookFont.label, color = foreground, maxLines = 1)
        if (kind == BrandFilterChip.Kind.Menu) {
            // Le « chevron.down » d'iOS, redessiné (`system_chevron_down`).
            Image(
                painter = painterResource(R.drawable.system_chevron_down),
                contentDescription = null,
                colorFilter = ColorFilter.tint(foreground),
                modifier = Modifier.size(chevronSide),
            )
        }
    }
}

object BrandFilterChip {
    /** Ce que la pastille annonce, et donc si elle porte un chevron. */
    enum class Kind {
        /** Elle ouvre une liste déroulante. Le chevron dit « il y a un choix dessous ». */
        Menu,

        /**
         * Elle **est** le choix : une pastille parmi une barre, qu'on allume et
         * qu'on éteint. Rien ne se déroule, donc pas de chevron.
         */
        Toggle,
    }
}

@Preview(locale = "fr-rFR", name = "Filtres", widthDp = 390)
@Composable
private fun BrandFilterChipPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandFilterChip("Pays", icon = painterResource(R.drawable.icon_lucide_globe))
            BrandFilterChip("Etape n°1", icon = painterResource(R.drawable.icon_lucide_backpack), isActive = true)
            BrandFilterChip("Transports", icon = painterResource(LucideIcon.image("train-front")))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandFilterChip("Tout", kind = BrandFilterChip.Kind.Toggle, isActive = true)
            BrandFilterChip("Tour du monde", icon = painterResource(LucideIcon.image("globe")), kind = BrandFilterChip.Kind.Toggle)
            BrandFilterChip("Randonnée", icon = painterResource(LucideIcon.image("footprints")), kind = BrandFilterChip.Kind.Toggle)
        }
    }
}
