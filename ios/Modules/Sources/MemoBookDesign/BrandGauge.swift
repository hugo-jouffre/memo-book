import SwiftUI

/// **La** jauge de MemoBook : une barre qui dit ce qui est consommé d'un budget.
///
/// Une seule dans l'app aujourd'hui — les limites de souvenirs —, et elle vit
/// ici quand même : c'est un motif, pas un dessin d'écran, et la prochaine
/// (les pages d'un carnet face à sa cible) devra lui ressembler.
///
/// À ne pas confondre avec ``BrandSlider``, qui se **règle** : celle-ci ne se
/// touche pas, elle se lit. D'où l'absence de poignée et de cible tactile, et
/// la lecture VoiceOver en pourcentage plutôt qu'en valeur réglable.
///
/// **Elle change de couleur à un seuil, et à un seul.** Le vert d'action tant
/// qu'il reste de la marge, le rouge sémantique quand il n'y a plus rien. Pas
/// d'orange intermédiaire : trois couleurs sur une barre demandent une légende,
/// et une jauge qui demande une légende a raté son travail.
public struct BrandGauge: View {
    private let fraction: Double
    private let isExhausted: Bool
    private let accessibilityLabel: String

    /// - Parameters:
    ///   - fraction: la part consommée, entre 0 et 1. Bornée ici : un barème
    ///     réétalonné entre deux périodes peut rendre un dépassement, et une
    ///     barre plus longue que son rail se lirait comme un défaut d'affichage.
    ///   - isExhausted: il ne reste rien. La barre passe au rouge sémantique.
    ///   - accessibilityLabel: ce que VoiceOver annonce — « Limites de
    ///     souvenirs ». La valeur, elle, est calculée ici.
    public init(fraction: Double, isExhausted: Bool = false, accessibilityLabel: String) {
        self.fraction = min(1, max(0, fraction))
        self.isExhausted = isExhausted
        self.accessibilityLabel = accessibilityLabel
    }

    /// Assez épaisse pour se voir de loin, assez fine pour rester une jauge et
    /// non un bloc. Elle suit le corps de texte : à taille accessible, une
    /// barre de 8 pt sous des lignes de 30 disparaîtrait.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 8

    private var fill: Color {
        isExhausted ? MemoBookColor.error : MemoBookColor.action
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MemoBookColor.separator.opacity(0.5))
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.4), value: fraction)
        .animation(.smooth(duration: 0.3), value: isExhausted)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("Jauge") {
    VStack(spacing: MemoBookSpacing.m) {
        BrandGauge(fraction: 0.12, accessibilityLabel: "Limites de souvenirs")
        BrandGauge(fraction: 0.85, accessibilityLabel: "Limites de souvenirs")
        BrandGauge(fraction: 1, isExhausted: true, accessibilityLabel: "Limites de souvenirs")
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
