import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookPayments
import MemoBookRecording
import Observation
import SwiftUI

/// Les dépendances que les écrans partagent. Un seul point d'assemblage :
/// l'app en construit une instance réelle, les aperçus SwiftUI une simulée.
///
/// **L'enregistrement de l'appareil n'est pas une condition de démarrage.**
/// Il l'a été, et l'app ouvrait sur « Connexion impossible » avant même d'avoir
/// affiché quoi que ce soit — y compris pour des écrans qui n'ont besoin de
/// rien (l'accueil, par exemple). Ici l'enregistrement est **paresseux** : il
/// se déclenche au premier appel réseau qui en a besoin, et son échec est
/// l'erreur de cet appel-là, pas un mur devant l'app.
@MainActor
@Observable
public final class AppDependencies {
    public let api: any MemoBookAPI

    /// La file de départ des vocaux. Elle vit **ici** et non dans un écran :
    /// un souvenir raconté dans un tunnel doit repartir tout seul au retour du
    /// réseau, quel que soit l'écran affiché à ce moment-là — et même si on
    /// n'est jamais revenu sur l'accueil depuis.
    public let outbox: RecordingOutbox

    /// Qui ouvre une feuille de paiement.
    ///
    /// Une dépendance injectée et non un appel direct au SDK : les aperçus
    /// Xcode et les tests en fournissent une qui n'appelle personne, et l'écran
    /// de cagnotte se relit sans compte Stripe.
    public let payments: any PaymentPresenter

    /// Qui achète l'abonnement — StoreKit, ou un double qui n'appelle personne.
    ///
    /// **À part de ``payments``, et pour de bon** : l'abonnement est un service
    /// numérique, Apple impose l'achat intégré, et le faire passer par la
    /// feuille Stripe ferait rejeter le binaire (règle 3.1.1).
    public let subscriptions: any SubscriptionStore

    /// Qui ouvre la feuille « Moyens de paiement » de Stripe, depuis le profil.
    /// La vraie par défaut ; un aperçu passe ``StubPaymentMethodsPresenter``.
    public let paymentMethods: any PaymentMethodsPresenter

    /// Ce que l'app garde du serveur sur l'appareil — voir ``ContentCache``.
    ///
    /// **Deux usages pour une seule pièce** : relire hors ligne, ce pour quoi
    /// il existait ; et **ouvrir vite**, ce qu'il fait depuis le 16/09/2026 —
    /// un écran déjà vu se dessine avec ce qu'on avait pendant que la lecture
    /// réseau continue derrière.
    private let content = ContentCache()

    /// Enregistrement en cours ou terminé. Le garder permet à plusieurs écrans
    /// qui démarrent en même temps d'attendre le même appel plutôt que d'en
    /// lancer un chacun.
    private var registration: Task<Void, any Error>?

    /// - Parameters:
    ///   - connectivity: d'où l'app apprend qu'elle a du réseau. Le vrai
    ///     moniteur par défaut ; un test en fournit un qu'il pilote.
    ///   - pendingRecordings: où dorment les vocaux qui n'ont pas pu partir.
    ///   - pendingTrips: où dorment les voyages créés hors ligne.
    ///   - payments: qui ouvre la feuille de paiement. La vraie par défaut ;
    ///     une preview Xcode — et le lancement `-previewSignedIn` — passe
    ///     ``StubPaymentPresenter``, qui n'appelle personne.
    ///   - subscriptions: qui achète l'abonnement. StoreKit par défaut ; un
    ///     aperçu passe ``StubSubscriptionStore``.
    public init(
        api: any MemoBookAPI,
        connectivity: Connectivity = .system,
        pendingRecordings: PendingRecordingStore = .inLibrary(),
        pendingTrips: PendingTripStore = .inLibrary(),
        payments: (any PaymentPresenter)? = nil,
        subscriptions: (any SubscriptionStore)? = nil,
        paymentMethods: (any PaymentMethodsPresenter)? = nil,
    ) {
        self.api = api
        // La vraie feuille Stripe par défaut ; un aperçu passe la sienne.
        // `applePayMerchantId` reste nul tant que le certificat Apple Pay n'est
        // pas posé : la feuille montre alors les cartes seules, au lieu d'un
        // bouton Apple Pay qui échouerait au moment de payer.
        self.payments = payments ?? StripePaymentSheetPresenter()
        self.subscriptions = subscriptions ?? StoreKitSubscriptionStore()
        self.paymentMethods = paymentMethods ?? StripeCustomerSheetPresenter()
        // Tout ce qu'on dit part par la file, et la file parle à la
        // conversation (`POST /v1/trips/:id/chat`) : le vocal de l'accueil est
        // un tour comme un autre, avec l'identifiant de sa bulle. La durée
        // voyage avec (`PendingTurn.duration`), donc un vocal parti trois
        // jours plus tard décompte la même chose.
        //
        // Les voyages créés hors ligne passent par elle aussi, et **avant** ce
        // qu'on y raconte : la création se rejoue sur l'identifiant que l'app
        // a tiré (`POST /v1/trips`), celui que les tours en attente portent.
        outbox = RecordingOutbox(
            store: pendingRecordings,
            trips: pendingTrips,
            connectivity: connectivity,
            send: { turn, tripId in try await ChatTransport.sendNow(turn, to: tripId, api: api) },
            createTrip: { draft in try await api.createTrip(draft) }
        )

        // Au démarrage, et pas à l'ouverture d'un écran : c'est ce qui permet
        // de savoir qu'on est hors ligne **avant** de dessiner l'accueil, et de
        // repartir avec ce qu'un lancement précédent avait laissé en file.
        outbox.start()

        // **Au lancement, et pas à l'ouverture du paywall** : un renouvellement,
        // une validation parentale ou un remboursement arrivent quand ils
        // veulent, et StoreKit garde ceux qu'on n'écoute pas.
        self.subscriptions.startListening(deliver: Self.deliveringTransaction(to: api, memoId: nil))
    }

    /// Remet une transaction App Store au serveur — voir
    /// ``MemoBookAPI/syncAppStoreTransaction(signedTransaction:memoId:)``.
    ///
    /// **Un refus définitif devient ``TransactionRefused``** : un achat fait
    /// depuis un autre compte MemoBook (403), un abonnement déjà rattaché
    /// ailleurs (409), une transaction que le serveur ne sait pas vérifier
    /// (400 — un achat Xcode envoyé à la production). StoreKit la finit alors,
    /// et l'écran affiche le message du serveur au lieu d'un abonnement qui
    /// n'existe pas. Tout le reste — pas de réseau, pas de session, une panne —
    /// lève tel quel, et la transaction reste ouverte pour la prochaine fois.
    nonisolated static func deliveringTransaction(
        to api: any MemoBookAPI,
        memoId: String?
    ) -> TransactionDelivery {
        { signed in
            do {
                _ = try await api.syncAppStoreTransaction(signedTransaction: signed.jws, memoId: memoId)
            } catch APIError.server(let statusCode, _, let message)
                where [400, 403, 409].contains(statusCode)
            {
                throw TransactionRefused(message: message)
            }
        }
    }

    /// Remet au serveur ce que StoreKit garde encore — à la connexion : un
    /// renouvellement arrivé pendant que personne n'était connecté n'a pas pu
    /// partir.
    func deliverUnfinishedTransactions() async {
        await subscriptions.deliverUnfinished(deliver: Self.deliveringTransaction(to: api, memoId: nil))
    }

    /// Ce que l'offre sait faire de l'App Store, pour **ce** compte — posé par
    /// `RootView` une fois connecté. L'identifiant du compte devient
    /// l'`appAccountToken` de l'achat : c'est lui qui permet au serveur de
    /// rattacher chaque renouvellement sans que l'app soit ouverte.
    func subscriptionPurchase(accountId: String) -> SubscriptionPurchase {
        let token = UUID(uuidString: accountId)
        return SubscriptionPurchase(
            displayPrice: { [subscriptions] in await subscriptions.displayPrice() },
            purchase: { [subscriptions, api] memoId in
                await subscriptions.purchase(
                    appAccountToken: token,
                    deliver: Self.deliveringTransaction(to: api, memoId: memoId)
                )
            },
            restore: { [subscriptions, api] in
                try await subscriptions.restore(deliver: Self.deliveringTransaction(to: api, memoId: nil))
            },
            willAutoRenew: { [subscriptions] in await subscriptions.willAutoRenew() }
        )
    }

    public convenience init(configuration: APIConfiguration = .localDevelopment) {
        self.init(api: MemoBookAPIClient(configuration: configuration))
    }

    /// Efface ce que l'app garde du compte qui s'en va. À appeler à la
    /// déconnexion : les voyages de quelqu'un ne doivent pas apparaître, même
    /// une demi-seconde, devant la personne suivante.
    ///
    /// **Les vocaux en attente, eux, restent.** Ce sont des souvenirs que
    /// personne n'a encore lus : si le même compte revient, ils repartent ; si
    /// c'en est un autre, le serveur les refuse et la file le dit. Les jeter
    /// serait le seul geste irréversible du lot.
    public func forgetAccountContent() async {
        await content.clearAll()
        // Les voyages créés hors ligne restent sur le disque, comme les
        // vocaux : ils ne se montrent plus, et ne partent plus, tant que leur
        // compte n'est pas revenu.
        outbox.setAccount(nil)
    }

    /// Relit la session gardée au trousseau — voir ``SessionRestore``.
    ///
    /// Une session refusée emporte ce qu'on gardait du compte, comme une
    /// déconnexion : l'écran d'entrée qui suit peut accueillir quelqu'un
    /// d'autre.
    public func restoreSession() async -> SessionRestore {
        let restore = await SessionRestore.resolve(
            verify: { [api] in try await api.currentAccount() },
            isStillStored: { [api] in await api.hasStoredSession() },
            remembered: { [content] in await content.read(.account, as: Account.self) }
        )
        if restore == .closed { await content.clearAll() }
        return restore
    }

    /// Garde le compte de la session ouverte, pour rouvrir l'app le jour où
    /// le serveur ne répond pas. Effacé avec le reste à la déconnexion.
    public func rememberAccount(_ account: Account) async {
        await content.write(.account, account)
        // Ses voyages créés hors ligne réapparaissent, et partent s'il y a du
        // réseau.
        outbox.setAccount(account.id)
    }

    /// Garantit que l'appareil est enregistré avant un appel réseau.
    ///
    /// Idempotent, et rejouable : après une panne réseau, l'appel suivant
    /// retente au lieu de rester bloqué sur l'échec précédent.
    public func ensureRegistered() async throws {
        if let registration {
            do {
                return try await registration.value
            } catch {
                // L'essai précédent a échoué : on le jette et on retente.
                self.registration = nil
            }
        }

        let task = Task { try await api.ensureDeviceRegistered() }
        registration = task
        try await task.value
    }

    // MARK: - Les modèles branchés sur l'API
    //
    // Chaque écran reçoit une **source**, une fonction qui rend son contenu.
    // Par défaut c'est le jeu d'essai, ce qui laisse les aperçus SwiftUI
    // fonctionner sans serveur. Ces trois fabriques rendent le même modèle,
    // branché sur le réseau.
    //
    // C'est ce que `RootView` passe aux trois écrans : l'app tourne donc sur
    // les données du serveur, et les aperçus SwiftUI sur le jeu d'essai, sans
    // qu'aucune vue ni aucun modèle ait à savoir lequel des deux le sert.

    /// L'accueil, servi par `GET /v1/home`. Exige une session ouverte.
    ///
    /// La source **passe par le cache** : ce qui arrive du serveur y est
    /// recopié, et une panne de réseau relit ce qu'on avait au lieu de vider
    /// l'écran. C'est ce qui rend vraie la phrase de la boîte d'information —
    /// « tu peux consulter tes récits ».
    ///
    /// Les vocaux, eux, ne passent plus par une fonction de l'écran : ils vont
    /// dans la ``RecordingOutbox``, qui décide d'envoyer ou de garder. Un
    /// identifiant de voyage est un identifiant de carnet — `trips[].id` et
    /// `memos.id` sont la même colonne côté serveur —, donc la route des
    /// souvenirs le prend tel quel.
    ///
    /// Le lieu est laissé vide : l'app ne demande pas encore la position, et
    /// inventer un libellé serait pire que de n'en donner aucun.
    ///
    /// **Les voyages créés hors ligne s'y ajoutent**, devant ceux du serveur :
    /// on vient de les créer, et ils doivent être là — sur le cache comme sur
    /// la réponse fraîche, tant que le serveur ne les a pas reçus. En
    /// supprimer un l'oublie sur le téléphone, avec ce qu'on y avait raconté :
    /// personne d'autre ne l'a jamais vu.
    public func homeModel() -> HomeModel {
        let read = cachedSource(.home) { [api] in try await api.homeFeed() }

        return HomeModel(
            source: { [outbox] in
                let feed = try await read()
                // Sur le fil principal, comme la file : rien à attendre.
                return outbox.mergingLocalTrips(into: feed)
            },
            cached: { [content, outbox] in
                guard let stored = await content.read(.home, as: HomeFeed.self) else { return nil }
                return await outbox.mergingLocalTrips(into: stored)
            },
            outbox: outbox,
            remove: { [api, outbox] id in
                if await outbox.discardLocalTrip(id) { return }
                try await api.deleteMemo(id: id)
            },
            join: { [api] code in try await api.joinTrip(code: code) }
        )
    }

    /// Enveloppe une lecture réseau du cache : elle **recopie** ce qui arrive,
    /// et **relit** ce qu'elle avait si le transport échoue.
    ///
    /// **On ne se replie que sur une panne de transport.** Un 500 ou un 404
    /// sont des réponses : les cacher derrière un contenu périmé, c'est masquer
    /// une panne du serveur — et laisser quelqu'un travailler sur un écran qui
    /// ment.
    ///
    /// Le repli et l'ouverture rapide sont **deux choses** : celui-ci rattrape
    /// une panne, l'autre — le `cached:` du modèle — dessine *avant* d'appeler.
    /// Les deux lisent le même fichier, et c'est pour ça qu'ils tiennent dans
    /// la même pièce.
    private func cachedSource<Value: Codable & Sendable>(
        _ slot: ContentCache.Slot,
        _ fetch: @escaping @Sendable () async throws -> Value
    ) -> @Sendable () async throws -> Value {
        { [content] in
            do {
                let fresh = try await fetch()
                await content.write(slot, fresh)
                return fresh
            } catch {
                guard (error as? APIError)?.isTransport == true,
                    let stored = await content.read(slot, as: Value.self)
                else { throw error }

                return stored
            }
        }
    }

    /// Le profil, servi par `GET /v1/profile` — et corrigé par `PATCH`.
    ///
    /// Les deux ensemble, et pas seulement la lecture : une ligne du profil
    /// s'enregistre en perdant le focus, sans bouton pour valider. Sans la
    /// seconde fonction, corriger son numéro de téléphone ne changeait rien
    /// ailleurs que sur l'écran, jusqu'au prochain chargement qui le remettait
    /// comme avant.
    public func profileModel() -> ProfileModel {
        ProfileModel(
            source: cachedSource(.profile) { [api] in try await api.profile() },
            persist: { [api] edit in try await api.updateProfile(edit) },
            // La troisième, et la seule sans retour : elle supprime le compte
            // et tout ce qui est à lui. L'écran demande confirmation avant.
            remove: { [api] in try await api.deleteAccount() },
            uploadAvatar: { [api] data, mimeType in
                try await api.uploadAvatar(data: data, mimeType: mimeType)
            },
            deleteAvatar: { [api] in try await api.removeAvatar() },
            changePassword: { [api] current, new in
                try await api.changePassword(current: current, new: new)
            },
            requestPasswordReset: { [api] email in try await api.requestPasswordReset(email: email) },
            // La résiliation, qui ne partait nulle part avant le 19/09/2026 —
            // voir ``ProfileModel/cancelSubscription(reason:)``.
            cancelSubscription: { [api] reason in
                try await api.cancelSubscription(reason: reason)
            },
            // « Exporter mes données » : le lien part par e-mail, l'archive se
            // compose à son ouverture — voir ``DataExportSheet``.
            exportData: { [api] in try await api.requestDataExport() },
            cached: { [content] in await content.read(.profile, as: TravellerProfile.self) }
        )
    }

    /// Les chiffres du profil, servis par `GET /v1/profile/statistics`.
    ///
    /// Un modèle à part du profil, parce qu'il **veille** : il relit sa route
    /// tant que le serveur annonce des relevés en attente, et repart à chaque
    /// vocal livré — d'où la file, passée en plus de la source. Le cache lui
    /// donne son ouverture immédiate, comme aux cinq autres écrans.
    public func statisticsModel() -> StatisticsModel {
        StatisticsModel(
            source: cachedSource(.statistics) { [api] in try await api.travelStatistics() },
            cached: { [content] in await content.read(.statistics, as: TravelStatistics.self) },
            outbox: outbox
        )
    }

    /// Un voyage ouvert, servi par `GET /v1/trips/:id`.
    ///
    /// Un voyage créé hors ligne n'y est pas encore — le serveur répond par
    /// une panne de transport, ou par un 404 tant que la création n'est pas
    /// arrivée. Il s'ouvre alors sur ce que l'app en sait : son brouillon.
    public func tripModel(id: String) -> TripHomeModel {
        // La source est construite **ici**, une fois, parce que le voyage est
        // fixé à la construction du modèle : c'est ce qui permet au cache
        // d'avoir sa case (`.trip(id)`) sans que le modèle sache qu'il existe.
        let read = cachedSource(.trip(id)) { [api] in try await api.tripDetail(id: id) }

        return TripHomeModel(
            tripId: id,
            source: { [outbox] _ in
                do {
                    return try await read()
                } catch {
                    guard let waiting = outbox.localTrip(id) else { throw error }
                    return TripDetail(trip: waiting.trip)
                }
            },
            cached: { [content, outbox] in
                if let stored = await content.read(.trip(id), as: TripDetail.self) { return stored }
                return await outbox.localTrip(id).map { TripDetail(trip: $0.trip) }
            },
            validateStep: { [api] tripId, stepId in try await api.validateStep(tripId: tripId, stepId: stepId) }
        )
    }

    /// La conversation avec MEMO — `docs/conversation.md`.
    ///
    /// Le fil vit sur le serveur (`GET`/`POST`/`DELETE /v1/trips/:id/chat`) et
    /// MEMO y répond dans un job : le modèle reçoit un ``ChatTransport`` qui
    /// relie ces routes, et **rien d'autre** — il ne sait pas s'il tient le
    /// serveur ou le moteur local des aperçus, qui offre le même contrat
    /// (`ChatTransport.local`). Pas de cache pour le fil, et c'est voulu : « un
    /// fil périmé se lit comme un message perdu ».
    ///
    /// **L'envoi passe par la file**, comme le vocal de l'accueil : hors
    /// ligne, un tour attend sur le disque au lieu d'échouer, et la bulle
    /// reste « en cours d'envoi » jusqu'à ce que la file dise qu'il est parti
    /// (``RecordingOutbox/turnDeliveries()``). Le modèle ne voit qu'un
    /// ``ChatSendOutcome``, ce qui attend, et ce qui part.
    public func chatModel(tripId: String, stepId: String? = nil) -> ChatModel {
        var transport = ChatTransport.remote(api: api, tripId: tripId)
        transport.send = { [outbox] turn in
            switch await outbox.submit(turn, to: tripId) {
            case .delivered(let receipt):
                // Sans reçu — réponse illisible —, le tour est arrivé quand
                // même : on dit au modèle qu'une réponse est en vol, et le
                // sondage relira ce que le serveur a écrit, depuis le curseur
                // qu'il tenait déjà.
                return .received(
                    receipt ?? ChatTurnReceipt(messages: [], turn: .replying(messageId: turn.id), now: .distantPast)
                )
            case .queued:
                return .queued
            case .rejected(let message):
                throw RecordingOutbox.Rejection(message: message)
            }
        }
        transport.waiting = { [outbox] in await outbox.waiting(for: tripId) }
        transport.deliveries = { [outbox] in await outbox.turnDeliveries() }
        // Sans réseau, ou pour un voyage que le serveur n'a pas encore reçu :
        // un fil **local** — l'accueil de MEMO, et ce qui attend d'être envoyé.
        // Pas une copie de l'ancien fil : un fil périmé se lit comme un message
        // perdu (`ios/CLAUDE.md`, « Le cache local »).
        transport.offlineThread = { [outbox, content] error in
            let traveller = await content.read(.home, as: HomeFeed.self)?.traveller
            if let waiting = await outbox.localTrip(tripId) {
                return .offline(trip: waiting.trip, traveller: traveller, isNew: true)
            }
            guard (error as? APIError)?.isTransport == true else { return nil }
            // Le titre du voyage, depuis ce qu'on en a gardé : l'écran du
            // voyage, à défaut l'accueil.
            var known = await content.read(.trip(tripId), as: TripDetail.self)?.trip
            if known == nil {
                known = await content.read(.home, as: HomeFeed.self)?.trips.first { $0.id == tripId }
            }
            return .offline(
                trip: known ?? Trip(id: tripId, title: TripDraft.untitled, stage: .ongoing),
                traveller: traveller,
                isNew: false
            )
        }
        return ChatModel(transport: transport, focusStepId: stepId)
    }

    /// La galerie des carnets de la communauté, servie par `GET /v1/gallery`.
    public func galleryModel() -> GalleryModel {
        GalleryModel(
            source: cachedSource(.gallery) { [api] in try await api.gallery() },
            cached: { [content] in await content.read(.gallery, as: Gallery.self) }
        )
    }

    /// Les six étapes de « Créer un voyage ». Deux routes et non une : la
    /// seconde sert la flèche de retour, qui ne doit pas créer un second
    /// voyage — voir ``TripCreationModel``.
    ///
    /// **Une seule fonction pour les deux, désormais** (01/10/2026) : le
    /// voyage part par la file, sous l'identifiant que l'app a tiré, et la
    /// création se rejoue sur lui — corriger, c'est la renvoyer. Le code
    /// d'accès arrive quand le serveur l'a créé, hors ligne au retour du
    /// réseau.
    public func tripCreationModel() -> TripCreationModel {
        TripCreationModel(
            save: { [outbox] draft in try await outbox.saveTrip(draft) },
            sync: { [outbox] id in await outbox.tripSync(for: id) },
            themes: { [api] in try await api.tripThemes() }
        )
    }

    /// Les réglages d'un voyage, servis par `GET /v1/trips/:id/settings` — et
    /// corrigés par son `PATCH`.
    ///
    /// Deux fonctions de plus que les autres écrans, et elles ne pouvaient pas
    /// passer par le `PATCH` : retirer un co-voyageur et lui renvoyer son lien
    /// touchent `memo_members`, pas `memos`. Elles ont donc leur route, et le
    /// modèle les reçoit comme le reste.
    public func tripSettingsModel(tripId: String) -> TripSettingsModel {
        let read = cachedSource(.tripSettings(tripId)) { [api] in
            try await api.tripSettings(id: tripId)
        }

        return TripSettingsModel(
            tripId: tripId,
            source: { _ in try await read() },
            persist: { [api] id, edit in try await api.updateTripSettings(id: id, edit: edit) },
            removeCompanion: { [api] id, companionId in
                try await api.removeCompanion(tripId: id, companionId: companionId)
            },
            resendInvitation: { [api] id, companionId in
                try await api.resendInvitation(tripId: id, companionId: companionId)
            },
            // La seule sans retour : `DELETE /v1/memos/:id`, que le serveur
            // réserve au propriétaire. L'écran demande confirmation avant.
            delete: { [api] id in try await api.deleteMemo(id: id) },
            // `DELETE /v1/trips/:id/chat` : le serveur efface le fil et repose
            // l'ouverture. Propriétaire seul — il refuse (403) à un co-voyageur,
            // et l'écran l'a déjà dit en pâlissant le lien.
            clearConversation: { [api] id in try await api.clearChat(tripId: id) },
            // Les limites de souvenirs : le seul « achat » que cet écran porte.
            setMemoryPlan: { [api] id, plan in
                try await api.setMemoryPlan(tripId: id, plan: plan)
            },
            cached: { [content] in
                await content.read(.tripSettings(tripId), as: TripSettings.self)
            },
            themes: { [api] in try await api.tripThemes() }
        )
    }

    /// Les personnalisations du carnet.
    ///
    /// **La même route que les réglages**, et c'est voulu : les
    /// personnalisations voyagent avec eux — il y en a un jeu par voyage, et
    /// les feuilles ont besoin des **dates** pour projeter leurs paliers de
    /// pages.
    ///
    /// ⚠️ L'aperçu du carnet, lui, reste à écrire : `GET /v1/memos/:id/preview`
    /// n'existe pas. Les deux pages qui flottent au-dessus des feuilles restent
    /// donc en papier nu tant qu'elle n'est pas là — voir ``BookPagesPeek``.
    public func bookCustomisationModel(tripId: String) -> BookCustomisationModel {
        BookCustomisationModel(
            tripId: tripId,
            source: { [api] id in try await api.tripSettings(id: id) },
            persist: { [api] id, edit in
                try await api.updateBookCustomisation(tripId: id, edit: edit)
            },
            // Les pointillés d'avant le verrou, gardés sur le téléphone : ils
            // doivent survivre à la fermeture de l'écran (Hugo, 02/10/2026).
            rulesMemory: .device()
        )
    }

    /// Les deux plats du carnet, servis par `GET /v1/trips/:id/covers` et
    /// corrigés par son `PATCH` ; les photos importées partent par
    /// `POST /v1/trips/:id/covers/photos` (T88, 29/09/2026). Le style, la
    /// photo retenue, les deux textes et les chiffres du dos tiennent dans
    /// `memos.coverFront` et `coverBack` : choisir une couverture survit à la
    /// fermeture de l'écran.
    public func coversModel(tripId: String) -> CoversModel {
        CoversModel(
            tripId: tripId,
            source: { [api] id in try await api.bookCovers(tripId: id) },
            persist: { [api] id, edit in try await api.updateBookCovers(tripId: id, edit: edit) },
            upload: { [api] id, data in try await api.uploadCoverPhoto(tripId: id, data: data) }
        )
    }

    /// L'aperçu du carnet, branché sur le serveur (26/09/2026 pour la cagnotte,
    /// 30/09/2026 pour le reste) : `GET /v1/memos/:id/preview` pour suivre la
    /// composition, `POST /v1/memos/:id/share-link` pour le lien de partage.
    public func bookPreviewModel(memoId: String) -> BookPreviewModel {
        BookPreviewModel(
            memoId: memoId,
            source: { [api] id in try await api.bookPreview(memoId: id) },
            requestLink: { [api] id in try await api.bookShareLink(memoId: id) },
            walletShare: { [api] memoId in
                async let wallet = api.wallet(tripId: memoId)
                async let link = api.bookShareLink(memoId: memoId)
                return try await WalletShare(tripId: memoId, title: wallet.tripTitle ?? "", link: link)
            }
        )
    }

    /// Ma cagnotte, servie par `GET /v1/wallet`.
    ///
    /// La route existait déjà ; c'est l'app qui ne l'appelait pas, et chaque
    /// écran affichait donc son propre jeu d'essai — 65,97 € ici, 67,88 € dans
    /// les réglages du voyage, autre chose ailleurs. Une seule source
    /// maintenant : le registre du serveur.
    ///
    /// `topUp` ouvre une intention côté serveur, présente la feuille, puis
    /// **attend que la cagnotte ait bougé** — voir ``creditedWallet(after:)``.
    ///
    /// `sandbox` n'existe qu'en debug, et écrit une **vraie** écriture : c'est
    /// ce qui permet de voir les déductions du tunnel de commande, que le
    /// serveur calcule et qu'une addition locale ne pouvait pas atteindre.
    public func walletModel(tripId: String?) -> WalletModel {
        WalletModel(
            tripId: tripId,
            source: { [api] trip in try await api.wallet(tripId: trip) },
            topUp: { [api, payments] trip, amount in
                // Le solde d'avant, lu maintenant : c'est la référence qui dira
                // que le webhook est passé. Le demander au serveur plutôt que
                // de croire l'écran évite de partir d'un solde périmé, affiché
                // avant qu'un proche ne contribue.
                let before = try await api.wallet(tripId: trip).balance

                let cents = NSDecimalNumber(decimal: amount * 100).intValue
                let ticket = try await api.startWalletTopUp(
                    amountCents: cents,
                    stripeApiVersion: StripeSDK.apiVersion
                )

                switch await payments.present(ticket) {
                case .cancelled:
                    return nil
                case .failed(let message):
                    throw PaymentError.refused(message)
                case .succeeded:
                    return try await Self.creditedWallet(
                        from: { try await api.wallet(tripId: trip) },
                        above: before
                    )
                }
            },
            sandbox: {
                #if DEBUG
                    { [api] amount, kind, label in
                        try await api.addWalletSandboxEntry(amount: amount, kind: kind, label: label)
                    }
                #else
                    nil
                #endif
            }(),
            shareLink: { [api] memoId in try await api.bookShareLink(memoId: memoId) }
        )
    }

    /// Le tunnel de commande, **entièrement servi par le serveur** — c'est ce
    /// qui le distingue des quatre écrans ci-dessus.
    ///
    /// Quatre routes : `GET /v1/memos/:id/order-context` ouvre les sept étapes
    /// d'un seul appel, `POST /v1/memos/:id/orders/quote` compte le
    /// récapitulatif, `POST /v1/memos/:id/orders` enregistre **et rend de quoi
    /// payer**, et `GET /v1/orders/:id` relit ce que le webhook a conclu.
    ///
    /// La commande naît en `draft` et n'en sort que sur retour de Stripe au
    /// serveur : `presentPayment` ouvre la feuille, `reloadOrder` attend le
    /// verdict. L'app ne décide jamais qu'une commande est payée.
    ///
    /// - Parameter email: l'adresse à laquelle la confirmation partira, pour
    ///   la dernière phrase de l'écran de confirmation. `nil` quand le compte
    ///   n'en a pas — la phrase s'abrège alors au lieu de promettre un envoi
    ///   sans destinataire.
    public func orderModel(memoId: String, email: String? = nil) -> OrderModel {
        OrderModel(
            memoId: memoId,
            email: email,
            context: { [api] id in try await api.orderContext(memoId: id) },
            quote: { [api] id, copies, speed in
                try await api.orderQuote(memoId: id, copies: copies, shippingSpeed: speed)
            },
            submit: { [api] id, request in
                // La version du SDK Stripe part avec la commande : c'est elle
                // qui fait revenir une clé éphémère, et donc les cartes du
                // compte dans la feuille.
                var request = request
                request.stripeApiVersion = StripeSDK.apiVersion
                return try await api.createPrintOrder(memoId: id, order: request)
            },
            // Le lien et le suivi WhatsApp de la confirmation n'étaient pas
            // branchés : la confirmation partageait un lien fabriqué par l'app,
            // qui ne menait nulle part.
            shareLink: { [api] memoId in try await api.bookShareLink(memoId: memoId) },
            setWhatsApp: { [api] orderId, phone in
                try await api.setOrderWhatsApp(orderId: orderId, phone: phone)
            },
            presentPayment: { [payments] ticket in await payments.present(ticket) },
            reloadOrder: { [api] orderId in try await api.printOrder(id: orderId) },
            resumePayment: { [api] orderId in
                try await api.resumePrintOrderPayment(orderId: orderId, stripeApiVersion: StripeSDK.apiVersion)
            },
            cancelOrder: { [api] orderId in try await api.cancelPrintOrder(orderId: orderId) }
        )
    }

    /// Ouvre la feuille « Moyens de paiement » de Stripe — les cartes du compte,
    /// à ajouter ou à retirer. Rend un message si elle n'a pas pu s'ouvrir.
    public func managePaymentMethods() async -> String? {
        await paymentMethods.present(
            key: { [api] in try await api.paymentMethodsKey(stripeApiVersion: StripeSDK.apiVersion) },
            setupIntent: { [api] in try await api.paymentMethodsSetupIntent() }
        )
    }

    /// Combien de fois relire la cagnotte après un paiement réussi.
    ///
    /// Une seconde entre deux lectures. Même raison que dans ``OrderModel`` :
    /// la feuille dit que Stripe a accepté, pas que le serveur l'a appris.
    private static let creditAttempts = 6

    /// Relit la cagnotte jusqu'à ce que le solde ait monté.
    ///
    /// **Le solde ne bouge pas au retour de la feuille** : il bouge quand le
    /// webhook écrit au registre, une seconde ou deux plus tard. Relire tout de
    /// suite rendrait le montant d'avant, et la recharge aurait l'air perdue.
    ///
    /// Au bout du budget, on rend la dernière lecture telle quelle : l'argent
    /// est encaissé de toute façon, et la prochaine ouverture de l'écran
    /// montrera le bon solde. Lever ici ferait afficher une erreur sur un
    /// paiement réussi, ce qui est la pire des deux issues.
    private static func creditedWallet(
        from read: () async throws -> Wallet,
        above previous: Decimal
    ) async throws -> Wallet {
        var latest = try await read()
        var attempts = 0

        while latest.balance <= previous, attempts < creditAttempts {
            try? await Task.sleep(for: .seconds(1))
            latest = try await read()
            attempts += 1
        }

        return latest
    }
}

extension EnvironmentValues {
    /// La feuille « Moyens de paiement » de Stripe, pour le profil — posée par
    /// `RootView`. `nil` en aperçu, où la ligne ne fait rien.
    @Entry public var managePaymentMethods: (@MainActor () async -> String?)?

    /// La cagnotte d'un voyage, pour le paywall — qui n'a pas accès aux
    /// dépendances non plus. C'est elle qui porte l'estimation du carnet
    /// (`GET /v1/wallet?tripId=…`, T127). `nil` en aperçu : la feuille
    /// « Estimation » garde alors les chiffres de la maquette.
    @Entry public var walletSource: (@MainActor (String?) async throws -> Wallet)?

    /// Le support de la session, pour un écran qui doit l'ouvrir **par-dessus
    /// lui** au lieu de le faire pousser par ``RootView``.
    ///
    /// Un seul écran est dans ce cas, et c'est le paywall (Hugo, 16/09/2026) :
    /// « Besoin d'aide ? » y refermait l'offre avant de pousser le support, et
    /// la flèche de retour ramenait donc au profil — l'écran qui avait présenté
    /// le paywall — au lieu de l'étape qu'on regardait. Le support se pose
    /// désormais **sur** le paywall, qui reste monté derrière avec sa page.
    ///
    /// Le modèle est celui de la session et non un neuf : les votes « cette
    /// réponse t'a-t-elle aidé » et le message en cours d'écriture ne doivent
    /// pas repartir de zéro parce qu'on est entré par une porte plutôt qu'une
    /// autre. `nil` en aperçu, où le paywall en fabrique un à la volée.
    @Entry public var supportModel: SupportModel?
}
