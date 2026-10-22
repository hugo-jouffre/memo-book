package com.memobook.feature.tripsettings

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.PageTargetTripStage
import com.memobook.design.BrandButton
import com.memobook.design.BrandNotice
import com.memobook.design.BrandSheet
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookSpacing
import kotlinx.coroutines.launch

/**
 * La feuille qui accompagne un changement de nombre de pages cible, une fois
 * qu'une étape du voyage est écrite (Hugo, 15/10/2026). Jumeau de
 * `TripSettings/PageTargetChangeSheet.swift`.
 *
 * **Une seule feuille, dont le contenu change** — comme `SubscriptionSheet` :
 * l'avertissement, la question du stade, puis ce qui est fait. Trois feuilles
 * empilées feraient reculer l'app trois fois, et un chemin se lirait comme un
 * empilement de fenêtres. C'est le modèle qui tient l'étape
 * ([PageTargetChange.Step]) : la feuille ne fait que la dessiner et appeler
 * ses gestes.
 *
 * Tant qu'un envoi attend sa réponse, elle ne se referme pas au glissé : on ne
 * saurait plus si la cible a changé. C'est l'écran qui la présente qui le dit
 * à son `BrandSheetHost` — `dismissDisabled = pageTargetChange?.isWorking == true`,
 * l'`interactiveDismissDisabled` d'iOS.
 */
@Composable
internal fun PageTargetChangeSheet(model: BookCustomisationModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val change = state.pageTargetChange ?: return

    AnimatedContent(
        targetState = change.step,
        transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(300)) },
        label = "étape du changement de cible",
    ) { step ->
        when (step) {
            is PageTargetChange.Step.Confirm -> PageTargetConfirm(model, change, changesLeft = step.changesLeft)
            PageTargetChange.Step.Stage -> PageTargetStage(model, change)
            PageTargetChange.Step.LimitReached -> PageTargetLimitReached(model)
            is PageTargetChange.Step.Done -> PageTargetDone(
                model,
                change,
                stage = step.stage,
                ratio = state.customisation?.photoTextRatio ?: 50,
            )
        }
    }
}

/**
 * Les trois réponses à « À quel stade de ton voyage en es-tu ? ». « Au début »
 * et « à la moitié » mènent au même cas — on ne touche pas à ce qui est
 * écrit —, mais la question en pose trois : c'est ainsi qu'on y répond sans
 * calculer.
 */
private enum class StageChoice(val title: String) {
    Beginning(BookCopy.Pages.stageBeginning),
    Middle(BookCopy.Pages.stageMiddle),
    End(BookCopy.Pages.stageEnd),
    ;

    val stage: PageTargetTripStage
        get() = if (this == End) PageTargetTripStage.End else PageTargetTripStage.BeginningOrMiddle
}

// MARK: - 1. L'avertissement

@Composable
private fun PageTargetConfirm(model: BookCustomisationModel, change: PageTargetChange, changesLeft: Int) {
    BrandSheet(BookCopy.Pages.changeTitle, subtitle = BookCopy.Pages.changeWarning(changesLeft = changesLeft)) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            Failure(change)

            BrandButton(
                BookCopy.Pages.confirmChange,
                isLoading = change.isWorking,
                fillsWidth = true,
                action = model::confirmPageTargetChange,
            )
            BrandButton(
                BookCopy.Pages.cancelChange,
                style = BrandButton.Style.Secondary,
                fillsWidth = true,
                action = model::dismissPageTargetChange,
            )
        }
    }
}

// MARK: - 2. Le stade du voyage, sans date de fin

@Composable
private fun PageTargetStage(model: BookCustomisationModel, change: PageTargetChange) {
    // Le stade touché, pour que seul son bouton attende — les deux autres
    // restent à leur place, sans roue.
    var chosenStage by remember { mutableStateOf<StageChoice?>(null) }

    BrandSheet(BookCopy.Pages.stageTitle) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            Failure(change)

            StageChoice.entries.forEach { choice ->
                BrandButton(
                    choice.title,
                    style = BrandButton.Style.Secondary,
                    isLoading = change.isWorking && chosenStage == choice,
                    fillsWidth = true,
                ) {
                    chosenStage = choice
                    model.choosePageTargetStage(choice.stage)
                }
            }
        }
    }
}

// MARK: - La limite

/**
 * Le serveur a refusé : les deux changements étaient faits — par un
 * co-voyageur, le plus souvent, entre l'ouverture et l'envoi.
 */
@Composable
private fun PageTargetLimitReached(model: BookCustomisationModel) {
    BrandSheet(BookCopy.Pages.changeTitle) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandNotice(BookCopy.Pages.limitReached, tone = BrandNotice.Tone.Warning)

            BrandButton(BookCopy.Pages.understood, fillsWidth = true, action = model::dismissPageTargetChange)
        }
    }
}

// MARK: - 3. C'est noté

/**
 * Au début ou au milieu du voyage, la suite suffit à rendre le carnet
 * homogène : un seul « OK », et pas un mot de réécriture — l'écrit ne bouge
 * pas. Vers la fin, la feuille propose d'étoffer ou de condenser ce qui est
 * écrit.
 */
@Composable
private fun PageTargetDone(model: BookCustomisationModel, change: PageTargetChange, stage: PageTargetTripStage, ratio: Int) {
    val scope = rememberCoroutineScope()
    val paragraphs = buildList {
        add(BookCopy.Pages.doneSummary(from = change.from, to = change.to, tripDays = change.tripDays, ratio = ratio))
        if (stage == PageTargetTripStage.End) add(BookCopy.Pages.rewriteOffer(isLonger = change.isLonger))
    }

    BrandSheet(BookCopy.Pages.doneTitle, paragraphs = paragraphs) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            Failure(change)

            when (stage) {
                PageTargetTripStage.End -> {
                    BrandButton(
                        BookCopy.Pages.rewriteAction(isLonger = change.isLonger),
                        isLoading = change.isWorking,
                        fillsWidth = true,
                    ) {
                        scope.launch { model.rewriteWrittenSteps() }
                    }
                    BrandButton(
                        BookCopy.Pages.later,
                        style = BrandButton.Style.Secondary,
                        fillsWidth = true,
                        action = model::dismissPageTargetChange,
                    )
                }
                PageTargetTripStage.BeginningOrMiddle -> BrandButton(
                    BookCopy.Pages.ok,
                    fillsWidth = true,
                    action = model::dismissPageTargetChange,
                )
            }
        }
    }
}

/**
 * L'envoi a raté pour une autre raison que la limite : la feuille reste à son
 * étape, et le bouton se retouche.
 */
@Composable
private fun Failure(change: PageTargetChange) {
    change.errorMessage?.let { ErrorBanner(message = it) }
}
