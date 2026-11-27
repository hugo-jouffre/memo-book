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
/// Les photos d'une bulle ouvertes en plein écran — ``ChatModel/viewedPhotos``.
public struct ChatPhotoViewing: Identifiable, Equatable, Sendable {
    public let attachments: [PhotoAttachment]
    public let index: Int

    /// La bulle d'où elles viennent, pour retrouver **son étape** quand on
    /// élit une photo principale (T270). Les photos, elles, se relisent sur la
    /// bulle vivante : une étoile posée pendant qu'on regarde doit se voir,
    /// et celles d'ici sont figées à l'ouverture.
    public var messageId: String?

    public var id: String { attachments.map(\.id).joined(separator: "|") + "#\(index)" }
}

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

    /// Les tours partis d'ici que la file garde **faute de réseau** — envoyés
    /// hors ligne depuis un fil ouvert en ligne. Tant qu'il y en a, la barre
    /// d'envoi le dit (``showsQueuedNotice``).
    private var queuedTurnIds: Set<String> = []

    /// « Tu es hors ligne, mais tu peux continuer » au-dessus de la barre :
    /// un message vient de partir dans la file au lieu du serveur (Hugo,
    /// 12/10/2026). Pas sur un fil local — sa boîte en tête du fil le dit
    /// déjà, depuis l'ouverture.
    public var showsQueuedNotice: Bool { !queuedTurnIds.isEmpty && !isOffline }

    /// **Ce que le moniteur réseau dit maintenant** (T318).
    ///
    /// Vrai alors qu'un tour attend dans la file : le réseau va bien, et ce
    /// qu'on attend est le **serveur**. C'est l'état présent qui parle, et non
    /// la raison du départ en file : si le réseau revient pendant qu'un tour
    /// attend, la phrase change avec lui.
    public private(set) var networkIsUp = true

    /// Ce que la barre d'envoi dit d'un tour qui attend — voir
    /// ``showsQueuedNotice``.
    public var queuedNotice: String {
        networkIsUp ? ChatCopy.queuedWhileServerWorks : ChatCopy.queuedOffline
    }

    /// Ce que le fil dit de lui-même quand il s'est ouvert sans le serveur —
    /// voir ``isOffline``.
    public var threadNotice: String {
        networkIsUp ? ChatCopy.threadWhileServerWorks : ChatCopy.offline
    }

    /// Relit le moniteur. Appelé aux moments où la phrase peut changer : à
    /// l'ouverture, quand un tour part dans la file, quand la file rend son
    /// verdict, et au retour au premier plan.
    public func refreshNetworkState() async {
        networkIsUp = await transport.isOnline()
    }

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
    /// (03/10/2026) : deux minutes pleines, moins ce qui attend dans la file,
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
    /// voir depuis sa carte, **et elle seule** (Hugo, 12/10/2026).
    ///
    /// Elle retombait sur l'étape où le voyage en était
    /// (`thread.context.stepId`) : chaque récit partait épinglé sur la
    /// dernière étape, et « ton carnet compte une étape de plus » n'en ajoutait
    /// aucune sur l'accueil du voyage. Le serveur ne la sert plus, et ne range
    /// de toute façon un récit nulle part ailleurs que dans sa propre étape —
    /// seules les photos suivent l'étape choisie.
    private var activeStepId: String? { focusStepId }

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
            // Un fil local ne dit « hors ligne » que si le réseau manque
            // vraiment : sinon, c'est le serveur qui met du temps (T318).
            await refreshNetworkState()
            // Le bonjour de MEMO **arrive** au lieu d'être déjà là — voir
            // ``revealOpening(of:)``.
            let opening = openingToReveal(in: loaded)
            // Ce que le serveur rend, il l'a reçu : son crédit le compte déjà.
            // Et le téléphone le garde, pour rouvrir le fil sans réseau.
            if !isOffline {
                forgetCosts(of: loaded.messages)
                rememberThread()
            }
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

            // En dernier : le reste du chargement n'a pas à attendre la pause.
            if let opening { await revealOpening(opening) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// **Le bonjour de MEMO, sur un fil qu'on ouvre pour la première fois.**
    ///
    /// Le serveur le pose dès la première lecture du fil
    /// (`ensureOpening`, `routes/chat.ts`) : sans ça, un carnet neuf s'ouvrait
    /// sur un fil vide, et l'app y dessinait son propre mot d'accueil — qui
    /// disait presque la même chose que la bulle d'ouverture (Hugo,
    /// 28/10/2026 : « deux informations se contredisent »).
    ///
    /// Mais une bulle déjà posée quand l'écran se dessine n'a l'air de rien :
    /// elle est là, comme un décor. Celle-ci **arrive** — le mot d'accueil, la
    /// bulle d'écriture, puis le bonjour qui prend sa place —, exactement
    /// comme arrivent les réponses de MEMO (``apply(_:)``).
    ///
    /// `nil` dès qu'il y a autre chose dans le fil : on ne rejoue pas un
    /// bonjour à chaque ouverture, et une conversation entamée s'ouvre sur ce
    /// qu'on s'est dit.
    private func openingToReveal(in thread: ChatThread) -> ChatMessage? {
        guard !isOffline, thread.messages.count == 1 else { return nil }
        let only = thread.messages[0]
        return only.author.isTraveller ? nil : only
    }

    /// Retire la bulle, pose la bulle d'écriture le temps de sa pause, puis la
    /// remet. Interrompue — on quitte l'écran —, elle la remet quand même :
    /// un fil ne se garde pas amputé de son premier message.
    ///
    /// ⚠️ **Elle ne retire qu'elle.** Vider le fil puis le réécrire emportait
    /// ce que le chargement venait d'y poser : les tours qui attendaient le
    /// réseau sur le disque, posés en bulles « en cours d'envoi » quelques
    /// lignes plus haut dans ``load()``. On ouvrait alors le fil sur le
    /// bonjour seul, et ce qu'on avait dit dans le métro avait disparu.
    private func revealOpening(_ opening: ChatMessage) async {
        guard thread != nil else { return }
        thread?.messages.removeAll { $0.id == opening.id }
        turn = .thinking

        let pause = Duration.milliseconds(opening.pauseMilliseconds ?? 700)
        try? await Task.sleep(for: max(pause, Self.minimumThinking))

        // `insert` et non un `append` : la bulle reprend son rang, devant ce
        // qui attendait déjà. Et rien si elle est revenue entre-temps — un
        // sondage a pu la reposer pendant la pause.
        if thread?.messages.contains(where: { $0.id == opening.id }) == false {
            insert(opening)
        }
        if turn == .thinking { turn = .idle }
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
    ///
    /// ⚠️ **Il ne jette pas le vocal en cours** (T252). Il appelait
    /// `recorder.cancel()`, et le fichier partait avec : ouvrir les réglages du
    /// voyage depuis la conversation — ils se posent **par-dessus**, donc
    /// l'écran disparaît — effaçait ce qu'on venait de dire. Or cet écran-ci
    /// reste dans la pile, et son modèle avec : un vocal suspendu y attend le
    /// retour, comme un brouillon de texte attend dans son champ. Seule la
    /// corbeille de la barre jette (``cancelRecording()``).
    public func teardown() {
        // Ce qu'on vient de lire, gardé tel qu'on le quitte : les réponses de
        // MEMO arrivées depuis l'ouverture comprises.
        rememberThread()
        exchange?.cancel()
        exchange = nil
        poller?.cancel()
        poller = nil
        deliveryWatcher?.cancel()
        deliveryWatcher = nil
        levelSampler?.cancel()
        player.stop()
        reader.stop()
        // « Ne doit pas enregistrer » : le micro se suspend. Il ne continue pas
        // de capter derrière un écran qu'on ne regarde plus — ce serait
        // enregistrer les réglages —, et il ne perd rien de ce qui précède.
        recorder.keepForLater()
    }

    /// Garde le fil sur le téléphone — voir ``ChatTransport/remember``. Rien
    /// d'un fil local : il ne contient que ce qu'on avait déjà gardé.
    private func rememberThread() {
        guard !isOffline, let thread else { return }
        let remember = transport.remember
        Task { await remember(thread) }
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
    /// **La bulle qu'on a choisie** (T286) — cernée d'un liseré, et c'est à
    /// elle que les puces répondent. `nil` : le fil entier décide, comme
    /// avant.
    public private(set) var selectedMessageId: String?

    /// Choisit une bulle, ou la relâche si c'est elle qu'on retouche : un
    /// second appui au même endroit défait le premier, sans quoi il n'y
    /// aurait aucun moyen de revenir aux puces du fil.
    public func select(_ messageId: String) {
        selectedMessageId = selectedMessageId == messageId ? nil : messageId
    }

    /// Relâche la bulle choisie. Appelé quand on parle : ce qu'on vient de
    /// dire est la nouvelle fin du fil, et le liseré d'hier n'a plus de sens.
    public func clearSelection() {
        if selectedMessageId != nil { selectedMessageId = nil }
    }

    public var visibleSuggestions: [ChatSuggestion] {
        guard turn == .idle else { return [] }
        // **Celles de la bulle choisie**, quand le serveur les a servies
        // (T286). Une bulle sans puces à elle — un serveur d'avant, un
        // sondage — laisse les puces du fil : mieux vaut celles d'avant
        // qu'une bande vide.
        let chosen = selectedMessageId.flatMap { id in messages.first { $0.id == id }?.suggestions }
        let shown = chosen?.isEmpty == false ? chosen! : suggestions
        guard isCreditExhausted else { return shown }
        return shown.filter { $0.intent != .sendThenSpeak }
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
    /// une fiche corrigée « à la main » — ce que la correction modifie
    /// au-delà des 200 caractères offerts à la fiche (Hugo, 19/10/2026, QA
    /// D8 ; ``DailyCredit/cost(ofCorrection:replacing:freeLeft:)``).
    private var draftCost: Int {
        guard let credit else { return 0 }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let original = editingOriginalText else { return credit.cost(ofText: text) }
        return credit.cost(ofCorrection: text, replacing: original, freeLeft: editingFreeCharactersLeft)
    }

    /// Ce qui reste des 200 caractères offerts à la fiche qu'on corrige — lu
    /// sur sa fiche dans le fil, que le serveur redessine à chaque lecture.
    private var editingFreeCharactersLeft: Int? {
        guard let editingEntryId else { return nil }
        for message in messages {
            if case .transcript(let card) = message.body, card.entryId == editingEntryId {
                return card.freeCorrectionCharactersLeft
            }
        }
        return nil
    }

    /// On corrige une fiche « à la main » : pot vide, le champ ne pâlit pas —
    /// les 200 caractères offerts par fiche passent encore (QA D8).
    public var isWritingCorrection: Bool { isEditingTranscript && editingOriginalText != nil }

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
        guard composer == .writing, let credit, !credit.isUnlimited else { return nil }
        // Pot vide, une correction au-delà des 200 offerts attend l'illimité :
        // la même phrase que le refus du serveur.
        if credit.isExhausted, isWritingCorrection, draftExceedsCredit {
            return .tooLong(DailyCreditCopy.correctionBeyondFree)
        }
        guard !credit.isExhausted else { return nil }
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
        // N'écrit que ce qui change : `@Observable` prévient à chaque
        // écriture, même d'une valeur identique, et le sondage passe ici
        // toutes les deux secondes.
        if showsExhaustedNotice { showsExhaustedNotice = false }
    }

    /// Le micro de la barre : il arme l'enregistrement, ou — crédit épuisé —
    /// dit pourquoi il ne le fait pas.
    ///
    /// - Parameter keepingKeyboard: le clavier était levé au moment de
    ///   l'appui. **Il le reste** pendant qu'on parle (Hugo, 12/10/2026 — il
    ///   se baissait au milieu du vocal), et le vocal parti, la barre revient
    ///   au champ de saisie qu'on avait sous les doigts. C'est l'écran qui
    ///   tient le clavier (``ChatSendingBar``) ; le modèle retient seulement
    ///   où revenir.
    public func tapMicrophone(keepingKeyboard: Bool = false) {
        guard !isCreditExhausted else {
            showExhaustedNotice()
            return
        }
        returnsToWritingAfterRecording = keepingKeyboard
        composer = .speaking
        startRecording()
    }

    /// Le vocal en cours a été commencé clavier levé : à sa fin, la barre
    /// revient au champ — voir ``tapMicrophone(keepingKeyboard:)``.
    public private(set) var returnsToWritingAfterRecording = false

    /// La disposition où revenir quand un vocal se termine, et l'oubli du
    /// clavier qu'on tenait pour lui.
    private func composerAfterRecording() -> ChatComposerMode {
        defer { returnsToWritingAfterRecording = false }
        return returnsToWritingAfterRecording ? .writing : .tools
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
        // Le même crédit, relu à chaque sondage : ne rien réécrire, sans quoi
        // la barre d'envoi se redessinait toutes les deux secondes.
        if servedCredit != served { servedCredit = served }
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
        for message in messages where unreceivedCosts[message.id] != nil {
            unreceivedCosts[message.id] = nil
        }
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
        returnsToWritingAfterRecording = false
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

        // Ce qu'on vient de dire est la nouvelle fin du fil : le liseré d'une
        // bulle d'hier n'a plus de sens, et ses puces non plus (T286).
        clearSelection()
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
            delivery: Self.delivery(of: outgoing),
            // **L'instant du geste** : c'est lui qui range la bulle, et le
            // serveur le rendra tel quel — la place ne bougera pas à l'envoi
            // (T309).
            postedAt: outgoing.postedAt
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
                // Et l'écran **le dit** (Hugo, 12/10/2026) : sans ça, on
                // envoyait hors ligne sans savoir que c'était gardé. Reste à
                // savoir **ce qu'on attend** — le réseau, ou le serveur
                // (T318) : la phrase se choisit sur l'état présent du
                // moniteur, qu'on relit ici.
                queuedTurnIds.insert(outgoing.id)
                await refreshNetworkState()
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
                // Un message relu **à l'identique** ne change rien : le
                // serveur rend tout ce qui a bougé depuis le curseur, et une
                // fiche qui se rédige revient à chaque sondage. Réécrire le
                // fil pour rien redessinait toute la conversation toutes les
                // deux secondes (Hugo, 08/10/2026 : « mini latences, scroll
                // pas toujours fluide »), et repoussait la fin du sondage.
                if replace(message) { changed = true }
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

        if let preview = update.preview, preview != thread?.preview { thread?.preview = preview }
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
            if turn != .thinking { turn = .thinking }
        } else if turn == .thinking {
            thread?.suggestions = update.suggestions
            turn = .idle
        } else if turn == .idle, !update.suggestions.isEmpty, update.suggestions != thread?.suggestions {
            thread?.suggestions = update.suggestions
        }

        return changed
    }

    // MARK: - Le fil

    /// **Le moment où chaque bulle a été posée**, et le rang d'arrivée pour
    /// départager (T309).
    ///
    /// Avant, c'était le rang d'arrivée seul, et une bulle qui n'en avait pas
    /// encore — une photo en attente — était rangée **sous tout le reste** :
    /// elle restait en bas du fil des jours durant, puis se posait ailleurs en
    /// arrivant. Elle porte maintenant l'instant de son geste, le serveur le
    /// garde, et la place ne change plus.
    ///
    /// Un serveur d'avant le 26/11/2026 n'envoie pas d'instant : on retombe
    /// alors sur le rang, c'est-à-dire exactement l'ordre d'avant.
    private static func byRank(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        if let left = a.postedAt, let right = b.postedAt, left != right { return left < right }
        return (a.seq ?? Int.max) < (b.seq ?? Int.max)
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
    ///
    /// - Returns: vrai si le message a changé. Un message identique ne touche
    ///   pas au fil : l'écrire quand même invaliderait tout ce qui le lit.
    @discardableResult
    private func replace(_ message: ChatMessage) -> Bool {
        guard var thread, let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return false }
        let merged = message.keepingLocalFiles(of: thread.messages[index])
        guard merged != thread.messages[index] else { return false }
        thread.messages[index] = merged
        thread.messages.sort(by: Self.byRank)
        self.thread = thread
        return true
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
                // Ce que la correction modifie au-delà des 200 offerts se
                // paie, comme un texte — et le serveur l'a déjà compté : c'est
                // son chiffre, pas une attente.
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
    // MARK: - Les deux versions d'un souvenir

    /// **Garder la transcription littérale**, ou revenir au texte rédigé
    /// (Hugo, 28/10/2026).
    ///
    /// C'est un choix, pas une correction : il ne coûte ni caractères offerts
    /// ni crédit du jour, et il ne passe pas par le composeur. La fiche se
    /// redessine avec ce que le serveur rend — c'est lui qui tranche quel
    /// texte part au carnet (`finalTextOf`).
    public func keepTranscript(_ keeps: Bool, forEntry entryId: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let entry = try await transport.keepTranscript(entryId, keeps)
                refreshCard(for: entry)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// **Relancer l'analyse** d'un souvenir : l'IA le relit et en tire une
    /// version généralement plus complète.
    ///
    /// La fiche repasse par « on rédige » le temps que la nouvelle version
    /// arrive — c'est le sondage qui la rapportera, comme pour une première
    /// rédaction. Le choix de garder la littérale tombe côté serveur : on
    /// redemande une rédaction, c'est qu'on veut la lire.
    public func reanalyse(entryId: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let entry = try await transport.reanalyse(entryId)
                refreshCard(for: entry)
                // Le serveur rédige ; le fil le rapportera.
                if needsPolling { startPolling() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Où en est la fiche d'un souvenir — la même lecture que le serveur
    /// (`transcriptPhaseOf`, `routes/chatSerializers.ts`).
    private static func phase(of entry: Entry) -> TranscriptCard.Phase {
        if entry.status == .failed || entry.redactionStatus == .failed { return .failed }
        if entry.status.isInProgress { return .listening }
        if entry.redactionStatus.isInProgress { return .writing }
        return .ready
    }

    private func refreshCard(for entry: Entry) {
        guard var thread else { return }
        for index in thread.messages.indices {
            guard case .transcript(let card) = thread.messages[index].body, card.entryId == entry.id else { continue }
            thread.messages[index].body = .transcript(
                TranscriptCard(
                    title: card.title,
                    capturedAt: entry.capturedAt,
                    // Le lieu et les jours **compris** restent ceux que le
                    // serveur a servis avec la fiche (T308) : le souvenir ne
                    // porte que l'écho du lieu, et aucune date vécue.
                    livedFrom: card.livedFrom,
                    livedTo: card.livedTo,
                    placeName: card.placeName,
                    duration: card.duration,
                    text: entry.displayText ?? card.text,
                    isSimulated: false,
                    entryId: entry.id,
                    footnote: card.footnote,
                    // Le temps vient du souvenir et non d'un `.ready` posé
                    // d'office : relancer l'analyse remet la fiche à « on
                    // rédige », et c'est ce qu'elle doit montrer (28/10/2026).
                    phase: Self.phase(of: entry),
                    isValidated: entry.validatedAt != nil || card.isValidated,
                    freeCorrectionCharactersLeft: entry.freeCorrectionCharactersLeft
                        ?? card.freeCorrectionCharactersLeft,
                    // Les deux versions suivent le souvenir relu — et elles
                    // ne se déduisent pas du texte affiché, qui est tantôt
                    // l'une tantôt l'autre (`finalTextOf`). Nulles quand il
                    // n'y a rien à comparer.
                    rawText: entry.hasTwoVersions ? entry.transcript : card.rawText,
                    writtenText: entry.hasTwoVersions ? entry.redactedText : card.writtenText,
                    prefersTranscript: entry.prefersTranscript
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
        // Parti, refusé ou en attente de crédit : plus « en attente du réseau ».
        if case .sending = delivery.state {} else if queuedTurnIds.contains(delivery.id) {
            queuedTurnIds.remove(delivery.id)
        }

        // Ce que la file vient de dire d'un tour peut changer la phrase de
        // la barre : le réseau est peut-être revenu depuis (T318).
        Task { await refreshNetworkState() }

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

            composer = composerAfterRecording()
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
        composer = composerAfterRecording()
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
    ///
    /// **Une case observée par image**, et non un dictionnaire observé
    /// (08/10/2026) : chaque image arrivée réécrivait le dictionnaire entier,
    /// et toutes les bulles qui en lisaient une — photos, portraits — se
    /// redessinaient à chaque arrivée, pendant qu'on faisait défiler le fil.
    /// Une bulle n'observe plus que la case de **son** image.
    @ObservationIgnored private var imageSlots: [URL: ChatImageSlot] = [:]
    @ObservationIgnored private var loadingImages: Set<URL> = []

    /// L'image déjà chargée à cette adresse, ou `nil`. Lue dans le corps d'une
    /// bulle : seule l'arrivée de **cette** image la redessine.
    public func image(at url: URL) -> UIImage? {
        slot(for: url).image
    }

    private func slot(for url: URL) -> ChatImageSlot {
        if let slot = imageSlots[url] { return slot }
        let slot = ChatImageSlot()
        imageSlots[url] = slot
        return slot
    }

    /// Charge une image du fil, une fois. Un échec n'est pas retenu : la bulle
    /// garde sa trame ou ses initiales, et redemande en réapparaissant.
    public func loadImage(_ url: URL) {
        let slot = slot(for: url)
        guard slot.image == nil, !loadingImages.contains(url) else { return }
        loadingImages.insert(url)

        Task { [weak self] in
            guard let self else { return }
            let data = await self.imageData(at: url)
            let image = await ChatImage.decode(data)
            self.loadingImages.remove(url)
            if let image { slot.image = image }
        }
    }

    // MARK: La photo en plein écran

    /// Les photos ouvertes en plein écran (Hugo, 18/10/2026 : « quand on
    /// clique sur une photo qu'on a envoyée, elle s'affiche en plein écran »),
    /// et celle par laquelle on est entré. `nil` : rien d'ouvert.
    public var viewedPhotos: ChatPhotoViewing?

    /// Ouvre les photos d'une bulle, sur celle qu'on a touchée.
    public func viewPhotos(_ attachments: [PhotoAttachment], at index: Int, from messageId: String? = nil) {
        guard attachments.indices.contains(index) else { return }
        viewedPhotos = ChatPhotoViewing(attachments: attachments, index: index, messageId: messageId)
    }

    /// Une bulle du fil par son identifiant — la visionneuse s'en sert pour
    /// relire les photos **telles qu'elles sont maintenant**.
    public func message(_ id: String?) -> ChatMessage? {
        guard let id else { return nil }
        return messages.first { $0.id == id }
    }

    /// La photo **à sa taille d'écran**, et non la vignette du fil : relue par
    /// le même chemin (`imageData(at:)`), décodée plus grand. La vignette
    /// reste en cache pour le fil ; celle-ci vit avec la vue qui la montre.
    public func fullScreenImage(_ url: URL) async -> UIImage? {
        await ChatImage.decode(await imageData(at: url), maximumPixelSize: ChatImage.fullScreenPixelSize)
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

    /// Poste les photos choisies — **toutes**, en autant de messages qu'il
    /// faut (T265, 23/11/2026).
    ///
    /// Les images sont écrites dans les caches avant d'entrer dans le fil : une
    /// bulle qui garderait ses octets en mémoire ferait grossir la conversation
    /// à chaque photo, et les perdrait au premier retour d'arrière-plan.
    ///
    /// ## Découper plutôt que couper
    ///
    /// La borne du serveur (``ChatMetrics/maxPhotosPerMessage``) n'a pas
    /// bougé, et c'est voulu : un envoi de vingt photos est déjà de l'ordre de
    /// trois mégaoctets, et le client abandonne à soixante secondes (T275). La
    /// relever ferait échouer les gros envois au lieu de les refuser.
    ///
    /// Soixante photos partent donc en **trois tours** de vingt. Chacun a son
    /// identifiant, sa bulle et son sort : la file hors ligne les reprend un à
    /// un, et un tour qui échoue ne perd pas les autres.
    ///
    /// Avant, le surplus était **jeté** avec un bandeau d'erreur. On gardait
    /// vingt photos sur soixante, et c'est précisément ce que T265 demandait
    /// de ne plus faire : « sans limite ». Ce qui choisit maintenant, ce n'est
    /// plus le hasard de l'ordre d'arrivée, c'est la page
    /// (`services/photoPicking.ts`).
    public func sendPhotos(_ images: [PickedPhoto]) {
        guard !images.isEmpty else { return }

        // **Une photo sans mémoire se fait demander où et quand** (T315) :
        // passée par une messagerie, elle n'a ni date de prise de vue ni
        // position, et ce que la photothèque en dit est le jour où elle est
        // arrivée sur le téléphone. L'envoi entier attend la réponse — les
        // photos du lot qui savent, elles, ne seront pas retouchées.
        if images.contains(where: \.isForwarded) {
            photosAwaitingOrigin = images
            return
        }

        deliver(images)
    }

    /// Les photos choisies qui attendent de dire d'où elles viennent. `nil` :
    /// la feuille est fermée, il n'y a rien en attente.
    public private(set) var photosAwaitingOrigin: [PickedPhoto]?

    /// Combien, dans ce lot, ont perdu leur mémoire — ce que la feuille
    /// annonce. Les autres partent telles quelles.
    public var forwardedPhotoCount: Int {
        photosAwaitingOrigin?.count(where: \.isForwarded) ?? 0
    }

    /// La réponse du voyageur. Ce qu'il laisse vide ne remplace rien, et seules
    /// les photos sans mémoire sont rangées : celles qui portaient leur date
    /// en savent plus que lui.
    public func placeAwaitingPhotos(day: Date?, place: String) {
        guard let waiting = photosAwaitingOrigin else { return }
        photosAwaitingOrigin = nil
        deliver(waiting.map { $0.isForwarded ? $0.placed(day: day, place: place) : $0 })
    }

    /// La sortie, et le glissé qui referme la feuille : les photos partent
    /// comme avant T315. Elles sont déjà choisies — une sélection perdue
    /// parce qu'on n'a pas répondu serait pire que mal rangée.
    public func sendAwaitingPhotosAsIs() {
        guard let waiting = photosAwaitingOrigin else { return }
        photosAwaitingOrigin = nil
        deliver(waiting)
    }

    private func deliver(_ images: [PickedPhoto]) {
        hideExhaustedNotice()

        var envoye = false
        for lot in images.chunked(into: ChatMetrics.maxPhotosPerMessage) {
            if envoiDUnLot(lot) { envoye = true }
        }
        if envoye { composer = .tools }
    }

    /// Un lot, un tour. Rend `false` quand aucune de ses photos n'a pu être
    /// écrite sur le disque : les autres lots partent quand même.
    private func envoiDUnLot(_ images: [PickedPhoto]) -> Bool {
        let id = UUID().uuidString.lowercased()

        var uploads: [ChatPhotoUpload] = []
        for (index, picked) in images.enumerated() {
            let photoId = "\(id)-\(index)"
            guard let url = try? ChatPhotoFile.save(picked.data, id: photoId) else { continue }
            localPhotoUrls[photoId] = url
            uploads.append(
                ChatPhotoUpload(
                    data: picked.data,
                    filename: "\(photoId).jpg",
                    mimeType: "image/jpeg",
                    // Ce que la photo sait d'elle-même (T280) : sa journée et
                    // son lieu voyagent avec elle, et non avec le tour.
                    capturedAt: picked.capturedAt,
                    capturedPlaceName: picked.placeName
                )
            )
        }

        guard !uploads.isEmpty else {
            errorMessage = ChatCopy.photosUnreadable
            return false
        }

        send(.photos(uploads, capturedAt: .now), id: id)
        return true
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

    // MARK: - Les gestes d'une fiche de MEMO (T288)

    /// **Ce qu'un appui long sur une fiche a ouvert** : sa feuille des dates,
    /// ou celle du lieu. `nil` : rien d'ouvert.
    ///
    /// Une seule à la fois, et c'est l'identité qui présente — comme
    /// ``shared`` : un second geste pendant qu'une feuille est ouverte la
    /// remplace au lieu d'en empiler une seconde (`ios/CLAUDE.md`).
    public var editedFacts: ChatFactsEdit?

    /// « Ré-analyser », depuis le menu d'une fiche (T288) : le même geste que
    /// la flèche circulaire posée sur elle, par son souvenir.
    public func reanalyse(_ card: TranscriptCard) {
        guard let entryId = card.entryId else { return }
        reanalyse(entryId: entryId)
    }

    /// « Changer les dates » : la feuille s'ouvre sur ce que la fiche dit.
    public func changeDates(of card: TranscriptCard) {
        guard card.entryId != nil else { return }
        editedFacts = .dates(card)
    }

    /// « Changer le nom du lieu ».
    public func changePlace(of card: TranscriptCard) {
        guard card.entryId != nil else { return }
        editedFacts = .place(card)
    }

    /// **Fixe les jours que ce récit raconte.** `nil` partout revient aux
    /// dates déduites — la rédaction reprend la parole.
    ///
    /// La fiche change tout de suite, puis le fil se relit : la correction
    /// remonte sur l'étape côté serveur, et c'est l'étape qui date les autres
    /// fiches de la même étape. Un échec le dit et remet la fiche d'avant.
    public func saveLivedDays(from: Date?, to: Date?, for card: TranscriptCard) {
        guard let entryId = card.entryId else { return }
        editedFacts = nil
        let before = card
        apply(
            card.situated(
                from: from,
                to: from == nil ? nil : to,
                place: card.placeName,
                livedDaysByHand: from != nil
            ),
            to: entryId
        )

        Task { [weak self, transport] in
            do {
                _ = try await transport.setLivedDays(entryId, from, from == nil ? nil : to)
                await self?.load()
            } catch {
                guard let self else { return }
                apply(before, to: entryId)
                errorMessage = error.localizedDescription
            }
        }
    }

    /// **Nomme le lieu à la main.** `nil` — ou un champ vidé — rend la parole
    /// au lieu que les récits de l'étape nomment.
    public func savePlaceName(_ name: String?, for card: TranscriptCard) {
        guard let entryId = card.entryId else { return }
        editedFacts = nil
        let before = card
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = (trimmed?.isEmpty ?? true) ? nil : trimmed
        apply(
            card.situated(from: card.livedFrom, to: card.livedTo, place: wanted, placeByHand: wanted != nil),
            to: entryId
        )

        Task { [weak self, transport] in
            do {
                _ = try await transport.setPlaceName(entryId, wanted)
                await self?.load()
            } catch {
                guard let self else { return }
                apply(before, to: entryId)
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Repose une fiche dans le fil, à la place de celle qui porte le même
    /// souvenir.
    private func apply(_ card: TranscriptCard, to entryId: String) {
        guard var thread else { return }
        for index in thread.messages.indices {
            guard case .transcript(let shown) = thread.messages[index].body,
                shown.entryId == entryId
            else { continue }
            thread.messages[index].body = .transcript(card)
        }
        self.thread = thread
    }

    // MARK: - L'appui long sur une bulle (T270)

    /// Ce qu'un appui long propose de partager, tant que la feuille du système
    /// est ouverte. `nil` : rien d'ouvert.
    public var shared: ChatSharing?

    /// Les souvenirs que porte une bulle, dans l'ordre où elle les montre.
    ///
    /// Un, d'ordinaire — un texte, un vocal, la fiche qui en parle. Autant que
    /// de photos pour une bulle de photos : chaque image est un souvenir à
    /// elle (`docs/conversation.md` § 4), et c'est la bulle qui les réunit.
    /// Vide pour ce qui n'est pas un souvenir : l'ouverture de MEMO, sa
    /// réponse, une question sur l'abonnement.
    public func memories(of message: ChatMessage) -> [String] {
        switch message.body {
        case .photos(let attachments):
            return attachments.map(\.id)
        case .transcript(let card):
            return [card.entryId].compactMap(\.self)
        case .text, .voice:
            // Un vocal du contexte du voyage, ou une correction dictée, vise
            // une fiche sans être elle : le serveur refuserait de le supprimer
            // comme un souvenir, et il a raison. On ne le propose donc pas.
            //
            // `nil` compte comme un souvenir, comme dans
            // ``ChatThread/storyMessage(about:)`` : un serveur d'avant ne
            // servait pas cette clé, et ses bulles sont bien des souvenirs.
            guard message.author.isTraveller else { return [] }
            guard message.disposition == .memory || message.disposition == nil else { return [] }
            return [message.entryId].compactMap(\.self)
        }
    }

    /// « Supprimer » se propose-t-il ? Seulement sur une bulle qui **est** un
    /// souvenir, et seulement quand elle est arrivée chez nous : une bulle qui
    /// attend le réseau se retire par « Supprimer » de sa mention, qui parle à
    /// la file et non au serveur (``discardWaitingTurn(_:)``).
    public func canDelete(_ message: ChatMessage) -> Bool {
        message.delivery == .sent && !memories(of: message).isEmpty
    }

    /// « Déplacer dans une autre étape » se propose-t-il ?
    ///
    /// **Ce qu'on a dit soi-même, et qui est un souvenir** : un récit, un
    /// vocal, des photos. Pas la fiche de MEMO, qui parle du souvenir sans
    /// être la bulle qui l'a apporté — le serveur la refuserait. Pas une
    /// précision non plus : « en fait c'était mardi » vise la fiche d'un autre
    /// souvenir, elle n'a pas d'étape à elle (``memories(of:)`` les écarte).
    ///
    /// Et il faut une **autre** étape où aller : un voyage d'une seule étape
    /// n'offre pas un menu qui ne mène qu'à elle-même.
    public func canMove(_ message: ChatMessage) -> Bool {
        guard message.author.isTraveller, message.delivery == .sent else { return false }
        guard !memories(of: message).isEmpty else { return false }
        return !destinations(for: message).isEmpty
    }

    /// Les étapes où cette bulle peut aller : celles du voyage, sauf la sienne.
    public func destinations(for message: ChatMessage) -> [ChatContextStep] {
        (thread?.context.steps ?? []).filter { $0.id != message.stepId }
    }

    /// **Déplace la bulle, et la montre déplacée tout de suite.** Le serveur
    /// pose l'épingle qui tiendra au recalcul ; ici, la bulle change d'étape
    /// sans attendre la relecture, pour que le menu ne paraisse pas sans effet.
    ///
    /// Un échec remet l'étape d'avant et le dit : mieux vaut une bulle qui
    /// revient en place avec un bandeau qu'une bulle déplacée pour de faux.
    public func move(_ message: ChatMessage, toStepId stepId: String) {
        guard let index = thread?.messages.firstIndex(where: { $0.id == message.id }) else { return }
        let before = thread?.messages[index].stepId
        thread?.messages[index].stepId = stepId

        Task { [weak self, transport, id = message.id] in
            do {
                try await transport.moveMessage(id, stepId)
                // Le découpage a peut-être bougé derrière (une étape vidée
                // disparaît) : on relit le fil plutôt que de deviner.
                await self?.load()
            } catch {
                guard let self else { return }
                if let index = self.thread?.messages.firstIndex(where: { $0.id == id }) {
                    self.thread?.messages[index].stepId = before
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// **Supprime le souvenir d'une bulle** — et la bulle avec, puisque c'est
    /// lui qu'elle montrait. Le serveur efface aussi le fichier et la fiche
    /// (`services/deletion.ts`) ; la vue confirme avant d'appeler, parce que
    /// le souvenir quitte aussi le carnet.
    ///
    /// La bulle part de l'écran tout de suite : attendre la réponse laisserait
    /// une bulle qu'on vient de supprimer sous le doigt. Un échec la remet,
    /// avec le bandeau.
    public func delete(_ message: ChatMessage) {
        let ids = memories(of: message)
        guard !ids.isEmpty, let thread else { return }
        guard let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return }
        let removed = thread.messages[index]
        self.thread?.messages.remove(at: index)

        Task { [weak self, transport] in
            do {
                for id in ids { try await transport.deleteMemory(id) }
                await self?.load()
            } catch {
                guard let self else { return }
                // Remise à sa place, et non à la fin : un souvenir réapparu
                // trois bulles plus bas se lirait comme un nouveau message.
                //
                // ⚠️ Le rang se lit **avant** l'insertion, et non dans ses
                // arguments : `thread?.messages.insert(…, at: thread?.messages.count)`
                // lit et modifie `thread` dans la même expression, ce que
                // Swift refuse à l'exécution (« Fatal access conflict »).
                let count = self.thread?.messages.count ?? 0
                if self.thread?.messages.contains(where: { $0.id == removed.id }) == false {
                    self.thread?.messages.insert(removed, at: min(index, count))
                }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// **« Définir comme photo principale de l'étape »** — l'étoile verte
    /// (T270), et le même geste pour la défaire.
    ///
    /// L'étoile se pose **tout de suite**, et celle de l'ancienne élue s'en va
    /// dans le même mouvement : une étoile qui arriverait après l'aller-retour
    /// se lirait comme un geste raté. Un échec remet le fil comme il était et
    /// le dit.
    public func electStepCover(_ photo: PhotoAttachment, in message: ChatMessage) {
        guard let stepId = message.stepId else { return }
        // ⚠️ Le fil d'avant se garde **avant** de poser l'étoile : pris après,
        // il rendrait l'étoile au lieu de l'enlever quand l'appel échoue.
        let before = thread?.messages
        let elected = !photo.isStepCover
        apply(stepCover: elected ? photo.id : nil, inStep: stepId)
        send(elected ? photo.id : nil, restoring: before) { [transport] entryId in
            try await transport.electStepCover(stepId, entryId)
        }
    }

    /// **« Définir comme photo principale du voyage »** — l'étoile lime.
    public func electTripCover(_ photo: PhotoAttachment) {
        let before = thread?.messages
        let elected = !photo.isTripCover
        apply(tripCover: elected ? photo.id : nil)
        send(elected ? photo.id : nil, restoring: before) { [transport] entryId in
            try await transport.electTripCover(entryId)
        }
    }

    /// L'étoile verte du fil : une par étape, et aucune si `entryId` est nul.
    private func apply(stepCover entryId: String?, inStep stepId: String) {
        updatePhotos { message, photo in
            guard message.stepId == stepId else { return }
            photo.isStepCover = photo.id == entryId
        }
    }

    /// L'étoile lime : une par voyage.
    private func apply(tripCover entryId: String?) {
        updatePhotos { _, photo in photo.isTripCover = photo.id == entryId }
    }

    /// Parcourt les photos du fil et laisse `change` les retoucher. Ne réécrit
    /// que les bulles qui bougent : `@Observable` prévient à chaque écriture,
    /// et le fil se redessinerait en entier pour une étoile.
    private func updatePhotos(_ change: (ChatMessage, inout PhotoAttachment) -> Void) {
        guard let thread else { return }
        for index in thread.messages.indices {
            let message = thread.messages[index]
            guard case .photos(let attachments) = message.body else { continue }
            var updated = attachments
            for photoIndex in updated.indices { change(message, &updated[photoIndex]) }
            if updated != attachments { self.thread?.messages[index].body = .photos(updated) }
        }
    }

    /// Envoie une élection, et remet le fil tel qu'il était si elle échoue.
    private func send(
        _ entryId: String?,
        restoring before: [ChatMessage]?,
        _ call: @escaping (String?) async throws -> Void
    ) {
        Task { [weak self] in
            do {
                try await call(entryId)
                // Le voyage a changé d'image : l'accueil et l'en-tête du fil
                // la lisent, on relit donc le fil pour les mettre d'accord.
                await self?.load()
            } catch {
                guard let self else { return }
                if let before { self.thread?.messages = before }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// **« Partager »** : le texte d'une bulle, ou ses photos. C'est la feuille
    /// du système qui s'ouvre — elle seule connaît les apps installées, les
    /// appareils AirDrop à portée et les habitudes de l'utilisateur.
    ///
    /// Les photos partent **à leur taille d'écran** et non en vignette du fil :
    /// on partage une photo pour qu'elle soit regardée ailleurs.
    public func share(_ message: ChatMessage) {
        if case .photos(let attachments) = message.body {
            let urls = attachments.compactMap(\.displayUrl)
            guard !urls.isEmpty else { return }
            Task { [weak self] in
                var images: [UIImage] = []
                for url in urls {
                    if let image = await self?.fullScreenImage(url) { images.append(image) }
                }
                guard let self, !images.isEmpty else { return }
                self.shared = ChatSharing(images: images)
            }
            return
        }
        guard let text = message.spokenText, !text.isEmpty else { return }
        shared = ChatSharing(text: text)
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

    /// « Compléter l'étape manquante » — le seul bouton de bulle qui **parle**
    /// au lieu d'ouvrir un écran (19/10/2026).
    ///
    /// Il part comme une puce, avec l'identifiant que le catalogue serveur
    /// connaît : c'est ce qui en fait une commande — gratuite, jamais un
    /// souvenir — et non un texte libre. MEMO répond en nommant la journée, et
    /// le souvenir qui suit se datera sur elle.
    public func fillMissingDay() {
        send(.text(ChatCopy.CallToAction.fillMissingDay, suggestionId: ChatCopy.CallToAction.fillMissingDayId))
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
    nonisolated static let localNoticePrefix = "local-daily-credit-"

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
    /// La fiche que visent les puces de validation : celle dont MEMO vient
    /// de demander « Il te convient ? » quand il le dit (``ChatMessage/entryId``
    /// — il revient parfois à une étape sautée, 12/10/2026), sinon la
    /// dernière fiche remplie du fil.
    private var latestTranscriptCard: TranscriptCard? {
        let asked = messages.last { $0.author == .memo && $0.entryId != nil }?.entryId
        var latest: TranscriptCard?
        for message in messages.reversed() {
            guard case .transcript(let card) = message.body, let text = card.text, !text.isEmpty else { continue }
            if asked == nil || card.entryId == asked { return card }
            latest = latest ?? card
        }
        return latest
    }

    // MARK: -

    /// **Une bulle se pose à sa place, pas à la fin** (T309).
    ///
    /// Le plus souvent c'est la même chose : on parle maintenant, et maintenant
    /// est après tout le reste. Mais un tour qui attend le réseau depuis hier
    /// se pose **hier**, entre les bulles de son époque — c'est tout l'objet
    /// du ticket, et sans ça il serait resté en bas du fil.
    private func append(_ message: ChatMessage) {
        guard var thread else { return }
        let place = thread.messages.firstIndex { Self.byRank(message, $0) } ?? thread.messages.endIndex
        thread.messages.insert(message, at: place)
        self.thread = thread
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
