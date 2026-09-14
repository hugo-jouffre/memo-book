import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Étape 5 — le récapitulatif : ce qu'on imprime, en combien d'exemplaires, ce
/// que la cagnotte couvre, et ce qui reste à payer.
///
/// **Aucun montant n'est calculé ici.** Tout arrive de
/// `POST /v1/memos/:id/orders/quote`, y compris les sous-totaux : deux calculs
/// pour un même total finiraient par se contredire, et c'est l'app qui aurait
/// tort devant la personne qui paie.
///
/// Il est le plus souvent **déjà là** quand on arrive : le devis part dès que
/// le nombre d'exemplaires ou la rapidité changent, donc bien avant cette
/// étape. Le squelette ne se voit que sur un réseau lent.
struct OrderSummaryStep: View {
    let model: OrderModel

    var body: some View {
        OrderStepLayout {
            OrderSectionHeader(title: BookCopy.Order.Summary.title)

            if let quote = model.quote {
                card(quote)
                    .transition(.opacity)
            } else if let message = model.quoteError {
                ErrorBanner(message: message) { model.refreshQuote() }
            } else {
                skeleton
            }
        } actions: {
            BrandButton(
                BookCopy.Order.Summary.cta,
                fillsWidth: true,
                action: model.advance
            )
            .disabled(!model.canContinue)
        }
        .animation(.smooth(duration: 0.3), value: model.quote)
    }

    /// Le bloc bleu de la maquette : deux groupes qui portent chacun leur
    /// sous-total, les déductions, puis le total.
    private func card(_ quote: OrderQuote) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            Text(BookCopy.Order.Summary.book(quote.bookTitle))
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            group(quote.book)

            // La fabrication ne se choisit pas : elle se **lit**, sous le prix.
            // Elle était facturée en trois lignes, ce qui laissait croire à
            // trois options — alors qu'il n'y a qu'un papier, qu'une couverture
            // et qu'une reliure, et que le prix ne suit que les pages.
            if !quote.specifications.isEmpty {
                specifications(quote.specifications)
            }

            separator
            group(quote.fulfilment)

            if !quote.deductions.isEmpty {
                VStack(spacing: MemoBookSpacing.xs) {
                    ForEach(quote.deductions) { deduction($0) }
                }
            }

            separator

            OrderPriceRow(
                label: BookCopy.Order.Summary.total,
                amount: quote.total,
                isProminent: true
            )
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoBookColor.listeningBackground.opacity(0.45),
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                .strokeBorder(MemoBookColor.outline.opacity(0.6), lineWidth: 1)
        }
    }

    /// Un groupe de lignes, et le sous-total aligné à droite qui les ferme.
    ///
    /// **Le sous-total disparaît quand il ne fait que répéter.** Depuis que le
    /// carnet ne se facture qu'en une ligne, le groupe du haut affichait deux
    /// fois le même montant l'un sous l'autre — un total de rien du tout.
    private func group(_ group: OrderQuoteGroup) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            ForEach(group.lines) { line in
                OrderPriceRow(label: line.label, detail: line.detail, amount: line.amount)
            }

            if group.lines.count > 1 {
                Text(group.subtotal.euros)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Sous-total \(group.subtotal.euros)")
            }
        }
    }

    /// Une déduction, sur son aplat : le lime pour ce que l'abonnement a versé,
    /// le bleu pour ce que les proches ont offert — les deux natures de
    /// ``WalletEntryKind``, et les deux couleurs de la maquette.
    private func deduction(_ deduction: OrderDeduction) -> some View {
        OrderPriceRow(label: deduction.label, amount: deduction.amount, isNegative: true)
            .padding(.horizontal, MemoBookSpacing.snug)
            .padding(.vertical, MemoBookSpacing.snug)
            .background(
                deduction.isFromSubscription
                    ? MemoBookColor.accent.opacity(0.45)
                    : MemoBookColor.outline.opacity(0.45),
                in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
            )
    }

    /// La petite boîte qui décrit le carnet, sous son prix.
    private func specifications(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BookCopy.Order.Summary.specifications)
                .font(MemoBookFont.overline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)

            // Séparés par des points médians plutôt qu'en liste à puces : c'est
            // une description, pas un choix, et trois puces rendraient la
            // hiérarchie des lignes facturées au-dessus.
            Text(items.joined(separator: " · "))
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(BookCopy.Order.Summary.pricedByPages)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.vertical, MemoBookSpacing.xs)
        .background(
            MemoBookColor.surface.opacity(0.7),
            in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
        )
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Rectangle()
            .fill(MemoBookColor.ink.opacity(0.12))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BrandSkeleton(width: 200, height: 18)
            ForEach(0..<6, id: \.self) { _ in
                HStack {
                    BrandSkeleton(width: 150)
                    Spacer()
                    BrandSkeleton(width: 60)
                }
            }
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoBookColor.listeningBackground.opacity(0.45),
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
    }
}
