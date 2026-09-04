import SwiftUI

/// Le M de MemoBook, tel qu'il est dessiné dans `Animated Cutout.svg` : un
/// unique trait à bouts ronds, incliné, qui monte, boucle et redescend.
///
/// Le SVG est **recopié courbe par courbe** plutôt qu'importé comme image :
/// c'est ce qui permet de le faire s'écrire au lancement avec `.trim(to:)`.
/// Une image vectorielle ne sait pas se tracer, elle sait seulement s'afficher.
///
/// Le tracé se recadre tout seul dans la place qu'on lui donne, épaisseur de
/// trait comprise — un `.stroke` déborde de la moitié de son épaisseur de
/// chaque côté, et ce débord est compté ici. Voir ``BrandMark/aspectRatio``
/// pour lui donner sa forme, et ``BrandMark/lineWidth(fitting:)`` pour
/// l'épaisseur à la bonne échelle.
public struct BrandMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let source = Self.designBounds
        guard source.width > 0, source.height > 0 else { return Path() }

        let scale = min(rect.width / source.width, rect.height / source.height)
        let drawn = CGSize(width: source.width * scale, height: source.height * scale)

        let transform = CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(
                CGAffineTransform(
                    translationX: rect.minX + (rect.width - drawn.width) / 2,
                    y: rect.minY + (rect.height - drawn.height) / 2
                )
            )

        return Self.designPath().applying(transform)
    }

    /// Rapport largeur / hauteur du signe, débord du trait compris. À poser en
    /// `.aspectRatio(BrandMark.aspectRatio, contentMode: .fit)`.
    public static var aspectRatio: CGFloat {
        designBounds.width / designBounds.height
    }

    /// Hauteur du signe pour une largeur donnée.
    ///
    /// À utiliser dès qu'on lui pose une `.frame(width:)` : la vue se recadre
    /// sur la place qu'on lui **propose**, et une proposition sans hauteur la
    /// laisse s'écraser. On donne donc toujours les deux.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }

    /// Épaisseur du trait une fois le signe recadré dans `size`. Le rapport
    /// trait / hauteur du dessin d'origine est conservé : le M garde sa
    /// graisse à toutes les tailles.
    public static func lineWidth(fitting size: CGSize) -> CGFloat {
        let source = designBounds
        guard source.width > 0, source.height > 0 else { return 0 }
        return designStrokeWidth * min(size.width / source.width, size.height / source.height)
    }

    // MARK: - Le tracé d'origine

    /// `stroke-width` du SVG, dans les coordonnées du SVG.
    private static let designStrokeWidth: CGFloat = 164.949

    /// `transform="translate(-263.854 557.01) rotate(-5.54015)"` du SVG. La
    /// rotation s'applique avant la translation, comme en SVG où le
    /// transform le plus à droite touche la géométrie en premier.
    private static let designTransform = CGAffineTransform(rotationAngle: -5.54015 * .pi / 180)
        .concatenating(CGAffineTransform(translationX: -263.854, y: 557.01))

    /// Boîte du tracé, élargie de la demi-épaisseur du trait de chaque côté.
    /// C'est elle, et pas la boîte du tracé nu, qui définit le cadrage : sans
    /// ça les bouts ronds seraient rognés.
    private static let designBounds: CGRect = designPath()
        .boundingRect
        .insetBy(dx: -designStrokeWidth / 2, dy: -designStrokeWidth / 2)

    /// Le `d` du SVG, courbe par courbe. Reconstruit à chaque appel plutôt que
    /// gardé dans une constante globale : treize courbes coûtent moins qu'un
    /// contournement de l'isolation de Swift 6, `Path` n'étant pas `Sendable`.
    private static func designPath() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 27.8559, y: 1250.68))

        for curve in curves {
            path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2)
        }

        return path.applying(designTransform)
    }

    private typealias Curve = (control1: CGPoint, control2: CGPoint, end: CGPoint)

    private static let curves: [Curve] = [
        (CGPoint(x: -11.988, y: 985.861), CGPoint(x: -21.4138, y: 670.389), CGPoint(x: 83.9949, y: 429.145)),
        (CGPoint(x: 189.404, y: 187.901), CGPoint(x: 323.854, y: -12.0481), CGPoint(x: 553.526, y: 0.951089)),
        (CGPoint(x: 713.14, y: 9.98504), CGPoint(x: 795.395, y: 193.301), CGPoint(x: 814.959, y: 381.853)),
        (CGPoint(x: 817.825, y: 409.471), CGPoint(x: 819.837, y: 442.459), CGPoint(x: 820.461, y: 476.937)),
        (CGPoint(x: 821.707, y: 545.777), CGPoint(x: 817.418, y: 620.558), CGPoint(x: 803.333, y: 670.389)),
        (CGPoint(x: 782.195, y: 745.176), CGPoint(x: 729.613, y: 923.846), CGPoint(x: 612.61, y: 910.847)),
        (CGPoint(x: 495.608, y: 897.849), CGPoint(x: 514.798, y: 699.982), CGPoint(x: 542.278, y: 618.6)),
        (CGPoint(x: 561.06, y: 562.975), CGPoint(x: 590.781, y: 502.855), CGPoint(x: 625.3, y: 444.913)),
        (CGPoint(x: 641.283, y: 418.083), CGPoint(x: 658.294, y: 391.721), CGPoint(x: 675.725, y: 366.487)),
        (CGPoint(x: 826.491, y: 148.226), CGPoint(x: 1012.33, y: 17.8264), CGPoint(x: 1180.64, y: 0.951176)),
        (CGPoint(x: 1348.94, y: -15.9241), CGPoint(x: 1380.5, y: 195.557), CGPoint(x: 1375.24, y: 332.305)),
        (CGPoint(x: 1369.98, y: 469.052), CGPoint(x: 1354.2, y: 600.54), CGPoint(x: 1404.17, y: 745.176)),
        (CGPoint(x: 1454.13, y: 889.813), CGPoint(x: 1544.59, y: 1023.09), CGPoint(x: 1630.33, y: 1110.71)),
    ]
}

/// Le M en train de s'écrire. `progress` est la part du trait déjà tracée :
/// 0 ne montre rien, 1 montre le signe entier.
///
/// La vue ne s'anime pas toute seule — c'est l'appelant qui fait varier
/// `progress` dans un `withAnimation`, pour rester maître du moment et de la
/// courbe. Voir `LaunchView`.
public struct BrandMarkDrawing: View {
    private let progress: Double
    private let color: Color

    public init(progress: Double, color: Color = MemoBookColor.outline) {
        self.progress = progress
        self.color = color
    }

    public var body: some View {
        // `GeometryReader` assumé : l'épaisseur du trait est un **nombre**
        // proportionnel à la taille de rendu, pas une contrainte de mise en
        // page. Ni `containerRelativeFrame` ni `visualEffect` ne rendent une
        // valeur exploitable dans un `StrokeStyle` — la géométrie reste la
        // seule façon de lire la taille effective.
        GeometryReader { proxy in
            BrandMark()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: BrandMark.lineWidth(fitting: proxy.size),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .aspectRatio(BrandMark.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview("Le M, tracé") {
    @Previewable @State var progress: Double = 0

    return VStack(spacing: MemoBookSpacing.l) {
        BrandMarkDrawing(progress: progress)
            .padding(MemoBookSpacing.m)

        Slider(value: $progress)
            .tint(MemoBookColor.action)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.background)
    .task {
        withAnimation(.timingCurve(0.884, 0.01, 0.302, 0.99, duration: 0.95)) { progress = 1 }
    }
}
