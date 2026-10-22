package com.memobook.feature.profile

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.core.Gender
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.LocalBrandSheetDismiss
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Dire à l'app à qui elle parle — femme, homme, ou qu'on ne préfère pas
 * répondre. Jumeau de `Profile/GenderSheet.swift`.
 *
 * Elle sert à **un accord grammatical**, et rien d'autre : « Abonnée » ou
 * « Abonné » sur la feuille d'abonnement. Le serveur devine sur le prénom tant
 * qu'on n'a rien dit ; cette feuille est là pour le corriger (Hugo,
 * 17/09/2026, T76). Le choix s'enregistre au toucher et la feuille se
 * referme : trois options, aucune saisie, un « Valider » de plus n'aurait rien
 * à valider.
 *
 * **Elle se referme après s'être montrée cochée**, pas avant (Hugo,
 * 18/09/2026) : une feuille qui part à l'instant du toucher ne dit pas ce
 * qu'elle a retenu, et on rouvre pour vérifier. La coche se pose, on la voit
 * un tiers de seconde, la feuille descend.
 *
 * ⚠️ **Aucune maquette** : écrite sur le motif des feuilles de choix du
 * profil (`PaymentMethodSheet`), et à dessiner dans Figma.
 */
@Composable
internal fun GenderSheet(current: Gender, onSelect: (Gender) -> Unit) {
    // Ce qu'on vient de toucher, le temps que la feuille parte. La feuille
    // coche **sa** valeur et non celle du modèle : celui-ci enregistre en
    // arrière-plan, et sa réponse ne doit pas faire clignoter la coche.
    var chosen by remember { mutableStateOf<Gender?>(null) }
    val dismiss = LocalBrandSheetDismiss.current
    val scope = rememberCoroutineScope()

    // Coche, enregistre, puis referme — dans cet ordre. Un second toucher
    // pendant l'attente ne fait rien : le premier est déjà parti.
    fun select(gender: Gender) {
        if (chosen != null) return
        chosen = gender
        onSelect(gender)
        scope.launch {
            delay(BrandOptionRow.lingerBeforeDismiss)
            dismiss()
        }
    }

    BrandSheet("Genre", subtitle = "Pour que MemoBook s’adresse à toi comme il faut.") {
        BrandOptionGroup {
            Gender.entries.forEach { gender ->
                BrandOptionRow(gender.label, isSelected = gender == (chosen ?: current)) { select(gender) }
            }
        }
    }
}

@Preview(locale = "fr-rFR", name = "Genre", heightDp = 600)
@Composable
private fun GenderSheetPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        GenderSheet(current = Gender.Female) {}
    }
}
