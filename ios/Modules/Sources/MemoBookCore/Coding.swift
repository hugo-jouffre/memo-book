import Foundation

extension JSONDecoder {
    /// Décodeur accordé au back-end MemoBook.
    ///
    /// Les dates arrivent au format `toISOString()` de JavaScript, qui inclut
    /// les millisecondes (`2026-08-08T12:48:25.295Z`). La stratégie `.iso8601`
    /// de Foundation les refuse : d'où le format explicite, avec repli sur la
    /// forme sans fraction pour les champs que le serveur pourrait sérialiser
    /// autrement.
    public static var memoBook: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601DateFormatter.memoBookDate(from: raw) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Date ISO 8601 illisible : \(raw)"
                    )
                )
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    public static var memoBook: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.memoBookString(from: date))
        }
        return encoder
    }
}

extension ISO8601DateFormatter {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func memoBookDate(from string: String) -> Date? {
        withFractionalSeconds.date(from: string) ?? withoutFractionalSeconds.date(from: string)
    }

    public static func memoBookString(from date: Date) -> String {
        withFractionalSeconds.string(from: date)
    }
}
