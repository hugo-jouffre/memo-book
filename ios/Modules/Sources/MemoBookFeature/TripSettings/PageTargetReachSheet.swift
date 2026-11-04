import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **Une cible personnalisée hors d'atteinte** (Hugo, 18/10/2026).
///
/// Elle dit, dans l'ordre : ce que le carnet peut faire avec les réglages du
/// moment, puis comment aller chercher la cible voulue — raconter plus,
/// envoyer plus de photos, monter le ratio. Trois réponses : la cible
/// atteignable la plus proche (le bouton plein), le ratio qui ouvre la cible
/// voulue quand il y en a un, et garder la cible telle quelle — le carnet s'en
/// approchera sans rien forcer.
///
/// **Les deux premières réponses s'appliquent d'un seul appui** (Hugo,
/// 04/11/2026). Elles ouvraient derrière elles la feuille qui redemande
/// « Changer le nombre de pages cible ? » : on venait de choisir, et la même
/// question revenait. Ce que cette confirmation disait — le prix du carnet et
/// la règle des deux changements — se lit donc **ici**, avant l'appui.
struct PageTargetReachSheet: View {
    let reach: PageTargetReach
    let model: BookCustomisationModel

    var body: some View {
        BrandSheet(BookCopy.Pages.reachTitle, paragraphs: paragraphs) {
            VStack(spacing: MemoBookSpacing.s) {
                BrandButton(
                    BookCopy.Pages.chooseReachable(reach.closestTarget),
                    fillsWidth: true,
                    action: model.chooseReachableTarget
                )
                if let ratio = reach.ratioThatReaches {
                    BrandButton(
                        BookCopy.Pages.raiseRatio(ratio),
                        style: .secondary,
                        fillsWidth: true,
                        action: model.raiseRatioForTarget
                    )
                }
                BrandButton(
                    BookCopy.Pages.keepAnyway(reach.target),
                    style: .link,
                    fillsWidth: true,
                    action: model.keepUnreachableTarget
                )
            }
        }
    }

    /// Ce que la feuille dit avant ses boutons : l'état des lieux, les
    /// leviers, puis — depuis qu'elle applique sans redemander — le prix de
    /// la cible proposée et ce que l'appui consomme.
    private var paragraphs: [String] {
        var lines = [BookCopy.Pages.reachToday(reach), BookCopy.Pages.reachLevers(reach)]
        if let price = priceOfClosest {
            lines.append(BookCopy.Pages.reachPrice(pages: reach.closestTarget, price: price))
        }
        // Un changement qui ne compte pas — avant le premier souvenir — n'a
        // rien à annoncer : la phrase ne paraît que quand le décompte court.
        let allowance = model.pageTargetAllowance
        if allowance.changesCount, allowance.changesLeft > 0 {
            lines.append(BookCopy.Pages.reachCountsAsChange(changesLeft: allowance.changesLeft))
        }
        return lines
    }

    /// Le prix du carnet à la cible proposée, à la tolérance près — la même
    /// règle que les paliers de l'écran. `nil` sans grille servie : mieux vaut
    /// pas de prix qu'un prix faux.
    private var priceOfClosest: String? {
        model.printPricing?.displayedPrice(forTarget: reach.closestTarget)?.euros
    }
}
