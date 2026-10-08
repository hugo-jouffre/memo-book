import SwiftUI

/// Le voile posé sous la barre d'état — l'heure, la batterie, l'île — pour
/// que ce qui défile dessous s'y **dissolve** au lieu de passer sous les
/// chiffres.
///
/// Sans lui, le texte d'un écran qui défile venait se lire à travers l'heure :
/// profil, réglages du voyage, commande, aperçu, support, accueil (T210). Hugo
/// l'a voulu **sur tous les écrans**, photos pleine page comprises, et « de la
/// hauteur de la barre d'état, dégradé sur le bord inférieur, similaire au
/// bandeau derrière « Commencer à enregistrer » » (06/10/2026). **Sauf
/// l'accueil d'un voyage** (08/10/2026) : sa photo pleine page reprend le haut
/// de l'écran, et le dégradé crème s'y lisait comme une bande étrange.
///
/// C'est donc le frère de ``BrandFooterScrim``, retourné, et il en reprend les
/// deux règles :
///
/// - **Il reste translucide** — le même crème à 90 % : on voit passer ce qui
///   défile, on ne le lit plus.
/// - **Il ne dépasse pas la barre d'état.** Le fondu est pris *dans* sa
///   hauteur, sur son bord bas, et non ajouté dessous : au repos, l'en-tête
///   d'un écran commence juste sous l'heure, et un fondu qui déborderait
///   pâlirait sa flèche de retour.
///
/// Il se pose **une fois**, à la racine (``SwiftUI/View/brandStatusBarScrim()``) :
/// tous les écrans de l'app sont des écrans poussés dans la même pile, et une
/// feuille de la marque s'arrête bien avant la barre d'état. Seul un écran
/// présenté en plein écran (le paywall) doit le reposer chez lui.
public struct BrandStatusBarScrim: View {
    /// La hauteur du fondu, au plus. Sur un iPhone à île (≈ 60 pt de barre),
    /// l'heure reste sous l'aplat ; sur un iPhone SE (20 pt), le fondu se
    /// réduit à proportion (``fadeHeight(for:)``) pour ne pas l'atteindre.
    public static let maximumFadeHeight: CGFloat = MemoBookSpacing.s

    /// La hauteur de la barre d'état, lue par ``SwiftUI/View/brandStatusBarScrim()``.
    let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    /// Le fondu pour une barre de `height` points : au plus
    /// ``maximumFadeHeight``, au plus un tiers de la barre.
    public static func fadeHeight(for height: CGFloat) -> CGFloat {
        max(0, min(maximumFadeHeight, height / 3))
    }

    public var body: some View {
        let fade = Self.fadeHeight(for: height)
        VStack(spacing: 0) {
            MemoBookColor.background.opacity(BrandFooterScrim.opacity)
                .frame(height: max(0, height - fade))

            LinearGradient(
                colors: [
                    MemoBookColor.background.opacity(BrandFooterScrim.opacity),
                    MemoBookColor.background.opacity(0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fade)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Pose le voile de la barre d'état par-dessus la vue — voir
    /// ``BrandStatusBarScrim``. À appliquer sur la racine d'un écran qui
    /// occupe tout l'écran, pas sur chaque écran d'une pile.
    ///
    /// La hauteur se lit sur la zone sûre du haut : 20 pt sur un iPhone SE,
    /// une soixantaine sur un iPhone à île, rien quand la barre est cachée.
    ///
    /// - Parameter isVisible: faux sous un écran dont la photo monte, pleine
    ///   page, jusque sous l'heure — l'accueil d'un voyage (Hugo, 08/10/2026).
    ///   Le voile s'y efface en fondu, et revient de même à l'écran suivant.
    public func brandStatusBarScrim(isVisible: Bool = true) -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                BrandStatusBarScrim(height: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isVisible)
            .allowsHitTesting(false)
        }
    }
}

#Preview("Voile de la barre d’état") {
    ScrollView {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            ForEach(0..<30) { index in
                Text("Ligne \(index) — le texte passe sous l’heure sans s’y lire")
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
            }
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
    .brandStatusBarScrim()
}
