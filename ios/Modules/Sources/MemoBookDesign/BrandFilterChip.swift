import SwiftUI

/// Une pastille de filtre : ce sur quoi on trie la liste d'en dessous.
///
/// Elle ne porte **pas** l'action, dans aucune de ses deux formes : c'est
/// l'étiquette d'un `Menu` ou le label d'un `Button`, et c'est lui qui apporte
/// le geste, le clavier et VoiceOver sans qu'on ait à les redessiner.
///
/// ```swift
/// // Une liste déroulante — les filtres d'un voyage.
/// Menu {
///     Picker("Pays", selection: $country) { … }
/// } label: {
///     BrandFilterChip("Pays", icon: Image(systemName: "flag"), isActive: country != nil)
/// }
///
/// // Un choix parmi une barre — les catégories de la galerie.
/// Button { category = item.id } label: {
///     BrandFilterChip(item.name, icon: item.icon, kind: .toggle, isActive: …)
/// }
/// ```
///
/// Deux états, et deux seulement : au repos elle est un contour sur le crème,
/// active elle prend le vert de la marque. Un filtre posé doit se voir de loin,
/// sinon on cherche pourquoi la liste est courte.
public struct BrandFilterChip: View {
    /// Ce que la pastille annonce, et donc si elle porte un chevron.
    public enum Kind {
        /// Elle ouvre une liste déroulante. Le chevron dit « il y a un choix
        /// dessous ».
        case menu
        /// Elle **est** le choix : une pastille parmi une barre, qu'on allume
        /// et qu'on éteint. Rien ne se déroule, donc pas de chevron.
        case toggle
    }

    private let title: String
    private let icon: Image?
    private let kind: Kind
    private let isActive: Bool

    public init(
        _ title: String,
        icon: Image? = nil,
        kind: Kind = .menu,
        isActive: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.kind = kind
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

            if kind == .menu {
                Image(systemName: "chevron.down")
                    .font(.system(size: chevronSide, weight: .semibold))
            }
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
        // ⚠️ **Sans ce groupe, l'aplat vert traîne derrière son libellé.**
        //
        // Une pastille change de largeur en même temps que d'état : « Étapes »
        // devient « Etape n°1 », et la liste déroulante qui se referme anime
        // les deux. Le texte se pose à sa nouvelle largeur tout de suite ; la
        // capsule du fond, elle, est un calque distinct, et la sienne
        // s'interpole — on voit alors une pastille verte **à moitié**, l'aplat
        // s'arrêtant au milieu du mot.
        //
        // Le défaut ne se voyait que sur le filtre « Étapes » du voyage, et
        // c'est la même cause : c'est lui dont le libellé s'allonge le plus.
        // « Pays » → « Italie » gagne trois lettres, « Transports » → « Avion »
        // en perd cinq — l'aplat déborde alors au lieu de manquer, ce qui ne se
        // remarque pas.
        //
        // `geometryGroup()` fait résoudre la géométrie du fond et celle du
        // contenu **ensemble** : la capsule et le texte grandissent du même
        // pas.
        .geometryGroup()
        // Une durée à nous plutôt que celle, variable, de la liste qui se
        // referme : deux pastilles voisines doivent s'allumer de la même façon,
        // qu'on ait choisi dans un menu ou tapé dans une barre.
        .animation(.snappy(duration: 0.22), value: isActive)
        .animation(.snappy(duration: 0.22), value: title)
    }
}

#Preview("Filtres") {
    VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
        HStack(spacing: MemoBookSpacing.xs) {
            BrandFilterChip("Pays", icon: Image(systemName: "flag"))
            BrandFilterChip("Etape n°1", icon: Image(systemName: "bag"), isActive: true)
            BrandFilterChip("Transports", icon: LucideIcon.image("train-front"))
        }

        HStack(spacing: MemoBookSpacing.xs) {
            BrandFilterChip("Tout", kind: .toggle, isActive: true)
            BrandFilterChip("Tour du monde", icon: LucideIcon.image("globe"), kind: .toggle)
            BrandFilterChip("Randonnée", icon: LucideIcon.image("footprints"), kind: .toggle)
        }
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
