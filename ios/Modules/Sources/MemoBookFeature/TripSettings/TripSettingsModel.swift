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

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripSettings = { _ in .fixture },
        persist: ((String, TripSettingsEdit) async throws -> TripSettings)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
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
