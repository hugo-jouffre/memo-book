import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookPayments
import MemoBookRecording
import Observation

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

    /// Le dernier accueil reçu, pour pouvoir le relire hors ligne.
    private let homeFeed = HomeFeedCache()

    /// Enregistrement en cours ou terminé. Le garder permet à plusieurs écrans
    /// qui démarrent en même temps d'attendre le même appel plutôt que d'en
    /// lancer un chacun.
    private var registration: Task<Void, any Error>?

    /// - Parameters:
    ///   - connectivity: d'où l'app apprend qu'elle a du réseau. Le vrai
    ///     moniteur par défaut ; un test en fournit un qu'il pilote.
    ///   - pendingRecordings: où dorment les vocaux qui n'ont pas pu partir.
    public init(
        api: any MemoBookAPI,
        connectivity: Connectivity = .system,
        pendingRecordings: PendingRecordingStore = .inLibrary(),
        payments: (any PaymentPresenter)? = nil
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
        await homeFeed.clear()
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
            source: { [api, homeFeed] in
                do {
                    let feed = try await api.homeFeed()
                    await homeFeed.write(feed)
                    return feed
                } catch {
                    // **On ne se replie que sur une panne de transport.** Un 500
                    // ou un 404 sont des réponses : les cacher derrière un
                    // contenu périmé, c'est masquer une panne du serveur.
                    guard (error as? APIError)?.isTransport == true,
                        let cached = await homeFeed.read()
                    else { throw error }

                    return cached
                }
            },
            outbox: outbox
        )
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
            source: { [api] in try await api.profile() },
            persist: { [api] edit in try await api.updateProfile(edit) },
            // La troisième, et la seule sans retour : elle supprime le compte
            // et tout ce qui est à lui. L'écran demande confirmation avant.
            remove: { [api] in try await api.deleteAccount() }
        )
    }

    /// Un voyage ouvert, servi par `GET /v1/trips/:id`.
    public func tripModel(id: String) -> TripHomeModel {
        TripHomeModel(tripId: id) { [api] identifier in
            try await api.tripDetail(id: identifier)
        }
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
        ChatModel(tripId: tripId, focusStepId: stepId)
    }

    /// La galerie des carnets de la communauté, servie par `GET /v1/gallery`.
    public func galleryModel() -> GalleryModel {
        GalleryModel { [api] in try await api.gallery() }
    }

    /// Les six étapes de « Créer un voyage ». Deux routes et non une : la
    /// seconde sert la flèche de retour, qui ne doit pas créer un second
    /// voyage — voir ``TripCreationModel``.
    public func tripCreationModel() -> TripCreationModel {
        TripCreationModel(
            create: { [api] draft in try await api.createTrip(draft) },
            update: { [api] id, draft in try await api.updateTrip(id: id, draft: draft) }
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
        TripSettingsModel(
            tripId: tripId,
            source: { [api] id in try await api.tripSettings(id: id) },
            persist: { [api] id, edit in try await api.updateTripSettings(id: id, edit: edit) },
            removeCompanion: { [api] id, companionId in
                try await api.removeCompanion(tripId: id, companionId: companionId)
            },
            resendInvitation: { [api] id, companionId in
                try await api.resendInvitation(tripId: id, companionId: companionId)
            }
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
    /// **`topUp` ne rend pas la cagnotte que le paiement vient de créditer**,
    /// et c'est la subtilité de tout l'écran : le solde ne bouge pas quand la
    /// feuille se ferme, il bouge quand Stripe prévient le serveur. Entre les
    /// deux il y a quelques centaines de millisecondes, parfois deux secondes.
    /// Relire tout de suite afficherait l'ancien solde et donnerait à croire
    /// que le paiement n'a rien fait — d'où l'attente ci-dessous.
    public func walletModel(tripId: String?) -> WalletModel {
        WalletModel(
            tripId: tripId,
            source: { [api] trip in try await api.wallet(tripId: trip) },
            topUp: { [api, payments] trip, euros in
                let before = try await api.wallet(tripId: trip)

                // Les euros de l'écran deviennent les centimes du serveur.
                // `NSDecimalNumber` et pas `Double` : 20,10 € n'a pas
                // d'écriture binaire exacte, et un centime perdu sur un
                // paiement est un centime que personne ne retrouve.
                let cents = NSDecimalNumber(decimal: euros * 100).intValue
                let ticket = try await api.startWalletTopUp(amountCents: cents)

                switch await payments.present(ticket) {
                case .cancelled:
                    // Fermer la feuille n'est pas une erreur : on rend la
                    // cagnotte telle qu'elle était, sans message.
                    return before
                case .failed(let message):
                    throw WalletTopUpError.refused(message)
                case .succeeded:
                    return try await Self.walletOnceCredited(
                        api: api,
                        tripId: trip,
                        previousBalance: before.balance
                    )
                }
            }
        )
    }

    /// Attend que le webhook ait crédité, puis rend la cagnotte à jour.
    ///
    /// **Une attente bornée, et un repli qui ne ment pas** : au bout du délai on
    /// rend quand même ce que le serveur dit. Un solde en retard d'une seconde
    /// se corrige au prochain affichage ; une erreur affichée sur un paiement
    /// qui a réussi, elle, inquiète pour rien.
    private static func walletOnceCredited(
        api: any MemoBookAPI,
        tripId: String?,
        previousBalance: Decimal
    ) async throws -> Wallet {
        var latest = try await api.wallet(tripId: tripId)

        for _ in 0..<10 where latest.balance == previousBalance {
            try? await Task.sleep(for: .milliseconds(500))
            latest = try await api.wallet(tripId: tripId)
        }

        return latest
    }
}

/// Ce qui peut rater pendant une recharge, du point de vue de l'écran.
///
/// Distinct d'`APIError` : un paiement refusé n'est pas une panne de réseau, et
/// le message vient de Stripe — il est déjà écrit pour être lu.
enum WalletTopUpError: LocalizedError {
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .refused(let message): message
        }
    }
}
