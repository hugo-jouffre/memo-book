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

    func testEcarteCeQuiNEstPasUneImage() {
        XCTAssertNil(PhotoEncoding.jpeg(from: Data("ni une image ni rien du tout".utf8)))
        XCTAssertEqual(PhotoEncoding.jpegs(from: [Data([0x00, 0x01])]), [])
    }
}
