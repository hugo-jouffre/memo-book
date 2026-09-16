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
        case .server(let statusCode, _, let message):
            // Un serveur déployé avant le 15/09/2026 répond encore « Erreur
            // interne du serveur. » : une phrase qui accuse sans dire à qui est
            // la panne. On la remplace par la sienne — le conseil, lui, vient de
            // ``recoveryAdvice``.
            statusCode >= 500 && message == "Erreur interne du serveur."
                ? "Notre serveur a rencontré un problème inattendu."
                : message
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

    /// L'appel n'a **pas quitté l'appareil** — ou n'est jamais revenu. C'est
    /// la seule erreur qui vaille un repli sur ce qu'on avait déjà : un 500 ou
    /// un 404 sont des réponses, et une réponse mérite qu'on la montre.
    public var isTransport: Bool {
        if case .transport = self { true } else { false }
    }

    /// La panne est **du côté du serveur** — un 5xx —, pas de l'appareil ni de
    /// la requête. C'est ce qui décide de proposer le support à côté de
    /// « Réessayer » : contre un bogue de notre côté, réessayer ne suffit pas.
    public var isServerSide: Bool {
        if case .server(let statusCode, _, _) = self { return statusCode >= 500 }
        return false
    }

    /// Ce qu'on peut **faire**, sous la phrase qui dit ce qui s'est passé.
    ///
    /// Une erreur qui ne propose rien laisse chercher ce qu'on a mal fait — et
    /// devant un 500, on n'a rien fait de mal. Chaque cas nomme donc à qui est
    /// la panne et le geste qui a une chance : réessayer, se reconnecter,
    /// revenir à l'accueil, nous écrire. `nil` pour un refus du serveur qui
    /// porte déjà son propre message (un 400, un 409). Hugo, 15/09/2026.
    public var recoveryAdvice: String? {
        switch self {
        case .server(let statusCode, _, _) where statusCode >= 500:
            "Le problème vient de notre côté, pas du tien. Réessaie dans un instant ; si ça continue, écris-nous depuis « Besoin d’aide ? » et on répare."
        case .server(404, _, _):
            "Ce voyage n’est plus sur ton compte, ou il a été supprimé : reviens à l’accueil pour le vérifier."
        // **Avant le cas générique des 403** : un 403 se traite d'ordinaire par
        // « reconnecte-toi », et ces deux-là n'ont rien à voir avec la session.
        // Les placer après ferait dire à l'app exactement le contraire de ce
        // qu'il faut faire.
        case .server(403, "memory_limit_reached", _):
            "Ouvre « Limites de souvenirs » dans les paramètres du voyage pour les étendre, ou attends le renouvellement du mois."
        case .server(403, "quota_exhausted", _):
            "Abonne-toi pour continuer à raconter : l’offre est dans ton profil, ou sur l’accueil."
        case .server(401, _, _), .server(403, _, _), .notAuthenticated:
            "Reconnecte-toi pour continuer."
        case .server:
            nil
        case .transport:
            "Vérifie ta connexion, puis réessaie."
        case .decoding:
            "Mets MemoBook à jour depuis l’App Store ; si ça continue, écris-nous depuis « Besoin d’aide ? »."
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

            #if targetEnvironment(simulator)
                let runsInSimulator = true
            #else
                let runsInSimulator = false
            #endif

            return switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                // Sur un iPhone, `localhost` est le téléphone : ce n'est pas le
                // back-end qui manque, c'est l'adresse qui est fausse — et
                // relancer `npm run dev` n'y changerait rien. Le build ne doit
                // plus pouvoir l'embarquer (`Debug.xcconfig`,
                // `APIConfiguration.effective`) ; si cette phrase s'affiche
                // quand même, c'est l'un des deux garde-fous qui a sauté.
                isLocal && !runsInSimulator
                    ? """
                    Ce build parle à \(target) depuis un iPhone — c'est-à-dire \
                    au téléphone lui-même.

                    Un appareil doit viser la production, ou l'IP du Mac \
                    dans Config/Secrets.xcconfig (avec la condition \
                    [sdk=iphoneos*]). Voir ios/Config/Debug.xcconfig.
                    """
                    : isLocal
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
