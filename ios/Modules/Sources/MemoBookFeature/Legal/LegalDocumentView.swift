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
/// chapitre — **du chapitre lui-même**, intertitres et puces compris, et non
/// d'un résumé : c'est ce qui permet à la carte de dérouler la suite sans
/// redessiner ce qu'on a lu (01/10/2026, voir ``BrandDisclosureCard``).
///
/// **Rien n'est ouvert à l'arrivée, et un seul chapitre l'est à la fois**
/// (Clara, 26/09/2026). Le premier s'ouvrait tout seul, et les cartes bleues
/// s'accumulaient au fil de la lecture : la page ressemblait à un bug plutôt
/// qu'à un sommaire. Ouvrir un chapitre referme celui qu'on lisait.
///
/// Le pied de page mène au support : quelqu'un qui lit les conditions cherche
/// souvent une réponse plus simple que le contrat, et la FAQ la porte. Il se
/// retire quand on arrive de l'écran d'entrée (T151) : sans compte, le support
/// n'est pas joignable, et la flèche de retour ramène à l'entrée.
public struct LegalDocumentView: View {
    private let document: LegalDocument
    private let onIntent: (LegalIntent) -> Void

    /// Le chapitre ouvert, ou aucun. **Un seul** : ouvrir l'un referme
    /// l'autre (Clara, 26/09/2026).
    @State private var expandedChapter: String?

    /// « Besoin d'aide ? Découvrir notre FAQ ». Faux depuis l'écran d'entrée.
    private let showsHelp: Bool

    public init(
        document: LegalDocument,
        showsHelp: Bool = true,
        onIntent: @escaping (LegalIntent) -> Void = { _ in }
    ) {
        self.document = document
        self.showsHelp = showsHelp
        self.onIntent = onIntent
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(title: document.title)

                chapters
                if showsHelp { help }
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
                let isExpanded = expandedChapter == chapter.id

                // **Un chapitre qui tient en trois lignes n'a rien à
                // déplier** : la carte le mesure elle-même et retire son
                // chevron — « si le contenu est trop long, on peut appuyer »
                // (Hugo, 17/09/2026), et pas autrement.
                BrandDisclosureCard(
                    title: LegalCopy.chapterTitle(chapter),
                    isExpanded: binding(for: chapter),
                    collapsedLineCount: Self.previewLineCount,
                    lineFont: LegalText.font
                ) {
                    LegalChapterBody(chapter: chapter, isExpanded: isExpanded)
                }
            }
        }
    }

    /// Ce qu'une carte repliée laisse voir : trois lignes, comme la maquette.
    private static let previewLineCount = 3

    private func binding(for chapter: LegalChapter) -> Binding<Bool> {
        Binding(
            get: { expandedChapter == chapter.id },
            set: { isExpanded in
                if isExpanded {
                    expandedChapter = chapter.id
                } else if expandedChapter == chapter.id {
                    expandedChapter = nil
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
///
/// Les mêmes dans les deux états de la carte : seule la couleur change — en
/// sourdine replié, comme sur la maquette ; à l'encre déplié, pour le contraste
/// sur l'aplat bleu.
private struct LegalChapterBody: View {
    let chapter: LegalChapter
    let isExpanded: Bool

    private var tone: LegalText.Tone { isExpanded ? .full : .preview }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(MemoBookFont.tagline)
                        .foregroundStyle(isExpanded ? MemoBookColor.ink : MemoBookColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        // Un intertitre se rapproche de ce qu'il annonce, pas
                        // de ce qui le précède.
                        .padding(.top, MemoBookSpacing.xs)
                case .paragraph(let text):
                    LegalText(text, tone: tone)
                case .lines(let lines):
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(lines, id: \.self) { line in
                            LegalText(line, tone: tone)
                        }
                    }
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
                                Text("•")
                                    .font(LegalText.font)
                                    .foregroundStyle(isExpanded ? MemoBookColor.ink : MemoBookColor.inkMuted)
                                    .accessibilityHidden(true)
                                LegalText(item, tone: tone)
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

    /// 14 et non 16 : c'est un texte qu'on parcourt, et onze chapitres au
    /// corps de texte feraient trois écrans de plus. C'est aussi la police
    /// dont la carte compte les lignes repliées.
    static let font = MemoBookFont.taglineRegular

    private let text: AttributedString
    private let tone: Tone

    init(_ markup: String, tone: Tone) {
        self.tone = tone
        text = Self.resolved(markup)
    }

    var body: some View {
        Text(text)
            .font(Self.font)
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
