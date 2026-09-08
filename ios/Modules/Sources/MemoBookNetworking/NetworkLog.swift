#if DEBUG

    import Foundation
    import os

    /// La trace des appels réseau, **en développement seulement**.
    ///
    /// Elle existe parce qu'une app qui échoue silencieusement coûte plus cher
    /// qu'elle ne le laisse croire : sans trace, un serveur local arrêté et un
    /// bug d'écran se ressemblent exactement — un écran vide et une phrase sur
    /// le réseau. Une ligne par requête suffit à trancher en une seconde.
    ///
    /// `os.Logger` et non `print` : les lignes partent dans le journal unifié,
    /// visibles à la fois dans la console Xcode **et** hors Xcode, avec
    ///
    /// ```bash
    /// xcrun simctl spawn booted log stream \
    ///   --predicate 'subsystem == "com.memobook.app"' --style compact
    /// ```
    ///
    /// Tout est interpolé en `.public` : le journal unifié masque par défaut
    /// les valeurs dynamiques (`<private>`), ce qui rendrait la trace inutile.
    /// C'est sans risque ici — on n'y écrit qu'une méthode, un chemin et un
    /// code de statut, jamais un corps de requête ni un jeton.
    enum NetworkLog {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.memobook.app",
            category: "réseau"
        )

        static func start(_ request: URLRequest) -> ContinuousClock.Instant {
            logger.debug("→ \(label(request), privacy: .public)")
            return .now
        }

        static func finish(
            _ request: URLRequest,
            statusCode: Int,
            since start: ContinuousClock.Instant
        ) {
            let line = "\(statusCode) \(label(request)) \(duration(since: start))"

            // Un 4xx/5xx n'est pas un incident de l'app, mais c'est presque
            // toujours ce qu'on cherche : il monte donc d'un niveau pour
            // ressortir dans une console bavarde.
            if (200..<400).contains(statusCode) {
                logger.debug("← \(line, privacy: .public)")
            } else {
                logger.error("← \(line, privacy: .public)")
            }
        }

        static func fail(
            _ request: URLRequest,
            error: any Error,
            since start: ContinuousClock.Instant
        ) {
            let cause = (error as? URLError)?.shortDescription ?? error.localizedDescription
            logger.error(
                """
                ✗ \(label(request), privacy: .public) \
                \(duration(since: start), privacy: .public) — \
                \(cause, privacy: .public)
                """
            )
        }

        private static func label(_ request: URLRequest) -> String {
            let method = request.httpMethod ?? "?"
            let path = request.url?.path ?? request.url?.absoluteString ?? "?"
            return "\(method) \(path)"
        }

        private static func duration(since start: ContinuousClock.Instant) -> String {
            let milliseconds = (ContinuousClock.now - start) / .milliseconds(1)
            return "(\(Int(milliseconds.rounded())) ms)"
        }
    }

    extension URLError {
        /// Le code d'URLError en clair. `localizedDescription` dit « Une erreur
        /// s'est produite » là où le code, lui, nomme la panne.
        var shortDescription: String {
            switch code {
            case .cannotConnectToHost: "connexion refusée (rien n'écoute)"
            case .cannotFindHost: "hôte introuvable"
            case .timedOut: "délai dépassé"
            case .networkConnectionLost: "connexion perdue en cours de route"
            case .notConnectedToInternet: "pas de réseau"
            case .appTransportSecurityRequiresSecureConnection: "bloqué par ATS (http en clair)"
            default: "\(localizedDescription) [URLError \(code.rawValue)]"
            }
        }
    }

#endif
