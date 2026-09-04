import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le titre d'une section de l'accueil, avec ses deux décorations possibles :
/// le point vert qui signale « en ce moment », et la pastille lime qui compte
/// ce que la section contient.
struct HomeSectionHeading: View {
    let title: String
    var showsLiveDot = false
    var count: Int?

    @ScaledMetric(relativeTo: .title3) private var dotSide: CGFloat = 9

    var body: some View {
        // Espacement nul : c'est le décalage de la pastille qui la place, et
        // il la fait mordre sur la dernière lettre du titre.
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if showsLiveDot {
                    Circle()
                        // Le vert clair, pas celui du CTA : c'est un voyant,
                        // pas une action. (`Green Lighter`, à confirmer sur le
                        // nœud Figma.)
                        .fill(MemoBookColor.actionLight)
                        .frame(width: dotSide, height: dotSide)
                        // Le point se cale sur la hauteur d'x du titre plutôt
                        // que sur sa ligne de base, où il flotterait.
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(MemoBookFont.heading)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let count, count > 0 {
                CountBadge(count: count)
                    // Elle est dessinée après le titre, donc au-dessus : elle
                    // chevauche la fin du mot au lieu de le suivre.
                    .offset(x: -11, y: -MemoBookSpacing.xs)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// La pastille lime qui compte les carnets d'une section. Lime est l'accent du
/// scheme : il ne sert qu'à ça, ponctuellement, jamais en aplat large.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("×\(count)")
            .font(MemoBookFont.overline)
            .foregroundStyle(MemoBookColor.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(MemoBookColor.accent, in: .rect(cornerRadius: MemoBookSpacing.xs))
            .fixedSize()
            .accessibilityLabel("\(count) au total")
    }
}

/// La carte de découverte : un carnet d'exemple, pour comprendre où tout ça
/// mène avant d'avoir enregistré quoi que ce soit.
///
/// Le pointillé la distingue des cartes de contenu : ce n'est pas un de tes
/// voyages, c'est une porte vers autre chose. L'image, elle, va **jusqu'au bord
/// droit** — elle n'est pas une vignette posée dans la carte, elle en est le
/// flanc.
struct ShowcaseCard: View {
    let showcase: Showcase
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 104

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Button(action: onOpen) {
            content
                .frame(minHeight: minimumHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CardPressStyle())
        .background(MemoBookColor.outline.opacity(0.22), in: shape)
        // L'image touche les bords : c'est la carte qui la rogne.
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                MemoBookColor.outline,
                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
            )
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        // En taille accessible le texte a besoin de toute la largeur : l'image
        // passe dessous plutôt que de lui voler la moitié de la carte.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                text.padding([.top, .horizontal], MemoBookSpacing.s)
                artwork
                    .frame(height: minimumHeight)
                    .overlay(alignment: .bottomTrailing) { arrow.padding(MemoBookSpacing.xs + 4) }
            }
        } else {
            HStack(spacing: 0) {
                text.padding(MemoBookSpacing.s)
                Spacer(minLength: MemoBookSpacing.xs)
                artwork
                    // Assez étroit pour que le titre tienne sur une ligne à la
                    // largeur de référence, assez large pour qu'on distingue
                    // les carnets sur la photo.
                    .frame(width: 124)
                    .overlay(alignment: .bottomTrailing) { arrow.padding(MemoBookSpacing.xs + 4) }
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(showcase.title)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.blueText)
            Text(showcase.subtitle)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.blueTextSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le flanc illustré : les carnets terminés.
    ///
    /// L'illustration est **livrée avec l'app** tant que le serveur n'en fournit
    /// pas : c'est une image de marque, pas un contenu qui change avec les
    /// données. Le jour où une campagne veut la sienne, `Showcase.imageUrl` la
    /// remplace sans toucher à la vue.
    private var artwork: some View {
        AsyncImage(url: showcase.imageUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(brand: "ShowcaseCarnets")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    /// Rond blanc cerclé de bleu, posé à cheval sur l'image.
    ///
    /// `IconArrowRight` et non `IconArrow` : celle du jeu de marque pointe à
    /// **gauche**, c'est une flèche de retour.
    private var arrow: some View {
        Image(brand: "IconArrowRight")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
            .foregroundStyle(MemoBookColor.blueText)
            .padding(MemoBookSpacing.xs)
            .background(MemoBookColor.surface, in: .circle)
            .overlay { Circle().strokeBorder(MemoBookColor.blueText, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}

/// L'accueil d'un compte tout neuf : aucun voyage, et une seule chose à faire.
struct HomeEmptyState: View {
    var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            BrandMarkDrawing(progress: 1, color: MemoBookColor.outline)
                .frame(width: 120, height: BrandMark.height(forWidth: 120))
                .padding(.bottom, MemoBookSpacing.xs)

            Text("Ton premier carnet commence ici")
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            Text("Raconte ta journée à la voix : MemoBook s’occupe du reste.")
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.l)
        .padding(.horizontal, MemoBookSpacing.s)
        .homeCard()
    }
}
