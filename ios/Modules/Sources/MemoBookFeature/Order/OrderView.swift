import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Commander mon Carnet : sept étapes, une seule charpente.
///
/// **Rien ne bouge autour de l'étape.** L'en-tête, sa flèche et le bouton du
/// bas sont à la même place du début à la fin ; seul le milieu glisse. C'est ce
/// qui rend la traversée lisible — on ne réapprend pas l'écran à chaque
/// « Continuer », on ne lit que ce qui change.
///
/// **L'écran ne navigue pas.** Il annonce une ``OrderIntent`` — j'ai fini, je
/// veux de l'aide, je veux partager — et `RootView` décide de la destination,
/// comme pour l'accueil et la galerie.
public struct OrderView: View {
    @State private var model: OrderModel
    private let onIntent: (OrderIntent) -> Void

    public init(model: OrderModel, onIntent: @escaping (OrderIntent) -> Void) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: OrderField?

    /// La feuille de choix du moyen de paiement.
    @State private var isChoosingPayment = false

    /// La feuille de partage du système, une fois le lien obtenu.
    @State private var systemShare: BookSharePayload?

    public var body: some View {
        VStack(spacing: 0) {
            header
            steps
        }
        .background(BrandBackdrop())
        .brandHiddenNavigationBar()
        .brandKeyboardDismissBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .brandSheet(isPresented: $isChoosingPayment) {
            OrderPaymentSheet(model: model) { isChoosingPayment = false }
        }
        .sheet(item: $systemShare) { BookShareSheet(payload: $0) }
        .task { await model.load() }
    }

    // MARK: - L'en-tête

    /// Le titre ne change pas d'une étape à l'autre : c'est le sous-titre qui
    /// dit où on en est. La flèche, elle, recule d'une étape — et ne referme
    /// l'écran que depuis la première.
    private var header: some View {
        BrandScreenHeader(
            title: BookCopy.Order.title,
            subtitle: model.step.progressLabel,
            onBack: goBack
        )
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.xs)
    }

    // MARK: - Le corps

    /// L'étape courante, qui glisse dans le sens où l'on va.
    ///
    /// Le `.id` force le remplacement plutôt qu'une mise à jour en place :
    /// sans lui, SwiftUI réutiliserait les vues d'une étape à l'autre et rien
    /// ne se verrait bouger.
    private var steps: some View {
        Group {
            switch model.step {
            case .start:
                OrderStartStep(model: model, onHelp: { onIntent(.openHelp) })
            case .shipping:
                OrderShippingStep(model: model, focus: $focus)
            case .copies:
                OrderCopiesStep(model: model, onHelp: { onIntent(.openHelp) })
            case .speed:
                OrderSpeedStep(model: model, onHelp: { onIntent(.openHelp) })
            case .summary:
                OrderSummaryStep(model: model)
            case .payment:
                OrderPaymentStep(model: model, onChoosePayment: { isChoosingPayment = true })
            case .confirmation:
                OrderConfirmationStep(
                    model: model,
                    onShare: { Task { await share() } },
                    onFinish: { onIntent(.finish) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .id(model.step)
        .transition(stepTransition)
        .animation(.smooth(duration: 0.32), value: model.step)
    }

    /// L'étape entre par le côté vers lequel on avance, et sort par l'autre.
    ///
    /// Sous « Réduire les animations », le glissé devient un simple fondu : le
    /// déplacement est précisément ce que ce réglage demande d'éviter.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        let leading = AnyTransition.move(edge: .leading).combined(with: .opacity)
        let trailing = AnyTransition.move(edge: .trailing).combined(with: .opacity)

        return model.isAdvancing
            ? .asymmetric(insertion: trailing, removal: leading)
            : .asymmetric(insertion: leading, removal: trailing)
    }

    // MARK: - La sortie

    /// « Partager le lien de prévisualisation ».
    ///
    /// La feuille est **celle du système** : elle seule connaît les apps
    /// installées et les appareils AirDrop à portée. Sans lien, rien ne
    /// s'ouvre — une feuille de partage vide serait pire qu'un bouton qui n'a
    /// pas répondu, et le bandeau du modèle dit pourquoi.
    private func share() async {
        guard let link = await model.prepareShareLink() else { return }

        systemShare = BookSharePayload(
            title: model.context?.bookTitle ?? "",
            steps: model.order?.pageCount ?? model.context?.pageCount ?? 0,
            file: nil,
            link: link
        )
    }

    /// La flèche du haut. Depuis la première étape il n'y a pas d'étape
    /// précédente : elle referme l'écran, ce que le modèle ne peut pas faire à
    /// sa place.
    private func goBack() {
        focus = nil
        if !model.goBack() { dismiss() }
    }
}

/// Ce que le tunnel de commande demande à `RootView`.
public enum OrderIntent: Sendable, Hashable {
    /// Tous les « Besoin d'aide ? » du parcours.
    case openHelp
    /// « Retour à l'accueil », une fois la commande passée.
    case finish
}

/// Les champs de l'étape 2. Le focus appartient à l'écran, pas au champ : c'est
/// ce qui permet à la touche « suivant » du clavier d'enchaîner.
enum OrderField: Hashable {
    case name
    case line1
    case line2
    case postalCode
    case city
}

// MARK: - La charpente d'une étape

/// Ce que toutes les étapes partagent : un contenu qui défile, et un bouton
/// ancré en bas.
///
/// **Tout défile sauf le bouton.** Même parti pris que la création d'un voyage,
/// et pour la même raison : en taille de texte accessible le contenu déborde,
/// et un bouton qui partirait avec lui deviendrait introuvable.
struct OrderStepLayout<Content: View, Actions: View>: View {
    /// Ce que l'étape veut amener sous les yeux — le rang d'un exemplaire qu'on
    /// vient de déplier. Remis à `nil` une fois la remontée jouée, pour que le
    /// même pli puisse rappeler la vue plus tard.
    var scrollTarget: Binding<Int?> = .constant(nil)

    /// Le « Besoin d'aide ? » de l'étape, quand elle en a un.
    ///
    /// Il est confié à la charpente plutôt que posé par chaque étape parce que
    /// **sa place change avec la taille du texte** : au-dessus du bouton aux
    /// tailles courantes, à la fin du contenu aux tailles accessibles, où la
    /// barre du bas mange déjà la moitié de l'écran et où une ligne de plus
    /// dedans ne laisserait presque rien à lire.
    var help: (() -> Void)?

    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollViewReader { proxy in
            scrollView
                .onChange(of: scrollTarget.wrappedValue) { _, target in
                    guard let target else { return }
                    // Après l'ouverture, pas pendant : l'animation du pli et
                    // celle du défilement se marcheraient dessus.
                    withAnimation(.smooth(duration: 0.35).delay(0.08)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollTarget.wrappedValue = nil
                }
        }
    }

    private var scrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                content()

                if let help, typeSize.isAccessibilitySize {
                    OrderHelpLink(action: help)
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.s)
            .padding(.bottom, MemoBookSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: MemoBookSpacing.xs) {
                if let help, !typeSize.isAccessibilitySize {
                    OrderHelpLink(action: help)
                }

                actions()
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.s)
            // **Un aplat opaque sous les commandes, un dégradé au-dessus.**
            //
            // Le dégradé seul ne suffisait pas : il s'étend sur toute la hauteur
            // de la barre, et celle-ci passe de 80 pt à près de 400 pt en taille
            // de texte accessible, où le libellé du bouton tient sur trois
            // lignes. Le contenu se lisait alors **à travers** le bouton — un
            // « Besoin d'aide ? » posé en travers de la carte de cagnotte. On
            // garde donc le fondu, qui efface le contenu à l'approche, et on
            // pose un fond plein sous les commandes elles-mêmes.
            .background {
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [MemoBookColor.background.opacity(0), MemoBookColor.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: MemoBookSpacing.l)

                    MemoBookColor.background
                }
                .padding(.top, -MemoBookSpacing.l)
                .allowsHitTesting(false)
            }
        }
    }
}

/// Le « Besoin d'aide ? » qui coiffe le bouton de plusieurs étapes.
struct OrderHelpLink: View {
    let action: () -> Void

    var body: some View {
        BrandButton(
            BookCopy.Order.help,
            style: .link,
            isSubdued: true,
            fillsWidth: true,
            action: action
        )
    }
}
