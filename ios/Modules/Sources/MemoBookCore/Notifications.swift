import Foundation

// Les notifications, côté app : où mène une notification qu'on touche, et ce
// que le téléphone dit de lui au serveur. Les règles — quoi envoyer, à qui,
// quel jour — vivent au serveur : `docs/notifications.md`.

/// Où mène une notification qu'on touche.
///
/// **Le contrat avec le serveur** : chaque notification porte un lien
/// `memobook://` (`NOTIFICATION_LINKS`, `backend/src/services/notificationPlanner.ts`),
/// et c'est ce type qui le lit. Les mêmes liens marchent depuis n'importe où —
/// un e-mail, une note, `xcrun simctl openurl` — puisque le schéma est celui
/// de l'app.
///
/// Un lien qu'on ne sait pas lire donne `nil` : l'app s'ouvre là où elle était,
/// au lieu d'aller vers un écran deviné.
public enum NotificationLink: Equatable, Sendable {
    /// `memobook://paywall` — l'offre. Le serveur ne l'envoie plus (la
    /// notification de fin de l'essai gratuit est partie avec lui, Hugo,
    /// 03/10/2026), mais des notifications déjà livrées et des e-mails le
    /// portent encore : il ouvre toujours le paywall.
    case paywall
    /// `memobook://subscription` — le rappel de résiliation à la fin du voyage
    /// (`renewal_reminder`) : la gestion de l'abonnement, là où on le coupe.
    case subscription
    /// `memobook://trips/new` — les vacances, l'anniversaire : créer un voyage.
    case newTrip
    /// `memobook://trips/<id>/chat` — un carnet qui se tait : la conversation.
    case chat(tripId: String)
    /// `memobook://trips/<id>/preview` — un carnet pas commandé, la fin du
    /// voyage : l'aperçu, qui porte « Commander ce carnet ». On ne commande pas
    /// un carnet qu'on n'a pas vu.
    ///
    /// `memobook://trips/<id>/wallet` y mène aussi. La fin du voyage ouvrait
    /// la cagnotte, partie avec elle (Hugo, 06/10/2026, T230) ; les
    /// notifications déjà livrées et les e-mails portent encore ce lien, et
    /// l'aperçu est ce qu'il avait de plus proche à montrer : le carnet qu'on
    /// finançait.
    case bookPreview(tripId: String)
    /// **L'invitation d'un co-voyageur** (Hugo, 18/10/2026) : rejoindre le
    /// voyage par son code, puis ouvrir son écran d'accueil. Trois formes :
    /// le lien universel `https://<l'API>/j/<code>` (``InviteLink``), et
    /// `memobook://join?code=<code>` ou `memobook://j/<code>`, ceux de la page
    /// de repli (`backend/src/routes/invitePage.ts`).
    case join(code: String)

    public init?(url: URL) {
        if let code = InviteLink.code(from: url) {
            self = .join(code: code)
            return
        }
        guard url.scheme?.lowercased() == "memobook" else { return nil }

        // `memobook://trips/abc/chat` : « trips » est l'hôte, le reste le chemin.
        let segments = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }

        switch segments.count {
        case 1 where segments[0] == "paywall":
            self = .paywall
        case 1 where segments[0] == "subscription":
            self = .subscription
        case 2 where segments[0] == "trips" && segments[1] == "new":
            self = .newTrip
        case 3 where segments[0] == "trips":
            let tripId = segments[1]
            switch segments[2] {
            case "chat": self = .chat(tripId: tripId)
            case "preview", "wallet": self = .bookPreview(tripId: tripId)
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Depuis la charge utile d'une notification — la clé `link`, à côté d'`aps`.
    public init?(payloadLink: String?) {
        guard let payloadLink, let url = URL(string: payloadLink) else { return nil }
        self.init(url: url)
    }
}

/// Le serveur APNs qui connaît un jeton.
///
/// **Un build Xcode reçoit un jeton du sandbox**, TestFlight et l'App Store un
/// jeton de production. Le serveur doit envoyer chacun au bon endroit, sinon
/// Apple répond `BadDeviceToken` — et seule l'app sait de quel build elle vient.
public enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    /// Celui de ce build : le sandbox en Debug, la production en Release —
    /// c'est la configuration d'une archive, donc de TestFlight.
    public static var current: PushEnvironment {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }
}

/// Ce que le téléphone dit de lui à `POST /v1/push-tokens`.
public struct PushTokenRegistration: Equatable, Sendable {
    /// Le jeton APNs, en hexadécimal.
    public var token: String
    public var environment: PushEnvironment
    /// Le fuseau du téléphone — `Europe/Paris`. C'est lui qui fait partir une
    /// notification à 10 h chez le voyageur, où qu'il soit.
    public var timeZone: String
    /// `0.1.0 (8)`, pour le support.
    public var appVersion: String?

    public init(token: String, environment: PushEnvironment, timeZone: String, appVersion: String?) {
        self.token = token
        self.environment = environment
        self.timeZone = timeZone
        self.appVersion = appVersion
    }

    /// Le jeton tel qu'iOS le donne — des octets — écrit comme APNs l'attend.
    public static func hex(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    /// Le corps de la requête.
    public var body: [String: String] {
        var body = ["token": token, "environment": environment.rawValue, "timeZone": timeZone]
        if let appVersion { body["appVersion"] = appVersion }
        return body
    }
}

/// **Le lien d'invitation d'un co-voyageur** (Hugo, 18/10/2026).
///
/// `https://<l'API de production>/j/<code>` : un lien universel. L'app
/// installée s'ouvre dessus et rejoint le voyage ; sinon, la page du serveur
/// envoie sur l'App Store (`backend/src/routes/invitePage.ts`). Toujours
/// l'adresse de **production** — c'est elle qui sert
/// `apple-app-site-association` et que déclare l'*Associated Domain* —, même
/// depuis un build de développement : un lien vers `localhost` ne mènerait
/// nulle part sur le téléphone de l'invité.
public enum InviteLink {
    /// Le chemin que l'app revendique sur ce domaine (`INVITE_PATH`).
    static let path = "j"

    /// Le lien à partager, ou `nil` si l'app ne connaît pas l'adresse de production.
    public static func url(code: String, base: URL? = productionBaseURL) -> URL? {
        guard let base, !code.isEmpty else { return nil }
        return base.appending(path: path).appending(path: code)
    }

    /// Le code d'un lien d'invitation, quelle que soit sa forme ; `nil` pour tout autre lien.
    public static func code(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()
        let segments = url.pathComponents.filter { $0 != "/" }
        let raw: String?
        switch scheme {
        case "https":
            raw = segments.count == 2 && segments[0] == path ? segments[1] : nil
        case "memobook":
            if url.host == "join" {
                raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "code" }?.value
            } else if url.host == path, segments.count == 1 {
                raw = segments[0]
            } else {
                raw = nil
            }
        default:
            raw = nil
        }
        // La forme de la base : majuscules, sans espace ni tiret (`normalizeAccessCode`).
        let code = (raw ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
        return code.isEmpty ? nil : code
    }

    /// L'adresse de production que l'app embarque (`MemoBookProductionAPIBaseURL`, `Base.xcconfig`).
    public static var productionBaseURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "MemoBookProductionAPIBaseURL") as? String)
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
