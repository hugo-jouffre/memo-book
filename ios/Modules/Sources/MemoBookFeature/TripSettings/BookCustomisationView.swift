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
/// **Six lignes ouvrent leur feuille** — ratio média, nombre de pages, fun
/// facts, pointillés, décorations et typographies — et quatre d'entre elles
/// portent les deux pages du carnet au-dessus d'elles, pour qu'on règle en
/// regardant ce qu'on règle (``BookPagesPeek``).
///
/// **Les typographies tiennent en une ligne, rangée avec les décors** (Hugo,
/// 16/09/2026). Il y en avait quatre — titres, sous-titres, textes, fun facts —,
/// chacune avec sa feuille et trois familles au choix : de quoi composer des
/// dizaines de mariages dont la plupart sont ratés, sur un objet qu'on imprime
/// et qui ne se rattrape pas. La feuille propose désormais quatre
/// **assortiments** (``BookFontCombo``) et dit ce que chaque police habille.
public struct BookCustomisationView: View {
    private let onIntent: (BookCustomisationIntent) -> Void

    @State private var model: BookCustomisationModel

    /// La feuille ouverte, s'il y en a une.
    @State private var sheet: BookCustomisationSheet?

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

                // **Le corps de texte, et non la légende de 12.** C'est un
                // paragraphe qu'on lit — le seul de l'écran —, et à 12 pt il
                // était plus petit que tout le reste de l'app (Hugo,
                // 16/09/2026). Même arbitrage que le chapeau du support, passé
                // au corps le 15/09. À l'encre pleine pour la même raison : une
                // explication n'est pas une mention.
                Text(BookCopy.Customisation.intro)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                coversRow
                layoutGroup
                decorGroup
                extras

                if let message = model.errorMessage {
                    // Le constat, le conseil, et les deux gestes — comme sur
                    // les paramètres du voyage (Hugo, 15/09/2026).
                    ErrorBanner(
                        message: message,
                        advice: model.errorAdvice,
                        retry: { Task { await model.load() } },
                        help: { onIntent(.openHelp) }
                    )
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
        .brandSheet(item: $sheet, content: sheetContent)
    }

    /// Les neuf feuilles, et les deux pages que sept d'entre elles portent.
    @ViewBuilder
    private func sheetContent(_ destination: BookCustomisationSheet) -> some View {
        // La réserve n'existe que s'il y a un carnet à montrer : sans PDF, la
        // feuille garde sa hauteur normale plutôt qu'un blanc de 130 pt au-dessus
        // de son titre.
        let inset = showsPages(destination) ? BookPagesPeek.sheetInset : 0

        Group {
            switch destination {
            case .ratio:
                BookRatioSheet(model: model)
            case .pages:
                BookPagesSheet(model: model)
            case .funFacts:
                BookToggleSheet(
                    title: BookCopy.FunFacts.title,
                    toggleTitle: BookCopy.FunFacts.toggle,
                    detail: BookCopy.FunFacts.detail,
                    isOn: binding(\.funFactsEnabled, model.setFunFacts),
                    isEnabled: model.customisation != nil,
                    topOverflow: inset
                )
            case .rules:
                BookToggleSheet(
                    title: BookCopy.Rules.title,
                    toggleTitle: BookCopy.Rules.toggle,
                    detail: BookCopy.Rules.detail,
                    isOn: binding(\.rulesEnabled, model.setRules),
                    isEnabled: model.customisation != nil,
                    topOverflow: inset
                )
            case .fonts:
                BookFontsSheet(model: model, topOverflow: inset)
            case .decorations:
                BookDecorationsSheet(model: model, topOverflow: inset)
            }
        }
        // Les deux pages ne se posent que s'il y a un carnet à montrer. Sans
        // PDF, deux rectangles blancs au-dessus de la feuille se liraient comme
        // un rendu qui a échoué — et non comme « il n'y a rien encore ».
        .bookPagesPeek(pdfUrl: model.bookPdfUrl, isVisible: destination.showsBookPages)
    }

    /// Cette feuille montre-t-elle les pages du carnet ? Les deux conditions,
    /// ensemble : la feuille les prévoit, et il y a un carnet.
    private func showsPages(_ destination: BookCustomisationSheet) -> Bool {
        destination.showsBookPages && model.bookPdfUrl != nil
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
                isValueLoading: model.isLoading,
                action: { sheet = .ratio }
            )
            BrandRow(
                BookCopy.Customisation.targetPageCount,
                value: customisation?.targetPageLabel ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading,
                action: { sheet = .pages }
            )
        }
        // Le temps de la lecture, et pas au-delà : une lecture qui a échoué
        // ne doit pas geler les lignes — elles ouvraient encore leurs
        // feuilles, elles ne le pouvaient plus derrière un 500 (Hugo,
        // 15/09/2026). Les feuilles, elles, savent attendre des valeurs.
        .disabled(model.isLoading)
    }

    private var decorGroup: some View {
        let customisation = model.customisation

        return BrandRowGroup {
            BrandRow(
                BookCopy.Customisation.funFacts,
                value: customisation.map { BookCopy.Customisation.toggleValue($0.funFactsEnabled) }
                    ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading,
                action: { sheet = .funFacts }
            )
            BrandRow(
                BookCopy.Customisation.rules,
                value: customisation.map { BookCopy.Customisation.toggleValue($0.rulesEnabled) }
                    ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading,
                action: { sheet = .rules }
            )
            BrandRow(
                BookCopy.Customisation.decorations,
                value: customisation?.decorationLabel ?? BookCopy.Settings.noValue,
                isValueLoading: model.isLoading,
                action: { sheet = .decorations }
            )
            // **Les typographies sont rangées ici**, avec les décors et non
            // dans un groupe à elles (Hugo, 16/09/2026) : ce sont les réglages
            // d'allure du carnet, et ils se règlent d'un bloc.
            BrandRow(
                BookCopy.Customisation.fonts,
                value: fontComboValue,
                isValueLoading: model.isLoading,
                action: { sheet = .fonts }
            )
        }
        .disabled(model.isLoading)
    }

    /// Ce que la ligne « Typographies » affiche : le nom de l'assortiment.
    ///
    /// « Personnalisé » quand le carnet n'entre dans aucun des quatre — il a
    /// été composé police par police avant que cette feuille existe, ou par un
    /// autre client. On ne coche pas de force : la ligne le dit, et ouvrir la
    /// feuille laisse choisir.
    private var fontComboValue: String {
        guard let customisation = model.customisation else { return BookCopy.Settings.noValue }
        return BookFontCombo.matching(customisation)?.name ?? BookCopy.Fonts.custom
    }

    // MARK: - Les extras

    private var extras: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            Text(BookCopy.Customisation.extrasSection)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

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

/// Ce que les personnalisations demandent à l'app d'ouvrir.
public enum BookCustomisationIntent: Sendable, Hashable {
    /// L'aperçu et la personnalisation des deux couvertures.
    case openCovers
    /// Le support, depuis le bandeau d'erreur : quand réessayer ne suffit pas.
    case openHelp
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
