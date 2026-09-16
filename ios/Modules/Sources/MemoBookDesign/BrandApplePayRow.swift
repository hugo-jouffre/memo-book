import SwiftUI

/// La ligne Apple Pay, dans le mode de paiement du profil comme dans celui de
/// la commande.
///
/// Elle vit ici et non dans un écran parce qu'elle porte une **règle de marque
/// tierce** : le logotype est celui d'Apple, posé tel quel. Jamais de
/// `renderingMode(.template)`, jamais recoloré, jamais recomposé à partir du
/// symbole système et du mot « Pay » — c'est ce qu'on faisait faute d'asset, et
/// les règles de marque d'Apple l'interdisent. Une seule implémentation, donc
/// une seule occasion de se tromper.
///
/// Le cadre noir est celui de la maquette, et c'est aussi la façon dont Apple
/// veut qu'on présente sa marque.
public struct BrandApplePayRow: View {
    private let isSelected: Bool
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - isSelected: Apple Pay est le moyen retenu. Le cadre passe alors au
    ///     **bleu** de la marque sur un aplat bleu transparent — exactement ce
    ///     que fait une ``BrandOptionRow`` cochée, parce que c'est le même
    ///     geste : choisir un moyen de paiement dans une liste. Il portait le
    ///     vert d'action et aucun fond, et la ligne retenue ne se distinguait
    ///     donc pas des cartes au-dessus d'elle (Hugo, 16/09/2026).
    ///   - action: `nil` pour une ligne qui **montre** sans se choisir — c'est
    ///     le cas du profil tant que le paiement n'existe pas. La ligne n'est
    ///     alors pas un bouton, et VoiceOver ne l'annonce pas comme tel.
    public init(isSelected: Bool = false, action: (() -> Void)? = nil) {
        self.isSelected = isSelected
        self.action = action
    }

    /// La hauteur du logotype suit le corps de texte : il se lit comme un mot
    /// de la ligne, pas comme une image posée dedans.
    @ScaledMetric(relativeTo: .body) private var markHeight: CGFloat = 22

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    public var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Apple Pay, disponible")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            row
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Apple Pay, disponible")
        }
    }

    private var row: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            Text("ApplePay")
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
            Text("disponible")
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
            Spacer(minLength: MemoBookSpacing.xs)
            mark
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.s - 2)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        // Le même aplat que ``BrandOptionRow`` retenue : le bleu de la marque à
        // 35 %, assez pour que la ligne se détache sans avaler le logotype
        // d'Apple, qui garde ses couleurs.
        .background(isSelected ? MemoBookColor.outline.opacity(0.35) : Color.clear, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? MemoBookColor.outline : MemoBookColor.ink,
                lineWidth: 2
            )
        }
        .contentShape(shape)
        .animation(.smooth(duration: 0.2), value: isSelected)
    }

    private var mark: some View {
        Image(brand: "LogoApplePay")
            .resizable()
            .scaledToFit()
            // Le rapport du fichier est 48 × 24 : on ne fixe que la hauteur, la
            // largeur suit. Une marque déformée n'est plus la marque.
            .frame(height: markHeight)
            .accessibilityHidden(true)
    }
}
