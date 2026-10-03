import SwiftUI

/// **Le bandeau d'une limite** : une phrase rouge sur un aplat rouge doux,
/// posée juste au-dessus de la barre qu'elle concerne (Hugo, 03/10/2026).
///
/// Il est né du crédit du jour : pendant qu'on parle, il paraît à trente
/// secondes de la limite et compte à rebours ; à cinq secondes, il **pulse
/// doucement par sa taille** ; le crédit épuisé, il dit « Crédit du jour
/// épuisé · Reviens demain, ou passe en illimité » et s'ouvre sur l'offre.
///
/// Ce n'est ni ``ErrorBanner`` — rien n'a raté, il n'y a rien à réessayer — ni
/// ``BrandNotice`` — il ne décrit pas un état des choses, il prévient d'une
/// échéance. D'où le rouge, mais **doux** : le titre et le pictogramme
/// portent ``MemoBookColor/error``, l'aplat ``MemoBookColor/errorSoft``. Le
/// détail, en petit corps sans graisse, passe à l'encre (03/10/2026) : le
/// rouge sur ce rose ne fait que 3,7:1, sous le seuil de 4,5:1 qu'un texte de
/// ce corps demande — l'encre y tient 12:1.
///
/// ⚠️ **Il s'empile, il ne flotte pas.** Posé en calque au-dessus d'une barre,
/// il se dessinerait très bien et ne recevrait aucune touche : SwiftUI ne teste
/// pas les doigts hors du cadre de la vue qui porte le calque. Celui qui
/// l'emploie le met donc dans la pile du pied, à la place de ce qu'il remplace.
///
/// **La pulsation s'éteint en Reduce Motion** : plus d'échelle, seulement une
/// respiration d'opacité à peine visible — ce qui bouge de lui-même est
/// exactement ce que ce réglage demande d'éteindre.
///
/// ⚠️ **Sans maquette** (T249) : coins, marges et polices sont ceux du design
/// system, la couleur celle que le contrat a fixée. À dessiner dans Figma, ou
/// à valider tel quel.
public struct BrandLimitBanner: View {
    private let title: String
    private let detail: String?
    private let systemImage: String
    private let isPulsing: Bool
    private let action: (() -> Void)?
    private let accessibilityHint: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: la phrase qui compte — le compte à rebours, ou « Crédit du
    ///     jour épuisé ».
    ///   - detail: ce qu'on peut y faire, sous la phrase, plus discret.
    ///   - systemImage: le pictogramme, un symbole SF.
    ///   - isPulsing: il ne reste presque plus rien — voir la note sur la
    ///     pulsation.
    ///   - accessibilityHint: ce que fait le toucher, pour VoiceOver.
    ///   - action: le bandeau se touche — il mène à l'offre. `nil` : il se lit
    ///     seulement.
    public init(
        _ title: String,
        detail: String? = nil,
        systemImage: String = "hourglass",
        isPulsing: Bool = false,
        accessibilityHint: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.isPulsing = isPulsing
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var content: some View {
        HStack(alignment: .center, spacing: MemoBookSpacing.xs) {
            Image(systemName: systemImage)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.error)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.error)
                    // Le compte à rebours change de chiffre chaque seconde :
                    // les chiffres à chasse fixe l'empêchent de faire danser la
                    // phrase.
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                if let detail {
                    Text(detail)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.ink)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if action != nil {
                Image(brand: "IconChevron")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(MemoBookColor.error)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.vertical, MemoBookSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget, alignment: .leading)
        .background(
            MemoBookColor.errorSoft,
            in: .rect(cornerRadius: MemoBookSpacing.cornerRadius, style: .continuous)
        )
        .contentShape(.rect(cornerRadius: MemoBookSpacing.cornerRadius, style: .continuous))
        // **La pulsation** : 1,00 ↔ 1,03 en 0,9 s, aller et retour, tant qu'il
        // reste moins de cinq secondes. Un `PhaseAnimator` sans déclencheur
        // tourne en boucle : hors pulsation, une seule phase l'arrête — le
        // bandeau « épuisé » peut rester affiché des heures.
        .phaseAnimator(isPulsing ? [false, true] : [false]) { view, swollen in
            view
                .scaleEffect(isPulsing && !reduceMotion && swollen ? 1.03 : 1)
                .opacity(isPulsing && reduceMotion && swollen ? 0.9 : 1)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
    }
}

// MARK: - Aperçus

#Preview("Bandeau de limite — ses trois états") {
    VStack(spacing: MemoBookSpacing.s) {
        BrandLimitBanner("Plus que 24 secondes avant la limite du jour")
        BrandLimitBanner("Plus que 3 secondes avant la limite du jour", isPulsing: true)
        BrandLimitBanner(
            "Crédit du jour épuisé",
            detail: "Reviens demain, ou passe en illimité",
            systemImage: "moon.zzz",
            action: {}
        )
    }
    .padding(MemoBookSpacing.screenMargin)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
