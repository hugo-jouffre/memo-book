import SwiftUI

/// La forme d'onde de MemoBook, sous ses deux emplois : ce qu'on est en train
/// de dire, et ce qu'on a déjà dit.
///
/// Elle existait déjà, dessinée dans `MemoDetailView` et privée à ce fichier —
/// donc invisible du chat, qui en a besoin dans chaque bulle vocale. C'est sa
/// deuxième occurrence : elle monte dans le design system, et les deux écrans
/// dessinent enfin la même chose.
///
/// | Emploi | Ce qu'on passe | Ce qu'on voit |
/// |---|---|---|
/// | **En direct**, pendant qu'on parle | ``init(live:capacity:isDimmed:tint:)`` | une frise qui **glisse** : la voix arrive par la droite et pousse le reste |
/// | **Un vocal terminé** | ``init(levels:progress:)`` | les niveaux relevés, la partie jouée teintée |
///
/// **Les deux ne se dessinent pas de la même façon, et c'est nécessaire.** Un
/// vocal terminé peut compter des centaines d'échantillons : il passe par un
/// `Canvas`, qui les rééchantillonne et n'a qu'une vue à mesurer. La frise en
/// direct, elle, est une pile de `Capsule` — une par **position** —, parce que
/// c'est cette identité de position qui fait que seule la *hauteur* s'anime et
/// que le tout glisse au lieu de sauter. Un `Canvas` redessinerait tout d'un
/// coup, et la frise sauterait d'un cran à chaque échantillon.
///
/// **Les niveaux d'un vocal terminé ne s'inventent pas.** ``AudioRecorder`` ne
/// publie qu'un niveau instantané : c'est au modèle de l'écran de les
/// accumuler pendant l'enregistrement. Un relevé vide donne une ligne plate, et
/// c'est honnête — une forme d'onde décorative, identique pour tous les vocaux,
/// dirait quelque chose de faux sur ce qui a été dit.
public struct BrandWaveform: View {
    /// Les barres à dessiner, entre 0 et 1.
    private let levels: [Double]

    /// De 0 à 1 : jusqu'où la lecture est arrivée. `nil` pour l'emploi en
    /// direct, où il n'y a rien de « déjà joué ».
    private let progress: Double?

    private let tint: Color
    private let playedTint: Color

    /// La forme d'onde d'un vocal terminé.
    ///
    /// - Parameters:
    ///   - levels: les niveaux relevés pendant l'enregistrement, dans l'ordre du
    ///     temps. Vide donne une ligne plate.
    ///   - progress: de 0 à 1, la position de lecture. Les barres avant elle
    ///     prennent ``playedTint``.
    public init(
        levels: [Double],
        progress: Double = 0,
        tint: Color = MemoBookColor.inkMuted,
        playedTint: Color = MemoBookColor.ink
    ) {
        self.levels = levels
        self.live = nil
        self.capacity = 0
        self.isDimmed = false
        self.progress = min(max(progress, 0), 1)
        self.tint = tint
        self.playedTint = playedTint
    }

    /// Les niveaux d'une capture en cours. `nil` pour un vocal terminé.
    private let live: [Double]?
    private let capacity: Int
    private let isDimmed: Bool

    /// La frise du micro pendant qu'on parle.
    ///
    /// Elle **avance** : tant qu'il y a moins d'échantillons que de barres, elle
    /// se remplit depuis la gauche ; ensuite chaque nouvel échantillon pousse
    /// les autres. C'est le même geste que la grande feuille d'enregistrement,
    /// et c'est ce qui fait qu'on voit sa voix *arriver* plutôt que clignoter.
    ///
    /// - Parameters:
    ///   - live: tous les niveaux relevés depuis le début, du plus ancien au
    ///     plus récent. Seuls les ``capacity`` derniers sont dessinés.
    ///   - capacity: combien de barres tiennent dans la place. C'est **la**
    ///     constante qui règle la vitesse apparente de la frise.
    ///   - isDimmed: la capture est en pause. Les barres restent en place — on
    ///     n'efface pas ce qui a été dit — mais s'éteignent, pour qu'on ne les
    ///     lise pas comme du son qui continue d'arriver.
    public init(
        live levels: [Double],
        capacity: Int = 34,
        isDimmed: Bool = false,
        tint: Color = MemoBookColor.action
    ) {
        self.levels = levels
        self.live = levels
        self.capacity = max(1, capacity)
        self.isDimmed = isDimmed
        self.progress = nil
        self.tint = tint
        self.playedTint = tint
    }

    /// L'épaisseur d'une barre et l'air entre deux. Fixes, et non mises à
    /// l'échelle du texte : une forme d'onde est un dessin, pas un mot — la
    /// grossir avec le corps de texte la transformerait en histogramme.
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2

    /// Le plancher d'une barre. Sans lui, un silence disparaît complètement et
    /// la forme d'onde a l'air rognée.
    private static let minimumBarHeight: CGFloat = 3

    @ViewBuilder
    public var body: some View {
        if live != nil {
            frieze
        } else {
            recorded
        }
    }

    /// La frise en direct : une `Capsule` par position, la plus récente à
    /// droite.
    private var frieze: some View {
        let shown = (live ?? []).suffix(capacity)

        return HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(tint)
                    .frame(width: Self.barWidth, height: barHeight(for: level))
            }
            // La frise pousse depuis la gauche tant qu'elle n'est pas pleine.
            Spacer(minLength: 0)
        }
        .opacity(isDimmed ? 0.35 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        // Assez court pour suivre la voix, assez long pour que deux
        // échantillons se rejoignent au lieu de clignoter.
        .animation(.linear(duration: 0.09), value: levels)
        .animation(.easeOut(duration: 0.25), value: isDimmed)
        .accessibilityHidden(true)
    }

    private func barHeight(for level: Double) -> CGFloat {
        let clamped = min(max(level, 0), 1)
        return Self.minimumBarHeight + (Self.height - Self.minimumBarHeight) * clamped
    }

    private var recorded: some View {
        // `Canvas` plutôt qu'une pile de `Capsule` : une bulle vocale peut
        // porter une centaine de barres, et autant de vues à mesurer feraient
        // ramer le défilement du fil.
        Canvas { context, size in
            let bars = Self.resample(levels, toFit: size.width)
            let played = Int((self.progress ?? 0) * Double(bars.count))

            for (index, level) in bars.enumerated() {
                let height = max(Self.minimumBarHeight, size.height * level)
                let rect = CGRect(
                    x: CGFloat(index) * (Self.barWidth + Self.barSpacing),
                    y: (size.height - height) / 2,
                    width: Self.barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: Self.barWidth / 2),
                    with: .color(self.progress != nil && index < played ? self.playedTint : self.tint)
                )
            }
        }
        .frame(height: Self.height)
        // Le dessin ne dit rien de plus que la durée, déjà annoncée par la bulle
        // qui le porte.
        .accessibilityHidden(true)
    }

    /// La hauteur de la bande. La maquette dessine 22,6 pt ; on prend le cran de
    /// l'échelle juste au-dessus (§2.2 de `docs/ui-development.md`).
    public static let height = MemoBookSpacing.m

    /// Ramène un relevé au nombre de barres que la largeur peut tenir.
    ///
    /// C'est **la largeur disponible qui commande**, pas la donnée : un vocal de
    /// trois minutes a des centaines d'échantillons, et les entasser donnerait
    /// un aplat gris. Chaque barre dessinée prend le **maximum** de sa tranche,
    /// et non la moyenne — une moyenne aplatit les pics, c'est-à-dire tout ce
    /// qu'une forme d'onde a à montrer.
    static func resample(_ levels: [Double], toFit width: CGFloat) -> [CGFloat] {
        let capacity = max(1, Int((width + barSpacing) / (barWidth + barSpacing)))
        guard !levels.isEmpty else { return [0] }
        guard levels.count > capacity else {
            return levels.map { CGFloat(min(max($0, 0), 1)) }
        }

        return (0..<capacity).map { slot in
            let start = slot * levels.count / capacity
            let end = max(start + 1, (slot + 1) * levels.count / capacity)
            let peak = levels[start..<min(end, levels.count)].max() ?? 0
            return CGFloat(min(max(peak, 0), 1))
        }
    }
}

// MARK: - Aperçus

#Preview("Formes d’onde") {
    VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
        BrandWaveform(levels: BrandWaveform.sampleLevels, progress: 0.35)
        BrandWaveform(levels: [])
        BrandWaveform(live: BrandWaveform.sampleLevels, capacity: 19)
        BrandWaveform(live: Array(BrandWaveform.sampleLevels.prefix(6)), capacity: 19)
        BrandWaveform(live: BrandWaveform.sampleLevels, capacity: 19, isDimmed: true)
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}

extension BrandWaveform {
    /// Un relevé d'exemple pour les aperçus. Une sinusoïde bruitée
    /// **déterministe** : pas de `random`, sinon deux captures d'un même aperçu
    /// ne se superposent plus.
    ///
    /// `nonisolated` parce qu'une `View` est isolée à l'acteur principal, et que
    /// les jeux d'essai qui s'en servent, eux, ne le sont pas. Un tableau de
    /// `Double` constant n'a rien à protéger.
    public nonisolated static let sampleLevels: [Double] = (0..<64).map { index in
        let base = sin(Double(index) / 3.1) * 0.35 + 0.5
        let grain = sin(Double(index) * 1.7) * 0.15
        return min(max(base + grain, 0.08), 1)
    }
}
