import SwiftUI
import UIKit

extension View {
    /// Dit de combien la `ScrollView` qui porte cette vue a défilé : le haut du
    /// contenu par rapport au haut du cadre, **négatif** quand on descend vers
    /// la fin — la même mesure que `frame(in:).minY` du contenu.
    ///
    /// ⚠️ **Pas de `GeometryReader` pour ça.** La conversation en posait un en
    /// fond de sa `LazyVStack`, ancrée en bas : sur la largeur d'un iPhone SE,
    /// lire le cadre de la liste la faisait se replacer, ce qui déplaçait le
    /// défilement, ce qui la faisait se replacer — l'app à 100 % d'un cœur,
    /// conversation ouverte et personne ne la touchant (recette du 30/09/2026).
    /// iOS 18 a `onScrollGeometryChange` ; l'app cible iOS 17. On lit donc
    /// l'`UIScrollView` elle-même, par observation de son `contentOffset` : rien
    /// ne dépend de la mise en page de SwiftUI, et rien ne s'y redemande.
    ///
    /// À poser **sur le contenu** de la `ScrollView`, comme
    /// ``SwiftUI/View/brandScrollWithoutBounce()`` : la sonde remonte ses
    /// parents jusqu'à la trouver.
    ///
    /// - Parameter onChange: le haut du contenu, et **si c'est le doigt** qui
    ///   fait défiler — pendant le glissé ou l'élan qui le suit. Une liste qui
    ///   se cale en bas à l'ouverture, un `scrollTo` à l'arrivée d'un message
    ///   bougent aussi le contenu, et ce ne sont pas des gestes.
    public func brandScrollOffset(
        _ onChange: @escaping @MainActor (_ top: CGFloat, _ byUser: Bool) -> Void
    ) -> some View {
        background(ScrollOffsetProbe(onChange: onChange).frame(width: 0, height: 0))
    }
}

private struct ScrollOffsetProbe: UIViewRepresentable {
    let onChange: @MainActor (CGFloat, Bool) -> Void

    func makeUIView(context: Context) -> Probe { Probe(onChange: onChange) }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onChange = onChange
    }

    final class Probe: UIView {
        var onChange: @MainActor (CGFloat, Bool) -> Void
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping @MainActor (CGFloat, Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            observation = nil
            guard window != nil, let scrollView = enclosingScrollView else { return }

            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) {
                [weak self] scrollView, _ in
                // L'observation arrive sur le fil principal — c'est lui qui fait
                // défiler —, mais le compilateur ne le sait pas. **Tout** se lit
                // donc dans `assumeIsolated`, et pas seulement le rappel : les
                // propriétés d'une `UIScrollView` sont isolées au fil principal
                // elles aussi.
                MainActor.assumeIsolated {
                    let top = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
                    let byUser = scrollView.isDragging || scrollView.isDecelerating
                    self?.onChange(top, byUser)
                }
            }
        }

        private var enclosingScrollView: UIScrollView? {
            var view: UIView? = superview
            while let current = view {
                if let scrollView = current as? UIScrollView { return scrollView }
                view = current.superview
            }
            return nil
        }
    }
}
