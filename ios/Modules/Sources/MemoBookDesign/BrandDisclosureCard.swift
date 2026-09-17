import SwiftUI

/// Une carte qui se déplie : un titre, un chevron, et un contenu qui ne se
/// montre en entier que si on le demande.
///
/// C'est le motif des pages de **texte long** — les chapitres des conditions
/// d'utilisation, demain la politique de confidentialité. Repliée, la carte
/// laisse voir le début du texte, assez pour savoir de quoi parle le chapitre
/// et pas assez pour le lire ; dépliée, elle passe au bleu d'aplat de la marque
/// et montre tout. Le bleu dit « celle-ci est ouverte » d'un coup d'œil dans
/// une colonne de neuf cartes crème.
///
/// ```swift
/// BrandDisclosureCard(
///     title: "Chapitre 1 — Présentation du service",
///     isExpanded: $isOpen
/// ) {
///     Text(chapter.preview).lineLimit(3)
/// } expanded: {
///     ChapterBody(chapter)
/// }
/// ```
///
/// À ne pas confondre avec ``BrandToggleCard`` (un réglage et sa bascule) ni
/// avec ``BrandRow`` (une ligne qui mène ailleurs) : ici, on ne quitte pas
/// l'écran et rien ne se règle — on lit.
public struct BrandDisclosureCard<Collapsed: View, Expanded: View>: View {
    private let title: String
    private let isExpandable: Bool
    @Binding private var isExpanded: Bool
    private let collapsed: Collapsed
    private let expanded: Expanded

    /// - Parameters:
    ///   - title: le titre de la carte — le libellé du bouton, pour VoiceOver.
    ///   - isExpandable: y a-t-il une suite à montrer ? **Faux quand le
    ///     contenu replié est déjà tout le contenu** : la carte perd alors son
    ///     chevron et ne répond plus au toucher — un chevron qui ne déplie
    ///     rien apprend à ne plus toucher les autres. C'est à l'appelant de
    ///     le savoir, en mesurant la troncature de ce qu'il a tronqué.
    ///   - isExpanded: l'état. Il appartient à l'écran, qui peut en ouvrir
    ///     une par défaut ou les refermer toutes.
    ///   - collapsed: ce qu'on voit repliée. C'est à l'appelant de tronquer
    ///     (`lineLimit`) : la carte ne sait pas ce qu'elle porte.
    ///   - expanded: ce qu'on voit dépliée.
    public init(
        title: String,
        isExpandable: Bool = true,
        isExpanded: Binding<Bool>,
        @ViewBuilder collapsed: () -> Collapsed,
        @ViewBuilder expanded: () -> Expanded
    ) {
        self.title = title
        self.isExpandable = isExpandable
        _isExpanded = isExpanded
        self.collapsed = collapsed()
        self.expanded = expanded()
    }

    /// Dépliée, **et** dépliable : une carte sans suite ne se déplie pas, même
    /// si l'écran l'avait ouverte par défaut.
    private var showsExpanded: Bool { isExpandable && isExpanded }

    /// Le chevron, à la taille de celui d'une ``BrandRow`` : c'est le même
    /// glyphe, et il doit faire la même taille d'un écran à l'autre.
    @ScaledMetric(relativeTo: .body) private var chevronSide: CGFloat = 22

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            header

            // Les deux contenus ne cohabitent jamais : le texte replié **est**
            // le début du texte déplié, et les faire se fondre l'un dans
            // l'autre donnerait deux fois la même première ligne.
            if showsExpanded {
                expanded
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                collapsed
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MemoBookSpacing.s)
        .background(showsExpanded ? MemoBookColor.outline : MemoBookColor.surface, in: shape)
        // Repliée, la carte est crème sur crème : c'est le filet qui la
        // détache du fond. Dépliée, l'aplat suffit — un filet bleu sur du bleu
        // ne se verrait pas, et un filet encre ferait un cadre.
        .overlay {
            shape.strokeBorder(MemoBookColor.hairline, lineWidth: showsExpanded ? 0 : 1)
        }
        .animation(.snappy(duration: 0.28), value: showsExpanded)
    }

    /// Le titre et le chevron, sur une seule cible : on ouvre en touchant
    /// **n'importe où** sur la ligne du titre, pas seulement le chevron.
    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
                Text(title)
                    .font(MemoBookFont.cardTitle)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isExpandable { chevron }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Pas `disabled` : le style éteindrait le titre, et un chapitre qui
        // tient en trois lignes n'est pas un chapitre en moins. Le toucher ne
        // passe simplement pas, et VoiceOver ne voit plus un bouton.
        .allowsHitTesting(isExpandable)
        .accessibilityRemoveTraits(isExpandable ? [] : .isButton)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpandable ? (showsExpanded ? "Dépliée" : "Repliée") : "")
    }

    /// Le chevron du jeu de marque, tourné : il pointe vers le bas quand la
    /// carte est repliée (« il y a la suite en dessous ») et vers le haut
    /// quand elle est dépliée.
    ///
    /// Comme dans ``BrandRow``, c'est la boîte de 24 qu'on dimensionne, pas le
    /// trait : le glyphe n'en occupe que le tiers.
    private var chevron: some View {
        Image(brand: "IconChevron")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: chevronSide, height: chevronSide)
            .foregroundStyle(showsExpanded ? MemoBookColor.ink : MemoBookColor.inkMuted)
            .rotationEffect(.degrees(showsExpanded ? -90 : 90))
            // En haut de la ligne, en face de la **première** ligne du titre :
            // un titre qui s'enroule sur deux lignes ne doit pas emmener le
            // chevron au milieu. Sa boîte de 22 fait à peu près la hauteur
            // d'une ligne de Sora 16, rien à rattraper.
            .accessibilityHidden(true)
    }
}

#Preview("Carte dépliable") {
    @Previewable @State var isFirstOpen = true
    @Previewable @State var isSecondOpen = false

    let text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."

    return ScrollView {
        VStack(spacing: MemoBookSpacing.s) {
            BrandDisclosureCard(title: "Chapitre 1 — Principes", isExpanded: $isFirstOpen) {
                Text(text).font(MemoBookFont.taglineRegular).lineLimit(3)
            } expanded: {
                Text(text).font(MemoBookFont.taglineRegular)
            }
            BrandDisclosureCard(title: "Chapitre 2 — Règles", isExpanded: $isSecondOpen) {
                Text(text).font(MemoBookFont.taglineRegular).lineLimit(3)
            } expanded: {
                Text(text).font(MemoBookFont.taglineRegular)
            }
        }
        .padding(MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
