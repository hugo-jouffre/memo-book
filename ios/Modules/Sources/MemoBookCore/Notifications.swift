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
    /// `memobook://paywall` — la fin des 3 jours offerts : l'offre.
    case paywall
    /// `memobook://trips/new` — les vacances, l'anniversaire : créer un voyage.
    case newTrip
    /// `memobook://trips/<id>/chat` — un carnet qui se tait : la conversation.
    case chat(tripId: String)
    /// `memobook://trips/<id>/wallet` — la fin du voyage : la cagnotte, avec ce
    /// qui est déjà versé et l'estimation du carnet.
    case wallet(tripId: String)
    /// `memobook://trips/<id>/preview` — un carnet pas commandé : l'aperçu,
    /// qui porte « Commander ce carnet ». On ne commande pas un carnet qu'on
    /// n'a pas vu.
    case bookPreview(tripId: String)

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "memobook" else { return nil }

        // `memobook://trips/abc/chat` : « trips » est l'hôte, le reste le chemin.
        let segments = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }

        switch segments.count {
        case 1 where segments[0] == "paywall":
            self = .paywall
        case 2 where segments[0] == "trips" && segments[1] == "new":
            self = .newTrip
        case 3 where segments[0] == "trips":
            let tripId = segments[1]
            switch segments[2] {
            case "chat": self = .chat(tripId: tripId)
            case "wallet": self = .wallet(tripId: tripId)
            case "preview": self = .bookPreview(tripId: tripId)
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
