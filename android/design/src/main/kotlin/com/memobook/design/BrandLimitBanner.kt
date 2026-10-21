package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.runtime.State
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * **Le bandeau d'une limite** : une phrase rouge sur un aplat rouge doux, posée
 * juste au-dessus de la barre qu'elle concerne (Hugo, 03/10/2026). Jumeau de
 * `BrandLimitBanner.swift`.
 *
 * Il est né du crédit du jour : pendant qu'on parle, il paraît à trente
 * secondes de la limite et compte à rebours ; à cinq secondes, il **pulse
 * doucement par sa taille** ; le crédit épuisé, il dit « Crédit du jour épuisé ·
 * Reviens demain, ou passe en illimité » et s'ouvre sur l'offre.
 *
 * Ni [ErrorBanner] — rien n'a raté — ni [BrandNotice] — il prévient d'une
 * échéance. D'où le rouge, mais **doux** : le titre et le pictogramme portent
 * [MemoBookColor.error], l'aplat [MemoBookColor.errorSoft]. Le détail passe à
 * l'encre (03/10/2026) : le rouge sur ce rose ne fait que 3,7:1, sous les 4,5:1
 * qu'un texte de ce corps demande — l'encre y tient 12:1.
 *
 * ⚠️ **Il s'empile, il ne flotte pas.** Posé en calque au-dessus d'une barre, il
 * se dessinerait et ne recevrait aucune touche hors du cadre qui le porte : on
 * le met dans la pile du pied, à la place de ce qu'il remplace.
 *
 * **La pulsation s'éteint sous « Supprimer les animations »** : plus d'échelle,
 * seulement une respiration d'opacité à peine visible.
 *
 * ⚠️ **Sans maquette** (T249) : coins, marges et polices sont ceux du design
 * system, la couleur celle que le contrat a fixée.
 *
 * @param title la phrase qui compte — le compte à rebours, ou « Crédit du jour épuisé ».
 * @param detail ce qu'on peut y faire, sous la phrase, plus discret.
 * @param systemImage le pictogramme : le symbole SF d'iOS, redessiné
 *   (`R.drawable.system_hourglass`, `R.drawable.system_moon_zzz`).
 * @param isPulsing il ne reste presque plus rien.
 * @param accessibilityHint ce que fait le toucher, pour TalkBack — le libellé du geste.
 * @param action le bandeau se touche — il mène à l'offre. `null` : il se lit seulement.
 */
@Composable
fun BrandLimitBanner(
    title: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    @DrawableRes systemImage: Int = R.drawable.system_hourglass,
    isPulsing: Boolean = false,
    accessibilityHint: String? = null,
    action: (() -> Unit)? = null,
) {
    val reduceMotion = isReduceMotionEnabled()
    // **La pulsation** : 1,00 ↔ 1,03 en 0,9 s, aller et retour, tant qu'il reste
    // moins de cinq secondes. Hors pulsation, rien ne tourne : le bandeau
    // « épuisé » peut rester affiché des heures.
    val swell: State<Float>? = if (isPulsing) {
        rememberInfiniteTransition(label = "pulsation").animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(900, easing = SwiftMotion.easeInOut), RepeatMode.Reverse),
            label = "phase",
        )
    } else {
        null
    }
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius)

    Row(
        modifier
            .graphicsLayer {
                val phase = swell?.value ?: 0f
                val scale = if (!reduceMotion) 1f + 0.03f * phase else 1f
                scaleX = scale
                scaleY = scale
                alpha = if (reduceMotion) 1f - 0.1f * phase else 1f
            }
            .then(
                if (action != null) {
                    Modifier.clickable(
                        interactionSource = null,
                        indication = PlainButtonIndication,
                        onClickLabel = accessibilityHint,
                        role = Role.Button,
                        onClick = action,
                    )
                } else {
                    Modifier
                },
            )
            .semantics(mergeDescendants = true) {}
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .background(MemoBookColor.errorSoft, shape)
            .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Le symbole à la taille du libellé de 14 qui le porte sur iOS.
        Image(
            painter = painterResource(systemImage),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.error),
            modifier = Modifier.size(scaled(18.dp)),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // Le compte à rebours change de chiffre chaque seconde : les chiffres
            // à chasse fixe l'empêchent de faire danser la phrase. iOS les fait
            // aussi rouler (`numericText`) ; ici, ils changent sur place.
            BrandText(title, MemoBookFont.tagline.copy(fontFeatureSettings = "tnum"), color = MemoBookColor.error)
            if (detail != null) {
                BrandText(detail, MemoBookFont.caption)
            }
        }
        if (action != null) {
            Image(
                painter = painterResource(R.drawable.icon_chevron),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.error),
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

@Preview(locale = "fr-rFR", name = "Bandeau de limite — ses trois états", widthDp = 390)
@Composable
private fun BrandLimitBannerPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandLimitBanner("Plus que 24 secondes avant la limite du jour")
        BrandLimitBanner("Plus que 3 secondes avant la limite du jour", isPulsing = true)
        BrandLimitBanner(
            "Crédit du jour épuisé",
            detail = "Reviens demain, ou passe en illimité",
            systemImage = R.drawable.system_moon_zzz,
            action = {},
        )
    }
}
