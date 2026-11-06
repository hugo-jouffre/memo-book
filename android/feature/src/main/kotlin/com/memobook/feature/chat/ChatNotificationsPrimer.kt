package com.memobook.feature.chat

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.isAccessibilityTextSize
import com.memobook.feature.AppSettings
import com.memobook.feature.notifications.LocalPushNotifications
import com.memobook.feature.notifications.NotificationAuthorization
import com.memobook.feature.notifications.rememberNotificationPermissionRequest
import kotlinx.coroutines.delay
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * **L'écran qui accompagne la question du système sur les notifications**, à
 * la première ouverture de la conversation d'un voyage qu'on vient de créer
 * (Hugo, 03/11/2026 ; maquette « Améliorons MemoBook ensemble »). Jumeau de
 * `Chat/ChatNotificationsPrimer.swift`.
 *
 * Il ne dessine pas la fenêtre — **c'est le système qui la pose**, par-dessus,
 * et lui seul peut le faire. L'écran, lui, tient le fond pendant ce temps-là :
 * le titre au-dessus, la flèche qui la désigne, et sous elle les deux phrases
 * qui disent à quoi sert la réponse. C'est un **contexte**, pas une étape : il
 * n'a ni bouton ni sortie, il s'efface dès que le système a sa réponse.
 *
 * **Il ne se montre qu'à qui n'a jamais répondu.** L'étape « Notifications »
 * de la création d'un voyage pose déjà la question quand on y choisit un
 * rythme — voir `docs/notifications.md`. Cet écran est le **recours** de qui a
 * passé cette étape : il arrive à la première conversation du voyage créé, là
 * où la promesse des relances se comprend enfin. Qui a déjà autorisé ou refusé
 * ne le voit jamais — il n'aurait porté aucune fenêtre.
 *
 * La suite appartient à [ChatNotificationsNudge] : un refus, ou une question
 * restée sans réponse, revient en bulle dans le fil.
 *
 * @param onAnswered le système a répondu : l'écran s'efface, et la
 *   conversation relit l'autorisation.
 * @param asksSystem poser la question au système. Seules les previews disent
 *   `false` : la question se pose toute seule ici, et une preview ne doit pas
 *   ouvrir de fenêtre système — elle reste donc sur l'écran, ce qui est
 *   justement ce qu'on vient y regarder.
 */
@Composable
fun ChatNotificationsPrimer(
    onAnswered: suspend () -> Unit,
    modifier: Modifier = Modifier,
    asksSystem: Boolean = true,
) {
    // `null` dans un aperçu, où aucune fenêtre système ne doit s'ouvrir.
    val pushNotifications = LocalPushNotifications.current
    val askSystem = rememberNotificationPermissionRequest()
    val answered by rememberUpdatedState(onAnswered)

    // **Après que l'écran est dessiné**, et non pendant : la fenêtre doit
    // arriver *sur* lui, pas à sa place — c'est tout ce que cet écran a à
    // faire.
    //
    // Dans le bac à sable, `PushNotifications` n'est pas branché (`null`) : la
    // question se pose alors directement au système, pour que l'écran se
    // vérifie quand même — comme [ChatNotificationsNudge].
    LaunchedEffect(asksSystem) {
        if (!asksSystem) return@LaunchedEffect
        delay(NotificationsPrimer.SETTLE_BEFORE_ASKING_MS)
        if (pushNotifications != null) pushNotifications.requestAuthorization(askSystem) else askSystem()
        answered()
    }

    // **Aux grandes tailles de texte, l'écran défile** : le titre et les deux
    // phrases ne tiennent plus entre l'en-tête et la barre d'envoi, et un
    // texte coupé par le bord vaut moins qu'un texte qu'on fait glisser. La
    // flèche, elle, ne se montre pas : c'est la place des phrases qu'elle
    // prendrait, et elle ne dit rien de plus que la fenêtre qu'elle désigne.
    val isLargeText = isAccessibilityTextSize()

    Column(
        modifier
            .fillMaxSize()
            // Opaque : le fil est derrière, et la maquette ne le montre pas.
            // Le crème seul, sans le motif de marque — celui de l'écran
            // continue en dessous, le redessiner ici le décalerait.
            .background(MemoBookColor.background)
            .then(if (isLargeText) Modifier.verticalScroll(rememberScrollState()) else Modifier)
            .padding(horizontal = MemoBookSpacing.screenMargin)
            // Le bas est plus serré que le haut : la flèche et les phrases
            // doivent passer **sous** la fenêtre du système, qui descend bas.
            .padding(top = MemoBookSpacing.l, bottom = MemoBookSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandText(
            text = NotificationsPrimer.TITLE,
            style = MemoBookFont.h1,
            color = MemoBookColor.ink,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { heading() },
        )

        // La place de la fenêtre du système : l'écran la laisse vide, c'est le
        // système qui la remplit. Pas de vide à distribuer dans une colonne
        // qui défile — le bloc du bas suit alors le titre.
        if (!isLargeText) Box(Modifier.weight(1f))

        // La flèche et les phrases sont **un bloc**, serré : il doit tenir
        // sous la fenêtre du système.
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            if (!isLargeText) {
                PrimerArrow(
                    Modifier
                        .align(Alignment.End)
                        .padding(end = MemoBookSpacing.xl)
                        .width(40.dp)
                        .height(44.dp),
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                NotificationsPrimer.paragraphs.forEach { paragraph ->
                    BrandText(
                        text = paragraph,
                        style = MemoBookFont.body,
                        color = MemoBookColor.inkMuted,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }
}

/**
 * La flèche dessinée de la maquette : elle part d'en bas à droite, remonte et
 * se recourbe vers la fenêtre, en haut à gauche.
 *
 * Un tracé et non un asset : le jeu de marque n'a pas de flèche courbe, et
 * celle-ci n'existe que sur cet écran.
 */
@Composable
private fun PrimerArrow(modifier: Modifier = Modifier) {
    val ink = MemoBookColor.ink
    Canvas(modifier) {
        val tip = Offset(0f, 0f)
        val tail = Offset(size.width, size.height)
        // Le point de contrôle, haut et à droite : la courbe part vers le bas
        // à droite, puis se redresse et arrive sur la pointe en diagonale,
        // comme sur la maquette.
        val control = Offset(size.width * 0.78f, size.height * 0.52f)

        val path = Path().apply {
            moveTo(tail.x, tail.y)
            quadraticTo(control.x, control.y, tip.x, tip.y)
        }

        // La pointe suit la tangente de la courbe — control → tip —, pour que
        // les barbes restent dans l'axe quelle que soit la taille du cadre.
        val heading = atan2((tip.y - control.y).toDouble(), (tip.x - control.x).toDouble())
        val length = size.height * BARB
        for (side in listOf(1.0, -1.0)) {
            val direction = heading + Math.PI + side * BARB_SPREAD
            path.moveTo(tip.x, tip.y)
            path.lineTo(
                tip.x + (cos(direction) * length).toFloat(),
                tip.y + (sin(direction) * length).toFloat(),
            )
        }

        drawPath(path, ink, style = Stroke(width = 5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** La longueur des deux barbes de la pointe, en part de la hauteur. */
private const val BARB = 0.34f

/** Leur écart de part et d'autre du tracé, en radians. */
private const val BARB_SPREAD = Math.PI * 32 / 180

/**
 * Ce que l'écran retient et ce qu'il dit — logique pure, testée. Jumeau de
 * l'`enum NotificationsPrimer` de Swift.
 *
 * La mémoire tient en **une** liste : les voyages créés sur cet appareil dont
 * la conversation n'a pas encore été ouverte. Créer un voyage y ajoute son
 * identifiant, l'ouvrir l'en retire — elle se vide donc toute seule, et il n'y
 * a pas de seconde liste à tenir d'accord avec la première.
 */
object NotificationsPrimer {
    /** Les voyages créés ici qui attendent leur première conversation. */
    private const val AWAITING_KEY = "memobook.notifications.primer.awaitingTrips"

    /**
     * Le temps qu'on laisse à l'écran pour se poser avant que la fenêtre du
     * système n'arrive dessus.
     */
    const val SETTLE_BEFORE_ASKING_MS = 350L

    /** Un voyage vient d'être créé sur cet appareil. */
    fun markTripCreated(tripId: String, settings: AppSettings) {
        val awaiting = awaitingTrips(settings)
        if (tripId in awaiting) return
        write(awaiting + tripId, settings)
    }

    /**
     * La conversation de ce voyage s'ouvre : rend `true` si c'est la première
     * fois, pour un voyage créé ici — et l'oublie, pour que la fois suivante
     * n'en soit plus une.
     */
    fun consumeFirstOpening(tripId: String, settings: AppSettings): Boolean {
        val awaiting = awaitingTrips(settings)
        if (tripId !in awaiting) return false
        write(awaiting - tripId, settings)
        return true
    }

    /**
     * L'écran se montre à la première conversation d'un voyage créé ici, **et
     * seulement si la question n'a jamais été posée** : un écran qui ne
     * porterait aucune fenêtre ne dirait rien.
     */
    fun isShown(isFirstOpeningOfANewTrip: Boolean, authorization: NotificationAuthorization): Boolean =
        isFirstOpeningOfANewTrip && authorization == NotificationAuthorization.NotDetermined

    // Les réglages ne savent que des chaînes : une ligne par identifiant.
    private fun awaitingTrips(settings: AppSettings): List<String> =
        settings.getString(AWAITING_KEY)?.lines()?.filter { it.isNotEmpty() } ?: emptyList()

    private fun write(trips: List<String>, settings: AppSettings) {
        settings.putString(AWAITING_KEY, trips.joinToString("\n").ifEmpty { null })
    }

    // MARK: - Les mots

    /** Le titre de la maquette, mot pour mot. */
    const val TITLE = "Améliorons MemoBook ensemble"

    /**
     * Les deux phrases sous la fenêtre. La seconde est celle de la maquette ;
     * la première y parlait de savoir comment on nous a découverts — ce que
     * cet écran ne demande pas. Elle dit donc ce que la réponse change
     * vraiment.
     */
    val paragraphs = listOf(
        "On s’en sert uniquement pour te faire signe quand il est temps de raconter la suite.",
        "Le contenu de ton carnet de voyage reste privé et nous n’allons jamais revendre tes données.",
    )
}

@Preview(name = "Notifications — l'écran de la question", showBackground = true)
@Composable
private fun ChatNotificationsPrimerPreview() {
    ChatNotificationsPrimer(onAnswered = {}, modifier = Modifier.size(390.dp, 700.dp), asksSystem = false)
}
