import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Étape 6 — par quoi on paie, où ça va, et combien.
///
/// « Payer » enregistre la commande en brouillon **puis ouvre la feuille
/// Stripe**, et ne passe à la confirmation qu'une fois le paiement accepté.
/// Voir ``OrderModel/pay()``, qui tient les trois chemins possibles.
///
/// **Le moyen de paiement se choisit dans la feuille de Stripe** (01/10/2026).
/// L'étape affichait une carte dessinée et une feuille de choix — cartes
/// fabriquées par l'app, Apple Pay —, et rien de ce choix n'arrivait à Stripe.
/// La feuille, elle, montre les cartes enregistrées du compte, en accepte une
/// nouvelle, et propose Apple Pay quand l'identifiant marchand est posé.
struct OrderPaymentStep: View {
    let model: OrderModel

    var body: some View {
        OrderStepLayout {
            OrderSectionHeader(title: BookCopy.Order.Payment.title)

            method

            address

            OrderPriceRow(
                label: BookCopy.Order.Payment.total,
                amount: model.quote?.total,
                isProminent: true
            )

            if let message = model.paymentError {
                ErrorBanner(message: message)
            }
        } actions: {
            BrandButton(
                BookCopy.Order.Payment.cta,
                isLoading: model.isSubmitting,
                fillsWidth: true
            ) {
                Task { await model.pay() }
            }
            .disabled(!model.canContinue || model.isSubmitting)
        }
    }

    // MARK: Le moyen de paiement

    private var method: some View {
        BrandNotice(BookCopy.Order.Payment.inStripeSheet)
    }

    // MARK: L'adresse

    private var address: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(BookCopy.Order.Payment.address)
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.draft.shipping.name)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)

                Text(formattedAddress)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .background(
                MemoBookColor.surface,
                in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MemoBookSpacing.controlCornerRadius)
                    .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// « 7 Rue Simon Fryd, Lyon, FRANCE 69007 ». Le pays s'écrit en toutes
    /// lettres — le code ISO est ce que la base garde, pas ce qui se lit.
    private var formattedAddress: String {
        let shipping = model.draft.shipping
        let country = model.context?.countries
            .first { $0.code == shipping.country }?
            .name ?? shipping.country

        return [shipping.line1, shipping.line2, shipping.city, "\(country) \(shipping.postalCode)"]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: ", ")
    }
}
