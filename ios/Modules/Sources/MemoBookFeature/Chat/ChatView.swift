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

    /// La file des vocaux, quand l'écran est ouvert par l'app.
    ///
    /// Elle n'est là que pour **une** chose : dire où en est l'envoi du vocal
    /// venu de l'accueil. La bulle est posée par ``RecordingHandoff``, mais son
    /// état d'envoi ne lui appartient pas — voir ``ChatModel/markHandoff(_:)``.
    /// `nil` en aperçu et en test, où rien n'a été enregistré ailleurs.
    private let outbox: RecordingOutbox?
    private let archive: ConversationArchive?

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

    @FocusState private var isWriting: Bool

    /// Le parcours d'ajout de photos : autorisation, feuille de choix,
    /// photothèque ou appareil photo. Voir ``PhotoFlow``.
    @State private var photos = PhotoFlow()

    /// Le paywall, ouvert par le micro quand les étapes offertes sont épuisées
    /// — le même verrou que sur l'accueil et sur un voyage.
    @State private var showsPaywall = false
    @Environment(\.subscriptionSession) private var subscriptionSession

    /// L'étape sur laquelle il reste à se poser en arrivant. Consommée **une
    /// fois** : se replacer à chaque nouveau message empêcherait de lire la
    /// suite.
    @State private var pendingFocus: String?

    /// - Parameter handoff: le vocal enregistré depuis l'accueil, à poser dans
    ///   le fil dès qu'il est chargé — voir ``RecordingHandoff``.
    /// - Parameter outbox: la file qui l'envoie, pour que la bulle suive son
    ///   sort au lieu de l'inventer.
    /// - Parameter archive: les conversations supprimées — voir
    ///   ``ConversationArchive``. Le fil se vide quand ce voyage y entre, y
    ///   compris depuis l'écran des réglages posé par-dessus celui-ci.
    public init(
        tripId: String,
        stepId: String? = nil,
        handoff: RecordingHandoff? = nil,
        outbox: RecordingOutbox? = nil,
        archive: ConversationArchive? = nil,
        onIntent: @escaping (ChatIntent) -> Void = { _ in }
    ) {
        self.tripId = tripId
        self.outbox = outbox
        self.archive = archive
        self.onIntent = onIntent
        let model = ChatModel(tripId: tripId, focusStepId: stepId, archive: archive)
        if let handoff { model.expect(handoff) }
        _model = State(initialValue: model)
        _pendingFocus = State(initialValue: stepId)
    }

    /// Pour les aperçus et les tests, qui fournissent leur propre source.
    init(
        model: ChatModel,
        stepId: String? = nil,
        tripId: String = "preview",
        onIntent: @escaping (ChatIntent) -> Void = { _ in }
    ) {
        self.tripId = tripId
        self.outbox = nil
        self.archive = nil
        self.onIntent = onIntent
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
    /// (Hugo, 17/09/2026). Elle apparaît à l'arrivée, s'en va vers le haut
    /// après quatre secondes, et revient dès que le doigt remonte de 20 pt
    /// dans la conversation — puis disparaît quand on remonte franchement
    /// (200 pt : on lit ses messages, on ne veut pas l'aperçu) ou dès qu'on
    /// redescend de 20 pt. Vivante : là quand on peut en avoir besoin, partie
    /// dès qu'on ne l'a plus.
    @State private var showsPreviewBanner = true

    /// La hauteur de l'en-tête, mesurée : la bannière se pose juste dessous.
    @State private var headerHeight: CGFloat = 0

    /// Le haut du contenu dans l'espace du fil, à la dernière mesure. `nil`
    /// avant la première : la première mesure n'est pas un mouvement.
    @State private var lastContentTop: CGFloat?

    /// De combien on a remonté (vers les anciens messages) sans redescendre,
    /// et l'inverse. Un changement de sens remet l'autre compteur à zéro.
    @State private var scrolledUp: CGFloat = 0
    @State private var scrolledDown: CGFloat = 0

    /// Les seuils de la bannière — voir ``showsPreviewBanner``.
    private static let bannerRevealDistance: CGFloat = 20
    private static let bannerReadingDistance: CGFloat = 200
    private static let bannerDismissDistance: CGFloat = 20
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
        // Rechargé quand une conversation est supprimée depuis les réglages :
        // cet écran reste sous le leur dans la pile, et c'est lui qu'on
        // retrouve en revenant — il doit alors être vide.
        .task(id: archive?.version ?? 0) { await model.load() }
        // L'envoi du vocal venu de l'accueil se joue **ailleurs** — dans la
        // file, qui vit au-dessus des écrans et continue pendant qu'on navigue.
        // La bulle ne fait que suivre ce qu'elle en dit, et `initial: true`
        // parce qu'il peut être arrivé avant que cet écran ne soit dessiné.
        .onChange(of: outbox?.handoffDelivery?.state, initial: true) { _, state in
            guard let state else { return }
            model.markHandoff(state)
        }
        // Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
        .onDisappear { model.teardown() }
        // Le verrou des étapes offertes : le micro mène au paywall au lieu de
        // s'ouvrir, tant qu'on n'est pas abonné (Hugo, 14/09/2026).
        .onAppear { model.onRecordingLocked = { showsPaywall = true } }
        .onChange(of: subscriptionSession?.isBlocked, initial: true) { _, blocked in
            model.isRecordingLocked = blocked == true
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(
                subscription: .offer,
                previewMemoId: tripId,
                onSubscribe: {
                    subscriptionSession?.record(isSubscribed: true)
                    showsPaywall = false
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

                    if thread.isEmpty, let greeting = thread.greeting {
                        ChatGreetingView(greeting: greeting)
                    }

                    ForEach(model.messages) { message in
                        ChatMessageRow(
                            message: message,
                            model: model,
                            isExpanded: expanded.contains(message.id),
                            onToggleExpansion: { toggleExpansion(of: message.id) }
                        )
                        .id(message.id)
                    }

                    if model.isThinking {
                        ChatThinkingBubble()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.horizontal, MemoBookSpacing.snug)
                .padding(.vertical, MemoBookSpacing.s)
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.3),
                    value: model.messages.count
                )
                // De combien le fil a défilé, lu sur le haut de son contenu.
                // Un `GeometryReader` en fond, et non `onScrollGeometryChange`
                // : celui-là est iOS 18, l'app cible iOS 17.
                .background {
                    GeometryReader { proxy in
                        let top = proxy.frame(in: .named(Self.scrollSpace)).minY
                        Color.clear.onChange(of: top) { _, value in trackScroll(to: value) }
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
                if showsPreviewBanner, let preview = thread.preview {
                    ChatPreviewBanner(preview: preview) { onIntent(.openBookPreview(memoId: tripId)) }
                        .padding(.horizontal, MemoBookSpacing.snug)
                        .padding(.top, headerHeight + MemoBookSpacing.xs)
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
            // Quatre secondes à l'arrivée, puis elle s'en va toute seule. Le
            // minuteur est structuré : quitter le fil l'annule.
            .task(id: thread.preview != nil) {
                guard thread.preview != nil else { return }
                showsPreviewBanner = true
                try? await Task.sleep(for: Self.bannerLinger)
                guard !Task.isCancelled else { return }
                showsPreviewBanner = false
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header(thread)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer(proxy) }
        }
    }

    /// Ce que le défilement fait à la bannière — voir ``showsPreviewBanner``.
    ///
    /// Le haut du contenu **monte** quand on descend vers les messages récents
    /// (il devient plus négatif) et **descend** quand on remonte vers les
    /// anciens. On cumule chaque sens tant qu'il dure ; un changement de sens
    /// remet l'autre compteur à zéro, pour qu'un tremblement du doigt ne
    /// compte pas.
    private func trackScroll(to top: CGFloat) {
        defer { lastContentTop = top }
        guard let previous = lastContentTop else { return }

        let delta = top - previous
        if delta > 0 {
            scrolledDown = 0
            scrolledUp += delta
            if scrolledUp >= Self.bannerReadingDistance {
                showsPreviewBanner = false
            } else if scrolledUp >= Self.bannerRevealDistance {
                showsPreviewBanner = true
            }
        } else if delta < 0 {
            scrolledUp = 0
            scrolledDown -= delta
            if scrolledDown >= Self.bannerDismissDistance {
                showsPreviewBanner = false
            }
        }
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

            ChatComposer(model: model, isWriting: $isWriting, onAddPhotos: photos.begin)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isAtBottom)
    }

    // MARK: - Ce qui ne va pas

    /// Les bandeaux en ligne, jamais des alertes : l'utilisateur garde le
    /// contexte de sa conversation.
    @ViewBuilder
    private var notices: some View {
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - Actions

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
    /// redemander en boucle.
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

#Preview("Chat — chargement") {
    ChatSkeleton()
        .environment(\.colorScheme, .light)
}

#Preview("Chat — erreur") {
    NavigationStack {
        ChatView(
            model: ChatModel(source: { throw URLError(.notConnectedToInternet) })
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
