import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Où envoyer le carnet imprimé — à donner, ou à corriger.
///
/// La feuille travaille sur une **copie** de l'adresse : tant qu'on n'a pas
/// validé, rien ne change dans le profil. Refermer d'un glissé revient donc à
/// annuler, ce que le geste laisse attendre. Ouverte sur une adresse déjà
/// connue, elle la montre telle quelle et tout s'y corrige : c'est la même
/// feuille qui ajoute et qui modifie, seule sa phrase d'en-tête change.
///
/// **Le pays se choisit, il ne se tape pas.** La liste est celle de
/// l'imprimeur, servie avec le profil (``TravellerProfile/shippingCountries``)
/// — la même que celle du tunnel de commande, dont cette adresse est l'amorce.
/// Un texte libre laissait écrire un pays où le carnet ne partira jamais, ou
/// trois graphies pour le même.
///
/// **Sauf quand la liste n'est pas là.** Un profil relu depuis le cache, ou
/// servi par un back-end qui ne l'envoie pas encore, arrive sans elle : le
/// champ redevient alors une saisie libre, et c'est le serveur qui ramène
/// « France » à son code. Un menu vide et grisé laissait la feuille sans issue
/// — « Choisir un pays » qu'on ne pouvait pas choisir, et « Valider » qui
/// n'y arrivait jamais (Paul, 21/09/2026). La liste arrive souvent une
/// seconde après, avec le profil frais : le menu prend alors la place du
/// champ, sans perdre ce qui y était tapé.
///
/// **« Valider » ne se désactive pas.** Il pâlit tant qu'il manque une ligne,
/// et l'appui dit laquelle au lieu d'avaler le geste — la règle de l'app pour
/// tout ce qu'on ne peut pas encore faire. Un bouton gris qui ne répond pas
/// laissait chercher ce qu'on avait mal fait : les exemples dans les champs
/// vides (« 7 rue Simon Fryd », « Lyon ») se lisaient comme une adresse déjà
/// remplie, et rien ne disait pourquoi elle ne partait pas (Paul, 18/09/2026).
struct PostalAddressSheet: View {
    private let hasAddress: Bool
    private let countries: [ShippingCountry]
    private let onSave: (PostalAddress) -> Void

    /// - Parameters:
    ///   - address: celle du profil. Vide pour un compte qui n'en a pas encore.
    ///   - countries: les pays livrables, dans l'ordre du serveur. Le premier
    ///     — la France — est proposé d'office quand l'adresse n'a pas encore de
    ///     pays : c'est celui de presque tous les carnets, et il se change d'un
    ///     geste.
    init(
        address: PostalAddress,
        countries: [ShippingCountry],
        onSave: @escaping (PostalAddress) -> Void
    ) {
        // Le même critère que la ligne du profil, qui écrit « Ajouter une
        // adresse » quand il n'y a rien à résumer.
        hasAddress = !address.singleLine.isEmpty
        self.countries = countries
        self.onSave = onSave

        _draft = State(initialValue: address.settled(in: countries))
    }

    @State private var draft: PostalAddress

    /// « Valider » a été touché trop tôt : on nomme ce qui manque, tant que ça
    /// manque. La phrase se lit sur le brouillon, pas sur un instantané — elle
    /// se raccourcit à mesure qu'on remplit, et s'efface toute seule à la
    /// dernière ligne.
    @State private var isExplainingWhatIsMissing = false

    @FocusState private var focus: PostalAddress.Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var missingSentence: String? {
        guard isExplainingWhatIsMissing, let missing = draft.missingFieldsDescription else {
            return nil
        }
        return "Il manque **\(missing)** pour que ton carnet arrive."
    }

    var body: some View {
        BrandSheet(
            "Adresse postale",
            subtitle: hasAddress
                ? "Modifie l’adresse où tu souhaites recevoir ton carnet."
                : "Ajoute l’adresse où tu souhaites recevoir ton carnet."
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                BrandTextField(
                    "Adresse",
                    text: $draft.street,
                    field: PostalAddress.Field.street,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: "7 rue Simon Fryd"
                )
                .textContentType(.streetAddressLine1)
                // Pas de majuscule à chaque mot : « 18 avenue des Ternes »
                // s'écrit ainsi, et le tunnel de commande fait pareil.
                .submitLabel(.next)
                .onSubmit { focus = .postalCode }

                postalCodeAndCity

                countryField

                if let missingSentence {
                    BrandNotice(missingSentence, tone: .information)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                BrandButton("Valider", fillsWidth: true, action: validate)
                    // Pâli, pas désactivé : il reste tapable pour expliquer.
                    .opacity(draft.isComplete ? 1 : 0.45)
                    .padding(.top, MemoBookSpacing.xs)
                    .accessibilityHint(draft.isComplete ? "" : "Il manque une ligne à l’adresse")
            }
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: missingSentence)
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: draft.isComplete)
            .animation(reduceMotion ? .none : .snappy(duration: 0.25), value: countries.isEmpty)
        }
        // La barre du clavier de l'app — l'icône qui le range —, et non un
        // « OK » qui laisserait croire qu'on valide quelque chose.
        .brandKeyboardDismissBar()
        // La liste arrive après l'ouverture — le profil frais a remplacé celui
        // du cache : ce qui était tapé retombe sur sa ligne du menu.
        .onChange(of: countries) { _, countries in
            draft = draft.settled(in: countries)
        }
    }

    /// Le menu quand la liste est là, la saisie libre sinon — voir l'en-tête.
    @ViewBuilder
    private var countryField: some View {
        if countries.isEmpty {
            BrandTextField(
                "Pays",
                text: $draft.country,
                field: PostalAddress.Field.country,
                focus: $focus,
                labelPlacement: .above,
                placeholder: "France"
            )
            .textContentType(.countryName)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { focus = nil }
        } else {
            BrandCountryField("Pays", countries: countries, code: $draft.country)
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
            field: PostalAddress.Field.postalCode,
            focus: $focus,
            labelPlacement: .above,
            placeholder: "69007"
        )
        .textContentType(.postalCode)
        .keyboardType(.numbersAndPunctuation)
        .submitLabel(.next)
        .onSubmit { focus = .city }

        // Dernier champ tapé quand le pays se choisit : le clavier se range, et
        // « Valider » est là. Quand le pays se tape, il est le suivant.
        let city = BrandTextField(
            "Ville",
            text: $draft.city,
            field: PostalAddress.Field.city,
            focus: $focus,
            labelPlacement: .above,
            placeholder: "Lyon"
        )
        .textContentType(.addressCity)
        .textInputAutocapitalization(.words)
        .submitLabel(countries.isEmpty ? .next : .done)
        .onSubmit { focus = countries.isEmpty ? .country : nil }

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

    /// Enregistre si tout y est ; sinon, dit ce qui manque et ouvre le premier
    /// champ vide, clavier compris — le pays, lui, se choisit dans son menu,
    /// sauf quand il se tape.
    private func validate() {
        guard draft.isComplete else {
            isExplainingWhatIsMissing = true
            focus = draft.missingFields.first { countries.isEmpty || $0 != .country }
            return
        }
        focus = nil
        onSave(draft.trimmed)
        dismiss()
    }
}

private extension PostalAddress {
    /// L'adresse telle que la feuille la présente, la liste des pays en main.
    ///
    /// Le pays retombe sur son code si la liste le connaît — par son code ou
    /// par son nom, tapé du temps où il se tapait — ; la France est proposée
    /// quand il n'y en a pas encore ; et sans liste, rien ne bouge : ce qui
    /// est écrit reste écrit, y compris ce qui vient d'être tapé.
    func settled(in countries: [ShippingCountry]) -> PostalAddress {
        var settled = self
        if let known = countries.matching(country) {
            settled.country = known.code
        } else if country.trimmed.isEmpty, let first = countries.first {
            settled.country = first.code
        }
        return settled
    }

    /// Les espaces de bord d'un clavier tactile ne font pas partie de
    /// l'adresse : on les retire avant d'envoyer, pas avant de comparer.
    var trimmed: PostalAddress {
        PostalAddress(
            street: street.trimmed,
            postalCode: postalCode.trimmed,
            city: city.trimmed,
            country: country.trimmed,
            countryName: countryName
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview("Adresse postale — à modifier") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            PostalAddressSheet(
                address: TravellerProfile.fixture.address,
                countries: TravellerProfile.fixture.shippingCountries
            ) { _ in }
        }
}

#Preview("Adresse postale — sans liste de pays") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            PostalAddressSheet(address: PostalAddress(), countries: []) { _ in }
        }
}

#Preview("Adresse postale — à ajouter") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            PostalAddressSheet(
                address: PostalAddress(),
                countries: TravellerProfile.fixture.shippingCountries
            ) { _ in }
        }
}
