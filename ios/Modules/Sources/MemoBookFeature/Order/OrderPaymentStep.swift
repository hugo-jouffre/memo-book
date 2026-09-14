import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Étape 6 — par quoi on paie, où ça va, et combien.
///
/// ⚠️ **Aucun encaissement n'a lieu.** « Payer » enregistre la commande en
/// brouillon ; le débit viendra du webhook du prestataire, avec le passage en
/// `submitted`. C'est la même honnêteté que l'abonnement du profil : l'écran
/// est complet, le paiement ne l'est pas encore, et rien ici ne prétend le
/// contraire.
struct OrderPaymentStep: View {
    let model: OrderModel
    let onChoosePayment: () -> Void

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
                model.quote?.isFullyCovered == true
                    ? BookCopy.Order.Payment.freeCta
                    : BookCopy.Order.Payment.cta,
                isLoading: model.isSubmitting,
                fillsWidth: true
            ) {
                Task { await model.pay() }
            }
            .disabled(!model.canContinue || model.isSubmitting)
        }
        .animation(.smooth(duration: 0.25), value: model.draft.paymentCardId)
        .animation(.smooth(duration: 0.25), value: model.draft.usesApplePay)
    }

    // MARK: Le moyen de paiement

    @ViewBuilder
    private var method: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            if model.quote?.isFullyCovered == true {
                // La cagnotte couvre tout : présenter une carte pour un débit
                // de zéro ferait craindre un prélèvement.
                BrandNotice("**\(BookCopy.Order.Payment.free)** — il n’y a rien à régler.")
            } else if model.draft.usesApplePay {
                BrandApplePayRow(isSelected: true, action: onChoosePayment)
                changeButton
            } else if let card = model.selectedCard {
                OrderCreditCard(card: card, holder: model.draft.shipping.name)
                changeButton
            } else {
                BrandButton(
                    BookCopy.Order.Payment.choose,
                    style: .secondary,
                    fillsWidth: true,
                    action: onChoosePayment
                )
            }
        }
    }

    private var changeButton: some View {
        BrandButton(
            BookCopy.Order.Payment.change,
            style: .secondary,
            fillsWidth: true,
            action: onChoosePayment
        )
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

// MARK: - La carte de crédit

/// La carte enregistrée, dessinée comme une carte.
///
/// **Le numéro complet n'existe nulle part dans l'app** — voir ``PaymentCard``.
/// Ce qu'on montre est un gabarit : les quatre derniers chiffres, précédés de
/// groupes masqués.
private struct OrderCreditCard: View {
    let card: PaymentCard
    let holder: String

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            Text(card.label)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.paper.opacity(0.7))

            Text(card.maskedNumber)
                .font(MemoBookFont.cardTitle)
                .foregroundStyle(MemoBookColor.paper)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !holder.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(holder)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.paper.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MemoBookSpacing.s)
        .background(
            MemoBookColor.ink,
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .brandShadow(.soft)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.label), carte se terminant par \(card.last4)")
    }
}

// MARK: - La feuille du mode de paiement

/// « Choisis ton mode de paiement » : les cartes enregistrées, Apple Pay, et de
/// quoi en ajouter une.
///
/// **Une seule feuille**, qui porte aussi l'échec de paiement en tête plutôt
/// que d'en ouvrir une deuxième par-dessus — voir la règle des feuilles
/// enchaînées dans `CLAUDE.md`.
struct OrderPaymentSheet: View {
    let model: OrderModel
    let onConfirm: () -> Void

    var body: some View {
        BrandSheet(
            BookCopy.Order.Payment.sheetTitle,
            subtitle: BookCopy.Order.Payment.sheetSubtitle
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                if let message = model.paymentError {
                    ErrorBanner(message: message)
                }

                BrandOptionGroup {
                    ForEach(model.context?.cards ?? []) { card in
                        BrandOptionRow(
                            card.label,
                            subtitle: card.maskedNumber,
                            value: card.id == model.context?.selectedCardId
                                ? BookCopy.Order.Payment.defaultCard
                                : nil,
                            isSelected: !model.draft.usesApplePay
                                && card.id == model.draft.paymentCardId
                        ) {
                            model.select(cardId: card.id)
                        }
                    }

                    BrandApplePayRow(isSelected: model.draft.usesApplePay) {
                        model.selectApplePay()
                    }
                }

                // ⚠️ **Pas de formulaire de carte ici.** Enregistrer un moyen
                // de paiement passe par le profil, où la feuille existe déjà :
                // en ouvrir une seconde depuis le tunnel ferait reculer deux
                // écrans d'affilée, et surtout dupliquerait le seul endroit de
                // l'app qui touche à un numéro de carte.
                BrandButton(
                    BookCopy.Order.Payment.confirm,
                    fillsWidth: true,
                    action: onConfirm
                )
                .disabled(!model.draft.hasPaymentMethod)
            }
        }
    }
}
