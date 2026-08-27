import MemoBookDesign
import MemoBookNetworking
import SwiftUI

/// *Mot de passe oublié* — l'adresse à laquelle le lien va partir.
///
/// L'adresse arrive pré-remplie de *Connection* quand elle y avait été saisie.
/// Le crayon la rend modifiable. Nœud Figma `2707:9275`.
struct ForgotPasswordView: View {
    @State private var model: ForgotPasswordModel
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email }

    init(model: ForgotPasswordModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        PasswordScreenLayout(title: "Mot de passe oublié") {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                Text(
                    "Un email pour reconfigurer ton mot de passe va t’être envoyé à l’adresse suivante :"
                )
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .tracking(MemoBookTracking.body)
                .fixedSize(horizontal: false, vertical: true)

                if model.isEditingEmail {
                    MemoBookTextField(
                        "Email",
                        text: $model.email,
                        field: .email,
                        focus: $focus,
                        kind: .email,
                        submitLabel: .go,
                        error: model.emailError
                    ) { Task { await model.submit() } }
                } else {
                    address
                }

                if let formError = model.formError {
                    ErrorBanner(message: formError)
                }
            }
        } action: {
            MemoBookButton(
                "Continuer",
                isEnabled: model.canSubmit,
                isLoading: model.isSubmitting
            ) {
                Task { await model.submit() }
            }
        }
    }

    /// L'adresse affichée, avec le crayon qui la rend modifiable.
    private var address: some View {
        HStack {
            Text(model.email)
                .font(MemoBookFont.sectionTitle)
                .foregroundStyle(MemoBookColor.inkSecondary)
                .tracking(MemoBookTracking.tight)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: MemoBookSpacing.xs)

            Button {
                model.isEditingEmail = true
                focus = .email
            } label: {
                FigmaImage(.pencil)
                    .frame(width: rem(1.5), height: rem(1.5))
                    .frame(
                        minWidth: MemoBookSpacing.minimumTapTarget,
                        minHeight: MemoBookSpacing.minimumTapTarget
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Modifier l’adresse email")
        }
        .padding(.leading, MemoBookSpacing.m)
        .padding(.trailing, MemoBookSpacing.xs)
        .frame(height: rem(3))
        .background(
            MemoBookColor.surface,
            in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
        )
    }
}

/// *Mdp oublié - compte inexistant* — l'adresse saisie n'a pas de compte.
///
/// Cet écran n'a **pas de CTA** : le lien est la seule sortie, et il mène à
/// l'inscription. C'est le dessin du nœud `2820:18513`, et le détail
/// fonctionnel le confirme.
struct ForgotPasswordNoAccountView: View {
    let email: String
    let onCreateAccount: () -> Void

    var body: some View {
        PasswordScreenLayout(title: "Mot de passe oublié") {
            VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
                Text("Il n’existe aucun compte associé à l’adresse \(email)")
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .tracking(MemoBookTracking.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: rem(0.375)) {
                    Text("Tu peux en créer un ")
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                        .tracking(MemoBookTracking.body)

                    Button("en cliquant ici", action: onCreateAccount)
                        .font(MemoBookFont.button)
                        .foregroundStyle(MemoBookColor.action)
                        .underline()
                        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                }
            }
        }
    }
}

/// *Mdp oublié - config* — le nouveau mot de passe, après clic sur le lien.
///
/// Accessible **uniquement** par le deep link : jamais par navigation dans
/// l'app. Nœud Figma `2707:9539`.
struct ResetPasswordView: View {
    @State private var model: ResetPasswordModel
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case password
        case confirmation
    }

    init(model: ResetPasswordModel) {
        self._model = State(initialValue: model)
    }

    var body: some View {
        PasswordScreenLayout(title: "Configure ton nouveau mot de passe") {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                MemoBookTextField(
                    "Mot de passe",
                    text: $model.password,
                    field: .password,
                    focus: $focus,
                    kind: .newPassword,
                    error: model.passwordError
                ) { focus = .confirmation }

                MemoBookTextField(
                    "Confirme ton nouveau mot de passe",
                    text: $model.confirmation,
                    field: .confirmation,
                    focus: $focus,
                    kind: .newPassword,
                    submitLabel: .go,
                    error: model.confirmationError
                ) { Task { await model.submit() } }

                if let linkError = model.linkError {
                    // Un lien mort ne laisse jamais devant un formulaire
                    // inutilisable : la sortie est là, à côté du message.
                    ErrorBanner(message: linkError) { model.backToSignIn() }
                }
            }
        } action: {
            MemoBookButton(
                "Continuer",
                isEnabled: model.canSubmit,
                isLoading: model.isSubmitting
            ) {
                Task { await model.submit() }
            }
        }
    }
}

/// La mise en page commune aux trois écrans de mot de passe : la pastille
/// cadenas, le titre, le contenu, et le CTA quand il y en a un.
private struct PasswordScreenLayout<Content: View, Action: View>: View {
    let title: String
    let content: () -> Content
    let action: () -> Action

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.title = title
        self.content = content
        self.action = action
    }

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: rem(1.75)) {
                    LockBadge()

                    VStack(spacing: MemoBookSpacing.l) {
                        Text(title)
                            .font(MemoBookFont.screenTitle)
                            .foregroundStyle(MemoBookColor.ink)
                            .tracking(MemoBookTracking.tight)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        content()

                        action()
                    }
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.top, rem(1.75))
                .padding(.bottom, MemoBookSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

extension PasswordScreenLayout where Action == EmptyView {
    /// Pour l'écran « compte inexistant », qui n'a pas de CTA.
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, content: content, action: { EmptyView() })
    }
}

#Preview("Mot de passe oublié") {
    let api = PreviewAPI()
    let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
    return ForgotPasswordView(model: ForgotPasswordModel(api: api, onboarding: onboarding))
}

#Preview("Compte inexistant") {
    ForgotPasswordNoAccountView(email: "cla.thioll@gmail.com", onCreateAccount: {})
}

#Preview("Nouveau mot de passe") {
    let api = PreviewAPI()
    let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
    return ResetPasswordView(
        model: ResetPasswordModel(token: "jeton", api: api, onboarding: onboarding)
    )
}
