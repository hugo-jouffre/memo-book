import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Où envoyer le carnet imprimé.
///
/// La feuille travaille sur une **copie** de l'adresse : tant qu'on n'a pas
/// validé, rien ne change dans le profil. Refermer d'un glissé revient donc à
/// annuler, ce que le geste laisse attendre.
struct PostalAddressSheet: View {
    let address: PostalAddress
    let onSave: (PostalAddress) -> Void

    init(address: PostalAddress, onSave: @escaping (PostalAddress) -> Void) {
        self.address = address
        _draft = State(initialValue: address)
        self.onSave = onSave
    }

    @State private var draft: PostalAddress
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field: Hashable {
        case street, postalCode, city, country
    }

    var body: some View {
        BrandSheet(
            "Adresse postale",
            subtitle: "Ajoute l’adresse où tu souhaites recevoir ton carnet."
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                BrandTextField(
                    "Adresse",
                    text: $draft.street,
                    field: Field.street,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: "7 rue Simon Fryd"
                )
                .textContentType(.streetAddressLine1)
                .textInputAutocapitalization(.words)

                postalCodeAndCity

                BrandTextField(
                    "Pays",
                    text: $draft.country,
                    field: Field.country,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: "FRANCE"
                )
                .textContentType(.countryName)
                .textInputAutocapitalization(.words)

                BrandButton("Valider", fillsWidth: true) {
                    focus = nil
                    onSave(draft)
                    dismiss()
                }
                .disabled(!draft.isComplete)
                .padding(.top, MemoBookSpacing.xs)
            }
            .onSubmit(advanceFocus)
            .submitLabel(.next)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focus = nil }
                        .font(MemoBookFont.bodySemibold)
                        .tint(MemoBookColor.action)
                }
            }
        }
    }

    /// Deux colonnes égales, comme prénom/nom de l'écran d'entrée — et une
    /// colonne unique en taille accessible, où chacune tomberait à quelques
    /// caractères de large.
    @ViewBuilder
    private var postalCodeAndCity: some View {
        let postalCode = BrandTextField(
            "Code postal",
            text: $draft.postalCode,
            field: Field.postalCode,
            focus: $focus,
            labelPlacement: .above,
            placeholder: "69007"
        )
        .textContentType(.postalCode)
        .keyboardType(.numbersAndPunctuation)

        let city = BrandTextField(
            "Ville",
            text: $draft.city,
            field: Field.city,
            focus: $focus,
            labelPlacement: .above,
            placeholder: "Lyon"
        )
        .textContentType(.addressCity)
        .textInputAutocapitalization(.words)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                postalCode
                city
            }
        } else {
            HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                postalCode
                city
            }
        }
    }

    private func advanceFocus() {
        switch focus {
        case .street: focus = .postalCode
        case .postalCode: focus = .city
        case .city: focus = .country
        default: focus = nil
        }
    }
}

#Preview("Adresse postale") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            PostalAddressSheet(address: TravellerProfile.fixture.address) { _ in }
        }
}
