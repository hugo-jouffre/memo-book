import Foundation

/// Les mots de l'accueil qui ne vivent pas dans une vue — ceux que les deux
/// apps doivent dire **pareil**, et que les tests peuvent lire.
public enum HomeCopy {
    /// **La corbeille**, tout en bas de l'accueil (Hugo, 10/11/2026) — « j'ai
    /// toujours peur qu'un voyage soit supprimé par inadvertance ».
    ///
    /// Le ton est celui d'un filet, pas d'une alarme : gris, petit, sous
    /// tout le reste. La section ne paraît que s'il y a quelque chose dedans
    /// — une rubrique « Supprimés » vide inquiéterait plus qu'elle ne
    /// rassurerait.
    public enum Trash {
        public static let title = "Supprimés récemment"

        /// Ce que la section promet, en une ligne : la durée, et le geste.
        public static let explanation =
            "Ils s’effacent définitivement au bout de 30 jours. D’ici là, tu peux les récupérer."

        /// Le bouton de chaque ligne.
        public static let restore = "Récupérer"

        /// Ce que VoiceOver lit sur le bouton d'une ligne.
        public static func restoreVoice(title: String) -> String {
            "Récupérer le voyage \(title)"
        }

        /// **Le compte à rebours d'une ligne**, en jours pleins.
        ///
        /// En jours et non en date : « s'efface dans 3 jours » se comprend
        /// sans calculer, là où « le 13 novembre » demande de savoir quel jour
        /// on est. Le dernier jour se dit « aujourd'hui » — c'est le moment où
        /// l'on veut agir, pas celui où l'on veut compter.
        public static func erasesIn(days: Int) -> String {
            switch days {
            case ...0: "S’efface aujourd’hui"
            case 1: "S’efface demain"
            default: "S’efface dans \(days) jours"
            }
        }

        /// Les jours pleins qui restent avant l'effacement — jamais négatifs :
        /// une purge en retard n'affiche pas « dans −2 jours ».
        public static func daysLeft(until purgeAt: Date, from now: Date = Date()) -> Int {
            let seconds = purgeAt.timeIntervalSince(now)
            return max(0, Int(ceil(seconds / 86_400)))
        }
    }
}
