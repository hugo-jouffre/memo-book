import MemoBookCore
import Network
import PDFKit
import UIKit
import XCTest

@testable import MemoBookFeature

/// **Le carnet composé reste sur le téléphone** (T299, Hugo, 08/11/2026 —
/// « l'aperçu ne doit pas se remettre en page à chaque ouverture ; la dernière
/// version est gardée sur le téléphone, donc lisible sans réseau, et un bouton
/// à flèche tournante la régénère »).
///
/// La composition, elle, ne se relançait déjà plus pour rien : l'empreinte du
/// carnet le dit depuis T224, et T258 l'a posée au bon moment. Ce qui restait
/// était le **transfert** — plusieurs mégaoctets avant la première page, à
/// chaque ouverture, et rien du tout sans réseau.
@MainActor
final class BookKeptOnPhoneTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "book-kept-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Un vrai PDF, de `pages` pages : c'est PDFKit qui le relira, et il
    /// refuse tout ce qui n'en est pas un.
    private func pdf(pages: Int = 3) -> Data {
        let page = CGRect(x: 0, y: 0, width: 420, height: 595)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for numero in 1...pages {
                context.beginPage()
                ("Page \(numero)" as NSString).draw(
                    at: CGPoint(x: 40, y: 40),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
                )
            }
        }
    }

    // MARK: Ce que le magasin garde

    func testAKeptBookComesBackWithTheRenderItShows() async {
        let store = BookDocumentStore(directory: directory)
        let hier = Date(timeIntervalSince1970: 1_764_000_000)

        await store.keep(pdf(), renderId: "render-7", for: "memo-1", at: hier)

        let garde = await store.kept(for: "memo-1")
        XCTAssertEqual(garde?.renderId, "render-7")
        XCTAssertEqual(garde?.keptAt, hier)
        XCTAssertNotNil(garde?.data)
        let autre = await store.kept(for: "memo-2")
        XCTAssertNil(autre, "Un carnet est gardé par voyage : celui-ci n'a rien.")
    }

    /// **Un PDF sans sa fiche ne compte pas.** On ne saurait pas de quel rendu
    /// il vient, donc ni s'il est à jour, ni de quand il date : autant le
    /// retélécharger.
    func testAKeptBookWithoutItsCardIsRefused() async {
        let store = BookDocumentStore(directory: directory)
        await store.keep(pdf(), renderId: "render-7", for: "memo-1")

        let fiche = directory.appending(path: "book-\(cacheFilenameDigest("memo-1")).json")
        try? FileManager.default.removeItem(at: fiche)

        let garde = await store.kept(for: "memo-1")
        XCTAssertNil(garde)
    }

    /// À la déconnexion : ce sont les voyages de quelqu'un.
    func testEverythingGoesOnSignOut() async {
        let store = BookDocumentStore(directory: directory)
        await store.keep(pdf(), renderId: "render-7", for: "memo-1")

        await store.clearAll()

        let garde = await store.kept(for: "memo-1")
        XCTAssertNil(garde)
    }

    // MARK: Ce que l'écran en fait

    private func model(
        _ reponses: [BookPreview],
        store: BookDocumentStore? = nil
    ) -> BookPreviewModel {
        var restantes = reponses
        let model = BookPreviewModel(
            memoId: "memo-1",
            source: { _ in
                guard !restantes.isEmpty else { throw Injoignable() }
                return restantes.removeFirst()
            },
            startComposition: { _ in }
        )
        model.documents = store
        #if DEBUG
            // Ces tests regardent l'écran livré : pas de pages blanches de
            // debug par-dessus un carnet gardé.
            model.opensBlankPages = false
        #endif
        return model
    }

    private struct Injoignable: Error {}

    /// Un carnet que le serveur annonce prêt, du rendu qu'on garde. **Son
    /// `pdfUrl` ne mène nulle part** : si l'app le téléchargeait, le test le
    /// verrait tout de suite.
    private func annonce(render: String) -> BookPreview {
        BookPreview(
            memoId: "memo-1",
            title: "Rome",
            status: .ready,
            pdfUrl: URL(string: "http://127.0.0.1:1/jamais.pdf"),
            pageCount: 3,
            readyRenderId: render,
            isUpToDate: true
        )
    }

    /// **Le cœur du ticket** : le serveur annonce le rendu qu'on a déjà, et
    /// rien ne se télécharge.
    func testTheAnnouncedRenderWeAlreadyHaveIsNotDownloadedAgain() async {
        let store = BookDocumentStore(directory: directory)
        await store.keep(pdf(pages: 3), renderId: "render-7", for: "memo-1")
        let model = model([annonce(render: "render-7")], store: store)

        await model.run()

        XCTAssertEqual(model.stage, .preview)
        XCTAssertEqual(model.sheetCount, 3, "Les pages sont celles du carnet gardé.")
        XCTAssertFalse(
            model.renderer.didFail,
            "Un téléchargement aurait échoué sur cette adresse : il n'a pas eu lieu."
        )
        XCTAssertNil(model.notice, "Le carnet est confirmé par le serveur : rien à dire.")
    }

    /// Et la comparaison n'est pas « ne jamais télécharger » : un autre rendu
    /// se va chercher.
    func testAnotherAnnouncedRenderIsFetched() async {
        let store = BookDocumentStore(directory: directory)
        await store.keep(pdf(pages: 3), renderId: "render-7", for: "memo-1")
        let model = model([annonce(render: "render-8")], store: store)

        await model.run()

        XCTAssertTrue(
            model.renderer.didFail,
            "Le serveur annonce un carnet plus récent : l'app est allée le chercher."
        )
    }

    /// **« Donc lisible sans réseau »** : le serveur ne répond pas, et le
    /// carnet s'ouvre quand même.
    func testTheKeptBookOpensWithoutNetwork() async {
        let store = BookDocumentStore(directory: directory)
        let hier = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        await store.keep(pdf(pages: 5), renderId: "render-7", for: "memo-1", at: hier)
        let model = model([], store: store)

        await model.run()

        XCTAssertEqual(model.stage, .preview)
        XCTAssertEqual(model.sheetCount, 5)
        XCTAssertNil(
            model.errorMessage,
            "Il n'y a pas d'erreur à montrer : il y a un carnet, et une version à nommer."
        )
        XCTAssertEqual(model.notice?.message, BookCopy.Preview.keptVersion(hier))
        XCTAssertEqual(
            model.notice?.answersAGesture,
            false,
            "C'est l'état des choses, au beige de la marque."
        )
        XCTAssertTrue(model.canShare, "Le PDF est en main : il se partage, réseau ou pas.")
    }

    /// Sans carnet gardé, rien ne change : l'écran dit la panne, comme avant.
    func testWithoutAKeptBookTheFailureIsStillSaid() async {
        let model = model([], store: BookDocumentStore(directory: directory))

        await model.run()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertNotEqual(model.stage, .preview)
    }

    /// Un carnet téléchargé est gardé pour la prochaine fois.
    func testADownloadedBookIsKept() async throws {
        let store = BookDocumentStore(directory: directory)
        let serveur = try PdfServer(pdf(pages: 2))
        defer { serveur.stop() }

        let model = model(
            [
                BookPreview(
                    memoId: "memo-1",
                    title: "Rome",
                    status: .ready,
                    pdfUrl: serveur.url,
                    pageCount: 2,
                    readyRenderId: "render-9",
                    isUpToDate: true
                )
            ],
            store: store
        )

        await model.run()

        XCTAssertEqual(model.sheetCount, 2)
        let garde = await store.kept(for: "memo-1")
        XCTAssertEqual(garde?.renderId, "render-9")
    }

    // MARK: La flèche

    /// Rien n'a changé : le serveur rend le carnet qu'on a, et le geste reçoit
    /// une réponse — sans elle, une flèche qui tourne une seconde se lirait
    /// comme une panne.
    func testTheArrowSaysWhenThereWasNothingToRegenerate() async {
        let store = BookDocumentStore(directory: directory)
        await store.keep(pdf(), renderId: "render-7", for: "memo-1")
        let model = model(
            [annonce(render: "render-7"), annonce(render: "render-7")],
            store: store
        )
        await model.run()

        await model.regenerate()

        XCTAssertTrue(model.isAlreadyUpToDate)
        XCTAssertEqual(model.notice?.message, BookCopy.Preview.alreadyUpToDate)
        XCTAssertEqual(model.notice?.answersAGesture, true, "C'est la réponse à un appui.")
        XCTAssertFalse(model.isRefreshing)
    }

    /// Et quand le serveur en lance une, la flèche **suit** la composition au
    /// lieu de dire que tout va bien.
    ///
    /// Le bandeau « On remet à jour ton carnet… » n'est pas vérifié ici : il
    /// est transitoire, et ``regenerate()`` ne rend la main qu'une fois la
    /// composition terminée — ce qui est précisément ce qu'on veut d'elle.
    func testTheArrowFollowsTheCompositionItStarted() async {
        let store = BookDocumentStore(directory: directory)
        await store.keep(pdf(), renderId: "render-7", for: "memo-1")
        let enCours = BookPreview(
            memoId: "memo-1",
            title: "Rome",
            status: .composing,
            pageCount: 3,
            readyRenderId: "render-7",
            isUpToDate: false
        )
        let model = model([annonce(render: "render-7"), enCours], store: store)
        model.pacing = .fast
        await model.run()

        await model.regenerate()

        XCTAssertFalse(
            model.isAlreadyUpToDate,
            "Une composition est partie : le carnet n'était pas à jour."
        )
        XCTAssertNotEqual(
            model.notice?.message,
            BookCopy.Preview.alreadyUpToDate,
            "Dire « déjà à jour » après avoir lancé une mise en page serait un mensonge."
        )
        XCTAssertFalse(model.isRefreshing, "La flèche s'arrête quand la composition s'arrête.")
    }

    /// La flèche pâlie **répond**, comme « Partager » depuis T302 : un
    /// `disabled` avalerait le geste sans un mot.
    func testThePaleArrowExplainsItself() async {
        let model = model([BookPreview(memoId: "memo-1", title: "Rome", status: .ready, pageCount: 0)])
        await model.run()
        XCTAssertFalse(model.canShare)

        model.explainRegenerateIsClosed()

        XCTAssertEqual(model.notice?.message, BookCopy.Preview.nothingToRegenerate)
        XCTAssertEqual(model.notice?.answersAGesture, true)
    }

    // MARK: La date qu'on annonce

    /// Le jour et le moment, pas une heure : personne ne se souvient avoir
    /// composé son carnet à 21 h 47.
    func testTheMomentIsSaidTheWayPeopleSayIt() {
        let calendar = Calendar(identifier: .gregorian)
        func date(_ composantes: DateComponents) -> Date { calendar.date(from: composantes)! }
        let maintenant = date(DateComponents(year: 2026, month: 11, day: 26, hour: 15))

        XCTAssertEqual(
            BookCopy.Preview.moment(
                date(DateComponents(year: 2026, month: 11, day: 26, hour: 9)),
                now: maintenant,
                calendar: calendar
            ),
            "ce matin"
        )
        XCTAssertEqual(
            BookCopy.Preview.moment(
                date(DateComponents(year: 2026, month: 11, day: 25, hour: 21)),
                now: maintenant,
                calendar: calendar
            ),
            "hier soir"
        )
        XCTAssertEqual(
            BookCopy.Preview.moment(
                date(DateComponents(year: 2026, month: 11, day: 12, hour: 10)),
                now: maintenant,
                calendar: calendar
            ),
            "le 12 novembre",
            "Passé hier, c'est la date qui parle : « il y a 14 jours » demande un calcul."
        )

        // ⚠️ **Un « aujourd'hui » qui n'est pas aujourd'hui** (27/11/2026).
        // Les trois cas ci-dessus tombaient le jour où ils ont été écrits :
        // la fonction lisait la vraie date du jour et ignorait son `now`, si
        // bien qu'ils passaient le 26 novembre et rougissaient le 27. Une
        // année passée ne peut plus passer par accident.
        let unJourDePrintemps = date(DateComponents(year: 2024, month: 3, day: 2, hour: 15))
        XCTAssertEqual(
            BookCopy.Preview.moment(
                date(DateComponents(year: 2024, month: 3, day: 2, hour: 9)),
                now: unJourDePrintemps,
                calendar: calendar
            ),
            "ce matin"
        )
        XCTAssertEqual(
            BookCopy.Preview.moment(
                date(DateComponents(year: 2024, month: 3, day: 1, hour: 21)),
                now: unJourDePrintemps,
                calendar: calendar
            ),
            "hier soir"
        )
    }

    // MARK: Un serveur de PDF, le temps d'un test

    /// Le plus petit serveur HTTP qui serve un fichier une fois. Il existe
    /// parce qu'un seul test a besoin d'un **vrai** téléchargement : garder ce
    /// qui est arrivé ne se vérifie pas sans qu'il arrive.
    private final class PdfServer: @unchecked Sendable {
        let url: URL
        private let listener: NWListener

        init(_ data: Data) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener

            let entete = """
                HTTP/1.1 200 OK\r
                Content-Type: application/pdf\r
                Content-Length: \(data.count)\r
                Connection: close\r
                \r

                """
            let reponse = Data(entete.utf8) + data

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                    connection.send(
                        content: reponse,
                        completion: .contentProcessed { _ in connection.cancel() }
                    )
                }
            }

            let pret = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                if case .ready = state { pret.signal() }
            }
            listener.start(queue: .global())
            guard pret.wait(timeout: .now() + 5) == .success, let port = listener.port else {
                listener.cancel()
                throw Injoignable()
            }
            url = URL(string: "http://127.0.0.1:\(port.rawValue)/carnet.pdf")!
        }

        func stop() { listener.cancel() }
    }

}
