import SwiftUI

/// Une action qu'un glissé vers la gauche découvre derrière une carte.
///
/// Un rond cerclé de sa couleur, une icône du jeu de marque, et ce que
/// VoiceOver en dit. La couleur dit le geste : le rouge sémantique pour ce qui
/// défait, le vert d'action pour le reste.
public struct BrandSwipeAction: Identifiable {
    public let id: String
    let icon: String
    let tint: Color
    let label: String
    let action: () -> Void

    /// - Parameters:
    ///   - icon: le nom d'une icône monochrome du catalogue (`IconCross`).
    ///   - tint: la couleur du rond et de l'icône.
    ///   - label: ce que VoiceOver lit — le rond ne porte pas de mot.
    public init(
        id: String? = nil,
        icon: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) {
        self.id = id ?? icon
        self.icon = icon
        self.tint = tint
        self.label = label
        self.action = action
    }
}

/// **Le** tiroir d'actions de MemoBook : une carte qu'on glisse vers la gauche
/// pour découvrir ses gestes — retirer un co-voyageur, supprimer un voyage,
/// le partager, le prévisualiser.
///
/// C'est le glissé des listes d'iOS, transposé aux cartes de l'app, qui ne
/// vivent pas dans une `List`. Trois choses le rendent honnête :
///
/// - **Vers la gauche seulement, et franchement horizontal** : l'écran défile
///   verticalement sous ce geste, et un glissé un peu de travers ne doit pas
///   ouvrir un tiroir au milieu d'une lecture.
/// - **Les actions n'existent que découvertes** : posées en permanence sous la
///   carte, elles resteraient tapables à travers elle.
/// - **Deux autres chemins vers les mêmes gestes** : l'appui long ouvre le menu
///   contextuel du système, et VoiceOver reçoit le rotor d'actions — un geste
///   continu n'existe pas pour ces deux-là.
///
/// La carte est **rognée sur sa propre place** : sans ça, elle glisserait
/// par-dessus la marge de l'écran et jusque sous le bord, le coin arrondi
/// coupé net. Rognée, elle disparaît sous la colonne comme une ligne de liste
/// sous le bord d'un tableau.
///
/// ```swift
/// BrandSwipeDrawer(actions: [
///     BrandSwipeAction(icon: "IconCross", tint: MemoBookColor.error, label: "Supprimer") { … },
/// ], cornerRadius: MemoBookSpacing.largeCornerRadius) {
///     FeaturedTripCard(…)
/// }
/// ```
public struct BrandSwipeDrawer<Content: View>: View {
    private let actions: [BrandSwipeAction]
    private let cornerRadius: CGFloat
    private let content: Content

    /// De combien la carte est décalée vers la gauche. `0` au repos, la largeur
    /// du tiroir quand il est ouvert.
    @State private var offset: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - actions: les gestes, de gauche à droite. Vide, la carte ne glisse pas.
    ///   - cornerRadius: le rayon de la carte, pour la rogner à sa forme.
    public init(
        actions: [BrandSwipeAction],
        cornerRadius: CGFloat = MemoBookSpacing.snug,
        @ViewBuilder content: () -> Content
    ) {
        self.actions = actions
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    /// Largeur du tiroir : une cible tactile par action, et leurs gouttières.
    private var drawerWidth: CGFloat {
        guard !actions.isEmpty else { return 0 }
        return MemoBookSpacing.minimumTapTarget * CGFloat(actions.count)
            + MemoBookSpacing.xs * CGFloat(actions.count + 1)
    }

    private var translation: CGFloat {
        (offset + drag).clampedToDrawer(drawerWidth)
    }

    private var isOpen: Bool { translation < -MemoBookSpacing.xs }

    public var body: some View {
        ZStack(alignment: .trailing) {
            if !actions.isEmpty { drawer }

            content
                .offset(x: translation)
                .gesture(swipe)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
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

    // MARK: Le tiroir

    private var drawer: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.action()
                } label: {
                    Image(brand: action.icon)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: MemoBookSpacing.sectionGap, height: MemoBookSpacing.sectionGap)
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
            }
        }
        .padding(.trailing, MemoBookSpacing.xs)
        // Elles n'existent que lorsqu'on les a fait apparaître : posées en
        // permanence sous la carte, elles resteraient tapables à travers elle.
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
        // VoiceOver passe par le rotor d'actions, pas par le tiroir.
        .accessibilityHidden(true)
    }

    // MARK: Le geste

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                guard !actions.isEmpty, abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                state = value.translation.width
            }
            .onEnded { value in
                guard !actions.isEmpty, abs(value.translation.width) > abs(value.translation.height) else {
                    return
                }
                let settled = (offset + value.translation.width).clampedToDrawer(drawerWidth)
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
                    offset = settled < -drawerWidth / 2 ? -drawerWidth : 0
                }
            }
    }

    private func close() {
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) { offset = 0 }
    }
}

private extension CGFloat {
    /// Le tiroir ne s'ouvre que vers la gauche, et pas au-delà de sa largeur.
    func clampedToDrawer(_ width: CGFloat) -> CGFloat {
        // `Swift.min` / `Swift.max` explicitement : dans une extension de
        // `CGFloat`, `min` et `max` désignent d'abord les bornes du type.
        Swift.min(0, Swift.max(-width, self))
    }
}

#Preview("Tiroir d’actions") {
    VStack(spacing: MemoBookSpacing.s) {
        BrandSwipeDrawer(
            actions: [
                BrandSwipeAction(icon: "IconCross", tint: MemoBookColor.error, label: "Supprimer") {},
                BrandSwipeAction(icon: "IconShareSystem", tint: MemoBookColor.action, label: "Partager") {},
                BrandSwipeAction(icon: "IconPrinter", tint: MemoBookColor.action, label: "Prévisualiser") {},
            ],
            cornerRadius: MemoBookSpacing.largeCornerRadius
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
