import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'accueil : où on en est de ses voyages, et le micro toujours à portée de
/// pouce.
///
/// **L'écran ne contient aucun contenu.** Titres, pays, dates, compteurs,
/// compagnons, carte de découverte : tout vient du ``HomeFeed`` que porte
/// ``HomeModel``. Ce qui est écrit ici, ce sont les seuls libellés qui
/// appartiennent à l'interface — les titres de section et l'appel à l'action.
///
/// **Le CTA ne défile pas.** Il est posé en `safeAreaInset` : il reste sous le
/// pouce quelle que soit la longueur de la liste, et le contenu se réserve
/// tout seul la place qu'il occupe.
///
/// **L'écran ne navigue pas.** Il émet des ``HomeIntent`` ; c'est `RootView`
/// qui décide où elles mènent.
public struct HomeView: View {
    @State private var model: HomeModel
    private let onIntent: (HomeIntent) -> Void

    /// Chaque bloc monte de quelques points en apparaissant, l'un après
    /// l'autre. C'est ce décalage qui prolonge le tracé du M au lieu de faire
    /// tomber l'écran d'un bloc.
    @State private var hasAppeared = false

    /// Le M du lancement ne s'en va pas : il descend de 50 % à 20 % et reste
    /// derrière le contenu. Il part de l'opacité du tracé pour que le passage
    /// depuis l'écran de lancement ne saute pas.
    @State private var markOpacity = BrandMarkBackdrop.drawingOpacity

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: HomeModel = HomeModel(),
        onIntent: @escaping (HomeIntent) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        // Trois couches, chacune une seule responsabilité : le contenu qui
        // défile, le voile qui l'efface en bas, le bouton qui reste. Le voile
        // ne peut pas vivre dans le `safeAreaInset` du bouton — un
        // `ignoresSafeArea` posé là ne descend pas sous l'indicateur d'accueil,
        // et c'est justement la bande où le texte restait lisible.
        ZStack(alignment: .bottom) {
            scrollingContent
            callToActionScrim
            recordCallToAction
        }
        .background {
            ZStack {
                MemoBookColor.background
                BrandMarkBackdrop(progress: 1, opacity: markOpacity)
            }
            .ignoresSafeArea()
        }
        .environment(\.homeContentHasAppeared, hasAppeared)
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task {
            await model.load()

            // Une passe de rendu avant de lever le drapeau, sinon rien ne
            // bouge : `animation(_:value:)` n'anime qu'un **changement**, et
            // le contenu qui vient d'être posé naîtrait déjà en place. Le jeu
            // d'essai revient sans jamais suspendre, donc rien ne s'était
            // affiché entre-temps. Cette attente-là est la seule chose qui
            // sépare l'état « en bas, transparent » de l'état final.
            try? await Task.sleep(for: .milliseconds(16))

            hasAppeared = true
            withAnimation(.smooth(duration: 0.8)) {
                markOpacity = BrandMarkBackdrop.restingOpacity
            }
        }
    }

    private var scrollingContent: some View {
        ScrollView {
            // Rien tant qu'il n'y a rien à montrer. Sans ce garde-fou, le
            // premier rendu affichait « Bienvenue 👋 » sans prénom, puis le
            // remplaçait — et la cascade rendait le fondu croisé des deux
            // textes bien visible. L'écran de lancement couvre cette attente.
            VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
                if model.feed != nil || model.errorMessage != nil {
                    loadedContent
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.m)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        // Le bouton est dessiné par la pile, pas ici : cet encart ne sert qu'à
        // lui **réserver sa place**, pour que le dernier carnet de la liste
        // puisse défiler jusqu'au-dessus de lui. `hidden()` garde la hauteur
        // exacte du bouton, Dynamic Type compris.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            recordCallToAction.hidden()
        }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var loadedContent: some View {
        Group {
            greeting.rising(0)

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                    .rising(1)
                }

                if model.isEmpty {
                    HomeEmptyState().rising(1)
                } else {
                    ongoingSection
                    pastSection
                }

            showcaseSection.rising(showcaseOrder)
        }
    }

    // MARK: - En-tête

    @ViewBuilder
    private var greeting: some View {
        let name = model.feed?.traveller.firstName

        // Le prénom vient du serveur : sans lui, on salue quand même plutôt
        // que d'afficher un trou ou un « Bienvenue  » à deux espaces.
        //
        // L'espace avant la main est insécable : sur un petit écran la
        // salutation se coupe, et sans ça l'emoji se retrouvait seul sur sa
        // ligne. On coupe entre « Bienvenue » et le prénom, jamais avant la main.
        let title = name.map { "Bienvenue \($0)\u{00A0}👋" } ?? "Bienvenue\u{00A0}👋"

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                avatarButton
                Text(title).font(MemoBookFont.greeting).foregroundStyle(MemoBookColor.ink)
            }
        } else {
            HStack(alignment: .center, spacing: MemoBookSpacing.s) {
                Text(title)
                    .font(MemoBookFont.greeting)
                    .foregroundStyle(MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                avatarButton
            }
        }
    }

    private var avatarButton: some View {
        Button { onIntent(.openProfile) } label: {
            AsyncImage(url: model.feed?.traveller.avatarUrl) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(brand: "IconUser")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                        .foregroundStyle(MemoBookColor.ink)
                }
            }
            .frame(width: HomeMetrics.avatarSide, height: HomeMetrics.avatarSide)
            .background(MemoBookColor.outline, in: .circle)
            .clipShape(.circle)
        }
        .frame(
            minWidth: MemoBookSpacing.minimumTapTarget,
            minHeight: MemoBookSpacing.minimumTapTarget
        )
        .contentShape(.circle)
        .accessibilityLabel("Ton profil")
    }

    // MARK: - Les voyages

    // MARK: Rangs d'apparition
    //
    // Chaque élément monte à son tour. Les rangs se calculent à partir du
    // contenu plutôt que d'être écrits en dur : ajouter un voyage décale
    // automatiquement tout ce qui le suit.

    private var ongoingHeadingOrder: Int { 1 }
    private var pastHeadingOrder: Int { ongoingHeadingOrder + 1 + model.ongoingTrips.count }
    private var showcaseOrder: Int { pastHeadingOrder + 1 + model.pastTrips.count }

    @ViewBuilder
    private var ongoingSection: some View {
        let trips = model.ongoingTrips

        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                HomeSectionHeading(title: "Tes voyages en cours", showsLiveDot: true)
                    .rising(ongoingHeadingOrder)

                // Le voyage le plus récent porte sa couverture ; les autres
                // tiennent sur une ligne. Une seule photo par écran, celle qui
                // compte.
                if let featured = trips.first {
                    FeaturedTripCard(trip: featured) { onIntent(.openTrip(id: featured.id)) }
                        .rising(ongoingHeadingOrder + 1)
                }

                ForEach(Array(trips.dropFirst().enumerated()), id: \.element.id) { index, trip in
                    CompactTripCard(trip: trip) { onIntent(.openTrip(id: trip.id)) }
                        .rising(ongoingHeadingOrder + 2 + index)
                }
            }
        }
    }

    @ViewBuilder
    private var pastSection: some View {
        let trips = model.pastTrips

        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                HomeSectionHeading(title: "Tes voyages précédents", count: trips.count)
                    .rising(pastHeadingOrder)

                LazyVStack(spacing: MemoBookSpacing.s) {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        PastTripCard(trip: trip) {
                            onIntent(.openTrip(id: trip.id))
                        } onOrderPrint: {
                            onIntent(.orderPrint(tripId: trip.id))
                        }
                        .rising(pastHeadingOrder + 1 + index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var showcaseSection: some View {
        if let showcase = model.feed?.showcase {
            ShowcaseCard(showcase: showcase) {
                onIntent(.openShowcase(url: showcase.destinationUrl))
            }
        }
    }

    // MARK: - Action

    /// Le voile qui protège la lisibilité du CTA : 200 pt de haut, pleine
    /// largeur, opaque au ras du bas et transparent en haut. Le contenu qui
    /// défile s'y dissout au lieu de buter sur un bandeau.
    ///
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
        // Le dégradé est ancré au bas d'un cadre qui prend tout l'écran, safe
        // area comprise. Le poser directement dans la pile ne suffisait pas :
        // l'alignement `.bottom` le repinçait sur le bord de la safe area, et
        // `ignoresSafeArea` l'étirait alors vers le haut au lieu de le faire
        // descendre — la bande de l'indicateur d'accueil restait à découvert,
        // et c'est exactement là que le texte se lisait encore.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var recordCallToAction: some View {
        BrandButton(
            "Commencer à enregistrer",
            // Le micro du jeu d'icônes de la marque, pas l'illustration du
            // Welcome : `BrandButton` teinte l'icône, il lui faut un tracé
            // plein d'une seule couleur.
            icon: Image(brand: "IconMic"),
            fillsWidth: true
        ) {
            onIntent(.startRecording)
        }
        // Le libellé suit le Dynamic Type, mais s'arrête à AX1. Au-delà, une
        // barre ancrée en bas prend la moitié de l'écran et cache ce qu'elle
        // sert à enrichir — c'est la limite habituelle des barres persistantes.
        // VoiceOver, lui, lit le libellé entier quelle que soit la taille.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.s)
        .padding(.bottom, MemoBookSpacing.xs)
    }
}

/// Les mesures que l'accueil partage avec son écran de lancement : c'est parce
/// que le squelette et l'écran réel tombent au même endroit que le passage de
/// l'un à l'autre ne saute pas.
enum HomeMetrics {
    static let avatarSide: CGFloat = 40
    /// Hauteur du voile posé derrière le CTA fixe.
    static let callToActionScrimHeight: CGFloat = 200

    /// Largeur de la barre qui tient la place de la salutation.
    static let greetingPlaceholderWidth: CGFloat = 196
    static let greetingPlaceholderHeight: CGFloat = 26
    static let topPadding: CGFloat = MemoBookSpacing.xs
}

// MARK: - Apparition

extension EnvironmentValues {
    /// `true` une fois le contenu de l'accueil chargé et prêt à se poser.
    ///
    /// Il passe par l'environnement plutôt que d'être repassé à chaque appel :
    /// un rang suffit alors sur le lieu d'appel (`.rising(3)`), et aucun
    /// élément ne peut se retrouver oublié hors de la cascade.
    @Entry var homeContentHasAppeared: Bool = false
}

extension View {
    /// Fait monter un élément depuis le bas, en fondu, avec un retard qui suit
    /// son rang : le contenu se pose morceau par morceau au lieu de tomber
    /// d'un bloc, et prolonge le tracé du M plutôt que de lui succéder.
    fileprivate func rising(_ order: Int) -> some View {
        modifier(HomeRise(order: order))
    }
}

/// L'apparition d'un élément de l'accueil.
private struct HomeRise: ViewModifier {
    let order: Int

    @Environment(\.homeContentHasAppeared) private var hasAppeared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distance parcourue. Assez pour qu'on voie l'élément *arriver*, pas assez
    /// pour qu'il traverse l'écran.
    private static let travel: CGFloat = 40

    /// Écart entre deux éléments. Quelques dizaines de millisecondes : en
    /// dessous la cascade ne se lit plus, au-dessus elle traîne.
    private static let stagger: Double = 0.06

    /// Le retard est plafonné : au-delà d'une dizaine d'éléments, attendre une
    /// seconde de plus n'ajoute rien et retarde ce qu'on voulait voir.
    private static let maximumRank = 10

    func body(content: Content) -> some View {
        let settled = hasAppeared || reduceMotion

        return
            content
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : Self.travel)
            .animation(
                // Un soupçon de rebond : c'est ce qui fait qu'un élément se
                // *pose* au lieu de s'arrêter net.
                .smooth(duration: 0.5, extraBounce: 0.12)
                    .delay(Double(min(order, Self.maximumRank)) * Self.stagger),
                value: hasAppeared
            )
    }
}

// MARK: - Aperçus

#Preview("Accueil") {
    HomeView()
}

#Preview("Accueil — aucun voyage") {
    HomeView(model: HomeModel { .emptyFixture })
}

#Preview("Accueil — erreur") {
    HomeView(model: HomeModel { throw URLError(.notConnectedToInternet) })
}

#Preview("Accueil — Dynamic Type AX3") {
    HomeView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
