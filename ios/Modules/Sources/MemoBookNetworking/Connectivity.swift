import Foundation
import Network

/// L'état du réseau, tel que l'app peut le lire.
///
/// C'est une **valeur**, pas un service : une fonction qui rend un flux de
/// « en ligne / hors ligne ». Un test ou un aperçu en fabrique une qui dit ce
/// qu'il veut, sans protocole ni double à écrire — c'est la même forme que les
/// fonctions-sources des modèles d'écran.
///
/// Elle vit dans `MemoBookNetworking` et non dans `Feature` parce qu'elle parle
/// du réseau, comme le client d'API — et parce que c'est le seul module qui a
/// déjà le droit d'importer `Network`.
///
/// ⚠️ **« En ligne » ne veut pas dire « l'API répond ».** `NWPathMonitor` dit
/// qu'une interface est montée et routable, rien de plus : un wifi de hall
/// d'hôtel avec un portail captif se déclare satisfait. C'est pourquoi la file
/// d'attente des vocaux ne se fie pas qu'à ce drapeau — un envoi qui échoue au
/// transport y retourne, même « en ligne ». Voir `RecordingOutbox`.
public struct Connectivity: Sendable {
    /// Rend l'état courant **tout de suite**, puis à chaque changement. Le
    /// premier élément n'attend donc pas la première coupure : un écran qui
    /// s'ouvre hors ligne le sait avant de dessiner quoi que ce soit.
    public let updates: @Sendable () -> AsyncStream<Bool>

    public init(updates: @escaping @Sendable () -> AsyncStream<Bool>) {
        self.updates = updates
    }

    /// Le vrai réseau de l'appareil.
    ///
    /// Un moniteur par flux, refermé avec lui (`onTermination`) : rien ne
    /// survit à l'écran qui l'écoutait. La file d'attente en ouvre un seul,
    /// pour toute la durée de l'app.
    public static let system = Connectivity {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()

            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }

            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.memobook.connectivity", qos: .utility))
        }
    }

    /// Toujours en ligne, et rien à suivre : les aperçus SwiftUI et les tests
    /// qui ne parlent pas du réseau.
    public static let online = Connectivity {
        AsyncStream { continuation in
            continuation.yield(true)
            continuation.finish()
        }
    }
}
