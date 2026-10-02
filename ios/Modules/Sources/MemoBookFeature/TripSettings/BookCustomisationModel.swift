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

    /// L'assortiment qui vient d'éteindre les pointillés, le temps que la
    /// feuille des typographies le dise. `nil` dès le geste suivant.
    public private(set) var rulesWithdrawnBy: BookFontCombo?

    /// On vient de toucher l'interrupteur verrouillé : Extras dit pourquoi,
    /// tant que le verrou tient.
    public var showsRulesLockNotice: Bool { isExplainingRulesLock && isRulesSwitchLocked }
    private var isExplainingRulesLock = false

    private let tripId: String
    private let source: (String) async throws -> TripSettings
    private let persist: ((String, BookCustomisationEdit) async throws -> TripSettings)?
    private let rulesMemory: BookRulesMemory

    /// L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
    /// gestes s'enchaînent — un curseur qu'on pousse d'un cran à l'autre en
    /// envoie un par cran, et c'est le dernier qui compte.
    private var pendingSave: Task<Void, Never>?

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripSettings = { _ in .fixture },
        persist: ((String, BookCustomisationEdit) async throws -> TripSettings)? = nil,
        rulesMemory: BookRulesMemory = .inMemory()
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
        self.rulesMemory = rulesMemory
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

    /// Lit les réglages, puis remet dans le rang un carnet que le verrou des
    /// pointillés n'a pas encore touché — voir ``BookRulesLock/normalised(_:remembered:)``.
    public func load() async {
        guard await reload() else { return }
        settleRules()
    }

    /// Lit les réglages, sans rien renvoyer. C'est la relecture d'après un
    /// envoi raté : y remettre les pointillés dans le rang renverrait le même
    /// envoi, qui raterait de la même façon, sans fin.
    @discardableResult
    private func reload() async -> Bool {
        do {
            settings = try await source(tripId)
            clearError()
            forgetRulesIfUnlocked()
            // Relu après un envoi raté, le carnet peut être revenu sur Carnet de
            // voyage, pointillés allumés : la note dirait le contraire.
            rulesWithdrawnBy = nil
            forgetLockNoticeIfUnlocked()
            return true
        } catch {
            report(error)
            return false
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

    /// Verrou posé, les pointillés ne se rallument pas : l'interrupteur pâlit
    /// et explique (``BookExtrasPanel``), et un appel qui passerait quand même
    /// ne part pas.
    public func setRules(_ isOn: Bool) {
        if isOn, areRulesLocked { return }
        edit(.rules(isOn)) { $0.rulesEnabled = isOn }
    }

    /// L'appui sur l'interrupteur verrouillé : poser la note qui dit pourquoi,
    /// et comment en sortir. Elle s'en va avec le verrou, et ne revient pas
    /// d'elle-même au suivant : elle répond à un appui, pas à un état.
    public func explainRulesLock() { isExplainingRulesLock = true }

    /// Les pointillés sont-ils verrouillés par l'assortiment du carnet ?
    public var areRulesLocked: Bool {
        customisation.map(BookRulesLock.isLocked) ?? false
    }

    /// L'interrupteur doit-il pâlir ? Verrou posé **et** pointillés éteints.
    ///
    /// Allumés sous un verrou — une remise dans le rang qui a échoué —, ils
    /// s'impriment : l'interrupteur reste libre de les éteindre, puisque le
    /// verrou n'interdit que de les rallumer, et la note qui dit « ils ne
    /// s'impriment qu'avec Carnet de voyage » mentirait.
    public var isRulesSwitchLocked: Bool {
        areRulesLocked && customisation?.rulesEnabled == false
    }

    public func setDecorationQuota(_ quota: Int) {
        edit(.decorationQuota(quota)) { $0.decorationQuota = quota }
    }

    /// L'assortiment de typographies du carnet : les quatre polices d'un coup.
    ///
    /// **Il n'y a plus de réglage par rôle** (Hugo, 16/09/2026) — voir
    /// ``BookFontCombo``. Une seule édition part, et les quatre colonnes
    /// bougent ensemble : c'est ce qui garantit qu'aucun carnet ne se retrouve
    /// avec deux polices d'un assortiment et deux d'un autre.
    ///
    /// **Les pointillés partent avec elles** : *Manuscrit* et *Éditorial* les
    /// éteignent, le retour au défaut rend ceux d'avant — ``BookRulesLock``
    /// décide, et la même édition porte les cinq valeurs.
    public func setFontCombo(_ combo: BookFontCombo) {
        guard let current = customisation else { return }
        let change = BookRulesLock.choosing(combo, in: current, remembered: rulesMemory.read(tripId))
        if let remember = change.remember { rulesMemory.write(tripId, remember) }

        edit(.fontCombo(combo, rulesEnabled: change.rulesEnabled)) { customisation in
            for role in BookFontRole.allCases {
                customisation[keyPath: role.keyPath] = combo.font(role)
            }
            customisation.rulesEnabled = change.rulesEnabled
        }
        // Après `edit`, qui efface la note du geste précédent.
        if current.rulesEnabled, !change.rulesEnabled { rulesWithdrawnBy = combo }
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
        rulesWithdrawnBy = nil
        apply(&customisation)
        current.customisation = customisation
        settings = current
        forgetLockNoticeIfUnlocked()
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
                forgetRulesIfUnlocked()
                forgetLockNoticeIfUnlocked()
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
                await reload()
            }
        }
    }

    // MARK: - Le verrou des pointillés

    /// Un carnet verrouillé aux pointillés allumés — passé sur *Manuscrit*
    /// avant le verrou, ou rallumé par une ancienne version de l'app — est
    /// remis dans le rang à l'ouverture : éteints, et « allumés » mémorisé
    /// pour le retour au défaut (Hugo, 02/10/2026) — sauf si ce téléphone
    /// garde déjà la valeur d'avant le verrou : c'est elle qu'on rendra. C'est
    /// une écriture au serveur sans geste du voyageur, et la seule de l'écran.
    private func settleRules() {
        guard let customisation,
              let change = BookRulesLock.normalised(customisation, remembered: rulesMemory.read(tripId))
        else { return }
        if let remember = change.remember { rulesMemory.write(tripId, remember) }
        edit(.rules(change.rulesEnabled)) { $0.rulesEnabled = change.rulesEnabled }
    }

    private func forgetLockNoticeIfUnlocked() {
        if !isRulesSwitchLocked { isExplainingRulesLock = false }
    }

    /// La mémoire ne sert qu'à défaire un verrou : dès que le serveur rend un
    /// carnet qui n'en a pas, elle s'efface. **Seulement sur sa parole**, et
    /// pas au geste : un retour au défaut dont l'envoi échoue relit un carnet
    /// encore verrouillé, et doit encore savoir quoi rendre.
    private func forgetRulesIfUnlocked() {
        guard let customisation, !BookRulesLock.isLocked(customisation) else { return }
        rulesMemory.write(tripId, nil)
    }
}
