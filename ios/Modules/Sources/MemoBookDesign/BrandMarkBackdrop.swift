import SwiftUI

/// Le M posé en fond d'écran, au cadrage de la maquette de lancement.
///
/// **Un seul cadrage pour deux écrans.** L'écran de lancement l'utilise pour
/// tracer le signe, l'accueil pour le garder derrière son contenu. Comme les
/// deux passent par cette vue, le M ne bouge pas d'un pixel au moment où l'un
/// remplace l'autre : seule son opacité change, et le passage se lit comme un
/// fondu du signe vers l'arrière-plan plutôt que comme un changement d'écran.
///
/// Il est **fixe** : posé en fond d'une `ScrollView`, il ne défile pas avec le
/// contenu — c'est un décor, pas un élément de la page.
public struct BrandMarkBackdrop: View {
    /// Part du trait déjà tracée. 1 pour un signe entier.
    private let progress: Double

    /// Opacité du trait. Franche pendant le tracé, discrète une fois le contenu
    /// posé — voir ``BrandMarkBackdrop/drawingOpacity`` et
    /// ``BrandMarkBackdrop/restingOpacity``.
    private let opacity: Double

    /// Échelle du signe, pour le faire arriver et se poser.
    private let scale: CGFloat

    public init(progress: Double, opacity: Double, scale: CGFloat = 1) {
        self.progress = progress
        self.opacity = opacity
        self.scale = scale
    }

    /// Pendant le tracé : on veut le voir s'écrire.
    public static let drawingOpacity: Double = 0.5

    /// Une fois l'accueil en place : présent, mais en dessous du contenu, sans
    /// concurrencer un titre ni une photo.
    public static let restingOpacity: Double = 0.2

    // Cadrage relevé sur la maquette de lancement. Le signe déborde de
    // l'écran : on n'en voit que le cœur, les deux jambages sortent du cadre.
    // Les décalages sont des fractions de l'écran, pour suivre toutes les
    // tailles d'iPhone ; ils amènent la boucle au centre optique, la boîte du
    // tracé penchant vers son long jambage gauche.

    /// Largeur du signe, en largeurs d'écran.
    private static let overscan: CGFloat = 2.0

    /// Décalage horizontal, en largeurs d'écran.
    private static let horizontalShift: CGFloat = 0.15

    /// Décalage vertical, en hauteurs d'écran.
    private static let verticalShift: CGFloat = 0.09

    public var body: some View {
        // `GeometryReader` assumé, pour deux raisons qu'aucune API plus récente
        // ne couvre : la hauteur du signe se déduit de sa **largeur** —
        // `containerRelativeFrame` ne sait pas dériver une dimension de
        // l'autre —, et les deux décalages sont des fractions de l'écran, donc
        // des nombres.
        GeometryReader { proxy in
            let width = proxy.size.width * Self.overscan

            BrandMarkDrawing(
                progress: progress,
                color: MemoBookColor.outline.opacity(opacity)
            )
            .frame(width: width, height: BrandMark.height(forWidth: width))
            .scaleEffect(scale)
            .position(
                x: proxy.size.width * (0.5 + Self.horizontalShift),
                y: proxy.size.height * (0.5 + Self.verticalShift)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Le M en fond") {
    ZStack {
        MemoBookColor.background.ignoresSafeArea()
        BrandMarkBackdrop(progress: 1, opacity: BrandMarkBackdrop.restingOpacity)
    }
}
