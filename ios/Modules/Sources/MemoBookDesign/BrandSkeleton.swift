import SwiftUI

/// La place d'une valeur qui n'est pas encore arrivée.
///
/// **Elle ne remplace jamais un écran, seulement une valeur.** Un écran de
/// MemoBook est fait à 90 % de choses que l'app connaît déjà — ses intitulés,
/// ses groupes, ses boutons : les cacher derrière un chargement parce qu'un
/// numéro de téléphone met 200 ms à venir fait apparaître la page en deux
/// temps, et donne l'impression que tout est lent. La page se dessine donc
/// tout de suite, et seules les valeurs qui viennent du serveur portent cette
/// barre.
///
/// Le reflet balaie la barre en boucle. C'est ce mouvement qui la distingue
/// d'un aplat gris, qu'on lirait comme un champ désactivé — mais il s'arrête
/// sous « Réduire les animations », où la barre reste sagement grise.
public struct BrandSkeleton: View {
    private let width: CGFloat?
    private let onDark: Bool

    /// - Parameters:
    ///   - width: la largeur de la barre. `nil` la laisse prendre toute la
    ///     place disponible — pour une valeur posée sous son intitulé.
    ///   - onDark: la barre est posée sur une photo ou un aplat sombre, comme
    ///     la couverture d'un voyage. Elle passe alors en clair : l'encre à 9 %
    ///     y disparaîtrait complètement.
    public init(width: CGFloat? = nil, onDark: Bool = false) {
        self.width = width
        self.onDark = onDark
    }

    /// La hauteur suit le corps de texte : la barre tient exactement la place
    /// que la valeur prendra, et la ligne ne saute pas en se remplissant.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    public var body: some View {
        Capsule()
            // Le noir de la marque à peine posé, pas un gris système : la barre
            // doit rester dans le crème de la page. Sur un fond sombre, c'est
            // le blanc de la marque qui joue le même rôle.
            .fill(onDark ? MemoBookColor.onAction.opacity(0.22) : MemoBookColor.ink.opacity(0.09))
            .frame(width: width, height: height)
            .overlay { sheen }
            .clipShape(.capsule)
            .accessibilityHidden(true)
            .onAppear { isSweeping = true }
    }

    /// Le reflet : une bande claire qui traverse la barre.
    ///
    /// Il est **masqué par la barre elle-même** plutôt que dessiné à sa
    /// largeur — c'est ce qui lui permet de sortir des deux côtés au lieu de
    /// s'allumer et de s'éteindre sur place.
    @ViewBuilder
    private var sheen: some View {
        if !reduceMotion {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [
                        .clear,
                        onDark
                            ? MemoBookColor.onAction.opacity(0.35)
                            : MemoBookColor.surface.opacity(0.9),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * 0.6)
                .offset(x: isSweeping ? proxy.size.width : -proxy.size.width * 0.6)
                .animation(
                    // Une pause entre deux passages : un reflet continu
                    // clignote, un reflet qui repasse *de temps en temps* dit
                    // « ça travaille » sans occuper l'œil.
                    .easeInOut(duration: 1.1).repeatForever(autoreverses: false).delay(0.2),
                    value: isSweeping
                )
            }
        }
    }
}

#Preview("Barres d’attente") {
    VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
        BrandSkeleton(width: 120)
        BrandSkeleton(width: 180)
        BrandSkeleton()

        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BrandSkeleton(width: 120, onDark: true)
            BrandSkeleton(width: 180, onDark: true)
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoBookColor.ink, in: .rect(cornerRadius: MemoBookSpacing.cornerRadius))
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
