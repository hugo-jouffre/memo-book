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
        traveller: Traveller(
            id: "traveller-1",
            firstName: "Camille",
            offeredSteps: 3,
            remainingSteps: 2
        ),
        trips: [
            Trip(
                id: "trip-rome",
                title: "Rome entre frère et sœur",
                destination: Destination(name: "Italie", countryCode: "IT", city: "Rome"),
                stage: .ongoing,
                startDate: .fixture(26, 8, 2026),
                endDate: .fixture(15, 9, 2026),
                stats: TripStats(dayCount: 10, distanceKilometres: 37, photoCount: 24),
                companions: [
                    Companion(id: "c-1", name: "Léa Marchand"),
                    Companion(id: "c-2", name: "Tom Marchand"),
                ],
                progress: TripProgress(memoryCount: 5, pageCount: 2, targetPageCount: 80)
            ),
            Trip(
                id: "trip-tour-du-monde",
                title: "Mon tour du monde",
                stage: .ongoing,
                startDate: .fixture(2, 6, 2026),
                stats: TripStats(dayCount: 10, distanceKilometres: 37, photoCount: 24),
                progress: TripProgress(memoryCount: 12, pageCount: 18, targetPageCount: 60)
            ),
            Trip(
                id: "trip-philippines",
                title: "Philippines avec Claire & Gus",
                destination: Destination(name: "Philippines", countryCode: "PH", city: "Palawan"),
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
                destination: Destination(name: "Colombie", countryCode: "CO", city: "Bogotá"),
                stage: .past,
                startDate: .fixture(3, 2, 2025),
                endDate: .fixture(24, 2, 2025),
                stats: TripStats(dayCount: 22, distanceKilometres: 890, photoCount: 204),
                isPrintable: true
            ),
            Trip(
                id: "trip-lisbonne",
                title: "Un week-end à Lisbonne",
                destination: Destination(name: "Portugal", countryCode: "PT", city: "Lisbonne"),
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
        traveller: Traveller(
            id: "traveller-1",
            firstName: "Camille",
            offeredSteps: 3,
            remainingSteps: 2
        ),
        trips: [],
        showcase: fixture.showcase
    )
}

extension Date {
    /// Une date de jeu d'essai, à midi UTC pour qu'aucun fuseau ne la fasse
    /// changer de jour à l'affichage. Partagée avec le jeu d'essai des voyages,
    /// qui doit tomber sur les mêmes dates que l'accueil.
    static func fixture(_ day: Int, _ month: Int, _ year: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        // Le repli ne sert qu'à satisfaire le compilateur : ces composants sont
        // écrits à la main juste au-dessus et sont toujours valides.
        return calendar.date(from: components) ?? .now
    }
}


// MARK: - Bac à sable

#if DEBUG

    extension Trip {
        /// Un voyage tiré au sort, pour le panneau d'essai de l'accueil.
        ///
        /// Les destinations viennent d'une petite banque plutôt que d'un
        /// générateur : on veut des carnets **plausibles**, avec un drapeau et
        /// un titre qui se lisent, pas du lorem ipsum.
        static func debugRandom(stage: TripStage, index: Int) -> Trip {
            let sample = destinations.randomElement() ?? destinations[0]
            let id = "debug-\(stage.rawValue)-\(index)-\(UUID().uuidString.prefix(4))"

            // Un voyage à venir commence dans quelques semaines ; un voyage
            // passé s'est terminé il y a quelques mois. C'est ce décalage qui
            // les range dans la bonne section.
            let offset = stage == .upcoming ? Int.random(in: 20...200) : Int.random(in: -900 ... -30)
            let start = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: .now) ?? .now
            let length = Int.random(in: 4...25)
            let end = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: length, to: start) ?? start

            return Trip(
                id: id,
                title: sample.title,
                destination: sample.destination,
                stage: stage,
                startDate: start,
                endDate: stage == .ongoing ? nil : end,
                stats: TripStats(
                    dayCount: length,
                    distanceKilometres: Double(Int.random(in: 20...2_400)),
                    photoCount: Int.random(in: 5...320)
                ),
                progress: stage == .upcoming
                    ? nil
                    : TripProgress(
                        memoryCount: Int.random(in: 1...40),
                        pageCount: Int.random(in: 0...70),
                        targetPageCount: 80
                    ),
                isPrintable: stage == .past
            )
        }

        private static let destinations: [(title: String, destination: Destination)] = [
            ("Road trip en Écosse", Destination(name: "Écosse", countryCode: "GB", city: "Édimbourg")),
            ("Les Lofoten en hiver", Destination(name: "Norvège", countryCode: "NO", city: "Svolvær")),
            ("Kyoto au printemps", Destination(name: "Japon", countryCode: "JP", city: "Kyoto")),
            ("Traversée du Chili", Destination(name: "Chili", countryCode: "CL", city: "Santiago")),
            ("Week-end à Porto", Destination(name: "Portugal", countryCode: "PT", city: "Porto")),
            ("Sur les routes du Kerala", Destination(name: "Inde", countryCode: "IN", city: "Kochi")),
            ("Cap sur l’Islande", Destination(name: "Islande", countryCode: "IS", city: "Reykjavik")),
        ]
    }

#endif
