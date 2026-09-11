import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les personnalisations du carnet : ce qui décide de sa mise en page.
///
/// On y arrive par la ligne « Style du carnet » des paramètres du voyage. C'est
/// l'écran le plus long de l'app, et il est volontairement rangé en **cinq
/// paquets** plutôt qu'en une liste : les couvertures, la forme de la page, les
/// décors, les typographies, et les extras. On ne règle pas une typographie en
/// même temps qu'on choisit un nombre de pages.
///
/// Les extras sont les seuls à porter un interrupteur, et c'est ce que dessine
/// la maquette : ils **ajoutent** quelque chose au carnet — un quiz, des pages
/// blanches, une grille de mots fléchés — là où les autres réglages ne font que
/// choisir entre des valeurs. Un interrupteur répond à « est-ce que j'en veux »,
/// une ligne à « lequel ».
///
/// ⚠️ **Seuls les trois extras s'enregistrent** aujourd'hui. Les onze autres
/// lignes montrent leur valeur et ne mènent nulle part : leurs écrans de choix
/// ne sont pas dessinés, et on ne les invente pas (R3). Signalé (T78).
public struct BookCustomisationView: View {
    private let onIntent: (BookCustomisationIntent) -> Void

    @State private var model: BookCustomisationModel

    public init(
        model: BookCustomisationModel,
        onIntent: @escaping (BookCustomisationIntent) -> Void
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(title: BookCopy.Customisation.title)

                Text(BookCopy.Customisation.intro)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                coversRow
                layoutGroup
                decorGroup
                typographyGroup
                extras

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }
            }
            .animation(.snappy(duration: 0.25), value: model.customisation == nil)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
    }

    // MARK: - Les couvertures

    /// La seule ligne de l'écran qui porte une image : les deux couvertures, vues
    /// de trois quarts.
    ///
    /// Elle est en tête parce que c'est la seule chose qu'on voit du carnet
    /// **avant** de l'ouvrir — et la seule que quelqu'un d'autre verra sur une
    /// étagère.
    private var coversRow: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return Button { onIntent(.openCovers) } label: {
            HStack(spacing: MemoBookSpacing.snug) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                    Text(BookCopy.Customisation.covers)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                    Text(BookCopy.Customisation.coversDetail)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MemoBookSpacing.xs)

                CoverStack(isLoading: model.isLoading)
                BrandChevron()
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(BookCopy.Customisation.covers). \(BookCopy.Customisation.coversDetail)")
    }

    // MARK: - Les quatre groupes de lignes

    private var layoutGroup: some View {
        let customisation = model.customisation

        return BrandRowGroup {
            BrandRow(
                BookCopy.Customisation.photoTextRatio,
                value: customisation?.photoTextLabel ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
            BrandRow(
                BookCopy.Customisation.targetPageCount,
                value: customisation?.targetPageLabel ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
        }
    }

    private var decorGroup: some View {
        let customisation = model.customisation

        return BrandRowGroup {
            BrandRow(
                BookCopy.Customisation.funFacts,
                value: customisation.map { BookCopy.Customisation.toggleValue($0.funFactsEnabled) }
                    ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
            BrandRow(
                BookCopy.Customisation.rules,
                value: customisation.map { BookCopy.Customisation.toggleValue($0.rulesEnabled) }
                    ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
            BrandRow(
                BookCopy.Customisation.decorations,
                value: customisation?.decorationLabel ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
        }
    }

    /// Les quatre familles du carnet.
    ///
    /// Les valeurs sont des **noms de police**, affichés tels quels : c'est le
    /// gabarit d'impression qui les résout, et les rendre dans leur propre
    /// dessin demanderait d'embarquer quatre polices de plus dans l'app pour
    /// quatre bouts de ligne.
    private var typographyGroup: some View {
        let customisation = model.customisation

        return BrandRowGroup {
            BrandRow(
                BookCopy.Customisation.fontTitle,
                value: customisation?.fontDisplay ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
            BrandRow(
                BookCopy.Customisation.fontDisplay,
                value: customisation?.fontTitle ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
            BrandRow(
                BookCopy.Customisation.fontHand,
                value: customisation?.fontHand ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
            BrandRow(
                BookCopy.Customisation.fontFacts,
                value: customisation?.fontFacts ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading
            )
        }
    }

    // MARK: - Les extras

    private var extras: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            Text(BookCopy.Customisation.extrasSection)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            CustomisationToggleCard(
                title: BookCopy.Customisation.quizTitle,
                detail: BookCopy.Customisation.quizDetail,
                isOn: binding(\.quizEnabled, model.setQuiz)
            )
            CustomisationToggleCard(
                title: BookCopy.Customisation.freeZonesTitle,
                detail: BookCopy.Customisation.freeZonesDetail,
                isOn: binding(\.freeZonesEnabled, model.setFreeZones)
            )
            CustomisationToggleCard(
                title: BookCopy.Customisation.crosswordTitle,
                detail: BookCopy.Customisation.crosswordDetail,
                isOn: binding(\.crosswordEnabled, model.setCrossword)
            )
        }
        // Les interrupteurs **agissent** : les basculer avant que les valeurs
        // soient là enverrait un état qu'on n'a pas lu.
        .disabled(model.customisation == nil)
    }

    /// La liaison d'un extra : elle lit le modèle et lui repasse la bascule.
    ///
    /// Une vue ne doit pas pouvoir poser une valeur sans qu'elle parte au
    /// serveur — d'où le passage par une méthode plutôt que par un `customisation`
    /// ouvert en écriture.
    private func binding(
        _ keyPath: KeyPath<BookCustomisation, Bool>,
        _ set: @escaping (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model.customisation?[keyPath: keyPath] ?? false },
            set: set
        )
    }
}

/// Ce que les personnalisations demandent à l'app d'ouvrir.
public enum BookCustomisationIntent: Sendable, Hashable {
    /// L'aperçu et la personnalisation des deux couvertures.
    case openCovers
}

// MARK: - Les deux blocs propres à l'écran

/// Les deux couvertures vues de trois quarts, l'une derrière l'autre.
///
/// La maquette pose un rendu 3D de deux livres ; on en garde l'**idée** — deux
/// plats qui se recouvrent, légèrement tournés — avec les moyens de l'app. Un
/// rendu 3D importé serait une image figée qui mentirait dès que le voyageur
/// change sa couverture, alors que ces deux plats-là afficheront sa photo le
/// jour où elle existe. Écart assumé et signalé (T79).
private struct CoverStack: View {
    let isLoading: Bool

    /// Taille **fixe**, hors Dynamic Type : c'est une image, pas du texte.
    private static let height: CGFloat = 64
    private static let ratio: CGFloat = 1 / 1.414

    var body: some View {
        ZStack {
            plate(MemoBookColor.separator.opacity(0.5))
                .rotationEffect(.degrees(-8))
                .offset(x: -10)

            plate(MemoBookColor.action)
                .rotationEffect(.degrees(6))
                .offset(x: 6)
        }
        .frame(width: Self.height * Self.ratio + 26, height: Self.height)
        .opacity(isLoading ? 0.35 : 1)
        .accessibilityHidden(true)
    }

    private func plate(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: Self.height * Self.ratio, height: Self.height)
            .overlay(alignment: .leading) {
                // Le dos du livre : un filet plus sombre le long du pli, qui
                // suffit à faire lire le rectangle comme une couverture.
                Rectangle()
                    .fill(.black.opacity(0.15))
                    .frame(width: 3)
            }
            .clipShape(.rect(cornerRadius: 3))
            .brandShadow(.soft)
    }
}

/// Une carte d'extra : ce que l'option ajoute, et son interrupteur.
///
/// Ce n'est pas une ``BrandRow`` parce que son texte fait trois lignes et
/// **explique** au lieu de nommer une valeur. Une ligne de réglage qui explique
/// n'est plus une ligne de réglage — c'est déjà l'argument du Tricount sur
/// l'écran précédent.
private struct CustomisationToggleCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
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
                .font(MemoBookFont.h3)
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

#Preview("Personnalisations du carnet") {
    NavigationStack {
        BookCustomisationView(model: BookCustomisationModel(tripId: "preview")) { _ in }
    }
}

#Preview("Personnalisations — AX3") {
    NavigationStack {
        BookCustomisationView(model: BookCustomisationModel(tripId: "preview")) { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
