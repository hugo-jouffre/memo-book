import SwiftUI

/// Une carte qui annonce **ce qui n'est pas encore là** : son contenu à demi
/// effacé, et une pastille « À venir » à cheval sur son coin.
///
/// C'est le parti pris de la carte « Bientôt disponible » de la feuille
/// « Nouveau carnet », devenu un motif (Hugo, 08/10/2026 : les connecteurs du
/// profil et le Tricount des réglages du voyage « en “À venir”, un peu fade
/// out, pour montrer que ce n'est pas encore disponible ») :
///
/// - **La carte pâlit d'un bloc**, à 45 % comme celle de « Nouveau carnet » :
///   assez pour qu'on ne la confonde pas avec une carte qui marche, pas assez
///   pour qu'on cesse de lire ce qu'elle annonce — une pastille posée sur un
///   texte illisible n'expliquerait rien.
/// - **La pastille reste franche**, posée par-dessus le voile : c'est la
///   seule chose de la carte qu'on doit lire à coup sûr.
/// - **Elle ne répond pas au doigt**, et VoiceOver ne la présente pas comme
///   un bouton : c'est une annonce, pas une action. Un geste qui n'ouvrirait
///   rien se lirait comme une panne.
///
/// Les marques d'un tiers s'effacent avec le reste, sans teinte : une marque
/// repeinte n'est plus la marque.
public struct BrandComingSoonBadge: View {
    private let label: String

    public init(_ label: String = BrandComingSoonBadge.defaultLabel) {
        self.label = label
    }

    /// « À venir ».
    public static let defaultLabel = "À venir"

    public var body: some View {
        Text(label)
            .font(MemoBookFont.overline)
            // À l'encre pleine sur le blanc : la pastille ne pâlit pas avec la
            // carte.
            .foregroundStyle(MemoBookColor.ink)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, MemoBookSpacing.xs / 2)
            .background(MemoBookColor.surface, in: .capsule)
            .overlay { Capsule().strokeBorder(MemoBookColor.separator, lineWidth: 1) }
            .fixedSize()
            .accessibilityHidden(true)
    }
}

extension View {
    /// Pose le traitement « À venir » sur une carte — voir
    /// ``BrandComingSoonBadge``.
    ///
    /// - Parameters:
    ///   - isComingSoon: faux, la carte reste telle quelle. Le jour où la
    ///     fonctionnalité arrive, c'est ce booléen qui bascule.
    ///   - label: le libellé de la pastille, et ce que VoiceOver ajoute.
    public func brandComingSoon(
        _ isComingSoon: Bool = true,
        label: String = BrandComingSoonBadge.defaultLabel
    ) -> some View {
        modifier(ComingSoonModifier(isComingSoon: isComingSoon, label: label))
    }
}

private struct ComingSoonModifier: ViewModifier {
    let isComingSoon: Bool
    let label: String

    /// Le voile de la carte : celui de « Bientôt disponible ».
    static let contentOpacity = 0.45

    func body(content: Content) -> some View {
        if isComingSoon {
            content
                .opacity(Self.contentOpacity)
                // Sur le coin haut droit, à cheval sur le filet : dans la
                // carte, elle se serait lue comme une ligne de plus.
                .overlay(alignment: .topTrailing) {
                    BrandComingSoonBadge(label)
                        .padding(.trailing, MemoBookSpacing.snug)
                        .offset(y: -MemoBookSpacing.xs)
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityRemoveTraits(.isButton)
                .accessibilityValue(label)
        } else {
            content
        }
    }
}

#Preview("À venir") {
    VStack(spacing: MemoBookSpacing.l) {
        HStack(spacing: MemoBookSpacing.s) {
            RoundedRectangle(cornerRadius: 8)
                .fill(MemoBookColor.action)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Strava")
                    .font(MemoBookFont.bodySemibold)
                Text("MemoBook pourra lire tes sorties.")
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(MemoBookSpacing.s)
        .background(MemoBookColor.surface, in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius))
        .brandComingSoon()
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
