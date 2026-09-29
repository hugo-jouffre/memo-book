import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Deux pages du carnet, l'une sur l'autre, un peu de travers — ce qu'on
/// regarde pendant qu'on règle ce qui les change.
///
/// **Elles vivent en tête de l'écran des personnalisations** depuis le
/// 29/09/2026 (V3 de la maquette, `3595:23801`) : fixes au-dessus des
/// pastilles de catégorie, et le reste de l'écran défile derrière elles. Elles
/// flottaient jusque-là au-dessus des feuilles de réglage, ce qui reste
/// possible — voir ``SwiftUI/View/bookPagesPeek(pdfUrl:isVisible:)`` — pour une
/// feuille qui en aurait besoin.
///
/// **Sans carnet composé, deux feuilles de papier nues** : la maquette dessine
/// toujours ses deux pages, et un bloc qui disparaît ferait sauter les
/// pastilles et tout le contenu sous elles. Le papier vide dit « il n'y a rien
/// encore », là où deux rectangles blancs *à la place d'un rendu* se liraient
/// comme un rendu raté — c'est la nuance qui décidait, avant, de ne rien
/// montrer.
///
/// Les deux pages sont les premières du PDF du dernier rendu prêt
/// (``TripSettings/bookPdfUrl``), par le même moteur que l'aperçu.
struct BookPagesPeek: View {
    /// Le PDF du carnet composé, ou rien.
    let pdfUrl: URL?

    /// La taille du bloc. Celle de la maquette V3 par défaut : la largeur de
    /// l'écran, et 17.5 rem de haut (280).
    var size: CGSize = Self.headerSize

    /// De combien le bloc descend sous son cadre — la réserve au-dessus d'une
    /// feuille, où la poignée passe. Zéro en tête d'écran.
    var clearance: CGFloat = 0

    @State private var renderer = BookPageRenderer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La taille au-dessus d'une feuille : celle d'avant le 29/09.
    static let sheetSize = CGSize(width: 250, height: 190)

    /// La taille en tête de l'écran des personnalisations (`3595:23806`).
    static let headerSize = CGSize(width: 358, height: 280)

    /// Ce que la feuille réserve au-dessus d'elle pour les pages : leur hauteur
    /// et un peu d'air, pour que la poignée ne les touche pas.
    static var sheetInset: CGFloat { sheetSize.height + MemoBookSpacing.xs }

    /// Sous la poignée d'une feuille, pas dessus.
    static let sheetClearance: CGFloat = MemoBookSpacing.xs * 2 + 5

    /// Les deux inclinaisons de la maquette : celle de derrière penche à
    /// gauche, celle de devant à droite.
    private static let backTilt: Double = -6.24
    private static let frontTilt: Double = 10.39

    /// Elles respirent : deux points de haut en bas, lentement. Assez pour
    /// dire qu'on regarde un objet, pas une capture.
    @State private var isFloating = false

    var body: some View {
        ZStack {
            page(index: 1)
                .rotationEffect(.degrees(Self.backTilt))
                .offset(x: -size.width * 0.18, y: -size.height * 0.07)

            page(index: 0)
                .rotationEffect(.degrees(Self.frontTilt))
                .offset(x: size.width * 0.16, y: size.height * 0.06)
        }
        .frame(width: size.width, height: size.height)
        .offset(y: clearance + (isFloating && !reduceMotion ? -2 : 2))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true),
            value: isFloating
        )
        // Décor, et rien d'autre : l'écran sous ces pages dit ce qu'il règle,
        // et VoiceOver n'a pas à s'arrêter sur deux images muettes.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: pdfUrl) {
            isFloating = true
            guard let pdfUrl else { return }
            await renderer.load(from: pdfUrl)
        }
    }

    private func page(index: Int) -> some View {
        // 80 % de la hauteur du bloc : 223 sur 280, comme la maquette.
        let height = size.height * 0.8
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.xs - 2)

        // Le papier nu tant qu'il n'y a rien à rendre : `BookSheetImage` le
        // dessine lui-même quand le moteur n'a pas de page.
        return BookSheetImage(renderer: renderer, index: index)
            .frame(width: height * renderer.aspectRatio, height: height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(MemoBookColor.onAction, lineWidth: 2) }
            .shadow(color: .black.opacity(0.25), radius: 5, y: 5)
    }
}

extension View {
    /// Pose les deux pages du carnet au-dessus d'une feuille — voir
    /// ``BookPagesPeek``. Rien sans PDF : au-dessus d'une feuille, deux pages
    /// vides se liraient comme un rendu raté.
    @ViewBuilder
    func bookPagesPeek(pdfUrl: URL?, isVisible: Bool = true) -> some View {
        if isVisible, let pdfUrl {
            overlay(alignment: .top) {
                BookPagesPeek(
                    pdfUrl: pdfUrl,
                    size: BookPagesPeek.sheetSize,
                    clearance: BookPagesPeek.sheetClearance
                )
            }
        } else {
            self
        }
    }
}
