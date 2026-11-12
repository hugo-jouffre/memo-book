import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Une page de carnet **en train de se monter** : l'en-tête, puis le texte qui
/// s'écrit ligne par ligne, puis ce qu'on colle par-dessus.
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
struct BookCompositionPage: View, Animatable {
    /// De 0 à 1 : où en est l'arrivée des morceaux. C'est l'écran qui la fait
    /// monter, pas cette vue — elle doit pouvoir être figée à 1 pour une
    /// capture, et à 0 pour un aperçu.
    var progress: Double

    /// La page est dessinée **en miroir** (une sur deux, voir
    /// ``BookCompositionLoop``). Elle a besoin de le savoir : retourner une
    /// mise en page est un bon moyen de ne pas rejouer deux fois la même page,
    /// mais retourner le **geste d'écrire** en serait un mauvais — les lignes
    /// se traceraient de droite à gauche. Elles s'ancrent donc du côté qui est
    /// visuellement la marge de gauche.
    var isMirrored = false

    /// ⚠️ **C'est `Animatable` qui fait exister la cascade**, et rien d'autre
    /// (10/11/2026).
    ///
    /// Sans cette ligne, un `withAnimation { progress = 1 }` ne rejoue pas le
    /// `body` image par image : SwiftUI le calcule **une fois** à l'arrivée —
    /// tous les morceaux posés — puis interpole les transformations qui en
    /// sortent, chacune sur la durée entière. Les treize pièces voyagent alors
    /// *ensemble*, et la chorégraphie de `BookCompositionPiece` n'est jamais
    /// lue qu'à `progress == 1`. C'était le cas depuis le premier jour :
    /// l'écran montrait une page qui se remplit d'un bloc, pas une page qui
    /// s'écrit. La jumelle Android ne l'avait pas, parce que Compose anime une
    /// **valeur** (`Animatable`) et redessine à chaque image.
    ///
    /// En déclarant l'avancement comme donnée animable, SwiftUI interpole
    /// *lui*, et redemande le `body` à chaque pas : chaque pièce y relit sa
    /// seconde.
    /// `nonisolated` : la conformance traverse l'acteur principal, où `View`
    /// isole `body`, et Swift 6 refuse sans ça. Lire et écrire un `Double`
    /// stocké n'a besoin d'aucun acteur.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

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
                    let settled = BookCompositionPiece.settled(piece, at: progress)

                    piece.shape
                        .frame(
                            width: piece.frame.width * size.width,
                            height: piece.frame.height * size.height
                        )
                        // ⚠️ **L'arrivée se pose avant le placement.** Un
                        // `scaleEffect` appliqué après l'`offset` prend pour
                        // repère le cadre de *mise en page* — resté en haut à
                        // gauche, l'offset n'étant qu'un dessin — et met donc
                        // la pièce à l'échelle **avec son décalage** : une
                        // ligne à moitié écrite partait se dessiner au tiers
                        // de la page. Ici, elle pousse dans son propre cadre,
                        // et c'est le cadre fini qu'on va poser.
                        .modifier(
                            PieceEntry(
                                settled: settled,
                                arrival: piece.arrival,
                                travel: size,
                                isMirrored: isMirrored,
                                reduceMotion: reduceMotion
                            )
                        )
                        .rotationEffect(.degrees(piece.rotation * settled))
                        .offset(
                            x: piece.frame.minX * size.width,
                            y: piece.frame.minY * size.height
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

}

/// Comment un morceau entre en scène — et **ce qu'il est** y suffit.
///
/// Trois façons, et c'est la nature du morceau qui la choisit (Hugo,
/// 10/11/2026 : « plus logique, ligne par ligne »). Avant, les treize morceaux
/// volaient depuis le hors-cadre, en-tête et lignes de texte comprises : ça
/// bougeait beaucoup et ça ne racontait rien. Une page ne s'assemble pas en
/// vol — **ce qui est imprimé s'imprime, ce qui est écrit s'écrit, et seul ce
/// qu'on colle arrive de l'extérieur.**
private struct PieceEntry: ViewModifier {
    let settled: Double
    let arrival: BookCompositionPiece.Arrival
    let travel: CGSize
    let isMirrored: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        // Sous « Réduire les animations », rien ne voyage et rien ne s'écrit :
        // les morceaux se révèlent sur place, en fondu. La promesse de
        // l'écran — « ça travaille » — tient toujours, sans mouvement.
        if reduceMotion {
            content.opacity(min(settled * 2.2, 1))
        } else {
            // L'arrivée est adoucie pour **ce morceau-là**, et non par
            // l'animation globale : celle-ci est désormais linéaire, parce
            // qu'elle sert d'horloge à la chorégraphie (voir
            // ``BookCompositionPiece/timeline``). Un `easeOut` global écraserait
            // la fin de la minuterie et les derniers morceaux arriveraient
            // ensemble.
            let eased = 1 - pow(1 - settled, 3)

            switch arrival {
            case .written:
                content
                    // La ligne **s'écrit** : sa largeur pousse depuis la marge
                    // de gauche, dans le sens de la lecture. C'est le geste que
                    // la demande nomme, et il remplace un vol latéral qui
                    // donnait l'inverse — une ligne déjà écrite qu'on pose.
                    // Sur une page retournée, la marge de gauche est à
                    // droite : l'ancre suit, pour que le trait parte toujours
                    // du bord où commence une ligne.
                    .scaleEffect(x: max(eased, 0.001), y: 1, anchor: isMirrored ? .trailing : .leading)
                    // Franche tout de suite : une ligne de deux pixels de large
                    // en fondu ne se voit pas, et le trait doit **partir** net.
                    .opacity(min(settled * 8, 1))

            case .printed:
                content
                    // Imprimé : ça apparaît sur place, en se posant d'un
                    // cheveu. Rien ne traverse la page.
                    .scaleEffect(0.92 + 0.08 * eased)
                    .opacity(min(settled * 2.2, 1))

            case let .glued(entry):
                content
                    .offset(
                        x: entry.direction.dx * travel.width * (1 - eased),
                        y: entry.direction.dy * travel.height * (1 - eased)
                    )
                    // Le morceau grandit d'un cheveu en arrivant : il **se
                    // pose** au lieu de glisser jusqu'à sa place.
                    .scaleEffect(0.88 + 0.12 * eased)
                    // L'opacité se remplit plus vite que la course : la pièce
                    // est déjà franche à mi-chemin, ce qui évite l'impression
                    // de brouillard.
                    .opacity(min(settled * 2.2, 1))
            }
        }
    }
}

/// Un morceau de la page en construction : où il finit, comment il arrive, et
/// **à quelle seconde**.
///
/// Une **description** et non une vue : la liste se relit d'un coup d'œil, et
/// c'est elle qui porte la chorégraphie. Régler le rythme de l'écran, c'est
/// changer des nombres ici, pas du code ailleurs.
struct BookCompositionPiece: Identifiable, Sendable {
    /// Comment un morceau arrive. Trois façons seulement, et chacune dit ce
    /// que le morceau **est** — voir `PieceEntry`.
    enum Arrival: Sendable {
        /// Il s'écrit, de la marge vers la droite : les lignes de texte et les
        /// bandeaux d'en-tête.
        case written
        /// Il s'imprime sur place : les pictogrammes de la frise.
        case printed
        /// Il est collé, et arrive donc du hors-cadre, de travers.
        case glued(Entry)
    }

    /// D'où arrive un morceau collé. Six directions, et pas quatre : deux
    /// pièces qui entrent par le même bord au même instant se lisent comme un
    /// seul bloc.
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
    let arrival: Arrival
    /// L'inclinaison finale, en degrés. Zéro pour tout ce qui est imprimé ;
    /// seuls les éléments *collés* penchent.
    let rotation: Double
    /// À quelle **seconde** de la chorégraphie ce morceau part.
    ///
    /// En secondes et non plus en fraction de l'avancement (Hugo,
    /// 10/11/2026) : une page se monte à un rythme, et un rythme se règle en
    /// temps. Une fraction obligeait à recalculer treize nombres dès qu'on
    /// allongeait la cascade — c'est ce qui l'avait laissée trop rapide.
    let start: Double
    /// Combien de secondes il met à arriver. Courte pour une ligne de texte,
    /// qui doit être **finie avant que la suivante commence** : c'est là tout
    /// le « ligne par ligne ».
    let span: Double

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
    /// (3335:10208), **en secondes**.
    ///
    /// Les positions sont des **fractions** de la page de 252 × 357 de la
    /// maquette. L'ordre des départs raconte quelque chose : la page se monte
    /// comme on monte une page — le signet et l'en-tête d'abord, la frise, puis
    /// le texte qui s'écrit ligne par ligne, et les éléments collés en dernier,
    /// parce que c'est bien ainsi qu'on colle une photo dans un carnet.
    ///
    /// **Les secondes ne sont pas des réglages de confort.** Une ligne met
    /// 0,5 s à s'écrire et la suivante part 0,6 s après la précédente : c'est
    /// cet écart — un peu plus long que le geste — qui fait *lire* une ligne
    /// après l'autre au lieu d'un bloc qui se remplit.
    static let all: [BookCompositionPiece] = {
        var pieces: [BookCompositionPiece] = []
        var id = 0
        func add(
            _ kind: Kind,
            _ x: Double,
            _ y: Double,
            _ width: Double,
            _ height: Double,
            _ arrival: Arrival,
            at start: Double,
            over span: Double,
            rotation: Double = 0
        ) {
            pieces.append(
                BookCompositionPiece(
                    id: id,
                    kind: kind,
                    frame: CGRect(x: x, y: y, width: width, height: height),
                    arrival: arrival,
                    rotation: rotation,
                    start: start,
                    span: span
                )
            )
            id += 1
        }

        // 1. Le signet pend du bord haut : il descend à sa place. C'est un
        //    ruban, la seule pièce de l'en-tête qui arrive vraiment d'ailleurs.
        add(.bookmark, 0.06, 0.0, 0.12, 0.13, .glued(.top), at: 0.0, over: 0.8)

        // 2. Les deux bandeaux d'en-tête s'écrivent, l'un après l'autre.
        add(.bar, 0.28, 0.045, 0.31, 0.035, .written, at: 0.5, over: 0.6)
        add(.bar, 0.63, 0.045, 0.31, 0.035, .written, at: 0.9, over: 0.6)

        // 3. La frise de pictogrammes, un par un et dans le sens de la
        //    lecture : chacun s'imprime sur place, comme un tampon.
        for index in 0..<6 {
            add(
                .glyph,
                0.30 + Double(index) * 0.072,
                0.125,
                0.038,
                0.027,
                .printed,
                at: 1.7 + Double(index) * 0.18,
                over: 0.45
            )
        }

        // 4. Le texte. Huit lignes qui s'écrivent, du haut et dans l'ordre :
        //    c'est le cœur de la demande. La dernière est plus courte, comme
        //    une fin de paragraphe.
        let lineWidths: [Double] = [0.80, 0.80, 0.80, 0.80, 0.80, 0.80, 0.80, 0.52]
        for (index, width) in lineWidths.enumerated() {
            add(
                .bar,
                0.10,
                0.225 + Double(index) * 0.027,
                width,
                0.012,
                .written,
                at: 3.0 + Double(index) * 0.6,
                over: 0.5
            )
        }

        // 5. Ce qu'on colle par-dessus, en dernier et de travers — un geste
        //    plus ample, parce qu'on prend le temps de coller droit.
        add(.card, 0.36, 0.50, 0.56, 0.17, .glued(.trailing), at: 8.0, over: 1.0, rotation: -4)
        add(.photo, 0.06, 0.61, 0.39, 0.23, .glued(.bottomTrailing), at: 8.9, over: 1.0, rotation: 2)
        add(.stamp, 0.62, 0.72, 0.26, 0.18, .glued(.bottom), at: 9.8, over: 0.9)

        return pieces
    }()

    /// Combien de secondes la page entière met à se monter : la fin du dernier
    /// morceau.
    ///
    /// C'est elle qui fixe la durée de l'animation (``BookCompositionLoop``) et
    /// donc le plancher de l'attente. Allonger la cascade, c'est déplacer un
    /// `start` ici — rien d'autre ne suit à la main.
    static let timeline: Double = all.map { $0.start + $0.span }.max() ?? 1

    /// De 0 à 1 pour **ce morceau-là**, à cet avancement global.
    ///
    /// L'avancement sert d'**horloge** : multiplié par ``timeline``, il donne la
    /// seconde où l'on en est, et chaque pièce y lit sa part. C'est ce qui rend
    /// la cascade juste à `progress == 1` quoi qu'on change au-dessus — une
    /// pièce encore en vol à la fin ferait sauter le passage à l'aperçu.
    static func settled(_ piece: BookCompositionPiece, at progress: Double) -> Double {
        let clock = progress * timeline
        let local = (clock - piece.start) / max(piece.span, 0.001)
        return min(max(local, 0), 1)
    }
}

/// La page qui se monte, **puis la suivante, et ainsi de suite** tant que le
/// carnet se compose (Hugo, 08/10/2026).
///
/// Une composition dure des minutes ; la cascade, quelques secondes. Une page
/// montée puis immobile pendant tout le reste « semble cassée ». Une fois la
/// première page posée, celle-ci s'en va donc comme on tourne une page — vers
/// la gauche, en pâlissant —, et une page blanche se monte à sa place, en
/// miroir pour que deux pages de suite ne se ressemblent pas. C'est ce qui se
/// passe pour de vrai : le carnet se compose page après page.
///
/// La **première** page suit l'avancement du modèle (`firstPass`) : c'est lui
/// qui décide du plancher de l'attente — voir
/// ``BookPreviewModel/compositionProgress``. Les suivantes sont à la vue
/// seule : elles n'ont rien à dire au modèle, et s'arrêtent avec elle.
///
/// Sous « Réduire les animations », une seule page, posée : la boucle se tait,
/// et c'est la ligne d'état par-dessus (``BookCompositionStatus``) qui dit que
/// ça travaille.
struct BookCompositionLoop: View {
    /// L'avancement de la première page, tenu par le modèle.
    let firstPass: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le rang de la page en cours de montage. Zéro : la première.
    @State private var page = 0
    /// L'avancement des pages suivantes.
    @State private var progress: Double = 0

    /// Combien de temps une page posée reste sous les yeux avant de tourner.
    /// Un peu plus qu'avant : une page qu'on a vue s'écrire mérite d'être
    /// regardée finie.
    private static let hold: Duration = .seconds(2.2)
    /// Combien de temps une page met à se monter — la première comme les
    /// suivantes, pour garder le même rythme.
    ///
    /// **Ce n'est plus un réglage** : c'est la longueur de la chorégraphie
    /// elle-même (``BookCompositionPiece/timeline``), pour qu'une seconde
    /// déplacée là-bas soit une seconde de plus à l'écran. Elle est passée de
    /// 4,2 s à une dizaine (Hugo, 10/11/2026 : « plus longue, plus lente »).
    static let assembly: Double = BookCompositionPiece.timeline
    /// Le temps de tourner la page.
    private static let turn: Double = 0.6

    var body: some View {
        ZStack {
            BookCompositionPage(progress: page == 0 ? firstPass : progress, isMirrored: !page.isMultiple(of: 2))
                // Une page sur deux en miroir : ses morceaux arrivent de
                // l'autre côté, et la page suivante ne rejoue pas la même.
                .scaleEffect(x: page.isMultiple(of: 2) ? 1 : -1)
                .id(page)
                .transition(
                    .asymmetric(
                        insertion: .identity,
                        removal: .offset(x: -40).combined(with: .opacity).combined(with: .scale(scale: 0.94))
                    )
                )
        }
        .task(id: firstPass >= 1) {
            guard firstPass >= 1, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.hold)
                if Task.isCancelled { return }
                // La page blanche arrive à zéro, sans animation : c'est
                // l'ancienne qui s'en va, pas la nouvelle qui se fond.
                progress = 0
                withAnimation(.easeInOut(duration: Self.turn)) { page += 1 }
                try? await Task.sleep(for: .seconds(Self.turn * 0.5))
                if Task.isCancelled { return }
                // **Linéaire** : l'avancement est l'horloge de la
                // chorégraphie, et chaque morceau porte sa propre courbe. Un
                // `easeOut` ici écraserait la fin de la minuterie — les trois
                // pièces collées arriveraient ensemble.
                withAnimation(.linear(duration: Self.assembly)) { progress = 1 }
                try? await Task.sleep(for: .seconds(Self.assembly))
            }
        }
    }
}

/// Ce que fait la composition **en ce moment**, posé sur la page qui se monte
/// (Hugo, 08/10/2026 : « agrandir le texte qui explique que la création est
/// en cours, le mettre peut-être par-dessus l'animation, un loader »).
///
/// Une carte crème, un sablier qui tourne, la phrase de la phase en corps de
/// texte — et non plus en légende grise sous la page, où on ne la lisait pas.
/// La seconde ligne dit le temps que ça prend : sans elle, une page qui se
/// remonte pour la troisième fois se lirait encore comme une boucle cassée.
struct BookCompositionStatus: View {
    let phase: BookRenderPhase?
    let pendingMemories: Int

    var body: some View {
        HStack(alignment: .center, spacing: MemoBookSpacing.snug) {
            ProgressView()
                .controlSize(.regular)
                .tint(MemoBookColor.action)

            VStack(alignment: .leading, spacing: 2) {
                // La phrase change d'un coup : en fondu, l'ancienne et la
                // nouvelle se superposaient le temps du passage, illisibles
                // quand elles n'ont pas le même nombre de lignes.
                Text(BookCopy.Composition.phase(phase, pendingMemories: pendingMemories))
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                Text(BookCopy.Composition.patience)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.snug)
        .background(
            MemoBookColor.surface.opacity(0.94),
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
        }
        .brandShadow(.soft)
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
    }
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
                        // Le rythme de l'app, à la seconde près : l'aperçu ne
                        // sert à rien s'il joue plus vite que l'écran.
                        withAnimation(.linear(duration: BookCompositionLoop.assembly)) { progress = 1 }
                        try? await Task.sleep(for: .seconds(BookCompositionLoop.assembly + 1.2))
                    }
                }
        }
    }

    return Loop()
}
