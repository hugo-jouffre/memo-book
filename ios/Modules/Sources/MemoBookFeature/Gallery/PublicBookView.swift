import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **Un carnet de la communauté, ouvert** — l'écran derrière une carte
/// d'« Exemples de carnets » (T236).
///
/// C'est la seconde moitié de la galerie : les cartes existaient depuis des
/// semaines et ne menaient nulle part. Elles mènent ici.
///
/// **L'écran ne contient aucun contenu.** Titre, dates, résumé, lieux, récit et
/// photos viennent du ``PublicBook`` que porte ``PublicBookModel``. Ce qui est
/// écrit ici, ce sont les seuls libellés qui appartiennent à l'interface :
/// l'intitulé des chiffres, les deux formulations du bouton et les états vides.
///
/// **Il s'ouvre sur ce que la carte montrait** — son titre et sa photo, que le
/// modèle garde sous la main — puis le récit arrive dessous. L'écran ne s'ouvre
/// donc jamais sur un vide, et la photo est déjà dans le cache d'URL.
///
/// **Ce carnet n'est pas à celui qui le lit**, et l'écran le sait : rien n'y est
/// tapable que le retour et l'appel à l'action. Pas de tiroir d'actions, pas de
/// partage, pas d'étoile sur une photo — ce sont les gestes du propriétaire d'un
/// voyage, et on regarde celui de quelqu'un d'autre.
public struct PublicBookView: View {
    @State private var model: PublicBookModel
    private let onIntent: (HomeIntent) -> Void

    /// La feuille « Nouveau carnet », la même que celle de l'accueil et de la
    /// galerie. Une feuille ne navigue pas, elle propose.
    @State private var isCreatingNotebook = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        model: PublicBookModel = PublicBookModel(),
        onIntent: @escaping (HomeIntent) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            scrollingContent
            // Le même voile que sous le CTA de l'accueil et de la galerie, pour
            // la même raison — voir ``BrandFooterScrim``.
            callToAction.brandFooterScrim()
        }
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre.
        .environment(\.colorScheme, .light)
        .brandSheet(isPresented: $isCreatingNotebook) {
            NewNotebookSheet(resumableTrip: nil, onIntent: onIntent)
        }
        .task { await model.load() }
        .animation(.smooth(duration: 0.35), value: model.book)
    }

    private var scrollingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.sectionGap) {
                cover
                heading

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                    .padding(.horizontal, MemoBookSpacing.screenMargin)
                }

                story
            }
            .padding(.bottom, MemoBookSpacing.m)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.load() }
        // Le bouton est dessiné par la pile, pas ici : cet encart ne sert qu'à
        // lui **réserver sa place**, pour que la fin du récit puisse défiler
        // jusqu'au-dessus de lui.
        .safeAreaInset(edge: .bottom, spacing: 0) { callToAction.hidden() }
    }

    // MARK: - La couverture

    /// La photo du carnet, pleine largeur, qui monte sous l'encoche.
    ///
    /// Un format large et non celui d'une couverture de livre : l'écran n'est
    /// pas un aperçu d'impression, c'est un récit qu'on fait défiler, et une
    /// couverture verticale aurait pris l'écran entier avant le premier mot.
    private var cover: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                AsyncImage(url: model.coverPhotoUrl) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        // Aucune photo montrable : l'aplat de marque des
                        // couvertures, comme sur la carte dont on vient — même
                        // empreinte, donc **le même aplat**, et le passage de la
                        // carte à l'écran ne change pas de couleur.
                        TripCoverPlaceholder(seed: model.book?.id ?? model.preview?.id ?? "")
                    }
                }
                .accessibilityHidden(true)
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
            // ⚠️ **La flèche de retour appartient à la couverture et défile avec
            // elle**, au lieu de rester posée sur l'écran (23/11/2026).
            // Épinglée, elle flottait sur le récit : en AX3 elle recouvrait le
            // premier mot du premier paragraphe, et plus bas elle se posait au
            // milieu d'une bande de photos — on la lisait comme un défaut
            // d'affichage. Un écran de lecture ne garde pas de chrome au-dessus
            // de son texte ; le geste depuis le bord ramène en arrière, et
            // remonter d'un pouce redonne la flèche.
            .overlay(alignment: .topLeading) { backButton }
    }

    /// La flèche de retour, en pastille claire : elle est posée sur une photo
    /// dont on ne connaît pas la couleur, et la bichrome bleue y disparaîtrait
    /// sur un ciel.
    private var backButton: some View {
        Button { dismiss() } label: {
            Image(brand: "IconArrowDuo")
                .resizable()
                .scaledToFit()
                .frame(
                    width: MemoBookSpacing.navigationIcon,
                    height: MemoBookSpacing.navigationIcon
                )
                .padding(MemoBookSpacing.xs)
                .background(MemoBookColor.surface.opacity(0.92), in: .circle)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retour")
        .padding(.leading, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.xs)
    }

    // MARK: - L'en-tête

    /// Le titre, les dates, la phrase de résumé et les deux chiffres.
    private var heading: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                Text(model.title)
                    .font(MemoBookFont.h2)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let flag = model.book?.flag {
                    Text(flag).font(MemoBookFont.body)
                }

                Spacer(minLength: 0)
            }

            if let summary = model.summary {
                Text(summary)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.isLoading {
                BrandSkeleton(width: 140)
            }

            if let dates = model.book?.dates {
                Text(dates)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }

            if let book = model.book {
                figures(book)
                    .padding(.top, MemoBookSpacing.xs)
            }
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    /// Les deux chiffres qui disent « c'est un vrai carnet fini » — toute la
    /// promesse de l'écran, et la raison pour laquelle une vitrine existe.
    ///
    /// Empilés aux tailles accessibles : côte à côte, « 92 pages » et
    /// « 24 souvenirs » en AX3 se chevauchent.
    @ViewBuilder
    private func figures(_ book: PublicBook) -> some View {
        let items = [
            book.pageCount > 0 ? "\(book.pageCount) pages" : nil,
            book.memoryCount > 0 ? memoryCountLabel(book.memoryCount) : nil,
        ]
        .compactMap { $0 }

        if !items.isEmpty {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { figureTexts(items) }
            } else {
                HStack(spacing: MemoBookSpacing.xs) { figureTexts(items) }
            }
        }
    }

    @ViewBuilder
    private func figureTexts(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.ink)
                .padding(.horizontal, MemoBookSpacing.xs)
                .padding(.vertical, 4)
                .background(MemoBookColor.surface, in: .capsule)
                .overlay { Capsule().strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        }
    }

    /// « 1 souvenir », « 24 souvenirs ».
    private func memoryCountLabel(_ count: Int) -> String {
        "\(count) souvenir\(count > 1 ? "s" : "")"
    }

    // MARK: - Le récit

    @ViewBuilder
    private var story: some View {
        if model.isLoading {
            placeholders
        } else if let book = model.book {
            if book.hasNothingToRead {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: MemoBookSpacing.l) {
                    // **Les étapes qui portent quelque chose**, pas toutes : une
                    // étape sans récit ni photo n'est qu'un jalon du trajet, et
                    // en dérouler cinq vides donnerait un carnet qui a l'air
                    // cassé plutôt qu'un carnet en cours d'écriture.
                    ForEach(book.tellingSteps) { step in
                        stepSection(step)
                    }
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
            }
        }
    }

    /// Une étape : son lieu, ses dates, son récit, ses photos.
    private func stepSection(_ step: PublicBookStep) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            stepHeader(step)

            ForEach(Array(step.story.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !step.photoUrls.isEmpty {
                stepPhotos(step)
            }
        }
    }

    private func stepHeader(_ step: PublicBookStep) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: MemoBookSpacing.xs) {
                Text(step.place ?? "Étape \(step.number)")
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let flag = step.flag {
                    Text(flag).font(MemoBookFont.caption)
                }

                Spacer(minLength: 0)
            }

            // Les dates et le transport sur une ligne grise : « du 1er au 8 juin
            // 2026 · Bateau ». Le transport est tu quand l'app ne connaît pas la
            // clé — voir ``PublicBookStep/mode``.
            if let subtitle = [step.dates, step.mode?.displayName]
                .compactMap({ $0 })
                .joined(separator: " · ")
                .nilWhenEmpty
            {
                Text(subtitle)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Les photos d'une étape, en bande qui défile.
    ///
    /// Une bande et non une grille : le nombre de photos d'une étape va de une à
    /// vingt, et une grille aurait fait de la première étape un mur avant le
    /// premier mot de la seconde.
    private func stepPhotos(_ step: PublicBookStep) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: MemoBookSpacing.xs) {
                ForEach(step.photoUrls, id: \.self) { url in
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            MemoBookColor.coverWash
                        }
                    }
                    .frame(width: photoSide, height: photoSide)
                    .clipShape(.rect(cornerRadius: MemoBookSpacing.cornerRadius))
                }
            }
        }
        .scrollIndicators(.hidden)
        // Ce qui sort par un bord s'y efface, comme la barre de filtres de la
        // galerie — voir ``brandHorizontalFade``.
        .brandHorizontalFade()
        // Les photos d'un récit se regardent, elles ne s'annoncent pas une par
        // une : VoiceOver en dit le nombre et passe à la suite.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            step.photoUrls.count > 1
                ? "\(step.photoUrls.count) photos" : "1 photo"
        )
    }

    @ScaledMetric(relativeTo: .body) private var photoSide: CGFloat = 148

    /// L'attente : des barres à la place du récit, pas un écran vide. L'en-tête
    /// et la couverture sont déjà là — ils viennent de la carte.
    private var placeholders: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            BrandSkeleton(width: 120)
            ForEach(0..<5, id: \.self) { _ in BrandSkeleton() }
            BrandSkeleton(width: 220)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .accessibilityHidden(true)
    }

    /// Un carnet partagé dont rien n'est encore rédigé. Il existe — la carte le
    /// montrait —, il n'a simplement pas encore de récit.
    private var emptyState: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            Text("Ce carnet s'écrit encore")
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            Text("Son voyageur l'a partagé, mais son récit n'est pas encore rédigé.")
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.xl)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    // MARK: - Action

    /// La même question que sur la galerie, et la même réponse : on reprend le
    /// carnet qu'on a, ou on en crée un. C'est pour ça qu'on regarde une
    /// vitrine.
    private var callToAction: some View {
        BrandButton(
            model.resumableTripId == nil ? "Créer mon voyage" : "Continuer mon voyage",
            icon: Image(brand: model.resumableTripId == nil ? "IconPlus" : "IconArrowRight"),
            style: .primary,
            fillsWidth: true
        ) {
            if let tripId = model.resumableTripId {
                onIntent(.openTrip(id: tripId))
            } else {
                isCreatingNotebook = true
            }
        }
        // Même limite que les deux autres CTA ancrés en bas : au-delà d'AX1 une
        // barre basse prend la moitié de l'écran.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.s)
        .padding(.bottom, MemoBookSpacing.xs)
    }
}

extension String {
    /// `nil` plutôt qu'une chaîne vide, pour qu'un `if let` suffise à ne rien
    /// dessiner.
    fileprivate var nilWhenEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Aperçus

#Preview("Carnet de la communauté") {
    NavigationStack { PublicBookView() }
}

#Preview("Carnet — rien à lire encore") {
    NavigationStack {
        PublicBookView(model: PublicBookModel { .nothingToReadFixture })
    }
}

#Preview("Carnet — erreur") {
    NavigationStack {
        PublicBookView(model: PublicBookModel { throw URLError(.notConnectedToInternet) })
    }
}

#Preview("Carnet — Dynamic Type AX3") {
    NavigationStack { PublicBookView() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
