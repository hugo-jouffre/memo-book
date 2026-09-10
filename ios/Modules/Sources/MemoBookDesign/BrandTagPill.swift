import SwiftUI

/// La pastille de MemoBook : un mot ou deux, dans une capsule, posé à côté de
/// ce qu'il qualifie.
///
/// C'est **la** pastille de l'app. Elle en portait trois dessins écrits chacun
/// de son côté — l'état d'un voyage, le compteur d'une section, le solde
/// d'étapes de l'accueil — qui divergeaient déjà sur le rayon et la graisse.
///
/// Quatre tons, et quatre seulement :
///
/// | Ton | Dessin | Ce qu'il dit |
/// |---|---|---|
/// | ``Tone/accent`` | aplat lime | un décompte, un cadeau — ce qu'on gagne |
/// | ``Tone/outlined`` | contour vert | un état — ce que le voyage fait en ce moment |
/// | ``Tone/info`` | contour bleu | une précision — ce qu'il y a à savoir |
/// | ``Tone/accentOutlined`` | lime cerclé de vert | un état qu'on veut voir de loin |
///
/// > Le rayon reste celui d'une capsule pour **tous** les tons, y compris
/// > ``Tone/accentOutlined``, que la maquette des modales d'abonnement dessine
/// > à 6. Un quatrième rayon rouvrirait exactement le problème que ce composant
/// > a été écrit pour fermer. Signalé à Clara (T40).
/// >
/// > ``Tone/accentOutlined`` applique la règle du lime (``MemoBookColor/accent``,
/// > D13) : aplat lime, encre et filet verts.
public struct BrandTagPill: View {
    public enum Tone {
        /// Lime plein. L'accent du scheme : petites surfaces uniquement, ce qui
        /// est exactement la taille d'une pastille.
        case accent
        /// Contour vert sur blanc.
        case outlined
        /// Contour bleu sur blanc.
        case info
        /// Lime plein **et** cerclé de vert, texte vert : la pastille qui doit
        /// s'attraper de loin — « ABONNÉE », « VOIR UN APERÇU DE TON CARNET ».
        case accentOutlined
    }

    private let title: String
    private let tone: Tone
    private let isUppercased: Bool

    /// - Parameter isUppercased: les **états** se crient en capitales
    ///   (« EN COURS ») ; les décomptes et les soldes, non.
    public init(_ title: String, tone: Tone = .accent, isUppercased: Bool = false) {
        self.title = title
        self.tone = tone
        self.isUppercased = isUppercased
    }

    private var shape: Capsule { Capsule() }

    /// Aux tailles de texte accessibles, une pastille cesse d'imposer sa
    /// largeur.
    ///
    /// ``fixedSize()`` est là pour qu'une pastille courte ne se fasse pas
    /// écraser dans une rangée. Mais « VOIR UN APERÇU DE TON CARNET → » double
    /// de largeur en AX3 et sortait alors de l'écran, que rien ne pouvait plus
    /// rattraper. Passé cette taille, on la laisse donc se replier sur deux
    /// lignes — la règle des écrans relus en AX3 prime sur le confort de mise
    /// en rangée, qui n'a plus cours à ces tailles-là.
    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        Text(isUppercased ? title.uppercased() : title)
            .font(MemoBookFont.overline)
            .tracking(isUppercased ? MemoBookFont.tracking(12) : 0)
            .foregroundStyle(foreground)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, 4)
            .background(background, in: shape)
            .overlay {
                if let border {
                    shape.strokeBorder(border, lineWidth: 1)
                }
            }
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
    }

    private var foreground: Color {
        switch tone {
        case .accent: MemoBookColor.ink
        case .outlined, .accentOutlined: MemoBookColor.action
        case .info: MemoBookColor.blueText
        }
    }

    private var background: Color {
        switch tone {
        case .accent, .accentOutlined: MemoBookColor.accent
        case .outlined, .info: MemoBookColor.surface
        }
    }

    private var border: Color? {
        switch tone {
        case .accent: nil
        case .outlined, .accentOutlined: MemoBookColor.action
        case .info: MemoBookColor.blueText
        }
    }
}

/// L'avancement d'un carnet : ce qui est rempli, et ce qui reste.
///
/// Un filet et non une jauge épaisse : c'est une information de coin d'œil,
/// posée sous une carte, pas le sujet de l'écran.
public struct BrandProgressBar: View {
    private let fraction: Double
    private let label: String?

    /// - Parameters:
    ///   - fraction: de 0 à 1. Bornée ici aussi, au cas où.
    ///   - label: ce que la barre veut dire, en toutes lettres. **VoiceOver ne
    ///     lit que lui** : une barre sans mots ne s'annonce pas.
    public init(fraction: Double, label: String? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        self.label = label
    }

    private static let height: CGFloat = 6

    public var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            if let label {
                Text(label)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(MemoBookColor.hairline)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(MemoBookColor.action)
                            .frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: Self.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Avancement du carnet")
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

extension View {
    /// Le contour en pointillés des blocs « il n'y a rien ici, mais il y aura
    /// quelque chose ».
    ///
    /// Le pointillé dit exactement ça, et c'est pour ça qu'il ne sert qu'à ça :
    /// un cadre qui n'est pas encore rempli. Un trait plein en ferait une carte
    /// vide, ce qui est une autre idée.
    public func brandDashedCard(
        color: Color = MemoBookColor.separator,
        cornerRadius: CGFloat = MemoBookSpacing.largeCornerRadius
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        return overlay {
            shape.strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .contentShape(shape)
    }
}

#Preview("Pastilles et jauge") {
    VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
        HStack(spacing: MemoBookSpacing.xs) {
            BrandTagPill("3 étapes offertes")
            BrandTagPill("×1")
            BrandTagPill("En cours", tone: .outlined, isUppercased: true)
            BrandTagPill("Bientôt", tone: .info)
            BrandTagPill("Abonnée", tone: .accentOutlined, isUppercased: true)
        }

        BrandProgressBar(fraction: 0.025, label: "5 souvenirs et 2/80 pages")

        Text("Tes voyages passés s’afficheront ici")
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(MemoBookSpacing.l)
            .brandDashedCard()
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
