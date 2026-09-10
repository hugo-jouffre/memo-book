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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement de la conversation")
    }

    private var header: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            icon
            Spacer(minLength: 0)
            BrandSkeleton(
                width: MemoBookSpacing.l,
                height: MemoBookSpacing.l,
                cornerRadius: MemoBookSpacing.avatarSide
            )
            BrandSkeleton(
                width: 84,
                height: MemoBookSpacing.sectionGap,
                cornerRadius: MemoBookSpacing.s
            )
            Spacer(minLength: 0)
            icon
            icon
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.top, DeviceScreen.topSafeInset + MemoBookSpacing.xs)
        .padding(.bottom, MemoBookSpacing.snug)
        .background(ChatMetrics.barMaterial)
    }

    /// Une des quatre pastilles carrées de l'en-tête.
    private var icon: some View {
        BrandSkeleton(
            width: MemoBookSpacing.m,
            height: MemoBookSpacing.m,
            cornerRadius: ChatMetrics.control
        )
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
            BrandSkeleton(
                width: MemoBookSpacing.xl,
                height: MemoBookSpacing.xl,
                cornerRadius: MemoBookSpacing.snug
            )

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton(width: 96, height: Self.lineHeight)
                BrandSkeleton(height: Self.lineHeight)
                BrandSkeleton(height: Self.lineHeight)
            }

            BrandSkeleton(
                width: MemoBookSpacing.sectionGap,
                height: MemoBookSpacing.sectionGap,
                cornerRadius: MemoBookSpacing.s
            )
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
                        BrandSkeleton(height: Self.lineHeight)
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
            BrandSkeleton(
                width: MemoBookSpacing.sectionGap,
                height: MemoBookSpacing.snug,
                cornerRadius: MemoBookSpacing.xs
            )
            ForEach(0..<3, id: \.self) { _ in
                BrandSkeleton(
                    height: MemoBookSpacing.xl + MemoBookSpacing.xs,
                    cornerRadius: MemoBookSpacing.m
                )
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
