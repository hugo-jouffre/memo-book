import Foundation
import XCTest

@testable import MemoBookCore

/// L'**aperçu de personnalisation** : quelle image, parmi deux cents, surmonte
/// l'écran « Personnalisations ». `docs/apercu-personnalisation.md` fait foi.
final class BookCustomisationPreviewTests: XCTestCase {
    private let fallback = BookCustomisationPreview.fallbackFileName

    // MARK: La règle

    func testTheUntouchedBookShowsTheDefaultPreview() {
        // Celui qui s'affiche à l'ouverture de l'écran : il doit exister, et
        // ne pas être le repli.
        XCTAssertEqual(
            BookCustomisationPreview.fileName(for: BookCustomisation()),
            "Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png"
        )
    }

    func testEachComboNamesItsOwnPreview() {
        // Hors de l'assortiment par défaut, la contrainte éteint les
        // pointillés : ce sont ces états-là qui existent.
        XCTAssertEqual(
            BookCustomisationPreview.fileName(for: book(.travelJournal, rules: false)),
            "Pointillés=off, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png"
        )
        XCTAssertEqual(
            BookCustomisationPreview.fileName(for: book(.handwritten, rules: false)),
            "Pointillés=off, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Hansley - Gloria Hellelujah.png"
        )
        XCTAssertEqual(
            BookCustomisationPreview.fileName(for: book(.editorial, rules: false)),
            "Pointillés=off, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display.png"
        )
    }

    func testTheHandwrittenTypoIsKept() {
        // « Hellelujah » est figé dans cinquante noms de fichiers. La police,
        // elle, s'appelle bien Gloria Hallelujah : corriger le segment
        // ferait tomber tout *Manuscrit* sur le repli.
        let name = BookCustomisationPreview.fileName(for: book(.handwritten, rules: false))
        XCTAssertTrue(name.hasSuffix("Typos=Hansley - Gloria Hellelujah.png"), name)
        XCTAssertEqual(BookFontCombo.handwritten.font(.texts), "Gloria Hallelujah")
    }

    func testEveryRatioStepHasItsPreview() {
        // Les bornes du curseur, et chaque cran entre elles.
        for ratio in stride(from: 0, through: 100, by: 25) {
            XCTAssertEqual(
                BookCustomisationPreview.fileName(for: book(.travelJournal, ratio: ratio)),
                "Pointillés=on, Ratio image=\(ratio)%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png"
            )
        }
    }

    func testARatioOffTheSliderFallsBack() {
        // Une valeur posée par un autre client, ou d'avant le pas de 25 : la
        // règle ne l'arrondit pas, elle n'a pas d'image pour elle.
        for ratio in [-25, 10, 60, 125] {
            XCTAssertEqual(
                BookCustomisationPreview.fileName(for: book(.travelJournal, ratio: ratio)),
                fallback,
                "ratio \(ratio)"
            )
        }
    }

    func testEveryStickerCountHasItsPreview() {
        for quota in 0...4 {
            XCTAssertEqual(
                BookCustomisationPreview.fileName(for: book(.travelJournal, quota: quota)),
                "Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=\(quota), Typos=Playfair Display - Hansley - Gloria Hallelujah.png"
            )
        }
    }

    func testAStickerCountOffTheSliderFallsBack() {
        for quota in [-1, 5] {
            XCTAssertEqual(
                BookCustomisationPreview.fileName(for: book(.travelJournal, quota: quota)),
                fallback,
                "quota \(quota)"
            )
        }
    }

    func testAHandComposedBookFallsBack() {
        // L'état « Personnalisé » : quatre polices qui ne forment aucun des
        // trois assortiments. Le seul qui n'a pas d'aperçu une fois la
        // contrainte posée.
        var oneOff = BookCustomisation(rulesEnabled: false)
        oneOff.fontHand = "Montserrat"

        // L'ancien « Moderne », retiré le 18/09/2026, et l'ancien
        // « Éditorial », qui mariait Alegreya au récit : leurs carnets
        // gardent leurs polices et se lisent « Personnalisé ».
        let modern = BookCustomisation(
            rulesEnabled: false,
            fontTitle: "Montserrat",
            fontDisplay: "Montserrat",
            fontHand: "Alegreya",
            fontFacts: "Montserrat"
        )
        var formerEditorial = book(.editorial, rules: false)
        formerEditorial.fontHand = "Alegreya"
        formerEditorial.fontFacts = "Alegreya"

        for custom in [oneOff, modern, formerEditorial] {
            XCTAssertNil(BookFontCombo.matching(custom))
            XCTAssertNil(BookCustomisationPreview.composedFileName(for: custom))
            XCTAssertEqual(BookCustomisationPreview.fileName(for: custom), fallback)
        }
    }

    func testTheShortFamilyNameStillFindsThePreview() {
        // La base a longtemps reçu « Playfair » là où le gabarit dit
        // « Playfair Display » : ces carnets sont dans l'assortiment par
        // défaut, et doivent en avoir l'aperçu.
        var book = BookCustomisation()
        book.fontDisplay = "Playfair"
        book.fontFacts = "Playfair"
        let name = BookCustomisationPreview.fileName(for: book)
        XCTAssertNotEqual(name, fallback)
        XCTAssertEqual(name, BookCustomisationPreview.fileName(for: BookCustomisation()))
    }

    func testSettingsOutsideThePreviewLeaveItAlone() {
        // Nombre de pages, quiz, zones libres, mots fléchés : aucun ne doit
        // changer l'image — donc aucun ne doit la recharger.
        let changes: [(String, (inout BookCustomisation) -> Void)] = [
            ("targetPageCount", { $0.targetPageCount = 120 }),
            ("quizEnabled", { $0.quizEnabled.toggle() }),
            ("freeZonesEnabled", { $0.freeZonesEnabled.toggle() }),
            ("crosswordEnabled", { $0.crosswordEnabled.toggle() }),
            ("hasConfiguredCovers", { $0.hasConfiguredCovers.toggle() }),
        ]

        for start in [book(.travelJournal), book(.handwritten, rules: false), book(.editorial, rules: false)] {
            let reference = BookCustomisationPreview.fileName(for: start)
            // Sinon le test passerait à vide : le repli ne change jamais.
            XCTAssertNotEqual(reference, fallback)

            var all = start
            for (property, change) in changes {
                var one = start
                change(&one)
                change(&all)
                XCTAssertEqual(BookCustomisationPreview.fileName(for: one), reference, property)
            }
            XCTAssertEqual(BookCustomisationPreview.fileName(for: all), reference, "les cinq à la fois")
        }
    }

    func testAStateMissingFromTheManifestFallsBack() {
        // *Manuscrit* avec pointillés : la règle sait le nommer, le dossier
        // n'a pas l'image. Tant que la contrainte ne l'a pas éteint en amont,
        // c'est le repli — pas l'aperçu sans pointillés, qui mentirait sur le
        // carnet imprimé.
        let ruled = book(.handwritten, rules: true)
        XCTAssertNotNil(BookCustomisationPreview.composedFileName(for: ruled))
        XCTAssertEqual(BookCustomisationPreview.fileName(for: ruled), fallback)

        // Et ce que la règle cherche, elle le cherche dans le manifeste qu'on
        // lui donne.
        XCTAssertEqual(BookCustomisationPreview.fileName(for: BookCustomisation(), among: []), fallback)
    }

    // MARK: Le manifeste et le dossier

    func testTheManifestIsTheFolder() throws {
        // Comparé **octet par octet** : Swift tient « é » et « e + accent »
        // pour la même chaîne, une URL non. C'est ce qui a fait répondre 404
        // à l'ancien repli.
        let names = try FileManager.default
            .contentsOfDirectory(atPath: Self.previewFolder.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
        XCTAssertTrue(names.contains(fallback), "L’image de repli manque au dossier")

        let onDisk = Set(names.filter { $0 != fallback }.map { Array($0.utf8) })
        let listed = Set(BookCustomisationPreview.availableFileNames.map { Array($0.utf8) })
        let rerun = "relancer `python3 ios/Tools/make-customisation-preview-manifest.py`"
        XCTAssertEqual(Self.names(onDisk.subtracting(listed)), [], "Dans le dossier, pas dans le manifeste : \(rerun)")
        XCTAssertEqual(Self.names(listed.subtracting(onDisk)), [], "Dans le manifeste, plus dans le dossier : \(rerun)")
    }

    func testEveryPreviewIsOneTheRuleCanPick() {
        // Un fichier que la règle ne compose jamais est un fichier mal nommé :
        // un segment de travers, un suffixe oublié.
        let composable = Set(Self.everyState.compactMap(BookCustomisationPreview.composedFileName(for:)))
        XCTAssertEqual(composable.count, 300)
        XCTAssertEqual(BookCustomisationPreview.availableFileNames.subtracting(composable).sorted(), [])
    }

    func testEveryReachableStateHasItsPreview() {
        // Une fois la contrainte posée — `BookFontCombo.allowsRules`, que lit
        // le verrou des pointillés —, les deux cents états atteignables ont
        // leur image : le repli ne sert plus qu'à « Personnalisé ».
        let reachable = Self.everyState.filter { !$0.rulesEnabled || Self.allowsRules($0) }
        XCTAssertEqual(reachable.count, 200)

        let missing = reachable
            .filter { BookCustomisationPreview.fileName(for: $0) == fallback }
            .map { BookCustomisationPreview.composedFileName(for: $0) ?? "sans assortiment : \($0)" }
        XCTAssertEqual(missing, [])

        // Et le nom rendu s'écrit comme sur le disque, octet pour octet : c'est
        // lui qui deviendra une URL.
        let listed = Set(BookCustomisationPreview.availableFileNames.map { Array($0.utf8) })
        let misspelt = reachable
            .map { BookCustomisationPreview.fileName(for: $0) }
            .filter { !listed.contains(Array($0.utf8)) }
        XCTAssertEqual(misspelt, [])
    }

    func testTheConstraintStillMatchesTheFolder() {
        // Les cent états qu'elle écarte sont exactement ceux qui n'ont pas
        // d'image. Le jour où ce test casse, les rendus manquants sont
        // arrivés : la contrainte doit sauter — `allowsRules` à `true`, elle
        // seule, la règle ne bouge pas.
        let excluded = Self.everyState.filter { $0.rulesEnabled && !Self.allowsRules($0) }
        XCTAssertEqual(excluded.count, 100)

        let present = excluded
            .compactMap(BookCustomisationPreview.composedFileName(for:))
            .filter { BookCustomisationPreview.availableFileNames.contains($0) }
        XCTAssertEqual(present, [])
    }

    // MARK: Outils

    /// Un carnet réglé sur cet assortiment, le reste aux valeurs par défaut.
    private func book(
        _ combo: BookFontCombo,
        rules: Bool = true,
        ratio: Int = 50,
        funFacts: Bool = true,
        quota: Int = 2
    ) -> BookCustomisation {
        Self.book(combo, rules: rules, ratio: ratio, funFacts: funFacts, quota: quota)
    }

    private static func book(
        _ combo: BookFontCombo,
        rules: Bool,
        ratio: Int,
        funFacts: Bool,
        quota: Int
    ) -> BookCustomisation {
        var book = BookCustomisation(
            photoTextRatio: ratio,
            funFactsEnabled: funFacts,
            rulesEnabled: rules,
            decorationQuota: quota
        )
        for role in BookFontRole.allCases {
            book[keyPath: role.keyPath] = combo.font(role)
        }
        return book
    }

    /// Les trois cents états que les cinq propriétés produisent : trois
    /// assortiments, deux pointillés, cinq ratios, deux fun facts, cinq quotas.
    private static let everyState: [BookCustomisation] = BookFontCombo.all.flatMap { combo in
        [true, false].flatMap { rules in
            stride(from: 0, through: 100, by: 25).flatMap { ratio in
                [true, false].flatMap { funFacts in
                    (0...4).map { quota in
                        book(combo, rules: rules, ratio: ratio, funFacts: funFacts, quota: quota)
                    }
                }
            }
        }
    }

    private static func allowsRules(_ book: BookCustomisation) -> Bool {
        BookFontCombo.matching(book)?.allowsRules ?? false
    }

    /// `assets/illustrations/aperçu personnalisation/`, depuis ce fichier.
    private static let previewFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MemoBookCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Modules
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // la racine du dépôt
        .appending(path: "assets/illustrations/aperçu personnalisation", directoryHint: .isDirectory)

    private static func names(_ spellings: Set<[UInt8]>) -> [String] {
        spellings.map { String(decoding: $0, as: UTF8.self) }.sorted()
    }
}
