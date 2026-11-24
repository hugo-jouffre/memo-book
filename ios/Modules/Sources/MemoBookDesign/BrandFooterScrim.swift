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

    /// **L'exception du paywall** (T251, Hugo, 24/11/2026).
    ///
    /// Aux tailles de texte accessibles, les 90 % ne suffisent plus : les mots
    /// qui passent dessous sont assez gros pour rester **lisibles**, et le
    /// pied du paywall laissait lire le texte des cartes sous « S'abonner ».
    /// Le voile fait alors exactement l'inverse de ce qu'il promet — « on voit
    /// passer ce qui défile, on ne le lit plus ».
    ///
    /// Hugo a tranché pour l'aplat plein **sur ce seul écran** : un paywall
    /// est le moment où l'on décide de payer, et ce qui transparaît sous le
    /// bouton y coûte plus cher qu'ailleurs. Partout ailleurs la règle tient,
    /// et c'est pour ça que l'opacité est un paramètre et non une constante
    /// changée.
    private let isOpaque: Bool

    public init(isOpaque: Bool = false) {
        self.isOpaque = isOpaque
    }

    private var veil: Double { isOpaque ? 1 : Self.opacity }

    public var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    MemoBookColor.background.opacity(0),
                    MemoBookColor.background.opacity(veil),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)

            MemoBookColor.background.opacity(veil)
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
    ///
    /// - Parameter isOpaque: l'aplat plein, **réservé au paywall** (T251).
    ///   Ailleurs, le voile reste translucide : c'est la règle de la marque.
    public func brandFooterScrim(isOpaque: Bool = false) -> some View {
        background { BrandFooterScrim(isOpaque: isOpaque) }
    }
}
