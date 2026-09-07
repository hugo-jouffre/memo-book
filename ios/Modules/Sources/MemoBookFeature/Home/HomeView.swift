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

    /// Le contenu est arrivé. Ce n'est pas encore le signal de la cascade : il
    /// faut aussi que le tracé du M se soit effacé.
    @State private var isLoaded = false

    @Environment(\.launchOverlayIsVisible) private var isCoveredByLaunch
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
            isLoaded = true
        }
        // Deux conditions, dans n'importe quel ordre : le contenu est là, et le
        // tracé du M ne couvre plus l'écran. C'est la seconde qui manquait —
        // l'accueil étant désormais monté **sous** le voile, sa cascade se
        // jouait en entier avant qu'on puisse la voir.
        .onChange(of: isReadyToRise) { _, ready in
            if ready { rise() }
        }
        .onAppear {
            if isReadyToRise { rise() }
        }
    }

    /// Le contenu est chargé et plus rien ne le cache.
    private var isReadyToRise: Bool { isLoaded && !isCoveredByLaunch }

    /// Lance la cascade : chaque bloc monte à son tour, et le M passe derrière.
    private func rise() {
        guard !hasAppeared else { return }

        Task {
            // Une passe de rendu avant de lever le drapeau, sinon rien ne
            // bouge : `animation(_:value:)` n'anime qu'un **changement**, et un
            // contenu posé en même temps que le drapeau naîtrait déjà en place.
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

            ongoingSection
            upcomingSection
            pastSection

            showcaseSection.rising(showcaseOrder)
            helpLink.rising(showcaseOrder + 1)

            #if DEBUG
                HomeDebugPanel(model: model).rising(showcaseOrder + 2)
            #endif
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
            // La pastille déborde de l'avatar par le haut : c'est ce
            // chevauchement qui la rattache à lui plutôt que de la faire flotter
            // dans le coin de l'écran.
            .overlay(alignment: .topTrailing) { freeStepsPill }
        }
        .frame(
            minWidth: MemoBookSpacing.minimumTapTarget,
            minHeight: MemoBookSpacing.minimumTapTarget
        )
        .contentShape(.circle)
        .accessibilityLabel("Ton profil")
    }

    /// Le solde d'étapes offertes.
    ///
    /// Deux messages pour un seul compteur : tant que rien n'est consommé on
    /// annonce un cadeau, ensuite un solde. C'est le même chiffre, mais pas la
    /// même nouvelle.
    @ViewBuilder
    private var freeStepsPill: some View {
        if let traveller = model.feed?.traveller,
            let offered = traveller.offeredSteps,
            let remaining = traveller.remainingSteps,
            remaining > 0
        {
            let label = remaining == offered
                ? "\(offered) étapes offertes"
                : "\(remaining) étapes restantes"

            BrandTagPill(label)
                .fixedSize()
                // Le bord droit de la pastille s'aligne sur celui de l'avatar,
                // qui touche déjà la marge de l'écran : la décaler encore la
                // ferait sortir de la page.
                .offset(y: -MemoBookSpacing.s - 4)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Les voyages

    // MARK: Rangs d'apparition
    //
    // Chaque élément monte à son tour. Les rangs se calculent à partir du
    // contenu plutôt que d'être écrits en dur : ajouter un voyage décale
    // automatiquement tout ce qui le suit.

    private var ongoingHeadingOrder: Int { 1 }

    private var upcomingHeadingOrder: Int {
        ongoingHeadingOrder + (model.ongoingTrips.isEmpty ? 0 : 1 + model.ongoingTrips.count)
    }

    private var pastHeadingOrder: Int {
        upcomingHeadingOrder + (showsUpcomingSection ? 1 + max(model.upcomingTrips.count, 1) : 0)
    }

    private var showcaseOrder: Int {
        pastHeadingOrder + 1 + max(model.pastTrips.count, 1)
    }

    /// La section « à venir » n'apparaît pas toujours : elle sert soit à
    /// montrer un voyage déjà prévu, soit à inviter à en préparer un — et cette
    /// invitation n'a de sens que si rien n'est en cours.
    private var showsUpcomingSection: Bool {
        !model.upcomingTrips.isEmpty || model.ongoingTrips.isEmpty
    }

    @ViewBuilder
    private var ongoingSection: some View {
        let trips = model.ongoingTrips

        if !trips.isEmpty {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                // Le titre suit le nombre : un seul voyage, « Ton voyage » ;
                // plusieurs, « Tes voyages ». Le singulier figé sonnait faux dès
                // le deuxième carnet ouvert.
                HomeSectionHeading(
                    title: trips.count > 1 ? "Tes voyages" : "Ton voyage",
                    showsLiveDot: true
                )
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
    private var upcomingSection: some View {
        if showsUpcomingSection {
            let trips = model.upcomingTrips

            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                HomeSectionHeading(title: "Voyage à venir")
                    .rising(upcomingHeadingOrder)

                if trips.isEmpty {
                    UpcomingTripInvite { onIntent(.browseCommunity) }
                        .rising(upcomingHeadingOrder + 1)
                } else {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        CompactTripCard(trip: trip) { onIntent(.openTrip(id: trip.id)) }
                            .rising(upcomingHeadingOrder + 1 + index)
                    }
                }
            }
        }
    }

    /// Toujours là, même vide : c'est une promesse — les carnets terminés
    /// viendront se ranger ici.
    private var pastSection: some View {
        let trips = model.pastTrips

        return VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            HomeSectionHeading(title: "Voyages précédents", count: trips.count)
                .rising(pastHeadingOrder)

            if trips.isEmpty {
                PastTripsPlaceholder()
                    .rising(pastHeadingOrder + 1)
            } else {
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

    private var helpLink: some View {
        BrandButton("Besoin d’aide ?", style: .link, isSubdued: true) {
            onIntent(.openHelp)
        }
        .frame(maxWidth: .infinity)
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

    /// Ce que le bouton propose dépend de ce qu'il y a à faire : raconter un
    /// voyage en cours, ou en créer un. Un micro devant quelqu'un qui n'a aucun
    /// carnet ouvert ne mène nulle part.
    private var hasOngoingTrip: Bool { !model.ongoingTrips.isEmpty }

    private var recordCallToAction: some View {
        BrandButton(
            hasOngoingTrip ? "Commencer à enregistrer" : "Créer un nouveau voyage",
            // Le micro du jeu d'icônes de la marque, pas l'illustration du
            // Welcome : `BrandButton` teinte l'icône, il lui faut un tracé
            // plein d'une seule couleur.
            icon: hasOngoingTrip ? Image(brand: "IconMic") : nil,
            fillsWidth: true
        ) {
            onIntent(hasOngoingTrip ? .startRecording : .createTrip)
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
