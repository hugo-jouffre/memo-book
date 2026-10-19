import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La feuille qui accompagne un changement de nombre de pages cible, une fois
/// qu'une étape du voyage est écrite (Hugo, 15/10/2026).
///
/// **Une seule feuille, dont le contenu change** — comme
/// ``SubscriptionSheet`` : l'avertissement, la question du stade, puis ce qui
/// est fait. Trois feuilles empilées feraient reculer l'app trois fois, et un
/// chemin se lirait comme un empilement de fenêtres. C'est le modèle qui tient
/// l'étape (``PageTargetChange/Step``) : la feuille ne fait que la dessiner et
/// appeler ses gestes.
///
/// Tant qu'un envoi attend sa réponse, elle ne se referme pas au glissé : on
/// ne saurait plus si la cible a changé.
struct PageTargetChangeSheet: View {
    let model: BookCustomisationModel

    /// Le stade touché, pour que seul son bouton attende — les deux autres
    /// restent à leur place, sans roue.
    @State private var chosenStage: Choice?

    /// Les trois réponses à « À quel stade de ton voyage en es-tu ? ». « Au
    /// début » et « à la moitié » mènent au même cas — on ne touche pas à ce
    /// qui est écrit —, mais la question en pose trois : c'est ainsi qu'on y
    /// répond sans calculer.
    private enum Choice: CaseIterable {
        case beginning, middle, end

        var title: String {
            switch self {
            case .beginning: BookCopy.Pages.stageBeginning
            case .middle: BookCopy.Pages.stageMiddle
            case .end: BookCopy.Pages.stageEnd
            }
        }

        var stage: PageTargetTripStage {
            self == .end ? .end : .beginningOrMiddle
        }
    }

    var body: some View {
        Group {
            if let change = model.pageTargetChange {
                switch change.step {
                case .confirm(let changesLeft): confirm(change, changesLeft: changesLeft)
                case .stage: stage(change)
                case .limitReached: limitReached
                case .done(let stage): done(change, stage: stage)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: model.pageTargetChange?.step)
        .interactiveDismissDisabled(model.pageTargetChange?.isWorking == true)
    }

    // MARK: - 1. L'avertissement

    private func confirm(_ change: PageTargetChange, changesLeft: Int) -> some View {
        BrandSheet(
            BookCopy.Pages.changeTitle,
            subtitle: BookCopy.Pages.changeWarning(changesLeft: changesLeft)
        ) {
            VStack(spacing: MemoBookSpacing.s) {
                failure(change)

                BrandButton(
                    BookCopy.Pages.confirmChange,
                    isLoading: change.isWorking,
                    fillsWidth: true,
                    action: model.confirmPageTargetChange
                )
                BrandButton(
                    BookCopy.Pages.cancelChange,
                    style: .secondary,
                    fillsWidth: true,
                    action: model.dismissPageTargetChange
                )
            }
        }
    }

    // MARK: - 2. Le stade du voyage, sans date de fin

    private func stage(_ change: PageTargetChange) -> some View {
        BrandSheet(BookCopy.Pages.stageTitle) {
            VStack(spacing: MemoBookSpacing.s) {
                failure(change)

                ForEach(Choice.allCases, id: \.self) { choice in
                    BrandButton(
                        choice.title,
                        style: .secondary,
                        isLoading: change.isWorking && chosenStage == choice,
                        fillsWidth: true
                    ) {
                        chosenStage = choice
                        model.choosePageTargetStage(choice.stage)
                    }
                }
            }
        }
    }

    // MARK: - La limite

    /// Le serveur a refusé : les deux changements étaient faits — par un
    /// co-voyageur, le plus souvent, entre l'ouverture et l'envoi.
    private var limitReached: some View {
        BrandSheet(BookCopy.Pages.changeTitle) {
            VStack(spacing: MemoBookSpacing.m) {
                BrandNotice(BookCopy.Pages.limitReached, tone: .warning)

                BrandButton(
                    BookCopy.Pages.understood,
                    fillsWidth: true,
                    action: model.dismissPageTargetChange
                )
            }
        }
    }

    // MARK: - 3. C'est noté

    /// Au début ou au milieu du voyage, la suite suffit à rendre le carnet
    /// homogène : un seul « OK », et pas un mot de réécriture — l'écrit ne
    /// bouge pas. Vers la fin, la feuille propose d'étoffer ou de condenser ce
    /// qui est écrit.
    private func done(_ change: PageTargetChange, stage: PageTargetTripStage) -> some View {
        var paragraphs = [BookCopy.Pages.doneSummary(
            from: change.from,
            to: change.to,
            tripDays: change.tripDays,
            ratio: model.customisation?.photoTextRatio ?? 50
        )]
        if stage == .end { paragraphs.append(BookCopy.Pages.rewriteOffer(isLonger: change.isLonger)) }

        return BrandSheet(BookCopy.Pages.doneTitle, paragraphs: paragraphs) {
            VStack(spacing: MemoBookSpacing.s) {
                failure(change)

                switch stage {
                case .end:
                    BrandButton(
                        BookCopy.Pages.rewriteAction(isLonger: change.isLonger),
                        isLoading: change.isWorking,
                        fillsWidth: true
                    ) {
                        Task { await model.rewriteWrittenSteps() }
                    }
                    BrandButton(
                        BookCopy.Pages.later,
                        style: .secondary,
                        fillsWidth: true,
                        action: model.dismissPageTargetChange
                    )
                case .beginningOrMiddle:
                    BrandButton(
                        BookCopy.Pages.ok,
                        fillsWidth: true,
                        action: model.dismissPageTargetChange
                    )
                }
            }
        }
    }

    /// L'envoi a raté pour une autre raison que la limite : la feuille reste
    /// à son étape, et le bouton se retouche.
    @ViewBuilder
    private func failure(_ change: PageTargetChange) -> some View {
        if let message = change.errorMessage {
            ErrorBanner(message: message)
        }
    }
}

#Preview("Changer la cible — avertissement") {
    // Une étape déjà écrite, deux changements devant soi : le changement
    // compte, et la feuille s'ouvre.
    let model = BookCustomisationModel(
        tripId: "preview",
        source: { _ in
            var settings = TripSettings.fixture
            settings.pageTarget = PageTargetAllowance(changesLeft: 2, changesCount: true)
            return settings
        }
    )
    Color.clear
        .task {
            await model.load()
            model.setTargetPageCount(80)
        }
        .sheet(isPresented: .constant(true)) {
            PageTargetChangeSheet(model: model)
        }
}
