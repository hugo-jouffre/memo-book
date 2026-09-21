import MemoBookCore
import SwiftUI

/// Le champ « Pays » : un choix dans la liste que **le serveur** sert, jamais
/// un texte libre.
///
/// La liste suit l'imprimeur, pas nos livraisons (``ShippingCountry``). Un
/// champ libre laisserait écrire « Monaco » dans une adresse où le carnet ne
/// partira jamais — et « FRANCE », « France », « Fr » pour le même pays. Le
/// tunnel de commande l'a d'abord dessiné pour lui seul ; la feuille
/// « Adresse postale » du profil le voulait aussi, et deux écrans font un
/// composant.
///
/// Il a le dessin d'un ``BrandTextField`` à intitulé au-dessus — même
/// intitulé, même cadre, même hauteur — pour se poser dans la colonne sans
/// qu'on voie qu'il n'est pas un champ de saisie. Ce qui le distingue est le
/// double chevron, qui dit « ça se choisit » là où le curseur dirait « ça se
/// tape ».
///
/// ```swift
/// BrandCountryField(countries: profile.shippingCountries, code: $draft.country)
/// ```
///
/// Un code qui n'est pas dans la liste — l'adresse d'un profil enregistré
/// avant elle — s'affiche tel quel, en gris : c'est ce que la personne avait
/// écrit, et le menu l'invite à choisir un pays livrable à la place. Une
/// valeur vide montre « Choisir un pays », en texte indicatif.
public struct BrandCountryField: View {
    private let label: String
    private let countries: [ShippingCountry]
    @Binding private var code: String

    /// - Parameters:
    ///   - label: l'intitulé au-dessus du cadre. « Pays » partout pour
    ///     l'instant, mais c'est l'écran qui le dit, comme pour tout champ.
    ///   - countries: la liste servie par le serveur, dans son ordre.
    ///   - code: le code ISO 3166-1 alpha-2 choisi.
    public init(_ label: String = "Pays", countries: [ShippingCountry], code: Binding<String>) {
        self.label = label
        self.countries = countries
        self._code = code
    }

    @ScaledMetric(relativeTo: .body) private var height = MemoBookSpacing.fieldHeight

    private var selected: ShippingCountry? {
        countries.first { $0.code == code }
    }

    /// Ce que le cadre écrit : le nom du pays choisi, le code inconnu tel quel,
    /// ou l'invitation à choisir.
    private var display: (text: String, isPlaceholder: Bool) {
        if let selected { return (selected.name, false) }
        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? ("Choisir un pays", true) : (raw, false)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(label)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                // Le menu porte déjà ce mot comme `accessibilityLabel`.
                .accessibilityHidden(true)

            Menu {
                Picker(label, selection: $code) {
                    ForEach(countries) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: MemoBookSpacing.xs) {
                    Text(display.text)
                        // Le texte indicatif prend le dessin de celui d'un
                        // `BrandTextField` ; une valeur, celui d'une valeur.
                        .font(display.isPlaceholder ? MemoBookFont.bodySemibold : MemoBookFont.body)
                        .foregroundStyle(
                            display.isPlaceholder || selected == nil
                                ? MemoBookColor.inkMuted
                                : MemoBookColor.ink
                        )
                        .lineLimit(1)

                    Spacer(minLength: MemoBookSpacing.xs)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: MemoBookSpacing.controlCornerRadius)
                        .strokeBorder(MemoBookColor.separator, lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: MemoBookSpacing.controlCornerRadius))
            }
            // Le menu du système ne connaît pas notre crème : il prend la
            // teinte de l'action pour sa coche.
            .tint(MemoBookColor.action)
            // Sans liste, il n'y a rien à choisir : le serveur ne l'a pas
            // envoyée, et un menu vide s'ouvrirait sur rien.
            .disabled(countries.isEmpty)
            .accessibilityLabel(label)
            .accessibilityValue(display.isPlaceholder ? "Aucun" : display.text)
            // Le nom change en fondu quand on choisit, comme une valeur qui
            // s'écrit — pas d'un coup sec.
            .animation(.snappy(duration: 0.2), value: code)
        }
    }
}

#Preview("Pays") {
    struct Host: View {
        @State private var code = "FR"
        @State private var legacy = "Monaco"
        @State private var empty = ""

        private let countries = [
            ShippingCountry(code: "FR", name: "France"),
            ShippingCountry(code: "BE", name: "Belgique"),
            ShippingCountry(code: "CH", name: "Suisse"),
        ]

        var body: some View {
            VStack(spacing: MemoBookSpacing.s) {
                BrandCountryField(countries: countries, code: $code)
                BrandCountryField(countries: countries, code: $legacy)
                BrandCountryField(countries: countries, code: $empty)
            }
            .padding(MemoBookSpacing.screenMargin)
            .background(MemoBookColor.background)
        }
    }

    return Host()
}
