import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MemoBookFeature

/// **Une photo choisie dans la photothèque part en JPEG** (Hugo, 11/11/2026).
///
/// Un iPhone garde ses photos en HEIC, et c'est le fichier brut que
/// `loadTransferable(type: Data.self)` rend. Envoyé tel quel, il s'affichait
/// partout dans l'app — iOS décode le HEIC — et manquait au carnet, composé par
/// un Chromium qui ne le décode pas.
final class PhotoEncodingTests: XCTestCase {
    /// Une image codée dans le format demandé, écrite par ImageIO.
    private func image(
        _ type: UTType,
        width: Int = 40,
        height: Int = 30,
        orientation: Int? = nil
    ) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func format(of data: Data) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceGetType(source)) as String
    }

    func testConvertitUnHeicEnJpeg() throws {
        let heic = try image(.heic)
        XCTAssertEqual(try format(of: heic), UTType.heic.identifier)

        let converted = try XCTUnwrap(PhotoEncoding.jpeg(from: heic))

        XCTAssertEqual(try format(of: converted), UTType.jpeg.identifier)
    }

    func testRendUnJpegInchange() throws {
        let jpeg = try image(.jpeg)

        XCTAssertEqual(PhotoEncoding.jpeg(from: jpeg), jpeg)
    }

    /// Le piège de `UIImage.jpegData` : il perd le drapeau d'orientation, et
    /// une photo prise à la verticale repart couchée.
    func testGardeLOrientationExif() throws {
        let heic = try image(.heic, orientation: 6)

        let converted = try XCTUnwrap(PhotoEncoding.jpeg(from: heic))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(converted as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, 6)
    }

    // MARK: - La taille d'envoi (T275)

    /// ⚠️ **Le cœur de T275** : une photo d'iPhone partait à sa taille
    /// d'origine — 3 à 6 Mo — alors que le serveur la ramène de toute façon à
    /// 2400 px pour le carnet. Tout ce qui dépassait était payé en temps
    /// d'envoi pour être jeté à l'arrivée.
    func testReduitUnePhotoPlusGrandeQueLeCarnet() throws {
        let grande = try image(.jpeg, width: 4_000, height: 3_000)

        let envoyee = try XCTUnwrap(PhotoEncoding.jpeg(from: grande))

        let dimensions = try dimensions(of: envoyee)
        XCTAssertEqual(max(dimensions.width, dimensions.height), PhotoEncoding.maxSide)
        XCTAssertLessThan(envoyee.count, grande.count)
    }

    /// Le cadrage ne change pas : on réduit, on ne recadre pas.
    func testGardeLesProportions() throws {
        let grande = try image(.jpeg, width: 4_000, height: 2_000)

        let envoyee = try XCTUnwrap(PhotoEncoding.jpeg(from: grande))

        let dimensions = try dimensions(of: envoyee)
        XCTAssertEqual(dimensions.width, 2_400)
        XCTAssertEqual(dimensions.height, 1_200)
    }

    /// Une photo réduite est **redressée** : son drapeau EXIF est appliqué aux
    /// pixels, et le côté le plus long reste le plus long.
    func testUnePhotoReduiteEstRedressee() throws {
        // Orientation 6 : à lire, l'image est tournée d'un quart de tour.
        let grande = try image(.jpeg, width: 4_000, height: 3_000, orientation: 6)

        let envoyee = try XCTUnwrap(PhotoEncoding.jpeg(from: grande))

        // Un fichier 4000×3000 marqué « 6 » **se lit** 3000×4000 : il est
        // debout. Le quart de tour appliqué aux pixels, il reste debout —
        // 1800×2400. Sans la transformation, on lirait 2400×1800 : c'est
        // cette inversion que le test attrape.
        let dimensions = try dimensions(of: envoyee)
        XCTAssertEqual(dimensions.width, 1_800)
        XCTAssertEqual(dimensions.height, 2_400)
    }

    private func dimensions(of data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        return (
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    func testEcarteCeQuiNEstPasUneImage() {
        XCTAssertNil(PhotoEncoding.jpeg(from: Data("ni une image ni rien du tout".utf8)))
        XCTAssertEqual(PhotoEncoding.jpegs(from: [Data([0x00, 0x01])]), [])
    }
}
