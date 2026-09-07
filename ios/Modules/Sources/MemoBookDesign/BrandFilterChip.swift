import SwiftUI

/// Une pastille de filtre : ce sur quoi on trie la liste d'en dessous.
///
/// Elle ne porte **pas** l'action : elle sert d'étiquette à un `Menu`, qui
/// apporte la liste déroulante, les coches, le clavier et VoiceOver sans qu'on
/// ait à les redessiner.
///
/// ```swift
/// Menu {
///     Picker("Pays", selection: $country) { … }
/// } label: {
///     BrandFilterChip("Pays", icon: Image(systemName: "flag"), isActive: country != nil)
/// }
/// ```
///
/// Deux états, et deux seulement : au repos elle est un contour sur le crème,
/// active elle prend le vert de la marque. Un filtre posé doit se voir de loin,
/// sinon on cherche pourquoi la liste est courte.
public struct BrandFilterChip: View {
    private let title: String
    private let icon: Image?
    private let isActive: Bool

    public init(_ title: String, icon: Image? = nil, isActive: Bool = false) {
        self.title = title
        self.icon = icon
        self.isActive = isActive
    }

    @ScaledMetric(relativeTo: .subheadline) private var iconSide: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var chevronSide: CGFloat = 10

    private var shape: Capsule { Capsule() }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon {
                icon
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
            }

            Text(title)
                .font(MemoBookFont.label)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: chevronSide, weight: .semibold))
        }
        .foregroundStyle(isActive ? MemoBookColor.onAction : MemoBookColor.ink)
        .padding(.horizontal, MemoBookSpacing.s - 2)
        .padding(.vertical, MemoBookSpacing.xs + 2)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .background(isActive ? MemoBookColor.action : MemoBookColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(
                isActive ? MemoBookColor.action : MemoBookColor.separator,
                lineWidth: 1
            )
        }
        .contentShape(shape)
    }
}

#Preview("Filtres") {
    HStack(spacing: MemoBookSpacing.xs) {
        BrandFilterChip("Pays", icon: Image(systemName: "flag"))
        BrandFilterChip("Étapes", icon: Image(systemName: "bag"), isActive: true)
        BrandFilterChip("Transports", icon: Image(systemName: "arrow.triangle.turn.up.right.diagonal"))
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
