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

    /// Le changement de nombre de pages cible que la feuille raconte, d'étape
    /// en étape — voir ``PageTargetChange``. `nil` quand elle est fermée.
    public private(set) var pageTargetChange: PageTargetChange?

    /// On vient de toucher un palier alors que la cible ne bouge plus : le
    /// panneau le dit à l'orange, sous les paliers pâlis. Comme la note du
    /// verrou des pointillés, elle répond à un appui, pas à un état.
    public var showsPageTargetLimitNotice: Bool { isExplainingPageTargetLimit && isPageTargetLocked }
    private var isExplainingPageTargetLimit = false

    /// La réécriture des étapes déjà écrites part — le lien du panneau
    /// attend sa réponse.
    public private(set) var isRewritingWrittenSteps = false

    /// La réécriture est lancée : le panneau le dit, à la place du lien.
    public private(set) var hasStartedRewrite = false

    private let tripId: String
    private let source: (String) async throws -> TripSettings
    private let persist: ((String, BookCustomisationEdit) async throws -> TripSettings)?
    private let rewrite: ((String) async throws -> TripSettings)?
    private let today: () -> Date
    private let rulesMemory: BookRulesMemory

    /// Les réglages qui attendent leur tour, envoyés **un par un**, dans
    /// l'ordre — voir ``save(_:)``.
    private var queue: [BookCustomisationEdit] = []
    private var isSending = false
    /// Un envoi est parti, et le serveur n'a pas encore répondu.
    private var isAwaitingResponse = false
    /// Compte les gestes et les réponses : une relecture partie avant l'un
    /// d'eux est périmée — voir ``reload()``.
    private var revision = 0

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripSettings = { _ in .fixture },
        persist: ((String, BookCustomisationEdit) async throws -> TripSettings)? = nil,
        rewrite: ((String) async throws -> TripSettings)? = nil,
        today: @escaping () -> Date = { .now },
        rulesMemory: BookRulesMemory = .inMemory()
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
        self.rewrite = rewrite
        self.today = today
        self.rulesMemory = rulesMemory
    }

    public var customisation: BookCustomisation? { settings?.customisation }

    /// `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
    /// ses intitulés et ses groupes appartiennent à l'app.
    public var isLoading: Bool { settings == nil && errorMessage == nil }

    /// Combien de jours dure le voyage, bornes comprises. `nil` quand une des
    /// deux dates manque — les paliers de pages retombent alors sur le défaut
    /// de la base (40 / 60 / 80) plutôt que d'annoncer une projection qu'on
    /// n'a pas de quoi faire.
    ///
    /// **Sans date de fin, on ne sait pas** (15/10/2026) : la date de début
    /// servait de fin, le voyage durait un jour, et le palier « Par défaut »
    /// tombait à 30 pages pour un voyage qui commence à peine.
    public var tripDays: Int? {
        guard let settings, let start = settings.startDate, let end = settings.endDate else { return nil }
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
    ///
    /// **Une lecture que croise un geste n'est pas montrée** : elle a été
    /// prise avant lui, et la poser effacerait à l'écran un réglage qui part
    /// encore — ou effacerait la mémoire du verrou qu'il vient d'écrire. Pareil
    /// tant qu'un envoi attend sa réponse : c'est elle qui remettra l'écran
    /// d'accord avec le serveur. Rend `false` dans ces deux cas, comme à
    /// l'échec — ``load()`` ne remet alors rien dans le rang.
    @discardableResult
    private func reload() async -> Bool {
        let before = revision
        do {
            let fresh = try await source(tripId)
            guard revision == before, !isAwaitingResponse, queue.isEmpty else { return false }
            settings = fresh
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

    /// L'image de l'aperçu de personnalisation, en tête de l'écran — voir
    /// ``BookCustomisationPreview/imageURL(for:)``. `nil` tant que les
    /// réglages ne sont pas lus.
    ///
    /// Elle ne dépend que des cinq réglages qui la pilotent : l'écran peut
    /// suivre cette adresse sans jamais recharger pour le nombre de pages, le
    /// quiz, les zones libres ou le mot fléché.
    public var previewURL: URL? {
        customisation.map(BookCustomisationPreview.imageURL(for:))
    }

    // MARK: - Ce qu'on change depuis les feuilles

    public func setPhotoTextRatio(_ ratio: Int) { edit(.photoTextRatio(ratio)) { $0.photoTextRatio = ratio } }

    /// Change le nombre de pages cible — ou ouvre la feuille qui le fait.
    ///
    /// **Tant qu'aucune étape n'est écrite, le changement est libre** et part
    /// au geste, comme tout réglage. Ensuite, il compte (Hugo, 15/10/2026) :
    /// la feuille prévient d'abord de ce qui reste, et rien ne change avant
    /// qu'on confirme — l'écran garde l'ancien palier coché. Les deux
    /// changements faits, rien ne part : le panneau dit pourquoi, à l'orange.
    public func setTargetPageCount(_ pages: Int) {
        guard let current = customisation?.targetPageCount, pages != current else { return }
        let allowance = pageTargetAllowance
        guard allowance.changesCount else {
            edit(.targetPageCount(pages)) { $0.targetPageCount = pages }
            return
        }
        guard allowance.changesLeft > 0 else {
            explainPageTargetLimit()
            return
        }
        pageTargetChange = PageTargetChange(
            from: current,
            to: pages,
            tripDays: tripDays,
            step: .confirm(changesLeft: allowance.changesLeft)
        )
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
    ///
    /// Retoucher l'assortiment déjà choisi n'envoie rien : l'édition porterait
    /// les pointillés de l'écran, et rallumerait ceux qu'un co-voyageur vient
    /// d'éteindre.
    public func setFontCombo(_ combo: BookFontCombo) {
        guard let current = customisation, !combo.matches(current) else { return }
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
        revision += 1
        rulesWithdrawnBy = nil
        apply(&customisation)
        current.customisation = customisation
        settings = current
        forgetLockNoticeIfUnlocked()
        save(change)
    }

    /// Envoie un réglage, et remplace l'écran par ce que le serveur relit.
    ///
    /// **En file, et non en annulant l'envoi d'avant** (02/10/2026). Annuler
    /// valait pour les crans d'un même curseur, mais pas pour deux réglages
    /// voisins : éteindre les fun facts puis le quiz annulait l'envoi des fun
    /// facts, la réponse du quiz les rendait allumés, et l'aperçu de
    /// personnalisation bougeait après un geste qui ne le concerne pas. Donc :
    ///
    /// - un envoi part quand le précédent a répondu ;
    /// - un réglage qui attend encore est remplacé par un plus récent **du même
    ///   champ** : un curseur qu'on fait glisser n'envoie que son premier cran
    ///   et celui où il s'arrête ;
    /// - seule la réponse du dernier envoi remplace l'écran — elle a vu tous
    ///   les gestes d'avant, les autres seraient déjà périmées ;
    /// - un envoi raté ne retient pas ceux qui attendent derrière : ce sont
    ///   d'autres réglages, ils partent quand même, et la réponse du dernier
    ///   montre ce que le serveur a vraiment — le réglage raté compris. Quand
    ///   c'est le dernier qui rate, l'écran relit le serveur.
    private func save(_ change: BookCustomisationEdit) {
        guard persist != nil else { return }
        queue.removeAll { $0.field == change.field }
        queue.append(change)
        // Posé ici, sans attendre que la tâche démarre : deux gestes dans la
        // même image lanceraient sinon deux envois côte à côte.
        guard !isSending else { return }
        isSending = true
        Task { await sendQueue() }
    }

    private func sendQueue() async {
        defer { isSending = false }
        guard let persist else { return }

        while !queue.isEmpty {
            let change = queue.removeFirst()
            isAwaitingResponse = true
            do {
                let updated = try await persist(tripId, change)
                isAwaitingResponse = false
                revision += 1
                guard queue.isEmpty else { continue }
                settings = updated
                clearError()
                forgetRulesIfUnlocked()
                forgetLockNoticeIfUnlocked()
            } catch {
                isAwaitingResponse = false
                revision += 1
                // Le troisième changement de cible, refusé : ce n'est pas une
                // panne. Le panneau le dit à l'orange, et la relecture
                // ci-dessous fait pâlir les paliers.
                if (error as? APIError)?.code == APIError.pageTargetLimitReachedCode {
                    explainPageTargetLimit()
                } else {
                    report(error)
                }
                // D'autres réglages attendent : ils partent, et la réponse du
                // dernier remettra l'écran d'accord avec le serveur.
                guard queue.isEmpty else { continue }
                // Rien derrière : l'écran relit le serveur, et montre ce qu'il
                // a vraiment. Un geste fait pendant cette relecture entre dans
                // la file — la boucle l'envoie au lieu de l'y laisser.
                await reload()
            }
        }
    }

    // MARK: - Le changement de nombre de pages cible

    /// Ce que le serveur dit des changements de cible — rien de compté tant
    /// qu'il ne l'a pas dit.
    public var pageTargetAllowance: PageTargetAllowance {
        settings?.pageTargetAllowance ?? .unrestricted
    }

    /// Les paliers doivent-ils pâlir ? Les deux changements sont faits.
    public var isPageTargetLocked: Bool { pageTargetAllowance.isExhausted }

    /// Le lien « Mettre les étapes déjà écrites à la nouvelle cible » : la
    /// réécriture reste ouverte — on a répondu « Plus tard » — et la feuille
    /// est fermée.
    public var offersRewrite: Bool {
        pageTargetAllowance.rewriteAvailable && pageTargetChange == nil && !hasStartedRewrite
    }

    /// L'appui sur un palier pâli : poser la note orange.
    public func explainPageTargetLimit() { isExplainingPageTargetLimit = true }

    /// « Changer le nombre de pages cible ». Avec une date de fin, les dates
    /// disent où en est le voyage ; sans elle, la feuille le demande.
    public func confirmPageTargetChange() {
        guard var change = pageTargetChange, case .confirm = change.step else { return }
        let stage = PageTargetTripStage.from(
            startDate: settings?.startDate,
            endDate: settings?.endDate,
            today: today()
        )
        guard let stage else {
            change.step = .stage
            pageTargetChange = change
            return
        }
        Task { await commitPageTarget(at: stage) }
    }

    /// La réponse à « À quel stade de ton voyage en es-tu ? ».
    public func choosePageTargetStage(_ stage: PageTargetTripStage) {
        guard pageTargetChange?.step == .stage else { return }
        Task { await commitPageTarget(at: stage) }
    }

    /// Ferme la feuille — « Annuler », « Plus tard », « OK », « Compris » ou
    /// le glissé. Annulé avant l'envoi, rien n'a changé : l'écran n'avait pas
    /// bougé.
    public func dismissPageTargetChange() {
        guard pageTargetChange?.isWorking != true else { return }
        pageTargetChange = nil
    }

    /// Envoie la nouvelle cible, et passe la feuille à son étape suivante.
    ///
    /// **Hors de la file des réglages**, et attendu : la feuille doit savoir
    /// si ce changement-ci est passé — un 409 la fait passer à l'orange de
    /// la limite (un co-voyageur a pu faire le dernier changement entre-temps),
    /// une autre erreur reste sur l'étape avec son message.
    private func commitPageTarget(at stage: PageTargetTripStage) async {
        guard var change = pageTargetChange, !change.isWorking else { return }
        change.isWorking = true
        change.errorMessage = nil
        pageTargetChange = change
        revision += 1
        // Un cran du curseur personnalisé qui attendrait encore ne doit pas
        // repartir derrière celui-ci.
        queue.removeAll { $0.field == BookCustomisationEdit.targetPageCount(0).field }

        guard let persist else {
            // Les aperçus travaillent en mémoire : le changement compte, et la
            // réécriture s'ouvre, comme au serveur.
            if var current = settings, var customisation = current.customisation {
                customisation.targetPageCount = change.to
                current.customisation = customisation
                var allowance = current.pageTargetAllowance
                allowance.changesLeft = max(0, allowance.changesLeft - 1)
                allowance.rewriteAvailable = true
                current.pageTarget = allowance
                settings = current
            }
            hasStartedRewrite = false
            advance(change, to: .done(stage))
            return
        }

        isAwaitingResponse = true
        do {
            let updated = try await persist(tripId, .targetPageCount(change.to))
            isAwaitingResponse = false
            revision += 1
            accept(updated)
            // Un nouveau changement rouvre la réécriture : la phrase « on
            // réécrit » du précédent ne vaut plus.
            hasStartedRewrite = false
            advance(change, to: .done(stage))
        } catch {
            isAwaitingResponse = false
            revision += 1
            if (error as? APIError)?.code == APIError.pageTargetLimitReachedCode {
                advance(change, to: .limitReached)
                await reload()
            } else {
                change.isWorking = false
                change.errorMessage = error.localizedDescription
                if pageTargetChange?.id == change.id { pageTargetChange = change }
            }
        }
    }

    /// Ce que le serveur rend d'un changement de cible. La réponse remplace
    /// l'écran quand rien d'autre n'est en route ; sinon, seules la cible et
    /// sa règle en sont reprises — la réponse du dernier réglage en file
    /// remettra le reste d'accord.
    private func accept(_ updated: TripSettings) {
        guard queue.isEmpty, !isSending else {
            guard var current = settings else { return }
            if let pages = updated.customisation?.targetPageCount {
                current.customisation?.targetPageCount = pages
            }
            current.pageTarget = updated.pageTarget
            settings = current
            return
        }
        settings = updated
        clearError()
    }

    /// Passe la feuille à l'étape suivante — si elle est encore ouverte sur
    /// ce changement-là : refermée entre-temps, elle ne se rouvre pas.
    private func advance(_ change: PageTargetChange, to step: PageTargetChange.Step) {
        guard pageTargetChange?.id == change.id else { return }
        var next = change
        next.step = step
        next.isWorking = false
        next.errorMessage = nil
        pageTargetChange = next
    }

    /// « Étoffer / Condenser les étapes déjà écrites », sur la feuille ou
    /// par le lien du panneau — `POST /v1/trips/:id/page-target/rewrite`.
    ///
    /// Un 409 dit que c'est déjà fait (un co-voyageur, un autre téléphone) :
    /// le lien s'en va, sans erreur — ce qu'on demandait est en route.
    public func rewriteWrittenSteps() async {
        guard !isRewritingWrittenSteps else { return }
        isRewritingWrittenSteps = true
        defer { isRewritingWrittenSteps = false }
        let change = pageTargetChange
        if var working = change {
            working.isWorking = true
            working.errorMessage = nil
            pageTargetChange = working
        }

        do {
            if let rewrite {
                let updated = try await rewrite(tripId)
                settings?.pageTarget = updated.pageTarget
            } else {
                settings?.pageTarget?.rewriteAvailable = false
            }
            hasStartedRewrite = true
            if pageTargetChange?.id == change?.id { pageTargetChange = nil }
        } catch {
            if (error as? APIError)?.code == APIError.pageTargetRewriteUnavailableCode {
                settings?.pageTarget?.rewriteAvailable = false
                if pageTargetChange?.id == change?.id { pageTargetChange = nil }
                return
            }
            if var failed = change, pageTargetChange?.id == failed.id {
                failed.isWorking = false
                failed.errorMessage = error.localizedDescription
                pageTargetChange = failed
            } else {
                report(error)
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

/// Un changement de nombre de pages cible, tel que sa feuille le raconte.
///
/// **Une seule feuille, dont le contenu change** (`ios/CLAUDE.md`, « un
/// enchaînement de feuilles ne s'empile pas ») : l'identifiant reste le même
/// d'une étape à l'autre, si bien que la présentation ne se refait pas.
///
/// ```
/// palier touché ─→ .confirm  (ce qui reste de changements)
///                     │ Changer le nombre de pages cible
///                     ▼
///                  .stage    (sans date de fin seulement)
///                     │ début · moitié · fin
///                     ▼
///                  .done(stage) ─→ fin : étoffer / condenser l'écrit
///
/// 409 à l'envoi ─→ .limitReached (l'orange)
/// ```
public struct PageTargetChange: Identifiable, Hashable, Sendable {
    public enum Step: Hashable, Sendable {
        /// L'avertissement, avant tout envoi.
        case confirm(changesLeft: Int)
        /// « À quel stade de ton voyage en es-tu ? »
        case stage
        /// Le serveur a refusé : les deux changements sont faits.
        case limitReached
        /// C'est fait. Vers la fin, la feuille propose de réécrire l'écrit.
        case done(PageTargetTripStage)
    }

    public let id: UUID
    /// La cible d'avant, et celle qu'on demande.
    public let from: Int
    public let to: Int
    /// La durée du voyage au moment du geste : c'est elle qui nomme les
    /// récits (« récit compact »), comme les paliers du panneau.
    public let tripDays: Int?
    public var step: Step
    /// Un envoi part — le bouton de l'étape attend.
    public var isWorking = false
    /// L'envoi a raté pour une autre raison que la limite : dit sur la
    /// feuille, qui reste à son étape.
    public var errorMessage: String?

    public init(from: Int, to: Int, tripDays: Int?, step: Step) {
        self.id = UUID()
        self.from = from
        self.to = to
        self.tripDays = tripDays
        self.step = step
    }

    /// La cible monte : le récit s'étoffe. Sinon il se condense.
    public var isLonger: Bool { to > from }
}

private extension BookCustomisationEdit {
    /// Le champ que cette édition écrit : deux éditions du même champ en file,
    /// seule la dernière part. `.fontCombo` et `.rules` restent deux champs —
    /// l'un porte les polices, et la file les envoie dans l'ordre.
    var field: String {
        switch self {
        case .photoTextRatio: "photoTextRatio"
        case .targetPageCount: "targetPageCount"
        case .funFacts: "funFacts"
        case .rules: "rules"
        case .decorationQuota: "decorationQuota"
        case .fontDisplay: "fontDisplay"
        case .fontTitle: "fontTitle"
        case .fontHand: "fontHand"
        case .fontFacts: "fontFacts"
        case .fontCombo: "fontCombo"
        case .quiz: "quiz"
        case .freeZones: "freeZones"
        case .crossword: "crossword"
        }
    }
}
