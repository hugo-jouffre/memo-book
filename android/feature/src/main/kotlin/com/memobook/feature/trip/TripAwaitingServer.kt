package com.memobook.feature.trip

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import com.memobook.design.BrandNotice
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.brandShadow
import com.memobook.design.isReduceMotionEnabled
import kotlinx.coroutines.delay
import kotlin.time.Duration.Companion.seconds

/**
 * **Ce qu'un voyage créé hors ligne ne peut pas encore faire** (T239, Hugo,
 * 06/10/2026). Jumeau de `Trip/TripAwaitingServer.swift`.
 *
 * Tant que le serveur ne l'a pas reçu, un voyage n'existe que sur le
 * téléphone : on y raconte (la file garde tout), mais ses réglages,
 * « Inviter un proche », l'aperçu du carnet et la commande sont des écrans
 * **du serveur** — ils s'ouvraient sur son erreur, un 404 ou une panne. Ces
 * portes-là **pâlissent** au lieu de mener à un écran cassé : elles restent
 * tapables, et l'appui dit pourquoi et quand elles s'ouvriront — la règle
 * « ce qu'on ne peut pas faire pâlit, ça ne se désactive pas »
 * (`ios/CLAUDE.md`).
 *
 * L'ensemble des voyages en attente vient de la file (`RecordingOutbox.localTrips`),
 * posé une fois par `RootView` ([com.memobook.feature.LocalTripsAwaitingServer]) :
 * l'accueil, l'écran du voyage et la conversation le lisent sans connaître la
 * file. Le voyage arrivé, il sort de l'ensemble et les portes se rallument
 * d'elles-mêmes.
 */
object TripAwaitingServer {
    /** L'opacité d'une commande qui attend le serveur — celle des autres contrôles pâlis de l'app (40–45 %). */
    const val dimmedOpacity = 0.45f

    /** La boîte posée à l'appui. La phrase de Hugo en tête, puis la cause. */
    const val notice =
        "**Disponible dès ta reconnexion.** Ton voyage a été créé hors ligne : il n’est encore que sur ton téléphone."

    /** Ce que TalkBack entend sur une commande pâlie, avant de la toucher. */
    const val hint = "Disponible dès ta reconnexion"

    /** Combien de temps la boîte reste, si on ne la touche pas. */
    val noticeDuration = 4.seconds
}

/**
 * Pâlit une commande qui attend le serveur, et le dit à TalkBack. Elle reste
 * tapable : c'est à son action de poser la boîte.
 *
 * L'`accessibilityHint` d'iOS n'a pas de jumeau exact : la phrase devient
 * l'état de la commande, que TalkBack lit après son nom.
 */
fun Modifier.dimmedWhileAwaitingServer(isAwaiting: Boolean): Modifier =
    if (!isAwaiting) {
        this
    } else {
        alpha(TripAwaitingServer.dimmedOpacity).semantics { stateDescription = TripAwaitingServer.hint }
    }

/**
 * La boîte « Disponible dès ta reconnexion », posée en haut de l'écran le temps
 * de la lire — le `.awaitingServerNotice(isPresented:below:)` d'iOS, qui était
 * un modificateur et devient ici une enveloppe : la boîte se pose par-dessus
 * [content].
 *
 * @param below le bas des commandes de l'en-tête, **en coordonnées de la
 *   fenêtre** : la boîte se pose dessous, pour ne pas les recouvrir. En
 *   coordonnées de la fenêtre parce que les deux écrans qui s'en servent passent
 *   sous la barre d'état chacun à sa façon — même mesure que la bannière de
 *   l'aperçu de la conversation.
 */
@Composable
fun AwaitingServerNotice(
    isPresented: Boolean,
    onIsPresentedChange: (Boolean) -> Unit,
    below: Dp,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val reduceMotion = isReduceMotionEnabled()
    val density = LocalDensity.current
    var originY by remember { mutableFloatStateOf(0f) }
    val dismiss by rememberUpdatedState(onIsPresentedChange)
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)

    Box(modifier.onGloballyPositioned { originY = it.positionInWindow().y }) {
        content()

        AnimatedVisibility(
            visible = isPresented,
            modifier = Modifier.align(Alignment.TopCenter),
            enter = if (reduceMotion) fadeIn() else slideInVertically(SwiftMotion.snappy(0.25f)) { -it } + fadeIn(SwiftMotion.snappy(0.25f)),
            exit = if (reduceMotion) fadeOut() else slideOutVertically(SwiftMotion.snappy(0.25f)) { -it } + fadeOut(SwiftMotion.snappy(0.25f)),
        ) {
            val inset = max(0.dp, below - with(density) { originY.toDp() })
            BrandNotice(
                TripAwaitingServer.notice,
                tone = BrandNotice.Tone.Information,
                modifier = Modifier
                    .padding(horizontal = MemoBookSpacing.screenMargin)
                    .padding(top = inset + MemoBookSpacing.xs)
                    .fillMaxWidth()
                    // La boîte d'information a un aplat très clair : posée sur
                    // une photo, elle a besoin du papier dessous.
                    .brandShadow(MemoBookShadow.Raised, shape)
                    .background(MemoBookColor.background, shape)
                    // Toucher la boîte la referme : elle a été lue.
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { dismiss(false) }
                    // L'annonce d'iOS (`AccessibilityNotification.Announcement`) :
                    // une région vivante, que TalkBack lit dès qu'elle paraît.
                    .semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
    }

    // La boîte s'en va d'elle-même, le temps de la lire. Une boîte rouverte
    // relance le décompte.
    LaunchedEffect(isPresented) {
        if (!isPresented) return@LaunchedEffect
        delay(TripAwaitingServer.noticeDuration)
        dismiss(false)
    }
}
