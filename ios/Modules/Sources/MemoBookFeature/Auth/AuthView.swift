import MemoBookCore
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
    private let onAuthenticated: (Account) -> Void

    /// Le secret d'un lien « Réinitialiser mon mot de passe » ouvert pendant
    /// qu'on est dehors. Posé par ``RootView``, qui reçoit les liens ; consommé
    /// ici, où la feuille peut s'ouvrir. Une liaison et non une valeur : le
    /// lien peut arriver avant que cet écran existe (lancement à froid) comme
    /// pendant qu'il est là, et il ne doit servir qu'une fois.
    @Binding private var resetToken: String?

    public init(resetToken: Binding<String?> = .constant(nil), onAuthenticated: @escaping (Account) -> Void) {
        self._resetToken = resetToken
        self.onAuthenticated = onAuthenticated
    }

    @Environment(AppDependencies.self) private var dependencies
    @State private var model: AuthModel?
    /// La feuille « Mot de passe oublié », quand elle est ouverte. Un modèle
    /// neuf à chaque ouverture : c'est lui qui la présente.
    @State private var recovery: PasswordRecoveryModel?

    /// La page du nouveau mot de passe, ouverte par le lien de l'e-mail. Elle
    /// **remplace** l'écran d'entrée le temps de choisir, comme la page de
    /// compléments après Apple ou Google — voir ``PasswordResetView``.
    @State private var reset: PasswordRecoveryModel?
    @FocusState private var focus: AuthField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu
    /// de s'étirer. Même règle que l'écran d'accueil.
    private static let contentWidth: CGFloat = 390

    public var body: some View {
        // Le modèle a besoin de l'API, qui arrive par l'environnement : il ne
        // peut plus naître dans un initialiseur de propriété.
        if let model {
            // Entré par Apple ou Google, on vérifie d'abord ce que le
            // fournisseur a donné — voir ``SocialCompletionView``.
            if model.completing != nil {
                SocialCompletionView(model: model, focus: $focus) { onAuthenticated($0) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let reset {
                PasswordResetView(
                    model: reset,
                    onAuthenticated: { account in
                        self.reset = nil
                        onAuthenticated(account)
                    },
                    onRequestAgain: {
                        // La page se retire et la feuille de l'adresse monte
                        // à sa place, dans le même mouvement.
                        withAnimation(reduceMotion ? .none : .snappy(duration: 0.35)) { self.reset = nil }
                        recovery = PasswordRecoveryModel(api: dependencies.api, email: model.email)
                    },
                    onCancel: {
                        withAnimation(reduceMotion ? .none : .snappy(duration: 0.35)) { self.reset = nil }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                content(model)
            }
        } else {
            Color.clear.onAppear { model = AuthModel(api: dependencies.api) }
        }
    }

    private func content(_ model: AuthModel) -> some View {
        @Bindable var model = model

        return ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandSegmentedPicker(AuthMode.allCases, selection: $model.mode, title: \.segmentTitle)

                header(model)

                fields(model)
                    .transition(transition(model))

                BrandButton(
                    "Continuer",
                    isLoading: model.isWorking,
                    fillsWidth: true,
                    action: { submit(model) }
                )
                .disabled(!model.canSubmit)
                .padding(.top, MemoBookSpacing.xs)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(MemoBookFont.notification)
                        .foregroundStyle(MemoBookColor.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                // Estompée, pas désactivée : l'opacité ne touche pas au test
                // de toucher, et celui qui change d'avis en cours de saisie
                // trouve les deux boutons exactement là où il les a laissés.
                SocialSignInSection(
                    onCredential: { acceptCredential($0, model) },
                    onFailure: model.report,
                    onGoogle: { signInWithGoogle(model) }
                )
                    .opacity(model.hasStartedFilling ? 0.5 : 1)
                    // Pendant un appel, un seul chemin doit rester actif.
                    .disabled(model.isWorking)
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 0.25),
                        value: model.hasStartedFilling
                    )

                // ⚠️ PROVISOIRE — à retirer dès que le back-end tourne pour
                // tout le monde. Entre dans l'app par le **compte de test**,
                // celui que le seed pose, pour pouvoir travailler les écrans qui
                // vivent derrière l'entrée sans retaper une adresse à chaque
                // lancement. Absent de la version livrée : `#if DEBUG` ne
                // compile pas en release.
                #if DEBUG
                    Button {
                        enterAsTestAccount(model)
                    } label: {
                        // Volontairement effacé : c'est un outil de chantier, pas
                        // une troisième façon d'entrer dans l'app.
                        Text("Testing mode →")
                            .font(MemoBookFont.caption)
                            .foregroundStyle(MemoBookColor.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                #endif
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.vertical, MemoBookSpacing.m)
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // La barre d'accessoires du clavier : c'est **la** réponse iOS au
        // « comment je referme ça ». Elle ne prend aucune place dans l'écran,
        // n'apparaît que clavier ouvert, et se pose au même endroit dans toutes
        // les apps du système — donc là où le pouce la cherche déjà. Le dessin
        // est celui du design system, partagé avec le profil.
        .brandKeyboardDismissBar()
        // `simultaneousGesture` et non `gesture` : le défilement vertical doit
        // continuer de fonctionner pendant qu'on guette un balayage latéral.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { handleSwipe($0, model) }
        )
        .background(BrandBackdrop())
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? .none : .snappy(duration: 0.35, extraBounce: 0.1), value: model.mode)
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
        .onChange(of: model.mode) { focus = nil }
        // Le petit « clic » d'un sélecteur iOS, que le geste vienne du
        // balayage ou du sélecteur lui-même.
        .sensoryFeedback(.selection, trigger: model.mode)
        // Le retour de la feuille Google passe par une adresse au schéma de
        // l'app, déclaré dans `project.yml`.
        .onOpenURL { GoogleSignInService.handle($0) }
        .brandSheet(item: $recovery) { recovery in
            PasswordRecoverySheet(
                model: recovery,
                onClose: { email in
                    // L'adresse corrigée dans la feuille revient dans le
                    // formulaire : c'est celle avec laquelle on va se reconnecter.
                    if !email.isEmpty { model.email = email }
                },
                onSignUp: { email in
                    // La feuille descend et le sélecteur glisse vers
                    // « Inscription » dans le même mouvement, l'adresse déjà
                    // en place : il ne reste que le prénom et le mot de passe.
                    self.recovery = nil
                    model.email = email
                    model.mode = .signUp
                }
            )
        }
        .onAppear { openResetIfLinked() }
        .onChange(of: resetToken) { openResetIfLinked() }
    }

    /// Un lien de l'e-mail est arrivé : la page du nouveau mot de passe prend
    /// la place de l'écran, et le secret est consommé pour qu'un second rendu
    /// ne la rouvre pas. Une feuille encore ouverte se referme d'abord.
    private func openResetIfLinked() {
        guard let token = resetToken else { return }
        resetToken = nil
        focus = nil
        recovery = nil
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.35)) {
            reset = PasswordRecoveryModel(api: dependencies.api, resetToken: token)
        }
    }

    // MARK: - Morceaux

    private func header(_ model: AuthModel) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(model.mode.title)
                .font(MemoBookFont.h1)
                .tracking(-0.41)
                .foregroundStyle(MemoBookColor.ink)
            Text(model.mode.subtitle)
                .font(MemoBookFont.body)
                .tracking(MemoBookFont.tracking(16))
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Le titre change de texte, pas de rôle : sans identité stable, SwiftUI
        // ferait disparaître un bloc pour en faire apparaître un autre.
        .id(model.mode)
        .transition(transition(model))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func fields(_ model: AuthModel) -> some View {
        switch model.mode {
        case .signUp:
            SignUpFields(model: model, focus: $focus)
                .onSubmit { advanceFocus(model) }
                .submitLabel(.next)
        case .signIn:
            SignInFields(model: model, focus: $focus, onForgottenPassword: recoverPassword)
                .onSubmit { advanceFocus(model) }
                .submitLabel(.next)
        }
    }

    /// Glissé dans le sens du sélecteur. En « Reduce Motion », un simple fondu :
    /// c'est exactement le genre de déplacement que le réglage vise.
    private func transition(_ model: AuthModel) -> AnyTransition {
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
    private func handleSwipe(_ drag: DragGesture.Value, _ model: AuthModel) {
        let horizontal = drag.translation.width
        guard abs(horizontal) > 60, abs(horizontal) > abs(drag.translation.height) * 1.5 else {
            return
        }
        model.mode = horizontal < 0 ? .signIn : .signUp
    }

    private func advanceFocus(_ model: AuthModel) {
        guard let focus, let next = model.fieldAfter(focus) else {
            self.focus = nil
            if model.canSubmit { submit(model) }
            return
        }
        self.focus = next
    }

    private func submit(_ model: AuthModel) {
        focus = nil
        Task {
            // `nil` : l'appel a échoué, et le message est déjà à l'écran.
            guard let account = await model.submit() else { return }
            onAuthenticated(account)
        }
    }

    #if DEBUG

        /// Le bouton de chantier. Il passe par le même chemin que « Continuer »
        /// : un échec s'affiche donc au même endroit, sous le formulaire, au
        /// lieu de ne rien faire du tout — c'est ce qui dit que le back-end
        /// n'est pas lancé, plutôt que de laisser croire à un bouton mort.
        private func enterAsTestAccount(_ model: AuthModel) {
            focus = nil
            Task {
                guard let account = await model.signInAsTestAccount() else { return }
                onAuthenticated(account)
            }
        }

    #endif

    /// Ouvre « Mot de passe oublié » sur l'adresse déjà tapée, s'il y en a une.
    private func recoverPassword() {
        guard let model else { return }
        focus = nil
        recovery = PasswordRecoveryModel(api: dependencies.api, email: model.email)
    }

    private func acceptCredential(_ credential: SocialCredential, _ model: AuthModel) {
        focus = nil
        Task {
            guard let account = await model.accept(credential) else { return }
            // Un compte neuf, ou auquel il manque un nom, passe par la page
            // de compléments avant d'entrer (Hugo, 14/09/2026).
            if model.needsCompletion(account) {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.35)) {
                    model.beginCompletion(account)
                }
            } else {
                onAuthenticated(account)
            }
        }
    }

    private func signInWithGoogle(_ model: AuthModel) {
        focus = nil
        Task {
            do {
                // `nil` : l'utilisateur a refermé la feuille. Rien à dire.
                guard let credential = try await GoogleSignInService.signIn() else { return }
                acceptCredential(credential, model)
            } catch {
                model.report(error)
            }
        }
    }
}

#Preview("Entrée") {
    AuthView { _ in }
        .environment(AppDependencies(api: PreviewAPI()))
}
