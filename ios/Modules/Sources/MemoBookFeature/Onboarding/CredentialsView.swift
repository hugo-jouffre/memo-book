import MemoBookCore
import MemoBookDesign
import MemoBookNetworking
import SwiftUI

/// *Sign Up* et *Login* — un seul écran, deux onglets.
///
/// Le détail fonctionnel le demande explicitement : basculer d'un onglet à
/// l'autre change l'état d'un même composant, ce n'est pas une navigation.
/// Nœuds Figma `2553:27489` (inscription) et `2720:21779` (connexion).
struct CredentialsView: View {
    @State private var model: CredentialsModel
    /// L'échec de connexion, en modale. C'est le seul de tout le flow.
    @Binding private var failure: OnboardingModel.SignInFailure?

    @FocusState private var focus: CredentialsModel.Field?

    init(model: CredentialsModel, failure: Binding<OnboardingModel.SignInFailure?>) {
        self._model = State(initialValue: model)
        self._failure = failure
    }

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()
            BackgroundRoute()

            ScrollView {
                VStack(spacing: MemoBookSpacing.l) {
                    tabs
                    heading
                    fields
                    submit
                    socialProviders
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.top, rem(2))
                .padding(.bottom, MemoBookSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // La seule modale du flow. Son message reste générique : dire lequel
        // des deux champs est faux, ce serait confirmer qu'une adresse a un
        // compte. « Réessayer » remet le focus sans rien effacer.
        .alert(
            failure?.message ?? "",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )
        ) {
            Button("Réessayer") { focus = .password }
            Button("Annuler", role: .destructive) {}
        }
    }

    private var tabs: some View {
        SegmentedToggle(
            segments: [
                .init(value: AuthTab.signUp, title: "S’inscrire"),
                .init(value: AuthTab.signIn, title: "Se connecter"),
            ],
            selection: Binding(get: { model.tab }, set: { model.select(tab: $0) })
        )
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(model.tab == .signUp ? "Crée ton compte" : "Ravi de te revoir !")
                .font(MemoBookFont.screenTitle)
                .foregroundStyle(MemoBookColor.ink)
                .tracking(MemoBookTracking.tight)

            Text(model.tab == .signUp ? "pour commencer à raconter ton histoire" : "connecte toi")
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkSecondary)
                .tracking(MemoBookTracking.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            if model.tab == .signUp {
                HStack(spacing: MemoBookSpacing.s) {
                    MemoBookTextField(
                        "Prénom",
                        text: $model.firstName,
                        field: .firstName,
                        focus: $focus,
                        kind: .givenName,
                        error: model.fieldErrors[.firstName]
                    ) { focus = .lastName }

                    MemoBookTextField(
                        "Nom",
                        text: $model.lastName,
                        field: .lastName,
                        focus: $focus,
                        kind: .familyName,
                        error: model.fieldErrors[.lastName]
                    ) { focus = .email }
                }
            }

            MemoBookTextField(
                "Email",
                text: $model.email,
                field: .email,
                focus: $focus,
                kind: .email,
                error: model.fieldErrors[.email]
            ) { focus = .password }

            MemoBookTextField(
                "Mot de passe",
                text: $model.password,
                field: .password,
                focus: $focus,
                kind: model.tab == .signUp ? .newPassword : .password,
                submitLabel: model.tab == .signUp ? .next : .go,
                error: model.fieldErrors[.password]
            ) {
                if model.tab == .signUp {
                    focus = .passwordConfirmation
                } else {
                    Task { await model.submit() }
                }
            }

            if model.tab == .signUp {
                MemoBookTextField(
                    "Confirme ton mot de passe",
                    text: $model.passwordConfirmation,
                    field: .passwordConfirmation,
                    focus: $focus,
                    kind: .newPassword,
                    submitLabel: .go,
                    error: model.fieldErrors[.passwordConfirmation]
                ) { Task { await model.submit() } }
            } else {
                Button("Mot de passe oublié ?") { model.forgotPassword() }
                    .font(MemoBookFont.link)
                    .foregroundStyle(MemoBookColor.action)
                    .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
            }

            if let formError = model.formError {
                ErrorBanner(message: formError)
            }
        }
    }

    private var submit: some View {
        MemoBookButton(
            "Continuer",
            isEnabled: model.canSubmit,
            isLoading: model.isSubmitting
        ) {
            Task { await model.submit() }
        }
    }

    private var socialProviders: some View {
        VStack(spacing: MemoBookSpacing.s) {
            Text("Ou continue avec")
                .font(MemoBookFont.link)
                .foregroundStyle(MemoBookColor.action)

            HStack(spacing: MemoBookSpacing.m) {
                // Apple est obligatoire dès qu'un login social tiers est
                // proposé (App Store 4.8) : les trois vont ensemble.
                socialButton(.facebook, asset: .facebookLogo)
                socialButton(.apple, asset: .appleLogo)
                socialButton(.google, asset: .googleLogo)
            }
        }
    }

    private func socialButton(_ provider: SocialProvider, asset: FigmaAsset) -> some View {
        SocialButton(asset: asset, label: provider.label) {
            Task { await model.signIn(with: provider) }
        }
    }
}

#Preview("Inscription") {
    OnboardingPreview(tab: .signUp)
}

#Preview("Connexion") {
    OnboardingPreview(tab: .signIn)
}

#Preview("Inscription — AX3") {
    OnboardingPreview(tab: .signUp)
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// Monte l'écran sur `PreviewAPI` : l'inscription crée vraiment un compte en
/// mémoire, ce qui rend l'aperçu utilisable pour travailler l'écran.
private struct OnboardingPreview: View {
    let tab: AuthTab

    var body: some View {
        let api = PreviewAPI()
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())

        return CredentialsView(
            model: CredentialsModel(api: api, onboarding: onboarding, tab: tab),
            failure: .constant(nil)
        )
    }
}
