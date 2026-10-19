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
/// Elle passe **avant** la feuille du changement de cible
/// (``PageTargetChangeSheet``) : rien n'a changé tant qu'on n'a pas répondu.
struct PageTargetReachSheet: View {
    let reach: PageTargetReach
    let model: BookCustomisationModel

    var body: some View {
        BrandSheet(
            BookCopy.Pages.reachTitle,
            paragraphs: [BookCopy.Pages.reachToday(reach), BookCopy.Pages.reachLevers(reach)]
        ) {
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
}
