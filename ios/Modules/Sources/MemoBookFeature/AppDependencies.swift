import Foundation
import MemoBookCore
import MemoBookNetworking
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
        pendingRecordings: PendingRecordingStore = .inLibrary()
    ) {
        self.api = api
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

    /// Les réglages d'un voyage.
    ///
    /// ⚠️ **Sur le jeu d'essai**, comme le chat : `GET /v1/trips/:id/settings`
    /// et son `PATCH` n'existent pas encore côté serveur. Le jour où ils
    /// existent, cette fabrique devient :
    ///
    /// ```swift
    /// TripSettingsModel(
    ///     tripId: tripId,
    ///     source: { [api] id in try await api.tripSettings(id: id) },
    ///     persist: { [api] id, edit in try await api.updateTripSettings(id: id, edit: edit) }
    /// )
    /// ```
    ///
    /// Rien d'autre ne bouge : ni la vue, ni le modèle, ni les aperçus. Voir la
    /// fiche des paramètres du voyage dans `docs/ui-development.md`.
    public func tripSettingsModel(tripId: String) -> TripSettingsModel {
        TripSettingsModel(tripId: tripId)
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

    /// Ma cagnotte.
    ///
    /// ⚠️ **Sur le jeu d'essai** : `GET /v1/wallet` reste à écrire. Le solde,
    /// lui, arrive déjà dans `GET /v1/profile` (`walletBalance`) — c'est
    /// l'**historique** qui manque, et c'est tout l'écran.
    ///
    /// `topUp` reste `nil` tant que Stripe n'est pas branché : l'écran le lit
    /// pour dire pourquoi « Ajouter » n'aboutit pas, au lieu d'ouvrir un écran
    /// qui n'existe pas.
    public func walletModel(tripId: String?) -> WalletModel {
        WalletModel(tripId: tripId)
    }
}
