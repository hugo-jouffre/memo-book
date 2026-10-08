import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit
import UserNotifications

/// **La bulle « Suggestions » qui propose d'activer les notifications**
/// (T246, Hugo, 06/10/2026 : « oui on garde pour les utilisateurs qui ont
/// passé l'étape »).
///
/// L'autorisation se demande à l'étape « Notifications » de la création d'un
/// voyage, une seule fois : choisir un rythme pose la question d'iOS, la
/// passer ne demande rien. Quelqu'un qui a traversé cette étape **sans
/// autoriser** — question jamais posée, ou refusée — voit dans la
/// conversation une bulle de MEMO (maquette « Suggestions - activer les
/// notifs », `3207:25190`) :
///
/// - question jamais posée : « Activer les notifications » la pose ;
/// - refusée : iOS ne la repose jamais, « Activer dans les Réglages » ouvre
///   la page de MemoBook dans les Réglages.
///
/// Elle disparaît dès que l'autorisation est donnée — relue à l'ouverture et
/// au retour au premier plan, donc au retour des Réglages — et « Ignorer » la
/// fait taire sur l'appareil, comme les autres appels à l'action de bulle
/// (``ChatCallToActionMemory``). C'est le dessin de ``ChatCallToActionCard``,
/// tel quel : le bouton n'ouvre pas un écran, il pose une question au système.
///
/// **Posée par l'app**, pas par le serveur : seul le téléphone sait ce qu'iOS
/// a répondu. Un co-voyageur qui a rejoint par un code n'a jamais vu l'étape :
/// il ne la voit pas.
///
/// L'autorisation est lue **par l'écran** (``ChatView``), à l'ouverture et à
/// chaque retour au premier plan : la bulle vit dans une liste paresseuse, où
/// une ligne vide garderait sa marge.
struct ChatNotificationsNudge: View {
    let model: ChatModel
    let authorization: UNAuthorizationStatus
    /// Relit l'autorisation, une fois la question posée.
    let onAnswered: () async -> Void

    @Environment(\.pushNotifications) private var pushNotifications

    var body: some View {
        ChatCallToActionCard(
            text: NotificationsNudge.text(isDenied: authorization == .denied),
            callToAction: NotificationsNudge.callToAction(isDenied: authorization == .denied),
            state: .pending,
            onFollow: follow,
            onDismiss: { model.dismissCallToAction(of: NotificationsNudge.bubbleId) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Dans le bac à sable, ``PushNotifications`` n'est pas branché (`nil`) :
    /// la question se pose alors directement au système, pour que la bulle
    /// se vérifie quand même.
    private func follow() {
        if authorization == .denied {
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
            UIApplication.shared.open(url)
            return
        }
        Task {
            if let pushNotifications {
                await pushNotifications.requestAuthorization()
            } else {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
            await onAnswered()
        }
    }
}

/// Ce que la bulle retient et ce qu'elle dit — logique pure, testée.
enum NotificationsNudge {
    /// L'identifiant de la bulle, sous lequel « Ignorer » est retenu. Un seul
    /// pour tous les voyages : c'est l'appareil qu'on autorise, pas un voyage.
    static let bubbleId = "local.notifications-nudge"

    private static let stepPassedKey = "memobook.notifications.stepPassed"

    /// L'étape « Notifications » de la création a été traversée — choisie ou
    /// passée — sur cet appareil.
    static func markStepPassed(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: stepPassedKey)
    }

    static func hasPassedStep(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: stepPassedKey)
    }

    /// La bulle se montre à qui a traversé l'étape, sans que les
    /// notifications puissent arriver, et ne l'a pas ignorée.
    static func isShown(
        hasPassedStep: Bool,
        authorization: UNAuthorizationStatus,
        state: ChatCallToActionState
    ) -> Bool {
        hasPassedStep && !authorization.allowsDelivery && state != .dismissed
    }

    // MARK: - Les mots

    /// Le texte de la bulle. La maquette (`3207:25190`) le mêle au rythme du
    /// récit ; on n'en garde que la phrase des notifications, au tutoiement.
    static func text(isDenied: Bool) -> String {
        isDenied
            ? "Les notifications sont coupées pour MemoBook. Active-les dans les Réglages pour que je t’aide à tenir le rythme que tu t’es fixé."
            : "Active les notifications pour que je t’aide à tenir le rythme que tu t’es fixé : je te ferai signe quand il sera temps de raconter la suite."
    }

    static func callToAction(isDenied: Bool) -> ChatCallToAction {
        ChatCallToAction(
            id: "enable_notifications",
            kind: .enableNotifications,
            label: isDenied ? "Activer dans les Réglages" : "Activer les notifications",
            // L'en-tête de la maquette.
            eyebrow: "Suggestions"
        )
    }

    /// Lu hors de l'acteur principal, comme ``PushNotifications`` : les
    /// réglages de notification ne traversent pas les acteurs, leur statut si.
    nonisolated static func systemAuthorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
