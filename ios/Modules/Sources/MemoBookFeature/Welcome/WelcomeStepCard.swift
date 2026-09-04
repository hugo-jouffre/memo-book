import MemoBookDesign
import SwiftUI

/// Une des trois étapes de l'écran d'accueil : une carte blanche cerclée de
/// bleu, légèrement inclinée, avec sa pastille numérotée à cheval sur le bord
/// haut.
struct WelcomeStepCard: View {
    enum Icon {
        case mic, photo, book

        /// Le livre est la seule icône livrée sans fond : les deux autres
        /// portent leur aplat bleu dans le SVG lui-même.
        var needsBackplate: Bool { self == .book }

        /// Ces trois-là ne sont **pas** des icônes du système d'icônes de la
        /// marque (`Icon…`) : ce sont des illustrations dessinées pour ces
        /// cartes, avec leurs proportions propres et leur aplat bleu déjà dans
        /// le SVG. D'où le préfixe qui les tient à part.
        var assetName: String {
            switch self {
            case .mic: "WelcomeMic"
            case .photo: "WelcomePhoto"
            case .book: "WelcomeBook"
            }
        }

        /// Taille de dessin, dans le rapport du SVG d'origine.
        var size: CGSize {
            switch self {
            case .mic: CGSize(width: 23.18, height: 30.57)
            case .photo: CGSize(width: 32.91, height: 25.92)
            case .book: CGSize(width: 24.42, height: 23.35)
            }
        }
    }

    let number: Int
    let icon: Icon
    let title: String
    let detail: String

    /// Inclinaison en degrés. Les cartes alternent -1° / +1° pour l'effet
    /// « posé à la main » de la maquette.
    let tilt: Double

    /// Sous les tailles Dynamic Type accessibles, l'icône passe au-dessus du
    /// texte : garder trois colonnes ne laisserait plus rien au libellé.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var slot: CGFloat { 44 }

    var body: some View {
        cardBody
            .background(MemoBookColor.surface, in: shape)
            .overlay(shape.strokeBorder(MemoBookColor.outline, lineWidth: 1))
            .overlay(alignment: .topTrailing) { badge }
            .rotationEffect(.degrees(tilt))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Étape \(number) sur 3. \(title)")
            .accessibilityValue(detail)
    }

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    @ViewBuilder
    private var cardBody: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                iconView
                text
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 20)
        } else {
            HStack(spacing: 12) {
                iconView
                text
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 20)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(MemoBookFont.bodySemibold)
                .tracking(MemoBookFont.tracking(16))
            Text(detail)
                .font(MemoBookFont.caption)
                .tracking(MemoBookFont.tracking(12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(MemoBookColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconView: some View {
        Image(brand: icon.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: icon.size.width, height: icon.size.height)
            .frame(width: slot, height: slot)
            .background {
                if icon.needsBackplate {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(MemoBookColor.outline.opacity(0.3))
                }
            }
            // L'icône reste droite pendant que la carte penche.
            .rotationEffect(.degrees(-tilt))
    }

    private var badge: some View {
        Text("\(number)")
            // Taille figée, contrairement au reste de l'écran : la pastille est
            // une décoration de 26 pt qui chevauche le bord de la carte, et le
            // numéro est déjà dit par le libellé d'accessibilité. La laisser
            // grandir avec le Dynamic Type ne rendrait rien de plus lisible et
            // ferait déborder le chiffre de son rond.
            .font(.custom(BrandFonts.soraSemiBold, fixedSize: 16))
            .tracking(MemoBookFont.tracking(16))
            .foregroundStyle(MemoBookColor.surface)
            .frame(width: 26, height: 26)
            .background(MemoBookColor.outline, in: .circle)
            .offset(x: -24.77, y: -13)
            .accessibilityHidden(true)
    }
}
