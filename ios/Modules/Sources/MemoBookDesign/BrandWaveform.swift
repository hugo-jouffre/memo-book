import SwiftUI

/// La frise du son : une barre par échantillon, la plus récente à droite.
///
/// Ce n'est pas une visualisation du fichier — c'est le **retour du micro**.
/// Elle sert à une seule chose : montrer que ce qu'on dit arrive. D'où le
/// parti pris de la maquette, des barres pleines et espacées plutôt qu'une
/// courbe : on lit le rythme de la voix d'un coup d'œil, pas sa forme d'onde.
///
/// La frise **avance** : tant qu'il y a moins d'échantillons que de barres,
/// elle se remplit depuis la gauche ; ensuite chaque nouvel échantillon pousse
/// les autres. Comme les barres gardent leur identité de position, c'est leur
/// hauteur qui s'anime, et le tout glisse au lieu de sauter.
public struct BrandWaveform: View {
    /// Les niveaux, de 0 à 1, du plus ancien au plus récent. Seuls les
    /// ``capacity`` derniers sont dessinés.
    private let levels: [Double]
    private let isDimmed: Bool

    /// Combien de barres tiennent à l'écran. C'est **la** constante qui règle
    /// la vitesse apparente de la frise : avec un échantillon toutes les 80 ms,
    /// 34 barres font défiler un peu moins de trois secondes de voix.
    public static let capacity = 34

    /// - Parameter isDimmed: la capture est en pause. Les barres restent en
    ///   place — on n'efface pas ce qui a été dit — mais s'éteignent, pour qu'on
    ///   ne les lise pas comme du son qui continue d'arriver.
    public init(levels: [Double], isDimmed: Bool = false) {
        self.levels = levels
        self.isDimmed = isDimmed
    }

    @ScaledMetric(relativeTo: .body) private var maximumHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var barWidth: CGFloat = 4
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 5

    /// La barre d'un silence. Pas zéro : une frise qui disparaît par endroits
    /// se lit comme un trou dans l'enregistrement, alors que se taire une
    /// seconde est normal.
    private var minimumHeight: CGFloat { barWidth }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(MemoBookColor.action)
                    .frame(width: barWidth, height: height(for: level))
            }
            // La frise pousse depuis la gauche tant qu'elle n'est pas pleine.
            Spacer(minLength: 0)
        }
        .opacity(isDimmed ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: maximumHeight)
        // Assez court pour suivre la voix, assez long pour que deux
        // échantillons se rejoignent au lieu de clignoter.
        .animation(.linear(duration: 0.09), value: levels)
        .animation(.easeOut(duration: 0.25), value: isDimmed)
        .accessibilityHidden(true)
    }

    private var shown: [Double] { levels.suffix(Self.capacity) }

    private func height(for level: Double) -> CGFloat {
        let clamped = min(max(level, 0), 1)
        return minimumHeight + (maximumHeight - minimumHeight) * clamped
    }
}

#Preview("Frise") {
    let levels = (0..<40).map { index in
        (sin(Double(index) / 2.2) * 0.4 + 0.5) * (index > 30 ? 0.4 : 1)
    }

    return VStack(spacing: MemoBookSpacing.l) {
        BrandWaveform(levels: levels)
        BrandWaveform(levels: levels, isDimmed: true)
        BrandWaveform(levels: Array(levels.prefix(8)))
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.listeningBackground)
    .environment(\.colorScheme, .light)
}
