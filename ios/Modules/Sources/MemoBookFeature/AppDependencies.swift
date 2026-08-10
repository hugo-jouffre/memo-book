import Foundation
import MemoBookNetworking
import Observation

/// Les dépendances que les écrans partagent. Un seul point d'assemblage :
/// l'app en construit une instance réelle, les aperçus SwiftUI une simulée.
@MainActor
@Observable
public final class AppDependencies {
    public let api: any MemoBookAPI

    /// `nil` tant que l'appareil n'est pas enregistré ; porte l'erreur si
    /// l'enregistrement a échoué au lancement.
    public private(set) var startupError: String?
    public private(set) var isReady = false

    public init(api: any MemoBookAPI) {
        self.api = api
    }

    public convenience init(configuration: APIConfiguration = .localDevelopment) {
        self.init(api: MemoBookAPIClient(configuration: configuration))
    }

    /// Enregistre l'appareil au premier lancement. Idempotent : rappelable
    /// après une panne réseau sans créer de doublon.
    public func prepare() async {
        do {
            try await api.ensureDeviceRegistered()
            startupError = nil
            isReady = true
        } catch {
            startupError = error.localizedDescription
            isReady = false
        }
    }
}
