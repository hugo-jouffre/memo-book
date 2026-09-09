import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les mesures de la mosaïque. Elles sont partagées par la grille, ses
/// vignettes et le modèle qui les répartit en colonnes : trois endroits qui
/// doivent tomber d'accord sur la hauteur d'une carte.
enum GalleryMetrics {
    /// Deux colonnes. Ce n'est pas un réglage : à trois, un titre de voyage
    /// tient sur trois lignes de deux mots.
    static let columnCount = 2

    /// Une seule colonne aux tailles de texte accessibles.
    ///
    /// À 165 points de large, « De Nantes à Saint-Malo à vélo » en AX3 fait dix
    /// lignes d'un mot. La mosaïque n'est pas ce qu'on protège ici : le titre
    /// l'est.
    static func columnCount(for typeSize: DynamicTypeSize) -> Int {
        typeSize.isAccessibilitySize ? 1 : columnCount
    }

    /// La gouttière, verticale comme horizontale.
    static let gutter: CGFloat = MemoBookSpacing.xs + 4

    /// Les formats possibles d'une vignette, en largeur / hauteur.
    ///
    /// Ce sont eux qui font la mosaïque : à format unique, la grille redevient
    /// deux colonnes bien sages et on ne distingue plus une carte de sa
    /// voisine. Les quatre valeurs encadrent le portrait — une vignette n'est
    /// jamais plus large que haute, sauf la plus courte, qui l'est à peine.
    private static let aspectRatios: [CGFloat] = [0.78, 1.12, 0.86, 1.0]

    /// Le format d'une vignette, tiré de l'identifiant du voyage.
    ///
    /// Même empreinte que celle des aplats de couverture — voir
    /// ``TripCoverPlaceholder`` : `hashValue` de Swift change à chaque
    /// lancement, et la grille se serait alors recomposée d'une session à
    /// l'autre. Ici elle ne bouge que si le contenu bouge.
    static func aspectRatio(for seed: String) -> CGFloat {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return aspectRatios[Int(hash % UInt64(aspectRatios.count))]
    }
}

/// Une vignette de la galerie : un carnet de la communauté, son titre et la
/// phrase qui le résume, posés sur son image.
///
/// **Elle ne s'ouvre pas encore.** Les carnets des autres n'ont pas d'écran :
/// la carte est donc une image et du texte, sans bouton ni flèche — rien qui
/// promette un geste qui ne se passerait pas.
struct GalleryTripCard: View {
    let trip: GalleryTrip

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.galleryCornerRadius)
    }

    var body: some View {
        content
            .clipShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    /// Aux tailles de texte accessibles, le titre **sort de l'image**.
    ///
    /// Une vignette a une hauteur fixée par son format : posé dessus, un titre
    /// en AX3 en déborde par le bas, recouvre le drapeau et se superpose à
    /// celui de la carte voisine. Le texte passe donc sous l'image, sur le
    /// papier de la marque, où il a toute la place de s'écrire — et il y gagne
    /// l'encre pleine, plus lisible que du blanc sur une photo.
    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                tile
                caption
                    .foregroundStyle(MemoBookColor.ink)
                    .padding(.top, MemoBookSpacing.xs)
            }
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        } else {
            tile
                .overlay { scrim }
                .overlay(alignment: .bottomLeading) {
                    caption.foregroundStyle(MemoBookColor.onAction)
                }
        }
    }

    /// L'image, à son format, avec le drapeau posé dans le coin.
    private var tile: some View {
        Color.clear
            .aspectRatio(GalleryMetrics.aspectRatio(for: trip.id), contentMode: .fit)
            .frame(maxWidth: .infinity)
            // L'image **remplit** le cadre et déborde par son plus grand côté.
            // C'est ce qui garantit qu'aucune vignette ne montre de bande vide,
            // quel que soit le format de la photo — et c'est la carte qui rogne
            // ce qui dépasse, pas l'image qui se déforme.
            .overlay { artwork }
            .overlay(alignment: .topLeading) { originMark }
            .clipShape(shape)
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: trip.coverPhotoUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                // Aucune photo n'est encore remontée du serveur : l'aplat de
                // marque des couvertures fait l'affaire, et donne à la grille
                // ses couleurs.
                TripCoverPlaceholder(seed: trip.id)
            }
        }
        .accessibilityHidden(true)
    }

    /// Le voile qui rend le texte lisible.
    ///
    /// Opaque en bas, transparent au tiers de la hauteur : le titre se lit sur
    /// n'importe quelle photo, y compris un ciel blanc, et le haut de l'image
    /// reste net. Sans lui, un titre blanc disparaît sur la moitié des
    /// couvertures — et l'assombrir en entier reviendrait à cacher ce qu'on
    /// vient montrer.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0.30),
                .init(color: .black.opacity(0.35), location: 0.62),
                .init(color: .black.opacity(0.68), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Le titre et sa phrase. La couleur vient de l'appelant : blanc sur
    /// l'image, encre sur le papier.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.title)
                .font(MemoBookFont.bodySemibold)

            if let subtitle = trip.subtitle {
                Text(subtitle)
                    .font(MemoBookFont.label)
                    // Une nuance en dessous, jamais un gris franc : sur une
                    // photo il devient sale, sur le papier il refroidit le
                    // crème.
                    .opacity(0.85)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MemoBookSpacing.xs + 4)
    }

    /// D'où vient le carnet : le drapeau du pays, ou le globe dès qu'il y en a
    /// plusieurs.
    ///
    /// Choisir un drapeau parmi dix désignerait le premier pays comme *le* pays
    /// du voyage, ce qu'un tour du monde n'a pas. Le globe le dit sans mentir —
    /// et c'est aussi ce qu'on montre quand le pays n'a pas de code exploitable.
    @ViewBuilder
    private var originMark: some View {
        Group {
            if let flag = trip.flag {
                Text(flag).font(MemoBookFont.caption)
            } else {
                Image(brand: "IconGlobeDuo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: markSide, height: markSide)
            }
        }
        .padding(4)
        .background(MemoBookColor.surface.opacity(0.9), in: .circle)
        .padding(MemoBookSpacing.xs)
        .accessibilityHidden(true)
    }

    @ScaledMetric(relativeTo: .caption) private var markSide: CGFloat = 14

    /// VoiceOver lit la carte d'un bloc, et nomme le pays plutôt que de laisser
    /// passer un drapeau qu'il annoncerait « emoji ».
    private var accessibilityLabel: String {
        [
            trip.title,
            trip.subtitle,
            trip.destinations.isEmpty
                ? nil
                : trip.destinations.map(\.name).formatted(.list(type: .and)),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// La place d'une vignette qui n'est pas encore arrivée.
///
/// La grille se dessine **tout de suite**, à sa forme définitive : l'écran
/// s'ouvre sur une mosaïque qui se remplit, et non sur un crème vide qui saute
/// d'un coup. Les formats sont ceux des vraies vignettes, tirés d'un rang.
struct GalleryCardPlaceholder: View {
    let rank: Int

    var body: some View {
        Color.clear
            .aspectRatio(GalleryMetrics.aspectRatio(for: "placeholder-\(rank)"), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { TripCoverPlaceholder(seed: "placeholder-\(rank)").opacity(0.5) }
            .clipShape(.rect(cornerRadius: MemoBookSpacing.galleryCornerRadius))
            .accessibilityHidden(true)
    }
}
