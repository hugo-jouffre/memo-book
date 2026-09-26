import MemoBookCore
import MemoBookDesign
import MemoBookRecording
import SwiftUI

/// L'accueil : où on en est de ses voyages, et le micro toujours à portée de
/// pouce.
///
/// **L'écran ne contient aucun contenu.** Titres, pays, dates, compteurs,
/// co-voyageurs, carte de découverte : tout vient du ``HomeFeed`` que porte
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
    ///
    /// **Arrivé, pas rechargé.** Il se lève dès que l'écran a quelque chose à
    /// montrer — ce que le cache avait, en quelques millisecondes — et non au
    /// retour du serveur : attendre l'aller-retour faisait durer le lancement
    /// exactement du temps que le cache était censé faire gagner (Hugo,
    /// 18/09/2026). Le serveur, lui, arrive quand il arrive, et le flash de
    /// rafraîchissement dit si quelque chose a changé.
    @State private var isLoaded = false

    @Environment(\.subscriptionSession) private var subscriptionSession

    /// La feuille d'enregistrement est ouverte. Même raison que celle du
    /// carnet : une feuille propose, elle ne navigue pas.
    @State private var isRecording = false

    /// Le paywall est ouvert — par le CTA verrouillé, quand les étapes offertes
    /// sont épuisées. Plein écran, comme depuis le profil.
    @State private var showsPaywall = false

    /// L'alerte système « Ton abonnement MemoBook s'est arrêté », ouverte quand
    /// la semaine payée s'est achevée depuis la dernière ouverture.
    ///
    /// **Une alerte du système et non une feuille de la marque** : elle
    /// n'arrive au bout d'aucun geste — on ouvre l'app, et on l'apprend. Une
    /// feuille qui monterait toute seule se lirait comme un écran de plus dans
    /// un parcours ; une alerte se lit comme une nouvelle, et c'est aussi la
    /// forme qu'iOS emploie lui-même pour annoncer la fin d'un abonnement.
    @State private var showsSubscriptionEnded = false

    /// Le dernier arrêt d'abonnement **déjà annoncé**, en secondes depuis 1970.
    ///
    /// Une date et non un booléen : l'alerte doit revenir au prochain
    /// abonnement qui s'arrête, et un drapeau posé une fois pour toutes
    /// l'aurait tue pour la vie du compte. Zéro tant que rien n'a été annoncé.
    ///
    /// Dans `UserDefaults` et non sur le serveur : c'est de l'état
    /// d'**affichage**, propre à cet appareil. Deux téléphones du même compte
    /// doivent chacun l'apprendre.
    @AppStorage("subscription.endAnnounced") private var announcedEnd: Double = 0

    /// La feuille « Nouveau carnet » est ouverte.
    ///
    /// Une feuille ne mène nulle part, elle propose, et ce n'est donc pas une
    /// entorse à la règle qui veut que l'accueil ne navigue pas. Ce qu'on y
    /// choisit, en revanche, redevient une ``HomeIntent`` que `RootView` route.
    @State private var isCreatingNotebook = false

    /// Le voyage dont on confirme la suppression — depuis le tiroir de sa
    /// carte (Hugo, 17/09/2026). La même feuille que celle des réglages du
    /// voyage : le bouton plein garde, le rouge supprime.
    @State private var tripToDelete: Trip?

    /// Le micro a été refusé dans iOS : la feuille ne s'ouvrira pas, et c'est
    /// cette boîte qui dit pourquoi, et où aller. `false` le reste du temps.
    @State private var showsMicrophoneDenied = false

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
        // Deux couches : le contenu qui défile, et le bouton qui reste — avec,
        // en fond, le voile de la marque qui dissout ce qui passe dessous
        // (``BrandFooterScrim``). Il descend jusqu'au bord de la dalle, sous
        // l'indicateur d'accueil, où le texte restait lisible.
        ZStack(alignment: .bottom) {
            scrollingContent
            recordCallToAction.brandFooterScrim()
        }
        .background {
            ZStack {
                MemoBookColor.background
                BrandMarkBackdrop(progress: 1, opacity: markOpacity)
            }
            .ignoresSafeArea()
        }
        .environment(\.homeContentHasAppeared, hasAppeared)
        .brandSheet(isPresented: $isCreatingNotebook) {
            NewNotebookSheet(
                resumableTrip: model.resumableTrip,
                join: { await model.join(code: $0) },
                onIntent: onIntent
            )
        }
        .brandSheet(item: $tripToDelete) { trip in
            DeleteTripSheet(
                tripName: trip.title,
                isDeleting: model.deletingTripId == trip.id,
                errorMessage: model.deletionError,
                onKeep: { tripToDelete = nil },
                onDelete: {
                    Task {
                        if await model.deleteTrip(id: trip.id) { tripToDelete = nil }
                    }
                }
            )
            .onDisappear { model.dismissDeletionError() }
        }
        // ⚠️ **Plus de glissé vers le profil** (Hugo, 19/09/2026). Il ouvrait
        // le profil d'un glissé vers la droite parti de n'importe où ; le geste
        // est retiré, et non inversé — vers la gauche, il entrerait en
        // concurrence avec le tiroir des cartes, qui va de ce côté-là. L'avatar
        // en haut à droite reste le chemin, et il est le seul.
        .brandSheet(isPresented: $isRecording) {
            // Deux choses, et les deux : l'envoi est l'affaire du modèle de
            // l'écran, comme son chargement — la file décide d'envoyer ou de
            // garder. Et **on arrive dans la conversation, le vocal déjà
            // posé** (Hugo, 14/09/2026) : c'est ça qui se route.
            RecordingSheet { audio, levels in
                // Un seul identifiant pour les deux : la bulle le porte, et la
                // file s'en sert pour dire où en est **cet** envoi-là. Sans
                // lui, la conversation devrait deviner — et elle devinerait
                // « envoyé » dès que MEMO répond, même sur un vocal qui attend
                // encore le réseau.
                let handoff = RecordingHandoff(audio: audio, levels: levels)
                Task { await model.upload(audio, levels: levels, handoffId: handoff.id) }
                if let tripId = ongoingTripId {
                    onIntent(.openConversation(tripId: tripId, handoff: handoff))
                }
            }
        }
        // **Le paywall, à la place du micro**, quand les étapes offertes sont
        // épuisées : on s'abonne avant de continuer — Hugo, 14/09/2026. Le
        // même écran que celui du profil, ouvert sur « Tu as enregistré tes
        // 3 premières étapes ».
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(
                subscription: .offer,
                previewMemoId: ongoingTripId,
                onSubscribe: {
                    subscriptionSession?.record(isSubscribed: true)
                    showsPaywall = false
                }
            )
        }
        // Ce que le serveur dit du palier, la session le retient : c'est ce qui
        // permet à un voyage ou à la conversation — qui n'ont pas de quota dans
        // leur réponse — de verrouiller leur micro aussi.
        .onChange(of: model.feed, initial: true) { _, feed in
            guard let feed else { return }
            subscriptionSession?.learn(feed.traveller.freemiumStatus(override: nil))
            announceSubscriptionEndIfNeeded(feed.traveller.subscriptionEndedOn)
        }
        // **L'alerte de fin d'abonnement.** Elle ne propose que deux gestes :
        // en prendre acte, ou se réabonner — et le second ouvre le paywall, où
        // l'offre est déjà écrite. Une alerte qui ne mènerait qu'à « D'accord »
        // annoncerait une porte fermée sans dire où est la poignée.
        .alert(
            SubscriptionCopy.endedTitle,
            isPresented: $showsSubscriptionEnded
        ) {
            Button(SubscriptionCopy.endedResubscribe) { showsPaywall = true }
            Button(SubscriptionCopy.endedDismiss, role: .cancel) {}
        } message: {
            Text(SubscriptionCopy.endedMessage(tripTitle: ongoingTripTitle))
        }
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task {
            await model.load()
            isLoaded = true
        }
        .onChange(of: model.feed != nil || model.errorMessage != nil, initial: true) { _, hasContent in
            if hasContent { isLoaded = true }
        }
        // **L'accueil s'ouvre sur ce qu'on avait, et le dit quand ça change.**
        // C'est l'écran qui gagne le plus au cache — c'est le premier — et
        // celui qui risque le plus de changer sous les yeux : une étape de
        // plus, un vocal transcrit, un solde d'étapes qui descend.
        .brandRefreshFlash(model.freshness.isUpdated)
        // Deux conditions, dans n'importe quel ordre : le contenu est là, et le
        // tracé du M ne couvre plus l'écran. C'est la seconde qui manquait —
        // l'accueil étant désormais monté **sous** le voile, sa cascade se
        // jouait en entier avant qu'on puisse la voir.
        .onChange(of: isReadyToRise) { _, ready in
            if ready { rise() }
        }
        .onAppear {
            if isReadyToRise { rise() }
            // On revient d'un écran poussé — un voyage, ses réglages, sa
            // suppression : l'accueil se relit, sans cascade ni écran vide,
            // pour que ce qui a changé là-bas se voie ici. Au premier passage,
            // rien n'est encore chargé et c'est `.task` qui s'en charge.
            if isLoaded { Task { await model.load() } }
        }
        // Le réseau qui tombe ou qui revient ne se voit pas quand on ne regarde
        // pas l'écran. VoiceOver l'annonce donc, une fois, à chaque changement :
        // c'est exactement ce que la boîte fait pour quelqu'un qui voit.
        .onChange(of: model.notice) { _, notice in
            guard let notice else { return }
            AccessibilityNotification.Announcement(notice.spokenMessage).post()
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

            noticeBox
                // La boîte apparaît et disparaît **pendant** qu'on regarde
                // l'écran — une coupure de réseau ne prévient pas. Elle se pose
                // donc au lieu de surgir, et l'animation vit ici plutôt que
                // dans le composant : c'est l'écran qui sait que sa valeur a
                // changé.
                .animation(.smooth(duration: 0.35), value: model.notice)
                .rising(1)

            if let message = model.errorMessage {
                ErrorBanner(message: message) {
                    Task { await model.retry() }
                }
                .rising(1)
            }

            if showsMicrophoneDenied {
                microphoneDeniedNotice.rising(1)
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

    // MARK: - L'état de la connexion

    /// La boîte d'information : hors ligne, vocaux en attente, envoi en cours,
    /// vocaux arrivés.
    ///
    /// Elle est **sous la salutation et au-dessus des voyages**, et elle y
    /// reste : une bande d'état qui change de place selon le message se
    /// cherche à chaque fois. Le contenu, lui, vient de ``HomeNotice`` — la vue
    /// n'écrit pas un mot de ces phrases, comme elle n'écrit pas les titres de
    /// voyages.
    @ViewBuilder
    private var noticeBox: some View {
        if let notice = model.notice {
            BrandNotice(notice.message)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
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
                        .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
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

    /// Le palier du compte. `nil` tant que l'accueil n'a rien reçu : on ne
    /// décide alors de rien, et surtout pas de peindre le CTA en lime.
    ///
    /// La session prime sur ce que le serveur a rendu : elle a pu voir une
    /// résiliation qu'aucune route ne sait encore écrire. Voir
    /// ``SubscriptionSession``.
    private var status: FreemiumStatus? {
        model.feed?.traveller.freemiumStatus(override: subscriptionSession?.override)
    }

    /// Le solde d'étapes offertes, et l'invitation qui le remplace quand il
    /// tombe à zéro.
    ///
    /// **Un seul message, un décompte** : « 3 étapes restantes », qui descend à
    /// chaque étape racontée, puis « Abonne-toi » quand il n'en reste plus. La
    /// pastille annonçait un cadeau (« 3 étapes offertes ») tant que rien
    /// n'était consommé ; deux formulations pour un même chiffre faisaient
    /// hésiter sur ce qu'il fallait lire. Arbitrage de Hugo, 07/09/2026.
    @ViewBuilder
    private var freeStepsPill: some View {
        if let label = status?.homePillLabel {
            BrandTagPill(label)
                .fixedSize()
                // De travers, comme le scotch des cartes : c'est une étiquette
                // collée sur l'avatar, pas un libellé d'interface.
                .rotationEffect(.degrees(-5))
                // Elle glisse vers le bord droit, au-delà de la marge de la
                // colonne. Alignée sur l'avatar, elle poussait sa moitié gauche
                // sous la Dynamic Island, où la fin du décompte devenait
                // illisible ; à droite, elle passe dessous et non dedans.
                .offset(x: MemoBookSpacing.s, y: -MemoBookSpacing.s - 4)
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
                    showsLiveDot: true,
                    onAdd: { isCreatingNotebook = true }
                )
                .rising(ongoingHeadingOrder)

                // Le voyage le plus récent porte sa couverture ; les autres
                // tiennent sur une ligne. Une seule photo par écran, celle qui
                // compte.
                if let featured = trips.first {
                    drawer(for: featured) {
                        FeaturedTripCard(trip: featured) { onIntent(.openTrip(id: featured.id)) }
                    }
                    .rising(ongoingHeadingOrder + 1)
                }

                ForEach(Array(trips.dropFirst().enumerated()), id: \.element.id) { index, trip in
                    drawer(for: trip) {
                        CompactTripCard(trip: trip) { onIntent(.openTrip(id: trip.id)) }
                    }
                    .rising(ongoingHeadingOrder + 2 + index)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if showsUpcomingSection {
            let trips = model.upcomingTrips

            // Le « + » ne se pose ici que si aucun voyage n'est en cours :
            // sinon il est déjà sur « Ton voyage », et deux ronds pour la même
            // porte se lisent comme deux portes.
            let addAction: (() -> Void)? =
                model.ongoingTrips.isEmpty ? { isCreatingNotebook = true } : nil

            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                HomeSectionHeading(title: "Voyage à venir", onAdd: addAction)
                    .rising(upcomingHeadingOrder)

                if trips.isEmpty {
                    UpcomingTripInvite { isCreatingNotebook = true }
                        .rising(upcomingHeadingOrder + 1)
                } else {
                    // La carte de la maquette `3125:33113` (Clara, 26/09/2026) :
                    // photo d'attente floutée, compte à rebours, scotch.
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        drawer(for: trip) {
                            UpcomingTripCard(trip: trip) { onIntent(.openTrip(id: trip.id)) }
                        }
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
                        drawer(for: trip) {
                            PastTripCard(trip: trip) {
                                onIntent(.openTrip(id: trip.id))
                            } onOrderPrint: {
                                onIntent(.orderPrint(tripId: trip.id))
                            }
                        }
                        .rising(pastHeadingOrder + 1 + index)
                    }
                }
            }
        }
    }

    /// Le tiroir d'une carte de voyage : **supprimer, partager, prévisualiser**
    /// — la croix, la flèche de partage, l'imprimante (Hugo, 17/09/2026). Le
    /// même ``BrandSwipeDrawer`` que la liste des co-voyageurs, au rayon des
    /// cartes de l'accueil. Le geste qui défait est le premier sous le doigt,
    /// et il demande confirmation ; les deux autres ouvrent l'aperçu du carnet.
    private func drawer<Card: View>(for trip: Trip, @ViewBuilder card: () -> Card) -> some View {
        BrandSwipeDrawer(
            actions: [
                BrandSwipeAction(
                    icon: "IconCross",
                    tint: MemoBookColor.error,
                    label: "Supprimer « \(trip.title) »"
                ) { tripToDelete = trip },
                BrandSwipeAction(
                    icon: "IconShareSystem",
                    tint: MemoBookColor.action,
                    label: "Partager « \(trip.title) »"
                ) { onIntent(.shareTrip(id: trip.id)) },
                BrandSwipeAction(
                    icon: "IconPrinter",
                    tint: MemoBookColor.action,
                    label: "Prévisualiser « \(trip.title) »",
                    // Le tracé de l'imprimante est plus petit dans sa boîte que
                    // les deux autres — voir ``BrandSwipeAction/iconScale``.
                    iconScale: 1.15
                ) { onIntent(.orderPrint(tripId: trip.id)) },
            ],
            content: card
        )
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
                onIntent(.openGallery)
            }
        }
    }

    // MARK: - Action

    /// Ce que le bouton propose dépend de ce qu'il y a à faire : raconter un
    /// voyage en cours, ou en créer un. Un micro devant quelqu'un qui n'a aucun
    /// carnet ouvert ne mène nulle part.
    private var hasOngoingTrip: Bool { ongoingTripId != nil }

    /// Le voyage que le bouton fait raconter : le premier en cours, celui que
    /// l'accueil montre en haut.
    private var ongoingTripId: String? { model.ongoingTrips.first?.id }

    /// Son titre, pour nommer le voyage dans l'alerte de fin d'abonnement.
    /// `nil` quand il n'y en a pas — la phrase se replie alors.
    private var ongoingTripTitle: String? { model.ongoingTrips.first?.title }

    /// Ouvre l'alerte **une seule fois par arrêt d'abonnement**.
    ///
    /// Le serveur ne dit que « la semaine payée s'est achevée ce jour-là », et
    /// il le dira à chaque chargement de l'accueil pendant quinze jours : c'est
    /// à l'app de se souvenir qu'elle l'a annoncé. D'où la date retenue plutôt
    /// qu'un drapeau — le prochain abonnement qui s'arrêtera portera une autre
    /// date, et l'alerte reviendra.
    private func announceSubscriptionEndIfNeeded(_ endedOn: Date?) {
        guard let endedOn else { return }
        let stamp = endedOn.timeIntervalSince1970
        guard stamp > announcedEnd else { return }
        announcedEnd = stamp
        showsSubscriptionEnded = true
    }

    /// Le CTA change de couleur et de destination, pas de place ni de taille.
    ///
    /// Il passe au lime et prend le cadenas **quand, et seulement quand, les
    /// étapes offertes sont épuisées** : la couleur dit « c'est fini, il faut
    /// s'abonner », la même que le bouton d'abonnement du profil — et il ouvre
    /// alors **le paywall, jamais le micro** (Hugo, 14/09/2026). Tant qu'il
    /// reste des étapes, il n'y a rien de bloqué et le parcours est celui de
    /// tout le monde — vert plein, et le micro.
    ///
    /// La feuille d'enregistrement ne s'ouvre donc **que** par ce chemin, et ce
    /// chemin vérifie le verrou : il n'y a pas de seconde porte. Le serveur
    /// referme la sienne de son côté (`quota_exhausted`).
    private var isBlocked: Bool { status?.isBlocked == true }

    private var recordCallToAction: some View {
        BrandButton(
            hasOngoingTrip ? "Commencer à enregistrer" : "Créer un nouveau voyage",
            // Le micro et le cadenas du jeu d'icônes de la marque, pas
            // l'illustration du Welcome : `BrandButton` teinte l'icône, il lui
            // faut un tracé plein d'une seule couleur.
            icon: callToActionIcon,
            style: isBlocked ? .accent : .primary,
            fillsWidth: true
        ) {
            // Verrouillé : le paywall, et rien d'autre. Sinon, un voyage
            // ouvert : on raconte. Aucun : il faut d'abord un carnet, et c'est
            // la feuille qui demande lequel.
            if isBlocked {
                showsPaywall = true
            } else if hasOngoingTrip {
                startRecording()
            } else {
                isCreatingNotebook = true
            }
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

    private var callToActionIcon: Image? {
        if isBlocked { return Image(brand: "IconLocker") }
        return hasOngoingTrip ? Image(brand: "IconMic") : nil
    }

    // MARK: - Le micro

    /// **La permission d'abord, la feuille ensuite** (Hugo, 17/09/2026).
    ///
    /// « Commencer à enregistrer » faisait disparaître l'app sur son iPhone :
    /// la feuille s'ouvrait et le micro démarrait pendant que la demande
    /// d'accès d'iOS montait par-dessus. Le premier appui ne fait donc que
    /// poser la question — l'app ne touche pas au micro avant la réponse — et
    /// c'est le second qui ouvre la feuille ; avec l'accès déjà accordé, le
    /// premier appui l'ouvre directement. La reconnaissance vocale est
    /// demandée dans la foulée, pour que la feuille n'ait plus rien à demander.
    ///
    /// Refusé, iOS ne repose jamais la question : la boîte le dit et mène aux
    /// Réglages, comme le micro barré de la conversation.
    private func startRecording() {
        switch RecordingPermission.current {
        case .granted:
            showsMicrophoneDenied = false
            isRecording = true
        case .undetermined:
            Task {
                guard await RecordingPermission.request() else {
                    showsMicrophoneDenied = true
                    return
                }
                _ = await SpeechTranscriber.requestAuthorization()
            }
        case .denied:
            showsMicrophoneDenied = true
        }
    }

    private var microphoneDeniedNotice: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            BrandNotice(
                "**Le micro est refusé** dans les réglages d’iOS : MemoBook ne peut pas t’écouter tant qu’il l’est.",
                tone: .information
            )
            BrandButton("Ouvrir les Réglages", style: .link) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        }
        .transition(.opacity)
    }
}

/// Les mesures de l'accueil.
enum HomeMetrics {
    /// L'avatar est **le** diamètre du design system : le chat pose le même
    /// devant son titre, et c'est à sa deuxième occurrence qu'il est monté dans
    /// `MemoBookSpacing`.
    static let avatarSide = MemoBookSpacing.avatarSide
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
