import Foundation

/// Où l'écran des personnalisations garde la valeur des pointillés d'avant le
/// verrou, voyage par voyage — celle que ``BookRulesLock`` rend au retour vers
/// l'assortiment par défaut.
///
/// **Sur l'appareil** (Hugo, 02/10/2026) : elle survit à la fermeture de
/// l'écran et de l'app, sans colonne ni route de plus. Ce qu'elle ne couvre pas,
/// et c'est accepté : un autre téléphone, ou un co-voyageur, ne la connaît pas,
/// et le retour au défaut y rallume les pointillés.
///
/// Deux fonctions et non un `UserDefaults` : le modèle reçoit ses dépendances,
/// et un test ou un aperçu lui en donne une qui ne touche pas au disque.
@MainActor
public struct BookRulesMemory {
    public var read: (_ tripId: String) -> Bool?
    /// `nil` efface : le verrou s'est défait, il n'y a plus rien à rendre.
    public var write: (_ tripId: String, _ value: Bool?) -> Void

    public init(
        read: @escaping (_ tripId: String) -> Bool?,
        write: @escaping (_ tripId: String, _ value: Bool?) -> Void
    ) {
        self.read = read
        self.write = write
    }

    /// Celle de l'app : une clé par voyage dans `UserDefaults`.
    public static func device(_ defaults: UserDefaults = .standard) -> BookRulesMemory {
        BookRulesMemory(
            read: { defaults.object(forKey: key($0)) as? Bool },
            write: { tripId, value in
                if let value {
                    defaults.set(value, forKey: key(tripId))
                } else {
                    defaults.removeObject(forKey: key(tripId))
                }
            }
        )
    }

    /// Une mémoire qui ne vit que le temps de l'objet : celle des aperçus et
    /// des tests.
    public static func inMemory() -> BookRulesMemory {
        let box = Box()
        return BookRulesMemory(read: { box.values[$0] }, write: { box.values[$0] = $1 })
    }

    private static func key(_ tripId: String) -> String { "bookRulesBeforeLock.\(tripId)" }

    private final class Box {
        var values: [String: Bool] = [:]
    }
}
