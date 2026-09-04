import MemoBookCore
import MemoBookDesign
import SwiftUI

// Les trois cartes de l'accueil. Elles partagent la même coque — surface
// blanche, rayon 20, filet discret — et ne diffèrent que par ce qu'elles
// mettent dedans : la couverture pleine pour le voyage du moment, une ligne
// pour les autres voyages en cours, une bande pour les carnets terminés.

/// Le voyage du moment : couverture, pays, état, titre, dates et compteurs.
struct FeaturedTripCard: View {
    let trip: Trip
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Un bout de scotch collé en haut de la carte, comme sur une page de
    /// carnet.
    ///
    /// Trois choses le font lire comme du scotch et pas comme un onglet : il
    /// est **par-dessus** la carte et non derrière, il est **translucide** —
    /// on voit le bord de la carte au travers, c'est ce qui trahit un adhésif —
    /// et il est **de travers**. Ses coins sont à peine adoucis : une bande
    /// coupée aux ciseaux n'a pas de rayon.
    private var tape: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(MemoBookColor.separator.opacity(0.55))
            .frame(width: 64, height: 22)
            .rotationEffect(.degrees(-5))
            // Il chevauche le bord haut : une moitié sur la carte, une moitié
            // dans le vide.
            .offset(y: -9)
            .padding(.leading, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                TripCover(trip: trip, aspectRatio: 16 / 9)
                    .padding(MemoBookSpacing.xs)

                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    header
                    titleAndDates
                    Rectangle()
                        .fill(MemoBookColor.hairline)
                        .frame(height: 1)
                    TripStatsRow(stats: trip.stats)
                }
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.bottom, MemoBookSpacing.s)
            }
        }
        .buttonStyle(CardPressStyle())
        .homeCard()
        // Le contenu est déjà décrit ligne à ligne ; VoiceOver lit une seule
        // fois le voyage, avec son état, plutôt que six éléments séparés.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .top) { tape }
    }

    /// Le pays à gauche, l'état à droite — sauf en taille accessible, où la
    /// pastille prend toute la largeur et ne laisserait au nom du pays que de
    /// quoi le couper en deux.
    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                destinationLabel
                stageBadge
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                destinationLabel
                Spacer(minLength: 0)
                stageBadge
            }
        }
    }

    @ViewBuilder
    private var destinationLabel: some View {
        if let destination = trip.destination {
            DestinationLabel(destination: destination)
        }
    }

    @ViewBuilder
    private var stageBadge: some View {
        if trip.stage.isOngoing {
            StageBadge()
        }
    }

    private var titleAndDates: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.title)
                .font(MemoBookFont.heading)
                .foregroundStyle(MemoBookColor.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let dates = trip.dateRangeLabel {
                Text(dates)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un autre voyage en cours : titre et compteurs sur une ligne, sans photo.
struct CompactTripCard: View {
    let trip: Trip
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: MemoBookSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let summary = trip.stats.inlineSummary {
                        Text(summary)
                            .font(MemoBookFont.label)
                            .foregroundStyle(MemoBookColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(brand: "IconArrowRight")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                    .foregroundStyle(MemoBookColor.ink)
                    .padding(MemoBookSpacing.xs + 2)
                    .background(MemoBookColor.background, in: .circle)
            }
            .padding(MemoBookSpacing.s)
        }
        .buttonStyle(CardPressStyle())
        .homeCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Un carnet terminé : sa bande de couverture, son titre, et de quoi le faire
/// imprimer quand il est prêt.
struct PastTripCard: View {
    let trip: Trip
    let onOpen: () -> Void
    let onOrderPrint: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    TripCover(trip: trip, aspectRatio: 5 / 2, showsCompanions: false)
                        .padding(MemoBookSpacing.xs)
                    caption
                        .padding(.horizontal, MemoBookSpacing.s)
                        .padding(.bottom, trip.isPrintable ? 0 : MemoBookSpacing.s)
                }
            }
            .buttonStyle(CardPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
        .homeCard()
    }

    @ViewBuilder
    private var caption: some View {
        // Le bouton d'impression descend sous le titre dès que le texte a
        // besoin de toute la largeur.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                titleAndDates
                printButton
            }
            .padding(.bottom, trip.isPrintable ? MemoBookSpacing.s : 0)
        } else {
            HStack(alignment: .center, spacing: MemoBookSpacing.xs) {
                titleAndDates
                Spacer(minLength: 0)
                printButton
            }
            .padding(.bottom, trip.isPrintable ? MemoBookSpacing.xs : 0)
        }
    }

    private var titleAndDates: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let flag = trip.destination?.flag {
                    Text(flag)
                }
                Text(trip.title)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let dates = trip.dateRangeLabel {
                Text(dates)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var printButton: some View {
        if trip.isPrintable {
            // Icône système en attendant l'export Figma de cet écran.
            BrandButton(
                icon: Image(brand: "IconPrinter"),
                style: .soft,
                size: .small,
                action: onOrderPrint
            )
            .accessibilityLabel("Commander l’impression de « \(trip.title) »")
        }
    }
}

// MARK: - Pièces communes

/// La pastille d'état d'un voyage en cours.
struct StageBadge: View {
    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Text("EN COURS")
            .font(MemoBookFont.overline)
            .tracking(MemoBookFont.tracking(12))
            .foregroundStyle(MemoBookColor.action)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, 3)
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.action, lineWidth: 1) }
            .fixedSize()
    }
}

/// Le drapeau et le pays, en capitales.
struct DestinationLabel: View {
    let destination: Destination

    var body: some View {
        HStack(spacing: 6) {
            if let flag = destination.flag {
                Text(flag)
                    .font(MemoBookFont.overline)
            }
            Text(destination.name.uppercased())
                .font(MemoBookFont.overline)
                .tracking(MemoBookFont.tracking(12))
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.name)
    }
}

/// Durée, distance, photos — répartis sur la largeur de la carte.
struct TripStatsRow: View {
    let stats: TripStats

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var iconSide: CGFloat = 16

    var body: some View {
        let items = stats.items

        if !items.isEmpty {
            // En taille accessible les trois compteurs ne tiennent plus sur une
            // ligne : ils s'empilent au lieu de se tronquer.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                    ForEach(items) { item($0) }
                }
            } else {
                HStack(spacing: MemoBookSpacing.xs) {
                    ForEach(items) { value in
                        item(value)
                        // Un ressort entre chaque compteur, pas après le
                        // dernier : les trois se répartissent sur la largeur
                        // de la carte au lieu de se tasser à gauche.
                        if value.id != items.last?.id { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }

    private func item(_ item: TripStatItem) -> some View {
        HStack(spacing: 5) {
            item.kind.icon
                .frame(width: iconSide, height: iconSide)
                .foregroundStyle(MemoBookColor.inkMuted)
            Text(item.text)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.text)
    }
}

// MARK: - Coque et retour tactile

extension View {
    /// La carte de l'accueil : surface blanche, rayon 20, un filet pour la
    /// décoller du crème du fond.
    func homeCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .contentShape(shape)
    }
}

/// Une carte s'enfonce légèrement sous le doigt, sans changer d'opacité :
/// c'est du papier, pas un bouton.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}
