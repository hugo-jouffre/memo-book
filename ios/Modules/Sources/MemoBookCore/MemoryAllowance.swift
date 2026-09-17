import Foundation

// Les **limites de souvenirs** : ce qu'un compte peut raconter dans la semaine.
//
// ⚠️ **Le mot « jeton » n'apparaît nulle part**, et c'est une consigne, pas une
// préférence (Hugo, 16/09/2026). L'unité s'appelle un **souvenir**, et l'app
// compte en souvenirs : « 1 240 sur 3 000 ». Personne n'ouvre MemoBook pour
// gérer un budget de calcul.
//
// Le barème lui-même vit côté serveur (`services/memoryAllowance.ts`) et
// **voyage avec le solde** : ce que coûte un message et ce que coûte une minute
// de vocal sont dans la réponse, pas dans le binaire. La feuille d'extension a
// besoin de les écrire pour expliquer pourquoi un vocal pèse plus — et une
// seconde table de prix dans l'app serait une seconde vérité à tenir d'accord.

/// Le palier de limites d'un compte.
public enum MemoryPlan: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Ce qui est compris. Le palier de tout le monde.
    case included
    /// Le palier étendu, à 3,99 €/semaine.
    case extended

    public var id: String { rawValue }

    /// Le nom du palier, tel que la feuille l'écrit.
    public var title: String {
        switch self {
        case .included: "Limites comprises"
        case .extended: "Limites étendues"
        }
    }
}

/// Où en est un compte de ses limites de souvenirs.
///
/// **Servi avec les réglages du voyage** — comme la cagnotte, et pour la même
/// raison : ça appartient au compte, mais c'est le seul écran qui le montre.
public struct MemoryAllowance: Codable, Sendable, Hashable {
    public var plan: MemoryPlan
    /// Ce qui a été consommé dans la période en cours.
    public var used: Int
    /// Ce que la période ouvre.
    public var allowance: Int
    /// Le jour où le compteur repart à zéro.
    public var renewsOn: Date?
    /// Ce que coûte le palier étendu, **par semaine**.
    ///
    /// Hebdomadaire comme l'abonnement, et pour la même raison : c'est une
    /// option du même produit, pas une seconde offre (Hugo, 17/09/2026).
    public var upgradeWeeklyPrice: Decimal
    /// Ce qu'un message écrit consomme.
    public var textCost: Int
    /// Ce qu'une **minute entamée** de vocal consomme.
    public var voiceCostPerMinute: Int

    public init(
        plan: MemoryPlan = .included,
        used: Int = 0,
        allowance: Int = 2_000,
        renewsOn: Date? = nil,
        upgradeWeeklyPrice: Decimal = 3.99,
        textCost: Int = 1,
        voiceCostPerMinute: Int = 10
    ) {
        self.plan = plan
        self.used = used
        self.allowance = allowance
        self.renewsOn = renewsOn
        self.upgradeWeeklyPrice = upgradeWeeklyPrice
        self.textCost = textCost
        self.voiceCostPerMinute = voiceCostPerMinute
    }

    /// Décodage tolérant : un serveur qui ne sert pas encore le barème ne doit
    /// pas faire échouer tout l'écran des réglages. On retombe alors sur les
    /// valeurs par défaut, qui sont celles du catalogue.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeIfPresent(MemoryPlan.self, forKey: .plan) ?? .included
        used = try container.decodeIfPresent(Int.self, forKey: .used) ?? 0
        allowance = try container.decodeIfPresent(Int.self, forKey: .allowance) ?? 2_000
        renewsOn = try container.decodeIfPresent(Date.self, forKey: .renewsOn)
        upgradeWeeklyPrice =
            try container.decodeIfPresent(Decimal.self, forKey: .upgradeWeeklyPrice) ?? 3.99
        textCost = try container.decodeIfPresent(Int.self, forKey: .textCost) ?? 1
        voiceCostPerMinute =
            try container.decodeIfPresent(Int.self, forKey: .voiceCostPerMinute) ?? 10
    }

    // MARK: Ce que la jauge lit

    /// Ce qu'il reste. Jamais négatif : un dépassement — un barème réétalonné
    /// entre deux périodes — se lit « 0 restant », pas « -40 ».
    public var remaining: Int { max(0, allowance - used) }

    /// Où en est la jauge, entre 0 et 1.
    public var fraction: Double {
        guard allowance > 0 else { return 0 }
        return min(1, Double(used) / Double(allowance))
    }

    /// **Le seuil à partir duquel on le dit.** En dessous, la ligne affiche son
    /// solde sans rien réclamer : cette limite est un garde-fou, pas un levier,
    /// et quelqu'un qui en a consommé un tiers n'a rien à décider.
    public static let warningFraction = 0.8

    /// Il est temps de proposer d'étendre.
    public var isRunningLow: Bool {
        plan == .included && fraction >= Self.warningFraction
    }

    /// Plus rien. Le micro et l'envoi se ferment — le serveur refuse de son
    /// côté avec `memory_limit_reached`.
    public var isExhausted: Bool { remaining == 0 }

    /// Ce que le palier étendu ouvrirait. Un multiple et non un nombre écrit à
    /// la main : si le barème bouge, la phrase suit.
    public func multiplier(over extendedAllowance: Int) -> Int {
        guard allowance > 0 else { return 1 }
        return max(1, extendedAllowance / allowance)
    }
}
