import Foundation
import MemoBookCore

// Jeu d'essai de l'accueil d'un voyage — **temporaire**, comme celui de
// l'accueil et du profil.
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une date,
// pas une étape n'est écrite dans une vue. Le jour où l'API rend un
// `TripDetail`, ce fichier disparaît et rien d'autre ne bouge.
//
// Le voyage lui-même est **repris de l'accueil** plutôt que réinventé : ouvrir
// une carte doit mener à ce qu'elle montrait. Seules les étapes, la relance et
// les abonnés sont ajoutés ici, faute d'exister ailleurs.

extension TripDetail {
    /// Le voyage d'identifiant donné, tel que l'accueil le connaît, complété de
    /// ce que l'API ne sait pas encore rendre.
    public static func fixture(id: String) -> TripDetail {
        let trip = HomeFeed.fixture.trips.first { $0.id == id } ?? fallbackTrip

        return TripDetail(trip: trip, prompt: prompt(for: trip), steps: steps(for: trip))
    }

    /// Un identifiant inconnu ne doit pas donner un écran vide : le carnet de
    /// démonstration prend le relais. Cas de figure du jeu d'essai uniquement —
    /// l'API, elle, répondra 404 et l'écran affichera son bandeau d'erreur.
    private static var fallbackTrip: Trip {
        HomeFeed.fixture.trips[0]
    }

    /// La relance de MemoBook, posée sur la dernière étape connue.
    private static func prompt(for trip: Trip) -> String? {
        guard let place = steps(for: trip).last?.placeName else { return nil }
        return "Comment ça se passe à \(place) ?"
    }

    /// Quatre étapes, avec des pays et des transports **différents** : sans ça,
    /// les trois filtres n'auraient rien à mordre et on ne saurait pas s'ils
    /// fonctionnent.
    private static func steps(for trip: Trip) -> [TripStep] {
        // Un voyage qui annonce un pays garde le sien d'un bout à l'autre ; un
        // tour du monde en traverse plusieurs.
        let itinerary: [(String, Destination)] =
            if let destination = trip.destination {
                [
                    ("Trastevere", destination),
                    ("Monti", destination),
                    ("Testaccio", destination),
                ]
            } else {
                [
                    ("Lisbonne", Destination(name: "Portugal", countryCode: "PT")),
                    ("Marrakech", Destination(name: "Maroc", countryCode: "MA")),
                    ("Hanoï", Destination(name: "Viêt Nam", countryCode: "VN")),
                ]
            }

        let transports: [TripTransport] = [.plane, .train, .walk]
        let start = trip.startDate ?? .fixture(26, 8, 2026)
        let companions = trip.companions.isEmpty
            ? [Companion(id: "c-mila", name: "Mila Fontaine")]
            : trip.companions

        return itinerary.enumerated().map { index, entry in
            let (place, destination) = entry

            return TripStep(
                id: "\(trip.id)-step-\(index + 1)",
                number: index + 1,
                placeName: place,
                destination: destination,
                startDate: start.adding(days: index * 5),
                endDate: start.adding(days: index * 5 + 4),
                // La première étape est faite avec tout le monde, les suivantes
                // avec une seule personne : la ligne « avec … » doit se voir
                // dans ses deux formes.
                companions: index == 0 ? companions : Array(companions.prefix(1)),
                transport: transports[index % transports.count]
            )
        }
    }
}

extension Date {
    fileprivate func adding(days: Int) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: self) ?? self
    }
}
