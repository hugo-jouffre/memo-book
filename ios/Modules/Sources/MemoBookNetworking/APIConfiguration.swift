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

    /// Les deux clés de l'Info.plist où la configuration de build dépose une
    /// adresse. Elles viennent de `Config/*.xcconfig` — voir `ios/project.yml`.
    public enum InfoKey: String, Sendable {
        /// L'adresse de **ce** build : le back-end local dans le simulateur, la
        /// production ailleurs.
        case baseURL = "MemoBookAPIBaseURL"
        /// La production, toujours — le filet de ``effective(configured:productionFallback:runsInSimulator:)``.
        case productionBaseURL = "MemoBookProductionAPIBaseURL"
    }

    /// L'adresse posée par la configuration de build, si elle est lisible.
    ///
    /// Rien n'est deviné ici : une valeur absente ou mal formée rend `nil`, et
    /// c'est à l'appelant de décider ce que ça veut dire. Voir
    /// ``APIConfiguration/fromBuildConfiguration`` côté app.
    public static func fromBundle(
        _ bundle: Bundle = .main,
        key: InfoKey = .baseURL
    ) -> APIConfiguration? {
        guard
            let raw = bundle.object(forInfoDictionaryKey: key.rawValue) as? String,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme != nil
        else { return nil }

        return APIConfiguration(baseURL: url)
    }

    /// L'adresse désigne **l'appareil lui-même** : `localhost`, `127.0.0.1`,
    /// `::1`, `0.0.0.0`. Juste dans le simulateur, où l'appareil est le Mac qui
    /// fait tourner le back-end ; absurde sur un iPhone, qui n'héberge rien.
    public var isLoopback: Bool {
        guard let host = baseURL.host()?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(host)
            || host.hasSuffix(".localhost")
    }

    /// L'adresse à retenir **pour cet appareil**.
    ///
    /// La configurée, sauf si elle est une boucle locale hors du simulateur :
    /// un téléphone ne parle jamais à `localhost`, c'est lui-même. On retombe
    /// alors sur la production, quand le build l'embarque — et c'est le filet
    /// derrière la ceinture de `Debug.xcconfig`, qui ne donne déjà plus
    /// `localhost` qu'au simulateur. Deux garde-fous pour une panne qui est
    /// revenue deux fois : un build Debug posé par ⌘R sur un iPhone répondait
    /// « Rien n'écoute sur localhost:3000 » (Hugo, 15/09/2026).
    ///
    /// Une fonction pure, testée sans appareil : ce qu'elle décide ne dépend
    /// que de ses trois arguments.
    public static func effective(
        configured: APIConfiguration?,
        productionFallback: APIConfiguration?,
        runsInSimulator: Bool
    ) -> APIConfiguration? {
        guard let configured else { return productionFallback }
        if configured.isLoopback, !runsInSimulator {
            return productionFallback ?? configured
        }
        return configured
    }
}
