import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// La conversation avec MEMO : on raconte, il écoute, et le carnet se remplit
/// pendant ce temps-là.
///
/// **L'écran ne contient aucun contenu.** Titre, bulles, fiches, suggestions,
/// compteurs : tout vient du ``ChatThread`` que porte ``ChatModel``. Ce qui est
/// écrit ici, ce sont les seuls libellés qui appartiennent à l'interface — et
/// ils vivent eux-mêmes dans ``ChatCopy``.
///
/// **Aucune bulle blanche ne s'écrit à la main.** Chacune est produite par
/// ``MemoResponder`` à partir du message bleu qui la précède : c'est lui qui
/// lit ce qu'on vient de dire, choisit quoi répondre, et décide du temps qu'il
/// prend pour le faire.
///
/// **Trois couches, une seule qui défile.** Le fil occupe tout l'écran ;
/// l'en-tête et la barre d'envoi flottent au-dessus de lui sur un matériau
/// translucide. La conversation passe donc dessous et se laisse deviner — c'est
/// ce qui dit qu'elle continue au-delà des deux bords.
public struct ChatView: View {
    /// Le voyage dont on parle. Gardé pour les deux commandes de l'en-tête, qui
    /// mènent aux réglages du voyage et à l'aperçu de son carnet.
    private let tripId: String

    private let onIntent: (ChatIntent) -> Void

    /// On arrive avec un vocal enregistré depuis l'accueil. Le fil a déjà
    /// beaucoup à faire — poser la bulle, suivre la transcription, défiler —
    /// et la bannière d'aperçu n'y ajoute que du mouvement : elle ne descend
    /// pas à l'ouverture dans ce cas (Hugo, 18/09/2026).
    private let arrivesWithRecording: Bool

    @State private var model: ChatModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les fiches de retranscription dépliées. Un état de **lecture**, pas de
    /// donnée : il n'a rien à faire dans le modèle, et il se perd volontiers
    /// quand on quitte l'écran.
    @State private var expanded: Set<String> = []

    /// On est au bas du fil. C'est cette seule question qui décide si une
    /// nouvelle bulle fait défiler l'écran, et si « Retourner en bas »
    /// apparaît.
    @State private var isAtBottom = true

    /// L'instant où le bas du fil a quitté l'écran. Le pied qui grandit le
    /// recouvre **dans la même passe** que celle où sa hauteur est relevée :
    /// sans ce souvenir, ``keepPinned(_:footerHeight:)`` croyait qu'on avait
    /// remonté le fil, et le bandeau du crédit cachait la dernière bulle d'un
    /// fil long (recette du 03/10/2026).
    @State private var bottomLeftAt: Date?

    @FocusState private var isWriting: Bool

    /// Le parcours d'ajout de photos : autorisation, feuille de choix,
    /// photothèque ou appareil photo. Voir ``PhotoFlow``.
    @State private var photos = PhotoFlow()

    /// Le paywall, ouvert par le bouton « Raconter sans limite » d'une bulle de
    /// MEMO, ou par le bandeau « Crédit du jour épuisé » au-dessus de la barre
    /// (Hugo, 03/10/2026). Plus jamais par le micro lui-même : tout le monde
    /// raconte, cinq minutes par jour et par voyage.
    @State private var showsPaywall = false

    /// Le fil est posé : ce qui arrive **ensuite** est un envoi ou une
    /// réponse, et se dessine comme tel (voir ``rowTransition(for:)``). À
    /// l'ouverture, les messages déjà là ne rejouent pas leur arrivée.
    @State private var isSettled = false

    /// La puce de suggestion en vol : elle quitte la barre, devient bleue et
    /// monte se poser en bulle du voyageur (Hugo, 29/09/2026). `nil` le reste
    /// du temps. Voir ``launch(_:from:)``.
    @State private var flight: SuggestionFlight?

    /// Le haut de la barre d'envoi, en coordonnées globales : c'est là que la
    /// puce en vol atterrit, juste au-dessus.
    @State private var footerTop: CGFloat = 0
    @Environment(\.subscriptionSession) private var subscriptionSession

    /// L'étape sur laquelle il reste à se poser en arrivant. Consommée **une
    /// fois** : se replacer à chaque nouveau message empêcherait de lire la
    /// suite.
    @State private var pendingFocus: String?

    /// - Parameter model: le modèle, construit par `AppDependencies.chatModel`
    ///   — c'est lui qui tient le transport, serveur ou moteur local.
    /// - Parameter handoff: le vocal enregistré depuis l'accueil, à poser dans
    ///   le fil dès qu'il est chargé — voir ``RecordingHandoff``. Son envoi
    ///   n'appartient pas à la bulle : le modèle écoute la file par son
    ///   transport (``ChatModel/markDelivery(_:)``).
    public init(
        model: ChatModel,
        tripId: String,
        stepId: String? = nil,
        handoff: RecordingHandoff? = nil,
        onIntent: @escaping (ChatIntent) -> Void = { _ in }
    ) {
        self.tripId = tripId
        self.onIntent = onIntent
        self.arrivesWithRecording = handoff != nil
        if let handoff { model.expect(handoff) }
        _model = State(initialValue: model)
        _pendingFocus = State(initialValue: stepId)
        _showsPreviewBanner = State(initialValue: handoff == nil)
    }

    /// Pour les aperçus et les tests, qui fournissent leur propre modèle.
    init(
        model: ChatModel,
        stepId: String? = nil,
        onIntent: @escaping (ChatIntent) -> Void = { _ in }
    ) {
        self.tripId = "preview"
        self.onIntent = onIntent
        self.arrivesWithRecording = false
        _model = State(initialValue: model)
        _pendingFocus = State(initialValue: stepId)
    }

    /// Le repère invisible posé tout en bas du fil.
    ///
    /// Il sert deux fois : c'est la cible de « Retourner en bas », et c'est son
    /// apparition ou sa disparition qui dit si on est au bas de la
    /// conversation. iOS 18 le ferait avec `onScrollGeometryChange` ; on cible
    /// iOS 17, où c'est la façon la plus sûre de le savoir — et la moins chère,
    /// puisqu'elle ne mesure rien pendant le défilement.
    private static let bottomAnchor = "chat-bottom"

    /// L'espace de coordonnées du fil, pour mesurer de combien il a défilé.
    private static let scrollSpace = "chat-scroll"

    // MARK: La bannière « Ton carnet prend forme »

    /// La bannière d'aperçu en direct est **posée sur le fil**, pas dedans
    /// (Hugo, 17/09/2026).
    ///
    /// **Une règle, et deux sens** (Hugo, 19/09/2026) : on remonte vers les
    /// anciens messages, elle vient ; on redescend vers les récents, elle s'en
    /// va. Rien d'autre. Elle allait et venait trop vite — trois seuils se
    /// contredisaient : elle apparaissait à 80 pt de remontée et **repartait**
    /// à 200 pt du même geste, c'est-à-dire au milieu du défilement qui venait
    /// de la faire venir.
    ///
    /// **Le temps ne la reprend qu'à l'arrivée.** Elle se montre quatre
    /// secondes en ouvrant le fil, puis se retire. Rappelée par un geste, en
    /// revanche, elle **reste** : c'est une descente qui la renvoie, et rien
    /// d'autre. Un minuteur qui l'effaçait pendant qu'on lisait faisait
    /// exactement ce que Hugo décrit — elle allait et venait toute seule.
    @State private var showsPreviewBanner = true

    /// La fiche du contexte du voyage, ouverte depuis sa pastille.
    @State private var showsTripContext = false

    /// Le retrait différé de la bannière. Une tâche et non un minuteur : elle
    /// s'annule quand on quitte le fil, et se relance à chaque remontée.
    @State private var bannerLingerTask: Task<Void, Never>?

    /// Le bas de l'en-tête, en coordonnées globales : la bannière se pose
    /// juste dessous. Le bas et non la hauteur — l'en-tête s'étend sous la
    /// barre d'état, et sa hauteur comptée depuis le haut du fil la posait
    /// soixante points trop bas.
    @State private var headerBottom: CGFloat = 0

    /// Ce que le défilement a parcouru — voir ``ChatScrollTracker``. Un
    /// objet **non observé** gardé par `@State` : ses compteurs changent à
    /// chaque image de défilement, et rien à l'écran n'en dépend directement.
    @State private var scroll = ChatScrollTracker()

    /// Les seuils de la bannière — voir ``showsPreviewBanner``.
    ///
    /// Remonter demande un geste franc (60 pt) ; redescendre en demande un
    /// aussi (40 pt, et non 20 : à vingt points, le rebond d'un doigt qui
    /// s'arrête suffisait à la faire partir).
    private static let bannerRevealDistance: CGFloat = 60
    private static let bannerDismissDistance: CGFloat = 40
    private static let bannerLinger: Duration = .seconds(4)

    public var body: some View {
        Group {
            if let thread = model.thread {
                conversation(thread)
            } else if model.isLoading {
                ChatSkeleton()
            } else {
                failure
            }
        }
        .background(BrandBackdrop())
        .photoFlow(photos) { model.sendPhotos($0) }
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        // `.task` repart à **chaque** apparition, donc aussi au retour des
        // réglages, posés par-dessus dans la pile : « Supprimer la
        // conversation » a pu vider le fil, et c'est lui qu'on retrouve. Le fil
        // n'est jamais mis en cache — « un fil périmé se lit comme un message
        // perdu ». Pas de second rechargement en `onAppear` : deux lectures au
        // même instant, c'est deux reconstructions (22/09/2026).
        .task {
            await model.load()
            // Les bulles qu'on vient de lire sont posées ; celles qui suivent
            // arrivent.
            isSettled = true
        }
        // Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
        .onDisappear { model.teardown() }
        // La session d'abonnement, prêtée au modèle : un achat fait passer le
        // crédit du jour en illimité tout de suite — plus de bandeau, plus de
        // micro pâli —, sans attendre que le serveur le redise.
        .onAppear { model.subscription = subscriptionSession }
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(
                subscription: .offer,
                // La version « retour » pour qui a déjà été abonné — la session
                // l'a appris de l'accueil ou du profil.
                variant: subscriptionSession?.paywallVariant ?? .firstTime,
                previewMemoId: tripId,
                onSubscribe: {
                    subscriptionSession?.record(isSubscribed: true)
                    showsPaywall = false
                    model.refreshAfterSubscribing()
                }
            )
        }
    }

    // MARK: - Le fil

    private func conversation(_ thread: ChatThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ChatMetrics.messageSpacing) {
                    notices

                    ChatPrivacyNote()

                    if thread.isEmpty, let greeting = thread.greeting {
                        ChatGreetingView(greeting: greeting)
                    }

                    ForEach(model.messages) { message in
                        ChatMessageRow(
                            message: message,
                            model: model,
                            isExpanded: expanded.contains(message.id),
                            onToggleExpansion: { toggleExpansion(of: message.id) },
                            onCallToAction: perform
                        )
                        .id(message.id)
                        .transition(rowTransition(for: message))
                    }

                    if model.isThinking {
                        ChatThinkingBubble()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                        .onAppear {
                            isAtBottom = true
                            bottomLeftAt = nil
                        }
                        .onDisappear {
                            isAtBottom = false
                            bottomLeftAt = .now
                        }
                }
                .padding(.horizontal, MemoBookSpacing.snug)
                .padding(.vertical, MemoBookSpacing.s)
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.3),
                    value: model.messages.count
                )
                // **Le fil se lève dès que la puce décolle** (Hugo,
                // 30/09/2026) : la bulle qui monte se pose dans le creux qu'il
                // laisse au lieu de passer sur le dernier message. Un décalage
                // **de dessin**, et non une ligne de plus : insérer une ligne
                // dans le fil épinglé en bas le faisait d'abord sauter de sa
                // hauteur vers le bas, puis remonter. À l'atterrissage, le vrai
                // message prend la place du décalage dans la même image — voir
                // ``launch(_:from:)``.
                .offset(y: -(flight?.lift ?? 0))
                // De combien le fil a défilé, lu sur l'`UIScrollView` et non
                // par un `GeometryReader` : celui-là faisait boucler la liste
                // paresseuse sur un iPhone SE — voir ``brandScrollOffset(_:)``.
                // Seul le doigt compte : la liste qui se cale en bas à
                // l'ouverture remontait d'assez pour rappeler la bannière, qui
                // ne repartait plus.
                .brandScrollOffset { top, byUser in
                    if byUser {
                        trackScroll(to: top)
                    } else {
                        scroll.lastContentTop = top
                    }
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Une conversation s'ouvre sur sa fin : c'est le dernier message
            // qu'on vient lire, jamais le premier. Un fil **vide**, lui, n'a ni
            // haut ni bas — il a un centre, et c'est là que la maquette pose son
            // accueil.
            .defaultScrollAnchor(thread.isEmpty ? .center : .bottom)
            .onChange(of: model.messages.count) { _, _ in follow(proxy) }
            .task { await settleOnFocusedStep(proxy) }
            .onChange(of: model.isThinking) { _, isThinking in
                guard isThinking else { return }
                follow(proxy)
            }
            // **La bannière, par-dessus le fil**, juste sous l'en-tête. Elle
            // glisse vers le haut avec un rebond quand elle s'en va, et revient
            // de la même façon. En Reduce Motion, un fondu.
            .overlay(alignment: .top) {
                // Pendant le contexte du voyage, sa pastille tient la place :
                // deux capsules l'une sur l'autre se liraient comme une pile.
                if showsPreviewBanner, !isGatheringContext, let preview = thread.preview {
                    GeometryReader { proxy in
                        ChatPreviewBanner(preview: preview) { onIntent(.openBookPreview(memoId: tripId)) }
                            .frame(maxWidth: .infinity)
                            .padding(.top, max(0, headerBottom - proxy.frame(in: .global).minY) + MemoBookSpacing.xs)
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.35),
                value: showsPreviewBanner
            )
            // Quatre secondes à l'arrivée, puis elle s'en va toute seule. Pas
            // d'arrivée du tout avec un vocal de l'accueil — voir
            // ``arrivesWithRecording``.
            .task(id: thread.preview != nil) {
                guard thread.preview != nil, !arrivesWithRecording else { return }
                revealBanner(withdrawing: true)
            }
            // Quitter le fil emporte le retrait différé avec lui.
            .onDisappear {
                bannerLingerTask?.cancel()
                bannerLingerTask = nil
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header(thread)
                        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) {
                            headerBottom = $0
                        }
                    // **Dans** la marge du haut et non en calque : le fil se
                    // décale d'autant, et la pastille ne recouvre jamais la
                    // première bulle. Elle ne s'efface pas au défilement — elle
                    // dit ce qui manque tant qu'il manque quelque chose.
                    if let tripContext = thread.tripContext, tripContext.isGathering {
                        ChatTripContextBanner(context: tripContext) { showsTripContext = true }
                            .padding(.horizontal, MemoBookSpacing.screenMargin)
                            .padding(.bottom, MemoBookSpacing.xs)
                            .frame(maxWidth: .infinity)
                            // Le verre de l'en-tête, prolongé : le fil passe
                            // **dessous** en se floutant, jamais à côté de la
                            // capsule en restant lisible.
                            .background(ChatMetrics.barMaterial)
                            .transition(
                                reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                            )
                    }
                }
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.3),
                    value: isGatheringContext
                )
            }
            .sheet(isPresented: $showsTripContext) {
                if let tripContext = thread.tripContext {
                    ChatTripContextSheet(context: tripContext)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer(proxy)
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) {
                        footerTop = $0
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                        keepPinned(proxy, footerHeight: $0)
                    }
            }
            // La puce en vol, par-dessus le fil et la barre : elle part de la
            // barre et se pose au bas du fil, là où sa bulle va apparaître.
            .overlay { flyingSuggestion }
        }
    }

    // MARK: - L'arrivée d'une bulle

    /// Comment une bulle entre dans le fil : **elle grandit depuis son coin
    /// bas** — droit pour le voyageur, gauche pour MEMO —, comme si elle
    /// partait du point d'où on l'envoie (Hugo, 29/09/2026). Rien pour les
    /// bulles déjà là à l'ouverture, ni en Reduce Motion, ni pour la bulle qui
    /// prend la place d'une puce en vol, déjà posée par l'animation.
    private func rowTransition(for message: ChatMessage) -> AnyTransition {
        guard isSettled, !reduceMotion else { return .identity }
        // La bulle qui prend la place d'une puce en vol **y est déjà** : elle
        // apparaît sans transition, dans l'image où la puce disparaît. Un
        // fondu laissait voir les deux à la fois.
        if flight != nil, message.author.isTraveller { return .identity }
        let anchor: UnitPoint = message.author.isTraveller ? .bottomTrailing : .bottomLeading
        return .scale(scale: 0.35, anchor: anchor).combined(with: .opacity)
    }

    /// La puce qu'on vient de toucher, en vol.
    ///
    /// Elle se dessine **comme la bulle qu'elle va devenir** — bleue, en corps
    /// de bulle —, part du cadre de la puce et monte jusqu'au coin bas droit
    /// du fil. Arrivée, le vrai message est posé dessous et elle s'efface dans
    /// la même image : la bulle du fil prend le relais sans qu'on voie la
    /// couture.
    @ViewBuilder
    private var flyingSuggestion: some View {
        if let flight {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                // La place du prochain message au bas du fil : sous elle,
                // l'espacement des bulles, le repère d'un point et la marge
                // du fil. La bulle se centre sur sa **ligne**, qui ne descend
                // pas sous la hauteur de ses boutons d'action.
                let row = max(flight.size.height, MemoBookSpacing.minimumTapTarget)
                let landing = CGPoint(
                    x: proxy.size.width - MemoBookSpacing.snug - flight.size.width / 2,
                    y: footerTop - origin.y - MemoBookSpacing.s - 1 - ChatMetrics.messageSpacing
                        - row / 2
                )
                let start = CGPoint(
                    x: flight.from.midX - origin.x,
                    y: flight.from.midY - origin.y
                )
                let progress = flight.progress

                BrandChatBubble(author: .traveller) {
                    Text(flight.suggestion.label)
                        .font(MemoBookFont.bubble)
                        .foregroundStyle(MemoBookColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { self.flight?.size = $0 }
                .scaleEffect(0.7 + 0.3 * progress)
                // Posée : le vrai message est dessous, elle s'efface d'un coup.
                .opacity(flight.hasLanded ? 0 : 1)
                .position(
                    x: start.x + (landing.x - start.x) * progress,
                    y: start.y + (landing.y - start.y) * progress
                )
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Fait décoller une puce : le vol, puis l'envoi.
    ///
    /// L'envoi attend la fin du vol pour que la bulle n'apparaisse pas en bas
    /// pendant que la puce est encore à mi-chemin. En Reduce Motion, on envoie
    /// tout de suite.
    ///
    /// **Le fil se lève au décollage** (Hugo, 30/09/2026). Il ne montait
    /// qu'à l'arrivée du vrai message, et pendant le vol la bulle passait sur
    /// le dernier message du fil. Le fil se lève donc de la hauteur de la
    /// bulle en même temps qu'elle part, et c'est dans le creux qu'elle se
    /// pose. À l'atterrissage, le décalage et le vrai message s'échangent
    /// **sans animation propre** : l'un part, l'autre arrive à la même place.
    private func launch(_ suggestion: ChatSuggestion, from frame: CGRect) {
        // « Voir ma page » ouvre l'aperçu : rien ne part dans le fil, rien ne vole.
        if suggestion.intent == .openPreview {
            onIntent(.openBookPreview(memoId: tripId))
            return
        }
        guard !reduceMotion, flight == nil else {
            model.choose(suggestion, addPhotos: photos.begin)
            return
        }

        flight = SuggestionFlight(suggestion: suggestion, from: frame)
        // « Ajouter des photos » ne devient pas une bulle : rien à lever pour
        // elle. Et on ne lève que le bas du fil : remonté dans les anciens
        // messages, c'est ``follow(_:)`` qui ramène en bas à l'arrivée.
        let lifts = suggestion.intent != .importPhotos && isAtBottom
        Task { @MainActor in
            // Un tour de boucle pour que la bulle en vol soit mesurée et
            // posée sur la puce avant de partir.
            try? await Task.sleep(for: .milliseconds(30))
            // **Le creux s'ouvre avant que la bulle arrive** (Hugo,
            // 30/09/2026 : « pas suffisamment tôt »). Il se lève en un quart
            // de seconde, vif, pendant que la bulle part doucement et met une
            // demi-seconde : elle trouve toujours la place faite. Et il prend
            // la hauteur d'une **ligne** du fil, pas celle de la bulle — la
            // ligne ne descend jamais sous ses boutons d'action.
            if lifts, let size = flight?.size {
                withAnimation(.snappy(duration: 0.25)) {
                    flight?.lift = max(size.height, MemoBookSpacing.minimumTapTarget)
                        + ChatMetrics.messageSpacing
                }
            }
            withAnimation(.smooth(duration: 0.5)) { flight?.progress = 1 }
            try? await Task.sleep(for: .milliseconds(480))
            // L'échange, sans animation à lui : le fil retombe de ce qu'il
            // s'était levé au moment où le vrai message l'agrandit d'autant —
            // l'ancre du bas le garde épinglé —, et la puce s'efface. La barre,
            // elle, garde la place de ses suggestions pendant que MEMO répond
            // (``ChatModel/reservesSuggestionRail``) : rien ne se tasse.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                flight?.lift = 0
                flight?.hasLanded = true
                model.choose(suggestion, addPhotos: photos.begin)
            }
            try? await Task.sleep(for: .milliseconds(220))
            flight = nil
        }
    }

    /// MEMO recueille le contexte du voyage : sa pastille est posée.
    private var isGatheringContext: Bool {
        model.thread?.tripContext?.isGathering == true
    }

    /// Ce que le défilement fait à la bannière — voir ``showsPreviewBanner``.
    ///
    /// Le haut du contenu **monte** quand on descend vers les messages récents
    /// (il devient plus négatif) et **descend** quand on remonte vers les
    /// anciens. On cumule chaque sens tant qu'il dure ; un changement de sens
    /// remet l'autre compteur à zéro, pour qu'un tremblement du doigt ne
    /// compte pas.
    private func trackScroll(to top: CGFloat) {
        defer { scroll.lastContentTop = top }
        guard let previous = scroll.lastContentTop else { return }

        let delta = top - previous
        if delta > 0 {
            scroll.scrolledDown = 0
            scroll.scrolledUp += delta
            // On remonte : elle vient, et le délai repart de zéro tant que le
            // geste dure. C'est ce qui la fait **rester** pendant qu'on
            // remonte, au lieu de repartir au milieu du mouvement.
            if scroll.scrolledUp >= Self.bannerRevealDistance { revealBanner() }
        } else if delta < 0 {
            scroll.scrolledUp = 0
            scroll.scrolledDown -= delta
            if scroll.scrolledDown >= Self.bannerDismissDistance { hideBanner() }
        }
    }

    /// Montre la bannière, et la laisse.
    ///
    /// - Parameter withdrawing: elle se retire toute seule au bout de
    ///   ``bannerLinger``. Vrai **à l'arrivée seulement** : c'est une
    ///   présentation, pas une invitation qu'on garde sous les yeux. Rappelée
    ///   au doigt, elle attend qu'on redescende.
    ///
    /// ⚠️ **N'écrit que ce qui change.** Elle est appelée à chaque image d'une
    /// remontée : réécrire la même valeur dans un `@State` à chaque fois
    /// redessinait tout le fil, et sur un iPhone SE la liste paresseuse
    /// bougeait d'un cheveu en retour — une boucle, l'app à 100 % d'un cœur
    /// conversation ouverte et personne ne la touchant (recette du 30/09/2026).
    private func revealBanner(withdrawing: Bool = false) {
        if !showsPreviewBanner { showsPreviewBanner = true }
        if bannerLingerTask != nil {
            bannerLingerTask?.cancel()
            bannerLingerTask = nil
        }

        guard withdrawing else { return }
        bannerLingerTask = Task {
            try? await Task.sleep(for: Self.bannerLinger)
            guard !Task.isCancelled else { return }
            showsPreviewBanner = false
        }
    }

    private func hideBanner() {
        if bannerLingerTask != nil {
            bannerLingerTask?.cancel()
            bannerLingerTask = nil
        }
        if showsPreviewBanner { showsPreviewBanner = false }
    }

    private func header(_ thread: ChatThread) -> some View {
        ChatHeader(
            thread: thread,
            onBack: { dismiss() },
            onSettings: { onIntent(.openSettings(tripId: tripId)) },
            onBook: { onIntent(.openBookPreview(memoId: tripId)) }
        )
    }

    /// La barre d'envoi, et la pastille « Retourner en bas » posée au-dessus
    /// d'elle.
    ///
    /// ⚠️ **La pastille est empilée, pas posée en calque.** Un `overlay` décalé
    /// au-dessus du cadre de la barre se dessine très bien — et ne reçoit
    /// aucune touche : SwiftUI ne teste pas les doigts hors des limites de la
    /// vue qui porte le calque, et les taps traversaient la pastille pour
    /// atteindre la puce de suggestion en dessous. Elle occupe donc sa propre
    /// bande, transparente, au-dessus du matériau de la barre.
    private func footer(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            if !isAtBottom, !model.messages.isEmpty {
                ChatBackToBottomPill { scrollToBottom(proxy) }
                    .padding(.bottom, MemoBookSpacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ChatComposer(
                model: model,
                isWriting: $isWriting,
                onAddPhotos: photos.begin,
                onSubscribe: openPaywall,
                flyingSuggestionId: flight?.suggestion.id,
                onLaunch: launch
            )
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isAtBottom)
    }

    // MARK: - Ce qui ne va pas

    /// Les bandeaux en ligne, jamais des alertes : l'utilisateur garde le
    /// contexte de sa conversation.
    @ViewBuilder
    private var notices: some View {
        // Un fil local, sans le serveur : on peut raconter quand même, et
        // c'est ce que la boîte dit d'abord.
        if model.isOffline {
            BrandNotice(ChatCopy.offline)
        }

        if model.microphoneIsDenied {
            ErrorBanner(message: RecordingErrorCopy.permissionDenied) {
                openSettings()
            }
        }

        if let message = photos.deniedMessage {
            ErrorBanner(message: message) { openSettings() }
        }

        if let message = model.errorMessage {
            ErrorBanner(message: message) {
                Task { await model.load() }
            }
        }
    }

    /// La conversation n'a pas pu être chargée du tout : il n'y a pas de fil à
    /// montrer, donc pas de bandeau en ligne où poser l'erreur.
    private var failure: some View {
        VStack(spacing: MemoBookSpacing.s) {
            ErrorBanner(message: model.errorMessage ?? "") {
                Task { await model.load() }
            }
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Le défilement

    /// Suit la conversation **sans voler le défilement**.
    ///
    /// On ne redescend que si on était déjà en bas, ou si c'est nous qui venons
    /// de parler. Quelqu'un qui remonte pour relire une fiche ne doit pas se
    /// faire ramener en bas parce que MEMO a répondu — c'est le défaut le plus
    /// agaçant d'une messagerie, et il est gratuit à éviter.
    private func follow(_ proxy: ScrollViewProxy) {
        // Tant qu'on n'a pas atterri sur l'étape demandée, le fil ne suit rien :
        // sinon l'arrivée d'une bulle nous ramènerait en bas avant même d'avoir
        // vu la journée qu'on venait relire.
        guard pendingFocus == nil else { return }

        let weJustSpoke = model.messages.last?.author.isTraveller == true
        guard isAtBottom || weJustSpoke else { return }
        scrollToBottom(proxy)
    }

    /// Se pose sur le dernier message de l'étape qu'on est venu voir.
    ///
    /// **Le dernier, et pas le premier** : on ne rouvre pas une journée pour
    /// relire son début, on la rouvre pour voir où on en était. Sans étape à
    /// viser — ou si elle n'a rien encore —, le fil s'ouvre sur sa fin, comme
    /// d'habitude.
    ///
    /// ⚠️ **Trois tentatives, et c'est nécessaire.** Le fil s'ouvre ancré en
    /// bas dans une `LazyVStack` : les rangées du haut n'existent pas encore, et
    /// un `scrollTo` vers l'une d'elles ne fait alors rien du tout — sans
    /// erreur, sans rien. Chaque tentative en matérialise une partie, et la
    /// suivante va plus loin. C'est laid, et c'est le prix d'un défilement
    /// paresseux qu'on veut ouvrir ailleurs qu'à son ancre.
    ///
    /// L'ancre est consommée **une fois** : se replacer à chaque nouveau
    /// message empêcherait de lire la suite.
    private func settleOnFocusedStep(_ proxy: ScrollViewProxy) async {
        guard let stepId = pendingFocus,
            let target = model.thread?.lastMessage(about: stepId)
        else {
            pendingFocus = nil
            return
        }

        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .milliseconds(90)) }
            // Sans animation : c'est la position d'arrivée de l'écran, pas un
            // déplacement qu'on aurait demandé.
            proxy.scrollTo(target.id, anchor: .bottom)
        }

        pendingFocus = nil
    }

    /// **Le fil reste collé au pied quand le pied change de hauteur**
    /// (recette du 03/10/2026). Le bandeau du crédit qui paraît, la boîte
    /// « trop long », un champ qui prend une ligne : la marge du bas grandit,
    /// et le fil, lui, ne bougeait pas — en très grand texte, le bandeau
    /// cachait la dernière bulle, celle qu'on venait de dire. Si l'on était en
    /// bas, on y reste, au rythme du pied ; remonté dans les anciens messages,
    /// on ne vole pas le défilement.
    private func keepPinned(_ proxy: ScrollViewProxy, footerHeight height: CGFloat) {
        let previous = scroll.footerHeight
        scroll.footerHeight = height
        // Le premier relevé n'est pas un changement ; une puce en vol et
        // l'arrivée sur une étape tiennent déjà le défilement ; un fil vide
        // n'a pas de bas, il a un centre.
        // « En bas », ou à l'instant encore : le pied qui vient de grandir a
        // pu recouvrir le repère du bas avant ce relevé.
        let leftJustNow = bottomLeftAt.map { Date.now.timeIntervalSince($0) < 0.5 } ?? false
        guard previous > 0, abs(height - previous) > 0.5, isAtBottom || leftJustNow, pendingFocus == nil,
            flight == nil, !model.messages.isEmpty
        else { return }
        // **Une image plus tard** : ce relevé arrive pendant la mise en page,
        // avant que le nouvel encart du bas ne soit appliqué au défilement. Un
        // `scrollTo` immédiat visait l'ancien bas — juste sur un fil court, où
        // il reste de la place, faux sur un fil long.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Quand une puce vient d'atterrir, le fil est **déjà** à sa place : le
        // décalage qui l'avait levé retombe dans l'image où le vrai message
        // arrive. Animer ce défilement-là le faisait plonger de la hauteur de
        // la bulle, puis remonter en 0,3 s (vu en vidéo, 30/09/2026).
        let landing = flight?.hasLanded == true
        withAnimation(reduceMotion || landing ? nil : .smooth(duration: 0.3)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - Actions

    /// Ce que le bouton d'une bulle de MEMO ouvre — ``ChatCallToAction/Kind``.
    /// Rien ne part dans le fil : un bouton ouvre un écran, il ne dit rien à
    /// MEMO. Chaque destination passe par le chemin qui l'ouvre déjà d'ici —
    /// l'en-tête pour les réglages et l'aperçu, la puce pour les photos.
    private func perform(_ callToAction: ChatCallToAction) {
        switch callToAction.kind {
        case .subscribe:
            openPaywall()
        case .openTripSettings:
            onIntent(.openSettings(tripId: tripId))
        case .openPreview:
            onIntent(.openBookPreview(memoId: tripId))
        case .importPhotos:
            photos.begin()
        case .openPhotoSettings:
            openSettings()
        case .unknown:
            // Jamais affiché (``ChatModel/showsCallToAction(_:)``) : un bouton
            // inconnu ne mènerait nulle part.
            break
        }
    }

    /// Le paywall en plein écran. Le clavier se replie d'abord : il resterait
    /// sinon ouvert derrière l'offre, et au retour.
    private func openPaywall() {
        isWriting = false
        showsPaywall = true
    }

    private func toggleExpansion(of id: String) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }

    /// iOS ne présente la demande de micro **qu'une fois** : une fois refusée,
    /// le seul recours est l'app Réglages, et l'écran doit y mener au lieu de
    /// redemander en boucle. Même chemin pour l'accès aux photos — le bouton
    /// « Modifier l’autorisation » d'une bulle de MEMO.
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Les commandes dont l'écran n'est pas encore dessiné : le menu, les
    /// réglages du voyage, la carte, et l'aperçu du carnet.
    ///
    /// Elles gardent leur bouton parce que la maquette les montre, et ne mènent
    /// nulle part parce que rien n'existe derrière — même parti pris que les
    /// intentions non routées de l'accueil, du profil et de l'accueil d'un
    /// voyage, et il se voit ici, en un seul endroit.
}

/// Le message d'un micro refusé, recopié de ``RecordingError`` pour que l'écran
/// puisse l'afficher sans avoir d'erreur sous la main.
private enum RecordingErrorCopy {
    static let permissionDenied =
        "MemoBook a besoin du micro pour enregistrer tes souvenirs. Autorise l’accès dans Réglages."
}

// MARK: - Aperçus

#Preview("Chat") {
    NavigationStack {
        ChatView(
            model: .preview(thread: .conversationFixture(tripId: "trip-rome"))
        )
    }
}

#Preview("Chat — conversation neuve") {
    NavigationStack {
        ChatView(model: .preview(thread: .fixture(tripId: "trip-rome")))
    }
}

#Preview("Chat — MEMO réfléchit") {
    NavigationStack {
        ChatView(
            model: .preview(
                thread: .conversationFixture(tripId: "trip-rome"),
                turn: .thinking
            )
        )
    }
}

#Preview("Chat — micro armé") {
    NavigationStack {
        ChatView(
            model: .preview(
                thread: .conversationFixture(tripId: "trip-rome"),
                composer: .speaking
            )
        )
    }
}

#Preview("Chat — crédit du jour épuisé") {
    NavigationStack {
        ChatView(model: .preview(thread: .creditExhaustedFixture(tripId: "trip-rome")))
    }
}

#Preview("Chat — trop long pour une journée") {
    NavigationStack {
        ChatView(model: .preview(thread: .tooLongForADayFixture(tripId: "trip-rome")))
    }
}

#Preview("Chat — bouton de MEMO touché") {
    let model = ChatModel.preview(thread: .creditExhaustedFixture(tripId: "trip-rome"))
    model.followCallToAction(of: ChatThread.exhaustedNoticeFixtureId)
    return NavigationStack {
        ChatView(model: model)
    }
}

#Preview("Chat — chargement") {
    ChatSkeleton()
        .environment(\.colorScheme, .light)
}

#Preview("Chat — erreur") {
    NavigationStack {
        ChatView(
            model: ChatModel(transport: .failing(URLError(.notConnectedToInternet)))
        )
    }
}

#Preview("Chat — Dynamic Type AX3") {
    NavigationStack {
        ChatView(
            model: .preview(thread: .conversationFixture(tripId: "trip-rome"))
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// Ce que la conversation demande à l'app d'ouvrir.
///
/// Deux destinations, et elles sortent toutes les deux de l'en-tête : les
/// réglages du voyage, et l'aperçu de son carnet. Comme partout, ``RootView``
/// seul tient la pile de navigation.
public enum ChatIntent: Sendable, Hashable {
    case openSettings(tripId: String)
    /// L'aperçu du carnet. Ouvert de **deux** endroits du même écran — la
    /// bannière bleue du fil et l'icône de carnet de l'en-tête — et c'est
    /// voulu : la bannière se voit quand on lit le fil, l'icône quand on ne
    /// l'a pas sous les yeux.
    case openBookPreview(memoId: String)
}

/// Une puce de suggestion en vol vers le fil — voir ``ChatView/launch(_:from:)``.
/// Les compteurs du défilement de la conversation : de combien on a remonté
/// ou redescendu sans changer de sens, depuis le haut du contenu mesuré en
/// dernier. Une classe **sans observation** : les écrire ne redessine rien —
/// seule la bannière qu'ils décident de montrer est un état de l'écran.
final class ChatScrollTracker {
    /// `nil` avant la première mesure : la première n'est pas un mouvement.
    var lastContentTop: CGFloat?
    var scrolledUp: CGFloat = 0
    var scrolledDown: CGFloat = 0
    /// La hauteur du pied au dernier relevé — voir ``ChatView``, qui garde le
    /// fil collé en bas quand elle change. Zéro avant la première mesure.
    var footerHeight: CGFloat = 0
}

struct SuggestionFlight: Equatable {
    let suggestion: ChatSuggestion
    /// Le cadre de la puce au départ, en coordonnées globales.
    let from: CGRect
    /// La taille de la bulle en vol, mesurée une fois posée.
    var size: CGSize = .zero
    /// De 0 (sur la puce) à 1 (posée au bas du fil).
    var progress: CGFloat = 0
    /// De combien le fil se lève pour laisser la place à la bulle : sa
    /// hauteur et l'espacement des bulles. Zéro quand rien ne se lève.
    var lift: CGFloat = 0
    /// Le vrai message a pris sa place : la puce s'efface.
    var hasLanded = false
}
