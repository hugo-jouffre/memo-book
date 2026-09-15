import SwiftUI

/// Le voile posé derrière le pied d'un écran — un appel à l'action, une
/// mention — pour que ce qui défile dessous s'y **dissolve** au lieu de venir
/// buter dessus.
///
/// **Un seul voile pour toute l'app.** Il en existait quatre, écrits chacun de
/// leur côté : celui de l'accueil, opaque et haut de 200 pt ; celui de la
/// commande, un aplat plein sous un fondu de 32 ; ceux de la création d'un
/// voyage et de la galerie. Trois intensités et deux hauteurs pour le même
/// geste — et selon l'écran, le voile était trop appuyé ou s'arrêtait trop tôt,
/// si bien que le contenu réapparaissait sous l'indicateur d'accueil (Hugo,
/// 15/09/2026).
///
/// Deux règles, et c'est tout :
///
/// - **Il reste translucide.** Le pied garde 90 % du crème, jamais 100 : on
///   voit *passer* ce qui défile dessous, on ne le lit plus. Un aplat plein fait
///   un bandeau ; un voile fait un pied de page.
/// - **Il descend jusqu'au bord de la dalle.** La zone sûre du bas en fait
///   partie : c'est précisément là que le texte restait lisible.
///
/// Il se pose en **fond du pied** (``SwiftUI/View/brandFooterScrim()``) et
/// déborde de ``fadeHeight`` au-dessus de lui : cette bande fait le fondu, le
/// pied lui-même est sur l'aplat. Le fond d'une vue collée au bas de l'écran
/// traverse la zone sûre de lui-même ; `ignoresSafeArea` est répété ici pour
/// que ce soit vrai aussi d'un pied posé dans un `safeAreaInset`.
public struct BrandFooterScrim: View {
    /// La hauteur du fondu au-dessus du pied. Assez pour qu'un titre s'y
    /// éteigne en deux lignes, pas assez pour manger la carte du dessus.
    public static let fadeHeight: CGFloat = MemoBookSpacing.xl + MemoBookSpacing.s

    /// Ce que le pied garde du crème. Sous 1, pour laisser deviner ce qui passe.
    static let opacity: Double = 0.9

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    MemoBookColor.background.opacity(0),
                    MemoBookColor.background.opacity(Self.opacity),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)

            MemoBookColor.background.opacity(Self.opacity)
        }
        .padding(.top, -Self.fadeHeight)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Pose le voile de la marque derrière un pied d'écran — voir
    /// ``BrandFooterScrim``. À appliquer sur le pied lui-même, marges comprises.
    public func brandFooterScrim() -> some View {
        background { BrandFooterScrim() }
    }
}
