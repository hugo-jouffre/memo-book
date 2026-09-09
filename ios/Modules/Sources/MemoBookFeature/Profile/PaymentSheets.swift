import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Choisir par quoi payer, ou en ajouter un.
///
/// La feuille d'ajout se présente **par-dessus** celle-ci plutôt qu'à sa place :
/// on revient sur son choix après avoir enregistré une carte, sans avoir à
/// rouvrir le profil.
struct PaymentMethodSheet: View {
    let model: ProfileModel

    @State private var isAddingCard = false

    var body: some View {
        BrandSheet(
            "Mode de paiement",
            subtitle: "Ajoutes-en un ou choisis parmi tes cartes déjà enregistrées."
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandOptionGroup {
                    ForEach(model.profile?.cards ?? []) { card in
                        BrandOptionRow(
                            card.label,
                            subtitle: card.maskedNumber,
                            isSelected: card.id == model.profile?.selectedCardId
                        ) {
                            model.selectCard(id: card.id)
                        }
                    }

                    ApplePayRow()
                }

                BrandButton(
                    "Ajouter une carte",
                    icon: Image(brand: "IconPlus"),
                    iconPlacement: .trailing,
                    fillsWidth: true
                ) {
                    isAddingCard = true
                }
            }
        }
        .brandSheet(isPresented: $isAddingCard) {
            AddCardSheet { number, name in
                model.addCard(number: number, label: name)
            }
        }
    }
}

/// La ligne Apple Pay. Elle n'est pas une option comme les autres : rien n'est
/// à choisir tant que le paiement n'existe pas, et le cadre noir de la maquette
/// est la façon dont Apple veut qu'on présente sa marque.
///
/// Le logotype est celui d'Apple, posé tel quel : **jamais** de
/// `renderingMode(.template)`, jamais recoloré, jamais recomposé à partir du
/// symbole système et du mot « Pay » — c'est ce qu'on faisait faute d'asset, et
/// les règles de marque d'Apple l'interdisent.
private struct ApplePayRow: View {
    /// La hauteur du logotype suit le corps de texte : il se lit comme un mot
    /// de la ligne, pas comme une image posée dedans.
    @ScaledMetric(relativeTo: .body) private var markHeight: CGFloat = 22

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            Text("ApplePay")
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
            Text("disponible")
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
            Spacer(minLength: MemoBookSpacing.xs)
            mark
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.s - 2)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .overlay { shape.strokeBorder(MemoBookColor.ink, lineWidth: 2) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Pay, disponible")
    }

    private var mark: some View {
        Image(brand: "LogoApplePay")
            .resizable()
            .scaledToFit()
            // Le rapport du fichier est 48 × 24 : on ne fixe que la hauteur,
            // la largeur suit. Une marque déformée n'est plus la marque.
            .frame(height: markHeight)
            .accessibilityHidden(true)
    }
}

/// Enregistrer une carte.
///
/// **Rien de ce qui est saisi ici ne quitte la feuille**, sinon les quatre
/// derniers chiffres — voir ``ProfileModel/addCard(number:label:)``. Le champ
/// est un formulaire de maquette tant qu'aucun prestataire de paiement n'est
/// branché : il ne faut surtout pas qu'il devienne un endroit où l'app garde un
/// numéro complet.
struct AddCardSheet: View {
    let onAdd: (_ number: String, _ name: String) -> Void

    @State private var number = ""
    @State private var expiry = ""
    @State private var securityCode = ""
    @State private var holder = ""

    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field: Hashable {
        case number, expiry, securityCode, holder
    }

    /// Ce que « Ajouter une carte » attend pour s'allumer. Volontairement
    /// permissif — une carte n'est vraiment validée que par le prestataire —
    /// mais assez pour écarter un formulaire à moitié rempli.
    private var canSubmit: Bool {
        number.filter(\.isNumber).count >= 12
            && expiry.filter(\.isNumber).count >= 4
            && securityCode.filter(\.isNumber).count >= 3
            && !holder.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        BrandSheet("Ajouter une carte") {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                    BrandTextField(
                        "Numéro de carte",
                        text: $number,
                        field: Field.number,
                        focus: $focus,
                        labelPlacement: .above,
                        placeholder: "0000000000000000"
                    )
                    .textContentType(.creditCardNumber)
                    .keyboardType(.numberPad)

                    expiryAndSecurityCode

                    BrandTextField(
                        "Nom sur la carte",
                        text: $holder,
                        field: Field.holder,
                        focus: $focus,
                        labelPlacement: .above,
                        placeholder: "Prénom NOM"
                    )
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                }
                .padding(MemoBookSpacing.s)
                .overlay {
                    RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                        .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
                }

                BrandButton("Ajouter une carte", fillsWidth: true) {
                    focus = nil
                    onAdd(number, holder)
                    dismiss()
                }
                .disabled(!canSubmit)
                .padding(.top, MemoBookSpacing.xs)
            }
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

    @ViewBuilder
    private var expiryAndSecurityCode: some View {
        let expiryField = BrandTextField(
            "Date d’expiration",
            text: $expiry,
            field: Field.expiry,
            focus: $focus,
            labelPlacement: .above,
            placeholder: "00/00"
        )
        // Un pavé **numérique** : la barre oblique est posée par le champ, elle
        // n'a pas à être cherchée sur un clavier de ponctuation.
        .keyboardType(.numberPad)
        .onChange(of: expiry) { _, value in
            expiry = PaymentCard.formattedExpiry(value)
        }

        let codeField = BrandTextField(
            "CVV",
            text: $securityCode,
            field: Field.securityCode,
            focus: $focus,
            labelPlacement: .above,
            placeholder: "000"
        )
        .keyboardType(.numberPad)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                expiryField
                codeField
            }
        } else {
            HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                expiryField
                codeField
            }
        }
    }
}

#Preview("Mode de paiement") {
    let model = ProfileModel()

    return Color.clear
        .background(MemoBookColor.background)
        .task { await model.load() }
        .sheet(isPresented: .constant(true)) {
            PaymentMethodSheet(model: model)
        }
}

#Preview("Ajouter une carte") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            AddCardSheet { _, _ in }
        }
}
