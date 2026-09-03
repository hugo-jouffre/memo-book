import MemoBookDesign
import SwiftUI

/// Les champs de la connexion.
struct SignInFields: View {
    @Bindable var model: AuthModel
    let focus: FocusState<AuthField?>.Binding
    let onForgottenPassword: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandTextField("Email", text: $model.email, field: .email, focus: focus)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            BrandTextField(
                "Mot de passe",
                text: $model.password,
                field: .password,
                focus: focus,
                isSecure: true
            )
            .textContentType(.password)

            // Lien souligné vert : le style `Link` du design system est un
            // texte noir sans soulignement, il ne couvre pas ce cas. À
            // remonter au design plutôt qu'à décliner `BrandButton` ici.
            Button(action: onForgottenPassword) {
                Text("Mot de passe oublié ?")
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.action)
                    .underline()
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}
