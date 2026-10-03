import SwiftUI

/// **La** jauge de MemoBook : une barre qui dit **ce qui reste** d'un budget.
///
/// Une seule dans l'app aujourd'hui — le crédit du jour d'un voyage, dans ses
/// réglages —, et elle vit ici quand même : c'est un motif, pas un dessin
/// d'écran, et la prochaine (les pages d'un carnet face à sa cible) devra lui
/// ressembler.
///
/// **Ce qui reste, et non ce qui est consommé** (recette du 03/10/2026). Le
/// chiffre posé à côté dit le reste — « 4 min 30 / 5 min » — et la barre se
/// remplissait avec le consommé : presque vide quand le chiffre disait presque
/// plein. Elle est désormais **pleine au matin, se vide à mesure qu'on
/// raconte, et rougit à zéro** : le chiffre et la barre disent la même chose.
///
/// À ne pas confondre avec ``BrandSlider``, qui se **règle** : celle-ci ne se
/// touche pas, elle se lit. D'où l'absence de poignée et de cible tactile.
///
/// **Elle change de couleur à un seuil, et à un seul.** Le vert d'action tant
/// qu'il reste de la marge, le rouge sémantique quand il n'y a plus rien. Pas
/// d'orange intermédiaire : trois couleurs sur une barre demandent une légende,
/// et une jauge qui demande une légende a raté son travail. À zéro, il n'y a
/// plus de barre à teindre : c'est le **rail** qui passe au rouge doux
/// (``MemoBookColor/errorSoft``), sans quoi le rouge ne se verrait jamais.
public struct BrandGauge: View {
    private let fraction: Double
    private let isExhausted: Bool
    private let accessibilityLabel: String
    private let accessibilityValue: String?

    /// - Parameters:
    ///   - fraction: la part qui **reste**, entre 0 et 1. Bornée ici : un
    ///     barème réétalonné entre deux périodes peut rendre un dépassement, et
    ///     une barre plus longue que son rail se lirait comme un défaut
    ///     d'affichage.
    ///   - isExhausted: il ne reste rien. Le rail passe au rouge doux.
    ///   - accessibilityLabel: ce que VoiceOver annonce — « Crédit du jour ».
    ///   - accessibilityValue: ce qu'il lit ensuite — « 3 min 20 sur 5 min ».
    ///     Un pourcentage nu sous « Il reste… » se comprenait de travers ; sans
    ///     valeur fournie, la jauge dit « 66 % restant ».
    public init(
        fraction: Double,
        isExhausted: Bool = false,
        accessibilityLabel: String,
        accessibilityValue: String? = nil
    ) {
        self.fraction = min(1, max(0, fraction))
        self.isExhausted = isExhausted
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }

    /// Assez épaisse pour se voir de loin, assez fine pour rester une jauge et
    /// non un bloc. Elle suit le corps de texte : à taille accessible, une
    /// barre de 8 pt sous des lignes de 30 disparaîtrait.
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 8

    private var fill: Color {
        isExhausted ? MemoBookColor.error : MemoBookColor.action
    }

    private var rail: Color {
        isExhausted ? MemoBookColor.errorSoft : MemoBookColor.separator.opacity(0.5)
    }

    private var spokenValue: Text {
        if let accessibilityValue { return Text(accessibilityValue) }
        return Text("\(fraction.formatted(.percent.precision(.fractionLength(0)))) restant")
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(rail)
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
        .accessibilityValue(spokenValue)
    }
}

#Preview("Jauge") {
    VStack(spacing: MemoBookSpacing.m) {
        // Au matin, à mi-journée, puis à zéro.
        BrandGauge(fraction: 1, accessibilityLabel: "Crédit du jour")
        BrandGauge(fraction: 0.4, accessibilityLabel: "Crédit du jour")
        BrandGauge(fraction: 0, isExhausted: true, accessibilityLabel: "Crédit du jour")
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
