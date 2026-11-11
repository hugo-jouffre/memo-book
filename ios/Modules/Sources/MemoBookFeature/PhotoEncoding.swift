import Foundation
import ImageIO
import UniformTypeIdentifiers

/// **Une photo part toujours en JPEG** (Hugo, 11/11/2026 — « les photos
/// n'apparaissent pas dans les PDF »).
///
/// La photothèque d'un iPhone garde ses photos en **HEIC**, et
/// `loadTransferable(type: Data.self)` rend le fichier *tel quel*. L'app les
/// envoyait donc en HEIC, sous un nom en `.jpg` et un `image/jpeg` — un
/// mensonge que rien ne révélait, puisque iOS décode le HEIC : la photo
/// s'affichait dans la conversation, sur l'accueil, partout. Mais le carnet
/// est composé par un Chromium, qui **ne décode pas le HEIC** : l'`<img>`
/// restait à `naturalWidth: 0`, sans émettre d'erreur, et la page se composait
/// sans la photo.
///
/// Le serveur convertit désormais lui aussi, parce qu'il ne doit pas dépendre
/// de l'honnêteté d'un client (`services/photoFormat.ts`). On convertit quand
/// même **ici** : c'est une conversion de moins à faire sur un serveur, c'est
/// le type déclaré qui cesse de mentir, et une vieille version de l'app n'est
/// pas la seule à être rattrapée.
enum PhotoEncoding {
    /// Qualité d'encodage. 0,85 : le même réglage que l'appareil photo de
    /// l'app (`CameraPicker`), pour qu'une photo prise et une photo choisie
    /// arrivent dans la même matière.
    static let quality: CGFloat = 0.85

    /// Les octets d'une photo, en JPEG — ou `nil` si ces octets ne sont pas
    /// une image lisible.
    ///
    /// Un JPEG revient **inchangé** : le réencoder perdrait de la matière pour
    /// rien.
    ///
    /// ⚠️ `UIImage(data:)?.jpegData(…)` serait le chemin court, et il est
    /// faux : il perd le drapeau EXIF d'orientation, et une photo prise à la
    /// verticale repart couchée. `CGImageDestinationAddImageFromSource` recopie
    /// les métadonnées de la source, orientation comprise.
    static func jpeg(from data: Data, quality: CGFloat = quality) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let jpeg = UTType.jpeg.identifier as CFString
        if CGImageSourceGetType(source) == jpeg { return data }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, jpeg, 1, nil)
        else { return nil }

        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Les photos choisies, toutes en JPEG. Celles qu'on ne sait pas lire sont
    /// écartées : mieux vaut une photo de moins qu'une photo qui manquera au
    /// carnet sans que personne ne l'ait su.
    static func jpegs(from photos: [Data]) -> [Data] {
        photos.compactMap { jpeg(from: $0) }
    }
}
