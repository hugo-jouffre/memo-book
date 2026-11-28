package com.memobook.feature.tripsettings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.RedactionManner
import com.memobook.core.RedactionSettings
import com.memobook.design.BrandButton
import com.memobook.design.BrandNotice
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandRow
import com.memobook.design.BrandRowGroup
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.BrandTextBox
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * **« Manière d'être rédigé »** — T292. Le jumeau de `RedactionMannerSheet.swift`.
 *
 * Trois manières, les indications libres du voyageur, et « Tout faire
 * reprendre ». Les fiches qui pilotent vraiment le modèle sont dans
 * `agents/redaction-manieres/` ; ici on ne montre que ce qu'on choisit.
 *
 * ⚠️ **La confirmation est un second temps de cette feuille**, et non une
 * feuille posée dessus : un enchaînement de feuilles ne s'empile pas
 * (`ios/CLAUDE.md`). C'est aussi là que le consentement est donné — le serveur
 * ne le redemande pas, il reprend le carnet dès que le réglage change.
 *
 * ⚠️ **Fermé, le réglage pâlit, il ne se désactive pas** : les manières restent
 * tapables, et l'appui pose la notice qui nomme la cause et la sortie.
 */
@Composable
internal fun RedactionMannerSheet(model: TripSettingsModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val dismiss = LocalBrandSheetDismiss.current
    val scope = rememberCoroutineScope()

    val redaction = state.settings?.redactionSettings ?: RedactionSettings.closed
    val isAvailable = redaction.isAvailable

    /** Ce que le second temps va faire si on confirme. */
    var pendingManner by remember { mutableStateOf<RedactionManner?>(null) }
    var pendingRewrite by remember { mutableStateOf(false) }
    val isConfirming = pendingManner != null || pendingRewrite

    // La manière cochée tant que l'aller-retour n'a pas répondu, comme sur la
    // feuille « Rythme du récit ».
    var chosen by remember { mutableStateOf<RedactionManner?>(null) }

    var notes by remember { mutableStateOf("") }
    var notesLoaded by remember { mutableStateOf(false) }
    var isWritingNotes by remember { mutableStateOf(false) }
    var explainsPaywall by remember { mutableStateOf(false) }

    LaunchedEffect(redaction.notes) {
        // Le champ se remplit **une fois** : relire à chaque réponse du serveur
        // écraserait ce qu'on est en train de taper.
        if (notesLoaded) return@LaunchedEffect
        notes = redaction.notes ?: ""
        notesLoaded = true
    }

    /** Demande confirmation — ou pose la notice, si le réglage est fermé. */
    fun askManner(manner: RedactionManner) {
        if (!isAvailable) {
            explainsPaywall = true
            return
        }
        // Choisir la manière déjà en place ne reprend rien : on ne demande même
        // pas, on referme.
        if (manner == redaction.manner) {
            dismiss()
            return
        }
        pendingManner = manner
    }

    fun askRewrite() {
        if (!isAvailable) {
            explainsPaywall = true
            return
        }
        pendingRewrite = true
    }

    fun commit() {
        pendingManner?.let { manner ->
            chosen = manner
            model.setRedactionManner(manner)
        }
        if (pendingRewrite) model.rewriteRedaction()
        pendingManner = null
        pendingRewrite = false
        scope.launch {
            delay(BrandOptionRow.lingerBeforeDismiss)
            dismiss()
        }
    }

    BrandSheet(
        if (isConfirming) BookCopy.Settings.Redaction.Confirm.title else BookCopy.Settings.Redaction.title,
        subtitle = if (isConfirming) {
            BookCopy.Settings.Redaction.Confirm.body
        } else {
            BookCopy.Settings.Redaction.subtitle
        },
    ) {
        Column(
            Modifier.animateContentSize(),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            if (isConfirming) {
                BrandButton(BookCopy.Settings.Redaction.Confirm.go, action = { commit() })
                BrandButton(
                    BookCopy.Settings.Redaction.Confirm.keep,
                    style = BrandButton.Style.Tertiary,
                    action = {
                        pendingManner = null
                        pendingRewrite = false
                    },
                )
            } else {
                BrandOptionGroup(Modifier.brandDimmed(isAvailable)) {
                    RedactionManner.entries.forEach { manner ->
                        BrandOptionRow(
                            mannerLabel(manner),
                            isSelected = (chosen ?: redaction.manner) == manner,
                            subtitle = mannerDetail(manner),
                            value = if (manner == RedactionManner.Spoken && redaction.chosenManner == null) {
                                BookCopy.Settings.Redaction.byDefault
                            } else {
                                null
                            },
                        ) {
                            askManner(manner)
                        }
                    }
                }

                AnimatedVisibility(visible = explainsPaywall) {
                    BrandNotice(
                        BookCopy.Settings.Redaction.needsUnlimited,
                        tone = BrandNotice.Tone.Information,
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    BrandText(
                        BookCopy.Settings.Redaction.notesTitle,
                        style = MemoBookFont.label,
                        color = MemoBookColor.ink,
                    )
                    BrandTextBox(
                        BookCopy.Settings.Redaction.notesPlaceholder,
                        value = notes,
                        onValueChange = { typed ->
                            // La coupe se voit **avant** l'envoi : le serveur
                            // tronque en silence, et couper après serait couper
                            // dans le texte de quelqu'un sans le lui dire.
                            notes = typed.take(RedactionSettings.NOTES_LIMIT)
                        },
                        isFocused = isWritingNotes,
                        onFocusChange = { focused ->
                            isWritingNotes = focused
                            // À la sortie du champ, comme le nom du voyage : un
                            // envoi par caractère ferait une requête par lettre,
                            // et chacune reprendrait le carnet.
                            if (!focused) model.setRedactionNotes(notes)
                        },
                        modifier = Modifier.brandDimmed(isAvailable),
                        lineSpan = 3..6,
                        accessibilityLabel = BookCopy.Settings.Redaction.notesTitle,
                    )
                    BrandText(
                        BookCopy.Settings.Redaction.notesHelp,
                        style = MemoBookFont.caption,
                        color = MemoBookColor.inkMuted,
                    )
                }

                if (isAvailable) {
                    BrandRowGroup {
                        +BrandRow(
                            BookCopy.Settings.Redaction.rewrite,
                            note = BookCopy.Settings.Redaction.rewriteDetail,
                            action = { askRewrite() },
                        )
                    }
                }
            }
        }
    }
}

/**
 * Le pâli de « ce qu'on ne peut pas faire » : 45 %, et le geste reste pris —
 * c'est l'appui qui pose la notice. Voir `ios/CLAUDE.md`.
 */
private fun Modifier.brandDimmed(isAvailable: Boolean): Modifier =
    if (isAvailable) this else this.alpha(0.45f)

/**
 * La valeur posée en bout de la ligne « Manière d'être rédigé » : la manière en
 * cours, suivie d'un point quand des indications s'y ajoutent — la ligne dit
 * ainsi qu'il y a plus à voir, sans recopier le texte.
 */
internal fun redactionLabel(settings: com.memobook.core.TripSettings?): String {
    val redaction = settings?.redaction ?: return BookCopy.Settings.noValue
    val name = mannerLabel(redaction.manner)
    return if (redaction.notes == null) name else "$name ·"
}

private fun mannerLabel(manner: RedactionManner): String = when (manner) {
    RedactionManner.Spoken -> BookCopy.Settings.Redaction.spoken
    RedactionManner.Literary -> BookCopy.Settings.Redaction.literary
    RedactionManner.Factual -> BookCopy.Settings.Redaction.factual
}

private fun mannerDetail(manner: RedactionManner): String = when (manner) {
    RedactionManner.Spoken -> BookCopy.Settings.Redaction.spokenDetail
    RedactionManner.Literary -> BookCopy.Settings.Redaction.literaryDetail
    RedactionManner.Factual -> BookCopy.Settings.Redaction.factualDetail
}

@Preview(locale = "fr-rFR", name = "Manière d'être rédigé", widthDp = 390, heightDp = 800)
@Composable
private fun RedactionMannerSheetPreview() {
    val model = remember { TripSettingsModel(tripId = "preview") }
    LaunchedEffect(model) { model.load() }
    Box(
        Modifier.fillMaxSize().background(MemoBookColor.background),
        contentAlignment = Alignment.BottomCenter,
    ) {
        RedactionMannerSheet(model)
    }
}
