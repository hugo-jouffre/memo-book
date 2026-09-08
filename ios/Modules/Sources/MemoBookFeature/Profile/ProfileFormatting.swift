import Foundation
import MemoBookCore

// Mise en forme des valeurs du profil. Les règles vivent ici, pas dans les
// vues : un montant s'écrit pareil dans la ligne « Ma cagnotte » et dans le
// libellé du bouton d'abonnement.

extension Decimal {
    /// Un montant en euros, écrit selon la région de l'utilisateur.
    ///
    /// La maquette écrit « 67,88€ », collé. On passe quand même par le
    /// formateur du système : c'est lui qui sait qu'un français attend une
    /// espace insécable avant le symbole, et qu'un lecteur d'une autre région
    /// attend autre chose. L'écart est signalé dans la fiche écran.
    var euros: String {
        formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
}

extension CurrentTrip {
    /// « 10/12/2026 - 02/01/2027 », la ligne du voyage en cours dans la carte
    /// de chiffres du profil.
    ///
    /// Des dates **numériques** ici, alors que les cartes de l'accueil écrivent
    /// « 26 août – 15 sept. 2026 » : la ligne est courte, poussée à droite d'un
    /// intitulé, et deux mois abrégés n'y tiendraient pas. Le format reste celui
    /// de la région de l'utilisateur — c'est `FormatStyle` qui met le jour avant
    /// le mois en France et l'inverse ailleurs.
    var dateRangeLabel: String? {
        // `.twoDigits` des deux côtés : sans ça, `month()` rend le mois en
        // toutes lettres en français — « 26 août 2026 » — et deux bornes comme
        // celles-là ne tiennent pas en bout de ligne. L'ordre des composants,
        // lui, reste celui de la région.
        let numeric = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year()

        return switch (startDate, endDate) {
        case let (start?, end?): "\(start.formatted(numeric)) - \(end.formatted(numeric))"
        case let (start?, nil): start.formatted(numeric)
        case let (nil, end?): end.formatted(numeric)
        case (nil, nil): nil
        }
    }
}

extension TravellerProfile {
    /// « 5 voyages ». Le chiffre de la carte, accordé.
    var tripCountLabel: String {
        tripCount <= 1 ? "\(tripCount) voyage" : "\(tripCount) voyages"
    }

    /// La pastille du haut de l'écran.
    ///
    /// Contrairement à celle de l'accueil, elle est **toujours là** : le profil
    /// est l'endroit où l'on vient voir ce que vaut son compte, et un abonné y
    /// a le droit de lire qu'il est abonné. Voir ``FreemiumStatus``.
    var statusPill: String { freemiumStatus.pillLabel }
}
