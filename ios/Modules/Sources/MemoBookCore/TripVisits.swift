import Foundation

/// **La règle qui décide si l'app s'ouvre sur un voyage** (T268, Hugo,
/// 05/11/2026 — « revenir deux fois sur un voyage en 24 h devrait ouvrir l'app
/// directement sur ce voyage »).
///
/// Quand on raconte un voyage en cours, on y revient plusieurs fois par jour,
/// et on repasse à chaque fois par un accueil qui ne sert à rien. Au bout de
/// deux visites dans la journée, l'app l'admet.
///
/// Ici, **la décision seule** : des dates en entrée, un identifiant ou rien en
/// sortie. Ce qui la garde sur le disque vit dans `RecentTripVisits`
/// (`MemoBookFeature`), parce que `UserDefaults` n'a pas sa place dans ce
/// module — et parce qu'une règle sans dépendance se teste.
public enum TripVisits {
    /// Deux visites, pas une. Une seule ne dit rien : on ouvre un voyage pour
    /// le regarder. Deux disent qu'on y travaille.
    public static let visitesRequises = 2

    /// La fenêtre qui compte, et au-delà de laquelle tout s'oublie.
    public static let fenetre: TimeInterval = 24 * 60 * 60

    /// Les visites qui comptent encore, les autres jetées.
    ///
    /// ⚠️ **Une visite dans le futur est gardée.** L'horloge d'un téléphone
    /// peut reculer — fuseau, réglage manuel, synchronisation — et jeter ces
    /// visites-là ferait oublier la journée en cours au pire moment.
    public static func recentes(
        _ visites: [String: [Date]],
        maintenant: Date = .now,
    ) -> [String: [Date]] {
        let plancher = maintenant.addingTimeInterval(-fenetre)
        return visites.reduce(into: [:]) { gardees, paire in
            let recentes = paire.value.filter { $0 > plancher }
            if !recentes.isEmpty { gardees[paire.key] = recentes }
        }
    }

    /// Le voyage sur lequel ouvrir, ou `nil` pour l'accueil.
    ///
    /// Le plus récemment visité parmi ceux qui ont assez de visites : revenir
    /// sur deux voyages dans la même journée est rare, mais c'est le dernier
    /// qu'on avait en tête.
    public static func voyageAReprendre(
        _ visites: [String: [Date]],
        maintenant: Date = .now,
    ) -> String? {
        recentes(visites, maintenant: maintenant)
            .filter { $0.value.count >= visitesRequises }
            .max { gauche, droite in
                (gauche.value.max() ?? .distantPast) < (droite.value.max() ?? .distantPast)
            }?
            .key
    }

    /// Ajoute une visite **délibérée** et rend la trace nettoyée.
    ///
    /// ⚠️ **Une ouverture automatique ne s'enregistre jamais ici.** Sans cette
    /// règle, la trace s'auto-entretient : l'app ouvre le voyage, l'ouverture
    /// compte, la condition reste vraie, et l'accueil devient inatteignable au
    /// lancement — pour toujours. Seul un geste depuis l'accueil appelle ceci.
    public static func enNotant(
        _ tripId: String,
        dans visites: [String: [Date]],
        maintenant: Date = .now,
    ) -> [String: [Date]] {
        var toutes = visites
        toutes[tripId, default: []].append(maintenant)
        return recentes(toutes, maintenant: maintenant)
    }
}
