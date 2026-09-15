import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La page qui suit le lien de l'e-mail « Mot de passe oublié » : **le nouveau
/// mot de passe, deux fois**, puis l'app.
///
/// Maquette « Mdp oublié – config » (Hugo, 15/09/2026) : le cadenas, le titre,
/// les deux champs, « Continuer ». Une **page** et non une feuille : on arrive
/// par un lien, il n'y a pas d'écran dessous qu'une feuille prolongerait — même
/// dessin que ``SocialCompletionView``, l'autre page qui s'interpose avant
/// l'entrée.
///
/// Les deux champs sont ceux de l'inscription — même règle (``PasswordRule``),
/// même phrase de désaccord, même proposition de mot de passe fort du
/// trousseau. La réussite ouvre une session : on entre sans retaper ce qu'on
/// vient d'écrire.
struct PasswordResetView: View {
    @Bindable var model: PasswordRecoveryModel

    /// La session est ouverte : l'app entre.
    let onAuthenticated: (Account) -> Void

    /// « Ce lien n'est plus valable » → en redemander un. La page se referme
    /// et la feuille de l'adresse s'ouvre à sa place.
    let onRequestAgain: () -> Void

    /// Sortir sans rien changer — un lien ouvert par erreur, ou trop tard.
    let onCancel: () -> Void

    @FocusState private var focus: PasswordRecoveryField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu
    /// de s'étirer. Même règle que l'écran d'entrée.
    private static let contentWidth: CGFloat = 390

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandIconBadge("IconLocker")
                    .frame(maxWidth: .infinity)

                Text(PasswordRecoveryCopy.resetTitle)
                    .font(MemoBookFont.h1)
                    .tracking(-0.41)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                fields

                VStack(spacing: MemoBookSpacing.xs) {
                    BrandButton(
                        PasswordRecoveryCopy.save,
                        isLoading: model.isWorking,
                        fillsWidth: true,
                        action: save
                    )
                    .disabled(!model.canSave)

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(MemoBookFont.notification)
                            .foregroundStyle(MemoBookColor.error)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)

                        // Le lien ne vaut plus rien : la seule issue est d'en
                        // redemander un.
                        BrandButton(PasswordRecoveryCopy.requestAgain, style: .link, action: onRequestAgain)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
                .padding(.top, MemoBookSpacing.xs)

                // La porte de sortie. La maquette n'en dessine pas ; sans elle,
                // un lien ouvert par erreur laisse quelqu'un devant deux champs
                // qu'il ne veut pas remplir, avec pour seule issue de tuer
                // l'app. Effacée, comme « Besoin d'aide ? » du profil.
                BrandButton(PasswordRecoveryCopy.backHome, style: .link, isSubdued: true, action: onCancel)
                    .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                    .padding(.top, MemoBookSpacing.s)
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.vertical, MemoBookSpacing.m)
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .brandKeyboardDismissBar()
        .background(BrandBackdrop())
        .environment(\.colorScheme, .light)
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
        .animation(.snappy(duration: 0.2), value: model.passwordConfirmationError)
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
        .onAppear {
            // Le clavier s'ouvre tout de suite : il n'y a rien d'autre à faire
            // sur cette page que d'écrire.
            if model.password.isEmpty { focus = .password }
        }
    }

    private var fields: some View {
        VStack(spacing: MemoBookSpacing.snug) {
            BrandTextField(
                PasswordRecoveryCopy.passwordLabel,
                text: $model.password,
                field: .password,
                focus: $focus,
                isSecure: true,
                hint: PasswordRule.hint
            )
            .textContentType(.newPassword)
            .submitLabel(.next)
            .onSubmit { focus = .passwordConfirmation }

            BrandTextField(
                PasswordRecoveryCopy.confirmationLabel,
                text: $model.passwordConfirmation,
                field: .passwordConfirmation,
                focus: $focus,
                isSecure: true
            )
            .textContentType(.newPassword)
            .submitLabel(.done)
            .onSubmit(save)

            if let error = model.passwordConfirmationError {
                Text(error)
                    .font(MemoBookFont.notification)
                    .foregroundStyle(MemoBookColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
        }
    }

    private func save() {
        guard model.canSave else { return }
        focus = nil
        Task {
            guard let account = await model.resetPassword() else { return }
            onAuthenticated(account)
        }
    }
}

#Preview("Nouveau mot de passe") {
    PasswordResetView(
        model: PasswordRecoveryModel(api: PreviewAPI(), resetToken: "aperçu"),
        onAuthenticated: { _ in },
        onRequestAgain: {},
        onCancel: {}
    )
}
