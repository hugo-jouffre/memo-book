import SwiftUI
import UIKit

extension View {
    /// Pose **la** barre d'accessoires du clavier de MemoBook : un seul bouton,
    /// à droite, qui referme le clavier.
    ///
    /// Une icône plutôt qu'un mot. « OK » laisse croire qu'on valide quelque
    /// chose, alors qu'on ne fait que ranger le clavier — et sur un écran où
    /// l'enregistrement se fait tout seul à la sortie du champ, ce faux bouton
    /// de validation est un contresens. `IconKeyboardDown` dit ce qu'il fait :
    /// le clavier descend. C'est l'icône dessinée pour ça, arrivée dans le jeu
    /// de marque à la place du double chevron provisoire (T27).
    ///
    /// Il est **centré sur la barre, quel que soit l'iOS** (Hugo, 16/09/2026).
    /// Il flottait de 8 pt au-dessus des touches — pour qu'on ne le vise pas
    /// entre deux rangées —, et ce décalage le sortait du milieu : de la ligne
    /// plate avant iOS 26, et de la **bulle de verre** que la barre
    /// d'accessoires dessine autour de chaque bouton depuis. La cible de 44 pt
    /// suffit à l'atteindre sans le soulever.
    public func brandKeyboardDismissBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    KeyboardDismissal.resignFirstResponder()
                } label: {
                    Image(brand: "IconKeyboardDown")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                        .foregroundStyle(MemoBookColor.action)
                        .frame(
                            minWidth: MemoBookSpacing.minimumTapTarget,
                            minHeight: MemoBookSpacing.minimumTapTarget
                        )
                        .contentShape(.rect)
                }
                .accessibilityLabel("Masquer le clavier")
            }
        }
    }
}

/// Referme le clavier sans savoir quel champ le tenait.
///
/// Les écrans qui corrigent une valeur sur place gardent leur focus pour eux —
/// c'est la sortie du champ qui enregistre. On demande donc au premier
/// répondant de se retirer, quel qu'il soit, plutôt que de faire remonter tous
/// les `@FocusState` de l'écran jusqu'à la barre.
public enum KeyboardDismissal {
    @MainActor
    public static func resignFirstResponder() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
