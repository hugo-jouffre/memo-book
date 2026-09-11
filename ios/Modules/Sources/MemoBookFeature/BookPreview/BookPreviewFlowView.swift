import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le parcours de l'aperçu du carnet : la page qui se monte, puis le carnet
/// qu'on feuillette.
///
/// **Un seul écran pour les deux temps**, parce que c'en est un seul :
/// la composition finit et l'aperçu apparaît, sans que personne appuie sur quoi
/// que ce soit. Deux destinations de navigation auraient laissé la composition
/// dans la pile, et la flèche de retour de l'aperçu y serait revenue.
///
/// On y arrive de trois endroits, et c'est voulu — c'est le même carnet :
/// la bannière bleue de la conversation, l'icône de carnet de son en-tête, et
/// la ligne « Prévisulation PDF » des paramètres du voyage.
public struct BookPreviewFlowView: View {
    @State private var model: BookPreviewModel

    /// Le mot des fondateurs s'ouvre tout seul, une fois dans la vie du
    /// compte. Voir ``OnboardingStorage/hasSeenFoundersNote``.
    @AppStorage(OnboardingStorage.hasSeenFoundersNote) private var hasSeenFoundersNote = false

    @State private var showsFoundersNote = false
    @State private var showsShareChoice = false

    /// Ce qui part dans la feuille de partage du système. `nil` quand rien n'est
    /// en partage — c'est ce qui la présente.
    @State private var systemShare: BookSharePayload?

    private let onIntent: (BookPreviewIntent) -> Void

    /// Combien de temps l'aperçu tourne avant que le mot des fondateurs
    /// s'invite.
    ///
    /// Douze secondes : la maquette dit « 10 à 15 », et il faut laisser le
    /// temps de tourner deux ou trois pages avant d'interrompre. Plus tôt, la
    /// feuille couvrirait un carnet qu'on n'a pas encore vu ; plus tard, elle
    /// arriverait après qu'on a rangé le téléphone.
    private static let foundersDelay: Duration = .seconds(12)

    public init(
        model: BookPreviewModel,
        onIntent: @escaping (BookPreviewIntent) -> Void
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        content
            .background(MemoBookColor.background.ignoresSafeArea())
            .brandHiddenNavigationBar()
            // Le crème de la marque ne se retourne pas en sombre — voir
            // `MemoBookColor`.
            .environment(\.colorScheme, .light)
            .task { await model.run() }
            .task(id: model.stage) { await inviteFoundersNoteIfNeeded() }
            .brandSheet(isPresented: $showsFoundersNote) {
                FoundersNoteSheet(
                    onFeedback: { onIntent(.shareFeedback) },
                    onContinue: { showsFoundersNote = false }
                )
            }
            .brandSheet(isPresented: $showsShareChoice) {
                ShareBookSheet(
                    preview: model.preview,
                    isPreparingLink: model.isPreparingLink,
                    onSharePdf: { Task { await share(.pdf) } },
                    onShareLink: { Task { await share(.link) } }
                )
            }
            // La feuille de partage du système, et non une feuille de la
            // marque : c'est **elle** qui connaît les apps installées, les
            // AirDrop à portée et les raccourcis de l'utilisateur. En
            // redessiner une ne donnerait qu'une liste plus courte.
            .sheet(item: $systemShare) { payload in
                BookShareSheet(payload: payload)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .composing:
            BookCompositionView(model: model, onIntent: onIntent, onShare: openShare)
                // La composition s'efface **en montant** d'un cheveu, et
                // l'aperçu arrive de la même façon : la page qui vient de se
                // monter et celle qu'on va feuilleter sont la même, elle ne
                // doit pas glisser sur le côté.
                .transition(.opacity.combined(with: .scale(scale: 1.03)))

        case .preview:
            Group {
                if model.isFullScreen {
                    BookFullScreenView(model: model, onShare: openShare)
                        .transition(.opacity)
                } else {
                    BookReaderView(model: model, onIntent: onIntent, onShare: openShare)
                        .transition(.opacity)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func openShare() {
        showsShareChoice = true
    }

    /// Ouvre la feuille de partage du système avec ce qu'il faut dedans.
    ///
    /// La feuille de choix se referme **d'abord** : sans ça, on retrouverait
    /// « Partager ton MemoBook » sous la feuille du système en sortant, et il
    /// faudrait la fermer deux fois.
    private func share(_ kind: BookShareKind) async {
        let title = model.preview?.title ?? ""
        let steps = model.preview?.pageCount ?? 0

        switch kind {
        case .pdf:
            guard let file = model.exportPdf() else { return }
            // Le lien de la cagnotte accompagne **aussi** le PDF : c'est le
            // message qui demande un coup de main, pas la pièce jointe.
            let link = await model.prepareShareLink()
            showsShareChoice = false
            systemShare = BookSharePayload(title: title, steps: steps, file: file, link: link)

        case .link:
            guard let link = await model.prepareShareLink() else { return }
            showsShareChoice = false
            systemShare = BookSharePayload(title: title, steps: steps, file: nil, link: link)
        }
    }

    /// Invite le mot des fondateurs, une fois l'aperçu ouvert et si on ne l'a
    /// jamais lu.
    ///
    /// La tâche est attachée à ``BookPreviewModel/stage`` : elle démarre quand
    /// l'aperçu apparaît et s'annule si l'écran se referme avant. Quitter
    /// l'écran au bout de trois secondes ne doit pas faire surgir une feuille
    /// sur l'écran suivant.
    private func inviteFoundersNoteIfNeeded() async {
        guard model.stage == .preview, !hasSeenFoundersNote else { return }

        try? await Task.sleep(for: Self.foundersDelay)
        guard !Task.isCancelled else { return }

        // Ni par-dessus la feuille de partage, ni par-dessus le plein écran :
        // le mot des fondateurs s'invite, il n'interrompt pas.
        guard !showsShareChoice, systemShare == nil, !model.isFullScreen else { return }

        hasSeenFoundersNote = true
        showsFoundersNote = true
    }

    private enum BookShareKind { case pdf, link }
}

/// Ce que l'aperçu demande à l'app d'ouvrir. Comme partout, ``RootView`` seul
/// tient la pile de navigation.
public enum BookPreviewIntent: Sendable, Hashable {
    /// « Personnaliser mon carnet ».
    case customise
    /// « Commander ce carnet ».
    case order
    /// « Voir ma cagnotte ».
    case openWallet
    /// Configurer la première ou la quatrième de couverture.
    case configureCovers
    /// « Partager mes retours », depuis le mot des fondateurs.
    case shareFeedback
}

// MARK: - On compose ton Carnet

/// L'attente : une page de carnet qui se monte sous les yeux.
///
/// Elle occupe exactement la place de l'aperçu qui va suivre — même en-tête,
/// mêmes boutons, même carte de cagnotte —, et c'est ce qui fait que le
/// passage de l'un à l'autre ne saute pas. Seule la page change, et c'est bien
/// la seule chose qui ait changé.
private struct BookCompositionView: View {
    let model: BookPreviewModel
    let onIntent: (BookPreviewIntent) -> Void
    let onShare: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(
                    title: BookCopy.Composition.title,
                    subtitle: BookCopy.Composition.message
                ) {
                    BrandHeaderAction(
                        icon: "IconTeleverser",
                        label: BookCopy.Preview.Voice.share,
                        action: onShare
                    )
                }
                // Le partage n'a rien à partager tant que le carnet n'est pas
                // composé. Le bouton reste à sa place — il déciderait sinon de
                // la hauteur de l'en-tête en apparaissant.
                .disabled(true)

                BookPageStage {
                    BookCompositionPage(progress: model.compositionProgress)
                }

                // L'indicateur de pages tient sa place pendant la composition,
                // en barre d'attente : c'est ce qui évite que les boutons du
                // dessous sautent de 43 pt quand l'aperçu arrive.
                BrandSkeleton(width: 96)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, MemoBookSpacing.snug)

                BookActionsBlock(
                    isEnabled: false,
                    onCustomise: { onIntent(.customise) },
                    onOrder: { onIntent(.order) }
                )

                BookOfferCard(
                    onShare: onShare,
                    onSeeWallet: { onIntent(.openWallet) }
                )

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.retry() }
                    }
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        // VoiceOver n'a pas besoin de la cascade : une phrase suffit à dire ce
        // qui se passe, et elle est annoncée sans interrompre la lecture.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(BookCopy.Composition.voiceOverStatus)
    }
}

// MARK: - Aperçu PDF

/// Le carnet qu’on feuillette : une page à la fois, et ce qu’on peut en faire.
///
/// `BookReaderView` et non `BookPreviewView` : ce dernier nom est déjà pris par
/// l’aperçu non brandé de `MemoDetail/`, qui montre un PDF dans un `PDFView`
/// nu. Les deux cohabiteront le temps que le détail d’un carnet passe à la
/// marque.
private struct BookReaderView: View {
    let model: BookPreviewModel
    let onIntent: (BookPreviewIntent) -> Void
    let onShare: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(
                    title: BookCopy.Preview.title,
                    subtitle: BookCopy.Preview.subtitle(
                        title: model.preview?.title ?? "",
                        pages: model.sheetCount
                    ),
                    isSubtitleLoading: model.preview == nil
                ) {
                    BrandHeaderAction(
                        icon: "IconTeleverser",
                        label: BookCopy.Preview.Voice.share,
                        action: onShare
                    )
                }

                BookPageStage {
                    BookSheetView(
                        model: model,
                        onExpand: { model.setFullScreen(true) },
                        onConfigureCovers: { onIntent(.configureCovers) }
                    )
                }

                BookPageStepper(model: model)

                BookActionsBlock(
                    isEnabled: model.renderer.sheetCount > 0,
                    onCustomise: { onIntent(.customise) },
                    onOrder: { onIntent(.order) }
                )

                BookOfferCard(
                    onShare: onShare,
                    onSeeWallet: { onIntent(.openWallet) }
                )

                if model.renderer.didFail {
                    ErrorBanner(message: BookCopy.Preview.loadFailed) {
                        Task { await model.reloadDocument() }
                    }
                } else if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.retry() }
                    }
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
    }
}

/// La scène où la page se pose : elle garde le rapport du carnet et se centre.
///
/// Partagée avec la feuille « Prévisualisation » du paywall : c'est la même
/// page, regardée depuis deux endroits, et elle doit y avoir exactement la même
/// boîte.
///
/// Elle existe pour une raison unique et vaut d'être un composant : la page en
/// composition et la page du PDF doivent occuper **exactement** la même boîte,
/// sinon le passage de l'une à l'autre décale tout l'écran de quelques points.
struct BookPageStage<Content: View>: View {
    @ViewBuilder let content: Content

    /// Le rapport de la maquette : 252 × 357, soit l'A5 du carnet.
    private static var ratio: CGFloat { 252.0 / 357.0 }

    /// La page ne prend pas toute la largeur de la colonne : la maquette la
    /// pose à 252 pt dans une colonne de 358, ce qui lui laisse de l'air des
    /// deux côtés. Une **fraction** et non 252 pt, pour que la page respire
    /// pareil sur un iPhone SE et sur un Pro Max (R5).
    private static var widthFraction: CGFloat { 252.0 / 358.0 }

    var body: some View {
        content
            .aspectRatio(Self.ratio, contentMode: .fit)
            // `containerRelativeFrame` et non un `GeometryReader` : celui-ci
            // prendrait toute la hauteur qu'on lui offre et ferait s'effondrer
            // la pile qui l'entoure.
            .containerRelativeFrame(.horizontal) { width, _ in width * Self.widthFraction }
            .frame(maxWidth: .infinity)
    }
}

/// La page regardée, avec ses deux commandes posées dessus.
struct BookSheetView: View {
    let model: BookPreviewModel
    /// `nil` retire la commande de plein écran. C'est le cas de la feuille du
    /// paywall : il faudrait en sortir pour entrer en plein écran, et on ne
    /// reviendrait pas à l'offre. Retirée, et non désactivée — un bouton qui ne
    /// fait rien est pire que pas de bouton.
    let onExpand: (() -> Void)?
    let onConfigureCovers: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .topLeading) {
            BookSheetImage(renderer: model.renderer, index: model.sheetIndex)
                .clipShape(.rect(cornerRadius: MemoBookSpacing.pageCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MemoBookSpacing.pageCornerRadius)
                        .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
                }
                // La page se remplace en fondu quand on tourne : sans ça, la
                // nouvelle apparaît d'un coup et le geste ne se sent pas.
                .id(model.sheetIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: model.sheetIndex)

            // L'invitation à choisir ses couvertures ne couvre que la première
            // et la dernière page — voir ``BookPreview/isConfigurableCover``.
            if model.isOnConfigurableCover {
                CoverInvitation(action: onConfigureCovers)
                    .clipShape(.rect(cornerRadius: MemoBookSpacing.pageCornerRadius))
                    .transition(.opacity)
            }

            if let onExpand {
                BookScreenModeButton(
                    icon: "IconFullScreen",
                    label: BookCopy.Preview.Voice.enterFullScreen,
                    action: onExpand
                )
                .padding(MemoBookSpacing.xs)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isOnConfigurableCover)
        .task(id: model.sheetIndex) {
            // La page voisine est rendue pendant qu'on lit celle-ci : tourner
            // ne coûte alors plus rien. Voir ``BookPageRenderer/prepare(around:width:)``.
            model.renderer.prepare(around: model.sheetIndex, width: 252 * displayScale)
        }
    }
}

/// Le voile posé sur une couverture pas encore choisie, et son invitation.
///
/// Le voile est celui de la maquette : la page passe en luminosité à 30 % sous
/// un aplat noir à 40 %. C'est assez pour qu'on voie qu'il y a une page dessous,
/// et pas assez pour qu'on la prenne pour la couverture définitive.
private struct CoverInvitation: View {
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)

            VStack(spacing: MemoBookSpacing.s) {
                Text(BookCopy.Preview.configureCover)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.onAction)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                BrandButton(
                    BookCopy.Preview.configureCoverAction,
                    style: .raised,
                    size: .small,
                    action: action
                )
            }
            .padding(MemoBookSpacing.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// « ‹ Page 4 / 10 › » — de quoi tourner les pages.
struct BookPageStepper: View {
    let model: BookPreviewModel

    var body: some View {
        HStack(spacing: MemoBookSpacing.l) {
            BookPageArrow(
                direction: .backward,
                label: BookCopy.Preview.Voice.previousPage,
                isEnabled: model.canGoBack,
                action: model.goBack
            )

            Text(BookCopy.Preview.pageIndicator(model.sheetIndex + 1, of: max(model.sheetCount, 1)))
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                // La largeur ne bouge pas d'une page à l'autre : sans ça, le
                // passage de « Page 9 / 10 » à « Page 10 / 10 » décale les deux
                // flèches.
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: model.sheetIndex)

            BookPageArrow(
                direction: .forward,
                label: BookCopy.Preview.Voice.nextPage,
                isEnabled: model.canGoForward,
                action: model.goForward
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.xs)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Aperçu PDF — sans document") {
    NavigationStack {
        BookPreviewFlowView(model: BookPreviewModel(memoId: "preview")) { _ in }
    }
}

#Preview("Aperçu PDF — AX3") {
    NavigationStack {
        BookPreviewFlowView(model: BookPreviewModel(memoId: "preview")) { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
