import SwiftUI

/// Motif de fond de la marque. Il déborde volontairement de l'écran ; il est
/// mis à l'échelle pour couvrir n'importe quelle taille d'iPhone en gardant le
/// cadrage de la maquette.
public struct BrandBackdrop: View {
    /// Cadre de référence de la maquette.
    private static let reference = CGSize(width: 390, height: 844)

    /// Taille du SVG, marges de débord comprises.
    private static let artwork = CGSize(width: 767.604, height: 602.933)

    /// Décalage du centre du motif par rapport au centre de l'écran, mesuré
    /// dans le cadre de référence.
    private static let center = CGSize(width: 48.67, height: -21.4)

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let scale = max(
                proxy.size.width / Self.reference.width,
                proxy.size.height / Self.reference.height
            )

            Image(brand: "Backdrop")
                .resizable()
                .scaledToFit()
                .frame(width: Self.artwork.width * scale, height: Self.artwork.height * scale)
                // Le motif est dessiné à l'horizontale et posé debout dans la
                // maquette. La rotation ne change pas la taille de mise en
                // page, donc le centre reste celui du cadre ci-dessus.
                .rotationEffect(.degrees(-90))
                .offset(x: Self.center.width * scale, y: Self.center.height * scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(MemoBookColor.background)
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
