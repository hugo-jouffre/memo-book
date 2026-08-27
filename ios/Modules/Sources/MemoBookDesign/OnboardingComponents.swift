import SwiftUI

// Les composants partagés des écrans d'entrée dans l'app, relevés sur les nœuds
// Figma du lot 1. Aucune valeur numérique nue ici non plus : tout passe par
// `Rem`, `MemoBookSpacing` et `MemoBookColor`.

// MARK: - Bouton

/// Le `Button` des maquettes : pleine largeur, 3 rem de haut, rayon 0.875 rem.
///
/// Deux états seulement, tels que Figma les dessine — *Mdp oublié* montre
/// l'actif (fond Green, ombre interne basse), *Sign Up* et *Login* montrent
/// l'inactif (fond Grey), parce que leur formulaire est vide.
public struct MemoBookButton: View {
    /// Icône posée **à gauche** du libellé, l'ensemble restant centré. C'est le
    /// dessin du CTA du *Welcome* (`arrow_right_alt`).
    public enum Leading {
        case none
        case asset(FigmaAsset)
    }

    private let title: String
    private let leading: Leading
    private let isEnabled: Bool
    private let isLoading: Bool
    private let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    public init(
        _ title: String,
        leading: Leading = .none,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.leading = leading
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    private var isTappable: Bool { isEnabled && !isLoading }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.xs) {
                if isLoading {
                    ProgressView().tint(MemoBookColor.onAction)
                } else if case .asset(let asset) = leading {
                    FigmaImage(asset).frame(width: unit * 1.5, height: unit * 1.5)
                }

                Text(title)
                    .font(MemoBookFont.button)
                    .foregroundStyle(MemoBookColor.onAction)
            }
            .frame(maxWidth: .infinity, minHeight: unit * 3)
            .background(
                isTappable ? MemoBookColor.action : MemoBookColor.actionDisabled,
                in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
            )
            // L'ombre interne basse du nœud actif : `inset 0 −4 20 rgba(0,0,0,.25)`.
            .overlay {
                if isTappable {
                    RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)
                        .stroke(Color.black.opacity(0.25), lineWidth: rem(0.25))
                        .blur(radius: rem(0.625))
                        .offset(y: rem(-0.25))
                        .mask(
                            RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)
                                .fill(
                                    LinearGradient(
                                        colors: [.black, .clear],
                                        startPoint: .bottom,
                                        endPoint: .center
                                    )
                                )
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Sélecteur Inscription / Connexion

/// Les deux onglets en tête de *Sign Up* et de *Login*.
///
/// C'est bien un sélecteur, pas une navigation : basculer d'un onglet à l'autre
/// change l'état d'un même écran. Le détail fonctionnel le demande explicitement.
public struct SegmentedToggle<Value: Hashable>: View {
    public struct Segment: Identifiable {
        public let value: Value
        public let title: String
        public var id: Value { value }

        public init(value: Value, title: String) {
            self.value = value
            self.title = title
        }
    }

    private let segments: [Segment]
    @Binding private var selection: Value

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    public init(segments: [Segment], selection: Binding<Value>) {
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let isSelected = segment.value == selection

                Button {
                    selection = segment.value
                } label: {
                    Text(segment.title)
                        .font(MemoBookFont.body)
                        .foregroundStyle(
                            isSelected ? MemoBookColor.onAction : MemoBookColor.ink
                        )
                        .tracking(MemoBookTracking.body)
                        .padding(.horizontal, rem(2.625))
                        .padding(.vertical, rem(0.625))
                        .frame(minHeight: unit * MemoBookMetric.minimumTapTarget)
                        .background(
                            isSelected ? MemoBookColor.action : .clear,
                            in: .rect(cornerRadius: rem(0.625))
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(rem(0.25))
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)
                .stroke(MemoBookColor.ink, lineWidth: MemoBookStroke.border)
        }
    }
}

// MARK: - Champ de saisie

/// Le champ des maquettes — 3 rem de haut, retrait 1.5 rem, rayon 0.875 rem.
///
/// Deux états, tous deux dessinés sur *Sign Up* : **au repos**, fond White et
/// le libellé en placeholder ; **actif ou rempli**, fond de l'écran, bordure
/// Green à 50 %, et le libellé remonte à cheval sur le trait — c'est le champ
/// *Prénom* du nœud `2553:27503`.
///
/// Le focus vient de l'appelant : c'est lui qui connaît l'ordre des champs de
/// son écran et enchaîne au clavier.
public struct MemoBookTextField<Field: Hashable>: View {
    public enum Kind {
        case plain
        case email
        case password
        case newPassword
        case givenName
        case familyName
    }

    private let title: String
    @Binding private var text: String
    private let kind: Kind
    private let submitLabel: SubmitLabel
    /// Message d'erreur affiché **sous le champ**, jamais en pop-up.
    private let error: String?
    private let field: Field
    private let focus: FocusState<Field?>.Binding
    private let onSubmit: () -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    public init(
        _ title: String,
        text: Binding<String>,
        field: Field,
        focus: FocusState<Field?>.Binding,
        kind: Kind = .plain,
        submitLabel: SubmitLabel = .next,
        error: String? = nil,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.title = title
        self._text = text
        self.field = field
        self.focus = focus
        self.kind = kind
        self.submitLabel = submitLabel
        self.error = error
        self.onSubmit = onSubmit
    }

    private var isFocused: Bool { focus.wrappedValue == field }
    private var isFloating: Bool { isFocused || !text.isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            input
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .tint(MemoBookColor.action)
                .focused(focus, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(kind != .plain)
                .textContentType(contentType)
                .keyboardType(kind == .email ? .emailAddress : .default)
                .padding(.horizontal, MemoBookSpacing.m)
                .frame(height: unit * 3)
                .background(
                    isFloating ? MemoBookColor.background : MemoBookColor.surface,
                    in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
                )
                .overlay {
                    if isFloating {
                        RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)
                            .stroke(borderColor, lineWidth: MemoBookStroke.border)
                    }
                }
                .overlay(alignment: .topLeading) { floatingLabel }
                .animation(.easeOut(duration: 0.15), value: isFloating)

            if let error {
                Text(error)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.error)
                    .padding(.leading, MemoBookSpacing.m)
                    .accessibilityLabel("Erreur : \(error)")
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        switch kind {
        case .password, .newPassword:
            SecureField(isFloating ? "" : title, text: $text)
        default:
            TextField(isFloating ? "" : title, text: $text)
        }
    }

    /// Le libellé remonté à cheval sur la bordure, sur un fond d'écran qui
    /// interrompt le trait — c'est le dessin de Figma, pas une décoration.
    @ViewBuilder
    private var floatingLabel: some View {
        if isFloating {
            Text(title)
                .font(MemoBookFont.link)
                .foregroundStyle(MemoBookColor.inkSecondary)
                .tracking(MemoBookTracking.tight)
                .padding(.horizontal, rem(0.375))
                .background(MemoBookColor.background)
                .padding(.leading, rem(1.1875))
                .offset(y: rem(-0.5))
        }
    }

    private var borderColor: Color {
        error == nil ? MemoBookColor.fieldBorderFocused : MemoBookColor.error
    }

    private var autocapitalization: TextInputAutocapitalization {
        switch kind {
        case .givenName, .familyName: .words
        case .plain: .sentences
        case .email, .password, .newPassword: .never
        }
    }

    private var contentType: UITextContentType? {
        switch kind {
        case .plain: nil
        case .email: .emailAddress
        case .password: .password
        case .newPassword: .newPassword
        case .givenName: .givenName
        case .familyName: .familyName
        }
    }
}

// MARK: - Pastilles

/// La pastille de bienvenue du *Welcome* : fond White, bordure et texte Green.
public struct Tagline: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(MemoBookFont.tagline)
            .foregroundStyle(MemoBookColor.action)
            .tracking(MemoBookTracking.tight)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, rem(0.125))
            .background(
                MemoBookColor.surface,
                in: .rect(cornerRadius: MemoBookSpacing.cardCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MemoBookSpacing.cardCornerRadius)
                    .stroke(MemoBookColor.action, lineWidth: MemoBookStroke.border)
            }
    }
}

/// La pastille numérotée des cartes bénéfices — 1.625 rem, fond Blue, chiffre
/// Sora SemiBold blanc.
public struct NumberBadge: View {
    private let number: Int

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    public init(_ number: Int) {
        self.number = number
    }

    public var body: some View {
        Text("\(number)")
            .font(MemoBookFont.badgeNumber)
            .foregroundStyle(MemoBookColor.onAction)
            .frame(width: unit * 1.625, height: unit * 1.625)
            .background(MemoBookColor.illustration, in: .circle)
    }
}

/// La pastille ronde qui porte le cadenas des trois écrans de mot de passe —
/// 4.125 rem de diamètre, icône 2.75 rem au centre.
public struct LockBadge: View {
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    public init() {}

    public var body: some View {
        FigmaImage(.lock)
            .frame(width: unit * 1.875, height: unit * 2.425)
            .frame(width: unit * 4.125, height: unit * 4.125)
            .background(MemoBookColor.illustrationSoft, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Chargement

/// La barre de progression du *Splash*.
///
/// Indéterminée : elle occupe l'attente du premier appel réseau, elle ne mesure
/// rien. 12.5 rem de large (Figma 198 → R2), 0.25 rem de haut — la convention
/// iOS, la maquette dessinant un trait de 7.
public struct LoaderBar: View {
    @State private var isAnimating = false

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(MemoBookColor.action)
                .frame(width: proxy.size.width * 0.4)
                .offset(x: isAnimating ? proxy.size.width * 0.6 : 0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .frame(width: rem(12.5), height: rem(0.25))
        .background(MemoBookColor.action.opacity(0.2), in: .capsule)
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Fournisseurs tiers

/// Un des trois boutons de connexion tierce, sous « Ou continue avec ».
///
/// Les logos sont des marques déposées : ils viennent de l'export Figma, ils ne
/// se redessinent pas et ne se recolorent pas.
public struct SocialButton: View {
    private let asset: FigmaAsset
    private let label: String
    private let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit

    public init(asset: FigmaAsset, label: String, action: @escaping () -> Void) {
        self.asset = asset
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            FigmaImage(asset)
                .frame(width: unit * 3, height: unit * 3)
                .frame(
                    minWidth: unit * MemoBookMetric.minimumTapTarget,
                    minHeight: unit * MemoBookMetric.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Le tracé décoratif posé en fond de *Splash*, *Welcome*, *Sign Up* et
/// *Login* : une route qui traverse le bas de l'écran.
public struct BackgroundRoute: View {
    public init() {}

    public var body: some View {
        FigmaImage(.backgroundRoute)
            .rotationEffect(.degrees(-90))
            .frame(width: rem(33.9), height: rem(44.2))
            .offset(x: rem(-1.72), y: rem(2.94))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
