import SwiftUI

/// Le bouton de l'app, repris du composant versionné du design system Figma
/// (frame « Button », node `1296:10750`).
///
/// Les quatre axes du composant Figma se retrouvent tels quels :
///
/// | Figma           | Ici                                      |
/// |-----------------|------------------------------------------|
/// | `Style`         | ``BrandButton/Style``                    |
/// | `Small`         | ``BrandButton/Size``                     |
/// | `Alternate`     | `alternate` — posé sur un fond sombre    |
/// | `Icon position` | `icon` + `iconPlacement`, ou titre `nil` |
///
/// ```swift
/// BrandButton("Découvre MemoBook", icon: Image(brand: "IconArrowRight"), fillsWidth: true) {
///     // …
/// }
/// ```
public struct BrandButton: View {
    /// Les quatre styles du design system, du plus au moins appuyé.
    public enum Style {
        /// Aplat vert. Une seule action primaire par écran.
        case primary
        /// Contour vert sur fond blanc.
        case secondary
        /// Ni fond ni contour, mais garde les marges d'un bouton.
        case tertiary
        /// Aplat crème sans contour : les actions posées **dans** une carte
        /// blanche, où un contour vert ferait concurrence au CTA de l'écran.
        case soft
        /// Aplat lime cerclé de vert. **La seule exception** à la règle qui
        /// réserve l'accent aux petites surfaces : c'est le bouton de
        /// l'abonnement, et il n'y en a qu'un par écran. Le lime dit « ce n'est
        /// pas l'action ordinaire de l'écran, c'est celle qui débloque » — le
        /// vert plein, lui, reste au CTA du parcours normal.
        case accent
        /// Texte seul, sans marges : à poser dans une phrase ou une barre.
        case link
    }

    public enum Size {
        case regular
        case small
    }

    public enum IconPlacement {
        case leading
        case trailing
    }

    private let title: String?
    private let icon: Image?
    private let iconPlacement: IconPlacement
    private let style: Style
    private let size: Size
    private let isRound: Bool
    private let alternate: Bool
    private let isLoading: Bool
    private let isSubdued: Bool
    private let fillsWidth: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: `nil` donne la variante « Icon only » du design system.
    ///   - icon: teintée par la couleur du bouton, quelles que soient les
    ///     couleurs du fichier source.
    ///   - isRound: la variante ronde, pour un bouton sans libellé. Le rayon
    ///     devient un demi-cercle et les marges s'égalisent.
    ///   - alternate: à activer quand le bouton est posé sur un fond sombre.
    ///   - isSubdued: pour un lien qui n'appelle à rien — « Besoin d'aide ? »
    ///     en bas d'un écran. Il prend alors la taille et le gris du texte
    ///     secondaire au lieu de la typographie des boutons. N'a de sens qu'avec
    ///     ``Style/link`` : partout ailleurs, un bouton qui n'attire pas l'œil
    ///     est un bouton raté.
    ///   - fillsWidth: pour les appels à l'action pleine largeur en bas d'écran.
    public init(
        _ title: String? = nil,
        icon: Image? = nil,
        iconPlacement: IconPlacement = .leading,
        style: Style = .primary,
        size: Size = .regular,
        isRound: Bool = false,
        alternate: Bool = false,
        isLoading: Bool = false,
        isSubdued: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.iconPlacement = iconPlacement
        self.style = style
        self.size = size
        self.isRound = isRound
        self.alternate = alternate
        self.isLoading = isLoading
        self.isSubdued = isSubdued
        self.fillsWidth = fillsWidth
        self.action = action
    }

    /// Hauteur de la ligne de texte : 1,5 × 16 pt dans le design system. Elle
    /// suit le Dynamic Type pour que le libellé ne soit jamais rogné.
    @ScaledMetric(relativeTo: .body) private var lineBox: CGFloat = 24

    /// La hauteur d'appel à l'action de l'app. Le libellé et ses marges ne
    /// donnent que 48 pt ; ce plancher porte le bouton à la hauteur commune à
    /// tous les CTA, y compris ceux des fournisseurs tiers, qui ne passent pas
    /// par ce composant. Il grandit avec le Dynamic Type comme le reste.
    @ScaledMetric(relativeTo: .body) private var controlHeight = MemoBookSpacing.controlHeight

    /// Les icônes du design system font 24 pt.
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 24

    /// Un bouton désactivé garde sa place et sa forme, mais passe au gris :
    /// c'est l'état « Continuer » tant que le formulaire est incomplet.
    @Environment(\.isEnabled) private var isEnabled

    public var body: some View {
        Button(action: action) {
            content
                .frame(minHeight: lineBox)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: minimumHeight)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(background)
                .overlay(border)
                .contentShape(.rect(cornerRadius: cornerRadius))
        }
        .buttonStyle(PressStyle())
        .disabled(isLoading)
        // Un bouton « small » ou « link » descend sous les 44 pt réglementaires.
        // On agrandit alors la zone tactile sans toucher au dessin.
        .frame(minWidth: MemoBookSpacing.minimumTapTarget, minHeight: MemoBookSpacing.minimumTapTarget)
        .accessibilityLabel(title ?? "")
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: gap) {
            if iconPlacement == .leading { leadingAccessory }
            if let title {
                Text(title)
                    .font(isSubdued ? MemoBookFont.label : MemoBookFont.button)
                    .lineLimit(fillsWidth ? nil : 1)
            }
            if iconPlacement == .trailing { leadingAccessory }
        }
        .foregroundStyle(foreground)
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(foreground)
                .frame(width: iconSide, height: iconSide)
        } else if let icon {
            icon
                .resizable()
                // Les icônes du design system sont dessinées dans une couleur
                // figée ; c'est le bouton qui décide de leur teinte.
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: iconSide, height: iconSide)
        }
    }

    // MARK: - Métriques

    private var isIconOnly: Bool { title == nil }

    /// Les styles qui posent un aplat plein. Désactivés, ils gardent leur pavé
    /// et passent au gris ; les autres n'ont qu'un texte à éteindre.
    private var isFilled: Bool { style == .primary || style == .accent }

    /// `RoundedRectangle` ramène tout seul un rayon trop grand à la moitié du
    /// plus petit côté : un carré devient un rond, sans changer de forme. Un
    /// grand nombre fini, pas `.infinity`, qui donnerait des NaN au tracé.
    private var cornerRadius: CGFloat {
        if isRound { return 9999 }
        return style == .link ? 0 : MemoBookSpacing.controlCornerRadius
    }

    private var gap: CGFloat { style == .link ? 8 : 12 }

    private var horizontalPadding: CGFloat {
        // Un bouton rond n'a qu'une marge, la même partout : c'est elle qui
        // fait le cercle plutôt qu'un ovale.
        if isRound { return verticalPadding }
        return switch (style, size, isIconOnly) {
        case (.link, _, _): 0
        case (_, .regular, true): 12
        case (_, .regular, false): 24
        case (_, .small, true): 8
        case (_, .small, false): 20
        }
    }

    /// Seuls les boutons pleine taille portent la hauteur des CTA. Un `small`
    /// est un bouton d'appoint, et un `link` n'est qu'un mot dans une phrase :
    /// leur imposer 56 pt les transformerait en blocs.
    private var minimumHeight: CGFloat? {
        switch (style, size) {
        case (.link, _), (_, .small): nil
        case (_, .regular): controlHeight
        }
    }

    private var verticalPadding: CGFloat {
        switch (style, size) {
        case (.link, _): 0
        case (_, .regular): 12
        case (_, .small): 8
        }
    }

    // MARK: - Couleurs
    //
    // Le design system nomme un blanc pur pour le texte des boutons pleins.
    // On lui préfère le blanc de la marque (`#FFFCF8`) : c'est celui de tous
    // les autres écrans, et l'écart est invisible à l'œil sur un aplat vert.

    private var foreground: Color {
        if isSubdued, isEnabled { return MemoBookColor.inkMuted }

        guard isEnabled else {
            return isFilled ? MemoBookColor.surface : MemoBookColor.disabled
        }
        return switch (style, alternate) {
        case (.primary, false): MemoBookColor.onAction
        case (.primary, true): MemoBookColor.ink
        case (.secondary, false): MemoBookColor.action
        case (.secondary, true): MemoBookColor.onAction
        case (.tertiary, false), (.link, false), (.soft, false): MemoBookColor.ink
        case (.tertiary, true), (.link, true), (.soft, true): MemoBookColor.onAction
        // Le lime est une couleur claire : c'est l'encre qui se pose dessus,
        // dans les deux cas. Un libellé blanc y tomberait à 1,1:1.
        // Le vert du contour, pas l'encre : sur un aplat lime, le noir chaud
        // se lit comme un texte posé là, le vert comme le bouton lui-même.
        case (.accent, _): MemoBookColor.action
        }
    }

    @ViewBuilder
    private var background: some View {
        if !isEnabled {
            shape.fill(isFilled ? MemoBookColor.disabled : Color.clear)
        } else {
            switch (style, alternate) {
            case (.primary, false):
                shape.fill(MemoBookColor.action)
            case (.primary, true):
                shape.fill(MemoBookColor.onAction)
            // Le contour secondaire est posé sur un aplat blanc sur fond clair,
            // et reste transparent en `alternate` pour laisser voir le fond.
            case (.secondary, false):
                shape.fill(MemoBookColor.surface)
            case (.soft, false):
                shape.fill(MemoBookColor.background)
            case (.soft, true):
                shape.fill(MemoBookColor.onAction.opacity(0.15))
            case (.accent, _):
                shape.fill(MemoBookColor.accent)
            case (.secondary, true), (.tertiary, _), (.link, _):
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var border: some View {
        if !isEnabled {
            EmptyView()
        } else {
            switch (style, alternate) {
            case (.primary, false), (.secondary, false), (.accent, _):
                shape.strokeBorder(MemoBookColor.action, lineWidth: 1)
            case (.primary, true), (.secondary, true):
                shape.strokeBorder(MemoBookColor.onAction, lineWidth: 1)
            case (.tertiary, _), (.link, _), (.soft, _):
                EmptyView()
            }
        }
    }

    private var shape: RoundedRectangle {
        .rect(cornerRadius: cornerRadius)
    }

    /// Retour tactile discret : le bouton s'éteint légèrement sous le doigt.
    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

#Preview("Boutons") {
    let arrow = Image(brand: "IconArrowRight")

    return ScrollView {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BrandButton("Découvre MemoBook", icon: arrow, fillsWidth: true) {}
            HStack {
                BrandButton("Primary", icon: arrow) {}
                BrandButton("Secondary", style: .secondary) {}
            }
            HStack {
                BrandButton("Tertiary", style: .tertiary) {}
                BrandButton("Link", icon: arrow, iconPlacement: .trailing, style: .link) {}
            }
            HStack {
                BrandButton("Small", size: .small) {}
                BrandButton(icon: arrow, size: .small) {}
                BrandButton(icon: arrow) {}
                BrandButton("Chargement", isLoading: true) {}
            }
            BrandButton(
                "Découvrir l’abonnement",
                icon: arrow,
                iconPlacement: .trailing,
                style: .accent,
                fillsWidth: true
            ) {}

            HStack {
                BrandButton("Soft", style: .soft) {}
                BrandButton(icon: arrow, style: .soft, isRound: true) {}
                BrandButton(icon: arrow, style: .soft, size: .small, isRound: true) {}
                BrandButton(icon: arrow, style: .secondary, isRound: true) {}
            }
            .padding(MemoBookSpacing.s)
            .background(MemoBookColor.surface, in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius))
        }
        .padding(MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
}

#Preview("Boutons — fond sombre") {
    let arrow = Image(brand: "IconArrowRight")

    return VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
        BrandButton("Primary", icon: arrow, alternate: true) {}
        BrandButton("Secondary", style: .secondary, alternate: true) {}
        BrandButton("Tertiary", style: .tertiary, alternate: true) {}
        BrandButton("Link", style: .link, alternate: true) {}
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.ink)
}
