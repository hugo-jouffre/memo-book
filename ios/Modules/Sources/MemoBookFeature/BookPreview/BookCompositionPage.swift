import MemoBookDesign
import SwiftUI

/// Une page de carnet **en train de se monter** : ses morceaux arrivent chacun
/// de son côté et se posent à leur place.
///
/// C'est le cœur de l'écran « On compose ton Carnet », et son seul travail est
/// de faire passer une attente pour un travail. La composition réelle se fait
/// côté serveur (OpenAI structure le récit, APITemplate le met en page) et dure
/// quelques dizaines de secondes ; montrer une roue qui tourne pendant ce
/// temps-là serait exact et décourageant. Une page qui se remplit dit la même
/// chose et la rend supportable.
///
/// **Ce ne sont pas les vraies pièces du carnet** : ce sont les blocs de la
/// maquette du squelette — un signet, deux bandeaux, une frise de pictogrammes,
/// des lignes de texte, une photo, une carte et un rond. Ils ne prétendent pas
/// à la ressemblance ; ils prétendent au **rythme**.
struct BookCompositionPage: View {
    /// De 0 à 1 : où en est l'arrivée des morceaux. C'est l'écran qui la fait
    /// monter, pas cette vue — elle doit pouvoir être figée à 1 pour une
    /// capture, et à 0 pour un aperçu.
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Les positions sont **relatives** : la page se dessine à 252 × 357 sur
        // la maquette, mais elle occupe ce qu'on lui donne. Aucune coordonnée
        // en points ici — c'est ce qui la rend juste sur un iPhone SE comme sur
        // un Pro Max (R5).
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                ForEach(BookCompositionPiece.all) { piece in
                    piece.shape
                        .frame(
                            width: piece.frame.width * size.width,
                            height: piece.frame.height * size.height
                        )
                        .rotationEffect(.degrees(piece.rotation * settled(piece)))
                        .offset(
                            x: piece.frame.minX * size.width,
                            y: piece.frame.minY * size.height
                        )
                        .modifier(
                            PieceEntry(
                                settled: settled(piece),
                                from: piece.entry,
                                travel: size,
                                reduceMotion: reduceMotion
                            )
                        )
                }
            }
        }
        .background(MemoBookColor.paper)
        .clipShape(.rect(cornerRadius: MemoBookSpacing.pageCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.pageCornerRadius)
                .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
        }
        // Une page en construction n'a rien à dire à VoiceOver que le titre de
        // l'écran ne dise déjà — voir ``BookCopy/Composition/voiceOverStatus``.
        .accessibilityHidden(true)
    }

    /// De 0 à 1 pour **ce morceau-là** : sa part de l'avancement global.
    ///
    /// Chaque pièce occupe une fenêtre de l'avancement, décalée par son rang.
    /// C'est ce décalage qui fait la cascade : sans lui, les treize morceaux
    /// arriveraient ensemble et la page apparaîtrait d'un bloc.
    private func settled(_ piece: BookCompositionPiece) -> Double {
        let window = 1 - Self.lastDelay
        let local = (progress - piece.delay) / max(window, 0.001)
        return min(max(local, 0), 1)
    }

    /// Le départ du dernier morceau. Les fenêtres se calculent dessus pour que
    /// la page soit **exactement** finie à `progress == 1` : une pièce encore
    /// en vol à la fin ferait sauter le passage à l'aperçu.
    private static let lastDelay = BookCompositionPiece.all.map(\.delay).max() ?? 0
}

/// Comment un morceau entre en scène.
private struct PieceEntry: ViewModifier {
    let settled: Double
    let from: BookCompositionPiece.Entry
    let travel: CGSize
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        // Sous « Réduire les animations », les morceaux ne voyagent plus : ils
        // se révèlent sur place. La promesse de l'écran — « ça travaille » —
        // tient toujours, sans mouvement.
        let remaining = reduceMotion ? 0 : 1 - settled

        return content
            .offset(
                x: from.direction.dx * travel.width * remaining,
                y: from.direction.dy * travel.height * remaining
            )
            // Le morceau grandit d'un cheveu en arrivant : il **se pose** au
            // lieu de glisser jusqu'à sa place.
            .scaleEffect(reduceMotion ? 1 : 0.88 + 0.12 * settled)
            // L'opacité se remplit plus vite que la course : la pièce est déjà
            // franche à mi-chemin, ce qui évite l'impression de brouillard.
            .opacity(min(settled * 2.2, 1))
    }
}

/// Un morceau de la page en construction : où il finit, d'où il vient, et à
/// quel moment il part.
///
/// Une **description** et non une vue : la liste se relit d'un coup d'œil, et
/// c'est elle qui porte la chorégraphie. Régler le rythme de l'écran, c'est
/// changer des nombres ici, pas du code ailleurs.
struct BookCompositionPiece: Identifiable, Sendable {
    /// D'où arrive le morceau. Six directions, et pas quatre : deux pièces qui
    /// entrent par le même bord au même instant se lisent comme un seul bloc.
    enum Entry: Sendable {
        case top, bottom, leading, trailing, topLeading, bottomTrailing

        /// Le vecteur de départ, en **fractions de la page**. Au-delà de 1, le
        /// morceau part de hors-cadre — ce qui est le but.
        var direction: (dx: Double, dy: Double) {
            switch self {
            case .top: (0, -1.15)
            case .bottom: (0, 1.15)
            case .leading: (-1.15, 0)
            case .trailing: (1.15, 0)
            case .topLeading: (-0.9, -0.9)
            case .bottomTrailing: (0.9, 0.9)
            }
        }
    }

    /// Ce que le morceau est. Chaque cas porte son dessin, et il n'y en a que
    /// cinq : au-delà, ce ne serait plus un squelette mais une contrefaçon de
    /// la page.
    enum Kind: Sendable {
        /// Le signet qui pend du bord haut.
        case bookmark
        /// Un bandeau d'en-tête, ou une ligne de texte.
        case bar
        /// Un pictogramme de la frise météo.
        case glyph
        /// Une photo collée.
        case photo
        /// Une carte posée de travers, avec son bandeau de couleur.
        case card
        /// Le rond d'un tampon.
        case stamp
    }

    let id: Int
    let kind: Kind
    /// La place finale, en fractions de la page — origine en haut à gauche.
    let frame: CGRect
    let entry: Entry
    /// L'inclinaison finale, en degrés. Zéro pour tout ce qui est imprimé ;
    /// seuls les éléments *collés* penchent.
    let rotation: Double
    /// Quand ce morceau part, de 0 à 1 de l'avancement global.
    let delay: Double

    /// `@MainActor` : le dessin pose une ombre de la marque, et les extensions
    /// de `View` sont isolées sur l'acteur principal. La description, elle,
    /// reste `Sendable` — c'est une constante statique.
    @MainActor
    @ViewBuilder
    var shape: some View {
        switch kind {
        case .bookmark:
            Rectangle()
                .fill(MemoBookColor.ink.opacity(0.45))
                .clipShape(.rect(bottomLeadingRadius: 3, bottomTrailingRadius: 3))
        case .bar:
            Capsule().fill(MemoBookColor.ink.opacity(0.12))
        case .glyph:
            Circle().fill(MemoBookColor.ink.opacity(0.18))
        case .photo:
            Rectangle()
                .fill(MemoBookColor.ink.opacity(0.22))
                .clipShape(.rect(cornerRadius: 2))
        case .card:
            VStack(spacing: 0) {
                // Le bandeau vert d'une carte « Fun fact » du carnet — c'est le
                // seul endroit du squelette où une couleur apparaît, et c'est
                // ce qui fait qu'on la remarque.
                Rectangle()
                    .fill(MemoBookColor.valid.opacity(0.35))
                    .frame(maxHeight: .infinity)
                Rectangle()
                    .fill(MemoBookColor.ink.opacity(0.08))
                    .frame(maxHeight: .infinity)
            }
            .clipShape(.rect(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(MemoBookColor.ink.opacity(0.12), lineWidth: 0.5)
            }
            .background(MemoBookColor.surface)
            .brandShadow(.soft)
        case .stamp:
            Circle().fill(MemoBookColor.separator.opacity(0.55))
        }
    }

    /// La chorégraphie, relevée sur le nœud `Skeleton - Prévisualisation PDF`
    /// (3335:10208).
    ///
    /// Les positions sont des **fractions** de la page de 252 × 357 de la
    /// maquette. L'ordre des départs raconte quelque chose : la page se monte
    /// comme on monte une page — la structure d'abord (signet, bandeaux), le
    /// texte ensuite, et les éléments collés en dernier, parce que c'est bien
    /// ainsi qu'on colle une photo dans un carnet.
    static let all: [BookCompositionPiece] = {
        var pieces: [BookCompositionPiece] = []
        var id = 0
        func add(
            _ kind: Kind,
            _ x: Double,
            _ y: Double,
            _ width: Double,
            _ height: Double,
            from entry: Entry,
            delay: Double,
            rotation: Double = 0
        ) {
            pieces.append(
                BookCompositionPiece(
                    id: id,
                    kind: kind,
                    frame: CGRect(x: x, y: y, width: width, height: height),
                    entry: entry,
                    rotation: rotation,
                    delay: delay
                )
            )
            id += 1
        }

        // 1. La structure de l'en-tête.
        add(.bookmark, 0.06, 0.0, 0.12, 0.13, from: .top, delay: 0.0)
        add(.bar, 0.28, 0.045, 0.31, 0.035, from: .trailing, delay: 0.04)
        add(.bar, 0.63, 0.045, 0.31, 0.035, from: .trailing, delay: 0.07)

        // 2. La frise de pictogrammes, un par un et de la gauche : c'est une
        //    ligne, elle s'écrit dans le sens de la lecture.
        for index in 0..<6 {
            add(
                .glyph,
                0.30 + Double(index) * 0.072,
                0.125,
                0.038,
                0.027,
                from: .leading,
                delay: 0.10 + Double(index) * 0.018
            )
        }

        // 3. Le texte. Huit lignes, du haut, décalées : la page « s'écrit ».
        //    La dernière est plus courte, comme une fin de paragraphe.
        let lineWidths: [Double] = [0.80, 0.80, 0.80, 0.80, 0.80, 0.80, 0.80, 0.52]
        for (index, width) in lineWidths.enumerated() {
            add(
                .bar,
                0.10,
                0.225 + Double(index) * 0.027,
                width,
                0.012,
                from: index.isMultiple(of: 2) ? .leading : .trailing,
                delay: 0.24 + Double(index) * 0.022
            )
        }

        // 4. Ce qu'on colle par-dessus, en dernier et de travers.
        add(.card, 0.36, 0.50, 0.56, 0.17, from: .trailing, delay: 0.46, rotation: -4)
        add(.photo, 0.06, 0.61, 0.39, 0.23, from: .bottomTrailing, delay: 0.56, rotation: 2)
        add(.stamp, 0.62, 0.72, 0.26, 0.18, from: .bottom, delay: 0.66)

        return pieces
    }()
}

#Preview("Page en composition") {
    /// L'aperçu rejoue la cascade en boucle : c'est le seul moyen de régler un
    /// rythme sans relancer l'app entre deux essais.
    struct Loop: View {
        @State private var progress: Double = 0

        var body: some View {
            BookCompositionPage(progress: progress)
                .aspectRatio(252.0 / 357.0, contentMode: .fit)
                .padding(MemoBookSpacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MemoBookColor.background)
                .environment(\.colorScheme, .light)
                .task {
                    while !Task.isCancelled {
                        progress = 0
                        withAnimation(.easeOut(duration: 2.4)) { progress = 1 }
                        try? await Task.sleep(for: .seconds(3.4))
                    }
                }
        }
    }

    return Loop()
}
