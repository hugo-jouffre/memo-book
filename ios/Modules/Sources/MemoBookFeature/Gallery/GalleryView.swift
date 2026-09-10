import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les carnets de la communauté : à quoi ressemble un MemoBook terminé, avant
/// d'en avoir un à soi.
///
/// **L'écran ne contient aucun contenu.** Titres, phrases de résumé, pays,
/// catégories et jusqu'au pictogramme de chaque pastille viennent de la
/// ``Gallery`` que porte ``GalleryModel``. Ce qui est écrit ici, ce sont les
/// seuls libellés qui appartiennent à l'interface : le titre de l'écran, la
/// pastille « Tout », les deux formulations du bouton et les états vides.
///
/// **Le bouton du bas ne défile pas.** Même construction que l'accueil : un
/// voile qui dissout le contenu, et un appel à l'action posé par-dessus, dont
/// le contenu se réserve la place.
///
/// **Les vignettes ne s'ouvrent pas.** Un carnet de la communauté n'a pas
/// d'écran : elles ne sont donc pas des boutons, et ne promettent rien.
public struct GalleryView: View {
    @State private var model: GalleryModel
    private let onIntent: (HomeIntent) -> Void

    /// La feuille « Nouveau carnet », la même que celle de l'accueil. Une
    /// feuille ne navigue pas, elle propose : ce qu'on y choisit redevient une
    /// ``HomeIntent`` que `RootView` route.
    @State private var isCreatingNotebook = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        model: GalleryModel = GalleryModel(),
        onIntent: @escaping (HomeIntent) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            scrollingContent
            callToActionScrim
            callToAction
        }
        .background(MemoBookColor.background.ignoresSafeArea())
        // L'écran dessine son propre en-tête, comme le profil : la flèche et le
        // titre partagent une ligne, à la marge de la colonne.
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .brandSheet(isPresented: $isCreatingNotebook) {
            // Aucun carnet à reprendre ici : quand il y en a un, c'est le
            // bouton lui-même qui y mène et cette feuille ne s'ouvre pas.
            NewNotebookSheet(resumableTrip: nil, onIntent: onIntent)
        }
        // Le nombre de colonnes est la seule chose que la vue apprenne à son
        // modèle : il dépend de la taille de texte, que seul l'environnement
        // connaît. Une fois à l'ouverture, et à chaque changement du réglage.
        .onChange(of: typeSize.isAccessibilitySize, initial: true) { _, _ in
            model.use(columnCount: GalleryMetrics.columnCount(for: typeSize))
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private var scrollingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                    .padding(.horizontal, MemoBookSpacing.screenMargin)
                }

                grid
            }
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.m)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // L'en-tête et la barre de filtres restent en haut pendant que la
        // mosaïque défile dessous : c'est la barre qui commande la grille, elle
        // ne doit pas partir avec elle.
        .safeAreaInset(edge: .top, spacing: MemoBookSpacing.s) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                header
                filters
            }
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.xs)
            // Le voile pend **sous** la barre, et c'est ce qui fait passer les
            // vignettes derrière elle au lieu de les couper net. Il est posé
            // avant l'aplat pour rester derrière la barre, et déborde de sa
            // propre hauteur pour tomber dans la zone qui défile.
            .background(alignment: .bottom) { topScrim.offset(y: topScrimHeight) }
            .background(MemoBookColor.background)
        }
        // Le bouton est dessiné par la pile, pas ici : cet encart ne sert qu'à
        // lui **réserver sa place**, pour que la dernière vignette puisse
        // défiler jusqu'au-dessus de lui.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            callToAction.hidden()
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            Button { dismiss() } label: {
                // La bichrome, en bleu : c'est le seul retour de l'écran, comme
                // sur le profil.
                Image(brand: "IconArrowDuo")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: MemoBookSpacing.navigationIcon,
                        height: MemoBookSpacing.navigationIcon
                    )
                    .frame(
                        width: MemoBookSpacing.minimumTapTarget,
                        height: MemoBookSpacing.minimumTapTarget
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retour")

            Text("Exemples de carnets")
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    // MARK: - Les filtres

    /// La barre de catégories : « Tout », puis une pastille par catégorie de la
    /// base.
    ///
    /// Un seul filtre à la fois. Retoucher la pastille cochée revient à
    /// « Tout » : c'est le geste qu'on fait spontanément pour défaire un
    /// filtre, et l'écran n'a pas de bouton « Tout afficher » — sa première
    /// pastille en tient lieu.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: MemoBookSpacing.xs) {
                // Le pictogramme **défile avec les pastilles**. Posé hors de la
                // bande, il restait planté à la marge pendant que les pastilles
                // lui passaient dessus — un signe fixe à moitié recouvert, qu'on
                // lisait comme un défaut de rendu. Il ouvre la ligne, il ne la
                // surplombe pas.
                filterMark

                chip("Tout", icon: nil, isActive: model.selectedCategoryId == nil) {
                    model.select(nil)
                }

                ForEach(model.categories) { category in
                    let isActive = model.selectedCategoryId == category.id

                    chip(
                        category.name,
                        icon: LucideIcon.image(category.iconKey),
                        isActive: isActive
                    ) {
                        model.select(isActive ? nil : category.id)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // La bande prend toute la largeur de l'écran et son contenu s'aligne sur
        // la colonne : la dernière pastille peut donc sortir par le bord au lieu
        // de buter sur une marge — et ce qui en sort est **rogné**. Voir le
        // même choix, et la raison, dans `TripStepsSection`.
        .contentMargins(.horizontal, MemoBookSpacing.screenMargin, for: .scrollContent)
        // Et ce qui sort par un bord s'y **efface** au lieu d'être tranché à la
        // verticale — voir ``brandHorizontalFade``.
        .brandHorizontalFade()
    }

    /// Une pastille de la barre.
    ///
    /// Un vrai `Button` et non un `onTapGesture` : c'est lui qui donne le geste
    /// à VoiceOver, au Contrôle de sélection et au clavier externe. `.plain`
    /// pour qu'il ne reteinte pas le libellé — la pastille porte déjà ses
    /// couleurs. `.isSelected` dit **laquelle est cochée**, ce que le vert seul
    /// ne dit qu'à ceux qui le voient.
    private func chip(
        _ title: String,
        icon: Image?,
        isActive: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button(action: select) {
            BrandFilterChip(title, icon: icon, kind: .toggle, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Les trois traits du jeu de marque, à gauche de la barre.
    ///
    /// ⚠️ **Décoratif** : la maquette ne lui donne aucune action, et un
    /// pictogramme qui ne fait rien ne doit pas non plus se laisser toucher. Il
    /// dit ce qu'est cette ligne, comme un intitulé. À trancher avec Clara —
    /// voir la fiche écran.
    private var filterMark: some View {
        Image(brand: "IconFilter")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: markSide, height: markSide)
            .foregroundStyle(MemoBookColor.ink)
            // La hauteur d'une pastille : sans elle, le pictogramme est plus
            // court que ses voisines et la ligne se recentre autour de lui.
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .padding(.trailing, MemoBookSpacing.xs - 4)
            .accessibilityHidden(true)
    }

    @ScaledMetric(relativeTo: .subheadline) private var markSide: CGFloat = 20

    // MARK: - La mosaïque

    @ViewBuilder
    private var grid: some View {
        if model.isLoading {
            placeholders
        } else if model.isEmpty {
            emptyState
        } else {
            HStack(alignment: .top, spacing: GalleryMetrics.gutter) {
                ForEach(Array(model.columns.enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: GalleryMetrics.gutter) {
                        ForEach(column) { trip in
                            GalleryTripCard(trip: trip)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
        }
    }

    /// La grille d'attente : les mêmes colonnes, les mêmes gouttières, des
    /// vignettes vides.
    private var placeholders: some View {
        let count = GalleryMetrics.columnCount(for: typeSize)

        return HStack(alignment: .top, spacing: GalleryMetrics.gutter) {
            ForEach(0..<count, id: \.self) { column in
                VStack(spacing: GalleryMetrics.gutter) {
                    ForEach(Array(stride(from: column, to: 6, by: count)), id: \.self) { rank in
                        GalleryCardPlaceholder(rank: rank)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    /// Deux vides très différents : une galerie qui n'a encore rien, et une
    /// catégorie qui ne range rien. Aucun des deux n'est maquetté — voir la
    /// fiche écran.
    private var emptyState: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            Text(
                model.selectedCategoryId == nil
                    ? "Les premiers carnets arrivent"
                    : "Aucun carnet dans cette catégorie"
            )
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.ink)

            Text(
                model.selectedCategoryId == nil
                    ? "Reviens bientôt : la communauté partage ses carnets terminés ici."
                    : "Choisis « Tout » pour revoir tous les carnets."
            )
            .font(MemoBookFont.label)
            .foregroundStyle(MemoBookColor.inkMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if model.selectedCategoryId != nil {
                BrandButton("Tout afficher", style: .link) { model.select(nil) }
                    .padding(.top, MemoBookSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.xl)
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }

    // MARK: - Action

    /// Le voile du haut : les vignettes s'y **dissolvent** en passant sous la
    /// barre de filtres, au lieu de disparaître sur un trait net.
    ///
    /// Court — une gouttière et demie. Le voile du bas doit effacer un bloc de
    /// texte entier derrière un bouton ; celui-ci n'a qu'à adoucir un bord, et
    /// plus haut il mangerait la première rangée de la mosaïque.
    private var topScrim: some View {
        LinearGradient(
            colors: [
                MemoBookColor.background,
                MemoBookColor.background.opacity(0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: topScrimHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topScrimHeight: CGFloat { MemoBookSpacing.m }

    /// Le voile qui protège la lisibilité du bouton. Repris de l'accueil au
    /// point près : ce sont deux écrans qui portent le même bouton au même
    /// endroit, ils ne peuvent pas se dissoudre différemment.
    private var callToActionScrim: some View {
        LinearGradient(
            colors: [
                MemoBookColor.background.opacity(0),
                MemoBookColor.background,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: HomeMetrics.callToActionScrimHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Ce que le bouton propose dépend de ce qu'il y a à faire.
    ///
    /// Un carnet déjà ouvert — en cours, ou un départ prévu : on y **retourne**,
    /// et la flèche dit qu'on reprend le fil. Aucun : on en **crée** un, et
    /// c'est le plus qui le dit. La même question que sur l'accueil, et c'est
    /// le serveur qui y répond pour les deux écrans — voir
    /// ``Gallery/resumableTripId``.
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
        // Même limite que le CTA de l'accueil : au-delà d'AX1, une barre ancrée
        // en bas prend la moitié de l'écran et cache ce qu'elle sert à enrichir.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.s)
        .padding(.bottom, MemoBookSpacing.xs)
    }
}

// MARK: - Aperçus

#Preview("Exemples de carnets") {
    NavigationStack { GalleryView() }
}

#Preview("Exemples — aucun voyage en cours") {
    NavigationStack { GalleryView(model: GalleryModel { .emptyTravellerFixture }) }
}

#Preview("Exemples — galerie vide") {
    NavigationStack { GalleryView(model: GalleryModel { Gallery() }) }
}

#Preview("Exemples — erreur") {
    NavigationStack {
        GalleryView(model: GalleryModel { throw URLError(.notConnectedToInternet) })
    }
}

#Preview("Exemples — Dynamic Type AX3") {
    NavigationStack { GalleryView() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
