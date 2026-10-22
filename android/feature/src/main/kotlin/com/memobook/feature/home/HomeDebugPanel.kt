package com.memobook.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.TripStage
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.brandDashedCard
import com.memobook.feature.LocalSubscriptionSession
import com.memobook.feature.SandboxCredit
import kotlinx.coroutines.launch

/**
 * Le bac à sable de l'accueil : de quoi voir chacun de ses états sans back-end
 * ni compte. Jumeau de `Home/HomeDebugPanel.swift`.
 *
 * **Il n'existe pas dans l'app livrée.** Sur iOS, le fichier entier est sous
 * `#if DEBUG`. `:feature` n'a pas de `BuildConfig` pour en faire autant : la
 * porte de l'accueil ne le pose que dans une app débogable — le `#if DEBUG`
 * d'iOS, lu à l'exécution comme celui de l'écran d'entrée (`WelcomeEntry`).
 *
 * Il est posé tout en bas de l'accueil, après le contenu réel, et se présente
 * comme ce qu'il est : un panneau d'atelier, pas un morceau de l'app. D'où le
 * pointillé et le libellé qui le nomme.
 */
@Composable
internal fun HomeDebugPanel(model: HomeModel, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()

    // Ce qu'un achat ou une résiliation ont imposé à la session. Le panneau ne
    // s'en sert que pour l'**effacer** : c'est `SandboxPersona` qui fait jouer
    // l'abonnement aux écrans, et un geste resté dans la session prendrait le
    // pas sur lui.
    val session = LocalSubscriptionSession.current

    /**
     * Fait jouer un personnage — et **efface d'abord ce que la session
     * impose**. Sans ça, un achat ou une résiliation faits plus tôt primaient
     * sur le personnage (voir `SubscriptionSession.isUnlimited`), et les
     * boutons du bac à sable n'avaient plus l'air de marcher.
     */
    fun play(persona: () -> Unit) {
        session?.play(isUnlimited = null)
        persona()
    }

    Column(
        modifier
            .fillMaxWidth()
            .brandDashedCard(color = MemoBookColor.separator)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandText("Bac à sable — absent de l’app livrée", MemoBookFont.caption, color = MemoBookColor.inkMuted)

        // Les boutons s'écoulent sur plusieurs lignes : ils sont nombreux, de
        // largeurs très différentes, et une bande qui défile cacherait les
        // derniers.
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            DebugAction("Tout effacer") { model.debugRemoveAllTrips() }
            DebugAction("+ voyage en cours") { model.debugAddTrip(TripStage.Ongoing) }
            DebugAction("+ voyage à venir") { model.debugAddTrip(TripStage.Upcoming) }
            DebugAction("+ voyage passé") { model.debugAddTrip(TripStage.Past) }

            DebugAction("Devenir un abonné") { play(model::debugBecomeSubscriber) }
            DebugAction("Sans abonnement") { play(model::debugBecomeFree) }
            // La découverte en trois écrans : il faut oublier aussi que la
            // session a déjà vu un abonné — elle ne l'oublie d'elle-même qu'en
            // changeant de compte.
            DebugAction("Jamais abonné") {
                session?.reset()
                model.debugBecomeNeverSubscribed()
            }
            // Le crédit du jour du voyage, servi par le double d'API au fil de
            // la conversation, à ses reçus, aux réglages et à l'accueil — voir
            // `SandboxCredit`.
            SandboxCredit.Preset.entries.forEach { preset ->
                DebugAction(preset.label) { play { model.debugPlayCredit(preset) } }
            }
            DebugAction("Erreur") { model.debugShowError() }

            // Le hors-ligne coupe **vraiment** le réseau de l'app, et le vocal
            // mis en file part **vraiment** sur le disque : c'est le seul moyen
            // de vérifier que la promesse écrite dans la boîte est tenue. Les
            // deux derniers, eux, ne font que poser un état passager qu'on
            // n'aurait sinon le temps de voir qu'avec un très mauvais réseau.
            DebugAction(if (state.isOffline) "Repasser en ligne" else "Passer hors ligne") { model.debugToggleOffline() }
            DebugAction("+ vocal en attente") { model.viewModelScope.launch { model.debugQueueRecording() } }
            DebugAction("Envoi en cours") { model.debugShowSending() }
            DebugAction("Vocal envoyé") { model.debugShowDelivered() }

            DebugAction("Jeu d’essai") {
                session?.play(isUnlimited = null)
                model.debugReset()
            }
        }
    }
}

/** Un bouton du panneau : une pastille cerclée, le libellé en vert d'action. */
@Composable
private fun DebugAction(title: String, perform: () -> Unit) {
    val shape = RoundedCornerShape(percent = 50)
    BrandText(
        title,
        MemoBookFont.caption,
        color = MemoBookColor.action,
        modifier = Modifier
            .clip(shape)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.separator, shape)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = perform)
            .padding(horizontal = MemoBookSpacing.xs, vertical = 6.dp),
    )
}
