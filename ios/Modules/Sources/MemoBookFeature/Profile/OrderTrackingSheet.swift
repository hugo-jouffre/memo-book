import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Où en sont les carnets partis à l'impression.
///
/// Un délai, pas une date : c'est ce que l'imprimeur annonce, et annoncer un
/// jour précis qu'on ne tient pas vaut moins qu'une fourchette honnête.
struct OrderTrackingSheet: View {
    let orders: [OrderTracking]

    /// Le voyage en cours, s'il y en a un : sans commande, c'est **lui** que la
    /// feuille propose de commander (Hugo, 29/09/2026), plutôt que d'envoyer
    /// planifier un prochain voyage quelqu'un qui en raconte un.
    var ongoingTrip: CurrentTrip? = nil

    /// Ce que fait la carte de l'état vide : aller voir les carnets de la
    /// communauté, comme la maquette l'écrit dessus.
    let onPlanTrip: () -> Void

    /// « Commander mon carnet » : le tunnel de commande du voyage en cours.
    var onOrder: (CurrentTrip) -> Void = { _ in }

    /// Une commande abandonnée vient d'être payée : le profil se relit, et sa
    /// carte passe en livraison.
    var onOrdersChanged: () -> Void = {}

    /// « Finaliser ma commande » — posé par `RootView`. Absent en aperçu : le
    /// bouton ne s'affiche alors pas, plutôt que de ne rien faire.
    @Environment(\.finishAbandonedOrder) private var finishAbandonedOrder

    /// La commande dont le paiement est en train de reprendre. Une à la fois :
    /// deux feuilles de Stripe ne s'empilent pas.
    @State private var finishingOrderId: String?
    @State private var finishError: (orderId: String, message: String)?

    var body: some View {
        BrandSheet("Suivi des commandes") {
            VStack(spacing: MemoBookSpacing.s) {
                if orders.isEmpty, let ongoingTrip {
                    orderInvitation(ongoingTrip)
                } else if orders.isEmpty {
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
                        OrderCard(
                            order: order,
                            isFinishing: finishingOrderId == order.id,
                            finishError: finishError?.orderId == order.id ? finishError?.message : nil,
                            onFinish: order.isPaymentAbandoned && finishAbandonedOrder != nil
                                ? { finish(order) }
                                : nil
                        )
                    }
                }
            }
        }
    }
}

extension OrderTrackingSheet {
    /// Reprend le paiement d'une commande abandonnée, sans repasser par le
    /// tunnel : elle a déjà son adresse, ses exemplaires et son prix.
    private func finish(_ order: OrderTracking) {
        guard finishingOrderId == nil, let finishAbandonedOrder else { return }
        finishingOrderId = order.id
        finishError = nil

        Task {
            let outcome = await finishAbandonedOrder(order.id)
            finishingOrderId = nil
            switch outcome {
            case .paid: onOrdersChanged()
            case .cancelled: break
            case .failed(let message): finishError = (order.id, message)
            }
        }
    }

    /// Aucune commande, mais un voyage en cours : le carnet se commande d'ici.
    private func orderInvitation(_ trip: CurrentTrip) -> some View {
        VStack(spacing: MemoBookSpacing.s) {
            VStack(spacing: MemoBookSpacing.xs / 2) {
                Text("Aucune commande pour le moment")
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                Text("Ton carnet est en cours d’écriture : commande-le dès que tu es prêt.")
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)

            BrandButton(
                "Commander mon carnet",
                icon: Image(brand: "IconDeliver"),
                fillsWidth: true
            ) {
                onOrder(trip)
            }
        }
    }
}

/// Une commande : sa couverture, son délai, et ce qu'elle contient — ou, quand
/// son paiement a été laissé en route, son étiquette et « Finaliser ma
/// commande » (T232).
private struct OrderCard: View {
    let order: OrderTracking
    var isFinishing = false
    var finishError: String?
    /// `nil` sur une commande en route, ou hors session.
    var onFinish: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var coverSide: CGFloat = 72

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            // Le bouton reste un élément à part : fondu dans la carte, il
            // serait lu sans pouvoir être activé.
            content
                .accessibilityElement(children: .combine)

            if let onFinish {
                BrandButton(
                    "Finaliser ma commande",
                    icon: Image(brand: "IconCart"),
                    size: .medium,
                    isLoading: isFinishing,
                    fillsWidth: true,
                    action: onFinish
                )
                .disabled(isFinishing)
            }

            if let finishError {
                Text(finishError)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MemoBookSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            shape.strokeBorder(
                order.isPaymentAbandoned ? MemoBookColor.separator : MemoBookColor.action,
                lineWidth: 1
            )
        }
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
            if order.isPaymentAbandoned {
                // Pas de délai : rien n'est parti. L'étiquette dit pourquoi,
                // le titre dit quel carnet.
                Text("Paiement abandonné, commande non finalisée")
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.error)

                Text(order.tripTitle ?? "Ton carnet")
                    .font(MemoBookFont.heading)
                    .foregroundStyle(MemoBookColor.ink)
            } else {
                Text("Livraison")
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.action)

                Text("Dans \(order.minimumDays) à \(order.maximumDays) jours")
                    .font(MemoBookFont.heading)
                    .foregroundStyle(MemoBookColor.ink)
            }

            Text(contents)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// « 2 exemplaires - 50 pages ». L'accord suit le nombre : la maquette ne
    /// montre que le pluriel, une commande d'un seul exemplaire existe quand
    /// même. Une commande à finaliser dit aussi ce qu'il reste à payer.
    private var contents: String {
        let copies = order.copies == 1 ? "1 exemplaire" : "\(order.copies) exemplaires"
        let line = "\(copies) - \(order.pageCount) pages"
        guard order.isPaymentAbandoned, let total = order.total else { return line }
        return "\(line) - \(total.euros)"
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
