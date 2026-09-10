import SwiftUI

/// Une forme grise qui tient la place d'un contenu pas encore arrivé.
///
/// **Toujours un rectangle arrondi**, parce qu'un squelette ne dessine que des
/// blocs : dès qu'il essaie de reproduire une carte, une icône ou un avatar, il
/// promet un contenu qu'il ne connaît pas encore.
///
/// ```swift
/// VStack(spacing: MemoBookSpacing.xs) {
///     BrandSkeleton().frame(height: 14)
///     BrandSkeleton().frame(width: 120, height: 14)
/// }
/// .brandSkeletonShimmer()
/// ```
///
/// Le lustre ne s'anime pas tout seul : il est piloté par
/// ``SwiftUI/View/brandSkeletonShimmer()``, posé **une fois** sur le conteneur.
/// C'est ce qui fait passer la lumière sur tous les blocs **en même temps** —
/// autant d'animations indépendantes se désynchroniseraient en quelques
/// secondes, et un squelette qui scintille en désordre attire l'œil au lieu de
/// se faire oublier.
public struct BrandSkeleton: View {
    private let cornerRadius: CGFloat

    /// - Parameter cornerRadius: par défaut celui d'une ligne de texte. Passer
    ///   ``MemoBookSpacing/bubbleCornerRadius`` pour un bloc de bulle, ou une
    ///   grande valeur pour un rond.
    public init(cornerRadius: CGFloat = MemoBookSpacing.xs / 2) {
        self.cornerRadius = cornerRadius
    }

    @Environment(\.brandSkeletonPhase) private var phase

    /// Le gris d'un squelette : le filet de la marque, un peu appuyé. Assez
    /// visible pour dire « il y aura quelque chose ici », assez discret pour
    /// qu'on n'essaie pas de le lire.
    private static let fill = MemoBookColor.hairline

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(Self.fill)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            MemoBookColor.surface.opacity(0.7),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.55)
                    // De hors-cadre à gauche à hors-cadre à droite.
                    .offset(x: proxy.size.width * (phase * 1.6 - 0.55))
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Anime le lustre de tous les ``BrandSkeleton`` posés en dessous, **en
    /// phase**.
    ///
    /// À poser une seule fois, sur le conteneur du squelette. Sans effet quand
    /// « Réduire les animations » est activé : le squelette reste alors un gris
    /// immobile, ce qui dit exactement la même chose sans rien faire bouger.
    public func brandSkeletonShimmer() -> some View {
        modifier(BrandSkeletonShimmer())
    }
}

private struct BrandSkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.brandSkeletonPhase, phase)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension EnvironmentValues {
    /// De 0 à 1 : où en est le lustre du squelette. Il descend par
    /// l'environnement pour que tous les blocs s'éclairent ensemble.
    @Entry var brandSkeletonPhase: CGFloat = 0
}

// MARK: - Aperçus

#Preview("Squelette") {
    VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
        BrandSkeleton(cornerRadius: MemoBookSpacing.largeCornerRadius)
            .frame(height: 88)
        BrandSkeleton().frame(height: 14)
        BrandSkeleton().frame(height: 14)
        BrandSkeleton().frame(width: 140, height: 14)
    }
    .brandSkeletonShimmer()
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
