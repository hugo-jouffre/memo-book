import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Deux pages du carnet, posées de travers **en tête** d'une feuille de réglage.
///
/// ⚠️ **La maquette les fait flotter hors de la carte ; iOS ne le permet pas.**
/// Une feuille du système rogne tout ce qui déborde d'elle — pas « un peu »,
/// pas « avec une ombre » : rien ne se dessine au-delà de son bord. Trois
/// géométries ont été essayées en simulateur (9 pt de recouvrement comme le
/// nœud, la moitié de la hauteur, puis 22 pt de débord) ; dans les trois cas,
/// ce qui sortait de la feuille disparaissait. Seul un écran custom — fond
/// assombri dessiné à la main, carte posée dessus — le permettrait, au prix du
/// glissé, du repli sur l'écran du dessous et du redimensionnement au clavier
/// que ``BrandSheet`` tient du système.
///
/// Les pages prennent donc leur place **dans** la feuille, au-dessus du titre,
/// dans la réserve que celle-ci ouvre pour elles
/// (``BrandSheet/init(_:badge:subtitle:titleAlignment:surface:topOverflow:content:)``).
/// Elles gardent tout le reste du dessin : les deux inclinaisons, le liseré
/// blanc, l'ombre portée, le flottement lent. Écart **signalé** — à arbitrer
/// avec Clara, voir la fiche écran.
///
/// **Ce sont les vraies pages.** Quatre feuilles de réglage les montrent — fun
/// facts, pointillés, typographie des titres, décorations —, et elles les
/// montrent pour une raison précise : on règle la mise en page *en la
/// regardant*. Les prendre dans le PDF composé, et non dans une image de
/// maquette, est ce qui rend ce coup d'œil honnête ; une illustration figée
/// mentirait dès le premier réglage changé.
///
/// **Pas de carnet, pas de pages.** Tant qu'aucun rendu n'est prêt, la feuille
/// s'ouvre seule : deux rectangles de papier vide au-dessus d'un réglage se
/// liraient comme un rendu qui a échoué, et non comme « il n'y a rien encore ».
/// C'est ``SwiftUI/View/bookPagesPeek(pdfUrl:isVisible:)`` qui tranche.
struct BookPagesPeek: View {
    /// Le PDF du carnet. Non optionnel : la feuille ne pose ces pages que
    /// lorsqu'il y en a un — voir ``SwiftUI/View/bookPagesPeek(pdfUrl:isVisible:)``.
    let pdfUrl: URL

    @State private var renderer = BookPageRenderer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Le cadre des deux pages, en points. **Fixe et hors Dynamic Type** : ce
    /// sont des images, et les faire grandir les pousserait hors de l'écran.
    ///
    /// Plus petit que la maquette (304 × 281) : les pages tiennent **dans la
    /// feuille**, et une réserve de 281 pt pousserait le « Valider » hors de
    /// l'écran sur un iPhone SE.
    static let size = CGSize(width: 250, height: 190)

    /// Ce qui sépare les pages du haut de la feuille : la poignée, et l'air
    /// qu'elle a autour d'elle. Les poser plus haut les ferait passer dessus.
    private static let handleClearance: CGFloat = MemoBookSpacing.xs * 2 + 5

    /// La place que la feuille réserve au-dessus de son titre pour les pages.
    static var sheetInset: CGFloat { size.height + MemoBookSpacing.xs }

    /// Les inclinaisons relevées sur le nœud : la page de gauche part en
    /// arrière, celle de droite revient. Des papiers posés à la main, pas une
    /// grille.
    private static let backTilt: Double = -6.21
    private static let frontTilt: Double = 10.34

    /// La page flotte : elle monte et descend d'un cheveu, sans fin. Même
    /// réglage que la photo des fondateurs — deux points, six secondes — et
    /// elle s'arrête sous « Réduire les animations ».
    @State private var isFloating = false

    var body: some View {
        ZStack {
            page(index: 1)
                .rotationEffect(.degrees(Self.backTilt))
                .offset(x: -Self.size.width * 0.16, y: -Self.size.height * 0.04)

            page(index: 0)
                .rotationEffect(.degrees(Self.frontTilt))
                .offset(x: Self.size.width * 0.16, y: Self.size.height * 0.04)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .offset(y: Self.handleClearance + (isFloating && !reduceMotion ? -2 : 2))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true),
            value: isFloating
        )
        // Décor, et rien d'autre : la feuille sous ces pages dit ce qu'elle
        // règle, et VoiceOver n'a pas à s'arrêter sur deux images muettes.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: pdfUrl) {
            isFloating = true
            await renderer.load(from: pdfUrl)
        }
    }

    /// Une page : l'image du PDF, son liseré blanc et son ombre portée.
    ///
    /// ⚠️ **C'est la hauteur qui commande, pas la largeur.** Une page d'A5
    /// dessinée à partir de sa largeur fait une fois et demie celle-ci en
    /// hauteur : cadrée ainsi, elle sortait du cadre du survol et venait
    /// couvrir le titre de la feuille, que la réserve avait pourtant écarté.
    /// Partir de la hauteur garde la paire **dans** ce qu'elle a annoncé,
    /// inclinaisons comprises.
    private func page(index: Int) -> some View {
        let height = Self.size.height * 0.72
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.xs - 2)

        return BookSheetImage(renderer: renderer, index: index)
            .frame(width: height * renderer.aspectRatio, height: height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(MemoBookColor.onAction, lineWidth: 2) }
            .shadow(color: .black.opacity(0.25), radius: 5, y: 5)
    }
}

extension View {
    /// Pose les deux pages du carnet en tête d'une feuille de réglage.
    ///
    /// À appliquer **sur la ``BrandSheet``**, et toujours avec le `topOverflow`
    /// que celle-ci doit réserver (``BookPagesPeek/sheetInset``) : sans lui, les
    /// pages couvriraient le titre. Sans PDF, la feuille reste seule — deux
    /// rectangles de papier vide ne montrent rien, et prendraient la place du
    /// titre sur un petit écran.
    @ViewBuilder
    func bookPagesPeek(pdfUrl: URL?, isVisible: Bool = true) -> some View {
        if isVisible, let pdfUrl {
            overlay(alignment: .top) { BookPagesPeek(pdfUrl: pdfUrl) }
        } else {
            self
        }
    }
}
