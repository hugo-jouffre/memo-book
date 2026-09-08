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

    /// La clé de l'Info.plist où la configuration de build dépose l'adresse de
    /// l'API. Elle vient de `Config/*.xcconfig` — voir `ios/project.yml`.
    static let baseURLInfoKey = "MemoBookAPIBaseURL"

    /// L'adresse posée par la configuration de build, si elle est lisible.
    ///
    /// Rien n'est deviné ici : une valeur absente ou mal formée rend `nil`, et
    /// c'est à l'appelant de décider ce que ça veut dire. Voir
    /// ``APIConfiguration/fromBuildConfiguration`` côté app.
    public static func fromBundle(_ bundle: Bundle = .main) -> APIConfiguration? {
        guard
            let raw = bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme != nil
        else { return nil }

        return APIConfiguration(baseURL: url)
    }
}
