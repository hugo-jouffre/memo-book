import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La photo de couverture d'un voyage, et les compagnons posés dessus.
///
/// Tant qu'il n'y a pas d'URL — c'est le cas de tout le jeu d'essai, et ce sera
/// le cas d'un voyage sans photo — la couverture n'est pas un rectangle gris :
/// c'est un aplat de marque frappé du M. Un vide dessiné, pas un vide subi.
struct TripCover: View {
    let trip: Trip
    /// Rapport largeur / hauteur de la vignette. Les voyages en cours sont
    /// montrés en 16:9, les carnets terminés dans une bande plus basse.
    let aspectRatio: CGFloat
    var showsCompanions = true

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { artwork }
            .clipShape(.rect(cornerRadius: MemoBookSpacing.cornerRadius))
            .overlay(alignment: .bottomTrailing) { companions }
            .accessibilityHidden(true)
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
    }

    @ViewBuilder
    private var companions: some View {
        if showsCompanions, !trip.companions.isEmpty {
            CompanionStack(companions: trip.companions)
                .padding(MemoBookSpacing.xs + 2)
        }
    }
}

/// L'aplat de repli : deux teintes de la marque et le M en filigrane, choisis
/// d'après l'identifiant du voyage pour que deux carnets voisins ne se
/// ressemblent pas — et que le même carnet garde sa couleur d'un lancement à
/// l'autre.
struct TripCoverPlaceholder: View {
    let seed: String

    /// Couples de teintes, tous tirés des tokens : aucune couleur inventée.
    ///
    /// Lime en est volontairement absent. C'est l'accent du scheme, réservé
    /// aux petites surfaces — un aplat de couverture en lime crierait plus
    /// fort que la photo qu'il remplace.
    private static let palettes: [(Color, Color)] = [
        (MemoBookColor.outline, MemoBookColor.background),
        (MemoBookColor.action.opacity(0.6), MemoBookColor.outline),
        (MemoBookColor.separator, MemoBookColor.surface),
        (MemoBookColor.ink.opacity(0.5), MemoBookColor.outline),
    ]

    var body: some View {
        let palette = Self.palettes[Self.index(for: seed)]

        // Un aplat nu, sans le M : l'écran en porte déjà un en fond, et deux
        // signes qui se superposent ne se lisent plus ni l'un ni l'autre.
        LinearGradient(
            colors: [palette.0, palette.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Empreinte stable de l'identifiant, plutôt que `hashValue` : celui de
    /// Swift est aléatoire à chaque lancement du processus, et la couverture
    /// changerait de couleur d'une session à l'autre.
    ///
    /// La simple somme des scalaires ne suffisait pas : deux titres de même
    /// longueur tombaient trop souvent sur la même teinte. Le facteur 33
    /// (djb2) mélange les rangs entre eux.
    private static func index(for seed: String) -> Int {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return Int(hash % UInt64(palettes.count))
    }
}

/// Les compagnons de voyage, en pastilles qui se chevauchent.
struct CompanionStack: View {
    let companions: [Companion]

    /// Au-delà de trois, les visages ne se distinguent plus : la pastille
    /// suivante compte le reste.
    private static let visibleLimit = 3

    /// Taille figée, contrairement au reste de l'écran — même raison que la
    /// pastille numérotée de `WelcomeStepCard`. Ces ronds sont une décoration
    /// posée sur une photo au format fixe, masquée à VoiceOver : les faire
    /// grandir avec le texte ne rend rien de plus lisible et finit par couvrir
    /// la couverture entière.
    private let diameter: CGFloat = 34

    var body: some View {
        let shown = companions.prefix(Self.visibleLimit)
        let overflow = companions.count - shown.count

        // Un cinquième de recouvrement, pas un tiers : la pastille de droite
        // mangeait la deuxième initiale de celle de gauche.
        HStack(spacing: -diameter / 5) {
            ForEach(shown) { companion in
                bubble { initials(companion) }
                    .overlay { avatar(companion) }
            }
            if overflow > 0 {
                bubble { Text("+\(overflow)") }
            }
        }
    }

    private func bubble(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.custom(BrandFonts.generalSansSemibold, fixedSize: 12))
            .foregroundStyle(MemoBookColor.ink)
            .frame(width: diameter, height: diameter)
            .background(MemoBookColor.outline, in: .circle)
            .overlay { Circle().strokeBorder(MemoBookColor.surface, lineWidth: 2) }
    }

    private func initials(_ companion: Companion) -> some View {
        Text(companion.initials)
    }

    @ViewBuilder
    private func avatar(_ companion: Companion) -> some View {
        AsyncImage(url: companion.avatarUrl) { image in
            image
                .resizable()
                .scaledToFill()
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(MemoBookColor.surface, lineWidth: 2) }
        } placeholder: {
            // Les initiales dessinées dessous restent visibles.
            Color.clear
        }
    }
}
