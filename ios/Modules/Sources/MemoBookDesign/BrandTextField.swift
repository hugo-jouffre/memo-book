import SwiftUI

/// Le champ de saisie de l'app. Un seul dessin pour tous les formulaires.
///
/// Deux états, comme dans la maquette :
///
/// - **au repos** : aplat blanc, pas de contour, l'intitulé sert de texte
///   indicatif à l'intérieur ;
/// - **actif** (au focus, ou dès qu'il contient quelque chose) : le fond
///   redevient transparent, un contour apparaît, et l'intitulé monte se poser à
///   cheval sur ce contour.
///
/// L'entaille dans le contour n'est pas dessinée : l'étiquette porte une
/// pastille de la couleur du fond d'écran, qui masque le trait derrière elle.
///
/// Le focus appartient à l'écran, pas au champ : c'est ce qui permet à la
/// touche « suivant » du clavier de passer d'un champ à l'autre.
///
/// ```swift
/// @FocusState private var focus: Field?
///
/// BrandTextField("Email", text: $email, field: .email, focus: $focus)
///     .textContentType(.emailAddress)
/// ```
public struct BrandTextField<Field: Hashable>: View {
    private let label: String
    @Binding private var text: String
    private let field: Field
    private let focus: FocusState<Field?>.Binding
    private let isSecure: Bool

    /// Texte d'aide affiché sous le champ. Contrairement à un indice glissé
    /// dans le texte indicatif, il ne disparaît pas quand on tape.
    private let hint: String?

    public init(
        _ label: String,
        text: Binding<String>,
        field: Field,
        focus: FocusState<Field?>.Binding,
        isSecure: Bool = false,
        hint: String? = nil
    ) {
        self.label = label
        self._text = text
        self.field = field
        self.focus = focus
        self.isSecure = isSecure
        self.hint = hint
    }

    /// Le mot de passe se dévoile à la demande. Sans ça, corriger une faute de
    /// frappe sur un clavier tactile relève du pari.
    @State private var isRevealed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var height = MemoBookSpacing.fieldHeight

    private var isFocused: Bool { focus.wrappedValue == field }
    private var isActive: Bool { isFocused || !text.isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            input
                .frame(height: height)
                .padding(.horizontal, 20)
                .background(isActive ? Color.clear : MemoBookColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isFocused ? MemoBookColor.action : MemoBookColor.separator,
                        lineWidth: isActive ? 1 : 0
                    )
                }
                .overlay(alignment: .topLeading) { floatingLabel }
                .contentShape(shape)
                .onTapGesture { focus.wrappedValue = field }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
                .animation(reduceMotion ? .none : .snappy(duration: 0.22), value: isActive)
                .animation(reduceMotion ? .none : .snappy(duration: 0.22), value: isFocused)

            if let hint {
                Text(hint)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkSecondary)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var shape: RoundedRectangle {
        .rect(cornerRadius: 16)
    }

    @ViewBuilder
    private var input: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ZStack(alignment: .leading) {
                // Texte indicatif dessiné à la main : le `prompt` de SwiftUI ne
                // se met pas à la typographie de la marque.
                if !isActive {
                    Text(label)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.inkSecondary)
                        .accessibilityHidden(true)
                }

                if isSecure, !isRevealed {
                    SecureField("", text: $text)
                        .focused(focus, equals: field)
                } else {
                    TextField("", text: $text)
                        .focused(focus, equals: field)
                }
            }
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.ink)
            .tint(MemoBookColor.action)

            if isSecure {
                Button {
                    isRevealed.toggle()
                    // Le champ change de type en se dévoilant ; sans ça le
                    // clavier se referme au milieu de la saisie.
                    focus.wrappedValue = field
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(MemoBookColor.inkSecondary)
                }
                .accessibilityLabel(isRevealed ? "Masquer le mot de passe" : "Afficher le mot de passe")
            }
        }
    }

    @ViewBuilder
    private var floatingLabel: some View {
        if isActive {
            Text(label)
                .font(MemoBookFont.caption)
                .foregroundStyle(isFocused ? MemoBookColor.action : MemoBookColor.inkSecondary)
                // La pastille prend la couleur du fond d'écran : c'est elle qui
                // « coupe » le contour pour laisser passer l'étiquette.
                .padding(.horizontal, 6)
                .background(MemoBookColor.background)
                .padding(.leading, 14)
                .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                .accessibilityHidden(true)
                .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }
}
