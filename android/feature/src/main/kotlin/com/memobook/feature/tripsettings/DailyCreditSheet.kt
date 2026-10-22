package com.memobook.feature.tripsettings

import androidx.annotation.DrawableRes
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.core.TripSettings
import com.memobook.design.BrandButton
import com.memobook.design.BrandGauge
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.scaled
import com.memobook.feature.LocalSubscriptionSession
import com.memobook.feature.profile.dayAndMonth

/**
 * « Crédit du jour » — ce que le voyage peut encore raconter aujourd'hui,
 * comment le crédit se consomme, et la porte de l'illimité. Jumeau de
 * `TripSettings/DailyCreditSheet.swift`.
 *
 * **Une seule étape** (Hugo, 03/10/2026). Elle remplace la feuille des
 * limites de souvenirs et ses trois temps (le solde, la comparaison des
 * paliers, « C’est étendu ») : il n'y a plus de palier à choisir ici. On lit
 * le reste, on comprend la règle, et l'on passe en illimité — ce qui se fait
 * **dans le paywall**, pas dans cette feuille.
 *
 * ```
 * Il reste 3 min 20 aujourd’hui        ← ou « Plus rien pour aujourd’hui : reviens demain »
 * ▬▬▬▬▬▬▬▬▬▬▬▬▬▭▭▭▭▭▭▭                  ← ce qui reste : verte, le rail rouge à zéro
 * soit environ 2 650 caractères à l’écrit
 *
 * (co-voyageurs) 5 minutes par jour pour ce voyage, à partager entre co-voyageurs.
 * (micro)        Un vocal consomme sa durée ; à l’écrit, 800 caractères valent une minute…
 * (calendrier)   Le crédit se recharge chaque nuit, à minuit.
 *
 * [ Passer en illimité ]   ← lime : le lime ne dit que l'abonnement
 * [ Fermer ]
 * ```
 *
 * **Le bouton ne pose pas le paywall sur la feuille.** Une feuille ne
 * s'empile pas sur une autre (règle du design system) : [onSubscribe] remonte
 * à [TripSettingsView], qui referme la feuille puis ouvre le paywall en plein
 * écran — le motif de « En savoir plus » dans le profil.
 *
 * Pour un abonné, ni jauge ni bouton : « Illimité », et un paragraphe qui
 * rappelle ce que l'abonnement n'ouvre pas — ses co-voyageurs non abonnés
 * partagent toujours le crédit du voyage.
 *
 * ⚠️ **Aucune maquette ne la dessine** (T248). Elle reprend les composants
 * validés — `BrandSheet`, `BrandGauge`, `BrandButton` — et reste à dessiner
 * dans Figma.
 *
 * @param onSubscribe « Passer en illimité ». La vue des réglages ferme la
 *   feuille et ouvre le paywall ; la feuille, elle, ne présente rien.
 */
@Composable
internal fun DailyCreditSheet(model: TripSettingsModel, onSubscribe: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val dismiss = LocalBrandSheetDismiss.current
    val subscriptionSession = LocalSubscriptionSession.current

    // Le crédit servi avec les réglages, relu avec le dernier geste de la
    // session : juste après un achat, il dit « Illimité » sans attendre que
    // les réglages soient relus. Sans réponse du serveur — un aperçu —, le
    // barème du catalogue, neuf.
    val served = state.dailyCredit ?: DailyCredit()
    val credit = subscriptionSession?.applied(served) ?: served

    BrandSheet(DailyCreditCopy.title) {
        Column(
            Modifier.animateContentSize(SwiftMotion.smooth(0.3f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
        ) {
            if (credit.isUnlimited) {
                Unlimited(credit, endsOn = subscriptionSession?.endsAt?.dayAndMonth)
            } else {
                Balance(credit)
                Rules(credit)
            }

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                if (!credit.isUnlimited) {
                    BrandButton(
                        DailyCreditCopy.unlimitedCallToAction,
                        style = BrandButton.Style.Accent,
                        fillsWidth = true,
                        action = onSubscribe,
                    )
                }

                BrandButton(
                    DailyCreditCopy.Sheet.close,
                    style = if (credit.isUnlimited) BrandButton.Style.Primary else BrandButton.Style.Secondary,
                    fillsWidth = true,
                    action = dismiss,
                )
            }
        }
    }
}

// MARK: - Ce qui reste

/** Le reste du jour, la jauge, et ce que ça vaut au clavier. */
@Composable
private fun Balance(credit: DailyCredit) {
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandText(
            DailyCreditCopy.Sheet.remaining(credit),
            MemoBookFont.calloutTitle.copy(fontFeatureSettings = "tnum"),
        )

        // Ce qui est **raconté** : vide au matin, le vert avance vers la
        // droite (Hugo, 08/10/2026) ; la phrase au-dessus dit le reste. Deux
        // couleurs, comme partout : le vert tant qu'il reste du crédit, le
        // rouge sémantique quand il n'y a plus rien.
        BrandGauge(
            fraction = credit.fraction,
            accessibilityLabel = DailyCreditCopy.title,
            isExhausted = credit.isExhausted,
            accessibilityValue = DailyCreditCopy.Sheet.gaugeAccessibilityValue(credit),
        )

        DailyCreditCopy.Sheet.charactersEquivalent(credit)?.let { characters ->
            BrandText(characters, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }
    }
}

// MARK: - La règle

/**
 * Les trois phrases qui font le crédit : le partage, ce qui consomme, la
 * recharge. Une icône chacune, pour qu'on les retrouve d'un coup d'œil sans
 * les relire.
 */
@Composable
private fun Rules(credit: DailyCredit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        Rule(R.drawable.icon_lucide_users, DailyCreditCopy.Sheet.sharing(limitMs = credit.limitMs))
        Rule(R.drawable.icon_mic, DailyCreditCopy.Sheet.consumption(textMsPerCharacter = credit.textMsPerCharacter))
        Rule(R.drawable.icon_lucide_calendar, DailyCreditCopy.Sheet.recharge)
    }
}

@Composable
private fun Rule(@DrawableRes icon: Int, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug), verticalAlignment = Alignment.Top) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
            modifier = Modifier.size(scaled(MemoBookSpacing.contentIcon)),
        )
        BrandText(text, MemoBookFont.body)
    }
}

// MARK: - Abonné

/** @param endsOn le jour où l'illimité s'arrête — un renouvellement coupé. */
@Composable
private fun Unlimited(credit: DailyCredit, endsOn: String?) {
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandText(DailyCreditCopy.unlimited, MemoBookFont.calloutTitle)

        BrandText(
            DailyCreditCopy.Sheet.unlimitedExplanation(limitMs = credit.limitMs),
            MemoBookFont.body,
            color = MemoBookColor.inkMuted,
        )

        // Renouvellement coupé : la date où l'illimité s'arrête.
        endsOn?.let { end ->
            BrandText(
                DailyCreditCopy.Sheet.unlimitedEnds(on = end, limitMs = credit.limitMs),
                MemoBookFont.body,
                color = MemoBookColor.inkMuted,
            )
        }
    }
}

// MARK: - Aperçus

@Composable
private fun DailyCreditSheetPreview(credit: DailyCredit?) {
    val model = remember {
        TripSettingsModel(tripId = "preview", source = { TripSettings.fixture.copy(dailyCredit = credit ?: TripSettings.fixture.dailyCredit) })
    }
    LaunchedEffect(model) { model.load() }
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        DailyCreditSheet(model, onSubscribe = {})
    }
}

@Preview(locale = "fr-rFR", name = "Crédit du jour", widthDp = 390, heightDp = 800)
@Composable
private fun DailyCreditSheetFixturePreview() = DailyCreditSheetPreview(credit = null)

@Preview(locale = "fr-rFR", name = "Crédit du jour — épuisé", widthDp = 390, heightDp = 800)
@Composable
private fun DailyCreditSheetExhaustedPreview() = DailyCreditSheetPreview(DailyCredit(usedMs = DailyCredit.Catalog.limitMs))

@Preview(locale = "fr-rFR", name = "Crédit du jour — abonné", widthDp = 390, heightDp = 800)
@Composable
private fun DailyCreditSheetUnlimitedPreview() = DailyCreditSheetPreview(DailyCredit(isUnlimited = true))
