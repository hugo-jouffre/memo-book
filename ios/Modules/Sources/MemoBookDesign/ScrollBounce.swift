import SwiftUI
import UIKit

extension View {
    /// Retire l'élastique de la `ScrollView` qui porte cette vue : le contenu
    /// **s'arrête** à ses deux bouts au lieu de rebondir au-delà.
    ///
    /// SwiftUI ne sait que `scrollBounceBehavior(.basedOnSize)`, qui coupe
    /// l'élastique seulement quand le contenu tient dans le cadre. Dès qu'il
    /// défile, il rebondit — et sur l'écran d'entrée, tirer la carte vers le
    /// haut découvrait ce qu'il y a sous elle (Clara, 17/09/2026). On va donc
    /// chercher l'`UIScrollView` que SwiftUI a posée derrière, et on lui dit
    /// de ne pas rebondir. À poser **sur le contenu** de la `ScrollView`, pas
    /// sur elle : la vue remonte ses parents jusqu'à la trouver.
    public func brandScrollWithoutBounce() -> some View {
        background(ScrollBounceDisabler().frame(width: 0, height: 0))
    }
}

/// La vue UIKit qui, une fois dans la fenêtre, remonte jusqu'à l'`UIScrollView`
/// la plus proche et lui retire son élastique.
private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view: UIView? = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    scrollView.bounces = false
                    return
                }
                view = current.superview
            }
        }
    }
}
