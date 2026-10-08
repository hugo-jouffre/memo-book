import SwiftUI

/// **La** jauge de MemoBook : une barre qui se remplit à mesure qu'un budget
/// se dépense.
///
/// Une seule dans l'app aujourd'hui — le crédit du jour d'un voyage, dans ses
/// réglages —, et elle vit ici quand même : c'est un motif, pas un dessin
/// d'écran, et la prochaine (les pages d'un carnet face à sa cible) devra lui
/// ressembler.
///
/// **Vide et grise au matin, le vert avance vers la droite** (Hugo,
/// 08/10/2026). Elle a été pleine au matin et se vidait (recette du
/// 03/10/2026) ; Hugo la veut dans l'autre sens : elle part de zéro, et ce
/// qu'on raconte la remplit. C'est le **chiffre posé à côté** qui dit le
/// reste — « 3 min 20 restantes » —, en toutes lettres, pour que la barre et
/// lui ne se contredisent pas.
///
/// À ne pas confondre avec ``BrandSlider``, qui se **règle** : celle-ci ne se
/// touche pas, elle se lit. D'où l'absence de poignée et de cible tactile.
///
/// **Elle change de couleur à un seuil, et à un seul.** Le vert d'action tant
/// qu'il reste de la marge, le rouge sémantique quand tout est dépensé — la
/// barre est alors pleine, et c'est elle qui rougit. Pas d'orange
/// intermédiaire : trois couleurs sur une barre demandent une légende, et une
/// jauge qui demande une légende a raté son travail.
public struct BrandGauge: View {
    private let fraction: Double
    private let isExhausted: Bool
    private let accessibilityLabel: String
    private let accessibilityValue: String?

    /// - Parameters:
    ///   - fraction: la part **dépensée**, entre 0 et 1. Bornée ici : un
    ///     barème réétalonné entre deux périodes peut rendre un dépassement, et
    ///     une barre plus longue que son rail se lirait comme un défaut
    ///     d'affichage.
    ///   - isExhausted: il ne reste rien. La barre, pleine, passe au rouge.
    ///   - accessibilityLabel: ce que VoiceOver annonce — « Crédit du jour ».
    ///   - accessibilityValue: ce qu'il lit ensuite — « 3 min 20 restantes
    ///     sur 5 min ». Un pourcentage nu se comprenait de travers ; sans
    ///     valeur fournie, la jauge dit « 34 % utilisé ».
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

    /// Le gris du matin : la barre entière, avant le premier mot raconté.
    private var rail: Color {
        MemoBookColor.separator.opacity(0.5)
    }

    private var spokenValue: Text {
        if let accessibilityValue { return Text(accessibilityValue) }
        return Text("\(fraction.formatted(.percent.precision(.fractionLength(0)))) utilisé")
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
        // Au matin, à mi-journée, puis tout dépensé.
        BrandGauge(fraction: 0, accessibilityLabel: "Crédit du jour")
        BrandGauge(fraction: 0.6, accessibilityLabel: "Crédit du jour")
        BrandGauge(fraction: 1, isExhausted: true, accessibilityLabel: "Crédit du jour")
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
