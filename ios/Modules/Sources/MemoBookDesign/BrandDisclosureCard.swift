import SwiftUI

/// Une carte qui se déplie : un titre, un chevron, et un contenu qui ne se
/// montre en entier que si on le demande.
///
/// C'est le motif des pages de **texte long** — les chapitres des conditions
/// d'utilisation et de la politique de confidentialité. Repliée, la carte
/// laisse voir le début du texte, assez pour savoir de quoi parle le chapitre
/// et pas assez pour le lire ; dépliée, elle passe au bleu d'aplat de la marque
/// et montre tout. Le bleu dit « celle-ci est ouverte » d'un coup d'œil dans
/// une colonne de neuf cartes crème.
///
/// **Un seul contenu, qui se déroule** (01/10/2026). La carte posait deux
/// textes — un aperçu tronqué, puis le chapitre entier — et les échangeait en
/// fondu : à chaque ouverture, tout le texte disparaissait et revenait, y
/// compris les trois lignes qu'on venait de lire. Elle dessine maintenant le
/// contenu entier **dans les deux états** et n'en montre qu'une hauteur :
/// repliée, ses premières lignes, la dernière en fondu ; dépliée, tout. Ce qui
/// était lu reste en place, seul ce qui manquait arrive, à mesure que la carte
/// grandit.
///
/// ```swift
/// BrandDisclosureCard(
///     title: "Chapitre 1 — Présentation du service",
///     isExpanded: $isOpen,
///     lineFont: MemoBookFont.taglineRegular
/// ) {
///     ChapterBody(chapter)
/// }
/// ```
///
/// À ne pas confondre avec ``BrandToggleCard`` (un réglage et sa bascule) ni
/// avec ``BrandRow`` (une ligne qui mène ailleurs) : ici, on ne quitte pas
/// l'écran et rien ne se règle — on lit.
public struct BrandDisclosureCard<Content: View>: View {
    private let title: String
    @Binding private var isExpanded: Bool
    private let collapsedLineCount: Int
    private let lineFont: Font
    private let content: Content

    /// - Parameters:
    ///   - title: le titre de la carte — le libellé du bouton, pour VoiceOver.
    ///   - isExpanded: l'état. Il appartient à l'écran, qui peut en ouvrir
    ///     une par défaut ou les refermer toutes.
    ///   - collapsedLineCount: combien de lignes la carte repliée laisse voir.
    ///   - lineFont: la police de ces lignes — celle du texte courant du
    ///     contenu. La carte en mesure la hauteur, Dynamic Type compris.
    ///   - content: le contenu **entier**. La carte le coupe elle-même, et sait
    ///     donc s'il a une suite : un contenu qui tient dans ses lignes perd le
    ///     chevron et ne répond plus au toucher — un chevron qui ne déplie rien
    ///     apprend à ne plus toucher les autres.
    public init(
        title: String,
        isExpanded: Binding<Bool>,
        collapsedLineCount: Int = 3,
        lineFont: Font,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.collapsedLineCount = collapsedLineCount
        self.lineFont = lineFont
        self.content = content()
    }

    /// La hauteur du contenu entier, et celle de ses lignes repliées. `nil`
    /// avant la première mesure.
    @State private var contentHeight: CGFloat?
    @State private var linesHeight: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Y a-t-il une suite à montrer ? **Oui tant qu'on ne sait pas** : un
    /// chevron qui apparaît après coup se verrait plus qu'un chevron qui part.
    private var isExpandable: Bool {
        guard let contentHeight, let linesHeight else { return true }
        // Un demi-point d'écart, c'est l'arrondi d'une ligne, pas une ligne.
        return contentHeight > linesHeight + 0.5
    }

    /// Dépliée, **et** dépliable : une carte sans suite ne se déplie pas, même
    /// si l'écran l'avait ouverte par défaut.
    private var showsExpanded: Bool { isExpandable && isExpanded }

    /// La hauteur montrée du contenu. Rien avant la mesure des lignes : un
    /// premier rendu qui montrerait tout se refermerait sous les yeux.
    private var visibleHeight: CGFloat {
        guard let linesHeight else { return 0 }
        guard let contentHeight else { return linesHeight }
        return showsExpanded ? contentHeight : min(contentHeight, linesHeight)
    }

    /// Le fondu de la dernière ligne repliée : la hauteur d'une ligne.
    private var fadeHeight: CGFloat {
        (linesHeight ?? 0) / CGFloat(max(collapsedLineCount, 1))
    }

    /// Le chevron, à la taille de celui d'une ``BrandRow`` : c'est le même
    /// glyphe, et il doit faire la même taille d'un écran à l'autre.
    @ScaledMetric(relativeTo: .body) private var chevronSide: CGFloat = 22

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            header
            window
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
    }

    /// **Doux** : la carte s'allonge sans rebond, à l'allure d'une page qu'on
    /// tourne, et non d'un tiroir qui claque.
    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    /// Le contenu entier, vu par une fenêtre qui s'agrandit.
    ///
    /// Le contenu se pose toujours à sa hauteur naturelle ; c'est le cadre
    /// au-dessus de lui qui change, et le masque qui coupe. Animer un cadre de
    /// hauteur connue à une autre hauteur connue est ce que SwiftUI fait le
    /// mieux — passer de `lineLimit(3)` à `nil` ne s'anime pas, il saute.
    private var window: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // **Le texte suit sa carte, d'un bloc.** Sans ce groupe, chaque
            // ligne animait sa propre position : quand un chapitre s'ouvrait
            // pendant que celui du dessus se refermait, ses lignes arrivaient
            // avant la carte et passaient un instant sous son titre.
            .geometryGroup()
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            .background(alignment: .topLeading) { lineRuler }
            .frame(height: visibleHeight, alignment: .top)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                    // La dernière ligne repliée s'efface : elle dit que le
                    // texte continue, comme les points de suspension qu'elle
                    // remplace. Dépliée, plus rien ne s'efface.
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .overlay { Rectangle().opacity(showsExpanded || !isExpandable ? 1 : 0) }
                        .frame(height: fadeHeight)
                }
            }
            // Ce qui dépasse de la fenêtre est masqué, mais se toucherait
            // encore — un lien du texte caché répondrait par-dessus la carte
            // suivante. La forme de toucher s'arrête au bord visible.
            .contentShape(.rect)
    }

    /// Les lignes repliées, mesurées sur la police du texte : autant de lignes
    /// d'un seul caractère, dessinées cachées. C'est leur hauteur — interligne
    /// compris, à la taille de texte du moment — qui fait la fenêtre.
    private var lineRuler: some View {
        Text(Array(repeating: "X", count: max(collapsedLineCount, 1)).joined(separator: "\n"))
            .font(lineFont)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { linesHeight = $0 }
            .accessibilityHidden(true)
    }

    /// Le titre et le chevron, sur une seule cible : on ouvre en touchant
    /// **n'importe où** sur la ligne du titre, pas seulement le chevron.
    private var header: some View {
        Button {
            // **Une transaction pour toute la colonne**, et non une animation
            // posée sur la carte : celle-là n'animait qu'elle, et les cartes du
            // dessous sautaient d'un coup à leur place finale pendant qu'elle
            // grandissait encore — un trou, puis rien. L'écran qui referme la
            // carte ouverte en même temps passe aussi dans ce geste-ci.
            withAnimation(motion) { isExpanded.toggle() }
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
        // Le geste, que seule la carte connaît : c'est elle qui sait s'il y a
        // une suite.
        .accessibilityHint(isExpandable ? (showsExpanded ? "Replier" : "Déplier") : "")
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
            BrandDisclosureCard(
                title: "Chapitre 1 — Principes",
                isExpanded: $isFirstOpen,
                lineFont: MemoBookFont.taglineRegular
            ) {
                Text(text).font(MemoBookFont.taglineRegular)
            }
            BrandDisclosureCard(
                title: "Chapitre 2 — Règles",
                isExpanded: $isSecondOpen,
                lineFont: MemoBookFont.taglineRegular
            ) {
                Text(text).font(MemoBookFont.taglineRegular)
            }
            BrandDisclosureCard(
                title: "Chapitre 3 — Court",
                isExpanded: .constant(false),
                lineFont: MemoBookFont.taglineRegular
            ) {
                Text("Une seule ligne.").font(MemoBookFont.taglineRegular)
            }
        }
        .padding(MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
