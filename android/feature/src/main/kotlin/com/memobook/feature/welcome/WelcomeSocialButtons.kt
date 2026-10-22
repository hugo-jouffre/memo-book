package com.memobook.feature.welcome

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.scaled

/**
 * L'entrée par fournisseur tiers, telle que la maquette d'accueil la dessine :
 * un pavé cerclé de beige, le logo à gauche du libellé. Jumeau de
 * `WelcomeSocialButtons.swift`.
 *
 * **Sur Android, c'est Google seul** : pas de « Continuer avec Apple »
 * (Hugo, 22/10/2026). On entre par Google ou par l'e-mail. Quelqu'un qui a
 * ouvert son compte par Apple sur l'iPhone entre ici par « Mot de passe
 * oublié » : le serveur lui envoie l'e-mail même sans mot de passe
 * (`backend/src/services/passwordReset.ts`), et le mot de passe qu'il y choisit
 * lui ouvre l'entrée par adresse.
 *
 * ⏳ **Le bouton ne s'affiche que si son client existe** ([showsGoogle]) :
 * `memobook.googleWebClientId` est vide dans `gradle.properties` tant que les
 * lots A0 et B1 ne sont pas faits.
 */
@Composable
internal fun WelcomeSocialButtons(
    showsGoogle: Boolean,
    enabled: Boolean,
    onGoogle: () -> Unit,
) {
    if (!showsGoogle) return
    ProviderButton(R.drawable.logo_google, WelcomeCopy.google, enabled, onGoogle)
}

/**
 * Un pavé de fournisseur. La hauteur — 3.25 rem sur la maquette, contre 3 rem
 * pour le CTA ordinaire de l'app — suit la taille de police, et le logo aussi.
 */
@Composable
private fun ProviderButton(@DrawableRes logo: Int, label: String, enabled: Boolean, onClick: () -> Unit) {
    val height = scaled(52.dp)
    val markSide = scaled(24.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = height)
            .providerChrome()
            .clickable(interactionSource = null, indication = PlainButtonIndication, enabled = enabled, role = Role.Button, onClick = onClick)
            // De l'air avant le filet : en taille accessible le libellé passe à
            // la ligne et vient occuper toute la largeur offerte — sans cette
            // réserve, « avec Google » butait contre le bord du bouton.
            .padding(horizontal = MemoBookSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 2.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Le logo de la marque, dessiné à la main et cerné de bleu comme les
        // trois icônes du dessus — surtout pas de teinte, qui l'aplatirait en
        // une couleur.
        Image(painter = painterResource(logo), contentDescription = null, modifier = Modifier.size(markSide))

        // General Sans Semibold, comme la maquette — et non la Sora des boutons
        // de l'app : celui-ci emprunte le gabarit des fournisseurs, pas la
        // typographie des CTA.
        BrandText(label, MemoBookFont.bodySemibold, textAlign = TextAlign.Center)
    }
}

/**
 * L'habillage du bouton de fournisseur : l'aplat, le filet beige, et la
 * découpe qui le fait suivre l'arrondi.
 */
private fun Modifier.providerChrome(): Modifier {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    return background(MemoBookColor.surface, shape)
        .clip(shape)
        .border(1.5.dp, MemoBookColor.separator, shape)
}
