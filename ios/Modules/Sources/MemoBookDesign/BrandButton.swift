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
    private let alternate: Bool
    private let isLoading: Bool
    private let fillsWidth: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: `nil` donne la variante « Icon only » du design system.
    ///   - icon: teintée par la couleur du bouton, quelles que soient les
    ///     couleurs du fichier source.
    ///   - alternate: à activer quand le bouton est posé sur un fond sombre.
    ///   - fillsWidth: pour les appels à l'action pleine largeur en bas d'écran.
    public init(
        _ title: String? = nil,
        icon: Image? = nil,
        iconPlacement: IconPlacement = .leading,
        style: Style = .primary,
        size: Size = .regular,
        alternate: Bool = false,
        isLoading: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.iconPlacement = iconPlacement
        self.style = style
        self.size = size
        self.alternate = alternate
        self.isLoading = isLoading
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
                    .font(MemoBookFont.button)
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

    private var cornerRadius: CGFloat { style == .link ? 0 : 16 }

    private var gap: CGFloat { style == .link ? 8 : 12 }

    private var horizontalPadding: CGFloat {
        switch (style, size, isIconOnly) {
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
        guard isEnabled else {
            return style == .primary ? MemoBookColor.surface : MemoBookColor.disabled
        }
        return switch (style, alternate) {
        case (.primary, false): MemoBookColor.onAction
        case (.primary, true): MemoBookColor.ink
        case (.secondary, false): MemoBookColor.action
        case (.secondary, true): MemoBookColor.onAction
        case (.tertiary, false), (.link, false): MemoBookColor.ink
        case (.tertiary, true), (.link, true): MemoBookColor.onAction
        }
    }

    @ViewBuilder
    private var background: some View {
        if !isEnabled {
            shape.fill(style == .primary ? MemoBookColor.disabled : Color.clear)
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
            case (.primary, false), (.secondary, false):
                shape.strokeBorder(MemoBookColor.action, lineWidth: 1)
            case (.primary, true), (.secondary, true):
                shape.strokeBorder(MemoBookColor.onAction, lineWidth: 1)
            case (.tertiary, _), (.link, _):
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
