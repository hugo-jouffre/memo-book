import Foundation
import MemoBookCore
import Observation

/// Ce que l'écran des paramètres d'un voyage sait faire : les charger, et
/// enregistrer ce qu'on y change.
///
/// Même construction que ``ProfileModel`` : le modèle ne connaît pas l'API, il
/// reçoit **deux fonctions** — une qui lit, une qui écrit. L'app leur branche
/// `GET` et `PATCH /v1/trips/:id/settings` ; les aperçus n'en fournissent aucune
/// et travaillent alors en mémoire, sans serveur.
///
/// **Un réglage modifié part au serveur dès qu'il est touché**, un par un. Pas
/// de bouton « Enregistrer » : c'est le contrat des lignes des Réglages, ici
/// comme dans le profil. Et un seul réglage à la fois dans la requête
/// (``TripSettingsEdit``), pour ne pas écraser ce qu'un co-voyageur aurait
/// changé entre-temps.
@MainActor
@Observable
public final class TripSettingsModel {
    public private(set) var settings: TripSettings?
    public private(set) var errorMessage: String?

    private let tripId: String
    private let source: (String) async throws -> TripSettings
    private let persist: ((String, TripSettingsEdit) async throws -> TripSettings)?

    /// L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
    /// bascules s'enchaînent : c'est la dernière qui compte, et la réponse
    /// d'une requête dépassée réécrirait l'écran avec une valeur périmée.
    private var pendingSave: Task<Void, Never>?

    /// Retirer un co-voyageur, et renvoyer son lien d'invitation. Deux gestes
    /// que le `PATCH` des réglages ne sait pas porter : ils touchent
    /// `memo_members`, pas `memos`.
    private let removeCompanion: ((String, String) async throws -> TripSettings)?
    private let resendInvitation: ((String, String) async throws -> Void)?

    /// Ce qu'on vient de faire, et qu'il faut dire. Un mot sous la liste de la
    /// feuille — « Invitation renvoyée » —, pas une alerte : l'action a réussi,
    /// il n'y a rien à confirmer.
    public private(set) var confirmation: String?

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripSettings = { _ in .fixture },
        persist: ((String, TripSettingsEdit) async throws -> TripSettings)? = nil,
        removeCompanion: ((String, String) async throws -> TripSettings)? = nil,
        resendInvitation: ((String, String) async throws -> Void)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
        self.removeCompanion = removeCompanion
        self.resendInvitation = resendInvitation
    }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// ses intitulés, ses groupes et ses lignes appartiennent à l'app, pas au
    /// serveur. Seules les valeurs portent une barre d'attente — voir
    /// ``BrandSkeleton``.
    public var isLoading: Bool { settings == nil && errorMessage == nil }

    public func load() async {
        do {
            settings = try await source(tripId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Ce qu'on change depuis l'écran
    //
    // Des méthodes plutôt qu'un `settings` ouvert en écriture : une vue ne doit
    // pas pouvoir poser une valeur sans qu'elle partie au serveur.

    public func setNotifications(_ isOn: Bool) {
        guard var current = settings else { return }
        current.wantsNotifications = isOn
        settings = current
        save(.notifications(isOn))
    }

    public func setPublicGallery(_ isOn: Bool) {
        guard var current = settings else { return }
        current.isPublicGallery = isOn
        settings = current
        save(.publicGallery(isOn))
    }

    /// Les deux dates d'un coup : elles se bornent l'une l'autre, et les
    /// envoyer séparément ferait refuser l'intermédiaire par le serveur.
    public func setDates(start: Date?, end: Date?) {
        guard var current = settings else { return }
        current.startDate = start
        current.endDate = end
        settings = current
        save(.dates(start: start, end: end))
    }

    public func setPace(_ pace: NarrationPace) {
        guard var current = settings else { return }
        current.narrationPace = pace
        settings = current
        save(.narrationPace(pace))
    }

    public func setTheme(_ theme: String) {
        let trimmed = theme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var current = settings, !trimmed.isEmpty, trimmed != current.theme else { return }
        current.theme = trimmed
        settings = current
        save(.theme(trimmed))
    }

    public func setNotificationPreferences(_ preferences: TripNotificationPreferences) {
        guard var current = settings else { return }
        current.notifications = preferences
        settings = current
        save(.notificationPreferences(preferences))
    }

    // MARK: - Les co-voyageurs

    /// Retire quelqu'un du voyage.
    ///
    /// **Le propriétaire ne se retire pas** — c'est la note « Logique » de la
    /// maquette, et c'est aussi ce que le serveur refuserait. Le garde-fou est
    /// ici pour que l'action ne soit pas *proposée*, pas pour rattraper un
    /// appel.
    public func remove(_ companion: Companion) {
        guard let removeCompanion, !companion.isOwner, var current = settings else { return }

        // L'écran a déjà bougé : une ligne qui reste en place le temps d'un
        // aller-retour donne l'impression que le geste n'a pas pris.
        current.companions.removeAll { $0.id == companion.id }
        settings = current

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await removeCompanion(tripId, companion.id)
                guard !Task.isCancelled else { return }
                settings = updated
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }

    /// Renvoie le lien d'invitation à quelqu'un qui n'est jamais entré.
    public func resendInvitation(to companion: Companion) {
        guard let resendInvitation, companion.isPending else { return }

        Task {
            do {
                try await resendInvitation(tripId, companion.id)
                confirm(BookCopy.Invite.resent(companion.name))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Un mot qui s'efface tout seul. Il ne demande rien, il **accuse
    /// réception** — le laisser à l'écran obligerait à le refermer.
    private func confirm(_ message: String) {
        confirmation = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard confirmation == message else { return }
            confirmation = nil
        }
    }

    /// Envoie un réglage, et remplace l'écran par ce que le serveur relit.
    ///
    /// **L'écran a déjà bougé** quand on arrive ici : un interrupteur qui
    /// attend un aller-retour réseau pour basculer se lit comme cassé. La
    /// réponse ne fait que confirmer — ou, en cas d'échec, remettre les
    /// valeurs du serveur, ce qui annule visiblement la bascule.
    private func save(_ edit: TripSettingsEdit) {
        guard let persist else { return }

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await persist(tripId, edit)
                guard !Task.isCancelled else { return }
                settings = updated
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                // Remettre ce que le serveur a vraiment : sans ça,
                // l'interrupteur resterait sur une valeur que personne n'a
                // enregistrée.
                await load()
            }
        }
    }

    #if DEBUG
        /// Vide les valeurs pour rejouer l'état de chargement. Absent de l'app
        /// livrée.
        func debugShowSkeleton() {
            settings = nil
            errorMessage = nil
        }
    #endif
}
