import Foundation
import MemoBookCore

// Mise en forme des données du parcours « carnet » : paramètres du voyage,
// aperçu PDF, cagnotte.
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

extension WalletEntry {
    /// La date d'une écriture — « 19 août ».
    ///
    /// **Sans l'année**, comme la maquette : l'historique se lit du plus récent
    /// au plus ancien et tient sur quelques semaines. L'année revient dès que
    /// l'écriture n'est plus de cette année-ci, sans quoi « 19 août » serait
    /// ambigu au bout de douze mois.
    var dateLabel: String {
        let calendar = Calendar.current
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)

        return isThisYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Le montant signé — « +10,00 € », « −8,50 € ».
    ///
    /// Le signe **fait partie du nombre** et vient du formateur : le plus d'un
    /// crédit, comme le moins d'un débit, s'écrit différemment selon la région,
    /// et un `"+"` collé à la main devant se retrouverait du mauvais côté.
    ///
    /// ⚠️ La maquette écrit « +30€ » sur une ligne et « +10,00€ » sur une
    /// autre. On garde **deux décimales partout** : c'est de l'argent, et deux
    /// formats de montant dans la même liste se lisent comme une erreur de
    /// saisie. Écart signalé dans la fiche de la cagnotte.
    var signedAmountLabel: String {
        amount.formatted(
            .currency(code: "EUR")
                .precision(.fractionLength(2))
                .sign(strategy: .always(showZero: false))
        )
    }
}

extension Decimal {
    /// Un montant **arrondi à l'euro quand il tombe juste** — « 60 € », mais
    /// « 5,97 € ».
    ///
    /// Réservé aux deux pastilles de synthèse de la cagnotte, qui sont des
    /// ordres de grandeur et non des lignes de compte : c'est exactement ce que
    /// la maquette écrit, et « 60,00 € » y ferait un chiffre de facture. Les
    /// montants qui comptent, eux, passent par ``euros`` et gardent leurs deux
    /// décimales.
    var roundedEuros: String {
        let isWhole = self == Decimal(NSDecimalNumber(decimal: self).intValue)
        return formatted(.currency(code: "EUR").precision(.fractionLength(isWhole ? 0 : 2)))
    }
}
