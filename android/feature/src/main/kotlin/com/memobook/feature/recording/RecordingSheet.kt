package com.memobook.feature.recording

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.BrandWaveform
import com.memobook.design.ErrorBanner
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.RecordButton
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.chat.DailyCreditBanner
import com.memobook.feature.chat.DailyCreditBannerView
import com.memobook.recording.AudioRecorder
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * La feuille où l'on parle. Jumeau de `RecordingSheet.swift`.
 *
 * C'est **le** cœur du produit : tout ce que l'app sait faire commence ici.
 * D'où le bleu — voir [MemoBookColor.listeningBackground] : on quitte le
 * papier crème sur lequel on lit son carnet pour passer de l'autre côté, celui
 * où on le remplit.
 *
 * **Rien à choisir avant de parler.** Pas de sélecteur de voyage, pas de titre
 * à saisir : on appuie, on raconte. C'est le sous-titre qui porte la promesse —
 * MemoBook rangera le souvenir tout seul.
 *
 * Quatre commandes, et leurs rôles ne se recouvrent pas :
 *
 * - le **disque** ouvre et referme le micro ;
 * - la **flèche circulaire** jette ce qui vient d'être dit et recommence ;
 * - les **deux barres** suspendent, pour reprendre son souffle ;
 * - le **rond de fermeture** de la feuille abandonne tout.
 *
 * **Le crédit du jour du voyage en cours** (Hugo, 03/10/2026) : le bandeau
 * rouge doux se pose au-dessus du disque — à trente secondes de la limite,
 * puis il pulse, et l'enregistrement s'arrête net à zéro (le vocal part, et la
 * conversation s'ouvre dessus). Crédit déjà épuisé, le disque pâlit et le
 * bandeau « Crédit du jour épuisé » mène à l'offre — la feuille se referme
 * d'abord : une feuille ne s'empile pas sous un plein écran.
 *
 * ### L'ouvrir — depuis l'accueil, depuis la conversation
 *
 * Comme sur iOS (`.brandSheet(isPresented:)`), l'écran qui présente la feuille
 * l'enveloppe dans `BrandSheetHost`, **après** avoir obtenu l'accès au micro
 * ([rememberRecordingPermissionRequest]) :
 *
 * ```kotlin
 * var isRecording by remember { mutableStateOf(false) }
 * BrandSheetHost(isPresented = isRecording, onDismissRequest = { isRecording = false }) {
 *     RecordingSheet(
 *         credit = subscription.applied(model.ongoingTripCredit) ?: model.ongoingTripCredit,
 *         onSubscribe = { showsPaywall = true },
 *     ) { audio, levels, stoppedAtLimit ->
 *         val handoff = RecordingHandoff(audio = audio, levels = levels, stoppedAtLimit = stoppedAtLimit)
 *         // le vocal part par la file (`outbox.submit(OutgoingTurn.voice(audio, levels, id = handoff.id), tripId)`),
 *         // et l'écran annonce `HomeIntent.OpenConversation(tripId, handoff)`.
 *     }
 * }
 * ```
 *
 * La feuille se referme d'elle-même quand un vocal en sort, puis appelle
 * `onFinish` ; elle ne l'envoie nulle part. Quittée sans « Envoyer » — glissé,
 * retour, rond de fermeture —, elle jette ce qui a été dit.
 *
 * @param credit le crédit du jour du voyage en cours, tel que l'accueil le tient.
 * @param onSubscribe ce que fait le bandeau « épuisé » : ouvrir l'offre, **une
 *   fois la feuille refermée**.
 * @param onFinish le vocal, une fois terminé, les niveaux relevés pendant qu'on
 *   parlait, et si c'est la limite du jour qui l'a coupé. La feuille ne
 *   l'envoie nulle part : elle le rend, et c'est l'écran qui l'a présentée qui
 *   décide de son sort — l'envoyer, et l'emporter dans la conversation
 *   ([RecordingHandoff]).
 */
@Composable
fun RecordingSheet(
    credit: DailyCredit? = null,
    onSubscribe: () -> Unit = {},
    onFinish: (RecordedAudio, List<Double>, Boolean) -> Unit,
) {
    val context = LocalContext.current
    val isPreview = LocalInspectionMode.current
    val requestMicrophone = rememberRecordingPermissionRequest()
    val model = remember {
        RecordingModel(
            recorder = AudioRecorder(context.applicationContext, requestPermission = { requestMicrophone() }),
            credit = credit,
        )
    }
    val dismiss = LocalBrandSheetDismiss.current
    val reduceMotion = isReduceMotionEnabled()
    val haptics = LocalHapticFeedback.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val currentOnFinish by rememberUpdatedState(onFinish)
    val currentOnSubscribe by rememberUpdatedState(onSubscribe)

    val recorder by model.recorder.state.collectAsStateWithLifecycle()
    val levels by model.levels.collectAsStateWithLifecycle()
    val errorMessage by model.errorMessage.collectAsStateWithLifecycle()
    val isBusy by model.isBusy.collectAsStateWithLifecycle()

    /**
     * Le bandeau « épuisé » a été touché : l'offre s'ouvrira quand la feuille
     * aura fini de descendre.
     */
    var opensOfferOnClose by remember { mutableStateOf(false) }

    // **On appuie une fois, pas deux.** « Commencer à enregistrer » est déjà la
    // décision de parler : demander un second appui sur le disque faisait
    // perdre les premiers mots, ceux qu'on dit toujours pendant que la feuille
    // monte. Le micro s'ouvre donc avec elle, et le disque ne sert plus qu'à
    // s'arrêter.
    //
    // C'est aussi ici qu'apparaît la demande d'accès au micro, si l'écran qui
    // présente ne l'a pas déjà posée. `start()` ne fait rien si
    // l'enregistrement tourne déjà : rouvrir la feuille ne peut pas en lancer deux.
    LaunchedEffect(model) {
        model.onFeedback = { feedback ->
            haptics.performHapticFeedback(
                when (feedback) {
                    RecordingModel.Feedback.Warning -> HapticFeedbackType.Reject
                    RecordingModel.Feedback.Light -> HapticFeedbackType.SegmentTick
                    RecordingModel.Feedback.Medium -> HapticFeedbackType.ContextClick
                },
            )
        }
        // L'annonce doit survivre à la feuille qui descend juste après l'arrêt
        // net : c'est la vue de l'app qui la porte, comme `UIAccessibility.post`.
        model.onAnnouncement = { message ->
            @Suppress("DEPRECATION")
            view.announceForAccessibility(message)
        }
        // L'arrêt net rend le vocal comme « Envoyer » : il part, et la
        // conversation s'ouvre dessus.
        model.onLimitReached = { audio, captured ->
            dismiss()
            currentOnFinish(audio, captured, true)
        }
        if (!isPreview) model.start()
    }

    // Quitter la feuille au glissé, c'est renoncer : le micro se referme et rien
    // n'est gardé. Sans ça, l'enregistrement continuait de tourner derrière un
    // écran qu'on croyait avoir fermé.
    DisposableEffect(model) {
        onDispose {
            model.close()
            if (opensOfferOnClose) {
                opensOfferOnClose = false
                currentOnSubscribe()
            }
        }
    }

    /** « Crédit du jour épuisé » touché : la feuille descend, puis l'offre monte en plein écran. */
    fun openOffer() {
        opensOfferOnClose = true
        dismiss()
    }

    /**
     * Le geste du disque. Il ne referme la feuille que lorsqu'un vocal en
     * sort : en pause, le disque reprend et la feuille reste.
     */
    fun toggle() {
        scope.launch {
            // Le relevé **entier**, et non la frise : `levels` ne garde que les
            // quarante dernières barres, celles qui défilent sous le micro. La
            // bulle du fil, elle, dessine tout le vocal.
            //
            // Et lu **avant** de refermer : la feuille l'efface en disparaissant
            // (`discard()`).
            val captured = model.capturedLevels
            val audio = model.toggle() ?: return@launch
            dismiss()
            currentOnFinish(audio, captured, false)
        }
    }

    BrandSheet(
        title = "Enregistrement",
        subtitle = RecordingCopy.subtitle(model.currentCredit),
        titleAlignment = BrandSheet.TitleAlignment.Centered,
        surface = BrandSheet.Surface.Listening,
    ) {
        Column(
            Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            errorMessage?.let { ErrorBanner(message = it) }

            // Recompté à chaque relevé du micro : lu ici, où `recorder` se lit.
            val banner = if (recorder.elapsed >= 0) model.creditBanner else null

            // Au-dessus du disque, **dans la pile** : il se touche.
            AnimatedVisibility(
                visible = banner != null,
                enter = if (reduceMotion) fadeIn(snap()) else fadeIn(SwiftMotion.smooth(0.3f)) + slideInVertically(SwiftMotion.smooth(0.3f)) { -it },
                exit = if (reduceMotion) fadeOut(snap()) else fadeOut(SwiftMotion.smooth(0.3f)) + slideOutVertically(SwiftMotion.smooth(0.3f)) { -it },
            ) {
                // Le dernier bandeau reste dessiné pendant qu'il s'en va.
                val shown = remember { RetainedBanner() }
                if (banner != null) shown.value = banner
                shown.value?.let { DailyCreditBannerView(it, onSubscribe = ::openOffer) }
            }

            // Pâli, pas désactivé : le toucher dit pourquoi rien ne s'ouvre.
            RecordButton(
                isRecording = recorder.isRecording,
                isPaused = recorder.isPaused,
                isBusy = isBusy,
                level = recorder.level,
                modifier = Modifier.alpha(if (model.isCreditExhausted) 0.45f else 1f),
                action = ::toggle,
            )

            Elapsed(isRecording = recorder.isRecording, label = model.elapsedLabel)
            BrandWaveform(live = levels, isDimmed = recorder.isPaused)
            Status(statusLabel(isRecording = recorder.isRecording, isPaused = recorder.isPaused))
            SecondaryControls(
                isRecording = recorder.isRecording,
                isPaused = recorder.isPaused,
                onRestart = { scope.launch { model.restart() } },
                onTogglePause = model::togglePause,
            )
        }
    }
}

/** Le bandeau qu'on montrait, gardé le temps qu'il disparaisse — sans recomposer pour lui. */
private class RetainedBanner {
    var value: DailyCreditBanner? = null
}

/**
 * Le chrono. Il n'apparaît qu'une fois qu'il y a quelque chose à compter : un
 * « 0:00 » posé sous un bouton qu'on n'a pas encore touché n'annonce rien, il
 * occupe.
 */
@Composable
private fun Elapsed(isRecording: Boolean, label: String) {
    AnimatedVisibility(visible = isRecording, enter = fadeIn(), exit = fadeOut()) {
        // Les chiffres ne dansent pas : les chiffres de General Sans sont à
        // chasse fixe, et le changement de seconde glisse plutôt qu'il ne saute.
        AnimatedContent(
            targetState = label,
            transitionSpec = {
                (fadeIn(SwiftMotion.snappy(0.2f)) + slideInVertically(SwiftMotion.snappy(0.2f)) { it / 2 }) togetherWith
                    (fadeOut(SwiftMotion.snappy(0.2f)) + slideOutVertically(SwiftMotion.snappy(0.2f)) { -it / 2 })
            },
            modifier = Modifier.semantics { contentDescription = "Durée : $label" },
            label = "chrono",
        ) { text ->
            BrandText(text, MemoBookFont.bodySemibold, color = MemoBookColor.ink)
        }
    }
}

/**
 * Ce que l'app fait, dit en un mot sous la frise : elle attend, elle
 * enregistre, elle est en pause.
 *
 * Il n'y a pas de mots transcrits à mesure qu'on parle : sur l'iPhone, la
 * reconnaissance vocale faisait disparaître l'app dès l'ouverture de la
 * feuille, et la conversation prouve qu'on enregistre très bien sans elle
 * (T176) ; sur Android, le micro ne se partage pas (`SpeechTranscriber.kt`).
 * C'est le serveur qui transcrit le vocal, une fois envoyé.
 */
@Composable
private fun Status(label: String) {
    AnimatedContent(
        targetState = label,
        transitionSpec = { fadeIn(tween(250, easing = SwiftMotion.easeOut)) togetherWith fadeOut(tween(250, easing = SwiftMotion.easeOut)) },
        modifier = Modifier.fillMaxWidth(),
        label = "statut",
    ) { text ->
        BrandText(
            text,
            MemoBookFont.body,
            modifier = Modifier.fillMaxWidth(),
            color = MemoBookColor.inkMuted,
            textAlign = TextAlign.Center,
        )
    }
}

private fun statusLabel(isRecording: Boolean, isPaused: Boolean): String {
    if (isPaused) return "En pause"
    return if (isRecording) "MemoBook enregistre" else "Prêt à enregistrer…"
}

/**
 * Recommencer et suspendre. Les deux ne servent que pendant qu'on enregistre :
 * au repos, ils n'auraient rien à annuler ni à suspendre.
 */
@Composable
private fun SecondaryControls(
    isRecording: Boolean,
    isPaused: Boolean,
    onRestart: () -> Unit,
    onTogglePause: () -> Unit,
) {
    Row(Modifier.fillMaxWidth().padding(horizontal = MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
        CircularControl(
            icon = R.drawable.system_arrow_counterclockwise,
            label = "Recommencer",
            isEnabled = isRecording,
            action = onRestart,
        )

        Spacer(Modifier.weight(1f))

        CircularControl(
            icon = if (isPaused) R.drawable.system_play_fill else R.drawable.system_pause_fill,
            label = if (isPaused) "Reprendre" else "Mettre en pause",
            isEnabled = isRecording,
            action = onTogglePause,
        )
    }
}

/**
 * Une commande secondaire : un tracé nu, sans pastille ni cadre.
 *
 * Le symbole système d'iOS redessiné (`system_*.xml`) et non le jeu de
 * marque : ni la flèche circulaire ni la pause n'y existent. Un seul endroit à
 * changer le jour où le jeu les gagne.
 */
@Composable
private fun CircularControl(icon: Int, label: String, isEnabled: Boolean, action: () -> Unit) {
    val tint by animateFloatAsState(if (isEnabled) 1f else 0.25f, tween(200, easing = SwiftMotion.easeOut), label = "teinte")
    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                enabled = isEnabled,
                role = Role.Button,
                onClickLabel = label,
                onClick = action,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink.copy(alpha = MemoBookColor.ink.alpha * tint)),
            modifier = Modifier.size(scaled(24.dp)),
        )
    }
}

/** Les textes de la feuille qui dépendent du crédit du jour. Jumeau de `RecordingCopy`. */
internal object RecordingCopy {
    /**
     * Le sous-titre. « Enregistre tout ce que tu veux » ne se dit plus qu'à un
     * abonné : à un voyage qui a cinq minutes par jour, ce serait mentir (Hugo,
     * 03/10/2026).
     *
     * **Pas de chiffre** pour qui a encore du crédit (03/10/2026) : lu à
     * l'ouverture, il restait figé pendant que le bandeau, juste dessous,
     * compte à rebours — et « Il te reste 3 min 20 aujourd’hui, et MemoBook
     * l’attribuera » donnait à MemoBook le temps restant à ranger. C'est le
     * bandeau qui dit ce qui reste, à trente secondes de la limite.
     */
    fun subtitle(credit: DailyCredit?): String {
        if (credit == null) return storyline
        if (credit.isUnlimited) return "Enregistre tout ce que tu veux et MemoBook l’attribuera automatiquement"
        if (credit.isExhausted) return "Ce voyage a raconté ses ${DailyCreditCopy.duration(credit.limitMs)} du jour"
        return storyline
    }

    /** La promesse de la feuille : on raconte, MemoBook range — « l’ » reprend la journée qu'on raconte. */
    const val storyline = "Raconte ta journée et MemoBook l’attribuera automatiquement"
}

// MARK: - Aperçus

/** Les crédits des aperçus — le `ChatCreditFixture` d'iOS, rechargés demain. */
private object RecordingPreviewCredit {
    private val tomorrow = Instant.now().plus(1, ChronoUnit.DAYS)
    val fresh = DailyCredit(usedMs = 120_000, resetsAt = tomorrow)
    val exhausted = DailyCredit(usedMs = DailyCredit.Catalog.limitMs, resetsAt = tomorrow)
    val unlimited = DailyCredit(isUnlimited = true, usedMs = 276_000, resetsAt = tomorrow)
}

@Composable
private fun RecordingSheetPreviewFrame(credit: DailyCredit) {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        RecordingSheet(credit = credit) { _, _, _ -> }
    }
}

@Preview(locale = "fr-rFR", name = "Enregistrement", widthDp = 390, heightDp = 844)
@Composable
private fun RecordingSheetPreview() = RecordingSheetPreviewFrame(RecordingPreviewCredit.fresh)

@Preview(locale = "fr-rFR", name = "Enregistrement — crédit épuisé", widthDp = 390, heightDp = 844)
@Composable
private fun RecordingSheetExhaustedPreview() = RecordingSheetPreviewFrame(RecordingPreviewCredit.exhausted)

@Preview(locale = "fr-rFR", name = "Enregistrement — abonné", widthDp = 390, heightDp = 844)
@Composable
private fun RecordingSheetUnlimitedPreview() = RecordingSheetPreviewFrame(RecordingPreviewCredit.unlimited)
