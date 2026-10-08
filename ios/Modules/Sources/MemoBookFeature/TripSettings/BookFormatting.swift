import Foundation
import MemoBookCore

// Mise en forme des données du parcours « carnet » : paramètres du voyage,
// aperçu PDF.
//
// Tout passe par `FormatStyle` plutôt que par des chaînes assemblées à la
// main — même parti pris que `TripFormatting` : c'est ce qui donne
// « 26 août – 15 sept. 2026 » en français et « Aug 26 – Sep 15, 2026 » en
// anglais, sans qu'un écran connaisse une seule règle de langue.

extension TripSettings {
    /// La ligne de dates du voyage — « 26 août – 15 sept. 2026 ».
    ///
    /// `nil` quand le voyage n'a aucune date : c'est la vue qui décide alors
    /// quoi écrire, et elle pose le tiret de ``BookCopy/Settings/noValue``. Une
    /// ligne de réglage vide se lirait comme une valeur qui n'a pas chargé.
    var dateRangeLabel: String? {
        switch (startDate, endDate) {
        case let (start?, end?) where start < end:
            (start..<end).formatted(.interval.day().month(.abbreviated).year())
        case let (start?, _):
            // Un voyage commencé qui n'a pas de fin : le cas courant d'un
            // carnet ouvert, pas une donnée manquante.
            start.formatted(.dateTime.day().month(.abbreviated).year())
        case (nil, let end?):
            end.formatted(.dateTime.day().month(.abbreviated).year())
        case (nil, nil):
            nil
        }
    }
}
