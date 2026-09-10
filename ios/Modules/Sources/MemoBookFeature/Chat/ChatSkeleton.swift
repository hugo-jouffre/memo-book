import MemoBookDesign
import SwiftUI

/// Ce que le chat montre pendant qu'il charge.
///
/// **Il ne dessine que ce qu'il sait déjà** : qu'il y aura un en-tête, une
/// bannière d'aperçu, une première bulle de MEMO et une barre en bas. C'est la
/// maquette « Chat - Skeleton », et c'est aussi la seule limite qu'un squelette
/// doit respecter — dessiner des cartes d'étapes ou des vignettes promettrait un
/// contenu qu'on ne connaît pas encore.
///
/// Les mesures viennent de ``ChatMetrics``, partagées avec l'écran réel : c'est
/// ce qui fait que le passage de l'un à l'autre ne saute pas.
struct ChatSkeleton: View {
    /// Les longueurs des lignes de texte simulées, en fraction de la largeur.
    ///
    /// Écrites à la main plutôt que tirées au sort : un squelette qui change de
    /// dessin à chaque lancement n'est plus comparable à la maquette, et deux
    /// captures d'écran ne se superposent plus.
    private static let paragraphs: [[Double]] = [
        [0.34, 0.92, 0.86, 0.28],
        [0.96, 0.88],
        [0.94, 0.9, 0.95, 0.3],
        [0.93, 0.97, 0.82, 0.86],
    ]

    private static let lineHeight: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Spacer(minLength: 0)
            bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BrandBackdrop())
        .brandSkeletonShimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de la conversation")
    }

    private var header: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            BrandSkeleton(cornerRadius: ChatMetrics.control)
                .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
            Spacer(minLength: 0)
            BrandSkeleton(cornerRadius: MemoBookSpacing.avatarSide)
                .frame(width: MemoBookSpacing.l, height: MemoBookSpacing.l)
            BrandSkeleton(cornerRadius: MemoBookSpacing.s)
                .frame(width: 84, height: MemoBookSpacing.sectionGap)
            Spacer(minLength: 0)
            BrandSkeleton(cornerRadius: ChatMetrics.control)
                .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
            BrandSkeleton(cornerRadius: ChatMetrics.control)
                .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.top, DeviceScreen.topSafeInset + MemoBookSpacing.xs)
        .padding(.bottom, MemoBookSpacing.snug)
        .background(ChatMetrics.barMaterial)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            banner
            bubble
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.top, MemoBookSpacing.m)
    }

    /// La bannière d'aperçu : sa pastille d'icône, ses trois lignes, sa flèche.
    private var banner: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            BrandSkeleton(cornerRadius: MemoBookSpacing.snug)
                .frame(width: MemoBookSpacing.xl, height: MemoBookSpacing.xl)

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton().frame(width: 96, height: Self.lineHeight)
                BrandSkeleton().frame(maxWidth: .infinity).frame(height: Self.lineHeight)
                BrandSkeleton().frame(maxWidth: .infinity).frame(height: Self.lineHeight)
            }

            BrandSkeleton(cornerRadius: MemoBookSpacing.s)
                .frame(width: MemoBookSpacing.sectionGap, height: MemoBookSpacing.sectionGap)
        }
        .padding(MemoBookSpacing.s)
        .background(
            MemoBookColor.hairline,
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
    }

    /// La grande bulle de MEMO, avec ses quatre paragraphes.
    private var bubble: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            ForEach(Array(Self.paragraphs.enumerated()), id: \.offset) { _, lines in
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, fraction in
                        BrandSkeleton()
                            .frame(height: Self.lineHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(x: fraction, anchor: .leading)
                    }
                }
            }
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: BrandChatBubble<EmptyView>.maximumContentWidth(for: .large))
        .background(
            MemoBookColor.surface,
            in: BrandBubbleShape(side: .leading)
        )
    }

    /// Les trois commandes de la barre d'envoi.
    private var bar: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            BrandSkeleton(cornerRadius: MemoBookSpacing.xs)
                .frame(width: MemoBookSpacing.sectionGap, height: MemoBookSpacing.snug)
            ForEach(0..<3, id: \.self) { _ in
                BrandSkeleton(cornerRadius: MemoBookSpacing.m)
                    .frame(height: MemoBookSpacing.xl + MemoBookSpacing.xs)
            }
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.top, MemoBookSpacing.xs)
        .padding(.bottom, DeviceScreen.bottomSafeInset + MemoBookSpacing.xs)
        .background(ChatMetrics.barMaterial)
    }
}

// MARK: - Aperçus

#Preview("Chat — squelette") {
    ChatSkeleton()
        .environment(\.colorScheme, .light)
}
