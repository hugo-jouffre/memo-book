import Foundation

public struct APIConfiguration: Sendable, Hashable {
    public var baseURL: URL
    /// Au-delà, l'upload d'un vocal long sur un réseau lent échouerait pour rien.
    public var timeout: TimeInterval

    public init(baseURL: URL, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    /// Back-end lancé en local (`npm run dev`), vu depuis le simulateur.
    public static let localDevelopment = APIConfiguration(
        baseURL: URL(string: "http://localhost:3000")!
    )
}
