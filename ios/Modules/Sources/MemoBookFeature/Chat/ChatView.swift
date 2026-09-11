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
    /// photothèque ou appareil photo. Voir ``ChatPhotoFlow``.
    @State private var photos = ChatPhotoFlow()

    /// L'étape sur laquelle il reste à se poser en arrivant. Consommée **une
    /// fois** : se replacer à chaque nouveau message empêcherait de lire la
    /// suite.
    @State private var pendingFocus: String?

    public init(
        tripId: String,
        stepId: String? = nil,
        onIntent: @escaping (ChatIntent) -> Void = { _ in }
    ) {
        self.tripId = tripId
        self.onIntent = onIntent
        _model = State(initialValue: ChatModel(tripId: tripId, focusStepId: stepId))
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
        .chatPhotoFlow(photos) { model.sendPhotos($0) }
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
        // Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
        .onDisappear { model.teardown() }
    }

    // MARK: - Le fil

    private func conversation(_ thread: ChatThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: ChatMetrics.messageSpacing) {
                    notices

                    if let preview = thread.preview {
                        ChatPreviewBanner(preview: preview) { onIntent(.openBookPreview(memoId: tripId)) }
                            .padding(.bottom, MemoBookSpacing.snug)
                    }

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
            }
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
            .safeAreaInset(edge: .top, spacing: 0) { header(thread) }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer(proxy) }
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
