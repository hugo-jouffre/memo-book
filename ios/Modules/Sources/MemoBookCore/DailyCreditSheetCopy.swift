import Foundation

/// Les textes de la feuille « Crédit du jour », ouverte depuis la ligne du
/// même nom dans les réglages du voyage.
///
/// **La feuille explique, elle ne fait pas la leçon** (Hugo, 03/10/2026) : ce
/// qui reste aujourd'hui, ce que ça représente à l'écrit, les trois règles qui
/// font le crédit, et la porte de l'illimité. Elle remplace celle des limites
/// de souvenirs : la ligne n'est plus un garde-fou discret, c'est le levier de
/// l'abonnement, et elle se lit donc en entier, sans chiffre caché.
///
/// Comme le reste de ``DailyCreditCopy``, **aucun chiffre n'est écrit en dur** :
/// la durée du crédit et le barème de l'écrit sont lus sur le solde servi par
/// le serveur. Si le barème bouge, les phrases suivent.
extension DailyCreditCopy {
    public enum Sheet {
        public static let close = "Fermer"

        /// La grande ligne du haut : « Il reste 3 min 20 aujourd’hui », ou le
        /// constat quand il n'y a plus rien.
        public static func remaining(_ credit: DailyCredit) -> String {
            credit.isExhausted
                ? "Plus rien pour aujourd’hui : reviens demain"
                : "Il reste \(duration(credit.remainingMs)) aujourd’hui"
        }

        /// Ce que VoiceOver lit sur la jauge, qui montre ce qui reste : « 3 min
        /// 20 sur 5 min ». Un pourcentage nu, sous « Il reste… », se
        /// comprenait de travers (03/10/2026).
        public static func gaugeAccessibilityValue(_ credit: DailyCredit) -> String {
            "\(duration(credit.remainingMs)) sur \(duration(credit.limitMs))"
        }

        /// Sous la jauge : ce que le reste vaut au clavier. Rien quand il n'y a
        /// plus rien — « soit environ 0 caractère » ne dirait que l'évidence.
        public static func charactersEquivalent(_ credit: DailyCredit) -> String? {
            guard !credit.isUnlimited, credit.charactersLeft > 0 else { return nil }
            return "soit environ \(characters(credit.charactersLeft)) à l’écrit"
        }

        /// Le partage : le crédit est celui du voyage, pas celui du compte.
        public static func sharing(limitMs: Int) -> String {
            "\(spelledDuration(limitMs)) par jour pour ce voyage, à partager entre les co-voyageurs qui ne sont pas abonnés."
        }

        /// Ce qui consomme, et ce qui ne consomme pas. Les 800 caractères
        /// viennent du barème (une minute divisée par le coût d'un caractère).
        public static func consumption(textMsPerCharacter: Int) -> String {
            let perMinute = textMsPerCharacter > 0 ? 60_000 / textMsPerCharacter : 0
            return "Un vocal consomme sa durée ; à l’écrit, \(characters(perMinute)) valent une minute. Les photos ne consomment rien."
        }

        /// La recharge — minuit, à l'heure de celui qui lit.
        public static let recharge = "Le crédit se recharge chaque nuit, à minuit."

        /// Le paragraphe d'un abonné, à la place de la jauge et du bouton. Il
        /// rappelle ce que l'abonnement n'ouvre pas : ses co-voyageurs non
        /// abonnés partagent toujours le crédit du voyage.
        public static func unlimitedExplanation(limitMs: Int) -> String {
            "Avec ton abonnement, tu racontes sans limite, à l’oral comme à l’écrit, et tes récits ne prennent rien au crédit du voyage. Tes co-voyageurs qui ne sont pas abonnés partagent toujours les \(spelledDuration(limitMs)) du jour."
        }

        /// « 5 minutes », « 1 minute » — en toutes lettres quand la durée tombe
        /// sur une minute ronde, ce qui est le cas du crédit. Sinon la forme
        /// courte de ``DailyCreditCopy/duration(_:)``.
        static func spelledDuration(_ milliseconds: Int) -> String {
            let seconds = max(0, milliseconds) / 1000
            guard seconds >= 60, seconds.isMultiple(of: 60) else { return duration(milliseconds) }
            let minutes = seconds / 60
            return minutes > 1 ? "\(minutes) minutes" : "1 minute"
        }
    }

    /// Ce que VoiceOver lit sur la ligne des réglages : le titre, la légende
    /// et le reste, en une phrase.
    public static func rowAccessibilityLabel(_ credit: DailyCredit) -> String {
        credit.isUnlimited
            ? "\(title), \(unlimited). \(rowCaptionUnlimited)."
            : "\(title), \(rowCaption(limitMs: credit.limitMs)). \(Sheet.remaining(credit))."
    }
}
