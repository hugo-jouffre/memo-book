import Foundation
import MemoBookCore
import MemoBookNetworking
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

    /// Enregistrement en cours ou terminé. Le garder permet à plusieurs écrans
    /// qui démarrent en même temps d'attendre le même appel plutôt que d'en
    /// lancer un chacun.
    private var registration: Task<Void, any Error>?

    public init(api: any MemoBookAPI) {
        self.api = api
    }

    public convenience init(configuration: APIConfiguration = .localDevelopment) {
        self.init(api: MemoBookAPIClient(configuration: configuration))
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
    // Passer l'app en données réelles, c'est donc remplacer dans `RootView` :
    //
    //     HomeView(onIntent: handle)
    //     ProfileView(onSignOut: signOut)
    //     TripHomeView(tripId: id)
    //
    // par :
    //
    //     HomeView(model: dependencies.homeModel(), onIntent: handle)
    //     ProfileView(model: dependencies.profileModel(), onSignOut: signOut)
    //     TripHomeView(tripId: id, model: dependencies.tripModel(id: id))
    //
    // Rien d'autre ne bouge : ni les vues, ni les modèles, ni les aperçus.

    /// L'accueil, servi par `GET /v1/home`. Exige une session ouverte.
    public func homeModel() -> HomeModel {
        HomeModel { [api] in try await api.homeFeed() }
    }

    /// Le profil, servi par `GET /v1/profile`.
    public func profileModel() -> ProfileModel {
        ProfileModel { [api] in try await api.profile() }
    }

    /// Un voyage ouvert, servi par `GET /v1/trips/:id`.
    public func tripModel(id: String) -> TripHomeModel {
        TripHomeModel(tripId: id) { [api] identifier in
            try await api.tripDetail(id: identifier)
        }
    }
}
