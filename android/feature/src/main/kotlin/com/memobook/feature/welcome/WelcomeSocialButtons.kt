package com.memobook.feature.welcome

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.memobook.feature.auth.LocalizedError

/**
 * Les deux entrées par fournisseur tiers, telles que la maquette d'accueil les
 * dessine : deux pavés de même gabarit, cerclés de beige, le logo à gauche du
 * libellé. Jumeau de `WelcomeSocialButtons.swift`.
 *
 * **Les deux portent le même habillage, et il n'est écrit qu'une fois** —
 * [providerChrome]. C'est ce qui empêche les deux boutons de diverger : même
 * rayon, même filet, même aplat, et un seul endroit à changer.
 *
 * **Le bouton Apple n'est pas celui d'Apple**, contrairement à iOS : Android
 * n'a pas de `SignInWithAppleButton`, l'entrée passe par la page web d'Apple
 * (`AppleSignInService`). Il prend donc l'habillage du bouton Google, avec la
 * pomme cernée de bleu du catalogue et le libellé qu'Apple écrit en français.
 *
 * ⏳ **Chacun ne s'affiche que si son client existe** ([showsApple],
 * [showsGoogle]) : `memobook.appleServicesId` et `memobook.googleWebClientId`
 * sont vides dans `gradle.properties` tant que les lots A0, B1 et B2 ne sont
 * pas faits.
 */
@Composable
internal fun WelcomeSocialButtons(
    showsApple: Boolean,
    showsGoogle: Boolean,
    enabled: Boolean,
    onApple: () -> Unit,
    onGoogle: () -> Unit,
) {
    if (!showsApple && !showsGoogle) return
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        if (showsApple) ProviderButton(R.drawable.logo_apple, WelcomeCopy.apple, enabled, onApple)
        if (showsGoogle) ProviderButton(R.drawable.logo_google, WelcomeCopy.google, enabled, onGoogle)
    }
}

/**
 * Un pavé de fournisseur. La hauteur — 3.25 rem sur la maquette, contre 3 rem
 * pour le CTA ordinaire de l'app — suit la taille de police, et le logo aussi.
 * Sur iOS, le bouton d'Apple garde 52 : Apple n'y fait pas suivre le Dynamic
 * Type. Ici, les deux libellés sont les nôtres, et suivent tous deux.
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
        // de l'app : ces deux-là empruntent le gabarit des fournisseurs, pas la
        // typographie des CTA.
        BrandText(label, MemoBookFont.bodySemibold, textAlign = TextAlign.Center)
    }
}

/**
 * L'habillage des deux boutons de fournisseur : l'aplat, le filet beige, et la
 * découpe qui les fait suivre le même arrondi.
 */
private fun Modifier.providerChrome(): Modifier {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    return background(MemoBookColor.surface, shape)
        .clip(shape)
        .border(1.5.dp, MemoBookColor.separator, shape)
}

/**
 * Les échecs propres à l'entrée par fournisseur. Tout le reste remonte tel quel
 * du fournisseur ou du réseau.
 */
internal sealed class SocialSignInError : Exception(), LocalizedError {
    /**
     * Apple a répondu, mais sans jeton d'identité exploitable — le retour du
     * web sans `id_token` (lot B2). En pratique : jamais, sauf mauvaise
     * configuration.
     */
    data object UnusableAppleCredential : SocialSignInError() {
        override val errorDescription = "Apple n’a pas transmis d’identifiant utilisable. Réessaie."
    }

    override val message: String get() = errorDescription
}
