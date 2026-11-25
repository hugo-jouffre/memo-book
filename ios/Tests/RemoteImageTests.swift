import SwiftUI
import UIKit
import XCTest

@testable import MemoBookFeature

/// **Une photo appartient à son URL, pas à la place qu'elle occupe à l'écran**
/// (T301, Hugo, 08/11/2026 — « un second voyage créé en même temps que le
/// premier utilise sa photo de couverture »).
///
/// SwiftUI réutilise l'identité d'une vue d'un élément à l'autre, et `@State`
/// ne se repose qu'à la construction. Un voyage créé hors ligne est posé **en
/// tête** de l'accueil (`mergingLocalTrips`) : sa carte hérite de la vue de
/// l'ancienne première, donc de sa photo — et un voyage sans photo n'avait
/// rien pour l'effacer.
final class RemoteImageTests: XCTestCase {
    /// ⚠️ ``RemoteImageCache`` est **partagé** : deux tests qui emploient la
    /// même URL se passent leur image, et le second lit ce que le premier a
    /// rangé. Chacun tire donc les siennes.
    private func url(_ nom: String = #function) -> URL {
        URL(string: "https://exemple.test/\(UUID().uuidString)-\(nom).jpg")!
    }

    private func image(_ tint: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor(white: tint, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    /// Le cas de Hugo : le voyage suivant n'a **aucune** photo, et l'ancienne
    /// restait affichée.
    func testATripWithoutAPhotoDoesNotKeepTheOneBefore() {
        let rome = image(0.2)
        RemoteImageCache.shared.store(rome, for: url())

        XCTAssertNil(
            RemoteImage<Color>.resynchronised(rome, for: nil),
            "Sans URL, il n'y a pas de photo à montrer — surtout pas celle d'un autre carnet."
        )
    }

    /// Et le cas voisin : la carte change de voyage, le nouveau a bien une
    /// photo mais elle n'est pas encore chargée.
    func testChangingTripDropsThePreviousPhotoUntilItsOwnArrives() {
        let rome = image(0.2)
        RemoteImageCache.shared.store(rome, for: url("premiere"))

        XCTAssertNil(
            RemoteImage<Color>.resynchronised(rome, for: url("seconde")),
            "Une URL qu'on n'a pas encore chargée ne montre rien, pas la photo d'avant."
        )
    }

    /// Ce que la correction ne doit **pas** casser : une photo déjà vue est là
    /// au premier dessin, sans clignoter — c'est la raison d'être du composant.
    func testAPhotoAlreadySeenStaysInPlace() {
        let kyoto = image(0.8)
        let adresse = url()
        RemoteImageCache.shared.store(kyoto, for: adresse)

        XCTAssertTrue(
            RemoteImage<Color>.resynchronised(kyoto, for: adresse) === kyoto,
            "La même URL rend la même instance : l'affectation appelante n'écrit alors rien."
        )
    }

    /// Une photo que le cache ne connaît plus — `NSCache` se vide sous
    /// pression mémoire — se recharge, elle ne reste pas affichée par hasard.
    func testAnEvictedPhotoIsReloadedRatherThanKept() {
        let orpheline = image(0.5)
        XCTAssertNil(RemoteImage<Color>.resynchronised(orpheline, for: url()))
    }
}
