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
    ///   - payments: qui ouvre la feuille de paiement. La vraie par défaut ;
    ///     une preview Xcode — et le lancement `-previewSignedIn` — passe
    ///     ``StubPaymentPresenter``, qui n'appelle personne.
    public init(
        api: any MemoBookAPI,
        connectivity: Connectivity = .system,
        pendingRecordings: PendingRecordingStore = .inLibrary(),
        payments: (any PaymentPresenter)? = nil,
    ) {
        self.api = api
        // La vraie feuille Stripe par défaut ; un aperçu passe la sienne.
        // `applePayMerchantId` reste nul tant que le certificat Apple Pay n'est
        // pas posé : la feuille montre alors les cartes seules, au lieu d'un
        // bouton Apple Pay qui échouerait au moment de payer.
        self.payments = payments ?? StripePaymentSheetPresenter()
        outbox = RecordingOutbox(store: pendingRecordings, connectivity: connectivity) { audio, tripId in
            _ = try await api.uploadAudio(
                memoId: tripId,
                data: audio.data,
                filename: audio.filename,
                mimeType: audio.mimeType,
                capturedAt: audio.recordedAt,
                // La durée part avec le fichier : c'est elle qui décompte les
                // limites de souvenirs. Elle voyage déjà dans la file hors
                // ligne (`PendingRecording.duration`), donc un vocal parti
                // trois jours plus tard décompte la même chose.
                durationSeconds: audio.duration,
                placeLabel: nil
            )
        }

        // Au démarrage, et pas à l'ouverture d'un écran : c'est ce qui permet
        // de savoir qu'on est hors ligne **avant** de dessiner l'accueil, et de
        // repartir avec ce qu'un lancement précédent avait laissé en file.
        outbox.start()
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
    public func homeModel() -> HomeModel {
        HomeModel(
            source: cachedSource(.home) { [api] in try await api.homeFeed() },
            cached: { [content] in await content.read(.home, as: HomeFeed.self) },
            outbox: outbox,
            remove: { [api] id in try await api.deleteMemo(id: id) }
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
    public func tripModel(id: String) -> TripHomeModel {
        // La source est construite **ici**, une fois, parce que le voyage est
        // fixé à la construction du modèle : c'est ce qui permet au cache
        // d'avoir sa case (`.trip(id)`) sans que le modèle sache qu'il existe.
        let read = cachedSource(.trip(id)) { [api] in try await api.tripDetail(id: id) }

        return TripHomeModel(
            tripId: id,
            source: { _ in try await read() },
            cached: { [content] in await content.read(.trip(id), as: TripDetail.self) }
        )
    }

    /// La conversation avec MEMO.
    ///
    /// **Le seul modèle de l'app qui reçoive deux sources** : celle qui rend le
    /// fil, et celle qui répond à la place de MEMO. Les deux sont encore
    /// locales, et pour deux raisons différentes — il n'existe ni route de chat
    /// (`GET /v1/trips/:id/chat`) ni agent de conversation côté serveur, alors
    /// que `agents/agent-conversation.md` en écrit déjà le contrat.
    ///
    /// Le jour où les deux existent, cette fabrique devient :
    ///
    /// ```swift
    /// ChatModel(
    ///     source: { [api] in try await api.chatThread(tripId: tripId, stepId: stepId) },
    ///     responder: RemoteMemoResponder(api: api)
    /// )
    /// ```
    ///
    /// Rien d'autre ne bouge : ni la vue, ni le modèle, ni les aperçus. Voir la
    /// fiche du chat dans `docs/ui-development.md` pour le contrat des deux
    /// routes.
    public func chatModel(tripId: String, stepId: String? = nil) -> ChatModel {
        ChatModel(tripId: tripId, focusStepId: stepId, archive: conversations)
    }

    /// Les conversations supprimées, **retenues sur l'appareil** en attendant
    /// `DELETE /v1/trips/:id/chat` — voir ``ConversationArchive``. Les réglages
    /// d'un voyage y écrivent, la conversation y lit.
    public let conversations = ConversationArchive(defaults: .standard)

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
    public func tripCreationModel() -> TripCreationModel {
        TripCreationModel(
            create: { [api] draft in try await api.createTrip(draft) },
            update: { [api] id, draft in try await api.updateTrip(id: id, draft: draft) },
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
            // Supprimer la conversation ne va **pas** au serveur : il n'y a
            // pas de conversation chez lui à supprimer. L'archive la retient
            // sur l'appareil, et le fil s'ouvre vide ensuite.
            clearConversation: { [conversations] id in conversations.clear(tripId: id) },
            restoreConversation: { [conversations] id in conversations.restore(tripId: id) },
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
            }
        )
    }

    /// Les deux plats du carnet.
    ///
    /// ⚠️ **Sur le jeu d'essai**, et plus complètement que les autres écrans du
    /// carnet : `GET` et `PATCH /v1/trips/:id/covers` n'existent ni l'un ni
    /// l'autre, et la base n'a aujourd'hui qu'un booléen sur le sujet
    /// (`memos.hasConfiguredCovers`). Il manque le style, la photo retenue, les
    /// deux textes et les chiffres choisis — cinq colonnes, une route, un
    /// sérialiseur. Tant qu'ils ne sont pas là, choisir une couverture ne
    /// survit pas à la fermeture de l'écran, et c'est écrit dans la fiche.
    public func coversModel(tripId: String) -> CoversModel {
        CoversModel(tripId: tripId)
    }

    /// L'aperçu du carnet.
    ///
    /// ⚠️ **Sur le jeu d'essai** : `GET /v1/memos/:id/preview` et
    /// `POST /v1/memos/:id/share-link` restent à écrire. Les routes de rendu
    /// (`POST /v1/memos/:id/renders`, `GET /v1/renders/:id`) existent, elles,
    /// mais rendent un ``Render`` et non un ``BookPreview`` — il manque le
    /// titre du carnet, l'extrait et l'état des couvertures, que l'écran
    /// affiche tous les trois.
    public func bookPreviewModel(memoId: String) -> BookPreviewModel {
        BookPreviewModel(memoId: memoId)
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
                let ticket = try await api.startWalletTopUp(amountCents: cents)

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
            }()
        )
    }

    /// Le tunnel de commande, **entièrement servi par le serveur** — c'est ce
    /// qui le distingue des quatre écrans ci-dessus.
    ///
    /// Voir aussi ``SwiftUI/EnvironmentValues/profileModelFactory`` : le paywall
    /// a besoin du profil pour sa feuille de paiement, et il se présente depuis
    /// des écrans qui ne tiennent pas de dépendances.
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
                try await api.createPrintOrder(memoId: id, order: request)
            },
            presentPayment: { [payments] ticket in await payments.present(ticket) },
            reloadOrder: { [api] orderId in try await api.printOrder(id: orderId) }
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
    /// Fabrique le modèle du profil, pour un écran qui n'a pas d'accès aux
    /// dépendances et en a pourtant besoin d'un.
    ///
    /// Le paywall est présenté par l'accueil, par un voyage et par le profil ;
    /// sa feuille « Choisis ton mode de paiement » lit et écrit les cartes du
    /// compte, ce que seul ``ProfileModel`` sait faire. Plutôt que de faire
    /// remonter `AppDependencies` dans trois écrans, `RootView` pose ici la
    /// fabrique branchée sur l'API ; un aperçu n'en pose aucune et le paywall
    /// retombe sur le jeu d'essai.
    @Entry public var profileModelFactory: (@MainActor () -> ProfileModel)?

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
