import Foundation
import MemoBookCore

// Mise en forme des chiffres de la feuille « Statistiques ». Les règles vivent
// ici, pas dans la vue, et elles se testent sans simulateur : un accord raté
// (« 1 personnes ») se lit sur chaque ligne de la feuille.

/// Un nombre et son mot, accordés : « 6 pays », « 1 région », « 13 villes ».
///
/// Les deux formes écrites plutôt qu'un « s » collé : « pays » ne bouge pas,
/// « vocal » fait « vocaux ». Le nombre passe par le formateur du système, qui
/// sait qu'un français sépare les milliers d'une espace fine.
///
/// **Zéro prend le singulier**, comme un : « 0 jour validé », pas « 0 jours
/// validés ». C'est la règle du français, et c'est la ligne que la feuille
/// écrit le plus souvent au début d'un voyage.
func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    let number = count.formatted(.number.grouping(.automatic))
    return count <= 1 ? "\(number) \(singular)" : "\(number) \(plural)"
}

extension TravelFigures {
    /// « 6 pays, 8 régions, 13 villes » — la ligne « Étapes » de la feuille.
    ///
    /// **Une part à zéro s'omet.** La maquette n'écrit que des chiffres pleins ;
    /// « 2 pays, 0 région, 7 villes » lirait un manque là où l'agent n'a
    /// simplement rien relevé encore. Tout à zéro, la ligne le dit en clair
    /// plutôt que de rester vide.
    var placesLabel: String {
        let parts = [
            countries > 0 ? counted(countries, "pays", "pays") : nil,
            regions > 0 ? counted(regions, "région", "régions") : nil,
            cities > 0 ? counted(cities, "ville", "villes") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? StatisticsCopy.nothingYet : parts.joined(separator: ", ")
    }

    /// « 406 personnes » — la ligne « Rencontres ».
    var encountersLabel: String {
        encounters > 0 ? counted(encounters, "personne", "personnes") : StatisticsCopy.nothingYet
    }

    /// « 2 280 km » — la ligne « Km parcourus ».
    ///
    /// La maquette écrit « 2.280km », collé et avec un point. On passe par le
    /// formateur du système, comme pour les euros du profil : c'est lui qui
    /// sait comment la région de l'utilisateur sépare les milliers, et l'unité
    /// prend son espace comme le veut `agents/agent-transcription.md` § 6.
    /// L'écart est signalé dans la fiche écran.
    var distanceLabel: String {
        "\(distanceKilometres.formatted(.number.grouping(.automatic))) km"
    }
}

extension CurrentTripStatistics {
    /// « 10/12/2026 - 02/01/2027 », le sous-titre de la carte du voyage en
    /// cours — le même format que la ligne du profil.
    var dateRangeLabel: String? {
        Date.numericRangeLabel(from: startDate, to: endDate)
    }

    /// « Tu es actuellement à Rome. »
    ///
    /// La maquette vouvoie (« Vous êtes actuellement à Rome. ») ; R9 tutoie,
    /// toujours, et c'est ce que le reste de l'écran fait déjà. Signalé dans
    /// la fiche. `nil` tant qu'aucun souvenir ni aucune destination ne situe
    /// le voyageur : on ne dit pas où il est si on ne le sait pas.
    var whereaboutsLabel: String? {
        currentPlace.map { "Tu es actuellement à \($0)." }
    }

    /// « 9 % écrit (2 jours validés sur 21) ».
    ///
    /// Le pourcentage passe par le formateur, qui pose l'espace fine devant le
    /// signe en français ; la maquette le colle. L'accord suit le nombre de
    /// jours validés — « 1 jour validé ».
    var writtenLabel: String {
        let percent = writtenFraction.formatted(.percent.precision(.fractionLength(0)))
        let days = counted(validatedDays, "jour validé", "jours validés")
        return "\(percent) écrit (\(days) sur \(dayCount))"
    }

    /// « 9 % » seul, au centre de l'anneau.
    var writtenPercentLabel: String {
        writtenFraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// « 300 vocaux » — la ligne « Enregistrements ».
    var recordingsLabel: String {
        recordings > 0 ? counted(recordings, "vocal", "vocaux") : StatisticsCopy.nothingYet
    }

    /// « 1 avion, 2 trains, scooter » — la ligne « Transports », dans l'ordre
    /// où le serveur les rend : les plus fréquents d'abord.
    var transportsLabel: String {
        transports.isEmpty
            ? StatisticsCopy.nothingYet
            : transports.map(\.label).joined(separator: ", ")
    }

    /// La part des pays du compte que ce voyage couvre, pour le second anneau.
    /// Un voyage qui couvre deux des six pays visités remplit un tiers.
    func countryFraction(of overall: TravelFigures) -> Double {
        guard overall.countries > 0 else { return figures.countries > 0 ? 1 : 0 }
        return min(1, Double(figures.countries) / Double(overall.countries))
    }
}

extension TravelStatistics {
    /// « 5 voyages », en tête de la première carte.
    var tripCountLabel: String {
        counted(tripCount, "voyage", "voyages")
    }

    /// La ligne qui dit que l'agent travaille : « 3 souvenirs en cours de
    /// lecture ». `nil` quand rien n'attend — la ligne disparaît.
    var detectingLabel: String? {
        guard pendingDetections > 0 else { return nil }
        return pendingDetections == 1
            ? "1 souvenir en cours de lecture"
            : "\(pendingDetections) souvenirs en cours de lecture"
    }
}

extension Date {
    /// « 10/12/2026 - 02/01/2027 » : deux dates **numériques** sur une ligne,
    /// dans l'ordre de la région. Partagé par la ligne « Voyage en cours » du
    /// profil et par la carte de la feuille des statistiques.
    ///
    /// `.twoDigits` des deux côtés : sans ça, `month()` rend le mois en toutes
    /// lettres en français, et deux bornes comme celles-là ne tiennent pas en
    /// bout de ligne.
    static func numericRangeLabel(from start: Date?, to end: Date?) -> String? {
        let numeric = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year()

        return switch (start, end) {
        case let (start?, end?): "\(start.formatted(numeric)) - \(end.formatted(numeric))"
        case let (start?, nil): start.formatted(numeric)
        case let (nil, end?): end.formatted(numeric)
        case (nil, nil): nil
        }
    }
}

/// Les libellés de la feuille qui n'appartiennent pas aux données.
enum StatisticsCopy {
    /// Ce qu'une ligne écrit tant que l'agent n'a rien relevé pour elle. En
    /// clair et non un tiret : un tiret se lit comme une panne.
    static let nothingYet = "Pas encore relevé"
}
