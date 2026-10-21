package com.memobook.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import java.text.NumberFormat

/**
 * **La** jauge de MemoBook : une barre qui se remplit à mesure qu'un budget se
 * dépense. Jumeau de `BrandGauge.swift`.
 *
 * Une seule dans l'app aujourd'hui — le crédit du jour d'un voyage —, et elle
 * vit ici quand même : c'est un motif, et la prochaine (les pages d'un carnet
 * face à sa cible) devra lui ressembler.
 *
 * **Vide et grise au matin, le vert avance vers la droite** (Hugo, 08/10/2026) :
 * elle part de zéro, et ce qu'on raconte la remplit. C'est le **chiffre posé à
 * côté** qui dit le reste — « 3 min 20 restantes » —, pour que la barre et lui
 * ne se contredisent pas.
 *
 * À ne pas confondre avec [BrandSlider], qui se **règle** : celle-ci ne se
 * touche pas, elle se lit. D'où l'absence de poignée et de cible tactile.
 *
 * **Elle change de couleur à un seuil, et à un seul** : le vert d'action tant
 * qu'il reste de la marge, le rouge sémantique quand tout est dépensé. Pas
 * d'orange intermédiaire : une jauge qui demande une légende a raté son travail.
 *
 * @param fraction la part **dépensée**, entre 0 et 1. Bornée ici : un barème
 *   réétalonné peut rendre un dépassement, et une barre plus longue que son rail
 *   se lirait comme un défaut d'affichage.
 * @param isExhausted il ne reste rien. La barre, pleine, passe au rouge.
 * @param accessibilityLabel ce que TalkBack annonce — « Crédit du jour ».
 * @param accessibilityValue ce qu'il lit ensuite — « 3 min 20 restantes sur
 *   5 min ». Un pourcentage nu se comprenait de travers ; sans valeur fournie,
 *   la jauge dit « 34 % utilisé ».
 */
@Composable
fun BrandGauge(
    fraction: Double,
    accessibilityLabel: String,
    modifier: Modifier = Modifier,
    isExhausted: Boolean = false,
    accessibilityValue: String? = null,
) {
    val clamped = fraction.coerceIn(0.0, 1.0).toFloat()
    // Assez épaisse pour se voir de loin, assez fine pour rester une jauge. Elle
    // suit le corps de texte : à taille accessible, une barre de 8 sous des
    // lignes de 30 disparaîtrait.
    val height = scaled(8.dp)
    val filled = animateFloatAsState(clamped, SwiftMotion.smooth(0.4f), label = "remplissage")
    val fill = animateColorAsState(
        if (isExhausted) MemoBookColor.error else MemoBookColor.action,
        SwiftMotion.smooth(0.3f),
        label = "couleur",
    )
    val spoken = accessibilityValue ?: "${percent(clamped)} utilisé"

    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clearAndSetSemantics {
                contentDescription = accessibilityLabel
                stateDescription = spoken
                progressBarRangeInfo = ProgressBarRangeInfo(clamped, 0f..1f)
            }
            // Deux capsules : le rail, et ce qui est dépensé, lus à chaque image
            // sans recomposer.
            .drawBehind {
                val capsule = CornerRadius(size.height / 2)
                // Le gris du matin : la barre entière, avant le premier mot raconté.
                drawRoundRect(MemoBookColor.separator.copy(alpha = 0.5f), cornerRadius = capsule)
                val width = size.width * filled.value
                if (width > 0f) drawRoundRect(fill.value, size = Size(width, size.height), cornerRadius = capsule)
            },
    )
}

/** « 34 % », à la manière du téléphone — l'espace fine du français comprise. */
private fun percent(fraction: Float): String =
    NumberFormat.getPercentInstance().apply { maximumFractionDigits = 0 }.format(fraction.toDouble())

@Preview(locale = "fr-rFR", name = "Jauge", widthDp = 390)
@Composable
private fun BrandGaugePreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        // Au matin, à mi-journée, puis tout dépensé.
        BrandGauge(0.0, accessibilityLabel = "Crédit du jour")
        BrandGauge(0.6, accessibilityLabel = "Crédit du jour")
        BrandGauge(1.0, accessibilityLabel = "Crédit du jour", isExhausted = true)
    }
}
