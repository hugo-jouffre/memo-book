import SwiftUI

/// Le champ de saisie **de plusieurs lignes** de MemoBook.
///
/// Le pendant de ``BrandTextField``, et la frontière entre les deux est nette :
/// un `BrandTextField` reçoit une **valeur** — un e-mail, un prénom, un code —,
/// un `BrandTextBox` reçoit un **texte**. Le premier est haut de 3,5 rem et ne
/// s'enroule pas ; le second part d'une hauteur de départ et grandit avec ce
/// qu'on y écrit.
///
/// Deux écrans l'emploient, et c'est ce qui l'a fait entrer ici : le message
/// qu'on écrit au support, et le texte de quatrième de couverture. La règle est
/// de factoriser à la **deuxième** occurrence.
///
/// ```swift
/// BrandTextBox("Ton message…", text: $message, focus: $isWriting)
/// ```
///
/// `TextField(axis: .vertical)` et non `TextEditor` : lui seul porte un texte
/// d'invite. Avec un `TextEditor`, il faudrait le superposer à la main — et
/// vivre avec les décalages de police que ça traîne.
public struct BrandTextBox: View {
    private let placeholder: String
    @Binding private var text: String
    private let focus: FocusState<Bool>.Binding
    private let minimumHeight: CGFloat
    private let lineSpan: ClosedRange<Int>
    private let accessibilityLabel: String?

    /// - Parameters:
    ///   - placeholder: l'exemple affiché tant que le champ est vide.
    ///   - minimumHeight: la hauteur de départ du cadre, en points. Il grandit
    ///     ensuite avec le texte.
    ///   - lineSpan: entre combien de lignes le cadre respire. La borne haute
    ///     compte : au-delà, c'est la feuille ou l'écran qui se mettrait à
    ///     défiler, et le bouton de validation partirait hors de vue.
    ///   - accessibilityLabel: ce que VoiceOver annonce. Par défaut le texte
    ///     d'invite, qui suffit quand il nomme ce qu'on attend.
    public init(
        _ placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding,
        minimumHeight: CGFloat = 133,
        lineSpan: ClosedRange<Int> = 4...10,
        accessibilityLabel: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.focus = focus
        self.minimumHeight = minimumHeight
        self.lineSpan = lineSpan
        self.accessibilityLabel = accessibilityLabel
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)

        TextField(placeholder, text: $text, axis: .vertical)
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.ink)
            .tint(MemoBookColor.action)
            .focused(focus)
            .lineLimit(resolvedSpan)
            .padding(MemoBookSpacing.snug)
            .frame(minHeight: minimumHeight * scale, alignment: .topLeading)
            .background(MemoBookColor.surface, in: shape)
            // Figma dessine #E6DAD0 ; `hairline` est l'encre à 10 %, qui tombe à
            // #E6DFD8 sur le crème — trois points d'écart sur un canal, et un
            // sixième filet de moins à tenir.
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .brandKeyboardDismissBar()
            .accessibilityLabel(accessibilityLabel ?? placeholder)
    }

    /// En taille accessible, le cadre montre moins de lignes : chacune est plus
    /// haute, et dix d'entre elles dépasseraient l'écran.
    private var resolvedSpan: ClosedRange<Int> {
        guard typeSize.isAccessibilitySize else { return lineSpan }
        return max(2, lineSpan.lowerBound - 1)...max(3, lineSpan.upperBound - 4)
    }
}
