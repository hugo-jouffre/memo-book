import SwiftUI

/// **Le** champ de recherche de MemoBook : une loupe, ce qu'on tape, et la
/// croix qui efface.
///
/// À ne pas confondre avec ``BrandTextField``, qui est le champ des
/// **formulaires** — un libellé, une valeur qu'on saisit, une erreur possible,
/// et un clavier qui enchaîne les champs d'un écran. Celui-ci ne saisit rien :
/// il **filtre ce qui est en dessous**, à chaque caractère, et son contenu ne
/// part nulle part. D'où un dessin à lui — capsule, loupe en tête, pas de
/// libellé — et un enchaînement de clavier qui s'arrête à lui.
///
/// **La croix n'apparaît qu'une fois qu'il y a quelque chose à effacer**, et
/// elle efface sans rendre le clavier : on efface pour retaper, pas pour
/// partir. C'est le comportement du champ de recherche du système, et c'est le
/// seul endroit où on le recopie plutôt que de le redessiner (R6).
public struct BrandSearchField: View {
    private let placeholder: String
    @Binding private var text: String
    private let onClear: (() -> Void)?

    /// - Parameters:
    ///   - placeholder: ce que le champ propose quand il est vide. Il dit
    ///     **où** l'on cherche, pas « Rechercher » : « Rechercher une
    ///     question » se lit, « Rechercher » se devine.
    ///   - onClear: ce que fait la croix en plus de vider le texte. `nil` la
    ///     laisse simplement vider.
    public init(_ placeholder: String, text: Binding<String>, onClear: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onClear = onClear
    }

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = 18

    private var shape: Capsule { Capsule() }

    public var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: glyphSide, weight: .regular))
                .foregroundStyle(MemoBookColor.inkMuted)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .tint(MemoBookColor.action)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // Un champ de recherche ne valide rien : le clavier propose de
                // se refermer, pas d'aller au champ suivant — il n'y en a pas.
                .submitLabel(.search)
                .onSubmit { isFocused = false }
                .focused($isFocused)
                .accessibilityLabel(placeholder)

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: glyphSide, weight: .regular))
                        .foregroundStyle(MemoBookColor.inkMuted)
                        // Le dessin fait 18, la cible 2.75 rem : R7. Elle
                        // déborde la capsule vers le haut et le bas, ce qui ne
                        // gêne personne — rien n'est posé au-dessus.
                        .frame(
                            width: MemoBookSpacing.minimumTapTarget,
                            height: MemoBookSpacing.minimumTapTarget
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
                .transition(.opacity)
                // La croix ne pousse pas le champ en apparaissant : elle est
                // ramenée dans la largeur qu'elle occupait déjà.
                .frame(width: MemoBookSpacing.minimumTapTarget, height: glyphSide)
            }
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .background(MemoBookColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(
                isFocused ? MemoBookColor.action : MemoBookColor.hairline,
                lineWidth: isFocused ? 1.5 : 1
            )
        }
        .animation(.smooth(duration: 0.2), value: isFocused)
        .animation(.smooth(duration: 0.2), value: text.isEmpty)
    }
}

#Preview("Champ de recherche") {
    struct Harness: View {
        @State private var empty = ""
        @State private var filled = "remboursement"

        var body: some View {
            VStack(spacing: MemoBookSpacing.s) {
                BrandSearchField("Rechercher une question", text: $empty)
                BrandSearchField("Rechercher une question", text: $filled)
            }
            .padding(MemoBookSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MemoBookColor.background)
            .environment(\.colorScheme, .light)
        }
    }

    return Harness()
}
