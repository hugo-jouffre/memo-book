import SwiftUI

/// Une carte à interrupteur : ce que l'option ajoute, et sa bascule.
///
/// À ne pas confondre avec la ligne à interrupteur de ``BrandRowGroup`` : celle-là
/// **nomme** un réglage sur une ligne, celle-ci l'**explique** sur deux ou trois.
/// Une ligne de réglage qui explique n'est plus une ligne de réglage — et c'est
/// le dessin que la maquette donne aux extras du carnet, aux quatre alertes d'un
/// voyage, et aux deux feuilles « Fun Facts » et « Pointillés ».
///
/// ```swift
/// BrandToggleCard(
///     title: "Rappel d’écriture",
///     detail: "Alerte selon le rythme du récit choisi",
///     isOn: $wantsWritingReminder
/// )
/// ```
public struct BrandToggleCard: View {
    private let title: String
    private let detail: String
    @Binding private var isOn: Bool

    public init(title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug)

        return content
            .padding(MemoBookSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MemoBookColor.surface, in: shape)
            // Figma dessine #E6DAD0, un beige ; `hairline` est l'encre à 10 %,
            // qui tombe à #E6DFD8 sur le crème. Trois points d'écart sur un
            // canal : on garde le token plutôt qu'une sixième valeur de filet.
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
    }

    /// En taille accessible, l'interrupteur passe **sous** le texte : à côté
    /// d'un paragraphe de trois lignes, il ne laisse plus que deux mots par
    /// ligne.
    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                text
                toggle
            }
        } else {
            HStack(alignment: .center, spacing: MemoBookSpacing.s) {
                text
                toggle
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
            Text(detail)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Un vrai `Toggle` et non un dessin : c'est lui qui apporte le geste de
    /// balayage, l'annonce « activé / désactivé » et le comportement attendu par
    /// VoiceOver — même parti pris que ``BrandRowGroup``.
    private var toggle: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .tint(MemoBookColor.action)
            .accessibilityLabel(title)
            .accessibilityHint(detail)
    }
}

#Preview("Carte à interrupteur") {
    @Previewable @State var isOn = true

    return VStack(spacing: MemoBookSpacing.snug) {
        BrandToggleCard(
            title: "Insérer des Fun facts",
            detail: "Encarts de culture générale toutes les 3 pages pour agrémenter vos récits.",
            isOn: $isOn
        )
        BrandToggleCard(
            title: "Rappel d’écriture",
            detail: "Alerte selon le rythme du récit choisi",
            isOn: $isOn
        )
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoBookColor.surface)
    .environment(\.colorScheme, .light)
}
