import MemoBookCore
import SwiftUI

/// La forme d'une bulle de conversation : un rectangle arrondi, et **une queue**
/// qui l'accroche à son côté.
///
/// La queue est ce qui fait la différence entre une bulle et une carte. Sans
/// elle, une suite de blocs alternés à gauche et à droite se lit comme une
/// liste ; avec elle, chaque bloc désigne celui qui l'a dit.
///
/// **La queue est comptée dans le cadre**, elle n'en sort pas. Un tracé qui
/// dépasse de son rectangle se fait rogner dès qu'on l'emploie en `clipShape`,
/// et fausse toutes les marges du contenu. ``BrandChatBubble`` réserve donc la
/// place correspondante avant de poser le texte — voir ``spur`` et ``drop``.
public struct BrandBubbleShape: Shape {
    /// Le côté auquel la bulle est accrochée.
    public enum Side: Sendable, Hashable {
        case leading
        case trailing
    }

    /// Ce que la queue prend en largeur, à l'intérieur du cadre.
    public static let spur: CGFloat = 7

    /// Ce qu'elle prend en hauteur : la pointe descend un peu sous la bulle,
    /// comme une goutte. La maquette la pose 2,74 pt plus bas que le bloc.
    public static let drop: CGFloat = 3

    private let side: Side
    private let cornerRadius: CGFloat

    public init(side: Side, cornerRadius: CGFloat = MemoBookSpacing.bubbleCornerRadius) {
        self.side = side
        self.cornerRadius = cornerRadius
    }

    public func path(in rect: CGRect) -> Path {
        let attached = attachedToLeading(in: rect)
        guard side == .trailing else { return attached }

        // Le miroir horizontal, écrit à la main plutôt que par `scaledBy` :
        // l'ordre de composition des transformations de Core Graphics se lit
        // mal, et ici on veut exactement `x' = (minX + maxX) - x`.
        return attached.applying(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0)
        )
    }

    /// Le tracé accroché à gauche. Celui de droite en est le reflet.
    private func attachedToLeading(in rect: CGRect) -> Path {
        // Le corps de la bulle : le cadre, moins la place de la queue.
        let body = CGRect(
            x: rect.minX + Self.spur,
            y: rect.minY,
            width: max(0, rect.width - Self.spur),
            height: max(0, rect.height - Self.drop)
        )
        let radius = min(cornerRadius, min(body.width, body.height) / 2)
        guard radius > 0 else { return Path(body) }

        var path = Path()

        // Le haut, puis le côté droit : trois coins arrondis sur quatre.
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Le bas, jusqu'à l'aplomb de la queue.
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))

        // La queue : deux courbes, une qui descend vers la pointe et une qui
        // remonte le long du bord. C'est ce retour concave qui la fait ressembler
        // à de l'encre plutôt qu'à un triangle collé.
        let tip = CGPoint(x: rect.minX, y: rect.maxY)
        path.addQuadCurve(
            to: tip,
            control: CGPoint(x: body.minX, y: body.maxY + Self.drop)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - radius),
            control: CGPoint(x: body.minX + Self.spur / 2, y: body.maxY - Self.drop)
        )

        // Le côté gauche, et le quatrième coin.
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(
            center: CGPoint(x: body.minX + radius, y: body.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

/// **La** bulle de conversation de l'app : le fond, la queue, les marges et la
/// largeur maximale, une fois pour toutes.
///
/// Quatre contenus la portent — le texte de MEMO, le texte du voyageur, un
/// vocal, une fiche de retranscription — et c'est précisément pour ça qu'elle
/// est un composant : quatre dessins écrits chacun de son côté divergeraient sur
/// le rayon avant la fin de l'écran.
///
/// ```swift
/// BrandChatBubble(author: .memo) {
///     Text(message).font(MemoBookFont.bubble)
/// }
/// ```
///
/// **La bulle épouse son texte, bornée par ce qui l'entoure.** Elle ne s'étire
/// pas sur toute la largeur — « Ça me convient » posé sur 300 pt ne se lit plus
/// comme une réplique — et elle ne peut pas non plus pousser hors de l'écran
/// les deux commandes qui l'accompagnent. Voir ``maximumContentWidth(for:)``.
///
/// **Elle ne décide pas de son alignement** : c'est la rangée qui la place, à
/// gauche ou à droite, avec ses commandes de l'autre côté.
public struct BrandChatBubble<Content: View>: View {
    private let author: ChatAuthor
    private let fill: Color?
    private let content: Content

    /// - Parameters:
    ///   - author: décide du côté, de la couleur et du sens de la queue. C'est
    ///     la seule question que la bulle pose.
    ///   - fill: pour un fond qui n'est pas celui de l'auteur — la fiche de
    ///     retranscription, par exemple, qui est blanche mais s'étend plus
    ///     large. `nil` prend le fond de l'auteur.
    public init(
        author: ChatAuthor,
        fill: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.author = author
        self.fill = fill
        self.content = content()
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private var side: BrandBubbleShape.Side {
        author.isTraveller ? .trailing : .leading
    }

    private var shape: BrandBubbleShape { BrandBubbleShape(side: side) }

    public var body: some View {
        content
            .frame(maxWidth: Self.maximumContentWidth(for: typeSize), alignment: .leading)
            .padding(.horizontal, MemoBookSpacing.snug)
            .padding(.vertical, MemoBookSpacing.xs)
            // La place de la queue, réservée du côté où elle s'accroche.
            .padding(author.isTraveller ? .trailing : .leading, BrandBubbleShape.spur)
            .padding(.bottom, BrandBubbleShape.drop)
            .background(shape.fill(fill ?? Self.fill(for: author)))
            .contentShape(shape)
    }

    public static func fill(for author: ChatAuthor) -> Color {
        author.isTraveller ? MemoBookColor.bubbleTraveller : MemoBookColor.bubbleMemo
    }

    /// La largeur maximale du **contenu** d'une bulle.
    ///
    /// Elle se déduit de ce qui l'entoure au lieu d'être une fraction ronde :
    /// la gouttière du fil, la colonne des deux commandes posées à côté de la
    /// bulle, et ce qui doit rester visible du fond de l'autre côté — c'est ce
    /// dernier reste qui dit « quelqu'un d'autre parle de ce côté-là ». Une
    /// fraction en dur ferait déborder les commandes hors de l'écran d'un
    /// iPhone SE.
    ///
    /// Aux tailles accessibles, on rend cette respiration au texte : à ce
    /// corps-là, la garder ne laisserait que trois mots par ligne.
    public static func maximumContentWidth(for typeSize: DynamicTypeSize) -> CGFloat {
        let gutters = MemoBookSpacing.snug * 2
        let actions = MemoBookSpacing.minimumTapTarget * 2
        let breathing = typeSize.isAccessibilitySize ? 0 : MemoBookSpacing.s
        return DeviceScreen.width - gutters - actions - breathing
    }
}

// MARK: - Aperçus

#Preview("Bulles") {
    VStack(spacing: MemoBookSpacing.s) {
        bubbleRow(.memo, "Comment ça se passe à Trastevere ?")
        bubbleRow(.traveller, "On a marché jusqu’au marché, et on a pris un café debout au comptoir.")
        bubbleRow(.memo, "Trastevere, je note. Qu’est-ce qui t’a marqué là-bas ?")
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}

#Preview("Bulles — Dynamic Type AX3") {
    VStack(spacing: MemoBookSpacing.s) {
        bubbleRow(.memo, "Comment ça se passe à Trastevere ?")
        bubbleRow(.traveller, "Ça me convient")
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// Une bulle posée du bon côté, pour les aperçus ci-dessus.
@MainActor
@ViewBuilder
private func bubbleRow(_ author: ChatAuthor, _ text: String) -> some View {
    HStack(spacing: 0) {
        if author.isTraveller { Spacer(minLength: MemoBookSpacing.s) }
        BrandChatBubble(author: author) {
            Text(text)
                .font(MemoBookFont.bubble)
                .foregroundStyle(MemoBookColor.ink)
        }
        if !author.isTraveller { Spacer(minLength: MemoBookSpacing.s) }
    }
}
