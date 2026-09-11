import Foundation
import MemoBookCore
import Observation

/// Ce que l'écran des personnalisations sait faire : les lire, et enregistrer ce
/// qu'on y change.
///
/// Même construction que ``TripSettingsModel``, et pour la même raison : le
/// modèle ne connaît pas l'API, il reçoit deux fonctions. L'app leur branche
/// `GET` et `PATCH /v1/trips/:id/customisation` ; les aperçus n'en fournissent
/// aucune et travaillent en mémoire.
///
/// **Un réglage part seul, dès qu'il est touché.** Pas de bouton
/// « Enregistrer » : c'est le contrat des lignes des Réglages partout dans
/// l'app.
@MainActor
@Observable
public final class BookCustomisationModel {
    public private(set) var customisation: BookCustomisation?
    public private(set) var errorMessage: String?

    private let tripId: String
    private let source: (String) async throws -> BookCustomisation
    private let persist: ((String, BookCustomisationEdit) async throws -> BookCustomisation)?

    /// L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
    /// bascules s'enchaînent : c'est la dernière qui compte.
    private var pendingSave: Task<Void, Never>?

    public init(
        tripId: String,
        source: @escaping (String) async throws -> BookCustomisation = { _ in .fixture },
        persist: ((String, BookCustomisationEdit) async throws -> BookCustomisation)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
    }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// ses intitulés et ses groupes appartiennent à l'app.
    public var isLoading: Bool { customisation == nil && errorMessage == nil }

    public func load() async {
        do {
            customisation = try await source(tripId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Les trois extras

    public func setQuiz(_ isOn: Bool) {
        guard var current = customisation else { return }
        current.quizEnabled = isOn
        customisation = current
        save(.quiz(isOn))
    }

    public func setFreeZones(_ isOn: Bool) {
        guard var current = customisation else { return }
        current.freeZonesEnabled = isOn
        customisation = current
        save(.freeZones(isOn))
    }

    public func setCrossword(_ isOn: Bool) {
        guard var current = customisation else { return }
        current.crosswordEnabled = isOn
        customisation = current
        save(.crossword(isOn))
    }

    /// Envoie un réglage, et remplace l'écran par ce que le serveur relit.
    ///
    /// L'écran a déjà bougé quand on arrive ici : un interrupteur qui attend un
    /// aller-retour réseau pour basculer se lit comme cassé.
    private func save(_ edit: BookCustomisationEdit) {
        guard let persist else { return }

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await persist(tripId, edit)
                guard !Task.isCancelled else { return }
                customisation = updated
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }
}
