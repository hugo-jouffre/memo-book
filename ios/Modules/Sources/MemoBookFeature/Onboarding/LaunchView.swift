import MemoBookDesign
import SwiftUI

/// L'écran de lancement : le M de MemoBook s'écrit d'un trait, par-dessus le
/// squelette de l'accueil, puis **reste** derrière le contenu.
///
/// **Pourquoi un squelette et pas un logo centré.** Un logo seul suivi d'un
/// écran plein est une coupure : deux images sans rapport. Ici la barre de
/// salutation et le rond de l'avatar sont déjà à leur place définitive — voir
/// ``HomeMetrics`` —, si bien que la sortie est une résolution, pas un
/// changement d'écran.
///
/// **Le signe ne disparaît pas.** Il est dessiné par ``BrandMarkBackdrop``, la
/// même vue que l'accueil garde en fond : au moment du passage, seul le
/// squelette s'efface et l'opacité du M descend de 50 % à 20 %. Le M, lui, ne
/// bouge pas.
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

            HomeSkeleton()

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

/// Le squelette de l'accueil : la salutation et l'avatar, réduits à leurs
/// formes. Rien d'autre — un squelette qui dessine des cartes vides promet un
/// contenu qu'il ne connaît pas encore.
struct HomeSkeleton: View {
    var body: some View {
        VStack {
            HStack(spacing: MemoBookSpacing.s) {
                RoundedRectangle(cornerRadius: MemoBookSpacing.xs)
                    .fill(MemoBookColor.hairline)
                    .frame(
                        width: HomeMetrics.greetingPlaceholderWidth,
                        height: HomeMetrics.greetingPlaceholderHeight
                    )

                Spacer(minLength: 0)

                Circle()
                    .fill(MemoBookColor.hairline)
                    .frame(width: HomeMetrics.avatarSide, height: HomeMetrics.avatarSide)
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, HomeMetrics.topPadding)

            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

extension Duration {
    /// La même durée en secondes, pour les API SwiftUI qui prennent encore un
    /// `TimeInterval`.
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}

#Preview("Lancement") {
    LaunchView {}
}
