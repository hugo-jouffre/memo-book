import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La couverture d'un voyage : sa photo pleine largeur, ce qu'on y a fait, et
/// qui y est.
///
/// **Le texte est blanc sur une photo qu'on ne choisit pas.** C'est le seul
/// endroit de l'app où le contraste ne peut pas se calculer d'avance : une
/// couverture claire rendrait le titre illisible. Deux voiles dégradés le
/// garantissent — un en haut pour les commandes, un en bas pour le titre — et
/// ils sont donc du dessin, pas de la décoration.
struct TripHeader: View {
    let detail: TripDetail

    let onBack: () -> Void
    let onPrint: () -> Void
    let onSettings: () -> Void
    let onInvite: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Le rapport de la maquette : la photo occupe un peu plus d'un carré. Un
    /// rapport plutôt qu'une hauteur en points, pour que la couverture garde
    /// ses proportions du SE au Pro Max.
    private static let aspectRatio: CGFloat = 390 / 440

    private var trip: Trip { detail.trip }

    /// La hauteur de la maquette — un **plancher**, pas une hauteur figée.
    ///
    /// C'est toute la différence : figée, elle rognait tout en taille de texte
    /// accessible. Les compteurs, qui s'empilent alors les uns sous les autres,
    /// débordaient par le haut et venaient se poser sur la flèche de retour.
    /// En plancher, la photo grandit avec ce qu'elle porte.
    private var minimumHeight: CGFloat { DeviceScreen.width / Self.aspectRatio }

    var body: some View {
        // Une **pile**, et non des calques posés sur un cadre fixe : c'est le
        // contenu qui décide de la hauteur, et rien ne peut donc en sortir.
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            controls
            Spacer(minLength: MemoBookSpacing.xl)
            caption
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
        .background {
            artwork
            scrim
        }
        .clipped()
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: trip.coverPhotoUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                TripCoverPlaceholder(seed: trip.id)
            }
        }
        .accessibilityHidden(true)
    }

    /// Le voile. Deux dégradés dans le même calque : le haut porte les
    /// commandes, le bas porte le titre, et le milieu de la photo reste net.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .black.opacity(0.05), location: 0.32),
                .init(color: .black.opacity(0.10), location: 0.55),
                .init(color: .black.opacity(0.65), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Commandes

    private var controls: some View {
        // Les commandes gardent leur place quelle que soit la taille du texte :
        // ce sont trois ronds de 44, pas des libellés.
        HStack(spacing: MemoBookSpacing.xs + 2) {
            TripHeaderButton(icon: "IconArrow", label: "Retour", action: onBack)
            Spacer(minLength: 0)
            TripHeaderButton(icon: "IconPrinter", label: "Imprimer ce carnet", action: onPrint)
            TripHeaderButton(icon: "IconSettings", label: "Paramètres du voyage", action: onSettings)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        // La photo passe sous la barre d'état ; les commandes, elles, se posent
        // dessous. `DeviceScreen` porte la mesure parce qu'elle change d'un
        // iPhone à l'autre — 20 pt sur un SE, 59 sur un modèle à Dynamic Island.
        .padding(.top, DeviceScreen.topSafeInset + MemoBookSpacing.xs)
    }

    // MARK: - Ce qu'on lit sur la photo

    private var caption: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            TripStatsRow(stats: trip.stats, tint: MemoBookColor.onAction, isSpread: false)

            Text(trip.title)
                .font(MemoBookFont.h1)
                .foregroundStyle(MemoBookColor.onAction)
                .fixedSize(horizontal: false, vertical: true)

            people
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.bottom, MemoBookSpacing.l)
    }

    /// Deux groupes : ceux qui racontent le voyage, et ceux qui le suivent. En
    /// taille de texte accessible ils passent l'un sous l'autre — six pastilles
    /// et deux pictogrammes sur une ligne ne tiennent plus.
    @ViewBuilder
    private var people: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                travellers
                followers
            }
        } else {
            HStack(spacing: MemoBookSpacing.s) {
                travellers
                followers
                Spacer(minLength: 0)
            }
        }
    }

    private var travellers: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            marker("IconUser")

            CompanionStack(companions: trip.companions, visibleLimit: 2)
                .accessibilityElement()
                .accessibilityLabel(travellersLabel)

            Button(action: onInvite) {
                Image(brand: "IconPlus")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.s, height: MemoBookSpacing.s)
                    .foregroundStyle(MemoBookColor.ink)
                    .frame(width: 34, height: 34)
                    .background(MemoBookColor.surface, in: .circle)
            }
            .frame(
                minWidth: MemoBookSpacing.minimumTapTarget,
                minHeight: MemoBookSpacing.minimumTapTarget
            )
            .contentShape(.circle)
            .accessibilityLabel("Inviter quelqu’un à ce voyage")
        }
    }

    @ViewBuilder
    private var followers: some View {
        if !detail.followers.isEmpty {
            HStack(spacing: MemoBookSpacing.xs) {
                // L'œil, et non la bichrome du jeu : une icône « duo » porte
                // ses propres couleurs, et la teinter en blanc la réduit à une
                // silhouette pleine — c'est un rond blanc qui apparaissait.
                marker("IconView")

                CompanionStack(
                    companions: detail.followers,
                    visibleLimit: 2,
                    totalCount: detail.followerCount
                )
            }
            .accessibilityElement()
            .accessibilityLabel("\(detail.followerCount) personnes suivent ce voyage")
        }
    }

    private func marker(_ name: String) -> some View {
        Image(brand: name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.s + 2, height: MemoBookSpacing.s + 2)
            .foregroundStyle(MemoBookColor.onAction)
            .accessibilityHidden(true)
    }

    private var travellersLabel: String {
        let names = trip.companions.map(\.name).formatted(.list(type: .and))
        return trip.companions.isEmpty ? "Personne d’autre pour l’instant" : "Avec \(names)"
    }
}

/// Un rond translucide posé sur la photo.
///
/// Le fond sombre n'est pas un choix de marque mais une garantie de lisibilité :
/// une icône blanche sur une couverture claire disparaîtrait sans lui.
private struct TripHeaderButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                .foregroundStyle(MemoBookColor.onAction)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .background(.black.opacity(0.35), in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        }
        .contentShape(.circle)
        .accessibilityLabel(label)
    }
}
