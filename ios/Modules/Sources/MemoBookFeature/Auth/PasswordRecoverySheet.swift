import MemoBookCore
import MemoBookDesign
import SwiftUI

/// « Mot de passe oublié » — la feuille qui monte sur le formulaire de
/// connexion.
///
/// Un parcours en plusieurs temps dans **une seule** feuille dont le contenu
/// change, jamais une pile de feuilles (voir `BrandSheet`). Le premier temps
/// confirme l'adresse et envoie l'e-mail ; il s'ouvre sur ce que la connexion
/// contenait déjà, et le crayon dit que ça se corrige.
struct PasswordRecoverySheet: View {
    @Bindable var model: PasswordRecoveryModel

    /// Appelé quand la feuille descend, avec l'adresse telle qu'elle a été
    /// laissée : le formulaire de connexion la reprend, pour ne pas la faire
    /// retaper à la reconnexion.
    let onClose: (String) -> Void

    /// « Tu peux en créer un en cliquant ici » : la feuille se referme et
    /// l'écran d'entrée bascule sur l'inscription, adresse déjà posée.
    let onSignUp: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @FocusState private var focus: PasswordRecoveryField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        BrandSheet(
            PasswordRecoveryCopy.title,
            icon: "IconLocker",
            subtitle: subtitle,
            titleAlignment: .centered
        ) {
            switch model.step {
            case .request:
                requestStep
                    .transition(stepTransition)
            case .sent:
                sentStep
                    .transition(stepTransition)
            case .reset:
                // Jamais dans la feuille : arrivé par le lien de l'e-mail, il
                // n'y a pas d'écran dessous — c'est une page, ``PasswordResetView``.
                EmptyView()
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.35, extraBounce: 0.05), value: model.step)
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
        .animation(reduceMotion ? .none : .snappy(duration: 0.28), value: model.isUnknownAccount)
        .sensoryFeedback(.error, trigger: model.isUnknownAccount) { _, new in new }
        .sensoryFeedback(.success, trigger: model.step) { _, new in new == .sent }
        .brandKeyboardDismissBar()
        // Une demande partie à moitié n'a pas de sens : le temps de l'appel,
        // la feuille ne se referme ni au glissé ni au tapotis hors d'elle.
        .interactiveDismissDisabled(model.isWorking)
        .onDisappear { onClose(model.email) }
    }

    private var subtitle: String? {
        model.step == .request ? PasswordRecoveryCopy.requestSubtitle : nil
    }

    // MARK: - Étape 1 : l'adresse

    private var requestStep: some View {
        VStack(spacing: MemoBookSpacing.m) {
            BrandTextField(
                "Email",
                text: $model.email,
                field: .email,
                focus: $focus,
                labelPlacement: .hidden,
                placeholder: PasswordRecoveryCopy.emailPlaceholder,
                trailingIcon: "IconPen"
            )
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit(submit)

            if let unknownEmail = model.unknownEmail {
                unknownAccount(unknownEmail)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }

            VStack(spacing: MemoBookSpacing.xs) {
                // Le même bouton change de mot et de geste : « Continuer »
                // envoie, « Revenir à l'accueil » referme. Une seule place, pour
                // que le pouce le trouve au même endroit dans les deux cas.
                BrandButton(
                    model.isUnknownAccount ? PasswordRecoveryCopy.backHome : PasswordRecoveryCopy.send,
                    isLoading: model.isWorking,
                    fillsWidth: true,
                    action: model.isUnknownAccount ? { dismiss() } : submit
                )
                .disabled(!model.canSubmit && !model.isUnknownAccount)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(MemoBookFont.notification)
                        .foregroundStyle(MemoBookColor.error)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Le refus du serveur, et la porte de sortie : la phrase rouge reprend
    /// l'adresse telle qu'elle est écrite, et le lien mène à l'inscription.
    private func unknownAccount(_ email: String) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(PasswordRecoveryCopy.unknownAccount(email))
                .font(MemoBookFont.notification)
                .foregroundStyle(MemoBookColor.error)
                .fixedSize(horizontal: false, vertical: true)

            // Deux `Text` côte à côte et non un seul : la seconde moitié est
            // un bouton, avec sa cible de 44 pt, pas un mot souligné dans une
            // phrase qu'on ne saurait pas toucher à VoiceOver. Aux tailles
            // accessibles, la phrase ne tient plus sur une ligne : le lien
            // passe dessous.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    signUpLead
                    signUpLink
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    signUpLead
                    signUpLink
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var signUpLead: some View {
        Text(PasswordRecoveryCopy.signUpLead)
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var signUpLink: some View {
        Button { onSignUp(model.email) } label: {
            Text(PasswordRecoveryCopy.signUpLink)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.action)
                .underline()
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PasswordRecoveryCopy.signUpAccessibility)
    }

    // MARK: - Étape 2 : l'e-mail est parti

    /// Ce qu'il reste à faire est **dans la boîte mail**, pas dans l'app : la
    /// feuille le dit, nomme le bouton de l'e-mail pour qu'on le reconnaisse,
    /// et rend la main. Pas de « renvoyer » : rouvrir « Mot de passe oublié »
    /// fait exactement ça, et une seconde porte au même endroit inviterait à
    /// taper deux fois avant d'avoir regardé.
    private var sentStep: some View {
        VStack(spacing: MemoBookSpacing.m) {
            VStack(spacing: MemoBookSpacing.xs) {
                Text(PasswordRecoveryCopy.sentBody(to: model.email))
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)

                Text(PasswordRecoveryCopy.sentHint)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)

            BrandButton(PasswordRecoveryCopy.backHome, fillsWidth: true) { dismiss() }
        }
    }

    // MARK: - Mouvement

    /// Une étape pousse la précédente vers la gauche, comme une page qu'on
    /// tourne. En « Reduce Motion », un fondu.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func submit() {
        guard model.canSubmit else { return }
        focus = nil
        Task { await model.submit() }
    }

}

/// Les champs du parcours, dans l'ordre où le clavier les enchaîne — l'adresse
/// sur la feuille, les deux mots de passe sur la page. Le focus appartient à
/// l'écran, comme partout.
enum PasswordRecoveryField: Hashable {
    case email
    case password
    case passwordConfirmation
}

/// Les mots de la feuille, tels que la maquette les écrit.
enum PasswordRecoveryCopy {
    static let title = "Mot de passe oublié"

    static let requestSubtitle =
        "Un email pour reconfigurer ton mot de passe va t’être envoyé à l’adresse suivante :"

    static let emailPlaceholder = "prenom@exemple.com"

    static let send = "Continuer"

    static let backHome = "Revenir à l’accueil"

    static func unknownAccount(_ email: String) -> String {
        "Il n’existe aucun compte associé à l’adresse \(email)"
    }

    static let signUpLead = "Tu peux en créer un"
    static let signUpLink = "en cliquant ici"
    static let signUpAccessibility = "Créer un compte avec cette adresse"

    /// L'e-mail est parti. On nomme le bouton de l'e-mail avec ses mots à lui
    /// (« Réinitialiser mon mot de passe »), pour qu'on le reconnaisse.
    static func sentBody(to email: String) -> String {
        "C’est envoyé ! Ouvre l’e-mail reçu sur \(email) et appuie sur « Réinitialiser mon mot de passe »."
    }

    static let sentHint = "Rien reçu d’ici quelques minutes ? Regarde dans tes courriers indésirables."

    // La page du nouveau mot de passe — maquette « Mdp oublié – config ».
    static let resetTitle = "Configure ton nouveau mot de passe"
    static let passwordLabel = "Mot de passe"
    static let confirmationLabel = "Confirme ton nouveau mot de passe"
    static let save = "Continuer"
    static let requestAgain = "Redemander un e-mail"
}

#Preview("Mot de passe oublié") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            PasswordRecoverySheet(
                model: PasswordRecoveryModel(api: PreviewAPI(), email: "ola.thioll@gmail.com"),
                onClose: { _ in },
                onSignUp: { _ in }
            )
        }
}

#Preview("Mot de passe oublié — vide") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            PasswordRecoverySheet(
                model: PasswordRecoveryModel(api: PreviewAPI(), email: ""),
                onClose: { _ in },
                onSignUp: { _ in }
            )
        }
}
