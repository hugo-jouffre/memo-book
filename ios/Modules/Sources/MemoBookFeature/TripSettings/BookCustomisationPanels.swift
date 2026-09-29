import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les cinq réglages de la personnalisation du carnet, un par pastille — ce qui
/// défile sous les deux pages (V3 de la maquette, 29/09/2026).
///
/// **Le réglage part au geste.** Il n'y a plus de bouton « Valider » : les
/// feuilles en avaient un qui ne faisait que fermer, et il n'y a plus rien à
/// fermer. C'est le contrat des réglages partout dans l'app.
///
/// Chaque panneau s'ouvre sur sa phrase d'explication — le gris de la
/// maquette — puis sur son contrôle. Les quatre qui proposent des choix les
/// posent dans une carte papier (`3595:23854`).

// MARK: - Ratio média

/// « Ratio media » — la part de photo dans la page, de 0 à 100 % (`3595:23823`).
struct BookRatioPanel: View {
    let model: BookCustomisationModel

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            BookPanelLead(BookCopy.Ratio.subtitle)
            value
            slider
        }
        .disabled(model.customisation == nil)
    }

    /// « 50 / 50 », et ce que l'équilibre vaut. C'est **ici** qu'on lit ce
    /// qu'on règle : le curseur ne fait que le poser.
    private var value: some View {
        VStack(spacing: MemoBookSpacing.xs - 2) {
            Text(BookCopy.Ratio.value(ratio.wrappedValue))
                // Sora à 24 (`3595:23828`), et non le solde de 48 des cagnottes.
                .font(MemoBookFont.figure)
                // Les chiffres ne dansent pas : sans chasse fixe, la valeur se
                // décale à chaque cran du curseur.
                .monospacedDigit()
                .foregroundStyle(MemoBookColor.ink)

            Text(BookCopy.Ratio.quality(ratio.wrappedValue))
                .font(MemoBookFont.tagline)
                .foregroundStyle(MemoBookColor.outline)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.2), value: ratio.wrappedValue)
        .accessibilityHidden(true)
    }

    private var slider: some View {
        BrandSlider(
            value: ratio,
            in: 0...100,
            step: 25,
            ticks: ["0%", "25%", "50%", "75%", "100%"],
            leadingLabel: BookCopy.Ratio.less,
            trailingLabel: BookCopy.Ratio.more,
            voiceLabel: BookCopy.Ratio.title,
            voiceValue: { "\($0) % de photos, \(100 - $0) % de texte" }
        )
    }

    private var ratio: Binding<Int> {
        Binding(
            get: { model.customisation?.photoTextRatio ?? 50 },
            set: { model.setPhotoTextRatio($0) }
        )
    }
}

// MARK: - Nombre de pages

/// « Nmb de pages » — quatre paliers, dont les projections suivent la durée
/// du voyage (`3595:23917`).
struct BookPagesPanel: View {
    let model: BookCustomisationModel

    /// Le nombre saisi à la main, quand on choisit « Personnalisé ».
    @State private var customPages: Double = 60
    @State private var isCustomising = false

    private var days: Int? { model.tripDays }

    private var selection: BookPageTarget {
        guard let pages = model.customisation?.targetPageCount else { return .standard }
        return isCustomising ? .custom : BookPageTarget.matching(pageCount: pages, tripDays: days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BookPanelLead(BookCopy.Pages.subtitle)

                // La ligne verte de la maquette : elle dit **sur quoi** les
                // trois projections sont faites. Le nœud écrit « 2 mois » en
                // dur ; ici c'est la durée du voyage qu'on regarde — c'est la
                // note « Logique » du nœud (`3443:10070`).
                if let duration {
                    Text(BookCopy.Pages.estimates(for: duration))
                        .font(MemoBookFont.label)
                        .foregroundStyle(MemoBookColor.action)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            BookPanelCard {
                ForEach(BookPageTarget.allCases) { target in
                    BrandOptionRow(
                        target.label(forTripDays: days),
                        subtitle: target.detail,
                        isSelected: selection == target
                    ) {
                        choose(target)
                    }
                }

                if isCustomising { customPageStepper }
            }
        }
        .animation(.snappy(duration: 0.25), value: isCustomising)
        .disabled(model.customisation == nil)
        .onAppear {
            guard let pages = model.customisation?.targetPageCount else { return }
            customPages = Double(pages)
            isCustomising = BookPageTarget.matching(pageCount: pages, tripDays: days) == .custom
        }
    }

    /// « 2 mois », « 12 jours » — la durée du voyage, écrite comme on la dit.
    private var duration: String? {
        guard let days else { return nil }
        if days >= 60 { return "\(days / 30) mois" }
        if days >= 14 { return "\(days / 7) semaines" }
        return days == 1 ? "1 jour" : "\(days) jours"
    }

    /// Le nombre exact, quand aucun palier ne convient. Un pas de dix : un
    /// carnet se relie par cahiers, et « 63 pages » ne veut rien dire de plus
    /// que « 60 ».
    private var customPageStepper: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            HStack {
                Text(BookCopy.Pages.customTitle)
                    .font(MemoBookFont.tagline)
                    .foregroundStyle(MemoBookColor.inkMuted)
                Spacer(minLength: MemoBookSpacing.xs)
                Text("\(Int(customPages))")
                    .font(MemoBookFont.figure)
                    .monospacedDigit()
                    .foregroundStyle(MemoBookColor.ink)
            }

            Slider(
                value: $customPages,
                in: 30...180,
                step: 10,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    model.setTargetPageCount(Int(customPages))
                }
            )
            .tint(MemoBookColor.action)
            .accessibilityLabel(BookCopy.Pages.customTitle)
            .accessibilityValue("\(Int(customPages)) pages")
        }
        .padding(.horizontal, MemoBookSpacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func choose(_ target: BookPageTarget) {
        isCustomising = target == .custom
        guard let pages = target.pageCount(forTripDays: days) else {
            // « Personnalisé » n'a pas de valeur à lui : on garde celle qui est
            // déjà posée et on ouvre le curseur dessous.
            return
        }
        customPages = Double(pages)
        model.setTargetPageCount(pages)
    }
}

// MARK: - Décorations & stickers

/// « Décorations & stickers » — de zéro à quatre par paragraphe (`3595:23965`).
struct BookDecorationsPanel: View {
    let model: BookCustomisationModel

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            BookPanelLead(BookCopy.Decorations.subtitle)

            BrandSlider(
                value: quota,
                in: 0...4,
                step: 1,
                ticks: ["0", "1", "2", "3", "4"],
                leadingLabel: BookCopy.Decorations.sliderLabel,
                voiceLabel: BookCopy.Decorations.sliderLabel,
                voiceValue: { $0 == 0 ? "Aucune" : "\($0) par paragraphe" }
            )
        }
        .disabled(model.customisation == nil)
    }

    private var quota: Binding<Int> {
        Binding(
            get: { model.customisation?.decorationQuota ?? 0 },
            set: { model.setDecorationQuota($0) }
        )
    }
}

// MARK: - Typographies

/// « Typos » — trois assortiments, un seul choisi (`3595:24006`).
///
/// **On ne compose plus police par police** (Hugo, 16/09/2026) : la plupart des
/// mariages sont laids, et un carnet imprimé ne se rattrape pas. Chaque
/// assortiment s'écrit **dans ses polices** — « Playfair - Hansley - Gloria
/// Hallelujah », chaque nom dessiné dans sa famille —, c'est ce que la maquette
/// montre, et la seule façon de choisir sans connaître la typographie.
struct BookFontsPanel: View {
    let model: BookCustomisationModel

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BookPanelLead(BookCopy.Fonts.subtitle)

            BookPanelCard {
                ForEach(BookFontCombo.all) { combo in
                    BookFontComboRow(combo: combo, isSelected: isSelected(combo)) {
                        model.setFontCombo(combo)
                    }
                }
            }
        }
        .disabled(model.customisation == nil)
    }

    private func isSelected(_ combo: BookFontCombo) -> Bool {
        guard let customisation = model.customisation else { return false }
        return combo.matches(customisation)
    }
}

/// Un assortiment : ses polices, écrites chacune dans sa police, sa phrase, et
/// le rond de sélection de ``BrandOptionRow`` — même aplat bleu quand c'est
/// coché, pour que le geste soit le même.
private struct BookFontComboRow: View {
    let combo: BookFontCombo
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 22

    /// La hauteur des noms dessinés : celle d'une ligne de
    /// ``MemoBookFont/bodySemibold``, avec laquelle ils suivent le Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var wordmarkHeight: CGFloat = 15

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    /// Les familles de l'assortiment, **sans doublon et dans l'ordre des
    /// rôles** : « Playfair - Hansley - Gloria Hallelujah » pour le carnet de
    /// voyage, « Hansley - Gloria Hallelujah » pour le manuscrit.
    private var families: [BookFontRole] {
        var seen: Set<String> = []
        return BookFontRole.allCases.filter { seen.insert(combo.font($0)).inserted }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    names
                    Text(combo.detail)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                mark
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.s - 2)
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .background(isSelected ? MemoBookColor.outline.opacity(0.35) : Color.clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? MemoBookColor.outline : MemoBookColor.hairline,
                    lineWidth: 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Les noms, dessinés dans leur police quand le vectoriel existe, écrits en
    /// General Sans sinon, séparés d'un tiret.
    private var names: some View {
        // Une grille et non une `HStack` : trois noms ne tiennent pas toujours
        // sur une ligne, et la grille sait passer à la suivante.
        FlowRow(spacing: MemoBookSpacing.xs / 2) {
            ForEach(Array(families.enumerated()), id: \.offset) { index, role in
                if index > 0 {
                    Text("-")
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                }
                if let wordmark = combo.fontWordmark(role) {
                    Image(brand: wordmark)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(height: wordmarkHeight)
                        .foregroundStyle(MemoBookColor.ink)
                } else {
                    Text(combo.fontLabel(role))
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                }
            }
        }
    }

    private var mark: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? MemoBookColor.blueText : MemoBookColor.separator,
                    lineWidth: 1.5
                )
            if isSelected {
                Circle()
                    .fill(MemoBookColor.blueText)
                    .padding(5)
            }
        }
        .frame(width: markSide, height: markSide)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let names = families.map { combo.fontLabel($0) }.joined(separator: ", ")
        return "\(names). \(combo.detail)"
    }
}

/// Des éléments posés en ligne, qui passent à la ligne quand la largeur
/// manque. Le strict nécessaire pour trois noms de police.
private struct FlowRow: Layout {
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            // Centrés sur la ligne : un nom dessiné et un tiret écrit n'ont pas
            // la même hauteur.
            subview.place(
                at: CGPoint(x: x, y: y + (max(rowHeight, size.height) - size.height) / 2),
                proposal: .unspecified
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Extras

/// « Extras » — cinq interrupteurs (`3595:24049`) : les pointillés et les fun
/// facts, qui étaient deux lignes à feuille, rejoignent le quiz, les zones
/// libres et le mot fléché.
struct BookExtrasPanel: View {
    let model: BookCustomisationModel

    var body: some View {
        BookPanelCard {
            BrandToggleCard(
                title: BookCopy.Rules.toggle,
                detail: BookCopy.Rules.detail,
                isOn: binding(\.rulesEnabled, model.setRules)
            )
            BrandToggleCard(
                title: BookCopy.FunFacts.toggle,
                detail: BookCopy.FunFacts.detail,
                isOn: binding(\.funFactsEnabled, model.setFunFacts)
            )
            BrandToggleCard(
                title: BookCopy.Customisation.quizTitle,
                detail: BookCopy.Customisation.quizDetail,
                isOn: binding(\.quizEnabled, model.setQuiz)
            )
            BrandToggleCard(
                title: BookCopy.Customisation.freeZonesTitle,
                detail: BookCopy.Customisation.freeZonesDetail,
                isOn: binding(\.freeZonesEnabled, model.setFreeZones)
            )
            BrandToggleCard(
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
    ///
    /// `@MainActor` sur la méthode **et** sur `set` : `Binding` veut des
    /// fermetures `@Sendable`, et une méthode du modèle — isolée au menu
    /// principal — ne s'y glisse que si cette isolation est dite ici aussi.
    @MainActor
    private func binding(
        _ keyPath: KeyPath<BookCustomisation, Bool>,
        _ set: @escaping @MainActor (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model.customisation?[keyPath: keyPath] ?? false },
            set: { isOn in set(isOn) }
        )
    }
}

// MARK: - Les deux blocs communs

/// La phrase d'explication en tête d'un panneau : le corps de texte, en gris.
private struct BookPanelLead: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// La carte papier qui porte les choix d'un panneau (`3595:23854`) : un aplat
/// papier, un filet, et les options dedans.
private struct BookPanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.snug)

        VStack(spacing: MemoBookSpacing.snug) {
            content
        }
        .padding(MemoBookSpacing.s)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
    }
}

#Preview("Panneaux du carnet") {
    let model = BookCustomisationModel(tripId: "preview")

    return ScrollView {
        VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
            BookRatioPanel(model: model)
            BookPagesPanel(model: model)
            BookDecorationsPanel(model: model)
            BookFontsPanel(model: model)
            BookExtrasPanel(model: model)
        }
        .padding(MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
    .task { await model.load() }
    .environment(\.colorScheme, .light)
}
