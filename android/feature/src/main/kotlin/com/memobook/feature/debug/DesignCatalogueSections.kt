package com.memobook.feature.debug

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandButton
import com.memobook.design.BrandIconBadge
import com.memobook.design.BrandProgressBar
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandTagPill
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R as DesignR

/** Les sections de composants de l'écran-catalogue, une par famille de `Brand…`. */
internal object DesignCatalogueSections {
    val all: List<Pair<String, @Composable () -> Unit>> = listOf(
        "Boutons" to { Buttons() },
        "Pastilles et jauges" to { Pills() },
        "Erreurs et attente" to { Feedback() },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Buttons() {
    val arrow = painterResource(DesignR.drawable.icon_arrow_right)
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandButton("Découvre MemoBook", icon = arrow, fillsWidth = true) {}
        BrandButton(
            "Découvrir l’abonnement",
            icon = arrow,
            iconPlacement = BrandButton.IconPlacement.Trailing,
            style = BrandButton.Style.Accent,
            fillsWidth = true,
        ) {}
        BrandButton("Continuer", style = BrandButton.Style.Blue, fillsWidth = true) {}
        FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandButton("Secondary", style = BrandButton.Style.Secondary) {}
            BrandButton("Soft", style = BrandButton.Style.Soft) {}
            BrandButton("Raised", style = BrandButton.Style.Raised) {}
            BrandButton("Small", size = BrandButton.Size.Small) {}
            BrandButton("Medium", size = BrandButton.Size.Medium) {}
            BrandButton(icon = arrow, isRound = true, contentDescription = "Suivant") {}
            BrandButton("Link", style = BrandButton.Style.Link) {}
        }
        BrandButton("Résilier mon abonnement", style = BrandButton.Style.Destructive, fillsWidth = true) {}
        BrandButton("Chargement", isLoading = true, fillsWidth = true) {}
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Pills() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandTagPill("Illimité")
            BrandTagPill("En cours", tone = BrandTagPill.Tone.Outlined, isUppercased = true)
            BrandTagPill("×3", tone = BrandTagPill.Tone.Info)
            BrandTagPill("Abonnée", tone = BrandTagPill.Tone.AccentOutlined, isUppercased = true)
        }
        BrandProgressBar(0.4, label = "12 souvenirs et 32/80 pages")
        BrandIconBadge(DesignR.drawable.icon_locker)
    }
}

@Composable
private fun Feedback() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        ErrorBanner("Connexion impossible.", retry = {})
        ErrorBanner("Le serveur ne répond pas.", advice = "La panne est chez nous : réessaie dans quelques minutes.", retry = {}, help = {})
        BrandSkeleton(width = 180.dp)
    }
}
