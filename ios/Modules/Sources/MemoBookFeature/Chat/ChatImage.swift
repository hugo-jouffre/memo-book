import ImageIO
import Observation
import UIKit

/// La case d'une image du fil : vide tant qu'elle charge. Observée **seule** —
/// voir ``ChatModel/image(at:)``.
@MainActor
@Observable
final class ChatImageSlot {
    var image: UIImage?
}

/// Une image du fil, décodée **à la taille où elle se montre**.
///
/// Une photo d'iPhone pèse plusieurs mégaoctets et décode en dizaines de
/// mégaoctets de pixels ; la bulle en montre une vignette de 180 pt. On la
/// réduit donc en la décodant (ImageIO, sans passer par l'image entière), hors
/// de l'acteur principal : un fil de vingt photos ne doit ni ramer ni se faire
/// tuer pour mémoire.
enum ChatImage {
    /// Le plus grand côté gardé, en pixels : trois fois la plus grande
    /// vignette du fil, arrondi.
    static let maximumPixelSize: CGFloat = 1_024

    /// L'image réduite, ou `nil` si les octets ne sont pas une image.
    static func decode(_ data: Data?) async -> UIImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) {
            thumbnail(of: data)
        }.value
    }

    static func thumbnail(of data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // L'orientation EXIF appliquée : une photo prise en portrait ne
            // doit pas se coucher dans la bulle.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
