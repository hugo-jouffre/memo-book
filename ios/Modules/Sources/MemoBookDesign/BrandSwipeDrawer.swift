import SwiftUI

/// Une action du tiroir d'une carte : son icône, sa couleur et ce qu'elle fait.
public struct BrandSwipeAction: Identifiable {
    public let id: String
    let icon: String
    let tint: Color
    let label: String
    let iconScale: CGFloat
    let action: () -> Void

    public init(
        id: String? = nil,
        icon: String,
        tint: Color,
        label: String,
        iconScale: CGFloat = 1,
        action: @escaping () -> Void
    ) {
        self.id = id ?? icon
        self.icon = icon
        self.tint = tint
        self.label = label
        self.iconScale = iconScale
        self.action = action
    }
}

/// Une carte qui glisse vers la gauche pour découvrir ses actions — celles
/// des voyages de l'accueil, des co-voyageurs de « Inviter un proche ».
///
/// **C'est une bande qui défile, et non un geste posé sur la carte** (Hugo,
/// 29/09/2026). Le tiroir était un `DragGesture` prioritaire sur la carte, et
/// il avait deux défauts qu'aucun réglage ne rattrapait :
///
/// - **il accrochait à l'ouverture et à la fermeture** : le glissé se
///   remettait à zéro d'un coup pendant que la carte, elle, s'animait vers sa
///   place, d'où un saut d'une frame à chaque geste ;
/// - **il volait le défilement vertical** : un doigt posé sur une carte qui
///   part vers le haut franchissait les douze points du geste, et la liste ne
///   bougeait plus. « Le scroll vertical est inactif si on commence depuis un
///   voyage. »
///
/// Une `ScrollView` horizontale, elle, sait faire les deux depuis toujours :
/// une bande dans une liste **se verrouille par sens** — vertical pour la
/// liste, horizontal pour la bande — et son arrêt sur une position est celui
/// du système, sans saut. Le bouton de la carte n'attrape plus le doigt qui
/// glisse : c'est la règle des boutons dans une bande qui défile.
///
/// Deux positions d'arrêt (`viewAligned`) : la carte en pleine largeur, ou le
/// tiroir. Les icônes arrivent en quinconce avec le glissé, comme avant.
/// L'espace de coordonnées de la bande, pour lire son défilement.
private let brandSwipeDrawerSpace = "brand-swipe-drawer"

public struct BrandSwipeDrawer<Content: View>: View {
    private let actions: [BrandSwipeAction]
    private let content: Content

    /// Ce qui est calé à gauche de la bande : la carte, ou son tiroir.
    private enum Slot: Hashable {
        case card
        case drawer
    }

    /// La position d'arrêt de la bande. `nil` tant qu'elle ne s'est pas posée.
    @State private var slot: Slot? = .card

    /// De combien la bande a défilé, en points, lue sur la bande elle-même :
    /// c'est ce qui fait arriver les icônes l'une après l'autre.
    @State private var scrolled: CGFloat = 0

    /// Ce qu'il y a entre la bande et les bords de l'écran, à gauche et à
    /// droite — la marge de l'écran, d'ordinaire. C'est jusque-là que la carte
    /// se dessine quand elle glisse. Voir ``band``.
    @State private var reach = HorizontalReach(
        leading: MemoBookSpacing.screenMargin,
        trailing: MemoBookSpacing.screenMargin
    )

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        actions: [BrandSwipeAction],
        @ViewBuilder content: () -> Content
    ) {
        self.actions = actions
        self.content = content()
    }

    private var drawerWidth: CGFloat {
        guard !actions.isEmpty else { return 0 }
        return MemoBookSpacing.minimumTapTarget * CGFloat(actions.count)
            + MemoBookSpacing.xs * CGFloat(actions.count + 1)
    }

    public var body: some View {
        Group {
            if actions.isEmpty {
                content
            } else {
                band
            }
        }
        .contextMenu {
            ForEach(actions) { action in
                Button(action.label, role: action.tint == MemoBookColor.error ? .destructive : nil) {
                    action.action()
                }
            }
        }
        .accessibilityActions {
            ForEach(actions) { action in
                Button(action.label, action: action.action)
            }
        }
    }

    // MARK: La bande

    private var band: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                content
                    // La carte prend exactement la largeur de la bande : c'est
                    // ce qui fait du tiroir la seule autre position.
                    .containerRelativeFrame(.horizontal)
                    .id(Slot.card)

                drawer
                    .frame(width: drawerWidth)
                    .id(Slot.drawer)
            }
            .scrollTargetLayout()
            // Pas d'élastique : ni avant la carte ni après le tiroir, il n'y a
            // rien à découvrir, et le rebond faisait trembler les icônes. Posé
            // sur le contenu, il remonte jusqu'à la bande — la plus proche.
            .brandScrollWithoutBounce()
            // Le défilement se lit sur la bande, dans son propre espace : la
            // position de son bord gauche dit de combien on a tiré.
            .background {
                GeometryReader { proxy in
                    let x = -proxy.frame(in: .named(brandSwipeDrawerSpace)).minX
                    Color.clear.onChange(of: x, initial: true) { _, value in
                        scrolled = max(0, value)
                    }
                }
            }
        }
        .coordinateSpace(name: brandSwipeDrawerSpace)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $slot)
        .scrollIndicators(.hidden)
        // ⚠️ **Rognée aux bords de l'écran, pas à ceux de la carte.** Une
        // `ScrollView` coupe tout ce qui sort de son cadre : le scotch des
        // cartes de l'accueil, qui chevauche leur bord haut, était tranché au
        // ras de la carte (Hugo, 30/09/2026) ; et une carte qu'on fait glisser
        // disparaissait à la marge, bien avant le bord de l'écran (01/10). La
        // découpe du système est levée, et un masque la remplace : de la marge
        // en haut et en bas, et **jusqu'aux bords de l'écran** à gauche et à
        // droite. Le tiroir fermé n'a pas besoin de la découpe pour rester
        // caché : il s'efface tant qu'on n'a pas tiré — voir ``drawer``.
        .scrollClipDisabled()
        .onGeometryChange(for: HorizontalReach.self) { proxy in
            let frame = proxy.frame(in: .global)
            return HorizontalReach(
                leading: max(0, frame.minX.rounded()),
                trailing: max(0, (DeviceScreen.width - frame.maxX).rounded())
            )
        } action: { reach = $0 }
        .mask {
            Rectangle()
                .padding(.vertical, -Self.verticalOverhang)
                .padding(.leading, -reach.leading)
                .padding(.trailing, -reach.trailing)
        }
        // La carte de l'accueil est un `Button` : dans une bande qui défile, le
        // système ne le déclenche pas au bout d'un glissé, sans rien à régler.
    }

    /// Ce qu'une carte peut faire dépasser au-dessus et au-dessous d'elle sans
    /// être rognée : son scotch, son ombre.
    private static var verticalOverhang: CGFloat { MemoBookSpacing.m }

    /// La place libre à gauche et à droite de la bande, jusqu'aux bords de
    /// l'écran. Lue sur l'axe horizontal seulement : faire défiler l'accueil
    /// ne la change pas, et ne réécrit donc rien.
    private struct HorizontalReach: Equatable {
        let leading: CGFloat
        let trailing: CGFloat
    }

    // MARK: Le tiroir

    /// Ce qui reste à tirer avant que le tiroir soit ouvert, de sa largeur à 0.
    private var remaining: CGFloat { max(0, drawerWidth - scrolled) }

    /// Le tiroir est là, au moins en partie : ses boutons se touchent.
    private var isOpen: Bool { scrolled > MemoBookSpacing.xs }

    private var drawer: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    close()
                    action.action()
                } label: {
                    Image(brand: action.icon)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(
                            width: MemoBookSpacing.sectionGap * action.iconScale,
                            height: MemoBookSpacing.sectionGap * action.iconScale
                        )
                        .foregroundStyle(action.tint)
                        .frame(
                            width: MemoBookSpacing.minimumTapTarget,
                            height: MemoBookSpacing.minimumTapTarget
                        )
                        .overlay { Circle().strokeBorder(action.tint, lineWidth: 1) }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.label)
                // **Elles arrivent avec le glissé, en quinconce** (Hugo,
                // 17/09/2026) : chaque icône suit la carte avec un retard qui
                // croît de la première à la dernière — elles glissent de la
                // droite l'une après l'autre et se posent avec le doigt, au
                // lieu d'être découvertes déjà en place. Le retard est un
                // rapport, pas une durée : pas d'animation à couper quand on
                // relâche à mi-chemin.
                .offset(x: reduceMotion ? 0 : remaining * (0.35 + 0.35 * CGFloat(index)))
                .opacity(1 - Double(min(1, remaining / max(drawerWidth, 1))) * 0.6)
            }
        }
        .padding(.horizontal, MemoBookSpacing.xs)
        .frame(maxHeight: .infinity)
        // **Fermé, il ne se voit pas** — même dans la marge de l'écran, où la
        // bande dessine désormais : la carte glisse jusqu'au bord, ses icônes
        // n'y attendent pas.
        .opacity(scrolled > 0.5 ? 1 : 0)
        // Elles n'existent que lorsqu'on les a fait apparaître : un tiroir
        // fermé n'a rien à offrir au doigt ni à VoiceOver, qui passe par le
        // rotor d'actions.
        .allowsHitTesting(isOpen)
        .accessibilityHidden(true)
    }

    private func close() {
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) { slot = .card }
    }
}

#Preview("Tiroir d’actions") {
    VStack(spacing: MemoBookSpacing.s) {
        BrandSwipeDrawer(
            actions: [
                BrandSwipeAction(icon: "IconCross", tint: MemoBookColor.error, label: "Supprimer") {},
                BrandSwipeAction(icon: "IconShareSystem", tint: MemoBookColor.action, label: "Partager") {},
                BrandSwipeAction(icon: "IconPrinter", tint: MemoBookColor.action, label: "Prévisualiser") {},
            ]
        ) {
            Text("Glisse-moi vers la gauche")
                .font(MemoBookFont.body)
                .padding(MemoBookSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MemoBookColor.surface,
                    in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
                )
        }
    }
    .padding(MemoBookSpacing.screenMargin)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
