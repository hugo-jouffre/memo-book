import MemoBookDesign
import SwiftUI

/// L'écran de lancement : le M de MemoBook s'écrit d'un trait sur le crème,
/// puis **reste** derrière le contenu.
///
/// **Le signe seul, et rien d'autre** (Hugo, 18/09/2026). Il y avait sous le
/// tracé un squelette de l'accueil — la barre de la salutation, le rond de
/// l'avatar — pour que la sortie soit une résolution plutôt qu'un changement
/// d'écran. Il est parti : l'accueil arrive **en montant** du bas, bloc après
/// bloc, et c'est cette cascade qui fait la transition ; deux formes grises
/// qui l'attendaient à leur place ne faisaient que la précéder.
///
/// **Le signe ne disparaît pas.** Il est dessiné par ``BrandMarkBackdrop``, la
/// même vue que l'accueil garde en fond : au moment du passage, l'opacité du M
/// descend de 50 % à 20 %. Le M, lui, ne bouge pas.
///
/// **La courbe du tracé est celle du fichier de marque**
/// (`cubic-bezier(0.884, 0.01, 0.302, 0.99)` dans `Animated Cutout.svg`) : un
/// départ enlevé, une fin qui se pose. C'est ce qui fait que le trait paraît
/// écrit à la main plutôt que balayé à vitesse constante.
struct LaunchView: View {
    /// Appelé quand le M a fini de s'écrire. C'est l'appelant qui fait
    /// disparaître l'écran, pour pouvoir attendre en plus ce qu'il a à charger.
    let onDrawingFinished: () -> Void

    /// Part du trait déjà tracée.
    @State private var drawn: Double = 0

    /// Le signe se pose : il arrive à 97 % et se détend jusqu'à sa taille.
    @State private var settle: CGFloat = 0.97

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Durée du tracé. Court : c'est un lancement, pas une intro.
    private static let drawDuration: Duration = .milliseconds(950)

    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()

            BrandMarkBackdrop(
                progress: drawn,
                opacity: BrandMarkBackdrop.drawingOpacity,
                scale: settle
            )
        }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MemoBook, chargement en cours")
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else {
            // Pas de tracé : le signe est là, on laisse juste le temps de le
            // voir avant de passer à l'accueil.
            drawn = 1
            settle = 1
            try? await Task.sleep(for: .milliseconds(400))
            onDrawingFinished()
            return
        }

        withAnimation(.smooth(duration: 1.2)) { settle = 1 }

        withAnimation(
            .timingCurve(0.884, 0.01, 0.302, 0.99, duration: Self.drawDuration.seconds),
            completionCriteria: .logicallyComplete
        ) {
            drawn = 1
        } completion: {
            onDrawingFinished()
        }
    }
}

extension Duration {
    /// La même durée en secondes, pour les API SwiftUI qui prennent encore un
    /// `TimeInterval`. Partagée avec le paywall, dont la barre de stories se
    /// remplit sur la même durée que celle de son minuteur.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}

#Preview("Lancement") {
    LaunchView {}
}
