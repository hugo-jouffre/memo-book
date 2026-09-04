import Foundation
import MemoBookCore

// Jeu d'essai de l'accueil — **temporaire**.
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une date,
// pas un compteur n'est écrit dans une vue. Le jour où l'API rend un
// `HomeFeed`, ce fichier disparaît et rien d'autre ne bouge.
//
// Les dates sont figées, pas relatives à aujourd'hui : une maquette qui change
// de texte selon le jour où on la regarde n'est pas comparable à Figma.

extension HomeFeed {
    /// Le contenu de la maquette d'accueil.
    public static let fixture = HomeFeed(
        traveller: Traveller(id: "traveller-1", firstName: "Camille"),
        trips: [
            Trip(
                id: "trip-rome",
                title: "Rome entre frère et sœur",
                destination: Destination(name: "Italie", countryCode: "IT"),
                stage: .ongoing,
                startDate: .fixture(26, 8, 2026),
                endDate: .fixture(15, 9, 2026),
                stats: TripStats(dayCount: 10, distanceKilometres: 37, photoCount: 24),
                companions: [
                    Companion(id: "c-1", name: "Léa Marchand"),
                    Companion(id: "c-2", name: "Tom Marchand"),
                ]
            ),
            Trip(
                id: "trip-tour-du-monde",
                title: "Mon tour du monde",
                stage: .ongoing,
                startDate: .fixture(2, 6, 2026),
                stats: TripStats(dayCount: 10, distanceKilometres: 37, photoCount: 24)
            ),
            Trip(
                id: "trip-philippines",
                title: "Philippines avec Claire & Gus",
                destination: Destination(name: "Philippines", countryCode: "PH"),
                stage: .past,
                startDate: .fixture(26, 8, 2025),
                endDate: .fixture(15, 9, 2025),
                stats: TripStats(dayCount: 21, distanceKilometres: 412, photoCount: 168),
                companions: [
                    Companion(id: "c-3", name: "Claire Nguyen"),
                    Companion(id: "c-4", name: "Gustave Pelletier"),
                ],
                isPrintable: true
            ),
            Trip(
                id: "trip-colombie",
                title: "Claire et Gus en Colombie",
                destination: Destination(name: "Colombie", countryCode: "CO"),
                stage: .past,
                startDate: .fixture(3, 2, 2025),
                endDate: .fixture(24, 2, 2025),
                stats: TripStats(dayCount: 22, distanceKilometres: 890, photoCount: 204),
                isPrintable: true
            ),
            Trip(
                id: "trip-lisbonne",
                title: "Un week-end à Lisbonne",
                destination: Destination(name: "Portugal", countryCode: "PT"),
                stage: .past,
                startDate: .fixture(11, 10, 2024),
                endDate: .fixture(14, 10, 2024),
                stats: TripStats(dayCount: 4, distanceKilometres: 26, photoCount: 61),
                isPrintable: false
            ),
        ],
        showcase: Showcase(
            title: "Voir des exemples de carnet",
            subtitle: "Découvre à quoi ressemble un carnet MemoBook terminé"
        )
    )

    /// Le tout premier lancement : un compte, aucun voyage.
    public static let emptyFixture = HomeFeed(
        traveller: Traveller(id: "traveller-1", firstName: "Camille"),
        trips: [],
        showcase: fixture.showcase
    )
}

extension Date {
    /// Une date de jeu d'essai, à midi UTC pour qu'aucun fuseau ne la fasse
    /// changer de jour à l'affichage.
    fileprivate static func fixture(_ day: Int, _ month: Int, _ year: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        // Le repli ne sert qu'à satisfaire le compilateur : ces composants sont
        // écrits à la main juste au-dessus et sont toujours valides.
        return calendar.date(from: components) ?? .now
    }
}
