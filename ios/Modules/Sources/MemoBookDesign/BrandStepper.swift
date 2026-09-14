import SwiftUI

/// Le compteur « − 2 + » de la commande.
///
/// **Un composant et non deux boutons posés autour d'un nombre** : les deux
/// cercles doivent faire la même taille, tomber à la même distance du chiffre,
/// et garder leur cible tactile de 44 pt même quand le dessin fait 43. C'est
/// exactement ce qu'on rate en le réécrivant.
///
/// Le `Stepper` du système n'a pas été retenu : il impose son propre dessin de
/// contrôle iOS, que la maquette ne dessine nulle part.
///
/// ```swift
/// BrandStepper(value: model.draft.copies, onDecrement: …, onIncrement: …)
/// ```
public struct BrandStepper: View {
    private let value: Int
    private let canDecrement: Bool
    private let canIncrement: Bool
    private let onDecrement: () -> Void
    private let onIncrement: () -> Void

    /// - Parameters:
    ///   - canDecrement: le « − » répond-il encore. À `false` il **reste
    ///     visible mais grisé** : un bouton qui disparaît au minimum fait
    ///     sauter la mise en page d'un cran à chaque bout de course.
    public init(
        value: Int,
        canDecrement: Bool = true,
        canIncrement: Bool = true,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) {
        self.value = value
        self.canDecrement = canDecrement
        self.canIncrement = canIncrement
        self.onDecrement = onDecrement
        self.onIncrement = onIncrement
    }

    /// Le cercle suit le corps de texte : à taille accessible, le compteur
    /// grandit avec le reste de l'écran au lieu de rester un jeton minuscule.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 43

    public var body: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            button(
                "minus",
                label: "Retirer un exemplaire",
                isEnabled: canDecrement,
                isFilled: false,
                action: onDecrement
            )

            Text(value, format: .number)
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)
                // Le chiffre roule d'une valeur à l'autre plutôt que de se
                // remplacer : c'est le seul endroit de l'écran qui bouge quand
                // on touche « + », il doit se voir.
                .contentTransition(.numericText(value: Double(value)))
                .monospacedDigit()
                // Une largeur tenue par le gabarit le plus large : sans elle,
                // passer de 9 à 10 décalerait les deux cercles.
                .frame(minWidth: side * 0.9)
                .accessibilityHidden(true)

            button(
                "plus",
                label: "Ajouter un exemplaire",
                isEnabled: canIncrement,
                isFilled: true,
                action: onIncrement
            )
        }
        .animation(.snappy(duration: 0.25), value: value)
        // Une seule cible pour VoiceOver, ajustable au balayage vertical —
        // c'est le geste que le système attend d'un compteur.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nombre d’exemplaires")
        .accessibilityValue(Text(value, format: .number))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { onIncrement() }
            case .decrement: if canDecrement { onDecrement() }
            @unknown default: break
            }
        }
    }

    /// - Parameter isFilled: le « + » est un aplat vert, le « − » un contour.
    ///   C'est la maquette, et c'est juste : ajouter est l'action qu'on propose.
    private func button(
        _ symbol: String,
        label: String,
        isEnabled: Bool,
        isFilled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.32, weight: .medium))
                .foregroundStyle(
                    isFilled ? MemoBookColor.onAction : MemoBookColor.action
                )
                .frame(width: side, height: side)
                .background {
                    Circle()
                        .fill(isFilled ? MemoBookColor.action : .clear)
                        .overlay {
                            if !isFilled {
                                Circle().strokeBorder(MemoBookColor.action, lineWidth: 1.5)
                            }
                        }
                }
                // La cible tactile ne descend jamais sous 44 pt, quelle que
                // soit la taille du dessin.
                .frame(
                    minWidth: MemoBookSpacing.minimumTapTarget,
                    minHeight: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .animation(.smooth(duration: 0.2), value: isEnabled)
        .accessibilityLabel(label)
    }
}

#Preview {
    @Previewable @State var value = 2

    return BrandStepper(
        value: value,
        canDecrement: value > 1,
        canIncrement: value < 20,
        onDecrement: { value -= 1 },
        onIncrement: { value += 1 }
    )
    .padding()
    .background(MemoBookColor.background)
}
