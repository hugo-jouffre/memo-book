import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Un plat de couverture, dessiné.
///
/// **La seule vue de couverture de l'app.** Les quatre écrans du parcours s'en
/// servent — le choix, le carrousel des styles, celui des photos et l'écran des
/// textes —, et c'est ce qui garantit qu'on regarde la même chose du début à la
/// fin : un plat qui changerait d'un écran à l'autre ne serait plus un aperçu.
///
/// ⚠️ **Ce n'est pas le rendu d'impression.** Le carnet est mis en page par le
/// gabarit, que l'app ne rejoue pas (voir ``BookPreview``). Ce plat-ci montre la
/// **composition** — le cadrage, la place du titre, le rapport A5 — avec la
/// photo et les mots du voyageur. Le jour où le gabarit rendra les couvertures,
/// cette vue laisse la place à une image et rien d'autre ne bouge.
struct CoverPlate: View {
    let cover: BookCover
    let style: CoverStyle?
    let photo: CoverPhoto?
    let face: CoverFace
    /// Les chiffres à imprimer au dos. Vides sur la première de couverture.
    var stats: [CoverStat] = []
    /// La largeur du plat. Sa hauteur en découle — voir ``ratio``.
    var width: CGFloat

    /// Ce que les crayons de l'écran des textes viennent poser par-dessus. Rien
    /// sur les trois autres écrans.
    var titleBadge: AnyView?
    var subtitleBadge: AnyView?
    var statsBadge: AnyView?

    /// Le rapport d'un carnet A5 — celui du carnet imprimé, et celui que la
    /// vignette des réglages emploie déjà.
    ///
    /// La maquette dessine 233 × 339, soit 1,455 : neuf points d'écart sur la
    /// hauteur. C'est **le format du papier** qui tranche, pas l'artboard.
    /// Signalé (T87).
    static let ratio: CGFloat = 1 / 1.414

    private var height: CGFloat { width / Self.ratio }

    /// Les mesures du plat sont des **fractions de sa largeur** et non des
    /// points : le même dessin sert à 208 pt dans un carrousel et à 300 pt sur
    /// l'écran de choix, et il doit se réduire entièrement — marges comprises —
    /// au lieu de garder des marges de 24 pt sur une vignette.
    ///
    /// ⚠️ **Et ses typographies ne suivent pas le Dynamic Type.** C'est la
    /// seule entorse de l'app à la règle « aucune taille de police fixe », et
    /// elle est délibérée : ce plat n'est pas de l'interface, c'est **l'image
    /// d'un objet imprimé**. Le titre d'une couverture ne grossit pas parce que
    /// son lecteur a agrandi le texte de son téléphone — et à AX3, il débordait
    /// du plat, ce qui donnait à voir une couverture ratée. Même parti pris que
    /// ``CoverStack`` et que les pastilles de co-voyageurs. L'interface autour,
    /// elle — l'en-tête, les onglets, les boutons —, suit le Dynamic Type comme
    /// partout ailleurs.
    private func unit(_ fraction: CGFloat) -> CGFloat { width * fraction }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug, style: .continuous)

        return content
            .frame(width: width, height: height)
            .background(background)
            .clipShape(shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .brandShadow(.soft)
    }

    // MARK: - Le fond

    @ViewBuilder
    private var background: some View {
        switch style?.treatment ?? .plain {
        case .photo:
            photoLayer
            // Le titre se pose **sur** la photo : sans ce voile, un ciel clair
            // avale les lettres blanches. Il descend du haut et remonte du bas,
            // là où le texte tombe, et laisse le milieu intact.
            LinearGradient(
                colors: [.black.opacity(0.45), .clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .framed, .plain, .kraft:
            tintColor
        }
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let url = photo?.url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    TripCoverPlaceholder(seed: photo?.id ?? cover.styleId)
                }
            }
        } else {
            TripCoverPlaceholder(seed: photo?.id ?? cover.styleId)
        }
    }

    private var tintColor: Color {
        switch style?.tint ?? .paper {
        case .paper: MemoBookColor.paper
        case .sand: MemoBookColor.beige
        case .forest: MemoBookColor.action
        case .slate: MemoBookColor.outline
        case .ink: MemoBookColor.ink
        }
    }

    /// L'encre du plat : claire sur les fonds sombres, sombre sur les clairs.
    private var inkColor: Color {
        switch style?.treatment ?? .plain {
        case .photo: MemoBookColor.paper
        case .framed, .kraft: MemoBookColor.ink
        case .plain:
            switch style?.tint ?? .paper {
            case .forest, .ink: MemoBookColor.paper
            case .paper, .sand, .slate: MemoBookColor.ink
            }
        }
    }

    // MARK: - Le contenu

    @ViewBuilder
    private var content: some View {
        switch face {
        case .front: frontContent
        case .back: backContent
        }
    }

    /// Le devant : le titre en haut, la signature en bas.
    private var frontContent: some View {
        VStack(spacing: 0) {
            titleBlock

            Spacer(minLength: 0)

            subtitleBlock
        }
        .padding(unit(0.09))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var titleBlock: some View {
        Text(cover.title)
            .font(titleFont)
            .foregroundStyle(inkColor)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) { titleBadge }
    }

    private var subtitleBlock: some View {
        Text(cover.subtitle)
            .font(.custom(BrandFonts.generalSansRegular, fixedSize: unit(0.055)))
            .foregroundStyle(inkColor)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomTrailing) { subtitleBadge }
    }

    /// Le titre du carnet. Manuscrit sur un kraft, composé partout ailleurs.
    private var titleFont: Font {
        if style?.treatment == .kraft {
            return .custom(BrandFonts.gloriaHallelujah, fixedSize: unit(0.13))
        }
        return .custom(BrandFonts.soraSemiBold, fixedSize: unit(0.155))
    }

    /// Le dos : la photo encadrée, le texte de quatrième, les chiffres, le logo.
    ///
    /// C'est l'ordre de la maquette, et il raconte quelque chose : on regarde,
    /// on lit, on compte, puis on voit d'où ça vient.
    private var backContent: some View {
        VStack(spacing: unit(0.05)) {
            if style?.treatment == .framed {
                photoLayer
                    .frame(height: unit(0.3))
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: unit(0.02)))
            }

            // **Une photo pleine page ne porte pas de texte de quatrième**, et
            // c'est ce que l'écran des textes annonce désormais en grisant le
            // plat (Hugo, 16/09/2026). Le dessin doit dire la même chose, sans
            // quoi l'explication contredirait ce qu'on a sous les yeux.
            if style?.treatment.carriesText(on: .back) ?? true {
                Text(cover.subtitle)
                    .font(.custom(BrandFonts.generalSansRegular, fixedSize: unit(0.045)))
                    .foregroundStyle(inkColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(unit(0.014))
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    // Le crayon du texte de dos, en haut à droite du texte
                    // (T90) — le devant pose le sien en bas de la signature.
                    .overlay(alignment: .topTrailing) { subtitleBadge }
            }

            Spacer(minLength: 0)

            if !stats.isEmpty {
                statsBlock
            }

            Image(brand: "LogoMemobookCreme")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: unit(0.07))
                .foregroundStyle(inkColor.opacity(0.7))
        }
        .padding(unit(0.09))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// « Mon voyage en quelques chiffres », et les trois ou quatre retenus.
    private var statsBlock: some View {
        VStack(spacing: unit(0.03)) {
            Text(BookCopy.Covers.Stats.heading)
                .font(.custom(BrandFonts.generalSansSemibold, fixedSize: unit(0.04)))
                .foregroundStyle(inkColor)

            HStack(alignment: .top, spacing: unit(0.03)) {
                ForEach(stats) { stat in
                    VStack(spacing: unit(0.012)) {
                        // « 2,3k » se coupait en deux lignes sur une colonne
                        // étroite (Clara, 17/09/2026) : un chiffre tient sur
                        // une ligne et rapetisse s'il le faut.
                        Text(stat.value)
                            .font(.custom(BrandFonts.soraSemiBold, fixedSize: unit(0.085)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(stat.label)
                            .font(.custom(BrandFonts.generalSansRegular, fixedSize: unit(0.035)))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(inkColor)
                    .frame(maxWidth: .infinity)
                }
            }
            .minimumScaleFactor(0.5)
        }
        .padding(unit(0.04))
        .background {
            RoundedRectangle(cornerRadius: unit(0.03))
                .strokeBorder(inkColor.opacity(0.4), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) { statsBadge }
    }
}

// MARK: - La pastille de sélection

/// Le rond coché qui coiffe le plat retenu, dans les deux carrousels.
///
/// Il déborde du coin haut-droit du plat, comme la maquette : posé dedans, il
/// serait passé pour un bouton de la couverture elle-même.
struct CoverSelectionBadge: View {
    var body: some View {
        Image(brand: "IconLucideCheck")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.s, height: MemoBookSpacing.s)
            .foregroundStyle(MemoBookColor.action)
            .frame(width: Self.side, height: Self.side)
            .background(MemoBookColor.surface, in: .circle)
            .overlay { Circle().strokeBorder(MemoBookColor.outline, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }

    /// 27 de dessin dans un rond de 45 sur la maquette ; le rond visible en fait
    /// 32, le reste est la marge du composant.
    private static let side: CGFloat = 32
}
