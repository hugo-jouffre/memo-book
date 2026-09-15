import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les neuf feuilles de la personnalisation du carnet — six dessins, la
/// typographie servant quatre fois.
///
/// **Sept d'entre elles portent deux pages du carnet au-dessus d'elles**, et
/// ce n'est pas un ornement : on ne règle pas des pointillés ou une quantité de
/// stickers dans l'abstrait, on les règle en regardant la page. Les deux qui ne
/// les portent pas — le ratio média et le nombre de pages — changent quelque
/// chose qu'une page ne montre pas : une proportion d'ensemble et une longueur.
/// C'est le découpage de la maquette, et il se tient.
///
/// **Le réglage part au geste, le bouton ne fait que fermer.** Les trois
/// feuilles à « Valider » de la maquette enregistrent déjà pendant qu'on pousse
/// le curseur ou qu'on bascule l'interrupteur : le bouton est une sortie, pas
/// une validation. C'est le contrat des réglages partout dans l'app, et le
/// garder ici évite qu'une feuille refermée au glissé perde ce qu'on venait d'y
/// faire.

/// Ce que les personnalisations du carnet ouvrent en feuille.
enum BookCustomisationSheet: Identifiable, Hashable {
    case ratio
    case pages
    case funFacts
    case rules
    /// La typographie d'un rôle — la même feuille pour les quatre.
    case font(BookFontRole)
    case decorations

    var id: String {
        switch self {
        case .ratio: "ratio"
        case .pages: "pages"
        case .funFacts: "funFacts"
        case .rules: "rules"
        case .font(let role): "font-\(role.rawValue)"
        case .decorations: "decorations"
        }
    }

    /// Celles qui montrent les pages du carnet.
    var showsBookPages: Bool {
        switch self {
        case .funFacts, .rules, .font, .decorations: true
        case .ratio, .pages: false
        }
    }
}

// MARK: - Ratio média

/// « Ratio média » — la part de photo dans la page, de 0 à 100 %.
struct BookRatioSheet: View {
    let model: BookCustomisationModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(BookCopy.Ratio.title, subtitle: BookCopy.Ratio.subtitle) {
            VStack(spacing: MemoBookSpacing.m) {
                value
                slider
                BrandButton(BookCopy.Ratio.validate, fillsWidth: true) { dismiss() }
            }
            .disabled(model.customisation == nil)
        }
    }

    /// « 50 / 50 », et ce que l'équilibre vaut. C'est **ici** qu'on lit ce
    /// qu'on règle : le curseur ne fait que le poser.
    private var value: some View {
        VStack(spacing: MemoBookSpacing.xs - 2) {
            Text(BookCopy.Ratio.value(ratio.wrappedValue))
                .font(MemoBookFont.balance)
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

// MARK: - Nombre de page

/// « Nombre de page » — quatre paliers, dont les projections suivent la durée
/// du voyage.
struct BookPagesSheet: View {
    let model: BookCustomisationModel

    @Environment(\.dismiss) private var dismiss

    /// Le nombre saisi à la main, quand on choisit « Personnalisé ».
    @State private var customPages: Double = 60
    @State private var isCustomising = false

    private var days: Int? { model.tripDays }

    private var selection: BookPageTarget {
        guard let pages = model.customisation?.targetPageCount else { return .standard }
        return isCustomising ? .custom : BookPageTarget.matching(pageCount: pages, tripDays: days)
    }

    var body: some View {
        BrandSheet(
            BookCopy.Pages.title,
            paragraphs: [BookCopy.Pages.subtitle]
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
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

                BrandOptionGroup {
                    ForEach(BookPageTarget.allCases) { target in
                        BrandOptionRow(
                            target.label(forTripDays: days),
                            subtitle: target.detail,
                            isSelected: selection == target
                        ) {
                            choose(target)
                        }
                    }
                }

                if isCustomising { customPageStepper }
            }
            .animation(.snappy(duration: 0.25), value: isCustomising)
            .disabled(model.customisation == nil)
        }
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
        dismiss()
    }
}

// MARK: - Fun Facts & Pointillés

/// « Fun Facts » et « Pointillés » — un interrupteur, un bouton, et les deux
/// pages du carnet au-dessus.
///
/// **Une seule vue pour les deux feuilles** : elles ne diffèrent que par trois
/// chaînes et la propriété qu'elles basculent. Les écrire deux fois aurait fait
/// deux endroits où corriger la même marge.
struct BookToggleSheet: View {
    let title: String
    let toggleTitle: String
    let detail: String
    let isOn: Binding<Bool>
    let isEnabled: Bool
    /// La place réservée aux deux pages du carnet, quand il y en a un à
    /// montrer — voir ``BookPagesPeek``.
    var topOverflow: CGFloat = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(title, topOverflow: topOverflow) {
            VStack(spacing: MemoBookSpacing.m) {
                BrandToggleCard(title: toggleTitle, detail: detail, isOn: isOn)
                BrandButton(BookCopy.FunFacts.validate, fillsWidth: true) { dismiss() }
            }
            .disabled(!isEnabled)
        }
    }
}

// MARK: - Les typographies

/// « Titres du carnet », et ses trois sœurs — quelques familles, une seule
/// choisie.
///
/// **Une vue pour les quatre rôles**, parce qu'ils doivent se comporter pareil
/// (Hugo, 16/09/2026) : même liste encadrée, même « Valider » qui ne fait que
/// fermer, même pages du carnet au-dessus. Ce qui change — le titre, le
/// chapeau, les familles proposées et la colonne écrite — appartient au rôle
/// (``BookFontRole``), pas à la feuille.
struct BookFontsSheet: View {
    let model: BookCustomisationModel
    let role: BookFontRole
    var topOverflow: CGFloat = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(
            BookCopy.Fonts.sheetTitle(for: role),
            subtitle: BookCopy.Fonts.sheetSubtitle(for: role),
            topOverflow: topOverflow
        ) {
            VStack(spacing: MemoBookSpacing.m) {
                BrandOptionGroup {
                    ForEach(role.options) { font in
                        BrandOptionRow(
                            font.label,
                            subtitle: font.detail,
                            isSelected: isSelected(font)
                        ) {
                            model.setFont(role, font.name)
                        }
                    }
                }

                BrandButton(BookCopy.Fonts.validate, fillsWidth: true) { dismiss() }
            }
            .disabled(model.customisation == nil)
        }
    }

    private func isSelected(_ font: BookFontOption) -> Bool {
        guard let customisation = model.customisation else { return false }
        return font.matches(customisation[keyPath: role.keyPath])
    }
}

// MARK: - Décorations & stickers

/// « Décorations & stickers » — de zéro à quatre par paragraphe.
struct BookDecorationsSheet: View {
    let model: BookCustomisationModel
    var topOverflow: CGFloat = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(
            BookCopy.Decorations.title,
            subtitle: BookCopy.Decorations.subtitle,
            topOverflow: topOverflow
        ) {
            VStack(spacing: MemoBookSpacing.m) {
                BrandSlider(
                    value: quota,
                    in: 0...4,
                    step: 1,
                    ticks: ["0", "1", "2", "3", "4"],
                    leadingLabel: BookCopy.Decorations.sliderLabel,
                    voiceLabel: BookCopy.Decorations.sliderLabel,
                    voiceValue: { $0 == 0 ? "Aucune" : "\($0) par paragraphe" }
                )

                BrandButton(BookCopy.Decorations.validate, fillsWidth: true) { dismiss() }
            }
            .disabled(model.customisation == nil)
        }
    }

    private var quota: Binding<Int> {
        Binding(
            get: { model.customisation?.decorationQuota ?? 0 },
            set: { model.setDecorationQuota($0) }
        )
    }
}

#Preview("Feuilles du carnet") {
    @Previewable @State var sheet: BookCustomisationSheet? = .ratio
    let model = BookCustomisationModel(tripId: "preview")

    return Color.clear
        .task { await model.load() }
        .brandSheet(item: $sheet) { destination in
            switch destination {
            case .ratio: BookRatioSheet(model: model)
            case .pages: BookPagesSheet(model: model)
            case .font(let role): BookFontsSheet(model: model, role: role)
            case .decorations: BookDecorationsSheet(model: model)
            case .funFacts, .rules: EmptyView()
            }
        }
        .environment(\.colorScheme, .light)
}
