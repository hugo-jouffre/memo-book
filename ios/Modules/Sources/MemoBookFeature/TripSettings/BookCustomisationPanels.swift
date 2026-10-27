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
                // Sora à 24 (`3595:23828`).
                .font(MemoBookFont.figure)
                // Les chiffres ne dansent pas : sans chasse fixe, la valeur se
                // décale à chaque cran du curseur.
                .monospacedDigit()
                .foregroundStyle(MemoBookColor.ink)

            // **À l'encre**, comme la valeur au-dessus (Hugo, 06/10/2026,
            // T218) : le bleu clair `outline` de la maquette ne se lisait pas
            // sur le crème.
            Text(BookCopy.Ratio.quality(ratio.wrappedValue))
                .font(MemoBookFont.tagline)
                .foregroundStyle(MemoBookColor.ink)
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

/// « Nombre de pages » — quatre paliers, dont les projections suivent la durée
/// du voyage (`3595:23917`).
///
/// **Deux changements par voyage, une fois une étape écrite** (Hugo,
/// 15/10/2026). Avant, le palier part au geste ; ensuite, le geste ouvre
/// ``PageTargetChangeSheet`` et rien ne bouge avant qu'on confirme. Les deux
/// changements faits, les paliers pâlissent sans se désactiver : l'appui pose
/// la note orange qui dit pourquoi.
struct BookPagesPanel: View {
    let model: BookCustomisationModel

    /// Le repère de la note orange : sous la carte, souvent sous le bas de
    /// l'écran, et l'écran défile jusqu'à elle.
    static let limitNoticeAnchor = "page-target-limit"

    /// Le nombre saisi à la main, quand on choisit « Personnalisé ».
    @State private var customPages: Double = 60
    @State private var isCustomising = false

    private var days: Int? { model.tripDays }
    /// Les paliers suivent aussi le ratio (18/10/2026).
    private var ratio: Int { model.customisation?.photoTextRatio ?? 50 }

    private var selection: BookPageTarget {
        guard let pages = model.customisation?.targetPageCount else { return .standard }
        return isCustomising ? .custom : BookPageTarget.matching(pageCount: pages, tripDays: days, ratio: ratio)
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
                        target.label(forTripDays: days, ratio: ratio),
                        subtitle: target.detail,
                        value: price(of: target),
                        valueTone: .accent,
                        isSelected: selection == target
                    ) {
                        choose(target)
                    }
                }

                if isCustomising { customPageStepper }
            }
            // Pâlie, pas désactivée : chaque ligne garde son geste, et c'est
            // le modèle qui répond par la note orange.
            .opacity(model.isPageTargetLocked ? 0.45 : 1)

            if model.showsPageTargetLimitNotice {
                BrandNotice(BookCopy.Pages.limitReached, tone: .warning)
                    .id(Self.limitNoticeAnchor)
                    .transition(.opacity)
            }

            rewrite
        }
        .animation(.snappy(duration: 0.25), value: isCustomising)
        .animation(.snappy(duration: 0.25), value: model.showsPageTargetLimitNotice)
        .animation(.snappy(duration: 0.25), value: model.offersRewrite)
        .disabled(model.customisation == nil)
        .onAppear {
            guard let pages = model.customisation?.targetPageCount else { return }
            customPages = Double(pages)
            isCustomising = BookPageTarget.matching(pageCount: pages, tripDays: days, ratio: ratio) == .custom
            logPrices()
        }
        // Le ratio se règle dans l'onglet voisin, et il déplace les cibles
        // (18/10/2026) : les prix affichés suivent, sans rien redemander au
        // serveur — la grille ne dépend que du nombre de pages.
        .onChange(of: ratio) { _, _ in logPrices() }
        // La feuille refermée sans changement — « Annuler », ou un refus — :
        // le curseur revient sur la cible qui tient toujours.
        .onChange(of: model.pageTargetChange == nil) { _, isClosed in
            if isClosed { resyncCustomPages() }
        }
        .onChange(of: model.pageTargetReach == nil) { _, isClosed in
            if isClosed, model.pageTargetChange == nil { resyncCustomPages() }
        }
    }

    /// La réécriture laissée « Plus tard » : un lien sous les paliers, tant
    /// que le serveur la garde ouverte. Une fois partie, une phrase la
    /// remplace.
    @ViewBuilder
    private var rewrite: some View {
        if model.hasStartedRewrite {
            BrandNotice(BookCopy.Pages.rewriteStarted)
                .transition(.opacity)
        } else if model.offersRewrite {
            BrandButton(
                BookCopy.Pages.rewriteLink,
                style: .link,
                isLoading: model.isRewritingWrittenSteps
            ) {
                Task { await model.rewriteWrittenSteps() }
            }
            .padding(.horizontal, MemoBookSpacing.xs)
            .transition(.opacity)
        }
    }

    /// « 2 mois », « 12 jours » — la durée du voyage, écrite comme on la dit.
    private var duration: String? {
        guard let days else { return nil }
        if days >= 60 { return "\(days / 30) mois" }
        if days >= 14 { return "\(days / 7) semaines" }
        return days == 1 ? "1 jour" : "\(days) jours"
    }

    /// **Ce que le curseur laisse poser** : de 20 pages à ce que le serveur
    /// accepte de facturer — 300, ou 400 quand la configuration ouvre le
    /// dernier palier (``PrintPricing/maxPages``).
    ///
    /// Le plancher de l'imprimeur est 16 pages ; le curseur part de 20 parce
    /// qu'il avance de dix en dix, et qu'un carnet de 16 se facture de toute
    /// façon comme un carnet de 20 — même palier. Sans grille servie, les
    /// bornes d'avant (30 à 180), qui sont celles que le serveur sait composer.
    private var customPageBounds: ClosedRange<Double> {
        guard let pricing = model.printPricing else { return 30...180 }
        return 20...Double(pricing.maxPages)
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
                in: customPageBounds,
                step: 10,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    // Un nombre posé à la main : hors d'atteinte, la feuille
                    // le dit avant que rien ne change (18/10/2026).
                    model.requestCustomTarget(Int(customPages))
                    if model.pageTargetChange == nil, model.pageTargetReach == nil { resyncCustomPages() }
                }
            )
            .tint(MemoBookColor.action)
            .accessibilityLabel(BookCopy.Pages.customTitle)
            .accessibilityValue("\(Int(customPages)) pages")
        }
        .padding(.horizontal, MemoBookSpacing.xs)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Le prix de chaque option

    /// **Ce que coûtera le carnet**, option par option — le prix du palier de
    /// `cible + tolérance` (``PrintPricing/displayedPrice(forTarget:)``).
    ///
    /// Le carnet composé tient dans sa cible à cinq pages près : annoncer le
    /// haut de la fourchette, c'est promettre un prix qu'on ne dépassera pas.
    ///
    /// « Personnalisé » n'a pas de cible à lui : c'est le nombre posé au
    /// curseur qui fait le prix, et il se met à jour à chaque cran — la grille
    /// entière est déjà là, aucun aller-retour n'est nécessaire.
    ///
    /// `nil` — un serveur qui ne sert pas encore la grille, un nombre de pages
    /// hors de ce qu'on sait facturer — : la ligne s'affiche **sans prix**.
    /// Mieux vaut pas de prix qu'un prix faux.
    private func price(of target: BookPageTarget) -> String? {
        guard let pricing = model.printPricing else { return nil }
        let amount: Decimal?
        if target == .custom {
            amount = pricing.price(forPages: Int(customPages))
        } else if let pages = target.pageCount(forTripDays: days, ratio: ratio) {
            amount = pricing.displayedPrice(forTarget: pages)
        } else {
            amount = nil
        }
        return amount?.euros
    }

    /// Le prix de chaque option, tel que l'écran vient de le calculer — en
    /// développement seulement.
    private func logPrices() {
        #if DEBUG
            guard let pricing = model.printPricing else {
                print("[pricing] aucune grille servie : les options s'affichent sans prix")
                return
            }
            for target in BookPageTarget.allCases {
                let pages = target == .custom
                    ? Int(customPages)
                    : (target.pageCount(forTripDays: days, ratio: ratio) ?? 0) + pricing.tolerancePages
                let tier = pricing.tier(forPages: pages)?.id ?? "aucun"
                let cible = target.pageCount(forTripDays: days, ratio: ratio).map { "\($0)" } ?? "—"
                let affiché = price(of: target) ?? "—"
                print("[pricing] \(target.rawValue) cible=\(cible) facturé=\(pages) palier=\(tier) prix=\(affiché)")
            }
        #endif
    }

    private func choose(_ target: BookPageTarget) {
        // La cible ne bouge plus : pas même le curseur ne s'ouvre.
        guard !model.isPageTargetLocked else {
            model.explainPageTargetLimit()
            return
        }
        isCustomising = target == .custom
        guard let pages = target.pageCount(forTripDays: days, ratio: ratio) else {
            // « Personnalisé » n'a pas de valeur à lui : on garde celle qui est
            // déjà posée et on ouvre le curseur dessous.
            return
        }
        customPages = Double(pages)
        request(pages)
    }

    /// Demande la cible au modèle. Rien n'a bougé et aucune feuille ne s'est
    /// ouverte — la cible verrouillée — : le curseur revient où il était.
    private func request(_ pages: Int) {
        model.setTargetPageCount(pages)
        if model.pageTargetChange == nil { resyncCustomPages() }
    }

    private func resyncCustomPages() {
        guard let pages = model.customisation?.targetPageCount else { return }
        customPages = Double(pages)
    }
}

// MARK: - Décorations & stickers

/// « Décorations & stickers » — de zéro à quatre stickers par étape (`3595:23965`).
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
                voiceValue: { $0 == 0 ? "Aucune" : "\($0) par étape" }
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

    /// Le repère de la note des pointillés retirés : elle paraît sous la carte,
    /// souvent sous le bas de l'écran, et l'écran défile jusqu'à elle.
    static let withdrawnNoticeAnchor = "rules-withdrawn"

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            BookPanelLead(BookCopy.Fonts.subtitle)

            BookPanelCard {
                ForEach(BookFontCombo.all) { combo in
                    // Éditorial et Manuscrit ne s'impriment pas encore : la
                    // ligne reste, pâlie, sous la pastille des connecteurs, et
                    // ne prend pas le geste (`isAvailable`).
                    BookFontComboRow(combo: combo, isSelected: isSelected(combo)) {
                        model.setFontCombo(combo)
                    }
                    .brandComingSoon(!combo.isAvailable)
                }
            }

            // L'interrupteur des pointillés est dans une autre pastille : c'est
            // ici, au geste, qu'on apprend qu'ils viennent de s'éteindre.
            if let combo = model.rulesWithdrawnBy {
                BrandNotice(BookCopy.Rules.withdrawn(by: combo), tone: .information)
                    .id(Self.withdrawnNoticeAnchor)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.rulesWithdrawnBy)
        // Sans annonce, VoiceOver resterait sur la ligne touchée, et la note
        // qui dit ce qu'on vient de perdre serait plus bas, à balayer.
        .onChange(of: model.rulesWithdrawnBy) { _, combo in
            guard let combo else { return }
            AccessibilityNotification.Announcement(BookCopy.Rules.withdrawn(by: combo)).post()
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

    /// Le repère de la note du verrou : aux tailles de texte accessibles, elle
    /// paraît sous le bas de l'écran, et l'écran défile jusqu'à elle.
    static let lockedNoticeAnchor = "rules-locked"

    var body: some View {
        BookPanelCard {
            // Verrouillés par *Manuscrit* ou *Éditorial* : l'interrupteur pâlit,
            // et l'appui dit pourquoi et comment en sortir.
            BrandToggleCard(
                title: BookCopy.Rules.toggle,
                detail: BookCopy.Rules.detail,
                isOn: binding(\.rulesEnabled, model.setRules),
                isAvailable: !model.isRulesSwitchLocked,
                onUnavailable: {
                    model.explainRulesLock()
                    AccessibilityNotification.Announcement(BookCopy.Rules.locked).post()
                }
            )
            if model.showsRulesLockNotice {
                BrandNotice(BookCopy.Rules.locked, tone: .information)
                    .id(Self.lockedNoticeAnchor)
                    .transition(.opacity)
            }
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
            // Le seul extra qui se facture : 3,00 € l'exemplaire, parce qu'il
            // ajoute du papier (maquette `3909:27845`). Le prix vient du
            // serveur avec les réglages ; sans lui, la ligne s'affiche telle
            // qu'avant plutôt que d'annoncer un supplément inventé.
            BrandToggleCard(
                title: BookCopy.Customisation.freeZonesTitle,
                detail: BookCopy.Customisation.freeZonesDetail,
                price: model.printPricing?.freeZonesPrice.map { "+\($0.euros)" },
                isOn: binding(\.freeZonesEnabled, model.setFreeZones)
            )
            BrandToggleCard(
                title: BookCopy.Customisation.crosswordTitle,
                detail: BookCopy.Customisation.crosswordDetail,
                isOn: binding(\.crosswordEnabled, model.setCrossword)
            )
        }
        .animation(.snappy(duration: 0.25), value: model.showsRulesLockNotice)
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
