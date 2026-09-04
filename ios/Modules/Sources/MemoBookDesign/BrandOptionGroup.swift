import SwiftUI

/// Un choix unique parmi plusieurs, présenté en lignes encadrées : le motif des
/// feuilles de sélection de MemoBook — un moyen de paiement aujourd'hui, un
/// style de carnet ou une typographie demain.
///
/// À ne pas confondre avec ``BrandRowGroup`` : celui-ci **range** des actions et
/// les sépare d'un filet, celui-là **fait choisir** et encadre chaque option.
/// Deux motifs, deux dessins, deux composants.
///
/// ```swift
/// BrandOptionGroup {
///     ForEach(cards) { card in
///         BrandOptionRow(card.label, subtitle: card.maskedNumber, isSelected: card.id == selection) {
///             selection = card.id
///         }
///     }
/// }
/// ```
public struct BrandOptionGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        VStack(spacing: MemoBookSpacing.xs) {
            content
        }
        .padding(MemoBookSpacing.xs)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
    }
}

/// Une option d'un ``BrandOptionGroup``.
public struct BrandOptionRow: View {
    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 22

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(MemoBookFont.body)
                            .foregroundStyle(MemoBookColor.inkMuted)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                mark
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.s - 2)
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .background(isSelected ? MemoBookColor.outline.opacity(0.35) : Color.clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? MemoBookColor.outline : MemoBookColor.hairline,
                    lineWidth: 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Le rond de sélection. Le bleu de la marque et non le vert d'action :
    /// c'est le dessin de la maquette — voir « À trancher » de la fiche écran,
    /// `Tokens.swift` réservant plutôt le vert à la sélection.
    private var mark: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? MemoBookColor.blueText : MemoBookColor.separator, lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(MemoBookColor.blueText)
                    .padding(5)
            }
        }
        .frame(width: markSide, height: markSide)
        .accessibilityHidden(true)
    }
}

#Preview("Options") {
    VStack {
        BrandOptionGroup {
            BrandOptionRow("Carte business", subtitle: "XXXX XXXX XXXX 3246", isSelected: false) {}
            BrandOptionRow("Carte perso", subtitle: "XXXX XXXX XXXX 1820", isSelected: true) {}
        }
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.surface)
    .environment(\.colorScheme, .light)
}
