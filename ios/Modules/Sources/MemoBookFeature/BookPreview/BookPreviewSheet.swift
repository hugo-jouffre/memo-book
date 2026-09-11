import MemoBookCore
import MemoBookDesign
import SwiftUI

/// « Prévisualisation » : le carnet qu'on feuillette, **sans quitter l'offre**.
///
/// C'est ce que les deux pastilles « Voir un aperçu » ouvrent — celle du
/// paywall et celle de la feuille d'abonnement. Une feuille et non un écran
/// poussé, et c'est tout le sujet : quelqu'un à qui l'on est en train de
/// proposer un abonnement veut voir ce qu'il achète, puis **revenir à l'offre**.
/// Un écran poussé l'aurait sorti du parcours de vente, et la flèche de retour
/// ne l'y aurait pas ramené au même endroit.
///
/// Elle réutilise les pièces de l'aperçu — ``BookPageStage``, ``BookSheetView``,
/// ``BookPageStepper`` — plutôt que d'en redessiner de plus petites. C'est la
/// même page et le même geste ; en refaire une version « pour la feuille »
/// aurait donné deux aperçus à tenir d'accord, et celui de la feuille aurait
/// vieilli le premier.
struct BookPreviewSheet: View {
    @State private var model: BookPreviewModel

    /// Le retour à l'étape d'où l'on vient. `nil` quand la feuille est
    /// présentée seule — le paywall la referme par son geste de feuille, il n'y
    /// a rien derrière elle.
    private let onBack: (() -> Void)?

    /// - Parameter memoId: le carnet à montrer. `nil` — le cas d'un compte qui
    ///   n'a pas encore de voyage en cours — ouvre le jeu d'essai : la feuille
    ///   existe pour **montrer à quoi ça ressemble**, et un aperçu vide ne
    ///   vendrait rien.
    init(memoId: String?, onBack: (() -> Void)? = nil) {
        _model = State(initialValue: BookPreviewModel(memoId: memoId ?? "preview"))
        self.onBack = onBack
    }

    var body: some View {
        BrandSheet(BookCopy.Preview.sheetTitle) {
            VStack(spacing: MemoBookSpacing.xs) {
                BookPageStage {
                    switch model.stage {
                    case .composing:
                        BookCompositionPage(progress: model.compositionProgress)
                            .transition(.opacity)
                    case .preview:
                        // Pas de plein écran depuis la feuille : il faudrait en
                        // sortir pour y entrer, et on ne reviendrait pas à
                        // l'offre. La commande est donc absente, et non
                        // désactivée — un bouton qui ne fait rien est pire que
                        // pas de bouton.
                        BookSheetView(model: model, onExpand: nil, onConfigureCovers: {})
                            .transition(.opacity)
                    }
                }
                .animation(.smooth(duration: 0.3), value: model.stage)

                // L'indicateur de pages attend que la page soit montée : le
                // montrer pendant la composition annoncerait des pages qu'on ne
                // peut pas encore tourner.
                if model.stage == .preview {
                    BookPageStepper(model: model)
                        .transition(.opacity)
                } else {
                    BrandSkeleton(width: 96)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, MemoBookSpacing.snug)
                }

                if model.renderer.didFail {
                    ErrorBanner(message: BookCopy.Preview.loadFailed) {
                        Task { await model.reloadDocument() }
                    }
                }

                if let onBack {
                    BrandButton(
                        BookCopy.Preview.backToOffer,
                        style: .secondary,
                        fillsWidth: true,
                        action: onBack
                    )
                    .padding(.top, MemoBookSpacing.xs)
                }
            }
        }
        // La composition se joue **aussi ici** : la page se monte sous les yeux
        // avant de se laisser feuilleter, exactement comme sur l'écran d'aperçu.
        // C'est ce que la maquette du paywall montre, et c'est ce qui donne
        // envie de tourner la page.
        .task { await model.run() }
    }
}

#Preview("Feuille de prévisualisation") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            BookPreviewSheet(memoId: nil)
        }
        .environment(\.colorScheme, .light)
}
