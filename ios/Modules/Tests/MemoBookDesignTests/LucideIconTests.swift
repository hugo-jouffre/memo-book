import UIKit
import XCTest

@testable import MemoBookDesign

/// Le pont entre une clé et le catalogue d'assets.
///
/// La clé d'un pictogramme est écrite **en base** pour les catégories de la
/// galerie (`gallery_categories.iconKey`) et le nom de l'asset se calcule des
/// deux côtés — par `ios/Tools/import-lucide-icons.py` à l'import, par
/// ``LucideIcon`` à l'affichage. Deux règles de nommage qui divergent, et les
/// pastilles se retrouvent vides sans que rien n'échoue.
final class LucideIconTests: XCTestCase {
    func testEveryKnownKeyHasAnAssetInTheCatalog() {
        for key in LucideIcon.known {
            let name = LucideIcon.assetName(for: key)
            XCTAssertNotNil(
                UIImage(named: name, in: .module, with: nil),
                "\(key) → \(name) : lancer `python3 ios/Tools/import-lucide-icons.py`"
            )
        }
    }

    func testUnknownKeyFallsBackToTheCompass() {
        // Une catégorie ajoutée en base avant la prochaine version de l'app
        // s'affiche quand même, avec une boussole.
        XCTAssertEqual(LucideIcon.assetName(for: "montgolfiere"), "IconLucideCompass")
        XCTAssertEqual(LucideIcon.assetName(for: nil), "IconLucideCompass")
    }

    func testHyphenatedKeysBecomePascalCase() {
        XCTAssertEqual(LucideIcon.assetName(for: "mountain-snow"), "IconLucideMountainSnow")
        XCTAssertEqual(LucideIcon.assetName(for: "building-2"), "IconLucideBuilding2")
        XCTAssertEqual(LucideIcon.assetName(for: "globe"), "IconLucideGlobe")
    }
}
