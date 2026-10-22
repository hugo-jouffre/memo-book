package com.memobook.feature.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.core.ChatCopy
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.design.BrandLimitBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R

/**
 * Ce que le bandeau du crédit du jour dit, au-dessus d'une barre
 * d'enregistrement — celle du chat comme la feuille bleue de l'accueil (Hugo,
 * 03/10/2026). Jumeau de `DailyCreditBanner.swift`.
 *
 * Trois états, et rien pour un abonné :
 *
 * | État | Quand | Ce qu'on voit |
 * |---|---|---|
 * | [Warning] | moins de 30 s pendant qu'on parle | le compte à rebours |
 * | [Urgent] | moins de 5 s | le même, qui pulse |
 * | [Exhausted] | plus rien | « Crédit du jour épuisé », qui mène à l'offre |
 *
 * Les seuils voyagent avec le solde ([DailyCredit.warningRemainingMs],
 * [DailyCredit.urgentRemainingMs]) : l'app n'en écrit aucun.
 */
sealed interface DailyCreditBanner {
    data class Warning(val remainingMs: Int) : DailyCreditBanner
    data class Urgent(val remainingMs: Int) : DailyCreditBanner
    data object Exhausted : DailyCreditBanner

    /** Le bandeau se touche : seul « épuisé » mène quelque part — à l'offre. */
    val opensOffer: Boolean get() = this == Exhausted

    companion object {
        /**
         * Le bandeau pendant qu'on parle : le reste du jour, moins ce que le
         * fichier contient déjà. `null` tant qu'il reste plus de trente secondes.
         */
        fun whileRecording(credit: DailyCredit, elapsedMs: Int): DailyCreditBanner? {
            val remaining = credit.remainingMs(whileRecording = elapsedMs)
            return when (credit.phase(remainingMs = remaining)) {
                DailyCredit.Phase.Calm -> null
                DailyCredit.Phase.Warning -> Warning(remaining)
                DailyCredit.Phase.Urgent -> Urgent(remaining)
                // L'instant entre zéro et l'arrêt net : le bandeau dit déjà la suite.
                DailyCredit.Phase.Exhausted -> Exhausted
            }
        }
    }
}

/**
 * Le bandeau du crédit du jour, dessiné — [BrandLimitBanner] habillé des
 * phrases de [DailyCreditCopy]. Jumeau de `DailyCreditBannerView`.
 *
 * **Empilé dans le pied, jamais en calque** : c'est la condition pour que
 * « épuisé » se touche. Il prend la place du rail de suggestions pendant
 * l'enregistrement — voir `ChatComposer`.
 *
 * @param onSubscribe ce que fait le toucher sur « épuisé » : ouvrir l'offre.
 *   Ignoré pour le compte à rebours, qui se lit seulement.
 */
@Composable
fun DailyCreditBannerView(banner: DailyCreditBanner, onSubscribe: () -> Unit, modifier: Modifier = Modifier) {
    when (banner) {
        is DailyCreditBanner.Warning ->
            BrandLimitBanner(DailyCreditCopy.warning(remainingMs = banner.remainingMs), modifier)
        is DailyCreditBanner.Urgent ->
            BrandLimitBanner(DailyCreditCopy.warning(remainingMs = banner.remainingMs), modifier, isPulsing = true)
        DailyCreditBanner.Exhausted ->
            BrandLimitBanner(
                DailyCreditCopy.exhaustedTitle,
                modifier,
                detail = DailyCreditCopy.exhaustedDetail,
                systemImage = R.drawable.system_moon_zzz,
                accessibilityHint = ChatCopy.Credit.exhaustedHint,
                action = onSubscribe,
            )
    }
}

/**
 * La boîte d'information au-dessus du champ, quand le crédit du jour pèse sur
 * ce qu'on écrit — voir `ChatModel.creditTextNotice`.
 */
sealed interface ChatCreditTextNotice {
    val message: String

    /** Le brouillon dépasse le reste du jour : l'envoi a pâli, voici pourquoi. */
    data class TooLong(override val message: String) : ChatCreditTextNotice

    /** Moins d'une minute de crédit : combien de caractères cela laisse. */
    data class Reminder(override val message: String) : ChatCreditTextNotice
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Bandeau du crédit — avertissement, pulsation, épuisé", widthDp = 390)
@Composable
private fun DailyCreditBannerPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        DailyCreditBannerView(DailyCreditBanner.Warning(remainingMs = 24_000), onSubscribe = {})
        DailyCreditBannerView(DailyCreditBanner.Urgent(remainingMs = 3_000), onSubscribe = {})
        DailyCreditBannerView(DailyCreditBanner.Exhausted, onSubscribe = {})
    }
}
