import MemoBookCore
import MemoBookDesign
import SwiftUI

// Les deux feuilles de l'écran d'offre : le calcul, et le paiement.

// MARK: - Estimation

/// Les chiffres de la feuille « Estimation ».
///
/// ⚠️ **Une projection, pas un devis** — au même titre que les « 40 pages » de
/// l'écran 2. Le serveur ne sert au paywall ni la durée du voyage ni le coût du
/// carnet : les trois semaines, les 50 pages et les 60 € sont ceux de la maquette
/// (`3469:14105`), et seul le prix hebdomadaire vient de l'offre. Le jour où
/// `GET /v1/wallet` — qui connaît déjà l'estimation d'un carnet — sera lu ici,
/// cette structure se remplit avec et rien d'autre ne bouge. Signalé (T127).
struct PaywallEstimation {
    let weeks: Int
    let start: Date
    let end: Date
    let pageCount: Int
    /// Le prix estimé du carnet, en euros.
    let bookPrice: Decimal
    let weeklyPrice: Decimal

    /// Ce que les semaines d'abonnement ont coûté — et qui se déduit.
    var subscriptionTotal: Decimal { Decimal(weeks) * weeklyPrice }

    /// Ce qu'il reste à payer à la commande.
    var finalAmount: Decimal { bookPrice - subscriptionTotal }

    /// Le prix d'un exemplaire de plus : -20 %.
    var extraCopyPrice: Decimal { bookPrice * 0.8 }

    /// « 15 sept. - 6 oct. » — les bornes, écrites court.
    var periodLabel: String {
        let short = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(start.formatted(short)) - \(end.formatted(short))"
    }

    /// Les chiffres de la maquette, sur trois semaines à partir d'aujourd'hui.
    static func example(weeklyPrice: Decimal) -> PaywallEstimation {
        let start = Date.now
        return PaywallEstimation(
            weeks: 3,
            start: start,
            end: Calendar.current.date(byAdding: .weekOfYear, value: 3, to: start) ?? start,
            pageCount: 50,
            bookPrice: 60,
            weeklyPrice: weeklyPrice
        )
    }
}

/// « Estimation » — d'où vient le montant final, ligne à ligne.
///
/// Le nœud `3469:14105` : la durée du voyage et ses dates, le prix du carnet et
/// ses pages, le cumul des abonnements **en négatif** — c'est l'argument de la
/// carte qui ouvre la feuille —, un filet, le montant final, et la remise sur
/// les exemplaires suivants dans un cartouche bleu.
struct PaywallEstimationSheet: View {
    let estimation: PaywallEstimation

    var body: some View {
        BrandSheet(PaywallCopy.Estimation.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                period

                VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                    line(
                        PaywallCopy.Estimation.bookPrice,
                        detail: PaywallCopy.Estimation.pages(estimation.pageCount),
                        amount: estimation.bookPrice.roundedEuros
                    )

                    line(
                        PaywallCopy.Estimation.subscriptions,
                        detail: PaywallCopy.Estimation.subscriptionDetail(
                            weeks: estimation.weeks,
                            weeklyPrice: estimation.weeklyPrice.euros
                        ),
                        amount: "-\(estimation.subscriptionTotal.euros)",
                        isCircled: true
                    )

                    Rectangle()
                        .fill(MemoBookColor.hairline)
                        .frame(height: 1)
                        .accessibilityHidden(true)

                    total
                    extraCopies
                }
            }
        }
    }

    /// « 3 semaines de voyage », et les dates au bout de la ligne.
    private var period: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.s) {
            Text(PaywallCopy.Estimation.duration(weeks: estimation.weeks))
                .font(MemoBookFont.calloutTitle)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(estimation.periodLabel)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// Une ligne du calcul : l'intitulé et sa précision à gauche, le montant à
    /// droite — cerclé de bleu pour celui qui se déduit, comme le trait à la
    /// main de la maquette.
    private func line(_ title: String, detail: String, amount: String, isCircled: Bool = false) -> some View {
        HStack(alignment: .center, spacing: MemoBookSpacing.s) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                Text(title)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.ink)
                Text(detail)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(amount)
                .font(MemoBookFont.body)
                .monospacedDigit()
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize()
                .padding(.horizontal, isCircled ? MemoBookSpacing.xs : 0)
                .overlay {
                    if isCircled {
                        // Le cercle esquissé de la maquette : une ellipse un peu
                        // plus large que le chiffre, dans le bleu d'aplat.
                        Ellipse()
                            .strokeBorder(MemoBookColor.outline, lineWidth: 1.5)
                            .padding(.horizontal, -MemoBookSpacing.xs / 2)
                            .padding(.vertical, -MemoBookSpacing.xs)
                            .accessibilityHidden(true)
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }

    /// « Montant final à payer lors de la commande du carnet » — en gras des
    /// deux côtés : c'est le chiffre qu'on vient chercher.
    private var total: some View {
        HStack(alignment: .center, spacing: MemoBookSpacing.s) {
            Text(PaywallCopy.Estimation.total)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(estimation.finalAmount.euros)
                .font(MemoBookFont.bodySemibold)
                .monospacedDigit()
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// Le cartouche bleu : « -20 % pour chaque carnet supplémentaire », et ce
    /// que ça donne par exemplaire.
    private var extraCopies: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.s) {
            (Text(PaywallCopy.Estimation.extraCopiesLead).font(MemoBookFont.tagline)
                + Text(" " + PaywallCopy.Estimation.extraCopies).font(MemoBookFont.taglineRegular))
                .foregroundStyle(MemoBookColor.blueText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(PaywallCopy.Estimation.perCopy(estimation.extraCopyPrice.roundedEuros))
                .font(MemoBookFont.label)
                .monospacedDigit()
                .foregroundStyle(MemoBookColor.blueText)
                .fixedSize()
        }
        .padding(.horizontal, MemoBookSpacing.xs)
        .padding(.vertical, MemoBookSpacing.xs)
        .background(MemoBookColor.outline.opacity(0.3), in: .rect(cornerRadius: MemoBookSpacing.xs))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Paiement

/// « Choisis ton mode de paiement » — les cartes du compte, Apple Pay, de quoi
/// en ajouter une, et « Payer ».
///
/// **La feuille du tunnel de commande, pilotée par le profil.** `OrderPaymentSheet`
/// lit ses cartes dans le contexte d'une commande ; ici il n'y a pas de
/// commande, il y a un compte — et ``ProfileModel`` est ce qui lit et écrit
/// ses cartes, comme sur l'écran du profil. Même dessin, même
/// ``AddCardSheet`` par-dessus pour le formulaire de carte, qui reste le seul
/// endroit de l'app à toucher un numéro.
///
/// ⚠️ **Aucun encaissement n'a lieu.** « Payer » pose l'abonnement comme le
/// faisait le bouton de l'offre — voir `ProfileModel.activateSubscription()` —
/// et rien de plus : StoreKit n'est pas branché, et l'écran ne prétend pas le
/// contraire.
struct PaywallPaymentSheet: View {
    let model: ProfileModel
    /// Le prix affiché sur le bouton — celui de l'offre.
    let price: String
    /// « Payer » : la feuille a fini, l'abonnement se pose.
    let onPaid: () -> Void

    @State private var selectedCardId: String?
    @State private var usesApplePay = false
    @State private var isAddingCard = false

    private var cards: [PaymentCard] { model.profile?.cards ?? [] }
    private var hasMethod: Bool { usesApplePay || selectedCardId != nil }

    var body: some View {
        BrandSheet(
            BookCopy.Order.Payment.sheetTitle,
            subtitle: BookCopy.Order.Payment.sheetSubtitle
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                if model.isLoading {
                    // Les cartes arrivent : deux barres à la place des lignes,
                    // et la feuille garde sa hauteur.
                    VStack(spacing: MemoBookSpacing.xs) {
                        BrandSkeleton(height: 66)
                        BrandSkeleton(height: 66)
                    }
                } else {
                    BrandOptionGroup {
                        ForEach(cards) { card in
                            BrandOptionRow(
                                card.label,
                                subtitle: card.maskedNumber,
                                value: card.id == model.profile?.selectedCardId
                                    ? BookCopy.Order.Payment.defaultCard
                                    : nil,
                                isSelected: !usesApplePay && card.id == selectedCardId
                            ) {
                                usesApplePay = false
                                selectedCardId = card.id
                            }
                        }

                        BrandApplePayRow(isSelected: usesApplePay) {
                            usesApplePay = true
                        }
                    }
                }

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }

                BrandButton(
                    BookCopy.Order.Payment.addCard,
                    icon: Image(brand: "IconPlus"),
                    iconPlacement: .trailing,
                    style: .secondary,
                    fillsWidth: true
                ) {
                    isAddingCard = true
                }

                BrandButton(PaywallCopy.Payment.pay(price), fillsWidth: true, action: onPaid)
                    .disabled(!hasMethod)
            }
        }
        .task {
            await model.load()
            if selectedCardId == nil { selectedCardId = model.profile?.selectedCardId }
        }
        // Une carte qui vient d'être ajoutée devient la carte du compte
        // (`ProfileModel.addCard`) : elle se coche ici dans le même geste.
        .onChange(of: model.profile?.selectedCardId) { _, id in
            guard let id else { return }
            selectedCardId = id
            usesApplePay = false
        }
        .brandSheet(isPresented: $isAddingCard) {
            AddCardSheet { number, name in
                model.addCard(number: number, label: name)
            }
        }
    }
}

#Preview("Estimation") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            PaywallEstimationSheet(estimation: .example(weeklyPrice: 1.99))
        }
}

#Preview("Paiement") {
    let model = ProfileModel()

    return Color.clear
        .brandSheet(isPresented: .constant(true)) {
            PaywallPaymentSheet(model: model, price: "1,99 €") {}
        }
}
