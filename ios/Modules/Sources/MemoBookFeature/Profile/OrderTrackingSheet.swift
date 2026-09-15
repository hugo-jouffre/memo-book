import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Où en sont les carnets partis à l'impression.
///
/// Un délai, pas une date : c'est ce que l'imprimeur annonce, et annoncer un
/// jour précis qu'on ne tient pas vaut moins qu'une fourchette honnête.
struct OrderTrackingSheet: View {
    let orders: [OrderTracking]

    /// Ce que fait la carte de l'état vide : aller voir les carnets de la
    /// communauté, comme la maquette l'écrit dessus.
    let onPlanTrip: () -> Void

    var body: some View {
        BrandSheet("Suivi des commandes") {
            VStack(spacing: MemoBookSpacing.s) {
                if orders.isEmpty {
                    // **La maquette existe** — `Modale – Profile PAS de
                    // commande`, `3162:34917` : la même carte en pointillés que
                    // l'accueil sans voyage à venir, « Commence à planifier ton
                    // prochain voyage », avec son bout de scotch. Rien à
                    // inventer, donc : c'est la carte de l'accueil, dont seule
                    // la seconde ligne change avec la destination (T22).
                    //
                    // ⚠️ Le titre de la maquette n'a pas pu être lu (quota MCP) :
                    // celui de la ligne reste. Sa seconde ligne écrit « le
                    // carnets » ; c'est une coquille, corrigée ici.
                    UpcomingTripInvite(
                        onOpen: onPlanTrip,
                        subtitle: "Clique ici pour voir les carnets de la communauté"
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
            OrderTrackingSheet(orders: TravellerProfile.fixture.orders) {}
        }
}

#Preview("Suivi des commandes — aucune") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            OrderTrackingSheet(orders: []) {}
        }
}
