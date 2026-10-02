import MemoBookCore
@testable import MemoBookFeature
import UIKit
import XCTest

/// L'aperçu de personnalisation en tête de l'écran : quelle image, quand elle
/// change, et ce qui reste à l'écran pendant qu'elle arrive — ou n'arrive pas.
@MainActor
final class BookCustomisationPreviewLoaderTests: XCTestCase {
    // MARK: L'adresse suit cinq réglages, et cinq seulement

    func testTheAddressIgnoresTheFourSettingsOutsideThePreview() async {
        let model = await openedModel()
        let opening = model.previewURL
        XCTAssertNotNil(opening)

        model.setTargetPageCount(120)
        model.setQuiz(false)
        model.setFreeZones(false)
        model.setCrossword(false)

        XCTAssertEqual(model.previewURL, opening, "l’image se rechargerait pour un réglage qu’elle ne montre pas")
    }

    func testTheAddressFollowsEachOfTheFiveSettings() async {
        let gestures: [(String, (BookCustomisationModel) -> Void)] = [
            ("pointillés", { $0.setRules(false) }),
            ("ratio", { $0.setPhotoTextRatio(75) }),
            ("fun facts", { $0.setFunFacts(false) }),
            ("stickers", { $0.setDecorationQuota(4) }),
            ("typographie", { $0.setFontCombo(.editorial) }),
        ]
        for (setting, gesture) in gestures {
            let model = await openedModel()
            let opening = model.previewURL
            gesture(model)
            XCTAssertNotEqual(model.previewURL, opening, setting)
        }
    }

    func testTheOpeningAddressIsTheDefaultPreview() async {
        let model = await openedModel()
        XCTAssertEqual(model.previewURL, BookCustomisationPreview.imageURL(for: BookCustomisation()))
    }

    // MARK: Ce que la tête montre

    func testTheOpeningImageArrivesWithoutWaiting() async {
        // Une attente de cinq secondes, qu'on mesure : la première image ne
        // doit pas la faire.
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(settle: .seconds(5), fetch: downloads.fetch)
        let clock = ContinuousClock()
        let start = clock.now

        await loader.show(Self.url(0))

        XCTAssertLessThan(clock.now - start, .seconds(1))
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(0)))
        XCTAssertEqual(loader.shownURL, Self.url(0))
    }

    func testNothingIsShownBeforeTheSettingsAreRead() async {
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(fetch: downloads.fetch)

        await loader.show(nil)

        XCTAssertNil(loader.image)
        XCTAssertEqual(downloads.requested, [])
    }

    func testASliderDragOnlyLoadsWhereItStops() async {
        // Le ratio glisse de 0 à 75 % : quatre crans en rafale. Comme
        // `.task(id:)`, chaque cran annule le précédent ; seul le dernier
        // arrive au bout de son attente.
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(settle: .milliseconds(150), fetch: downloads.fetch)
        let screen = Screen(loader)
        await screen.change(to: Self.url(0)).value

        screen.change(to: Self.url(25))
        screen.change(to: Self.url(50))
        await screen.change(to: Self.url(75)).value

        XCTAssertEqual(downloads.requested, [Self.url(0), Self.url(75)])
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(75)))
    }

    func testASlowDragAtTheRealPaceOnlyLoadsWhereItStops() async throws {
        // Le même glissé, à l'attente de l'app et à un cran toutes les 80 ms —
        // un doigt qui traverse le curseur. Une attente trop courte ferait
        // charger les crans du milieu.
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(fetch: downloads.fetch)
        let screen = Screen(loader)
        await screen.change(to: Self.url(0)).value

        screen.change(to: Self.url(25))
        try await Task.sleep(for: .milliseconds(80))
        screen.change(to: Self.url(50))
        try await Task.sleep(for: .milliseconds(80))
        await screen.change(to: Self.url(75)).value

        XCTAssertEqual(downloads.requested, [Self.url(0), Self.url(75)])
    }

    func testADragOnBarePaperOnlyLoadsWhereItStops() async throws {
        // L'ouverture a échoué : la tête est le papier nu. Un glissé qui suit
        // ne doit pas en profiter pour charger chaque cran.
        let downloads = Downloads()
        downloads.failing = [Self.url(0)]
        let loader = BookCustomisationPreviewLoader(fetch: downloads.fetch)
        let screen = Screen(loader)
        await screen.change(to: Self.url(0)).value
        XCTAssertNil(loader.image)

        screen.change(to: Self.url(25))
        try await Task.sleep(for: .milliseconds(80))
        screen.change(to: Self.url(50))
        try await Task.sleep(for: .milliseconds(80))
        await screen.change(to: Self.url(75)).value

        XCTAssertEqual(downloads.requested, [Self.url(0), Self.url(75)])
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(75)))
    }

    func testThePreviousImageStaysUntilTheNextIsReady() async throws {
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(settle: .milliseconds(10), fetch: downloads.fetch)
        let screen = Screen(loader)
        await screen.change(to: Self.url(0)).value

        downloads.hold(Self.url(25))
        let task = screen.change(to: Self.url(25))
        try await waitUntil { downloads.requested.contains(Self.url(25)) }

        // Elle se télécharge : la tête montre toujours la précédente, pas le
        // papier nu.
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(0)))

        downloads.release(Self.url(25))
        await task.value
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(25)))
    }

    func testAFailureKeepsWhatIsShownAndIsRetriedLater() async {
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(settle: .milliseconds(10), fetch: downloads.fetch)
        let screen = Screen(loader)
        await screen.change(to: Self.url(0)).value

        downloads.failing = [Self.url(25)]
        await screen.change(to: Self.url(25)).value
        XCTAssertEqual(loader.shownURL, Self.url(0))
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(0)), "un échec a vidé la tête")

        // Le réseau revient ; le réglage suivant redemande l'image.
        downloads.failing = []
        await screen.change(to: Self.url(50)).value
        await screen.change(to: Self.url(25)).value
        XCTAssertTrue(loader.image === downloads.image(for: Self.url(25)))
    }

    func testAFailureAtOpeningLeavesThePaper() async {
        let downloads = Downloads()
        downloads.failing = [Self.url(0)]
        let loader = BookCustomisationPreviewLoader(fetch: downloads.fetch)

        await loader.show(Self.url(0))

        XCTAssertNil(loader.image)
    }

    func testARecentImageIsNotDownloadedAgain() async {
        let downloads = Downloads()
        let loader = BookCustomisationPreviewLoader(settle: .milliseconds(10), fetch: downloads.fetch)
        let screen = Screen(loader)

        await screen.change(to: Self.url(0)).value
        await screen.change(to: Self.url(25)).value
        await screen.change(to: Self.url(0)).value

        XCTAssertEqual(downloads.requested, [Self.url(0), Self.url(25)])
        XCTAssertEqual(loader.shownURL, Self.url(0))
    }

    // MARK: Outils

    private static func url(_ ratio: Int) -> URL {
        URL(string: "https://apercus.test/\(ratio).webp")!
    }

    private func openedModel() async -> BookCustomisationModel {
        let model = BookCustomisationModel(tripId: "trip-rome", source: { _ in .fixture })
        await model.load()
        return model
    }

    /// Ce que fait `.task(id:)` : une nouvelle adresse annule la tâche en
    /// cours et en lance une autre.
    @MainActor
    private final class Screen {
        private let loader: BookCustomisationPreviewLoader
        private var current: Task<Void, Never>?

        init(_ loader: BookCustomisationPreviewLoader) { self.loader = loader }

        @discardableResult
        func change(to url: URL) -> Task<Void, Never> {
            current?.cancel()
            let task = Task { [loader] in await loader.show(url) }
            current = task
            return task
        }
    }

    /// Les téléchargements, que le test fait échouer ou retient.
    @MainActor
    private final class Downloads {
        private(set) var requested: [URL] = []
        var failing: Set<URL> = []
        private var held: Set<URL> = []
        private var waiting: [URL: CheckedContinuation<Void, Never>] = [:]
        private var images: [URL: UIImage] = [:]

        /// Une image par adresse, toujours la même : on les compare par
        /// identité.
        func image(for url: URL) -> UIImage {
            if let image = images[url] { return image }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
            images[url] = image
            return image
        }

        func fetch(_ url: URL) async throws -> UIImage {
            requested.append(url)
            if held.contains(url) {
                await withCheckedContinuation { waiting[url] = $0 }
            }
            if failing.contains(url) { throw URLError(.notConnectedToInternet) }
            return image(for: url)
        }

        func hold(_ url: URL) { held.insert(url) }

        func release(_ url: URL) {
            held.remove(url)
            waiting.removeValue(forKey: url)?.resume()
        }
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
