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
/// Métriques verticales de General Sans, lues dans ses tables `hhea` et
/// `OS/2` et ramenées à la taille de police (em) : montante 1,010,
/// interligne 0,050, hauteur de capitale 0,718.
///
/// Elles servent à poser l'étiquette flottante sur le contour du champ. Le
/// cadre d'un `Text` n'est pas centré sur ses lettres : il réserve au-dessus
/// l'interligne, en dessous la place du jambage descendant. Aligner les cadres
/// laisserait donc l'étiquette visiblement basse. On vise le milieu des
/// capitales, seul repère que l'œil voit.
private enum GeneralSansMetrics {
    static let ascender: CGFloat = 1.010
    static let lineGap: CGFloat = 0.050
    static let capHeight: CGFloat = 0.718

    /// Du haut du cadre d'un `Text` au milieu de ses capitales.
    static let capCenterFromTop = ascender + lineGap - capHeight / 2
}

public struct BrandTextField<Field: Hashable>: View {
    /// Où se pose l'intitulé du champ. Un seul champ, deux mises en page —
    /// pas deux composants.
    public enum LabelPlacement {
        /// L'intitulé **est** le texte indicatif, et monte sur le contour dès
        /// que le champ sert. C'est le formulaire d'entrée dans l'app : une
        /// colonne de champs qu'on remplit d'affilée, où chaque étiquette au
        /// repos serait une ligne de plus à lire.
        case floating

        /// L'intitulé est écrit **au-dessus** du champ, en gras, et reste
        /// lisible pendant la saisie. C'est le dessin des feuilles modales :
        /// des champs peu nombreux, souvent préremplis, où le texte indicatif
        /// montre un **exemple de valeur** (« 7 rue Simon Fryd ») et non le nom
        /// du champ.
        case above
    }

    private let label: String
    @Binding private var text: String
    private let field: Field
    private let focus: FocusState<Field?>.Binding
    private let isSecure: Bool
    private let labelPlacement: LabelPlacement

    /// Exemple de valeur affiché tant que le champ est vide. N'a de sens qu'en
    /// ``LabelPlacement/above`` : en `floating`, c'est l'intitulé qui tient ce
    /// rôle, et un second texte le recouvrirait.
    private let placeholder: String?

    /// Texte d'aide affiché sous le champ. Contrairement à un indice glissé
    /// dans le texte indicatif, il ne disparaît pas quand on tape.
    private let hint: String?

    public init(
        _ label: String,
        text: Binding<String>,
        field: Field,
        focus: FocusState<Field?>.Binding,
        isSecure: Bool = false,
        labelPlacement: LabelPlacement = .floating,
        placeholder: String? = nil,
        hint: String? = nil
    ) {
        self.label = label
        self._text = text
        self.field = field
        self.focus = focus
        self.isSecure = isSecure
        self.labelPlacement = labelPlacement
        self.placeholder = placeholder
        self.hint = hint
    }

    /// Le mot de passe se dévoile à la demande. Sans ça, corriger une faute de
    /// frappe sur un clavier tactile relève du pari.
    @State private var isRevealed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var height = MemoBookSpacing.fieldHeight

    /// Taille de l'étiquette flottante. Suivie à la trace parce que le
    /// décalage qui la pose sur le contour s'exprime en fraction de police.
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12

    private var isFocused: Bool { focus.wrappedValue == field }
    private var isActive: Bool { isFocused || !text.isEmpty }

    /// L'aplat blanc du repos n'appartient qu'à l'étiquette flottante : c'est
    /// lui qui fait exister le champ avant qu'on le touche. Étiquette au-dessus,
    /// c'est le mot qui remplit ce rôle, et le contour suffit.
    private var isOutlined: Bool { labelPlacement == .above || isActive }

    private var showsPlaceholder: Bool {
        switch labelPlacement {
        case .floating: !isActive
        case .above: text.isEmpty
        }
    }

    /// L'intitulé sert de texte indicatif en `floating`. En `above`, le texte
    /// indicatif est un exemple de valeur — et l'intitulé, s'il n'y en a pas.
    private var placeholderText: String {
        switch labelPlacement {
        case .floating: label
        case .above: placeholder ?? label
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            if labelPlacement == .above {
                Text(label)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    // Le champ porte déjà ce mot comme `accessibilityLabel` :
                    // le laisser lisible ferait entendre l'intitulé deux fois.
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                input
                    .frame(height: height)
                    .padding(.horizontal, 20)
                    .background(isOutlined ? Color.clear : MemoBookColor.surface, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            isFocused ? MemoBookColor.action : MemoBookColor.separator,
                            lineWidth: isOutlined ? 1 : 0
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
    }

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    @ViewBuilder
    private var input: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ZStack(alignment: .leading) {
                // Texte indicatif dessiné à la main : le `prompt` de SwiftUI ne
                // se met pas à la typographie de la marque.
                if showsPlaceholder {
                    Text(placeholderText)
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
        if labelPlacement == .floating, isActive {
            Text(label)
                .font(MemoBookFont.caption)
                .foregroundStyle(isFocused ? MemoBookColor.action : MemoBookColor.inkSecondary)
                // La pastille prend la couleur du fond d'écran : c'est elle qui
                // « coupe » le contour pour laisser passer l'étiquette.
                .padding(.horizontal, 6)
                .background(MemoBookColor.background)
                .padding(.leading, 14)
                // Un `alignmentGuide(.top)` serait le geste idiomatique, mais
                // il reste sans effet sur le contenu d'un `overlay` : l'étiquette
                // se posait sous le trait au lieu de le chevaucher. Un décalage
                // explicite fait le travail, et reste exact au Dynamic Type
                // puisqu'il se calcule sur la taille réelle de l'étiquette.
                .offset(y: -labelSize * GeneralSansMetrics.capCenterFromTop)
                .accessibilityHidden(true)
                .transition(.opacity.combined(with: .offset(y: 6)))
        }
    }
}
