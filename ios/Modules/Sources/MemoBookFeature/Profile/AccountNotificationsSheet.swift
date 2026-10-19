import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// « Notifications » du profil — celles **du compte**, qui ne parlent d'aucun
/// voyage : rappel de renouvellement, vacances scolaires, l'an dernier à la
/// même époque, anniversaire (D13, Hugo, 19/10/2026). Une carte chacune.
///
/// Elles n'avaient aucun interrupteur : seul le réglage d'iOS les coupait, et
/// lui coupe tout. Celles d'un voyage restent dans ses réglages
/// (``TripNotificationsSheet``), et ne valent que pour soi.
///
/// ⚠️ **Aucune maquette** : dessinée exactement sur la feuille
/// « Notifications » d'un voyage — même chapeau, mêmes cartes, même avis quand
/// iOS refuse tout —, et à dessiner dans Figma.
struct AccountNotificationsSheet: View {
    let model: ProfileModel

    @Environment(\.pushNotifications) private var pushNotifications
    @Environment(\.openURL) private var openURL

    private var preferences: AccountNotificationPreferences? { model.profile?.notifications }

    /// Tout est coupé dans les Réglages de l'iPhone : les cartes enregistrent
    /// toujours, mais rien n'arrivera tant qu'on n'y retourne pas.
    private var isBlockedBySystem: Bool { pushNotifications?.authorization == .denied }

    var body: some View {
        BrandSheet(AccountNotificationsCopy.title, subtitle: AccountNotificationsCopy.subtitle) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                if isBlockedBySystem {
                    BrandNotice(BookCopy.Notifications.systemDeniedNotice) {
                        Button(BookCopy.Notifications.openSettings) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.action)
                    }
                }

                BrandToggleCard(
                    title: AccountNotificationsCopy.renewalReminder,
                    detail: AccountNotificationsCopy.renewalReminderDetail,
                    isOn: binding(\.renewalReminder) { $0.renewalReminder = $1 }
                )
                BrandToggleCard(
                    title: AccountNotificationsCopy.schoolHolidays,
                    detail: AccountNotificationsCopy.schoolHolidaysDetail,
                    isOn: binding(\.schoolHolidays) { $0.schoolHolidays = $1 }
                )
                BrandToggleCard(
                    title: AccountNotificationsCopy.learnedPeriod,
                    detail: AccountNotificationsCopy.learnedPeriodDetail,
                    isOn: binding(\.learnedPeriod) { $0.learnedPeriod = $1 }
                )
                BrandToggleCard(
                    title: AccountNotificationsCopy.birthday,
                    detail: AccountNotificationsCopy.birthdayDetail,
                    isOn: binding(\.birthday) { $0.birthday = $1 }
                )
            }
            // Les bascules **agissent** : les toucher avant que le profil soit
            // là enverrait un état qu'on n'a pas lu.
            .disabled(preferences == nil)
        }
        // On revient peut-être des Réglages : ce qu'iOS autorise a pu changer.
        .task { await pushNotifications?.refreshAuthorization() }
    }

    /// La liaison d'une carte : elle lit le modèle et lui repasse le bloc
    /// entier, parce que c'est le bloc entier que la route accepte — comme
    /// ``TripNotificationsSheet``.
    @MainActor
    private func binding(
        _ keyPath: KeyPath<AccountNotificationPreferences, Bool>,
        _ set: @escaping (inout AccountNotificationPreferences, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { model.profile?.notifications[keyPath: keyPath] ?? false },
            set: { isOn in
                guard var preferences = model.profile?.notifications else { return }
                set(&preferences, isOn)
                model.setNotifications(preferences)
                // Allumer une notification sans avoir jamais répondu à iOS :
                // c'est le moment de lui poser la question.
                if isOn, pushNotifications?.authorization == .notDetermined {
                    Task { await pushNotifications?.requestAuthorization() }
                }
            }
        )
    }
}

/// Les mots de la feuille. ⚠️ **Aucun ne vient d'une maquette** — textes à
/// relire par Clara, sur le ton de la feuille d'un voyage.
enum AccountNotificationsCopy {
    static let rowTitle = "Notifications"

    static let title = "Notifications"
    static let subtitle =
        "Choisis ce que MemoBook peut te rappeler en dehors de tes voyages. Les alertes d’un voyage se règlent dans ses réglages."

    static let renewalReminder = "Rappel de renouvellement"
    static let renewalReminderDetail = "Trois jours avant que ton abonnement reparte"
    static let schoolHolidays = "Vacances scolaires"
    static let schoolHolidaysDetail = "Une semaine avant, puis le jour même"
    static let learnedPeriod = "L’an dernier à la même époque"
    static let learnedPeriodDetail = "Quand revient la période d’un voyage passé"
    static let birthday = "Anniversaire"
    static let birthdayDetail = "Une semaine avant le tien"

    /// Ce que la ligne du profil résume : « Toutes actives », « 3 sur 4 »,
    /// « Aucune ».
    static func summary(_ preferences: AccountNotificationPreferences) -> String {
        let flags = [
            preferences.renewalReminder, preferences.schoolHolidays,
            preferences.learnedPeriod, preferences.birthday,
        ]
        let on = flags.filter { $0 }.count
        switch on {
        case flags.count: return "Toutes actives"
        case 0: return "Aucune"
        default: return "\(on) sur \(flags.count)"
        }
    }
}

#Preview("Notifications du compte") {
    // Le jeu d'essai, chargé : l'anniversaire coupé, le reste allumé.
    let model = ProfileModel()
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            AccountNotificationsSheet(model: model)
                .task { await model.load() }
        }
}
