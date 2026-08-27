import MemoBookDesign
import SwiftUI

/// Le premier écran au lancement, pendant la restauration de session.
///
/// Aucune interaction possible : il se contente de tenir la place pendant que
/// `OnboardingModel.start()` décide de la destination. Nœud Figma `2553:27641`.
struct SplashView: View {
    var body: some View {
        ZStack {
            MemoBookColor.background.ignoresSafeArea()
            BackgroundRoute()

            VStack(spacing: MemoBookSpacing.xl) {
                FigmaImage(.companyLogo)
                    .frame(width: rem(9.33), height: rem(6.67))

                LoaderBar()
            }
            // Le bloc est centré, très légèrement sous le centre optique —
            // c'est ce que donne la maquette (haut du bloc à 360 sur 844).
            .offset(y: rem(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MemoBook, chargement en cours")
    }
}

#Preview("Splash") {
    SplashView()
}
