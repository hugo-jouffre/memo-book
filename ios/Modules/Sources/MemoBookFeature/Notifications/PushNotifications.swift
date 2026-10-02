import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// Les notifications, côté téléphone : **l'autorisation**, **le jeton**, et
/// **le toucher**. Les règles — quoi envoyer, quand — sont au serveur
/// (`docs/notifications.md`) ; l'app ne programme aucune notification locale.
///
/// Un objet **de l'app entière**, et non d'un écran : c'est le délégué de
/// l'application qui reçoit le jeton et le toucher (``NotificationAppDelegate``),
/// parfois avant même que ``RootView`` existe — une notification touchée app
/// fermée ouvre l'app sur elle. Il garde donc ce qu'on lui confie jusqu'à ce
/// que quelqu'un puisse s'en servir :
///
/// - le jeton part au serveur dès qu'une session est branchée (``connect(api:)``) ;
/// - le lien touché attend dans ``pendingLink`` que l'accueil soit là pour
///   ouvrir l'écran qu'il désigne.
@MainActor
@Observable
public final class PushNotifications {
    public static let shared = PushNotifications()

    /// Ce qu'iOS a répondu à la demande d'autorisation. `notDetermined` tant
    /// qu'on ne l'a pas posée — la feuille « Notifications » s'en sert pour dire
    /// que tout est coupé dans les Réglages.
    public private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Le lien de la notification qu'on vient de toucher, en attendant que
    /// ``RootView`` l'ouvre. Remis à `nil` par celui qui l'a consommé.
    public var pendingLink: NotificationLink?

    /// Le dernier jeton qu'iOS a donné, en hexadécimal.
    private var deviceToken: String?

    /// L'API de la session ouverte, ou `nil` hors session — rien ne part alors.
    private var api: (any MemoBookAPI)?

    /// Le jeton déjà remis **à cette session**. Une nouvelle session le
    /// renvoie : le serveur l'a oublié avec la précédente.
    private var deliveredToken: String?

    /// Les notifications touchées avant qu'une session soit là pour le dire au
    /// serveur — app fermée, le toucher arrive avant la relecture de la
    /// session. Elles partent à ``connect(api:)``.
    private var unreportedOpenings: [String] = []

    private init() {}

    // MARK: - La session

    /// Une session s'ouvre : on la retient, et on demande à iOS le jeton si
    /// l'autorisation est déjà donnée — sans jamais poser la question ici.
    /// La question se pose au bon moment, à l'étape « Notifications » de la
    /// création d'un voyage (``requestAuthorization()``).
    public func connect(api: any MemoBookAPI) async {
        self.api = api
        deliveredToken = nil
        await refreshAuthorization()
        if authorization.allowsDelivery {
            UIApplication.shared.registerForRemoteNotifications()
        }
        let openings = unreportedOpenings
        unreportedOpenings.removeAll()
        for id in openings { reportOpening(id) }
        await deliverToken()
    }

    /// La session se ferme. Le serveur oublie le jeton avec elle ; l'app, elle,
    /// garde le jeton pour la personne suivante.
    public func disconnect() {
        api = nil
        deliveredToken = nil
        pendingLink = nil
    }

    // MARK: - L'autorisation

    /// Relit ce qu'iOS a retenu — la personne a pu tout couper dans les
    /// Réglages entre deux ouvertures.
    public func refreshAuthorization() async {
        authorization = await Self.systemAuthorization()
    }

    /// Lu hors de l'acteur principal : `UNNotificationSettings` ne traverse
    /// pas les acteurs, son statut — une énumération — si.
    private nonisolated static func systemAuthorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// **Pose la question**, si elle ne l'a jamais été, puis s'inscrit chez
    /// Apple. Sans effet quand la réponse est déjà connue : iOS ne repose
    /// jamais la question, et un refus se corrige dans les Réglages.
    ///
    /// Rend `true` quand les notifications peuvent arriver.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
        guard authorization.allowsDelivery else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    // MARK: - Ce que le délégué de l'application transmet

    /// iOS a donné un jeton — à chaque lancement, et chaque fois qu'il change.
    func didRegister(deviceToken data: Data) {
        deviceToken = PushTokenRegistration.hex(data)
        Task { await deliverToken() }
    }

    /// On a touché une notification : on retient où elle mène, et on dit au
    /// serveur qu'elle a été ouverte.
    func didOpen(link: String?, deliveryId: String?) {
        if let destination = NotificationLink(payloadLink: link) {
            pendingLink = destination
        }
        if let deliveryId {
            if api == nil {
                unreportedOpenings.append(deliveryId)
            } else {
                reportOpening(deliveryId)
            }
        }
    }

    private func reportOpening(_ deliveryId: String) {
        guard let api else { return }
        Task { try? await api.markNotificationOpened(id: deliveryId) }
    }

    // MARK: - Le jeton, au serveur

    private func deliverToken() async {
        guard let api, let deviceToken, deviceToken != deliveredToken else { return }

        let registration = PushTokenRegistration(
            token: deviceToken,
            environment: .current,
            timeZone: TimeZone.current.identifier,
            appVersion: Self.appVersion
        )
        do {
            try await api.registerPushToken(registration)
            deliveredToken = deviceToken
        } catch {
            // Rien à dire à l'écran : on réessaiera à la prochaine entrée dans
            // l'app. Une notification manquée vaut mieux qu'une alerte.
        }
    }

    private static var appVersion: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

extension UNAuthorizationStatus {
    /// iOS laissera passer ce qu'on enverra — « provisoire » compris : les
    /// notifications arrivent alors en silence dans le centre de notifications.
    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }
}

/// Le délégué de l'application, pour ce que SwiftUI ne sait pas recevoir : le
/// jeton APNs et le toucher d'une notification.
///
/// Déclaré par la cible app (`@UIApplicationDelegateAdaptor`), mais il vit ici :
/// tout ce qu'il fait passe par ``PushNotifications``.
public final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // **Avant la fin du lancement** : une notification touchée app fermée
        // n'est remise qu'au délégué déjà en place.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotifications.shared.didRegister(deviceToken: deviceToken)
    }

    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        // Le simulateur sans compte iCloud, un réseau coupé : rien à faire
        // d'autre que réessayer au prochain lancement.
    }

    /// Une notification qui arrive **pendant qu'on est dans l'app** s'affiche
    /// quand même : sans ça, iOS la tait, et la fin d'un voyage passerait
    /// inaperçue parce qu'on regardait son carnet.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = response.notification.request.content.userInfo
        let link = payload["link"] as? String
        let deliveryId = payload["deliveryId"] as? String
        await MainActor.run {
            PushNotifications.shared.didOpen(link: link, deliveryId: deliveryId)
        }
    }
}

extension EnvironmentValues {
    /// Les notifications de l'app, pour les écrans qui en parlent — la feuille
    /// « Notifications », l'étape du même nom à la création d'un voyage. `nil`
    /// dans un aperçu : rien n'y demande l'autorisation pour de vrai.
    @Entry var pushNotifications: PushNotifications?
}
