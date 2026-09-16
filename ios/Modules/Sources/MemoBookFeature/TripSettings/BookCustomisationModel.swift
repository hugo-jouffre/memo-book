import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// Ce que l'écran des personnalisations sait faire : les lire, et enregistrer
/// ce qu'on y change.
///
/// Même construction que ``TripSettingsModel``, et pour la même raison : le
/// modèle ne connaît pas l'API, il reçoit des fonctions. L'app leur branche
/// `GET /v1/trips/:id/settings` et son `PATCH` ; les aperçus n'en fournissent
/// aucune et travaillent en mémoire.
///
/// **Il lit les réglages entiers, pas seulement les personnalisations**, et
/// c'est la route qui le veut : elles voyagent ensemble parce qu'il y en a un
/// jeu par voyage. Ça tombe bien — la feuille « Nombre de page » a besoin des
/// **dates** pour projeter ses trois paliers, et un second appel pour deux
/// dates déjà servies aurait été un aller-retour pour rien.
///
/// **Un réglage part seul, dès qu'il est touché.** Pas de bouton
/// « Enregistrer » : c'est le contrat des lignes des Réglages partout dans
/// l'app. Les feuilles qui portent quand même un « Valider » ne l'ont pas pour
/// enregistrer — c'est déjà fait — mais pour se refermer, comme la maquette le
/// dessine.
@MainActor
@Observable
public final class BookCustomisationModel {
    public private(set) var settings: TripSettings?
    public private(set) var errorMessage: String?

    /// Ce qu'on peut **faire** de l'erreur — voir `APIError.recoveryAdvice`.
    public private(set) var errorAdvice: String?

    private let tripId: String
    private let source: (String) async throws -> TripSettings
    private let persist: ((String, BookCustomisationEdit) async throws -> TripSettings)?

    /// L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
    /// gestes s'enchaînent — un curseur qu'on pousse d'un cran à l'autre en
    /// envoie un par cran, et c'est le dernier qui compte.
    private var pendingSave: Task<Void, Never>?

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripSettings = { _ in .fixture },
        persist: ((String, BookCustomisationEdit) async throws -> TripSettings)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
    }

    public var customisation: BookCustomisation? { settings?.customisation }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// ses intitulés et ses groupes appartiennent à l'app.
    public var isLoading: Bool { settings == nil && errorMessage == nil }

    /// Combien de jours dure le voyage, bornes comprises. `nil` quand les dates
    /// manquent — les paliers de pages retombent alors sur le défaut de la base
    /// plutôt que d'annoncer une projection qu'on n'a pas de quoi faire.
    public var tripDays: Int? {
        guard let settings, let start = settings.startDate else { return nil }
        let end = settings.endDate ?? start
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }

    public func load() async {
        do {
            settings = try await source(tripId)
            clearError()
        } catch {
            report(error)
        }
    }

    /// Pose l'erreur **et son conseil** : la phrase dit ce qui s'est passé, le
    /// conseil ce qu'on peut faire (Hugo, 15/09/2026).
    private func report(_ error: any Error) {
        errorMessage = error.localizedDescription
        errorAdvice = (error as? APIError)?.recoveryAdvice
    }

    private func clearError() {
        errorMessage = nil
        errorAdvice = nil
    }

    /// Le PDF du carnet composé, pour les deux pages qui flottent au-dessus des
    /// feuilles. `nil` tant qu'aucun carnet n'a été composé.
    ///
    /// **Il arrive avec les réglages**, sans second appel : la route lit déjà le
    /// dernier rendu prêt pour en tirer la vignette de couverture. Un appel de
    /// plus n'aurait servi qu'à redemander ce qu'on avait.
    public var bookPdfUrl: URL? { settings?.bookPdfUrl }

    // MARK: - Ce qu'on change depuis les feuilles

    public func setPhotoTextRatio(_ ratio: Int) { edit(.photoTextRatio(ratio)) { $0.photoTextRatio = ratio } }

    public func setTargetPageCount(_ pages: Int) {
        edit(.targetPageCount(pages)) { $0.targetPageCount = pages }
    }

    public func setFunFacts(_ isOn: Bool) { edit(.funFacts(isOn)) { $0.funFactsEnabled = isOn } }

    public func setRules(_ isOn: Bool) { edit(.rules(isOn)) { $0.rulesEnabled = isOn } }

    public func setDecorationQuota(_ quota: Int) {
        edit(.decorationQuota(quota)) { $0.decorationQuota = quota }
    }

    /// L'assortiment de typographies du carnet : les quatre polices d'un coup.
    ///
    /// **Il n'y a plus de réglage par rôle** (Hugo, 16/09/2026) — voir
    /// ``BookFontCombo``. Une seule édition part, et les quatre colonnes
    /// bougent ensemble : c'est ce qui garantit qu'aucun carnet ne se retrouve
    /// avec deux polices d'un assortiment et deux d'un autre.
    public func setFontCombo(_ combo: BookFontCombo) {
        edit(.fontCombo(combo)) { customisation in
            for role in BookFontRole.allCases {
                customisation[keyPath: role.keyPath] = combo.font(role)
            }
        }
    }

    public func setQuiz(_ isOn: Bool) { edit(.quiz(isOn)) { $0.quizEnabled = isOn } }

    public func setFreeZones(_ isOn: Bool) { edit(.freeZones(isOn)) { $0.freeZonesEnabled = isOn } }

    public func setCrossword(_ isOn: Bool) { edit(.crossword(isOn)) { $0.crosswordEnabled = isOn } }

    /// Pose la valeur à l'écran, puis l'envoie.
    ///
    /// Les deux dans cet ordre, toujours : un curseur qui attend un
    /// aller-retour réseau pour bouger se lit comme cassé, et les quatre
    /// feuilles à curseur seraient inutilisables.
    private func edit(
        _ change: BookCustomisationEdit,
        _ apply: (inout BookCustomisation) -> Void
    ) {
        guard var current = settings, var customisation = current.customisation else { return }
        apply(&customisation)
        current.customisation = customisation
        settings = current
        save(change)
    }

    /// Envoie un réglage, et remplace l'écran par ce que le serveur relit.
    private func save(_ change: BookCustomisationEdit) {
        guard let persist else { return }

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await persist(tripId, change)
                guard !Task.isCancelled else { return }
                settings = updated
                clearError()
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
                await load()
            }
        }
    }
}
