import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les personnalisations du carnet : ce qui décide de sa mise en page.
///
/// On y arrive par la ligne « Style du carnet » des paramètres du voyage.
/// **C'est la V3 de la maquette** (`3595:23801` à `3595:24027`, Hugo,
/// 29/09/2026) : les deux pages du carnet et cinq pastilles de catégorie sont
/// **fixes en tête**, et c'est le réglage de la catégorie choisie qui défile
/// sous elles — ratio média, nombre de pages, décorations, typographies,
/// extras. Il y avait avant une liste de lignes ouvrant chacune sa feuille ;
/// on réglait sans voir, et on rouvrait une feuille par réglage.
///
/// **Le contenu passe derrière la tête et s'y estompe** (`3595:23846`) : un
/// voile crème sous les pastilles, qui fond sur les premiers points du
/// défilement. Ce qui est derrière n'existe plus ; ce qui approche s'éteint.
///
/// **Un réglage part dès qu'il est touché**, comme partout dans les réglages :
/// pas de « Valider ». Les feuilles en avaient un, qui ne faisait que fermer.
public struct BookCustomisationView: View {
    private let onIntent: (BookCustomisationIntent) -> Void

    @State private var model: BookCustomisationModel

    /// La catégorie ouverte. Le ratio média d'abord, comme la maquette.
    @State private var category: BookCustomisationCategory = .ratio

    /// La hauteur de la tête fixe, mesurée : c'est de là que le contenu part.
    @State private var headerHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le repère du haut du contenu, où l'on revient en changeant de catégorie.
    private static let topAnchor = "customisation-top"

    public init(
        model: BookCustomisationModel,
        onIntent: @escaping (BookCustomisationIntent) -> Void
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                    // La place de la tête, qui est posée par-dessus.
                    Color.clear
                        .frame(height: headerHeight)
                        .id(Self.topAnchor)
                        .accessibilityHidden(true)

                    panel
                        .id(category)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom))
                        )

                    if let message = model.errorMessage {
                        // Le constat, le conseil, et les deux gestes — comme sur
                        // les paramètres du voyage (Hugo, 15/09/2026).
                        ErrorBanner(
                            message: message,
                            advice: model.errorAdvice,
                            retry: { Task { await model.load() } },
                            help: { onIntent(.openHelp) }
                        )
                    }
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .padding(.bottom, MemoBookSpacing.l)
                .animation(.snappy(duration: 0.25), value: model.customisation == nil)
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: category)
            }
            .scrollIndicators(.hidden)
            // Changer de catégorie ramène en haut : un panneau court hériterait
            // sinon du défilement du panneau long qu'on vient de quitter, et
            // resterait à moitié derrière la tête.
            .onChange(of: category) { _, _ in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
            // La note des pointillés retirés paraît sous les trois assortiments,
            // plus bas que l'écran sur la plupart des iPhone : on la montre au
            // moment où l'on choisit, sinon le choix n'a l'air de rien.
            .onChange(of: model.rulesWithdrawnBy) { _, combo in
                guard combo != nil else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    proxy.scrollTo(BookFontsPanel.withdrawnNoticeAnchor, anchor: .bottom)
                }
            }
            // Même chose pour la note du verrou, dans Extras : en taille de texte
            // accessible, elle tombe sous l'écran. Déjà visible, elle descend
            // au plus au bas de l'écran — et en haut du panneau, où l'on est en
            // taille courante, rien ne bouge : il n'y a pas de quoi remonter.
            .onChange(of: model.showsRulesLockNotice) { _, isShown in
                guard isShown else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    proxy.scrollTo(BookExtrasPanel.lockedNoticeAnchor, anchor: .bottom)
                }
            }
            }

            header
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
        }
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
    }

    // MARK: - La tête fixe

    /// Le titre, les deux pages et les pastilles — et le voile qui éteint ce
    /// qui passe dessous.
    private var header: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BrandScreenHeader(title: BookCopy.Customisation.title) {
                headerActions
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)

            // L'aperçu de personnalisation, et non plus les pages du PDF
            // composé : c'est lui qui suit les réglages (Hugo, 02/10/2026).
            BookCustomisationPreviewView(url: model.previewURL)
                .frame(maxWidth: .infinity)

            categories
        }
        .padding(.bottom, MemoBookSpacing.xs)
        .background(MemoBookColor.background)
        // **L'estompe** : le contenu qui monte vers les pastilles s'éteint sur
        // ces seize points, et n'existe plus derrière. C'est le dégradé de la
        // maquette (`3595:23876`), ramené à ce qu'on en voit.
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [MemoBookColor.background, MemoBookColor.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: MemoBookSpacing.s)
            .offset(y: MemoBookSpacing.s)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// **Deux commandes en haut à droite** (Hugo, 06/10/2026, T197 et T224) :
    /// les couvertures, et l'aperçu PDF.
    ///
    /// Plus rien ne menait aux couvertures depuis cet écran (la V3 ne dessine
    /// pas leur ligne), et l'aperçu — ce que les réglages vont changer — était
    /// à deux écrans. Les deux prennent la forme des commandes d'en-tête de
    /// l'app : une icône cerclée de 2.75 rem, son nom dit à VoiceOver.
    /// L'aperçu porte **l'imprimante**, comme sur l'accueil du voyage et la
    /// conversation : la même destination, le même signe — et l'ouvrir lance
    /// la composition, comme partout.
    ///
    /// ⚠️ « Au plus une action » en tête d'écran, dit ``BrandScreenHeader`` :
    /// l'écart est demandé. Côte à côte et non empilées, parce que la tête est
    /// fixe — empilées, elles prendraient au réglage une ligne de hauteur ; le
    /// titre, lui, passe à la ligne (deux lignes sur un iPhone SE).
    private var headerActions: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            BrandHeaderAction(
                icon: "IconPictureFrame",
                label: BookCopy.Preview.configureCovers,
                action: { onIntent(.openCovers) }
            )
            BrandHeaderAction(
                icon: "IconPrinter",
                label: BookCopy.Settings.pdfPreview,
                action: { onIntent(.openBookPreview) }
            )
        }
    }

    /// Les cinq pastilles, en bande qui défile : « Décorations & stickers » ne
    /// tient pas sur une largeur d'iPhone avec les quatre autres, et la
    /// maquette la laisse sortir par le bord droit.
    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: MemoBookSpacing.xs) {
                ForEach(BookCustomisationCategory.allCases) { item in
                    BookCategoryChip(category: item, isSelected: item == category) {
                        category = item
                    }
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Catégories de personnalisation")
    }

    // MARK: - Le réglage ouvert

    @ViewBuilder
    private var panel: some View {
        switch category {
        case .ratio:
            BookRatioPanel(model: model)
        case .pages:
            BookPagesPanel(model: model)
        case .decorations:
            BookDecorationsPanel(model: model)
        case .fonts:
            BookFontsPanel(model: model)
        case .extras:
            BookExtrasPanel(model: model)
        }
    }
}

/// Ce que les personnalisations demandent à l'app d'ouvrir.
public enum BookCustomisationIntent: Sendable, Hashable {
    /// L'aperçu et la personnalisation des deux couvertures — la commande
    /// d'en-tête « Configurer mes couvertures » (T197). « Configurer », sur la
    /// première et la dernière page de l'aperçu PDF, y mène aussi.
    case openCovers
    /// L'aperçu PDF, qui lance la composition — la commande d'en-tête à
    /// l'imprimante (T224).
    case openBookPreview
    /// Le support, depuis le bandeau d'erreur : quand réessayer ne suffit pas.
    case openHelp
}

// MARK: - Les catégories

/// Les cinq pastilles de la tête, dans l'ordre de la maquette.
enum BookCustomisationCategory: String, CaseIterable, Identifiable {
    case ratio
    case pages
    case decorations
    case fonts
    case extras

    var id: String { rawValue }

    /// Le libellé, **au caractère près** (R8) : « Typos » ; « Nombre de
    /// pages » en entier depuis T214.
    var title: String {
        switch self {
        case .ratio: BookCopy.Customisation.categoryRatio
        case .pages: BookCopy.Customisation.categoryPages
        case .decorations: BookCopy.Customisation.categoryDecorations
        case .fonts: BookCopy.Customisation.categoryFonts
        case .extras: BookCopy.Customisation.categoryExtras
        }
    }

    /// Le pictogramme de la pastille, exporté du nœud (`3595:23807`) dans
    /// `assets/icons/brand-icons/Category *.svg` — cinq tracés d'encre, à
    /// teinter.
    var icon: String {
        switch self {
        case .ratio: "IconCategoryRatio"
        case .pages: "IconCategoryPages"
        case .decorations: "IconCategoryDecorations"
        case .fonts: "IconCategoryTypos"
        case .extras: "IconCategoryExtras"
        }
    }
}

/// Une pastille de catégorie : le pictogramme et le mot, en capsule — bleue
/// quand elle est choisie, papier sinon (`3595:23808`).
private struct BookCategoryChip: View {
    let category: BookCustomisationCategory
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var iconSide: CGFloat = MemoBookSpacing.snug

    var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.xs / 2) {
                Image(brand: category.icon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .accessibilityHidden(true)

                Text(category.title)
                    .font(MemoBookFont.overline)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(MemoBookColor.ink)
            .padding(MemoBookSpacing.snug)
            .background(isSelected ? MemoBookColor.outline : MemoBookColor.surface, in: .capsule)
            // La cible reste à 2.75 rem, la pastille dessinée plus basse (R7).
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Personnalisations du carnet") {
    NavigationStack {
        BookCustomisationView(model: BookCustomisationModel(tripId: "preview")) { _ in }
    }
}

#Preview("Personnalisations — AX3") {
    NavigationStack {
        BookCustomisationView(model: BookCustomisationModel(tripId: "preview")) { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
