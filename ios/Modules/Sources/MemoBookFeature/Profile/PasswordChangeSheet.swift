import MemoBookCore
import MemoBookDesign
import MemoBookNetworking
import SwiftUI

/// « Modifier mon mot de passe » — la feuille sous la ligne « Mot de passe »
/// du profil (Hugo, 29/09/2026), et la même feuille pour le nouveau mot de
/// passe d'un lien reçu par e-mail quand on est déjà entré.
///
/// Trois champs, un bouton, et le bouton reste gris tant que les trois ne
/// disent pas la même chose : le mot de passe actuel n'est pas vide, le nouveau
/// respecte les trois critères — cochés **pendant qu'on tape** —, et la
/// confirmation le répète. Le serveur revérifie tout, mais la feuille ne lui
/// envoie rien qu'il refuserait à coup sûr.
///
/// Quatre issues, et une phrase pour chacune :
///
/// - **mot de passe actuel faux** : sous son champ, avec « Mot de passe
///   oublié ? », qui sort du parcours et envoie l'e-mail de réinitialisation ;
/// - **réussite** : « Mot de passe modifié ✓ », et « Retour à mon compte » ;
/// - **session expirée** : on demande de se reconnecter ;
/// - **panne** : « Impossible de modifier ton mot de passe pour le moment. »
struct PasswordChangeSheet: View {
    @Bindable var model: PasswordChangeModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: PasswordChangeField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrandSheet(
            PasswordChangeCopy.title,
            icon: "IconLocker",
            subtitle: subtitle,
            titleAlignment: .centered
        ) {
            switch model.step {
            case .form:
                form.transition(stepTransition)
            case .done:
                done.transition(stepTransition)
            case .resetSent:
                resetSent.transition(stepTransition)
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.35, extraBounce: 0.05), value: model.step)
        .animation(.snappy(duration: 0.2), value: model.failure)
        .sensoryFeedback(.error, trigger: model.failure) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: model.step) { _, new in new == .done }
        .brandKeyboardDismissBar()
        // Un envoi parti à moitié n'a pas de sens : le temps de l'appel, la
        // feuille ne se referme ni au glissé ni au tapotis hors d'elle.
        .interactiveDismissDisabled(model.isWorking)
    }

    private var subtitle: String? {
        switch model.step {
        case .form: model.mode.subtitle
        case .done, .resetSent: nil
        }
    }

    // MARK: - Le formulaire

    private var form: some View {
        VStack(spacing: MemoBookSpacing.m) {
            VStack(spacing: MemoBookSpacing.snug) {
                if model.mode.asksCurrentPassword {
                    BrandTextField(
                        PasswordChangeCopy.current,
                        text: $model.currentPassword,
                        field: .current,
                        focus: $focus,
                        isSecure: true
                    )
                    .textContentType(.password)
                    .submitLabel(.next)
                    .onSubmit { focus = .new }

                    if model.failure == .wrongPassword {
                        wrongPassword.transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }

                BrandTextField(
                    PasswordChangeCopy.new,
                    text: $model.newPassword,
                    field: .new,
                    focus: $focus,
                    isSecure: true
                )
                // `newPassword` déclenche la proposition de mot de passe fort
                // du trousseau, comme à l'inscription.
                .textContentType(.newPassword)
                .submitLabel(.next)
                .onSubmit { focus = .confirmation }

                criteria

                BrandTextField(
                    PasswordChangeCopy.confirmation,
                    text: $model.confirmation,
                    field: .confirmation,
                    focus: $focus,
                    isSecure: true
                )
                .textContentType(.newPassword)
                .submitLabel(.done)
                .onSubmit(submit)

                if let mismatch = model.confirmationError {
                    fieldError(mismatch)
                }

                if model.failure == .samePassword {
                    fieldError(PasswordChangeCopy.samePassword)
                }
            }

            VStack(spacing: MemoBookSpacing.xs) {
                BrandButton(
                    model.mode.callToAction,
                    isLoading: model.isWorking,
                    fillsWidth: true,
                    action: submit
                )
                .disabled(!model.canSubmit)

                if let message = model.failure?.message {
                    Text(message)
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

    /// Les trois critères, cochés à mesure : c'est ce que « en temps réel »
    /// veut dire — on voit lequel manque avant d'appuyer.
    private var criteria: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            ForEach(PasswordRule.Criterion.allCases) { criterion in
                let isMet = criterion.isMet(by: model.newPassword)
                HStack(spacing: MemoBookSpacing.xs) {
                    Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isMet ? MemoBookColor.valid : MemoBookColor.inkFaint)
                        .contentTransition(.symbolEffect(.replace))
                    Text(criterion.label)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(isMet ? MemoBookColor.ink : MemoBookColor.inkMuted)
                }
                .animation(.snappy(duration: 0.2), value: isMet)
                .accessibilityElement(children: .combine)
                .accessibilityValue(isMet ? "respecté" : "manquant")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.xs)
    }

    /// « Mot de passe incorrect », et la sortie de secours.
    private var wrongPassword: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            Text(PasswordChangeCopy.wrongPassword)
                .font(MemoBookFont.notification)
                .foregroundStyle(MemoBookColor.error)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await model.requestReset() }
            } label: {
                Text(PasswordChangeCopy.forgotten)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.action)
                    .underline()
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
            .accessibilityHint(PasswordChangeCopy.forgottenHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.xs)
    }

    private func fieldError(_ text: String) -> some View {
        Text(text)
            .font(MemoBookFont.notification)
            .foregroundStyle(MemoBookColor.error)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MemoBookSpacing.xs)
            .transition(.opacity)
    }

    // MARK: - Réussite

    private var done: some View {
        VStack(spacing: MemoBookSpacing.m) {
            VStack(spacing: MemoBookSpacing.xs) {
                Text(PasswordChangeCopy.doneTitle)
                    .font(MemoBookFont.h2)
                    .foregroundStyle(MemoBookColor.ink)
                Text(PasswordChangeCopy.doneBody)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)

            BrandButton(PasswordChangeCopy.backToAccount, fillsWidth: true) { dismiss() }
        }
    }

    // MARK: - L'e-mail est parti

    private var resetSent: some View {
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

            BrandButton(PasswordChangeCopy.backToAccount, fillsWidth: true) { dismiss() }
        }
    }

    // MARK: - Mouvement

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

enum PasswordChangeField: Hashable {
    case current
    case new
    case confirmation
}

// MARK: - Le modèle

/// Ce que la feuille sait faire : vérifier les trois champs, envoyer, et dire
/// ce qui s'est passé.
///
/// Il reçoit des fonctions et non l'API, comme ``ProfileModel`` : l'app leur
/// branche `POST /v1/profile/password` et « mot de passe oublié » ; un aperçu
/// n'en fournit aucune et la feuille joue alors la réussite.
@MainActor
@Observable
final class PasswordChangeModel {
    /// Pourquoi la feuille est ouverte : changer, ou poser un nouveau mot de
    /// passe depuis un lien reçu par e-mail.
    enum Mode: Equatable {
        case change
        case reset(token: String)

        var asksCurrentPassword: Bool { self == .change }

        var subtitle: String {
            switch self {
            case .change: PasswordChangeCopy.subtitle
            case .reset: PasswordChangeCopy.resetSubtitle
            }
        }

        var callToAction: String {
            switch self {
            case .change: PasswordChangeCopy.submit
            case .reset: PasswordChangeCopy.submitReset
            }
        }
    }

    enum Step: Equatable {
        case form
        case done
        case resetSent
    }

    /// Ce qui a échoué, et la phrase qui va avec.
    enum Failure: Equatable {
        case wrongPassword
        case samePassword
        case sessionExpired
        case noPassword
        case unavailable

        var message: String? {
            switch self {
            case .wrongPassword, .samePassword: nil  // sous leur champ
            case .sessionExpired: PasswordChangeCopy.sessionExpired
            case .noPassword: PasswordChangeCopy.noPassword
            case .unavailable: PasswordChangeCopy.unavailable
            }
        }
    }

    let mode: Mode
    let email: String

    private let change: ((String, String) async throws -> Void)?
    private let reset: ((String, String) async throws -> Void)?
    private let requestResetMail: ((String) async throws -> Void)?

    var currentPassword = "" {
        didSet { if failure == .wrongPassword { failure = nil } }
    }
    var newPassword = "" {
        didSet { if failure == .samePassword { failure = nil } }
    }
    var confirmation = ""

    private(set) var step: Step = .form
    private(set) var failure: Failure?
    private(set) var isWorking = false

    init(
        mode: Mode = .change,
        email: String,
        change: ((String, String) async throws -> Void)? = nil,
        reset: ((String, String) async throws -> Void)? = nil,
        requestReset: ((String) async throws -> Void)? = nil
    ) {
        self.mode = mode
        self.email = email
        self.change = change
        self.reset = reset
        self.requestResetMail = requestReset
    }

    var isNewPasswordValid: Bool { PasswordRule.isValid(newPassword) }

    var passwordsMatch: Bool { newPassword == confirmation }

    /// Même phrase que l'inscription, une fois qu'il y a de quoi juger.
    var confirmationError: String? {
        guard !confirmation.isEmpty, !passwordsMatch else { return nil }
        return AuthModel.passwordMismatchMessage
    }

    /// Le bouton s'allume quand les champs sont **bien remplis**, pas avant :
    /// un bouton qui échoue après coup apprend moins qu'un bouton gris.
    var canSubmit: Bool {
        guard !isWorking, isNewPasswordValid, passwordsMatch else { return false }
        guard mode.asksCurrentPassword else { return true }
        return !currentPassword.isEmpty && currentPassword != newPassword
    }

    func submit() async {
        guard canSubmit else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }

        do {
            switch mode {
            case .change:
                // Sans serveur (aperçu), la feuille joue la réussite.
                try await change?(currentPassword, newPassword)
            case .reset(let token):
                try await reset?(token, newPassword)
            }
            step = .done
        } catch {
            failure = Self.failure(for: error)
        }
    }

    /// « Mot de passe oublié ? » : l'e-mail de réinitialisation part à l'adresse
    /// du compte, et la feuille le dit. C'est la sortie du parcours classique.
    func requestReset() async {
        isWorking = true
        failure = nil
        defer { isWorking = false }

        do {
            try await requestResetMail?(email)
            step = .resetSent
        } catch {
            failure = .unavailable
        }
    }

    private static func failure(for error: any Error) -> Failure {
        guard let apiError = error as? APIError else { return .unavailable }
        switch apiError {
        case .server(_, "wrong_password", _): return .wrongPassword
        case .server(_, "same_password", _): return .samePassword
        case .server(_, "no_password", _): return .noPassword
        case .server(401, _, _), .notAuthenticated: return .sessionExpired
        default: return .unavailable
        }
    }
}

enum PasswordChangeCopy {
    static let title = "Modifier mon mot de passe"
    static let subtitle = "Choisis un nouveau mot de passe pour ton compte."
    static let resetSubtitle = "Configure ton nouveau mot de passe."

    static let current = "Mot de passe actuel"
    static let new = "Nouveau mot de passe"
    static let confirmation = "Confirmer le nouveau mot de passe"

    static let submit = "Modifier mon mot de passe"
    static let submitReset = "Enregistrer mon mot de passe"

    static let wrongPassword = "Mot de passe incorrect. Vérifie ton mot de passe et réessaie."
    static let forgotten = "Mot de passe oublié ?"
    static let forgottenHint = "Envoie un e-mail pour réinitialiser ton mot de passe"
    static let samePassword = "Ton nouveau mot de passe doit être différent de l’ancien."
    static let sessionExpired = "Ta session a expiré : reconnecte-toi pour modifier ton mot de passe."
    static let noPassword = "Ce compte s’ouvre avec Apple ou Google : il n’a pas de mot de passe à modifier."
    static let unavailable =
        "Impossible de modifier ton mot de passe pour le moment. Réessaie dans quelques instants."

    static let doneTitle = "Mot de passe modifié ✓"
    static let doneBody = "Ton mot de passe a bien été modifié."
    static let backToAccount = "Retour à mon compte"
}

#Preview("Modifier mon mot de passe") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            PasswordChangeSheet(model: PasswordChangeModel(email: "margaux@exemple.com"))
        }
}
