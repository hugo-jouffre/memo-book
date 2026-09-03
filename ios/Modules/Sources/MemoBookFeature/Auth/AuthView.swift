import MemoBookDesign
import SwiftUI

/// Écran d'entrée : inscription et connexion sous un même sélecteur.
///
/// Le passage d'un mode à l'autre est une seule animation : la pastille du
/// sélecteur glisse (`matchedGeometryEffect`), et le formulaire se décale dans
/// le même sens — depuis la droite quand on va vers « Connexion », depuis la
/// gauche au retour. C'est le geste d'un `UIPageViewController`, sans la
/// navigation.
public struct AuthView: View {
    private let onAuthenticated: () -> Void

    public init(onAuthenticated: @escaping () -> Void) {
        self.onAuthenticated = onAuthenticated
    }

    @State private var model = AuthModel()
    @FocusState private var focus: AuthField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu
    /// de s'étirer. Même règle que l'écran d'accueil.
    private static let contentWidth: CGFloat = 390

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandSegmentedPicker(AuthMode.allCases, selection: $model.mode, title: \.segmentTitle)

                header

                fields
                    .transition(transition)

                BrandButton("Continuer", fillsWidth: true, action: submit)
                    .disabled(!model.canSubmit)
                    .padding(.top, MemoBookSpacing.xs)

                SocialSignInSection(onApple: signInWithApple, onGoogle: signInWithGoogle)
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.vertical, MemoBookSpacing.m)
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // `simultaneousGesture` et non `gesture` : le défilement vertical doit
        // continuer de fonctionner pendant qu'on guette un balayage latéral.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded(handleSwipe)
        )
        .background(BrandBackdrop())
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? .none : .snappy(duration: 0.35, extraBounce: 0.1), value: model.mode)
        .onChange(of: model.mode) { focus = nil }
        // Le petit « clic » d'un sélecteur iOS, que le geste vienne du
        // balayage ou du sélecteur lui-même.
        .sensoryFeedback(.selection, trigger: model.mode)
    }

    // MARK: - Morceaux

    private var header: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(model.mode.title)
                .font(MemoBookFont.h1)
                .tracking(-0.41)
                .foregroundStyle(MemoBookColor.ink)
            Text(model.mode.subtitle)
                .font(MemoBookFont.body)
                .tracking(MemoBookFont.tracking(16))
                .foregroundStyle(MemoBookColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Le titre change de texte, pas de rôle : sans identité stable, SwiftUI
        // ferait disparaître un bloc pour en faire apparaître un autre.
        .id(model.mode)
        .transition(transition)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var fields: some View {
        switch model.mode {
        case .signUp:
            SignUpFields(model: model, focus: $focus)
                .onSubmit(advanceFocus)
                .submitLabel(.next)
        case .signIn:
            SignInFields(model: model, focus: $focus, onForgottenPassword: recoverPassword)
                .onSubmit(advanceFocus)
                .submitLabel(.next)
        }
    }

    /// Glissé dans le sens du sélecteur. En « Reduce Motion », un simple fondu :
    /// c'est exactement le genre de déplacement que le réglage vise.
    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let forward = model.mode == .signIn
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Actions

    /// Balayage latéral pour passer d'un mode à l'autre, comme entre deux
    /// pages. On exige un geste franchement horizontal : sans ça, un défilement
    /// un peu de travers ferait basculer le formulaire au milieu de la saisie.
    private func handleSwipe(_ drag: DragGesture.Value) {
        let horizontal = drag.translation.width
        guard abs(horizontal) > 60, abs(horizontal) > abs(drag.translation.height) * 1.5 else {
            return
        }
        model.mode = horizontal < 0 ? .signIn : .signUp
    }

    private func advanceFocus() {
        guard let focus, let next = model.fieldAfter(focus) else {
            self.focus = nil
            if model.canSubmit { submit() }
            return
        }
        self.focus = next
    }

    private func submit() {
        focus = nil
        // TODO(auth) — brancher sur l'API quand elle existera. Voir `AuthModel`.
        onAuthenticated()
    }

    private func recoverPassword() {
        // TODO(auth) — écran de récupération, pas encore maquetté.
    }

    private func signInWithApple() {
        // TODO(auth) — passer par `SignInWithAppleButton`. Voir `SocialSignInSection`.
        onAuthenticated()
    }

    private func signInWithGoogle() {
        // TODO(auth) — SDK Google Sign-In, à arbitrer avant de l'ajouter.
        onAuthenticated()
    }
}

#Preview("Entrée") {
    AuthView {}
}
