import MemoBookCore
import MemoBookDesign
import SwiftUI

// Les pièces que plusieurs étapes du tunnel se partagent. Rien ici ne décide
// de quoi que ce soit : ce sont des dessins, pilotés par ce qu'on leur passe.

// MARK: - L'intitulé d'une section

/// Le titre d'une étape, et la phrase qui l'explique quand il y en a une.
struct OrderSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)

            if let subtitle {
                Text(subtitle)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
        // Le titre s'enroule au lieu de se faire rogner : en taille accessible,
        // « Vérifications finales avant impression » tient sur trois lignes.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Une ligne de prix

/// Un libellé à gauche, un montant à droite. Le motif de tout le
/// récapitulatif, et de la ligne « Prix unitaire ».
struct OrderPriceRow: View {
    let label: String
    /// « x2 », posé entre le libellé et le montant.
    var detail: String?
    /// `nil` tant que le montant n'est pas arrivé : un squelette tient sa place.
    var amount: Decimal?
    var isProminent = false
    /// Le montant est une déduction : il s'écrit en négatif.
    var isNegative = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Côte à côte ils n'auraient plus que deux mots de large chacun en
        // taille accessible : ils s'empilent.
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    value
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                    title
                    Spacer(minLength: MemoBookSpacing.xs)
                    value
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            Text(label)
                .font(isProminent ? MemoBookFont.bodySemibold : MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            if let detail {
                Text(detail)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
    }

    @ViewBuilder
    private var value: some View {
        if let amount {
            Text(isNegative ? "- \(amount.euros)" : amount.euros)
                .font(isProminent ? MemoBookFont.figure : MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .monospacedDigit()
                // Le montant change quand on ajoute un exemplaire : il roule.
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            BrandSkeleton(width: 64, height: isProminent ? 20 : 14)
        }
    }
}

// MARK: - La carte de la cagnotte

/// Ce qu'il y a sur la cagnotte, et ce que le carnet coûtera. La carte d'en
/// haut de l'étape 1.
///
/// Elle **ne disparaît jamais** pendant le chargement : c'est le propre du
/// squelette de cette app — la page se dessine tout de suite, seules les
/// valeurs attendent. Voir ``BrandSkeleton``.
struct OrderHeroCard: View {
    let wallet: Wallet?
    let isLoading: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.galleryCornerRadius)

        return VStack(spacing: MemoBookSpacing.sectionGap) {
            balance
            estimate
        }
        .padding(MemoBookSpacing.m)
        .frame(maxWidth: .infinity)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .brandShadow(.soft)
    }

    private var balance: some View {
        VStack(spacing: MemoBookSpacing.xs / 2 + 2) {
            Text(BookCopy.Order.Start.balance)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)

            if isLoading {
                BrandSkeleton(width: 160, height: 48, cornerRadius: MemoBookSpacing.snug)
            } else {
                Text(wallet?.balance.roundedEuros ?? "")
                    .font(MemoBookFont.balance)
                    // Vert dès qu'il y a quelque chose dessus, gris à zéro —
                    // la même règle que l'écran de la cagnotte. Une cagnotte
                    // vide ne doit pas avoir l'air d'une réussite.
                    .foregroundStyle(
                        (wallet?.balance ?? 0) > 0 ? MemoBookColor.action : MemoBookColor.inkMuted
                    )
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var estimate: some View {
        if isLoading {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton()
                BrandSkeleton(
                    height: MemoBookSpacing.progressBarHeight,
                    cornerRadius: MemoBookSpacing.progressBarHeight / 2
                )
            }
        } else if let wallet, let estimate = wallet.estimate {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                estimateLine(estimate)
                BrandProgressTrack(
                    fraction: estimate.coverage(of: wallet.balance),
                    tone: .tinted
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(BookCopy.Order.Start.estimate(pages: estimate.pageCount)), environ \(estimate.cost.euros)"
            )
        }
    }

    @ViewBuilder
    private func estimateLine(_ estimate: WalletEstimate) -> some View {
        let pages = Text(BookCopy.Order.Start.estimate(pages: estimate.pageCount))
            .font(MemoBookFont.label)
            .foregroundColor(MemoBookColor.ink)
        let cost = Text("environ \(estimate.cost.roundedEuros)")
            .font(MemoBookFont.label)
            .foregroundColor(MemoBookColor.inkMuted)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                pages
                cost
            }
        } else {
            HStack(spacing: MemoBookSpacing.xs) {
                pages
                Spacer(minLength: MemoBookSpacing.xs)
                cost
            }
        }
    }
}

// MARK: - La carte du voyage

/// Le voyage qu'on s'apprête à faire imprimer, monté comme une photo dans un
/// album : un bout de ruban en haut, quatre coins de maintien.
///
/// Elle **ne s'ouvre pas** — on est déjà dans le tunnel de commande, la carte
/// est là pour dire *lequel* de ses voyages on commande, pas pour y aller.
struct OrderTripCard: View {
    let trip: Trip?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            photo
            caption
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity)
        .background(
            MemoBookColor.surface,
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
        }
        .overlay(alignment: .top) { tape }
        .brandShadow(.soft)
        .accessibilityElement(children: .combine)
    }

    /// Le ruban adhésif du haut. Décoratif, et volontairement discret : il dit
    /// « photo collée dans un carnet », il ne se regarde pas.
    private var tape: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(MemoBookColor.beige.opacity(0.9))
            .frame(width: 64, height: 17)
            .rotationEffect(.degrees(-1.5))
            .offset(y: -8)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var photo: some View {
        if let trip {
            TripCover(trip: trip, aspectRatio: 8 / 5, showsCompanions: false)
                .overlay { CornerMounts() }
        } else {
            BrandSkeleton(height: 190, cornerRadius: MemoBookSpacing.cornerRadius)
        }
    }

    @ViewBuilder
    private var caption: some View {
        if isLoading || trip == nil {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton(width: 120)
                BrandSkeleton(width: 220, height: 18)
                BrandSkeleton(width: 160)
            }
        } else if let trip {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                HStack(spacing: MemoBookSpacing.xs) {
                    // Un voyage sans destination nommée garde sa pastille
                    // d'état : la ligne ne se vide pas, elle se décale.
                    if let destination = trip.destination {
                        DestinationLabel(destination: destination)
                    }
                    Spacer(minLength: MemoBookSpacing.xs)
                    StageBadge(stage: trip.stage)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title)
                        .font(MemoBookFont.cardTitle)
                        .foregroundStyle(MemoBookColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if let dates = trip.dateRangeLabel {
                        Text(dates)
                            .font(MemoBookFont.label)
                            .foregroundStyle(MemoBookColor.inkMuted)
                    }
                }

                Rectangle()
                    .fill(MemoBookColor.hairline)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                TripStatsRow(stats: trip.stats)
            }
        }
    }
}

/// Les quatre coins de maintien de la photo. Purement décoratifs.
private struct CornerMounts: View {
    var body: some View {
        GeometryReader { proxy in
            ForEach(Corner.allCases, id: \.self) { corner in
                Triangle(corner: corner)
                    .fill(MemoBookColor.beige.opacity(0.85))
                    .frame(width: 17, height: 17)
                    .position(corner.point(in: proxy.size))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    fileprivate enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        func point(in size: CGSize) -> CGPoint {
            switch self {
            case .topLeading: CGPoint(x: 8.5, y: 8.5)
            case .topTrailing: CGPoint(x: size.width - 8.5, y: 8.5)
            case .bottomLeading: CGPoint(x: 8.5, y: size.height - 8.5)
            case .bottomTrailing: CGPoint(x: size.width - 8.5, y: size.height - 8.5)
            }
        }
    }

    private struct Triangle: Shape {
        let corner: Corner

        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch corner {
            case .topLeading:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .topTrailing:
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            case .bottomLeading:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .bottomTrailing:
                path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            }
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Une option d'exemplaire

/// Une option du carnet, avec son interrupteur. La « toggle-card » de la
/// maquette de l'étape 3.
struct OrderToggleCard: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .toggleStyle(SwitchToggleStyle(tint: MemoBookColor.action))
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.snug)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .background(
            MemoBookColor.surface,
            in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.controlCornerRadius)
                .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
        }
    }
}
