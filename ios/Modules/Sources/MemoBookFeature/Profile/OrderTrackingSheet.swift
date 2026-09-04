import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Où en sont les carnets partis à l'impression.
///
/// Un délai, pas une date : c'est ce que l'imprimeur annonce, et annoncer un
/// jour précis qu'on ne tient pas vaut moins qu'une fourchette honnête.
struct OrderTrackingSheet: View {
    let orders: [OrderTracking]

    var body: some View {
        BrandSheet("Suivi des commandes") {
            VStack(spacing: MemoBookSpacing.s) {
                if orders.isEmpty {
                    // État non maquetté : une phrase qui dit ce qui manque,
                    // plutôt qu'une feuille vide.
                    EmptyStateView(
                        systemImage: "shippingbox",
                        title: "Aucune commande en cours",
                        message: "Tes carnets imprimés apparaîtront ici dès que tu en auras commandé un."
                    )
                } else {
                    ForEach(orders) { order in
                        OrderCard(order: order)
                    }
                }
            }
        }
    }
}

/// Une commande : sa couverture, son délai, et ce qu'elle contient.
private struct OrderCard: View {
    let order: OrderTracking

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var coverSide: CGFloat = 72

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        content
            .padding(MemoBookSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { shape.strokeBorder(MemoBookColor.action, lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                cover
                text.padding(.horizontal, MemoBookSpacing.xs)
            }
        } else {
            HStack(spacing: MemoBookSpacing.s) {
                cover
                text
                Spacer(minLength: 0)
            }
        }
    }

    private var cover: some View {
        AsyncImage(url: order.coverImageUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                // Pas de photo : l'aplat de marque, comme les couvertures sans
                // image de l'accueil.
                MemoBookColor.outline
            }
        }
        .frame(width: coverSide, height: coverSide)
        .clipShape(.rect(cornerRadius: MemoBookSpacing.cornerRadius))
        .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Livraison")
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.action)

            Text("Dans \(order.minimumDays) à \(order.maximumDays) jours")
                .font(MemoBookFont.heading)
                .foregroundStyle(MemoBookColor.ink)

            Text(contents)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// « 2 exemplaires - 50 pages ». L'accord suit le nombre : la maquette ne
    /// montre que le pluriel, une commande d'un seul exemplaire existe quand
    /// même.
    private var contents: String {
        let copies = order.copies == 1 ? "1 exemplaire" : "\(order.copies) exemplaires"
        return "\(copies) - \(order.pageCount) pages"
    }
}

#Preview("Suivi des commandes") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            OrderTrackingSheet(orders: TravellerProfile.fixture.orders)
        }
}

#Preview("Suivi des commandes — aucune") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            OrderTrackingSheet(orders: [])
        }
}
