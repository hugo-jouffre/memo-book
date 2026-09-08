import Foundation

/// Erreur remontée par le client d'API.
///
/// Les messages sont destinés à l'utilisateur : le back-end renvoie déjà des
/// libellés en français dans son champ `message`, on les réutilise plutôt que
/// d'afficher un code HTTP.
public enum APIError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case server(statusCode: Int, code: String?, message: String)
    /// L'appel n'a pas abouti du tout. L'URL visée est gardée avec l'erreur :
    /// elle ne sert à rien à l'utilisateur, mais elle est **l'essentiel du
    /// diagnostic** en développement — voir ``developerDiagnosis(_:url:)``.
    case transport(any Error, url: URL?)
    case decoding(any Error)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Cet appareil n'est pas encore enregistré."
        case .server(_, _, let message):
            message
        case .transport(let error, let url):
            #if DEBUG
                Self.developerDiagnosis(error, url: url)
            #else
                "Connexion impossible. Vérifie ton réseau et réessaie."
            #endif
        case .decoding(let error):
            #if DEBUG
                """
                Réponse inattendue du serveur.

                \(error)

                Le modèle Swift et `appSerializers.ts` ne disent plus la même \
                chose. Compare le champ nommé ci-dessus avec ce que rend la \
                route.
                """
            #else
                "Réponse inattendue du serveur."
            #endif
        }
    }

    /// `true` quand réessayer a une chance d'aboutir.
    public var isRetryable: Bool {
        switch self {
        case .transport: true
        case .server(let statusCode, _, _): statusCode >= 500
        case .notAuthenticated, .decoding: false
        }
    }

    #if DEBUG

        /// Ce qui a vraiment échoué, et quoi faire — **build de développement
        /// seulement**.
        ///
        /// « Connexion impossible. Vérifie ton réseau et réessaie. » est la
        /// bonne phrase pour quelqu'un qui a l'app installée : il ne peut rien
        /// faire d'autre que regarder son wifi. Sur un build branché sur
        /// `localhost`, c'est **la pire phrase possible** — elle envoie
        /// chercher du côté du réseau un serveur qui n'est simplement pas
        /// lancé. On a déjà perdu deux fois une demi-heure là-dessus.
        ///
        /// On nomme donc la panne, et on donne la commande qui la répare.
        static func developerDiagnosis(_ error: any Error, url: URL?) -> String {
            let target = url.map { "\($0.host() ?? "?"):\($0.port ?? 80)" } ?? "le serveur"
            let isLocal = ["localhost", "127.0.0.1"].contains(url?.host())

            guard let urlError = error as? URLError else {
                return "L'appel vers \(target) a échoué.\n\n\(error)"
            }

            return switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                isLocal
                    ? """
                    Rien n'écoute sur \(target).

                    Le back-end n'est pas lancé :
                        cd backend && npm run dev

                    Pour vérifier, dans un autre terminal :
                        curl -s -o /dev/null -w "%{http_code}\\n" \
                          localhost:3000/v1/showcases/welcome
                    """
                    : "Impossible de joindre \(target)."

            case .networkConnectionLost:
                """
                La connexion vers \(target) s'est coupée en cours de route.

                Le serveur est mort **pendant** la requête. Regarde la fin de \
                sa sortie : c'est là qu'est la vraie erreur.
                """

            case .timedOut:
                """
                \(target) n'a pas répondu à temps.

                Le serveur tourne mais bloque — souvent la base : vérifie que \
                `DATABASE_URL` répond.
                """

            case .notConnectedToInternet:
                "Pas de réseau. Là, c'est vraiment le wifi."

            case .appTransportSecurityRequiresSecureConnection:
                """
                ATS a bloqué l'appel en clair vers \(target).

                `NSAllowsLocalNetworking` doit couvrir cet hôte — voir \
                `project.yml`.
                """

            default:
                "L'appel vers \(target) a échoué : \(urlError.localizedDescription)"
            }
        }

    #endif
}

/// Corps d'erreur normalisé du back-end.
struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}
