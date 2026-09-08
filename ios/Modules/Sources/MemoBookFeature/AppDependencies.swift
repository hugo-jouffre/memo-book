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
    // C'est ce que `RootView` passe aux trois écrans : l'app tourne donc sur
    // les données du serveur, et les aperçus SwiftUI sur le jeu d'essai, sans
    // qu'aucune vue ni aucun modèle ait à savoir lequel des deux le sert.

    /// L'accueil, servi par `GET /v1/home`. Exige une session ouverte.
    public func homeModel() -> HomeModel {
        HomeModel { [api] in try await api.homeFeed() }
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
}
