import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Un document légal — les conditions d'utilisation, la politique de
/// confidentialité — chapitre par chapitre, une carte chacun.
///
/// **On y arrive par les deux lignes du groupe légal du profil.** La page ne
/// charge rien : le texte est celui du site, recopié dans ``TermsOfUse`` et
/// ``PrivacyPolicy``, et il appartient à l'app comme la foire aux questions.
///
/// Chaque carte se déplie **sur place**, et non dans une feuille comme les
/// réponses du support : un contrat se lit d'une traite, chapitre après
/// chapitre, et ouvrir onze feuilles pour le parcourir en ferait un
/// formulaire. Repliée, la carte montre les trois premières lignes du
/// chapitre ; le premier chapitre est ouvert à l'arrivée, comme sur la
/// maquette, pour que la page ne soit pas une colonne de titres.
///
/// Le pied de page mène au support : quelqu'un qui lit les conditions cherche
/// souvent une réponse plus simple que le contrat, et la FAQ la porte.
public struct LegalDocumentView: View {
    private let document: LegalDocument
    private let onIntent: (LegalIntent) -> Void

    /// Les chapitres ouverts. Un ensemble et non un seul identifiant : deux
    /// chapitres ouverts côte à côte se comparent, et refermer l'un pour lire
    /// l'autre serait une contrainte que rien ne justifie.
    @State private var expandedChapters: Set<String>

    /// Les chapitres dont l'aperçu **tient** en trois lignes, mesurés à
    /// l'affichage. Un chapitre qui y tient et qui n'a qu'un paragraphe n'a
    /// rien à déplier : sa carte perd son chevron — « si le contenu est trop
    /// long, on peut appuyer » (Hugo, 17/09/2026), et pas autrement.
    ///
    /// Mesuré et non deviné : le nombre de lignes dépend de la largeur de
    /// l'écran et de la taille de texte, et un chapitre qui tient sur un
    /// 17 Pro Max déborde à AX3.
    @State private var fittingChapters: Set<String> = []

    public init(document: LegalDocument, onIntent: @escaping (LegalIntent) -> Void = { _ in }) {
        self.document = document
        self.onIntent = onIntent
        _expandedChapters = State(initialValue: Set(document.chapters.prefix(1).map(\.id)))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(title: document.title)

                chapters
                help
            }
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
    }

    // MARK: - Les chapitres

    private var chapters: some View {
        VStack(spacing: MemoBookSpacing.s) {
            ForEach(document.chapters) { chapter in
                let isExpandable = isExpandable(chapter)

                BrandDisclosureCard(
                    title: LegalCopy.chapterTitle(chapter),
                    isExpandable: isExpandable,
                    isExpanded: binding(for: chapter)
                ) {
                    LegalText(chapter.preview, tone: .preview, lineLimit: Self.previewLineCount) { isTruncated in
                        if isTruncated {
                            fittingChapters.remove(chapter.id)
                        } else {
                            fittingChapters.insert(chapter.id)
                        }
                    }
                } expanded: {
                    LegalChapterBody(chapter: chapter)
                }
                .accessibilityHint(
                    isExpandable
                        ? (expandedChapters.contains(chapter.id) ? LegalCopy.collapseHint : LegalCopy.expandHint)
                        : ""
                )
            }
        }
    }

    /// Ce qu'une carte repliée laisse voir : trois lignes, comme la maquette.
    private static let previewLineCount = 3

    /// Y a-t-il une suite à montrer ? Oui si l'aperçu est tronqué, ou si le
    /// chapitre a une **structure** que l'aperçu aplatit — des intertitres,
    /// des puces, des lignes : trois lignes d'adresse jointes par des espaces
    /// tiennent en trois lignes et ne sont pas pour autant le chapitre.
    private func isExpandable(_ chapter: LegalChapter) -> Bool {
        if !fittingChapters.contains(chapter.id) { return true }
        return chapter.blocks.count > 1
    }

    private func binding(for chapter: LegalChapter) -> Binding<Bool> {
        Binding(
            get: { expandedChapters.contains(chapter.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedChapters.insert(chapter.id)
                } else {
                    expandedChapters.remove(chapter.id)
                }
            }
        )
    }

    // MARK: - Le pied de page

    /// « Besoin d'aide ? Découvrir notre FAQ » — la question en sourdine à
    /// gauche, le lien à droite, comme la maquette les pose.
    ///
    /// Le lien est celui du design system, en petite taille : la maquette le
    /// dessine en vert, et ``BrandButton/Style/link`` écrit à l'encre — un
    /// lien d'une autre couleur serait un second bouton, et il n'y en a qu'un.
    /// Signalé (T148).
    private var help: some View {
        HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
            Text(LegalCopy.helpPrompt)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.inkMuted)

            Spacer(minLength: MemoBookSpacing.xs)

            BrandButton(LegalCopy.helpLink, style: .link, size: .small) {
                onIntent(.openHelp)
            }
        }
        .padding(.top, MemoBookSpacing.xs)
    }
}

/// Ce qu'un document légal peut demander à ``RootView``.
public enum LegalIntent: Sendable, Hashable {
    /// « Découvrir notre FAQ », en pied de page : le support.
    case openHelp
}

// MARK: - Le corps d'un chapitre

/// Les blocs d'un chapitre, les uns sous les autres.
private struct LegalChapterBody: View {
    let chapter: LegalChapter

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(MemoBookFont.tagline)
                        .foregroundStyle(MemoBookColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        // Un intertitre se rapproche de ce qu'il annonce, pas
                        // de ce qui le précède.
                        .padding(.top, MemoBookSpacing.xs)
                case .paragraph(let text):
                    LegalText(text, tone: .full)
                case .lines(let lines):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines, id: \.self) { line in
                            LegalText(line, tone: .full)
                        }
                    }
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
                                Text("•")
                                    .font(MemoBookFont.taglineRegular)
                                    .foregroundStyle(MemoBookColor.ink)
                                    .accessibilityHidden(true)
                                LegalText(item, tone: .full)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Un paragraphe d'un document légal, avec ses liens et ses étiquettes.
///
/// Le Markdown est lu ici et nulle part ailleurs : le document écrit
/// `[adresse](mailto:adresse)` et `**Finalité :**`, et c'est ce qui fait de
/// l'adresse un lien qu'on touche et de l'étiquette un demi-gras. Le reste du
/// texte n'a aucun balisage.
private struct LegalText: View {
    enum Tone {
        /// Le début d'un chapitre replié : en sourdine, comme sur la maquette.
        case preview
        /// Le chapitre déplié, sur l'aplat bleu : à l'encre, pour le contraste.
        case full
    }

    private let text: AttributedString
    private let tone: Tone
    private let lineLimit: Int?
    private let onTruncation: ((Bool) -> Void)?

    /// La hauteur du texte limité, et celle qu'il aurait sans limite. Quand
    /// les deux sont connues, leur écart dit si quelque chose a été coupé.
    @State private var limitedHeight: CGFloat?
    @State private var fullHeight: CGFloat?

    /// - Parameters:
    ///   - lineLimit: le nombre de lignes au-delà duquel le texte se coupe.
    ///     `nil` ne coupe rien.
    ///   - onTruncation: appelé avec `true` si la limite a coupé quelque chose,
    ///     `false` sinon — et **à nouveau** quand la largeur ou la taille de
    ///     texte change la réponse.
    init(
        _ markup: String,
        tone: Tone,
        lineLimit: Int? = nil,
        onTruncation: ((Bool) -> Void)? = nil
    ) {
        self.tone = tone
        self.lineLimit = lineLimit
        self.onTruncation = onTruncation
        text = Self.resolved(markup)
    }

    var body: some View {
        styled
            .lineLimit(lineLimit)
            .background {
                if onTruncation != nil {
                    // Le même texte, sans limite, dessiné caché sous le
                    // premier : la seule façon en SwiftUI de savoir si
                    // `lineLimit` a coupé, c'est de comparer avec ce qu'il
                    // aurait fait sans. Le fond reçoit la largeur du texte
                    // visible et prend sa propre hauteur — celle qui compte.
                    styled
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { limitedHeight = $0 }
            .onChange(of: limitedHeight) { report() }
            .onChange(of: fullHeight) { report() }
    }

    private func report() {
        guard let onTruncation, let limitedHeight, let fullHeight else { return }
        // Un demi-point d'écart, c'est l'arrondi d'une ligne, pas une ligne.
        onTruncation(fullHeight > limitedHeight + 0.5)
    }

    private var styled: some View {
        Text(text)
            // 14 et non 16 : c'est un texte qu'on parcourt, et onze chapitres
            // au corps de texte feraient trois écrans de plus.
            .font(MemoBookFont.taglineRegular)
            .foregroundStyle(tone == .preview ? MemoBookColor.inkMuted : MemoBookColor.ink)
            // Le lien seul est vert : c'est la couleur de ce qu'on peut
            // toucher, partout dans l'app.
            .tint(MemoBookColor.action)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Traduit `**…**` en portions de texte en demi-gras — le même passage
    /// que ``BrandNotice``, et pour la même raison : le gras est une **autre
    /// police** (General Sans Semibold), pas un épaississement du tracé.
    private static func resolved(_ markup: String) -> AttributedString {
        guard
            var text = try? AttributedString(
                markdown: markup,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        else {
            return AttributedString(markup)
        }

        let emphasised = text.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true ? run.range : nil
        }
        for range in emphasised { text[range].font = MemoBookFont.tagline }
        return text
    }
}

#Preview("Conditions d’utilisation") {
    NavigationStack {
        LegalDocumentView(document: TermsOfUse.document)
    }
}

#Preview("Politique de confidentialité") {
    NavigationStack {
        LegalDocumentView(document: PrivacyPolicy.document)
    }
}
