import MemoBookDesign
import SwiftUI

/// Les champs de l'inscription.
struct SignUpFields: View {
    @Bindable var model: AuthModel
    let focus: FocusState<AuthField?>.Binding

    /// Aux tailles de texte accessibles, deux champs côte à côte ne laissent
    /// plus la place à leur propre intitulé : ils passent l'un sous l'autre.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 12) {
            nameFields
                .textInputAutocapitalization(.words)

            BrandTextField("Email", text: $model.email, field: .email, focus: focus)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // Ce que le serveur reproche à l'adresse, **sous son champ** : c'est
            // là que la maquette le pose (`3394:10929`), et c'est la ligne à
            // changer. Le reste des échecs reste sous le bouton.
            if let error = model.emailError {
                Text(error)
                    .font(MemoBookFont.notification)
                    .foregroundStyle(MemoBookColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            BrandTextField(
                "Mot de passe",
                text: $model.password,
                field: .password,
                focus: focus,
                isSecure: true,
                hint: AuthModel.passwordRule
            )
            // `newPassword` déclenche la proposition de mot de passe fort du
            // trousseau ; sans les règles, iOS en propose un que notre
            // validation refuserait.
            .textContentType(.newPassword)

            BrandTextField(
                "Confirme ton mot de passe",
                text: $model.passwordConfirmation,
                field: .passwordConfirmation,
                focus: focus,
                isSecure: true
            )
            .textContentType(.newPassword)

            if let error = model.passwordConfirmationError {
                Text(error)
                    .font(MemoBookFont.notification)
                    .foregroundStyle(MemoBookColor.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: model.passwordConfirmationError)
        .animation(.snappy(duration: 0.2), value: model.emailError)
    }

    @ViewBuilder
    private var nameFields: some View {
        let firstName = BrandTextField("Prénom", text: $model.firstName, field: .firstName, focus: focus)
            .textContentType(.givenName)
        let lastName = BrandTextField("Nom", text: $model.lastName, field: .lastName, focus: focus)
            .textContentType(.familyName)

        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                firstName
                lastName
            }
        } else {
            HStack(spacing: 12) {
                firstName
                lastName
            }
        }
    }
}
