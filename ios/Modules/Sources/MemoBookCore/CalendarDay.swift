import Foundation

/// Un jour du calendrier, sans heure ni fuseau : une date de naissance.
///
/// **Un jour et non une `Date`**, parce qu'une `Date` est un instant. La
/// naissance du 12 mai, envoyée comme minuit UTC, se relisait le 11 mai dans un
/// fuseau à l'ouest de Greenwich. Le serveur la garde en `DATE` et la rend
/// `AAAA-MM-JJ` ; ce type la transporte telle quelle, et c'est aussi lui qui lit
/// ce qu'on tape, `JJ/MM/AAAA`.
public struct CalendarDay: Sendable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// `nil` pour un jour qui n'existe pas — le 30 février, le mois 13.
    public init?(year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Le jour qu'un instant désigne **dans ce calendrier** — celui de
    /// l'appareil, par défaut.
    public init(_ date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    /// `AAAA-MM-JJ`, la forme du serveur.
    public init?(iso: String) {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// `JJ/MM/AAAA`, la forme qu'on tape.
    public init?(slashed: String) {
        let parts = slashed.split(separator: "/")
        guard parts.count == 3, parts[0].count == 2, parts[1].count == 2, parts[2].count == 4,
            let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var slashed: String {
        String(format: "%02d/%02d/%04d", day, month, year)
    }

    /// Une date de naissance qu'on peut croire : pas dans le futur, pas avant
    /// 1900. La même borne que le serveur.
    public func isPlausibleBirthDate(today: CalendarDay = CalendarDay(.now)) -> Bool {
        year >= 1900 && self <= today
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDay: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let day = CalendarDay(iso: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Jour illisible : \(raw)")
            )
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso)
    }
}
