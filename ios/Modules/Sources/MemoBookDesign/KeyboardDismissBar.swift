import SwiftUI
import UIKit

extension View {
    /// Pose **la** barre d'accessoires du clavier de MemoBook : un seul bouton,
    /// à droite, qui referme le clavier.
    ///
    /// Un chevron plutôt qu'un mot. « OK » laisse croire qu'on valide quelque
    /// chose, alors qu'on ne fait que ranger le clavier — et sur un écran où
    /// l'enregistrement se fait tout seul à la sortie du champ, ce faux bouton
    /// de validation est un contresens. Le chevron dit ce qu'il fait :
    /// ça descend.
    ///
    /// Il flotte un peu au-dessus du clavier plutôt que d'y être collé : posé au
    /// ras des touches, on l'atteint en visant entre deux rangées, et on tape un
    /// caractère une fois sur trois.
    public func brandKeyboardDismissBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    KeyboardDismissal.resignFirstResponder()
                } label: {
                    Image(brand: "IconChevronDown")
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
                .padding(.bottom, MemoBookSpacing.xs)
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
