import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Le **verrou des pointillés** dans l'écran des personnalisations : ce que le
/// modèle pose à l'écran, ce qu'il envoie, ce qu'il garde sur l'appareil.
///
/// La règle elle-même est testée dans `BookRulesLockTests` ; ici, on vérifie
/// qu'elle est appliquée et **envoyée** — après chaque geste, l'écran et le
/// serveur doivent dire la même chose.
@MainActor
final class BookCustomisationModelTests: XCTestCase {
    // MARK: Les deux assortiments contraints

    func testChoosingHandwrittenSendsFontsAndRulesInOneEdit() async throws {
        let (model, server, memory) = await open(rules: true)

        model.setFontCombo(.handwritten)

        // Posé à l'écran avant toute réponse.
        let shown = model.customisation
        XCTAssertEqual(shown?.rulesEnabled, false)
        XCTAssertTrue(model.areRulesLocked)
        XCTAssertTrue(model.isRulesSwitchLocked)
        try await settled(model, server, edits: 1, shown: shown)

        // **Une** édition, qui porte les cinq valeurs : le serveur ne passe
        // jamais par un Manuscrit aux pointillés allumés.
        XCTAssertEqual(server.received, [.fontCombo(.handwritten, rulesEnabled: false)])
        XCTAssertEqual(memory.read(Self.tripId), true)
        XCTAssertEqual(model.rulesWithdrawnBy, .handwritten)
    }

    func testChoosingEditorialLocksTheSwitchToo() async throws {
        let (model, server, memory) = await open(rules: true)

        try await act(model, server, edits: 1) { model.setFontCombo(.editorial) }

        XCTAssertEqual(server.received, [.fontCombo(.editorial, rulesEnabled: false)])
        XCTAssertTrue(model.areRulesLocked)
        XCTAssertEqual(memory.read(Self.tripId), true)
    }

    func testALockedSwitchCannotBeRelit() async throws {
        let (model, server, _) = await open(rules: true)
        try await act(model, server, edits: 1) { model.setFontCombo(.handwritten) }

        model.setRules(true)

        XCTAssertEqual(model.customisation?.rulesEnabled, false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(server.received.count, 1, "un rallumage verrouillé est parti au serveur")
    }

    func testTappingTheChosenComboAgainSendsNothing() async throws {
        // L'édition porterait les pointillés de l'écran : sur un écran resté
        // ouvert, elle rallumerait ceux qu'un co-voyageur vient d'éteindre.
        let (model, server, _) = await open(rules: true)

        model.setFontCombo(.travelJournal)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(server.attempts, 0)
    }

    // MARK: Le retour au défaut

    func testBackToDefaultRelightsRulesThatWereOn() async throws {
        let (model, server, memory) = await open(rules: true)
        try await act(model, server, edits: 1) { model.setFontCombo(.handwritten) }

        try await act(model, server, edits: 2) { model.setFontCombo(.travelJournal) }

        XCTAssertEqual(server.received.last, .fontCombo(.travelJournal, rulesEnabled: true))
        XCTAssertFalse(model.areRulesLocked)
        // Le verrou défait, il n'y a plus rien à rendre.
        XCTAssertNil(memory.read(Self.tripId))
    }

    func testBackToDefaultKeepsOffRulesThatWereOff() async throws {
        let (model, server, _) = await open(rules: false)
        try await act(model, server, edits: 1) { model.setFontCombo(.editorial) }
        // Rien n'a été retiré : pas de note sous les assortiments.
        XCTAssertNil(model.rulesWithdrawnBy)

        try await act(model, server, edits: 2) { model.setFontCombo(.travelJournal) }

        XCTAssertEqual(server.received.last, .fontCombo(.travelJournal, rulesEnabled: false))
    }

    func testARoundTripLeavesTheBookExactlyAsItWas() async throws {
        for rules in [true, false] {
            let (model, server, _) = await open(rules: rules)
            let before = model.customisation

            try await act(model, server, edits: 1) { model.setFontCombo(.handwritten) }
            try await act(model, server, edits: 2) { model.setFontCombo(.editorial) }
            try await act(model, server, edits: 3) { model.setFontCombo(.travelJournal) }

            XCTAssertEqual(model.customisation, before, "pointillés \(rules ? "allumés" : "éteints") au départ")
            XCTAssertEqual(server.settings.customisation, before)
        }
    }

    func testTheMemoryOutlivesTheScreen() async throws {
        // On verrouille, on ferme l'écran, on le rouvre plus tard : la mémoire
        // est sur l'appareil, pas dans le modèle.
        let memory = BookRulesMemory.inMemory()
        let server = Server(rules: false)

        let first = await open(server, memory)
        try await act(first, server, edits: 1) { first.setFontCombo(.handwritten) }

        let second = await open(server, memory)
        try await act(second, server, edits: 2) { second.setFontCombo(.travelJournal) }

        XCTAssertEqual(second.customisation?.rulesEnabled, false)
    }

    func testAFailedReturnToDefaultKeepsTheMemory() async throws {
        let (model, server, memory) = await open(rules: false)
        try await act(model, server, edits: 1) { model.setFontCombo(.handwritten) }

        server.isFailing = true
        model.setFontCombo(.travelJournal)
        // L'envoi échoue, l'écran relit : le carnet est encore verrouillé…
        try await waitUntil { server.attempts == 2 && model.areRulesLocked }
        // … et doit encore savoir quoi rendre au prochain essai.
        XCTAssertEqual(memory.read(Self.tripId), false)
        XCTAssertEqual(model.customisation, server.settings.customisation)
    }

    // MARK: Les envois, un par un

    func testANeighbouringSettingDoesNotUndoTheOneBefore() async throws {
        // Fun facts éteints, puis le quiz dans la foulée, pendant que le
        // serveur fait attendre la première requête. Annuler l'envoi des fun
        // facts laissait la réponse du quiz les rallumer — et l'aperçu bougeait
        // pour un réglage qu'il ne montre pas.
        let (model, server, _) = await open(rules: true)
        server.holdsNext = true

        model.setFunFacts(false)
        let shown = model.previewURL
        model.setQuiz(false)
        try await waitUntil { server.attempts == 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(server.attempts, 1, "le quiz est parti avant la réponse des fun facts")

        server.release()
        try await waitUntil { server.received.count == 2 && model.customisation == server.settings.customisation }

        XCTAssertEqual(server.received, [.funFacts(false), .quiz(false)])
        XCTAssertEqual(model.customisation?.funFactsEnabled, false)
        XCTAssertEqual(model.previewURL, shown)
    }

    func testASliderDragSendsItsFirstAndLastSteps() async throws {
        // Un cran part ; ceux qui suivent attendent sa réponse, et seul le
        // dernier part après elle.
        let (model, server, _) = await open(rules: true)
        server.holdsNext = true

        model.setPhotoTextRatio(25)
        try await waitUntil { server.attempts == 1 }
        model.setPhotoTextRatio(50)
        model.setPhotoTextRatio(75)

        server.release()
        try await waitUntil { server.received.count == 2 && model.customisation == server.settings.customisation }

        XCTAssertEqual(server.received, [.photoTextRatio(25), .photoTextRatio(75)])
        XCTAssertEqual(model.customisation?.photoTextRatio, 75)
    }

    func testAFailedSettingDoesNotTakeTheNextOnesWithIt() async throws {
        // Les fun facts échouent pendant que le quiz attend derrière : le quiz
        // part quand même, et l'écran finit sur ce que le serveur a vraiment.
        let (model, server, _) = await open(rules: true)
        let funFacts = !(model.customisation?.funFactsEnabled ?? true)
        let quiz = !(model.customisation?.quizEnabled ?? true)
        server.holdsNext = true
        server.failsNext = true

        model.setFunFacts(funFacts)
        try await waitUntil { server.attempts == 1 }
        model.setQuiz(quiz)
        server.release()

        try await waitUntil { server.received.count == 1 && model.customisation == server.settings.customisation }
        XCTAssertEqual(server.received, [.quiz(quiz)])
        XCTAssertEqual(model.customisation?.quizEnabled, quiz)
        XCTAssertEqual(model.customisation?.funFactsEnabled, !funFacts, "le réglage raté reste affiché")
    }

    func testAGestureDuringTheRereadAfterAFailureIsSent() async throws {
        // L'envoi échoue, l'écran relit le serveur — lentement — et le
        // voyageur touche au quiz pendant ce temps. Le geste restait en file
        // sans partir, et la relecture l'effaçait de l'écran.
        let (model, server, _) = await open(rules: true)
        let quiz = !(model.customisation?.quizEnabled ?? true)
        server.failsNext = true
        server.holdsNextRead = true

        model.setFunFacts(!(model.customisation?.funFactsEnabled ?? true))
        try await waitUntil { server.attempts == 1 && server.reads == 2 }
        model.setQuiz(quiz)
        server.releaseRead()

        try await waitUntil { server.received.count == 1 && model.customisation == server.settings.customisation }
        XCTAssertEqual(server.received, [.quiz(quiz)])
        XCTAssertEqual(model.customisation?.quizEnabled, quiz)
    }

    func testARereadDoesNotUndoASettingOnItsWay() async throws {
        // « Réessayer », ou l'écran qui réapparaît, relit le serveur pendant
        // qu'un envoi attend sa réponse : la lecture est d'avant le geste.
        let (model, server, _) = await open(rules: true)
        let quiz = !(model.customisation?.quizEnabled ?? true)
        server.holdsNext = true

        model.setQuiz(quiz)
        try await waitUntil { server.attempts == 1 }
        await model.load()
        XCTAssertEqual(model.customisation?.quizEnabled, quiz, "la relecture a défait le geste")

        server.release()
        try await settled(model, server, edits: 1, shown: model.customisation)
    }

    // MARK: Les carnets d'avant le verrou

    func testABookLockedBeforeTheLockIsPutBackInLineOnOpening() async throws {
        let server = Server(rules: true, combo: .handwritten)
        let memory = BookRulesMemory.inMemory()

        let model = await open(server, memory)
        // Éteints à l'écran dès l'ouverture, avant la réponse.
        let shown = model.customisation
        XCTAssertEqual(shown?.rulesEnabled, false)

        try await settled(model, server, edits: 1, shown: shown)
        XCTAssertEqual(server.received, [.rules(false)])
        XCTAssertEqual(memory.read(Self.tripId), true)

        // Et le retour au défaut rend ce qu'ils étaient.
        try await act(model, server, edits: 2) { model.setFontCombo(.travelJournal) }
        XCTAssertEqual(model.customisation?.rulesEnabled, true)
    }

    func testAFailedNormalisationIsNotRetriedForever() async throws {
        // La relecture qui suit un envoi raté ne remet rien dans le rang :
        // sinon, un serveur qui refuse ferait tourner l'écran en boucle.
        let server = Server(rules: true, combo: .editorial)
        server.isFailing = true

        _ = await open(server, .inMemory())

        try await waitUntil { server.attempts >= 1 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(server.attempts, 1)
    }

    func testRulesLeftOnUnderALockCanStillBeTurnedOff() async throws {
        // La remise dans le rang a échoué : ce Manuscrit imprimera ses
        // pointillés. L'interrupteur ne doit ni pâlir ni dire le contraire —
        // le verrou interdit de les rallumer, pas de les éteindre.
        let server = Server(rules: true, combo: .handwritten)
        server.isFailing = true
        let model = await open(server, .inMemory())
        try await waitUntil { server.attempts == 1 && model.customisation?.rulesEnabled == true }

        XCTAssertTrue(model.areRulesLocked)
        XCTAssertFalse(model.isRulesSwitchLocked)

        server.isFailing = false
        try await act(model, server, edits: 1) { model.setRules(false) }
        XCTAssertTrue(model.isRulesSwitchLocked)
    }

    func testOpeningAnUnlockedBookForgetsAStaleMemory() async throws {
        // Le verrou a été défait ailleurs — un co-voyageur est revenu au
        // défaut : la mémoire de ce téléphone ne sert plus.
        let memory = BookRulesMemory.inMemory()
        memory.write(Self.tripId, false)

        _ = await open(Server(rules: true), memory)

        XCTAssertNil(memory.read(Self.tripId))
    }

    // MARK: Ce que l'écran dit

    func testTheWithdrawnNoticeLastsOneGesture() async throws {
        let (model, server, _) = await open(rules: true)
        model.setFontCombo(.handwritten)
        XCTAssertEqual(model.rulesWithdrawnBy, .handwritten)
        try await settled(model, server, edits: 1, shown: model.customisation)

        model.setPhotoTextRatio(75)

        XCTAssertNil(model.rulesWithdrawnBy)
    }

    func testTheLockNoticeAnswersATapAndLeavesWithTheLock() async throws {
        let (model, server, _) = await open(rules: true)
        try await act(model, server, edits: 1) { model.setFontCombo(.handwritten) }
        XCTAssertFalse(model.showsRulesLockNotice, "la note répond à un appui, pas au verrou")

        model.explainRulesLock()
        XCTAssertTrue(model.showsRulesLockNotice)

        try await act(model, server, edits: 2) { model.setFontCombo(.travelJournal) }
        XCTAssertFalse(model.showsRulesLockNotice)

        // Reverrouillé, elle ne revient pas d'elle-même.
        try await act(model, server, edits: 3) { model.setFontCombo(.editorial) }
        XCTAssertFalse(model.showsRulesLockNotice)
    }

    func testAFailedChoiceTakesTheNoticeAway() async throws {
        // L'envoi de Manuscrit échoue, l'écran relit Carnet de voyage aux
        // pointillés allumés : « on les a retirés » serait faux.
        let (model, server, _) = await open(rules: true)
        server.isFailing = true

        model.setFontCombo(.handwritten)
        XCTAssertEqual(model.rulesWithdrawnBy, .handwritten)
        try await waitUntil { server.attempts == 1 && !model.areRulesLocked }

        XCTAssertNil(model.rulesWithdrawnBy)
        XCTAssertEqual(model.customisation?.rulesEnabled, true)
    }

    // MARK: La mémoire de l'app

    func testTheDeviceMemoryIsKeptPerTripAndForgotten() throws {
        let suite = "BookRulesMemoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = BookRulesMemory.device(defaults)

        memory.write("trip-a", false)
        memory.write("trip-b", true)

        // Relue par une autre instance, comme à la prochaine ouverture.
        let reopened = BookRulesMemory.device(defaults)
        XCTAssertEqual(reopened.read("trip-a"), false)
        XCTAssertEqual(reopened.read("trip-b"), true)
        XCTAssertNil(reopened.read("trip-c"))

        reopened.write("trip-a", nil)
        XCTAssertNil(memory.read("trip-a"))
        XCTAssertEqual(memory.read("trip-b"), true)
    }

    // MARK: Outils

    private static let tripId = "trip-rome"

    /// Le serveur, en mémoire : il applique chaque édition comme la route
    /// `PATCH /v1/trips/:id/settings`, et rend ce qu'il a.
    @MainActor
    private final class Server {
        var settings: TripSettings
        private(set) var received: [BookCustomisationEdit] = []
        private(set) var attempts = 0
        var isFailing = false
        /// La prochaine requête échoue, et elle seule.
        var failsNext = false
        /// La prochaine requête attend ``release()`` avant d'être traitée :
        /// une connexion lente, ou un pooler qui fait patienter.
        var holdsNext = false
        private var held: CheckedContinuation<Void, Never>?
        /// La prochaine lecture attend ``releaseRead()`` : une relecture
        /// lente, pendant laquelle le voyageur continue de régler.
        var holdsNextRead = false
        private(set) var reads = 0
        private var heldRead: CheckedContinuation<Void, Never>?

        init(rules: Bool, combo: BookFontCombo = .travelJournal) {
            var customisation = BookCustomisation.fixture
            customisation.rulesEnabled = rules
            for role in BookFontRole.allCases {
                customisation[keyPath: role.keyPath] = combo.font(role)
            }
            settings = .fixture
            settings.customisation = customisation
        }

        func release() {
            held?.resume()
            held = nil
        }

        func releaseRead() {
            heldRead?.resume()
            heldRead = nil
        }

        /// `GET /v1/trips/:id/settings` : ce que le serveur a **au moment où
        /// la lecture part** — une lecture retenue rend un état d'avant.
        func read() async -> TripSettings {
            reads += 1
            let snapshot = settings
            if holdsNextRead {
                holdsNextRead = false
                await withCheckedContinuation { heldRead = $0 }
            }
            return snapshot
        }

        func patch(_ edit: BookCustomisationEdit) async throws -> TripSettings {
            attempts += 1
            if holdsNext {
                holdsNext = false
                await withCheckedContinuation { held = $0 }
            }
            if isFailing { throw Refused() }
            if failsNext {
                failsNext = false
                throw Refused()
            }
            received.append(edit)
            var customisation = settings.customisation ?? .fixture
            switch edit {
            case .photoTextRatio(let value): customisation.photoTextRatio = value
            case .targetPageCount(let value): customisation.targetPageCount = value
            case .funFacts(let isOn): customisation.funFactsEnabled = isOn
            case .rules(let isOn): customisation.rulesEnabled = isOn
            case .decorationQuota(let value): customisation.decorationQuota = value
            case .fontDisplay(let value): customisation.fontDisplay = value
            case .fontTitle(let value): customisation.fontTitle = value
            case .fontHand(let value): customisation.fontHand = value
            case .fontFacts(let value): customisation.fontFacts = value
            case .fontCombo(let combo, let rules):
                for role in BookFontRole.allCases {
                    customisation[keyPath: role.keyPath] = combo.font(role)
                }
                customisation.rulesEnabled = rules
            case .quiz(let isOn): customisation.quizEnabled = isOn
            case .freeZones(let isOn): customisation.freeZonesEnabled = isOn
            case .crossword(let isOn): customisation.crosswordEnabled = isOn
            }
            settings.customisation = customisation
            return settings
        }

        struct Refused: Error {}
    }

    private func open(
        rules: Bool
    ) async -> (BookCustomisationModel, Server, BookRulesMemory) {
        let server = Server(rules: rules)
        let memory = BookRulesMemory.inMemory()
        return (await open(server, memory), server, memory)
    }

    private func open(_ server: Server, _ memory: BookRulesMemory) async -> BookCustomisationModel {
        let model = BookCustomisationModel(
            tripId: Self.tripId,
            source: { _ in await server.read() },
            persist: { _, edit in try await server.patch(edit) },
            rulesMemory: memory
        )
        await model.load()
        return model
    }

    /// Fait le geste, garde ce que l'écran montre **aussitôt** — avant toute
    /// réponse —, puis attend le serveur et vérifie qu'il a reçu exactement
    /// cet état.
    private func act(
        _ model: BookCustomisationModel,
        _ server: Server,
        edits: Int,
        _ gesture: () -> Void
    ) async throws {
        gesture()
        try await settled(model, server, edits: edits, shown: model.customisation)
    }

    /// Attend que le serveur ait reçu `edits` éditions et que l'écran ait relu
    /// sa réponse, puis compare ce que le serveur a **reçu** à ce que l'écran
    /// montrait avant de la relire : après la relecture, les deux sont égaux
    /// par construction, et la comparaison ne prouverait rien.
    private func settled(
        _ model: BookCustomisationModel,
        _ server: Server,
        edits: Int,
        shown: BookCustomisation?
    ) async throws {
        try await waitUntil {
            server.received.count == edits && model.customisation == server.settings.customisation
        }
        XCTAssertEqual(server.settings.customisation, shown, "le serveur a reçu autre chose que ce que l’écran montrait")
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Condition non remplie en \(timeout)")
                throw TimedOut()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct TimedOut: Error {}
}

/// Le **changement de nombre de pages cible** (Hugo, 15/10/2026) : libre tant
/// qu'aucune étape n'est écrite, puis deux fois par voyage, chaque fois à
/// travers la feuille ``PageTargetChangeSheet`` — avertissement, stade du
/// voyage, puis ce qui est fait.
@MainActor
final class BookPageTargetChangeTests: XCTestCase {
    // MARK: La durée du voyage

    func testWithoutEndDateTheTripHasNoDuration() async {
        let (model, _) = await open(PageServer(allowance: nil, endDate: nil))
        XCTAssertNil(model.tripDays, "sans date de fin, le voyage durait un jour et le palier par défaut tombait à 30")
        XCTAssertEqual(BookPageTarget.standard.pageCount(forTripDays: model.tripDays), 60)
    }

    // MARK: Avant la première étape écrite

    func testAChangeBeforeAnyStoryIsSentSilently() async throws {
        let (model, server) = await open(PageServer(allowance: PageTargetAllowance(changesCount: false)))

        model.setTargetPageCount(80)

        XCTAssertNil(model.pageTargetChange)
        XCTAssertEqual(model.customisation?.targetPageCount, 80)
        try await waitUntil { server.patches == [80] }
    }

    // MARK: Un changement qui compte

    func testACountedChangeAsksFirstAndCancellingChangesNothing() async throws {
        let (model, server) = await open(PageServer(allowance: PageTargetAllowance(changesLeft: 2, changesCount: true)))

        model.setTargetPageCount(80)

        XCTAssertEqual(model.pageTargetChange?.step, .confirm(changesLeft: 2))
        XCTAssertEqual(model.customisation?.targetPageCount, 60, "la cible a bougé avant la confirmation")

        model.dismissPageTargetChange()

        XCTAssertNil(model.pageTargetChange)
        XCTAssertEqual(model.customisation?.targetPageCount, 60)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(server.patches.isEmpty)
    }

    func testConfirmingNearTheEndSavesAndOffersTheRewrite() async throws {
        // Le jeu d'essai finit le 15/09/2026 : le 15/10, le voyage est fini.
        let (model, server) = await open(
            PageServer(allowance: PageTargetAllowance(changesLeft: 2, changesCount: true)),
            today: Self.day(15, 10)
        )
        model.setTargetPageCount(80)

        model.confirmPageTargetChange()

        try await waitUntil { model.pageTargetChange?.step == .done(.end) }
        XCTAssertEqual(server.patches, [80])
        XCTAssertEqual(model.customisation?.targetPageCount, 80)
        XCTAssertEqual(model.pageTargetAllowance.changesLeft, 1)
        XCTAssertTrue(model.pageTargetChange?.isLonger == true)

        await model.rewriteWrittenSteps()

        XCTAssertEqual(server.rewrites, 1)
        XCTAssertNil(model.pageTargetChange)
        XCTAssertTrue(model.hasStartedRewrite)
        XCTAssertFalse(model.offersRewrite)
    }

    func testEarlyInTheTripTheSheetEndsWithoutRewrite() async throws {
        let (model, _) = await open(
            PageServer(allowance: PageTargetAllowance(changesLeft: 1, changesCount: true)),
            today: Self.day(28, 8)
        )
        model.setTargetPageCount(40)
        XCTAssertEqual(model.pageTargetChange?.step, .confirm(changesLeft: 1))

        model.confirmPageTargetChange()

        try await waitUntil { model.pageTargetChange?.step == .done(.beginningOrMiddle) }
        XCTAssertEqual(model.pageTargetChange?.isLonger, false)
    }

    func testWithoutEndDateTheSheetAsksTheStage() async throws {
        let (model, server) = await open(
            PageServer(allowance: PageTargetAllowance(changesLeft: 2, changesCount: true), endDate: nil)
        )
        model.setTargetPageCount(80)

        model.confirmPageTargetChange()

        XCTAssertEqual(model.pageTargetChange?.step, .stage)
        XCTAssertTrue(server.patches.isEmpty, "on envoie avant de savoir où en est le voyage")

        model.choosePageTargetStage(.end)

        try await waitUntil { model.pageTargetChange?.step == .done(.end) }
        XCTAssertEqual(server.patches, [80])
    }

    // MARK: La limite

    func testNoChangeLeftSendsNothingAndExplains() async throws {
        let (model, server) = await open(PageServer(allowance: PageTargetAllowance(changesLeft: 0, changesCount: true)))
        XCTAssertTrue(model.isPageTargetLocked)

        model.setTargetPageCount(80)

        XCTAssertNil(model.pageTargetChange)
        XCTAssertTrue(model.showsPageTargetLimitNotice)
        XCTAssertEqual(model.customisation?.targetPageCount, 60)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(server.patches.isEmpty)
    }

    func testARefusalMovesTheSheetToTheLimit() async throws {
        // L'écran croit qu'il reste un changement ; un co-voyageur l'a pris.
        let server = PageServer(allowance: PageTargetAllowance(changesLeft: 1, changesCount: true))
        let (model, _) = await open(server, today: Self.day(15, 10))
        server.refusesWithLimit = true
        model.setTargetPageCount(80)

        model.confirmPageTargetChange()

        try await waitUntil { model.pageTargetChange?.step == .limitReached }
        try await waitUntil { model.isPageTargetLocked }
        XCTAssertEqual(model.customisation?.targetPageCount, 60)
        XCTAssertNil(model.errorMessage, "un refus de la limite n'est pas une panne")
    }

    // MARK: Outils

    private func open(
        _ server: PageServer,
        today: Date = BookPageTargetChangeTests.day(15, 10)
    ) async -> (BookCustomisationModel, PageServer) {
        let model = BookCustomisationModel(
            tripId: "trip-rome",
            source: { _ in server.settings },
            persist: { _, edit in try server.patch(edit) },
            rewrite: { _ in try server.rewrite() },
            today: { today }
        )
        await model.load()
        return (model, server)
    }

    private static func day(_ day: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)) ?? .now
    }

    /// Le serveur de la règle des deux changements, en mémoire — comme
    /// `services/pageTarget.ts`.
    @MainActor
    private final class PageServer {
        var settings: TripSettings
        private(set) var patches: [Int] = []
        private(set) var rewrites = 0
        var refusesWithLimit = false

        init(allowance: PageTargetAllowance?, endDate: Date? = TripSettings.fixture.endDate) {
            settings = .fixture
            settings.endDate = endDate
            settings.pageTarget = allowance
            settings.customisation?.targetPageCount = 60
        }

        func patch(_ edit: BookCustomisationEdit) throws -> TripSettings {
            guard case .targetPageCount(let pages) = edit else { return settings }
            var allowance = settings.pageTargetAllowance
            if allowance.changesCount {
                if refusesWithLimit {
                    allowance.changesLeft = 0
                    settings.pageTarget = allowance
                    throw APIError.server(statusCode: 409, code: APIError.pageTargetLimitReachedCode, message: "Limite")
                }
                allowance.changesLeft -= 1
                allowance.rewriteAvailable = true
                settings.pageTarget = allowance
            }
            patches.append(pages)
            settings.customisation?.targetPageCount = pages
            return settings
        }

        func rewrite() throws -> TripSettings {
            rewrites += 1
            settings.pageTarget?.rewriteAvailable = false
            return settings
        }
    }

    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Condition non remplie en \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
