import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
import Observation
import UIKit

/// Où en est le tour de parole en cours.
///
/// **Un seul état, porté par l'identifiant de la bulle concernée.** La vue ne
/// tient pas de second état parallèle : c'est ce qui garantit qu'un échec ne
/// puisse pas laisser l'indicateur d'attente allumé pendant que le composeur se
/// croit disponible.
public enum ChatTurnState: Sendable, Hashable {
    /// Rien en vol. Le composeur est ouvert, les suggestions sont là.
    case idle

    /// La bulle du voyageur est posée, l'envoi n'est pas confirmé.
    case sending(messageId: String)

    /// MEMO réfléchit. Trois points qui respirent à gauche, à la place de la
    /// bulle qui vient — jamais un `ProgressView` centré, qui ferait sauter le
    /// fil.
    case thinking

    /// Échec. La bulle du voyageur reste, marquée « Non envoyé », et le tour est
    /// rejouable tel quel.
    case failed(messageId: String, message: String)
}

/// Ce que la barre d'envoi propose.
///
/// Trois modes et pas quatre : « en train d'enregistrer » se lit sur
/// ``AudioRecorder/isRecording`` et n'a pas à être dupliqué ici — deux sources
/// pour le même fait finissent toujours par se contredire.
public enum ChatComposerMode: Sendable, Hashable {
    /// Les trois commandes de la maquette : photo, clavier, micro.
    case tools

    /// Le champ de saisie est ouvert.
    case writing

    /// Le micro est armé : le bouton « Record » occupe la barre.
    case speaking
}

/// Ce que l'écran de chat sait faire : charger sa conversation, envoyer ce que
/// le voyageur raconte, et laisser MEMO répondre — `docs/conversation.md`.
///
/// **Même construction que ``HomeModel``, ``TripHomeModel`` et
/// ``ProfileModel``** : le modèle ne connaît pas l'API, il reçoit un
/// ``ChatTransport`` — cinq fonctions-sources — et ne sait pas si derrière il
/// y a le serveur ou le moteur local des aperçus. Un seul chemin de code, deux
/// transports.
///
/// **Tout le déroulé d'un tour est ici, jamais dans la vue.** La bulle du
/// voyageur se pose avant le réseau et passe « envoyée » dès le reçu du
/// serveur ; MEMO répond dans un job, que le modèle **sonde** toutes les deux
/// secondes tant qu'un tour est en vol ou qu'une fiche n'est pas prête ; ses
/// bulles arrivent une par une, chacune après le silence que le serveur a
/// décidé pour elle, avec l'indicateur qui se rallume entre deux ; un échec
/// garde le message pour qu'on puisse le renvoyer, sous le **même**
/// identifiant. Une vue qui aurait à orchestrer ça se remettrait à clignoter
/// au premier refactoring.
@MainActor
@Observable
public final class ChatModel {
    public private(set) var thread: ChatThread?
    public private(set) var errorMessage: String?
    public private(set) var turn: ChatTurnState = .idle

    /// Le fil affiché n'est pas celui du serveur, mais le fil **local** —
    /// sans réseau, ou pour un voyage créé hors ligne que le serveur n'a pas
    /// encore reçu (``ChatThread/offline(trip:traveller:isNew:)``). On y raconte
    /// quand même : tout part dans la file. L'écran le dit, et le vrai fil
    /// revient dès qu'un message est arrivé.
    public private(set) var isOffline = false

    /// Le vrai fil est en cours de relecture, après un fil local.
    private var isReloading = false

    /// L'enregistrement a été refusé par iOS. La demande ne se présente qu'une
    /// fois : le seul recours est l'app Réglages, et l'écran doit le dire au
    /// lieu de redemander en boucle.
    public private(set) var microphoneIsDenied = RecordingPermission.current == .denied

    /// Le message dont le texte vient d'être copié. Il porte la coche verte
    /// pendant une seconde — voir ``copy(_:)``.
    public private(set) var copiedMessageId: String?

    // MARK: Le crédit du jour

    /// **Le crédit du jour du voyage** (Hugo, 03/10/2026) — ``DailyCredit`` :
    /// celui que le serveur a servi en dernier (``servedCredit``), rechargé si
    /// minuit est passé depuis (``DailyCredit/refreshed(now:calendar:)``), et
    /// **décompté ici** des tours partis d'ici que le serveur n'a pas encore
    /// reçus (``unreceivedCosts``). Le serveur tranche, l'app prévient : ce
    /// chiffre fait compter la barre pendant qu'on parle et pâlir le micro et
    /// l'envoi quand il n'y a plus rien — jamais il ne décide seul.
    ///
    /// `nil` : on ne sait rien — un serveur d'avant, un fil local ouvert sans
    /// souvenir du crédit. Le serveur refusera ce qui dépasse
    /// (``ChatDelivery/waitingForCredit(until:)``) ; hors ligne, l'écran
    /// plafonne quand même au crédit du catalogue (``credit``).
    public var dailyCredit: DailyCredit? {
        servedCredit?.refreshed(now: .now).consuming(unreceivedCosts.values.reduce(0, +))
    }

    /// **Le crédit servi**, et lui seul : le fil, une mise à jour, un reçu, un
    /// refus — ou, sans réseau, le dernier qu'on a connu pour ce voyage. Les
    /// estimations ne s'y mêlent jamais (03/10/2026) : un fil rouvert hors
    /// ligne repart de ce chiffre-ci, moins ce qui attend dans la file, et
    /// rouvrir dix fois ne décompte pas dix fois le même vocal.
    private var servedCredit: DailyCredit?

    /// Ce que coûte chaque tour parti d'ici que le serveur n'a **pas encore
    /// reçu** — en vol, ou en file —, par identifiant de bulle. Le serveur le
    /// comptera en le recevant : d'ici là, le crédit qu'il sert ne le contient
    /// pas, et la barre ne doit pas promettre ce qu'il prendra. Un tour sort
    /// d'ici à son reçu, à son refus, ou quand une lecture du fil le rend.
    /// Un dictionnaire et non un total : le même tour vu deux fois — rouvert
    /// depuis la file, renvoyé — ne coûte qu'une fois.
    private var unreceivedCosts: [String: Int] = [:]

    /// L'abonnement de la session, posé par l'écran : un achat fait passer en
    /// illimité **tout de suite**, sans attendre que le serveur le redise —
    /// ``SubscriptionSession/applied(to:)``.
    var subscription: SubscriptionSession?

    /// Le crédit qui fait foi à l'écran : celui du serveur, relu avec le
    /// dernier geste de la session.
    ///
    /// **Hors ligne et sans rien savoir du crédit, le pot du catalogue**
    /// (03/10/2026) : cinq minutes pleines, moins ce qui attend dans la file,
    /// tant que la session ne sait pas le compte illimité — elle l'apprend
    /// au lancement du cache de l'accueil, ou du profil. Ne rien compter
    /// laissait dicter un vocal de six minutes, sans bandeau ni coupure, que
    /// le serveur aurait refusé chaque jour ; plafonner à la limite ne retire
    /// rien qu'une journée aurait laissé passer. En ligne, le serveur sert
    /// toujours le sien : un serveur qui n'en sert pas ne compte pas, et
    /// l'app non plus.
    public var credit: DailyCredit? {
        if let known = dailyCredit { return subscription?.applied(to: known) ?? known }
        guard isOffline, thread != nil, subscription?.isUnlimited != true else { return nil }
        return DailyCredit(resetsAt: RecordingOutbox.creditReturns(nil))
            .consuming(unreceivedCosts.values.reduce(0, +))
    }

    /// Le bandeau « Crédit du jour épuisé » est demandé : on a touché le micro
    /// ou le clavier pâlis. **Il passe, il ne reste pas** (recette du
    /// 03/10/2026) : au repos, il s'efface après quelques secondes ou au geste
    /// suivant — une puce, des photos, la croix —, et le crédit qui revient
    /// l'emporte aussi. Voir ``showExhaustedNotice()``.
    public private(set) var showsExhaustedNotice = false

    /// Le retrait différé du bandeau « épuisé ».
    private var exhaustedNoticeTimer: Task<Void, Never>?

    /// Combien de temps le bandeau « épuisé » reste, une fois paru : de quoi
    /// le lire et le toucher, pas de quoi encombrer le pied. Une variable pour
    /// qu'un test n'attende pas cinq secondes.
    var exhaustedNoticeLinger = Duration.seconds(5)

    /// La phase du bandeau au dernier relevé, pour ne faire vibrer qu'à son
    /// apparition — voir ``watchCredit()``.
    private var lastRecordingPhase: DailyCredit.Phase = .calm

    /// Le vocal que la limite vient de couper. Hors ligne, il n'y a pas de
    /// reçu pour apporter la bulle de MEMO : l'app pose la sienne — voir
    /// ``postLocalExhaustedNotice()``.
    private var limitTurnId: String?

    /// Le texte de la fiche qu'on corrige « à la main », tel qu'il était : le
    /// serveur ne fait payer que ce qu'une correction **ajoute**.
    private var editingOriginalText: String?

    /// Ce qu'on a fait des boutons posés sous les bulles de MEMO — touché,
    /// ignoré —, par identifiant de bulle. Retenu sur l'appareil
    /// (``ChatCallToActionMemory``) : c'est l'état d'un geste, pas un fait du
    /// récit.
    public private(set) var callToActionStates: [String: ChatCallToActionState] = [:]
    private let callToActionMemory: ChatCallToActionMemory

    /// Le dernier crédit **servi** de chaque voyage, le temps que l'app vive :
    /// un fil rouvert sans réseau dans le métro garde de quoi compter, au lieu
    /// de laisser parler sans limite jusqu'à un refus. En mémoire seulement,
    /// et jamais une estimation (``servedCredit``) : ce qui attend dans la
    /// file se redécompte à chaque ouverture, depuis ce chiffre-ci.
    ///
    /// **Il appartient au compte qui l'a lu** (03/10/2026) : il porte son
    /// `isUnlimited`. Oublié à chaque changement de compte —
    /// ``forgetRememberedCredits()`` —, sans quoi le fil hors ligne de B,
    /// connecté après A sur le même iPhone, se croyait illimité et apprenait
    /// à la session un abonnement que B n'a jamais pris.
    private static var rememberedCredits: [String: DailyCredit] = [:]

    /// Oublie le dernier crédit servi de chaque voyage — à chaque changement
    /// de compte, avec ce que l'app garde du compte qui s'en va
    /// (``AppDependencies/forgetAccountContent()``), là même où la session
    /// d'abonnement est remise à zéro.
    public static func forgetRememberedCredits() {
        rememberedCredits = [:]
    }

    /// Ce que le bandeau du crédit montre dans un aperçu, où le micro ne tourne
    /// pas. Jamais posé hors de ``preview(thread:turn:composer:draft:microphoneIsDenied:focusStepId:dailyCredit:showsExhaustedNotice:creditBanner:)``.
    private var previewCreditBanner: DailyCreditBanner?

    public var composer: ChatComposerMode = .tools
    public var draft: String = ""

    /// Le brouillon est une retranscription qu'on corrige, et non un message
    /// qu'on écrit. Le champ s'y étire plus haut — corriger un texte de
    /// cinquante mots demande de le **lire**, et six lignes en cachent la
    /// moitié. Retombe à faux dès que le brouillon part ou se jette.
    public private(set) var isEditingTranscript = false

    /// Le souvenir que le brouillon corrige — « à la main ». Envoyer le
    /// brouillon passe alors par ``ChatTransport/editTranscript`` et non par
    /// un nouveau message : la fiche change, le fil n'en gagne pas une copie.
    private var editingEntryId: String?

    public let recorder = AudioRecorder()
    public let player = AudioNotePlayer()
    public let reader = SpeechReader()

    private let transport: ChatTransport

    /// Le curseur du sondage : le `now` de la dernière lecture, en temps
    /// **serveur** — jamais l'horloge du téléphone, qui peut être fausse.
    private var cursor: Date?

    /// Les niveaux du micro, accumulés pendant qu'on parle.
    ///
    /// ``AudioRecorder`` ne publie qu'un niveau **instantané** : sans cette
    /// collecte, la forme d'onde d'un vocal terminé n'aurait aucune donnée et
    /// il faudrait en dessiner une fausse. C'est la seule raison de cette
    /// boucle.
    public private(set) var capturedLevels: [Double] = []
    private var levelSampler: Task<Void, Never>?

    private var exchange: Task<Void, Never>?
    private var poller: Task<Void, Never>?

    /// Le tour dont l'envoi a échoué. ``retry()`` le renvoie **tel quel**, sous
    /// le même identifiant : le serveur reconnaît un renvoi et ne crée pas un
    /// second souvenir.
    private var pending: OutgoingTurn?

    /// L'écoute de la file — voir ``markDelivery(_:)``. Une tâche, qui meurt
    /// avec l'écran.
    private var deliveryWatcher: Task<Void, Never>?

    /// Le dernier mot de la file, gardé au cas où il arrive **avant** le fil —
    /// l'écran s'ouvre pendant que le vocal de l'accueil part. Il est rejoué
    /// dès que le fil est là.
    private var latestDelivery: ChatTurnDelivery?

    /// - Parameters:
    ///   - transport: ce qui relie le modèle au monde — le serveur, ou le
    ///     moteur local des aperçus. Voir ``ChatTransport``.
    ///   - focusStepId: l'étape sur laquelle le fil s'ouvre, quand on vient
    ///     d'une carte d'étape.
    ///   - callToActionMemory: où retenir ce qu'on a fait des boutons des
    ///     bulles — les réglages de l'appareil, sauf dans un test.
    public init(
        transport: ChatTransport,
        focusStepId: String? = nil,
        callToActionMemory: ChatCallToActionMemory = .standard
    ) {
        self.transport = transport
        self.focusStepId = focusStepId
        self.callToActionMemory = callToActionMemory
    }

    /// L'étape sur laquelle le fil s'est ouvert, quand on vient d'une carte
    /// d'étape.
    public private(set) var focusStepId: String?

    /// L'étape à laquelle rattacher un nouveau message : celle qu'on est venu
    /// voir, ou à défaut celle où le voyage en est.
    private var activeStepId: String? {
        focusStepId ?? thread?.context.stepId
    }

    /// Le silence minimal avant une bulle de MEMO. Sans lui, une réponse
    /// arriverait dans la même image que le message du voyageur : c'est le
    /// premier signe qu'il n'y a personne en face.
    private static let minimumThinking = Duration.milliseconds(450)

    /// La cadence du sondage, et le moment où il renonce : le motif de la
    /// feuille Statistiques — pas de connexion ouverte, pas de minuterie
    /// globale, une tâche qui meurt avec l'écran.
    private static let pollingInterval = Duration.seconds(2)
    private static let pollingGivesUpAfter = 90  // × 2 s = trois minutes sans changement

    // MARK: - Charger

    /// `true` tant qu'on n'a rien à montrer. L'écran dessine alors son
    /// squelette plutôt qu'une demi-conversation.
    public var isLoading: Bool { thread == nil && errorMessage == nil }

    public func load() async {
        do {
            let loaded: ChatThread
            do {
                loaded = try await transport.load()
                isOffline = false
            } catch {
                // Sans réseau, ou sur un voyage que le serveur n'a pas encore
                // reçu : on raconte quand même, dans un fil local. Le transport
                // décide s'il y en a un — une panne du serveur ne se cache pas.
                guard let local = await transport.offlineThread(error) else { throw error }
                loaded = local
                isOffline = true
            }
            thread = loaded
            cursor = loaded.now
            errorMessage = nil
            // Ce que le serveur rend, il l'a reçu : son crédit le compte déjà.
            if !isOffline { forgetCosts(of: loaded.messages) }
            // Le crédit du serveur ; sans lui — un fil local —, **le plus
            // avancé** de ce qu'on sait : le dernier servi ici pour ce voyage,
            // et celui des caches de l'écran du voyage et de l'accueil, que le
            // fil local porte (``DailyCredit/merged(with:)``, 03/10/2026). Le
            // premier passait devant d'office : retenu à 9 h, il effaçait ce
            // que l'accueil avait relu à 14 h après le vocal d'un co-voyageur.
            // Rechargé à la lecture s'il date d'hier (``dailyCredit``).
            setServerCredit(
                isOffline
                    ? Self.rememberedCredits[loaded.context.tripId]?.merged(with: loaded.dailyCredit)
                        ?? loaded.dailyCredit
                    : loaded.dailyCredit
            )

            // Le serveur dit si un tour est encore en vol — on l'a quitté au
            // milieu d'une réponse, ou un co-voyageur vient de parler.
            turn = loaded.turn.isReplying ? .thinking : .idle
            if needsPolling { startPolling() }

            // Relu à chaque ouverture : l'accès peut avoir été retiré depuis
            // les Réglages pendant que l'app était en arrière-plan.
            microphoneIsDenied = RecordingPermission.current == .denied

            // Le vocal de l'accueil, s'il y en a un, se pose maintenant — il
            // fallait un fil pour l'y poser. Une fois, et une seule.
            if let handoff = pendingHandoff {
                pendingHandoff = nil
                receive(handoff)
            }

            // Ce qui attend le réseau sur le disque pour ce fil se pose en
            // bulles « en cours d'envoi » : on a quitté l'écran sur un texte
            // dit dans le métro, il est encore là quand on revient.
            for turn in await transport.waiting() where !messages.contains(where: { $0.id == turn.id }) {
                keepLocalFiles(of: turn)
                append(optimisticMessage(for: turn))
                // Le serveur ne l'a pas encore compté : il le comptera en le
                // recevant, et la barre ne doit pas promettre ce qu'il prendra.
                // Sauf ce qui est retenu — demain, ou l'illimité : ce n'est pas
                // le crédit d'aujourd'hui. Une attente échue, elle, ne retient
                // plus : le tour partira aujourd'hui, il compte aujourd'hui.
                if turn.isOnHold { unreceivedCosts[turn.id] = nil } else { expectCost(of: turn) }
            }

            // Et si la file a parlé pendant qu'on chargeait, on l'écoute
            // maintenant — puis on l'écoute tout court. Un mot déjà entendu
            // avant cette lecture : son crédit ne passe pas devant elle.
            if let latestDelivery { markDelivery(latestDelivery.replayed) }
            watchDeliveries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Suit ce que la file fait des tours partis par elle — le vocal de
    /// l'accueil, un message d'ici qui attendait le réseau. Une seule écoute à
    /// la fois ; elle repart avec le prochain chargement quand l'écran revient.
    private func watchDeliveries() {
        guard deliveryWatcher == nil else { return }
        deliveryWatcher = Task { [weak self] in
            guard let transport = self?.transport else { return }
            for await delivery in await transport.deliveries() {
                guard !Task.isCancelled, let self else { return }
                self.markDelivery(delivery)
            }
        }
    }

    /// Tout arrêter en quittant l'écran : la lecture, la voix de synthèse, le
    /// tour en vol, le sondage, l'écoute de la file et la collecte de niveaux.
    /// Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
    public func teardown() {
        exchange?.cancel()
        exchange = nil
        poller?.cancel()
        poller = nil
        deliveryWatcher?.cancel()
        deliveryWatcher = nil
        levelSampler?.cancel()
        player.stop()
        reader.stop()
        recorder.cancel()
    }

    // MARK: - Ce que la vue lit

    public var messages: [ChatMessage] { thread?.messages ?? [] }

    public var suggestions: [ChatSuggestion] { thread?.suggestions ?? [] }

    public var isThinking: Bool { turn == .thinking }

    /// Le composeur reste utilisable en cas d'échec : on ne piège personne
    /// derrière un message qui ne passe pas.
    public var isComposerEnabled: Bool {
        switch turn {
        case .idle, .failed: true
        case .sending, .thinking: false
        }
    }

    /// Les suggestions ne s'affichent qu'au repos. Un rail encore tapable
    /// pendant que MEMO réfléchit invite au double envoi.
    ///
    /// Crédit épuisé, « Raconter à l'oral » se tait (03/10/2026) : elle
    /// n'armerait qu'un micro qui ne s'ouvre pas.
    public var visibleSuggestions: [ChatSuggestion] {
        guard turn == .idle else { return [] }
        guard isCreditExhausted else { return suggestions }
        return suggestions.filter { $0.intent != .sendThenSpeak }
    }

    /// La bande de suggestions **garde sa place** pendant le tour : ses puces
    /// s'effacent, sa hauteur reste. Sans ça, la barre du bas raccourcissait au
    /// moment même où le message partait, et le fil, épinglé en bas, se tassait
    /// d'autant sous le message qu'on venait de poser — puis remontait quand
    /// MEMO répondait (Hugo, 30/09/2026, T207).
    public var reservesSuggestionRail: Bool {
        turn != .idle && railWasShowing
    }

    /// La bande montrait des puces quand le tour est parti. Retenu à part :
    /// l'envoi vide les suggestions du fil dès le départ — celles du tour
    /// d'avant ne veulent plus rien dire —, et la bande n'aurait plus de
    /// raison de garder sa place.
    private var railWasShowing = false

    public var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isComposerEnabled && !draftExceedsCredit
    }

    // MARK: - Le crédit du jour, à l'écran

    /// Le crédit est épuisé pour aujourd'hui : le micro et le clavier
    /// pâlissent — **sans se désactiver** (règle du design system) : les
    /// toucher dit pourquoi. Jamais pour un abonné.
    public var isCreditExhausted: Bool { credit?.isExhausted == true }

    /// Ce que le brouillon coûterait au crédit : ses caractères, ou — pour
    /// une fiche corrigée « à la main » — ce que la correction ajoute.
    private var draftCost: Int {
        guard let credit else { return 0 }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original = editingOriginalText else { return credit.cost(ofText: text) }
        let growth = max(0, text.unicodeScalars.count - original.unicodeScalars.count)
        return growth * credit.textMsPerCharacter
    }

    /// Le brouillon dépasse ce qu'il reste aujourd'hui : l'envoi pâlit, et une
    /// boîte d'information dit combien de caractères il reste. Le serveur le
    /// refuserait en entier — l'app l'en empêche avant (Hugo, 03/10/2026).
    public var draftExceedsCredit: Bool {
        guard let credit, !credit.isUnlimited else { return false }
        return draftCost > credit.remainingMs
    }

    /// La boîte d'information au-dessus du champ, quand on écrit : le
    /// brouillon est trop long (``DailyCreditCopy/textTooLong(charactersLeft:)``),
    /// ou — plus discret — il reste moins d'une minute de crédit, et on dit
    /// combien de caractères cela fait. `nil` le reste du temps, et toujours
    /// pour un abonné.
    public var creditTextNotice: ChatCreditTextNotice? {
        guard composer == .writing, let credit, !credit.isUnlimited, !credit.isExhausted else { return nil }
        if draftExceedsCredit {
            return .tooLong(DailyCreditCopy.textTooLong(charactersLeft: credit.charactersLeft))
        }
        if credit.remainingMs < Self.characterReminderBelowMs {
            return .reminder(ChatCopy.Credit.charactersLeft(credit.charactersLeft))
        }
        return nil
    }

    /// Sous une minute de crédit, le champ rappelle ce qu'il reste.
    private static let characterReminderBelowMs = 60_000

    /// Le bandeau rouge doux au-dessus de la barre — ``DailyCreditBanner`` :
    /// pendant qu'on parle, le compte à rebours à partir de 30 secondes, qui
    /// pulse sous 5 ; à l'arrêt, « Crédit du jour épuisé » quand on a touché
    /// le micro ou le clavier pâlis, ou qu'on écrit. Rien pour un abonné.
    public var creditBanner: DailyCreditBanner? {
        if let previewCreditBanner { return previewCreditBanner }
        guard let credit, !credit.isUnlimited else { return nil }
        if recorder.isRecording {
            return DailyCreditBanner.whileRecording(credit: credit, elapsedMs: recorder.elapsedMilliseconds)
        }
        guard credit.isExhausted, showsExhaustedNotice || composer == .writing else { return nil }
        return .exhausted
    }

    /// Le micro ou le clavier pâlis ont été touchés : le bandeau « épuisé »
    /// paraît, avec un retour haptique — on a voulu faire quelque chose, et
    /// il se passe quelque chose.
    ///
    /// VoiceOver l'**annonce à chaque toucher** : le bandeau s'insère ailleurs
    /// dans la pile, et sans annonce le micro resterait muet. Le bandeau
    /// s'efface seul après quelques secondes — sauf sous VoiceOver, où il
    /// faut le temps d'aller le toucher : il attend alors le geste suivant.
    public func showExhaustedNotice() {
        if !showsExhaustedNotice {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        showsExhaustedNotice = true
        UIAccessibility.post(notification: .announcement, argument: ChatCopy.Credit.exhaustedAnnouncement)

        exhaustedNoticeTimer?.cancel()
        exhaustedNoticeTimer = nil
        guard !UIAccessibility.isVoiceOverRunning else { return }
        exhaustedNoticeTimer = Task { [weak self, linger = exhaustedNoticeLinger] in
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, let self else { return }
            self.showsExhaustedNotice = false
            self.exhaustedNoticeTimer = nil
        }
    }

    /// Le geste suivant emporte le bandeau « épuisé ».
    private func hideExhaustedNotice() {
        exhaustedNoticeTimer?.cancel()
        exhaustedNoticeTimer = nil
        showsExhaustedNotice = false
    }

    /// Le micro de la barre au repos : il arme l'enregistrement, ou — crédit
    /// épuisé — dit pourquoi il ne le fait pas.
    public func tapMicrophone() {
        guard !isCreditExhausted else {
            showExhaustedNotice()
            return
        }
        composer = .speaking
        startRecording()
    }

    /// Le clavier de la barre au repos : il ouvre le champ, ou — crédit
    /// épuisé — dit pourquoi écrire ne mènerait nulle part.
    ///
    /// - Returns: le champ s'est ouvert, et l'écran peut lui donner le clavier.
    @discardableResult
    public func tapKeyboard() -> Bool {
        guard !isCreditExhausted else {
            showExhaustedNotice()
            return false
        }
        composer = .writing
        return true
    }

    /// Un abonnement vient d'être pris : on relit le crédit du serveur —
    /// la session a déjà basculé l'écran en illimité, le serveur le confirme.
    public func refreshAfterSubscribing() {
        hideExhaustedNotice()
        refreshOnce()
    }

    /// **Le seul chemin du crédit servi** (03/10/2026) : le fil, une mise à
    /// jour, un reçu, un refus. Retenu pour ce voyage, le temps que l'app
    /// vive ; l'écran, lui, le lit décompté de ce qui n'est pas encore arrivé
    /// (``dailyCredit``).
    private func setServerCredit(_ served: DailyCredit?) {
        servedCredit = served
        if let served, let tripId = thread?.context.tripId {
            Self.rememberedCredits[tripId] = served
        }
        // Le serveur dit « illimité » et la session ne le tenait pas de lui —
        // un achat restauré, un abonnement pris sur un autre appareil, ou un
        // achat que le serveur vient seulement d'apprendre : elle l'apprend,
        // et ce qui attendait dans la file repart (``RootView``).
        if served?.isUnlimited == true, let subscription, subscription.known != true {
            subscription.learn(isUnlimited: true, hasSubscribedBefore: true)
        }
        if dailyCredit?.isExhausted != true { hideExhaustedNotice() }
    }

    /// Un tour part, ou se rouvre depuis la file : son coût attend le reçu.
    private func expectCost(of turn: OutgoingTurn) {
        unreceivedCosts[turn.id] = turn.creditCost(in: servedCredit ?? DailyCredit())
    }

    /// Le serveur a ces bulles : leur coût est dans son crédit, plus dans le
    /// nôtre.
    private func forgetCosts(of messages: [ChatMessage]) {
        for message in messages { unreceivedCosts[message.id] = nil }
    }

    /// Le crédit d'un mot **rejoué** par la file (03/10/2026) : le reçu ou le
    /// refus du dernier tour parti de cet appareil, qu'elle redonne à chaque
    /// fil qui s'ouvre. Il ne remplace pas ce que le fil vient de lire —
    /// rejoué à 15 h, le reçu de 10 h rendait 4:00 à qui n'avait plus que
    /// 0:30, et un vocal de 2:00 partait sans avertissement vers un refus.
    ///
    /// Un reçu plus ancien que la dernière lecture (`servedAt` avant
    /// `lastRead`, deux heures du serveur) ne dit rien de neuf : ignoré.
    /// Sinon — un refus, qui n'a pas d'heure ; un fil local, qui n'a pas lu le
    /// serveur —, il se fond dans le crédit tenu (``DailyCredit/merged(with:)``)
    /// : le jour le plus tardif, le plus consommé. Un refus d'aujourd'hui dit
    /// toujours « épuisé », un reçu d'hier ne dit plus rien.
    private func takeReplayedCredit(_ replayed: DailyCredit?, servedAt: Date? = nil, before lastRead: Date? = nil) {
        guard let replayed else { return }
        if let servedAt, let lastRead, servedAt < lastRead { return }
        setServerCredit(servedCredit.map { $0.merged(with: replayed) } ?? replayed)
    }

    /// Le serveur a dit « plus rien aujourd'hui » : son solde s'il l'a rendu,
    /// sinon le dernier qu'il a servi, vidé.
    private func exhaustCredit(with served: DailyCredit?) {
        if let served {
            setServerCredit(served)
        } else if var known = servedCredit?.refreshed(now: .now) {
            known.usedMs = known.limitMs
            setServerCredit(known)
        }
    }

    // MARK: - Envoyer

    public func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trop long pour ce qu'il reste aujourd'hui : le serveur le refuserait
        // en entier. Le brouillon reste, la boîte d'information dit pourquoi.
        guard !text.isEmpty, !draftExceedsCredit else { return }
        let cost = draftCost
        let original = editingOriginalText
        draft = ""
        isEditingTranscript = false
        editingOriginalText = nil

        // « À la main » : la correction va au souvenir, pas dans le fil.
        if let entryId = editingEntryId {
            editingEntryId = nil
            submitTranscriptEdit(entryId: entryId, text: text, original: original, growthCost: cost)
            return
        }

        send(.text(text))
    }

    /// Referme l'outil ouvert et ramène la barre à ses trois boutons.
    ///
    /// C'est la croix qui remplace le burger. Elle **jette** un enregistrement
    /// en cours : c'est le seul geste de la barre qui puisse perdre quelque
    /// chose, et c'est aussi ce qu'on attend d'une croix — sinon elle
    /// laisserait le micro tourner derrière une barre au repos.
    public func collapseComposer() {
        if recorder.isRecording {
            cancelRecording()
        }
        draft = ""
        isEditingTranscript = false
        editingEntryId = nil
        editingOriginalText = nil
        hideExhaustedNotice()
        composer = .tools
    }

    /// iOS ne présente la demande d'accès **qu'une fois** : après un refus, le
    /// seul recours est l'app Réglages. Le bouton micro barré y mène.
    public func openMicrophoneSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Ce qu'une puce de suggestion déclenche.
    ///
    /// Elle **envoie son libellé** comme un message — la maquette la montre bien
    /// posée en bulle bleue dans le fil — et ouvre en plus l'outil qui va avec.
    /// Le serveur reçoit aussi son identifiant : c'est lui qui dit qu'une puce
    /// est une commande, sans modèle et sans souvenir. Seul l'import de photos
    /// n'envoie rien : on ne dit pas « j'importe des photos », on les importe.
    public func choose(
        _ suggestion: ChatSuggestion,
        addPhotos: () -> Void,
        openPreview: () -> Void = {}
    ) {
        // Une puce est le geste suivant : le bandeau « épuisé » s'en va.
        hideExhaustedNotice()
        switch suggestion.intent {
        case .importPhotos:
            addPhotos()
        case .openPreview:
            openPreview()
        case .send, .unknown:
            composer = .tools
            // « Ça me convient » vise la dernière fiche du fil : c'est elle
            // que le serveur valide, dans la même requête.
            let entryId = suggestion.id == "accept" ? latestTranscriptCard?.entryId : nil
            send(.text(suggestion.label, suggestionId: suggestion.id, entryId: entryId))
        case .sendThenWrite:
            composer = .writing
            send(.text(suggestion.label, suggestionId: suggestion.id))
        case .sendThenEditTranscript:
            // Le texte de la fiche est posé dans le champ **avant** d'envoyer
            // la puce : la bulle bleue part, MEMO répond « je te laisse la
            // main », et le voyageur a déjà le texte sous les doigts. S'il n'y
            // a aucune fiche remplie — la puce vient du serveur sous un tour
            // qui n'en a pas —, le champ s'ouvre simplement vide.
            if let card = latestTranscriptCard, let text = card.text, !text.isEmpty {
                draft = text
                isEditingTranscript = true
                editingEntryId = card.entryId
                editingOriginalText = text
            }
            composer = .writing
            send(.text(suggestion.label, suggestionId: suggestion.id))
        case .sendThenSpeak:
            // Crédit épuisé, elle est cachée ; et si elle part quand même — une
            // puce en vol au moment où le crédit tombe —, elle n'arme pas un
            // micro qui ne s'ouvrirait pas.
            composer = isCreditExhausted ? .tools : .speaking
            send(.text(suggestion.label, suggestionId: suggestion.id))
        }
    }

    /// Pose la bulle du voyageur et lance le tour.
    ///
    /// - Parameter id: l'identifiant de la bulle, quand il vient d'ailleurs —
    ///   le vocal de l'accueil porte le sien. Sinon un UUID, qui sera aussi
    ///   celui du message côté serveur.
    private func send(_ body: OutgoingTurn.Body, id: String = UUID().uuidString.lowercased()) {
        guard thread != nil else { return }

        let outgoing = OutgoingTurn(id: id, stepId: activeStepId, body: body)
        append(optimisticMessage(for: outgoing))
        start(outgoing)
    }

    /// La bulle bleue telle qu'elle se dessine avant le reçu du serveur. Le
    /// serveur la remplacera par la sienne, sous le même identifiant — sans
    /// perdre le fichier local d'un vocal ou d'une photo.
    private func optimisticMessage(for outgoing: OutgoingTurn) -> ChatMessage {
        let body: ChatMessageBody
        switch outgoing.body {
        case .text(let text, _, _):
            body = .text(text)
        case .voice(let audio):
            body = .voice(
                VoiceNote(
                    id: outgoing.id,
                    duration: audio.durationSeconds,
                    levels: audio.levels,
                    localUrl: localVoiceUrls[outgoing.id]
                )
            )
        case .photos(let photos, _):
            body = .photos(
                photos.indices.map { index in
                    let id = "\(outgoing.id)-\(index)"
                    return PhotoAttachment(id: id, localUrl: localPhotoUrls[id])
                }
            )
        }
        return ChatMessage(
            id: outgoing.id,
            author: .traveller,
            body: body,
            sentAt: .now,
            stepId: outgoing.stepId,
            delivery: Self.delivery(of: outgoing)
        )
    }

    /// Ce qui attend le crédit de demain, ou l'illimité, le dit dès
    /// l'ouverture du fil. Une attente **échue** — refusé hier soir, rouvert
    /// ce matin — ne dit plus « Partira demain » : le tour partira à la
    /// reconnexion, il est « en cours d'envoi » (03/10/2026).
    private static func delivery(of outgoing: OutgoingTurn) -> ChatDelivery {
        if outgoing.waitingForUnlimited { return .waitingForUnlimited }
        if outgoing.isWaitingForCredit(), let until = outgoing.waitingForCreditUntil {
            return .waitingForCredit(until: until)
        }
        return .sending
    }

    /// Les fichiers écrits dans les caches pour ce qu'on vient d'envoyer, par
    /// identifiant — ce que le serveur ne rend jamais et qu'on ne veut pas
    /// perdre en fusionnant sa réponse.
    private var localVoiceUrls: [String: URL] = [:]
    private var localPhotoUrls: [String: URL] = [:]

    /// « Réessayer » sous la bulle : le tour repart **tel quel**, sous le même
    /// identifiant. Celui dont l'envoi vient d'échouer ici ; sinon celui que
    /// la file a vu refuser — rebâti depuis la bulle et ses fichiers locaux,
    /// puisque la file l'a déjà oublié.
    public func retry() {
        guard let turn = pending ?? refusedTurn() else { return }
        mark(turn.id, as: .sending)
        start(turn)
    }

    private func refusedTurn() -> OutgoingTurn? {
        guard let message = messages.last(where: { $0.author.isTraveller && $0.delivery.hasFailed }) else { return nil }
        return outgoingTurn(from: message)
    }

    /// Le tour qu'une bulle du voyageur représente, avec ses octets relus des
    /// caches. `nil` quand ils n'y sont plus : il n'y a alors rien à renvoyer.
    private func outgoingTurn(from message: ChatMessage) -> OutgoingTurn? {
        switch message.body {
        case .text(let text):
            return OutgoingTurn(id: message.id, stepId: message.stepId, body: .text(text))
        case .voice(let note):
            guard let url = note.localUrl, let data = try? Data(contentsOf: url) else { return nil }
            return OutgoingTurn(
                id: message.id,
                stepId: message.stepId,
                body: .voice(
                    RecordedTurnAudio(
                        data: data,
                        filename: "\(message.id).m4a",
                        mimeType: "audio/mp4",
                        capturedAt: message.sentAt,
                        durationSeconds: note.duration,
                        levels: note.levels,
                        placeLabel: thread?.context.placeName
                    )
                )
            )
        case .photos(let attachments):
            let photos = attachments.compactMap { attachment -> ChatPhotoUpload? in
                guard let url = attachment.localUrl, let data = try? Data(contentsOf: url) else { return nil }
                return ChatPhotoUpload(data: data, filename: "\(attachment.id).jpg", mimeType: "image/jpeg")
            }
            guard !photos.isEmpty, photos.count == attachments.count else { return nil }
            return OutgoingTurn(id: message.id, stepId: message.stepId, body: .photos(photos, capturedAt: message.sentAt))
        case .transcript:
            return nil
        }
    }

    // MARK: - Le tour de parole

    private func start(_ outgoing: OutgoingTurn) {
        pending = outgoing
        // Décompté **ici**, sans attendre le reçu : hors ligne, il n'y en aura
        // pas avant longtemps, et la barre doit savoir ce qui reste pour le
        // prochain vocal. Le reçu remettra le chiffre du serveur.
        expectCost(of: outgoing)
        exchange?.cancel()
        exchange = Task { await run(outgoing) }
    }

    private func run(_ outgoing: OutgoingTurn) async {
        guard var thread else { return }

        // La bande garde sa place si elle montrait des puces — ou si elle la
        // gardait déjà, pour un renvoi après un échec. Voir
        // ``reservesSuggestionRail``.
        railWasShowing = !thread.suggestions.isEmpty || (railWasShowing && turn != .idle)

        // Les suggestions du tour précédent ne veulent plus rien dire.
        thread.suggestions = []
        self.thread = thread

        turn = .sending(messageId: outgoing.id)

        do {
            let outcome = try await transport.send(outgoing)
            try Task.checkCancellation()
            pending = nil

            switch outcome {
            case .received(let receipt):
                accept(receipt, for: outgoing.id)
                if limitTurnId == outgoing.id { limitTurnId = nil }
            case .queued:
                // Le tour attend le réseau sur le disque. Ce n'est pas un
                // échec : la bulle reste « en cours d'envoi », le composeur se
                // rouvre, et c'est la file qui la terminera — par son
                // identifiant, voir ``markDelivery(_:)``.
                turn = .idle
                // Le vocal que la limite a coupé, parti dans la file : pas de
                // reçu pour apporter la bulle de MEMO, l'app pose la sienne.
                if limitTurnId == outgoing.id {
                    limitTurnId = nil
                    postLocalExhaustedNotice()
                }
            }
        } catch is CancellationError {
            // L'écran s'est refermé, ou un nouveau tour a démarré. Rien à dire.
            turn = .idle
        } catch let error as APIError
            where error.isDailyCreditTooLong
            || (error.isDailyCreditExhausted && RecordingOutbox.neverFitsADay(outgoing, refusal: error.dailyCredit))
        {
            // Plus long qu'une journée de crédit : demain n'y changerait rien.
            // La bulle propose l'illimité, comme la file la ferait attendre.
            pending = nil
            unreceivedCosts[outgoing.id] = nil
            if let served = error.dailyCredit { setServerCredit(served) }
            mark(outgoing.id, as: .waitingForUnlimited)
            turn = .idle
        } catch let error as APIError where error.isDailyCreditExhausted {
            // Un transport sans file — les aperçus — rend le refus tel quel.
            // Ce n'est pas un échec à réessayer : la bulle attend demain,
            // comme la file la ferait attendre.
            pending = nil
            unreceivedCosts[outgoing.id] = nil
            exhaustCredit(with: error.dailyCredit)
            mark(outgoing.id, as: .waitingForCredit(until: RecordingOutbox.creditReturns(error.dailyCredit?.resetsAt)))
            turn = .idle
            if limitTurnId == outgoing.id {
                limitTurnId = nil
                postLocalExhaustedNotice()
            }
            refreshOnce()
        } catch {
            unreceivedCosts[outgoing.id] = nil
            mark(outgoing.id, as: .failed(error.localizedDescription))
            turn = .failed(messageId: outgoing.id, message: error.localizedDescription)
        }
        exchange = nil
    }

    /// Ce que le serveur a écrit en recevant un tour : la bulle du voyageur
    /// avec son rang, l'ouverture de MEMO si elle vient d'être posée, la fiche
    /// d'un vocal. On fusionne ; on ne remplace pas le fil.
    ///
    /// Le curseur ne recule jamais : un reçu arrivé en retard — un tour parti
    /// de la file après une lecture plus récente — ne fait pas relire ce qu'on
    /// a déjà.
    ///
    /// - Parameter isReplay: le reçu vient d'un mot **rejoué** par la file —
    ///   le dernier tour parti de cet appareil, peut-être ce matin. Voir
    ///   ``takeReplayedCredit(_:servedAt:before:)``.
    private func accept(_ receipt: ChatTurnReceipt, for id: String, isReplay: Bool = false) {
        merge(receipt.messages)
        mark(id, as: .sent)
        let lastRead = cursor
        cursor = max(cursor ?? .distantPast, receipt.now)
        // Le crédit **après** ce tour, tel que le serveur l'a compté — il
        // remplace l'estimation faite à l'envoi, et ne garde que celle des
        // tours qu'il n'a pas encore reçus.
        unreceivedCosts[id] = nil
        forgetCosts(of: receipt.messages)
        if isReplay {
            takeReplayedCredit(receipt.dailyCredit, servedAt: receipt.now, before: lastRead)
        } else if let credit = receipt.dailyCredit {
            setServerCredit(credit)
        }

        if receipt.turn.isReplying {
            turn = .thinking
        } else if owns(id) {
            turn = .idle
        }
        if needsPolling { startPolling() }
    }

    /// Le tour en cours est celui de cette bulle. Un reçu venu de la file pour
    /// un tour d'hier ne doit pas rouvrir le composeur pendant qu'un autre part.
    private func owns(_ id: String) -> Bool {
        switch turn {
        case .sending(let messageId), .failed(let messageId, _): messageId == id
        case .idle, .thinking: false
        }
    }

    // MARK: - Le sondage

    /// Tant qu'un tour est en vol, ou qu'une fiche attend sa transcription ou
    /// sa rédaction.
    private var needsPolling: Bool {
        if turn == .thinking { return true }
        return messages.contains { message in
            if case .transcript(let card) = message.body { return card.isSettling || card.text == nil }
            return false
        }
    }

    /// Une tâche, et une seule : relire la suite du fil toutes les deux
    /// secondes, jouer ce qui arrive, s'arrêter dès qu'il n'y a plus rien à
    /// attendre ou après trois minutes sans changement.
    private func startPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            var quietTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollingInterval)
                guard !Task.isCancelled, let self else { return }
                guard self.needsPolling else { break }

                do {
                    let update = try await self.transport.poll(self.cursor ?? .distantPast)
                    try Task.checkCancellation()
                    let changed = await self.apply(update)
                    quietTicks = changed ? 0 : quietTicks + 1
                } catch is CancellationError {
                    return
                } catch {
                    // Un sondage qui rate n'est pas une erreur d'écran : on
                    // réessaie au tour suivant, et on renonce comme un fil
                    // silencieux.
                    quietTicks += 1
                }

                if quietTicks >= Self.pollingGivesUpAfter { break }
            }
            guard let self else { return }
            self.poller = nil
            // On renonce sans réponse : le composeur se rouvre, le fil ne
            // ment pas — MEMO n'a simplement pas répondu à temps.
            if self.turn == .thinking { self.turn = .idle }
        }
    }

    /// Fusionne la suite du fil. Les bulles d'un co-voyageur et les fiches
    /// mises à jour entrent tout de suite ; les bulles de MEMO **une par une,
    /// rythmées** par le silence que le serveur a décidé — c'est ce qui les
    /// fait arriver comme une réponse et non comme un chargement.
    ///
    /// - Returns: `true` si quelque chose a changé.
    private func apply(_ update: ChatThreadUpdate) async -> Bool {
        cursor = update.now

        var arrivals: [ChatMessage] = []
        var changed = false

        for message in update.messages.sorted(by: Self.byRank) {
            if messages.contains(where: { $0.id == message.id }) {
                replace(message)
                changed = true
            } else if message.author.isTraveller {
                insert(message)
                changed = true
            } else {
                arrivals.append(message)
            }
        }

        for bubble in arrivals {
            turn = .thinking
            let pause = Duration.milliseconds(bubble.pauseMilliseconds ?? 700)
            try? await Task.sleep(for: max(pause, Self.minimumThinking))
            if Task.isCancelled { return changed }
            insert(bubble)
            changed = true
        }

        if let preview = update.preview { thread?.preview = preview }
        // Ce qu'un co-voyageur vient de raconter a pu entamer le pot commun.
        // Le chiffre servi ne compte pas ce qui est encore en route d'ici —
        // un vocal qui monte en 3G, un tour en file : ``dailyCredit`` le
        // retire toujours, la barre ne remonte pas d'autant.
        forgetCosts(of: update.messages)
        if let credit = update.dailyCredit { setServerCredit(credit) }
        // Posé **après** les bulles : la pastille se remplit au moment où MEMO
        // dit ce qu'il a compris, pas avant qu'il l'ait dit.
        if let tripContext = update.tripContext, tripContext != thread?.tripContext {
            thread?.tripContext = tripContext
            changed = true
        }

        if update.turn.isReplying {
            turn = .thinking
        } else if turn == .thinking {
            thread?.suggestions = update.suggestions
            turn = .idle
        } else if turn == .idle, !update.suggestions.isEmpty {
            thread?.suggestions = update.suggestions
        }

        return changed
    }

    // MARK: - Le fil

    /// L'ordre du serveur d'abord ; ce qui n'en a pas encore — une bulle
    /// optimiste — reste en bas, où il est.
    private static func byRank(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        (a.seq ?? Int.max) < (b.seq ?? Int.max)
    }

    private func merge(_ received: [ChatMessage]) {
        for message in received.sorted(by: Self.byRank) {
            if messages.contains(where: { $0.id == message.id }) {
                replace(message)
            } else {
                insert(message)
            }
        }
    }

    private func insert(_ message: ChatMessage) {
        guard var thread else { return }
        // La bulle « reviens demain » du serveur remplace celle que l'app
        // avait posée hors ligne : une seule, et la vraie.
        if message.callToAction?.id == ChatCallToAction.dailyCreditSubscribe.id {
            thread.messages.removeAll { $0.id.hasPrefix(Self.localNoticePrefix) && $0.id != message.id }
        }
        thread.messages.append(message)
        thread.messages.sort(by: Self.byRank)
        self.thread = thread
    }

    /// Remplace par identifiant, en gardant ce que l'app seule sait : le
    /// fichier local. L'état d'envoi, lui, est celui du serveur — un message
    /// qu'il rend est un message qu'il a : une bulle restée « en cours
    /// d'envoi » parce qu'on a raté le mot de la file se répare au sondage
    /// suivant.
    private func replace(_ message: ChatMessage) {
        guard var thread, let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return }
        thread.messages[index] = message.keepingLocalFiles(of: thread.messages[index])
        thread.messages.sort(by: Self.byRank)
        self.thread = thread
    }

    // MARK: - « À la main »

    /// La correction part au souvenir ; la fiche se redessine avec elle ; puis
    /// une commande silencieuse fait accuser réception à MEMO — sans modèle,
    /// sans souvenir de plus.
    ///
    /// **Un refus garde le brouillon** (03/10/2026) : le champ a été vidé à
    /// l'envoi, et un `429` — un co-voyageur a raconté entre-temps — ou une
    /// panne le remettent sous les doigts, tel qu'il était, avec la fiche
    /// qu'il corrige. Jamais une correction tapée ne se perd parce que le
    /// serveur a dit non.
    private func submitTranscriptEdit(entryId: String, text: String, original: String?, growthCost: Int = 0) {
        exchange?.cancel()
        turn = .sending(messageId: entryId)
        exchange = Task {
            do {
                let entry = try await transport.editTranscript(entryId, text)
                try Task.checkCancellation()
                refreshCard(for: entry)
                // Ce que la correction ajoute se paie, comme un texte — et le
                // serveur l'a déjà compté : c'est son chiffre, pas une attente.
                if growthCost > 0, let served = servedCredit {
                    setServerCredit(served.refreshed(now: .now).consuming(growthCost))
                }
                turn = .idle
                send(.text(ChatCopy.editedByHand, suggestionId: "transcript_edited", entryId: entryId))
            } catch is CancellationError {
                turn = .idle
            } catch {
                if let apiError = error as? APIError, apiError.isDailyCreditExhausted {
                    exhaustCredit(with: apiError.dailyCredit)
                }
                // Le brouillon revient — sauf si l'on s'est déjà remis à écrire.
                if draft.isEmpty {
                    draft = text
                    editingEntryId = entryId
                    editingOriginalText = original
                    isEditingTranscript = true
                    composer = .writing
                }
                errorMessage = error.localizedDescription
                turn = .idle
            }
        }
    }

    /// La fiche d'un souvenir, une fois le serveur repassé dessus.
    private func refreshCard(for entry: Entry) {
        guard var thread else { return }
        for index in thread.messages.indices {
            guard case .transcript(let card) = thread.messages[index].body, card.entryId == entry.id else { continue }
            thread.messages[index].body = .transcript(
                TranscriptCard(
                    title: card.title,
                    capturedAt: entry.capturedAt,
                    placeLabel: entry.placeLabel ?? card.placeLabel,
                    duration: card.duration,
                    text: entry.displayText ?? card.text,
                    isSimulated: false,
                    entryId: entry.id,
                    footnote: card.footnote,
                    phase: .ready,
                    isValidated: entry.validatedAt != nil || card.isValidated
                )
            )
        }
        self.thread = thread
    }

    // MARK: - Le vocal

    /// Le vocal enregistré depuis l'accueil, en attendant que le fil soit là
    /// pour le recevoir. Voir ``RecordingHandoff``.
    private var pendingHandoff: RecordingHandoff?

    /// Annonce un vocal venu de l'accueil. Il sera posé dans le fil au
    /// chargement, exactement comme s'il avait été dit ici : même bulle, même
    /// forme d'onde.
    public func expect(_ handoff: RecordingHandoff) {
        pendingHandoff = handoff
    }

    /// Pose un vocal déjà enregistré, **sans l'envoyer** : il est parti avant
    /// que cet écran n'existe, par la file de l'accueil, et c'est elle qui
    /// dira où il en est — par ``markDelivery(_:)``. Le fichier est gardé pour
    /// la réécoute.
    ///
    /// S'il est déjà dans le fil — le serveur l'a reçu avant qu'on ait fini de
    /// charger —, la bulle du serveur reste, et ne gagne que le fichier local.
    private func receive(_ handoff: RecordingHandoff) {
        let url = try? VoiceNoteFile.save(handoff.audio, id: handoff.id)
        localVoiceUrls[handoff.id] = url

        if messages.contains(where: { $0.id == handoff.id }) {
            if let url { rememberLocalUrl(url, forVoice: handoff.id) }
            return
        }

        // Le serveur ne l'a pas encore compté : la barre le décompte d'avance.
        // Coupé par la limite, il a vidé le crédit — et sans réseau, aucun
        // reçu n'apportera la bulle de MEMO : l'app pose la sienne.
        let spent = Int((handoff.audio.duration * 1000).rounded())
        unreceivedCosts[handoff.id] =
            handoff.stoppedAtLimit ? max(spent, servedCredit?.limitMs ?? spent) : spent
        if handoff.stoppedAtLimit {
            limitTurnId = handoff.id
            if isOffline { postLocalExhaustedNoticeAfterHandoff = true }
        }

        append(
            ChatMessage(
                id: handoff.id,
                author: .traveller,
                body: .voice(
                    VoiceNote(
                        id: handoff.id,
                        duration: handoff.audio.duration,
                        levels: handoff.levels,
                        localUrl: url
                    )
                ),
                sentAt: .now,
                stepId: activeStepId,
                delivery: .sending
            )
        )
        // Après la bulle du vocal, et pas avant : MEMO répond à ce qu'on a dit.
        if postLocalExhaustedNoticeAfterHandoff {
            postLocalExhaustedNoticeAfterHandoff = false
            limitTurnId = nil
            postLocalExhaustedNotice()
        }
    }

    /// Le vocal de l'accueil a été coupé par la limite, sans réseau : la bulle
    /// « reviens demain » se pose juste après lui.
    private var postLocalExhaustedNoticeAfterHandoff = false

    /// Ce que la file dit d'un tour — le vocal de l'accueil, ou un message
    /// d'ici qui attendait le réseau. La bulle suit **la file**, pas l'écran :
    /// hors ligne elle reste sur « envoi en cours », et c'est la reconnexion
    /// qui la termine, par son identifiant.
    ///
    /// Arrivé, le tour a un reçu : les bulles que le serveur a écrites — la
    /// sienne avec son rang, sa fiche — entrent dans le fil, et le sondage
    /// prend la suite si MEMO répond. Un tour d'un autre voyage ne touche à
    /// rien ici.
    public func markDelivery(_ delivery: ChatTurnDelivery) {
        latestDelivery = delivery
        guard let thread, delivery.tripId == thread.context.tripId else { return }

        switch delivery.state {
        case .sending:
            mark(delivery.id, as: .sending)
        case .failed(let message):
            unreceivedCosts[delivery.id] = nil
            mark(delivery.id, as: .failed(message))
        case .waitingForUnlimited:
            // Plus long qu'une journée : la bulle propose l'illimité. Le crédit
            // d'aujourd'hui n'est pas pour autant épuisé — le solde rendu le dit.
            unreceivedCosts[delivery.id] = nil
            mark(delivery.id, as: .waitingForUnlimited)
            if delivery.isReplay {
                takeReplayedCredit(delivery.credit)
            } else if let served = delivery.credit {
                setServerCredit(served)
            }
        case .waitingForCredit(let until):
            // Refusé faute de crédit : la bulle attend demain, la barre passe à
            // « épuisé », et la bulle « reviens demain » que le serveur vient
            // de poser se lit tout de suite. Rejoué à l'ouverture d'un fil, le
            // refus ne fait que se fondre dans ce que le fil vient de lire.
            unreceivedCosts[delivery.id] = nil
            mark(delivery.id, as: .waitingForCredit(until: until))
            if delivery.isReplay {
                takeReplayedCredit(delivery.credit)
            } else {
                exhaustCredit(with: delivery.credit)
            }
            if limitTurnId == delivery.id {
                limitTurnId = nil
                if isOffline { postLocalExhaustedNotice() }
            }
            if !delivery.isReplay { refreshOnce() }
        case .sent:
            if let receipt = delivery.receipt {
                accept(receipt, for: delivery.id, isReplay: delivery.isReplay)
            } else {
                unreceivedCosts[delivery.id] = nil
                mark(delivery.id, as: .sent)
            }
            // Un message est arrivé : le serveur répond, et il connaît le
            // voyage. Le fil local cède la place au vrai. Pas sur un mot
            // rejoué : il date d'avant la lecture qui vient d'échouer.
            if isOffline, !delivery.isReplay { reloadFromServer() }
        }
    }

    /// Relit le fil du serveur après un fil local. Une fois à la fois : trois
    /// tours qui arrivent ensemble au retour du réseau ne font qu'une lecture.
    private func reloadFromServer() {
        guard !isReloading else { return }
        isReloading = true
        Task { [weak self] in
            guard let self else { return }
            await self.load()
            self.isReloading = false
        }
    }

    /// Écrit dans les caches les fichiers d'un tour relu du disque de la
    /// file, pour que sa bulle se réécoute et se regarde comme celle d'un tour
    /// dit ici.
    private func keepLocalFiles(of turn: OutgoingTurn) {
        switch turn.body {
        case .text:
            break
        case .voice(let audio):
            guard localVoiceUrls[turn.id] == nil else { return }
            let recorded = RecordedAudio(
                data: audio.data,
                filename: audio.filename,
                mimeType: audio.mimeType,
                duration: audio.durationSeconds,
                recordedAt: audio.capturedAt
            )
            localVoiceUrls[turn.id] = try? VoiceNoteFile.save(recorded, id: turn.id)
        case .photos(let photos, _):
            for (index, photo) in photos.enumerated() {
                let id = "\(turn.id)-\(index)"
                guard localPhotoUrls[id] == nil else { continue }
                localPhotoUrls[id] = try? ChatPhotoFile.save(photo.data, id: id)
            }
        }
    }

    public func startRecording() {
        // Plus de crédit aujourd'hui : ni micro, ni niveaux, ni permission
        // demandée pour rien — le bandeau dit pourquoi.
        guard !isCreditExhausted else {
            showExhaustedNotice()
            return
        }
        guard !recorder.isRecording else { return }

        Task {
            do {
                try await recorder.start()
                microphoneIsDenied = false
                lastRecordingPhase = .calm
                startSamplingLevels()
            } catch RecordingError.permissionDenied {
                microphoneIsDenied = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func finishRecording() {
        finishRecording(atLimit: false)
    }

    /// - Parameter atLimit: c'est la limite du jour qui coupe, pas le
    ///   voyageur — voir ``stopAtLimit()``.
    private func finishRecording(atLimit: Bool) {
        levelSampler?.cancel()
        let levels = capturedLevels

        do {
            guard let audio = try recorder.stop() else { return }
            let id = UUID().uuidString.lowercased()
            if atLimit { limitTurnId = id }

            // `AudioRecorder.stop()` efface son fichier temporaire et ne rend
            // que des octets : sans cette écriture, le vocal ne serait plus
            // réécoutable une seconde après l'avoir dit.
            if let url = try? VoiceNoteFile.save(audio, id: id) {
                localVoiceUrls[id] = url
            }

            composer = .tools
            send(
                .voice(
                    RecordedTurnAudio(
                        data: audio.data,
                        filename: audio.filename,
                        mimeType: audio.mimeType,
                        capturedAt: audio.recordedAt,
                        durationSeconds: audio.duration,
                        levels: levels,
                        placeLabel: thread?.context.placeName
                    )
                ),
                id: id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pauseRecording() {
        recorder.pause()
        levelSampler?.cancel()
    }

    public func resumeRecording() {
        recorder.resume()
        startSamplingLevels(resetting: false)
    }

    public func cancelRecording() {
        levelSampler?.cancel()
        capturedLevels = []
        recorder.cancel()
        composer = .tools
    }

    /// Onze relevés par seconde : assez pour dessiner le grain d'une voix,
    /// assez peu pour qu'un vocal de trois minutes reste un tableau de deux
    /// mille valeurs.
    ///
    /// La même boucle **guette le crédit du jour** : c'est elle qui fait vibrer
    /// le bandeau à son apparition et qui coupe net à zéro — voir
    /// ``watchCredit()``. 90 ms de grain : le serveur tolère trois secondes
    /// au-delà du reste (`VOICE_TOLERANCE_MS`), la coupure tombe bien avant.
    private func startSamplingLevels(resetting: Bool = true) {
        if resetting { capturedLevels = [] }
        levelSampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard let self, self.recorder.isRecording, !self.recorder.isPaused else { return }
                self.capturedLevels.append(self.recorder.level)
                self.watchCredit()
            }
        }
    }

    /// Ce que le crédit du jour fait à l'enregistrement en cours, à chaque
    /// relevé : un léger retour haptique et une annonce VoiceOver quand le
    /// bandeau paraît (30 s), un second quand il se met à pulser (5 s), et
    /// l'**arrêt net** à zéro. Rien pour un abonné, rien sans crédit connu.
    private func watchCredit() {
        guard let credit, !credit.isUnlimited, recorder.isCapturing else { return }
        let remaining = credit.remainingMs(whileRecording: recorder.elapsedMilliseconds)
        let phase = credit.phase(remainingMs: remaining)
        guard phase != lastRecordingPhase else { return }
        lastRecordingPhase = phase

        switch phase {
        case .calm:
            break
        case .warning:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: DailyCreditCopy.warning(remainingMs: remaining))
        case .urgent:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .exhausted:
            stopAtLimit()
        }
    }

    /// **L'arrêt net**, à zéro (Hugo, 03/10/2026) : ce qui a été dit **part**
    /// — jamais on ne jette la fin d'un récit parce que la minute est passée.
    /// Le serveur répond avec sa bulle « reviens demain » dans le reçu ; hors
    /// ligne, l'app pose la sienne (``postLocalExhaustedNotice()``).
    private func stopAtLimit() {
        guard recorder.isRecording else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(notification: .announcement, argument: ChatCopy.Credit.stoppedAnnouncement)
        finishRecording(atLimit: true)
    }

    // MARK: - Les commandes d'un message

    /// Joue un vocal. Le fichier local d'abord ; sinon le serveur le sert
    /// **avec la session** — une URL nue ne suffirait pas —, et on le garde
    /// dans les caches pour la fois suivante.
    public func togglePlayback(of note: VoiceNote) {
        reader.stop()

        if let url = cachedAudio(of: note) {
            play(note.id, at: url)
            return
        }

        guard note.remoteUrl != nil else {
            errorMessage = MemoResponderError.transcriptionUnavailable.localizedDescription
            return
        }

        Task {
            guard let url = await downloadAudio(of: note) else {
                errorMessage = MemoResponderError.transcriptionUnavailable.localizedDescription
                return
            }
            rememberLocalUrl(url, forVoice: note.id)
            play(note.id, at: url)
        }
    }

    /// Le fichier d'un vocal déjà sur l'appareil : celui de la bulle, celui
    /// qu'on a écrit pendant cette session, ou celui qu'une session d'avant a
    /// laissé dans les caches.
    private func cachedAudio(of note: VoiceNote) -> URL? {
        note.localUrl ?? localVoiceUrls[note.id] ?? VoiceNoteFile.existing(id: note.id)
    }

    /// Descend le vocal du serveur et l'écrit dans les caches. `nil` si le
    /// serveur ne le rend pas.
    private func downloadAudio(of note: VoiceNote) async -> URL? {
        guard let remote = note.remoteUrl else { return nil }
        do {
            let data = try await transport.media(remote)
            let audio = RecordedAudio(
                data: data,
                filename: "\(note.id).m4a",
                mimeType: "audio/mp4",
                duration: note.duration,
                recordedAt: .now
            )
            let url = try VoiceNoteFile.save(audio, id: note.id)
            localVoiceUrls[note.id] = url
            return url
        } catch {
            return nil
        }
    }

    // MARK: - La forme d'onde d'un vocal qui n'en a pas

    /// Les niveaux **relus dans le fichier** des vocaux arrivés sans relevé —
    /// voir ``VoiceLevels``. Gardés ici et non dans le fil : chaque relecture
    /// du serveur rend ces vocaux sans niveaux, et les écraserait.
    private var derivedLevels: [String: [Double]] = [:]
    private var derivingLevels: Set<String> = []

    /// Ce que la bulle dessine : le relevé du serveur, sinon celui qu'on a relu
    /// dans le fichier, sinon rien — la ligne plate, le temps de le relire.
    public func levels(of note: VoiceNote) -> [Double] {
        note.levels.isEmpty ? derivedLevels[note.id] ?? [] : note.levels
    }

    /// Relit la forme d'onde d'un vocal qui n'en a pas (Hugo, 30/09/2026 : les
    /// vocaux des voyages passés n'avaient plus qu'une ligne plate). Une fois
    /// par vocal et par écran ; le fichier descendu sert ensuite à l'écoute.
    public func deriveLevelsIfNeeded(for note: VoiceNote) async {
        guard note.levels.isEmpty,
            derivedLevels[note.id] == nil,
            !derivingLevels.contains(note.id)
        else { return }

        derivingLevels.insert(note.id)
        defer { derivingLevels.remove(note.id) }

        let file: URL?
        if let cached = cachedAudio(of: note) {
            file = cached
        } else {
            file = await downloadAudio(of: note)
        }
        guard let file else { return }

        let levels = await VoiceLevels.read(from: file)
        guard !levels.isEmpty else { return }
        derivedLevels[note.id] = levels
    }

    // MARK: - Les images du fil

    /// Les images du fil — les portraits des vocaux, les photos —, chargées
    /// **par le modèle** et non par un `AsyncImage` dans la bulle.
    ///
    /// Deux raisons, vues dans les journaux de Railway le 30/09/2026.
    /// **Les annulations** : le fil se recompose en s'ouvrant — il relit,
    /// fusionne, anime — et chaque recomposition recréait les `AsyncImage` des
    /// bulles ; leurs requêtes partaient annulées en 5 ms (des `499`) et le rond
    /// restait sur ses initiales pour de bon. **La session** : une photo du
    /// voyage se sert par `/v1/entries/:id/media`, qui la demande, et un
    /// `AsyncImage` n'envoie aucun en-tête — des `401`, et la bulle restait sur
    /// sa trame. Ici, une requête par adresse, qui survit aux recompositions,
    /// par le bon chemin, et un résultat gardé tant que l'écran est ouvert.
    public private(set) var images: [URL: UIImage] = [:]
    private var loadingImages: Set<URL> = []

    /// Charge une image du fil, une fois. Un échec n'est pas retenu : la bulle
    /// garde sa trame ou ses initiales, et redemande en réapparaissant.
    public func loadImage(_ url: URL) {
        guard images[url] == nil, !loadingImages.contains(url) else { return }
        loadingImages.insert(url)

        Task { [weak self] in
            guard let self else { return }
            let data = await self.imageData(at: url)
            let image = await ChatImage.decode(data)
            self.loadingImages.remove(url)
            if let image { self.images[url] = image }
        }
    }

    /// Les octets d'une image, par le chemin qu'elle demande : le disque pour
    /// une photo qui vient d'être choisie ; **le transport, avec la session**,
    /// pour un média du voyage (`…/media`) — comme l'écoute d'un vocal ; une
    /// requête nue pour un avatar (`GET /v1/avatars/:file`), servi sans session
    /// parce qu'il se montre à ceux qui partagent le voyage.
    private func imageData(at url: URL) async -> Data? {
        if url.isFileURL { return try? Data(contentsOf: url) }
        if url.lastPathComponent == "media" { return try? await transport.media(url) }
        return try? await URLSession.shared.data(from: url).0
    }

    private func play(_ id: String, at url: URL) {
        do {
            try player.toggle(id: id, url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rememberLocalUrl(_ url: URL, forVoice id: String) {
        guard var thread else { return }
        for index in thread.messages.indices {
            guard case .voice(var note) = thread.messages[index].body, note.id == id else { continue }
            note.localUrl = url
            thread.messages[index].body = .voice(note)
        }
        self.thread = thread
    }

    public func toggleReading(of message: ChatMessage) {
        guard let text = message.spokenText else { return }
        player.stop()
        reader.toggle(id: message.id, text: text)
    }

    /// Copie le message. Le retour est un `UINotificationFeedbackGenerator` et
    /// non une alerte : on ne pose pas une fenêtre pour dire qu'un texte est
    /// dans le presse-papiers.
    public func copy(_ message: ChatMessage) {
        guard let text = message.spokenText else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // La coche verte prend la place de l'icône pendant une seconde. Une
        // seconde parce que c'est le temps qu'il faut pour la voir sans qu'elle
        // devienne un état : au-delà, on se demande si elle attend un second
        // geste.
        copiedMessageId = message.id
        Task { [id = message.id] in
            try? await Task.sleep(for: .seconds(1))
            guard copiedMessageId == id else { return }
            copiedMessageId = nil
        }
    }

    /// Poste les photos choisies.
    ///
    /// Les images sont écrites dans les caches avant d'entrer dans le fil : une
    /// bulle qui garderait ses octets en mémoire ferait grossir la conversation
    /// à chaque photo, et les perdrait au premier retour d'arrière-plan.
    public func sendPhotos(_ images: [Data]) {
        guard !images.isEmpty else { return }
        hideExhaustedNotice()
        let id = UUID().uuidString.lowercased()

        var uploads: [ChatPhotoUpload] = []
        for (index, data) in images.prefix(ChatMetrics.visiblePhotoCount).enumerated() {
            let photoId = "\(id)-\(index)"
            guard let url = try? ChatPhotoFile.save(data, id: photoId) else { continue }
            localPhotoUrls[photoId] = url
            uploads.append(ChatPhotoUpload(data: data, filename: "\(photoId).jpg", mimeType: "image/jpeg"))
        }

        guard !uploads.isEmpty else {
            errorMessage = ChatCopy.photosUnreadable
            return
        }

        composer = .tools
        send(.photos(uploads, capturedAt: .now), id: id)
    }

    /// « Modifier » : le texte revient dans le champ de saisie, le clavier
    /// s'ouvre. Sur une fiche, c'est « à la main » sans la puce : envoyer
    /// corrige le souvenir. Sur une bulle de texte, c'est un nouveau message.
    public func edit(_ message: ChatMessage) {
        guard let text = message.spokenText else { return }
        hideExhaustedNotice()
        draft = text
        if case .transcript(let card) = message.body {
            isEditingTranscript = true
            editingEntryId = card.entryId
            editingOriginalText = text
        }
        composer = .writing
    }

    // MARK: - Le bouton sous une bulle de MEMO

    /// Le bouton d'une bulle se montre-t-il ? Jamais pour un genre que cette
    /// version ne sait pas ouvrir ; et « s'abonner » pas à qui l'est déjà —
    /// le serveur le taira à la prochaine lecture, l'écran n'attend pas.
    public func showsCallToAction(_ callToAction: ChatCallToAction?) -> Bool {
        guard let callToAction, callToAction.kind.isSupported else { return false }
        if callToAction.kind == .subscribe, credit?.isUnlimited == true || subscription?.isUnlimited == true {
            return false
        }
        return true
    }

    /// Où en est le bouton d'une bulle : rien encore, touché, ignoré.
    public func callToActionState(for messageId: String) -> ChatCallToActionState {
        if let known = callToActionStates[messageId] { return known }
        return callToActionMemory.state(for: messageId)
    }

    /// Le bouton a été touché — l'écran a ouvert ce qu'il ouvre. Il passe au
    /// bleu, « Ignorer » s'en va, et c'est retenu.
    public func followCallToAction(of messageId: String) {
        remember(.followed, for: messageId)
    }

    /// « Ignorer » : le bouton et « Ignorer » s'en vont, la bulle redevient une
    /// bulle — et le reste.
    public func dismissCallToAction(of messageId: String) {
        remember(.dismissed, for: messageId)
    }

    private func remember(_ state: ChatCallToActionState, for messageId: String) {
        callToActionStates[messageId] = state
        callToActionMemory.remember(state, for: messageId)
    }

    // MARK: - Supprimer un tour qui attend l'illimité

    /// « Supprimer », sous une bulle « Trop long pour une journée », une fois
    /// confirmé (03/10/2026) : sans abonnement, rien ne la ferait jamais
    /// partir. Le tour quitte la file — fiche et fichiers — et la bulle le
    /// fil. Jamais une autre bulle : un tour qui part, ou qui attend le
    /// réseau, ne se supprime pas d'ici.
    public func discardWaitingTurn(_ id: String) {
        guard let message = messages.first(where: { $0.id == id }), message.delivery.isWaitingForUnlimited else { return }
        thread?.messages.removeAll { $0.id == id }
        unreceivedCosts[id] = nil
        if pending?.id == id { pending = nil }
        Task { [transport] in _ = await transport.discard(id) }
    }

    // MARK: - La bulle « reviens demain », hors ligne

    /// Le début de l'identifiant d'une bulle « reviens demain » posée par
    /// l'app — jamais par le serveur, qui tire des UUID.
    static let localNoticePrefix = "local-daily-credit-"

    /// Pose la bulle « reviens demain » **sans le serveur** : la limite vient
    /// de couper un vocal parti dans la file, et aucun reçu n'apportera celle
    /// de MEMO. Le même texte et le même bouton que le serveur
    /// (``DailyCreditCopy/exhaustedMessage``, ``ChatCallToAction/dailyCreditSubscribe``)
    /// ; **jamais gardée** — le vrai fil la remplace au retour du réseau, et la
    /// bulle du serveur la chasse dès qu'elle arrive (``insert(_:)``).
    ///
    /// Une par jour : l'identifiant porte le jour du crédit, pour qu'un
    /// « Ignorer » d'hier ne fasse pas disparaître le bouton de demain.
    private func postLocalExhaustedNotice() {
        guard thread != nil, !hasExhaustedNoticeToday else { return }
        let day = credit?.day ?? Self.localDay(.now)
        append(
            ChatMessage(
                id: Self.localNoticePrefix + day,
                author: .memo,
                body: .text(DailyCreditCopy.exhaustedMessage),
                sentAt: .now,
                callToAction: .dailyCreditSubscribe
            )
        )
    }

    /// Le fil porte déjà une bulle « reviens demain » d'aujourd'hui.
    private var hasExhaustedNoticeToday: Bool {
        messages.contains {
            $0.callToAction?.id == ChatCallToAction.dailyCreditSubscribe.id && Calendar.current.isDateInToday($0.sentAt)
        }
    }

    /// `AAAA-MM-JJ`, le jour local — le format du `day` du serveur.
    private static func localDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Une lecture de la suite du fil, hors du sondage : après un refus de
    /// crédit (la bulle de MEMO vient d'être posée), après un achat (le crédit
    /// devient illimité). Rien hors ligne, rien si le sondage tourne déjà.
    private func refreshOnce() {
        guard !isOffline, poller == nil, thread != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let update = try? await self.transport.poll(self.cursor ?? .distantPast) else { return }
            _ = await self.apply(update)
        }
    }

    /// La dernière fiche remplie du fil — celle que le trio « Ça me convient /
    /// à la main / à l'oral » suit. La dernière et non la première : on
    /// corrige ce qu'on vient d'entendre, pas la fiche d'hier.
    private var latestTranscriptCard: TranscriptCard? {
        for message in messages.reversed() {
            if case .transcript(let card) = message.body, let text = card.text, !text.isEmpty {
                return card
            }
        }
        return nil
    }

    // MARK: -

    private func append(_ message: ChatMessage) {
        thread?.messages.append(message)
    }

    private func mark(_ id: String, as delivery: ChatDelivery) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        thread?.messages[index].delivery = delivery
    }
}

// MARK: - Aperçus

extension ChatModel {
    /// Une conversation déjà remplie, pour les aperçus. Dans une extension du
    /// fichier du modèle, parce que `private(set)` ne s'ouvre qu'ici.
    ///
    /// Pas de `#if DEBUG` : un `#Preview` se compile **aussi** en release, donc
    /// ce que l'aperçu appelle doit exister en release. Sinon l'archive casse,
    /// alors que la compilation de debug passait. C'est la règle du paquet —
    /// les jeux d'essai des aperçus (`ChatThread.fixture`, `HomeFeed.emptyFixture`)
    /// se compilent partout ; seuls les panneaux du bac à sable sont en `#if DEBUG`.
    ///
    /// - Parameters:
    ///   - dailyCredit: le crédit du jour ; à défaut, celui du fil.
    ///   - showsExhaustedNotice: le bandeau « épuisé » est déjà demandé.
    ///   - creditBanner: le bandeau à montrer comme si le micro tournait —
    ///     un aperçu n'enregistre pas.
    static func preview(
        thread: ChatThread,
        turn: ChatTurnState = .idle,
        composer: ChatComposerMode = .tools,
        draft: String = "",
        microphoneIsDenied: Bool = false,
        focusStepId: String? = nil,
        dailyCredit: DailyCredit? = nil,
        showsExhaustedNotice: Bool = false,
        creditBanner: DailyCreditBanner? = nil
    ) -> ChatModel {
        let model = ChatModel(
            transport: .local(tripId: thread.id),
            focusStepId: focusStepId,
            callToActionMemory: .inMemory()
        )
        model.thread = thread
        model.turn = turn
        model.composer = composer
        model.draft = draft
        model.microphoneIsDenied = microphoneIsDenied
        model.servedCredit = dailyCredit ?? thread.dailyCredit
        model.showsExhaustedNotice = showsExhaustedNotice
        model.previewCreditBanner = creditBanner
        return model
    }
}
