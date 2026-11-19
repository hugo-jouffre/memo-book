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

    /// **Le plus grand côté d'une photo envoyée dans la conversation** (T275,
    /// 19/11/2026).
    ///
    /// 2400 px, parce que c'est **exactement ce que le serveur garde** :
    /// `RENDER_MAX_SIDE` réduit chaque photo à 2400 px pour le carnet
    /// (`services/photoDownscale.ts`), où une pleine page A4 est encore tirée
    /// à 290 dpi. Tout ce qu'on envoyait au-delà était donc payé par le
    /// voyageur — en temps, en données — pour être jeté à l'arrivée.
    ///
    /// Une photo d'iPhone 17 pèse 3 à 6 Mo ; réduite, elle en pèse moins de
    /// 1. Quatre photos passaient de ~20 Mo à ~3 : c'est la différence entre
    /// un envoi qui aboutit et un envoi qui dépasse les 60 secondes du client
    /// et retombe dans la file en annonçant « hors ligne ».
    static let maxSide = 2_400

    /// Les octets d'une photo, en JPEG et **à la taille du carnet** — ou `nil`
    /// si ces octets ne sont pas une image lisible.
    ///
    /// Un JPEG déjà assez petit revient **inchangé** : le réencoder perdrait
    /// de la matière pour rien.
    ///
    /// ⚠️ `UIImage(data:)?.jpegData(…)` serait le chemin court, et il est
    /// faux : il perd le drapeau EXIF d'orientation, et une photo prise à la
    /// verticale repart couchée. `CGImageDestinationAddImageFromSource` recopie
    /// les métadonnées de la source, orientation comprise.
    static func jpeg(from data: Data, quality: CGFloat = quality, maxSide: Int = maxSide) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        if let reduced = reduced(source, to: maxSide, quality: quality) { return reduced }

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

    /// La même photo, **ramenée à `maxSide`** — ou `nil` si elle y tient déjà,
    /// et c'est alors au chemin d'origine de la rendre telle quelle.
    ///
    /// ImageIO réduit **et redresse** en une passe
    /// (`kCGImageSourceCreateThumbnailWithTransform`) : le drapeau EXIF est
    /// appliqué aux pixels au lieu d'être recopié. Une photo réduite n'a donc
    /// plus d'orientation à porter — ce qui est la même image, et une
    /// ambiguïté de moins pour tout ce qui la lit ensuite.
    ///
    /// ⚠️ Et c'est pour ça qu'on ne réduit **que** ce qui dépasse : une photo
    /// déjà petite doit revenir intacte, drapeau compris — voir
    /// `PhotoEncodingTests`.
    private static func reduced(_ source: CGImageSource, to maxSide: Int, quality: CGFloat) -> Data? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            max(width, height) > maxSide,
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxSide,
                ] as CFDictionary
            )
        else { return nil }

        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else { return nil }

        CGImageDestinationAddImage(
            destination,
            thumbnail,
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
