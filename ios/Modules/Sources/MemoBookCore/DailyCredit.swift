import Foundation

/// **Le crédit du jour d'un voyage** (Hugo, 03/10/2026).
///
/// Tout le monde raconte gratuitement, dans la limite de **5 minutes par jour
/// et par voyage**, partagées entre les co-voyageurs qui ne sont pas abonnés.
/// Un seul crédit pour le vocal et l'écrit : un vocal consomme sa durée, un
/// texte une minute pour 800 caractères. Les photos ne consomment rien.
/// L'abonnement mensuel rend le récit illimité — **pour l'abonné seul** : il ne
/// prend rien au pot commun, et n'en ouvre pas un second à ses co-voyageurs.
///
/// **Le serveur tranche, l'app prévient.** `services/dailyCredit.ts` mesure
/// chaque vocal, décompte dans la même transaction que la bulle, et refuse
/// au-delà (`429 daily_credit_exhausted`). Ce que l'app tient ici sert à
/// prévenir à 4:30, à faire pulser à 4:55 et à couper net à 5:00 — jamais à
/// décider seule : les seuils et le barème **voyagent avec le solde**, pour
/// qu'il n'y ait qu'une vérité à tenir d'accord.
///
/// Les durées sont en **millisecondes de crédit**, comme côté serveur : un
/// texte en consomme 75 par caractère, et un vocal arrondi à la seconde aurait
/// laissé passer une demi-seconde à chaque envoi.
public struct DailyCredit: Codable, Sendable, Hashable {
    /// Celui qui lit raconte sans limite : il est abonné.
    public var isUnlimited: Bool
    /// Ce que le voyage peut raconter par jour.
    public var limitMs: Int
    /// Ce que le voyage a déjà raconté aujourd'hui, co-voyageurs compris.
    public var usedMs: Int
    /// Ce qu'un caractère écrit consomme.
    public var textMsPerCharacter: Int
    /// Le reste à partir duquel la barre d'enregistrement prévient (30 s).
    public var warningRemainingMs: Int
    /// Le reste à partir duquel l'avertissement pulse (5 s).
    public var urgentRemainingMs: Int
    /// Le reste **en dessous duquel le pot est vide** (1 s) — la règle
    /// `EXHAUSTION_SLACK_MS` du serveur, qui arrondit à zéro un reste de
    /// quelques millisecondes après un tour. Voir ``isExhausted``.
    public var exhaustionSlackMs: Int
    /// Le jour local du crédit, `AAAA-MM-JJ`.
    public var day: String?
    /// L'instant où le crédit se recharge — minuit, chez celui qui lit.
    public var resetsAt: Date?

    /// Le barème servi par défaut, celui du catalogue du serveur. Il ne sert
    /// qu'au décodage d'une réponse incomplète et aux aperçus : la valeur qui
    /// compte arrive toujours avec le solde.
    public enum Catalog {
        public static let limitMs = 300_000
        public static let textMsPerCharacter = 75
        public static let warningRemainingMs = 30_000
        public static let urgentRemainingMs = 5_000
        /// Ce qu'un dernier vocal peut dépasser du reste (`VOICE_TOLERANCE_MS`).
        /// Le serveur ne le sert pas avec le solde : il ne sert qu'à reconnaître
        /// un tour qui ne tiendra **jamais** dans une journée — voir
        /// ``DailyCredit/limitWithTolerance(forVoice:)``.
        public static let voiceToleranceMs = 3_000
        /// Le reste en dessous duquel le pot est vide (`EXHAUSTION_SLACK_MS`).
        /// Moins d'une seconde ne raconte rien : le serveur l'arrondit à zéro
        /// après un tour, l'app le lit de même — sans quoi elle ouvrirait le
        /// micro pour 400 ms, qu'elle refermerait aussitôt.
        public static let exhaustionSlackMs = 1_000
    }

    public init(
        isUnlimited: Bool = false,
        limitMs: Int = Catalog.limitMs,
        usedMs: Int = 0,
        textMsPerCharacter: Int = Catalog.textMsPerCharacter,
        warningRemainingMs: Int = Catalog.warningRemainingMs,
        urgentRemainingMs: Int = Catalog.urgentRemainingMs,
        exhaustionSlackMs: Int = Catalog.exhaustionSlackMs,
        day: String? = nil,
        resetsAt: Date? = nil
    ) {
        self.isUnlimited = isUnlimited
        self.limitMs = limitMs
        self.usedMs = usedMs
        self.textMsPerCharacter = textMsPerCharacter
        self.warningRemainingMs = warningRemainingMs
        self.urgentRemainingMs = urgentRemainingMs
        self.exhaustionSlackMs = exhaustionSlackMs
        self.day = day
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case isUnlimited, limitMs, usedMs, textMsPerCharacter
        case warningRemainingMs, urgentRemainingMs, exhaustionSlackMs, day, resetsAt
    }

    /// Décodage tolérant : un serveur qui ne sert pas encore un champ ne doit
    /// pas faire tomber le fil ni les réglages. On retombe sur le catalogue.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited) ?? false
        limitMs = try container.decodeIfPresent(Int.self, forKey: .limitMs) ?? Catalog.limitMs
        usedMs = try container.decodeIfPresent(Int.self, forKey: .usedMs) ?? 0
        textMsPerCharacter =
            try container.decodeIfPresent(Int.self, forKey: .textMsPerCharacter)
            ?? Catalog.textMsPerCharacter
        warningRemainingMs =
            try container.decodeIfPresent(Int.self, forKey: .warningRemainingMs)
            ?? Catalog.warningRemainingMs
        urgentRemainingMs =
            try container.decodeIfPresent(Int.self, forKey: .urgentRemainingMs)
            ?? Catalog.urgentRemainingMs
        // Servi depuis le 03/10/2026 ; un serveur d'avant ne le dit pas, et
        // sa règle est la même.
        exhaustionSlackMs =
            try container.decodeIfPresent(Int.self, forKey: .exhaustionSlackMs)
            ?? Catalog.exhaustionSlackMs
        day = try container.decodeIfPresent(String.self, forKey: .day)
        resetsAt = try? container.decodeIfPresent(Date.self, forKey: .resetsAt)
    }

    // MARK: - Ce qui reste

    /// Ce qu'il reste aujourd'hui. Jamais négatif.
    public var remainingMs: Int { max(0, limitMs - usedMs) }

    /// Plus rien pour aujourd'hui. Un abonné n'est jamais à court.
    ///
    /// **Moins d'une seconde, c'est plus rien** (03/10/2026) — comme au
    /// serveur (`EXHAUSTION_SLACK_MS`). Le serveur ne laisse jamais ce reste ;
    /// une estimation locale — un vocal arrêté à 0:59,6 hors ligne sur une
    /// minute — ou un solde d'avant la règle, si. Lu « restant », il gardait
    /// le micro ouvert pour un vocal de 400 ms, coupé aussitôt, puis refusé
    /// au retour du réseau : une bulle vide « Partira demain ».
    public var isExhausted: Bool { !isUnlimited && remainingMs < max(1, exhaustionSlackMs) }

    /// Où en est la jauge, entre 0 et 1.
    public var fraction: Double {
        guard limitMs > 0 else { return 1 }
        return min(1, Double(usedMs) / Double(limitMs))
    }

    /// Ce qu'il resterait une fois le vocal en cours compté.
    ///
    /// **Une projection, jamais un décompte** (Hugo, 06/10/2026) : elle ne
    /// sert qu'au bandeau et à l'arrêt net **pendant que le vocal existe** —
    /// en cours ou en pause. Rien ne l'écrit dans un crédit : un vocal mis en
    /// pause puis abandonné ne coûte rien, nulle part. Seul l'envoyé compte —
    /// le serveur à sa réception, l'app entre-temps pour ce qui attend la file
    /// (la conversation, l'accueil, les réglages du voyage).
    public func remainingMs(whileRecording elapsedMs: Int) -> Int {
        max(0, remainingMs - max(0, elapsedMs))
    }

    /// Le même crédit, ce qu'on vient d'envoyer décompté — l'estimation que
    /// l'app tient entre deux réponses du serveur, hors ligne surtout. Un
    /// reste de moins d'une seconde s'arrondit à zéro, comme le serveur le
    /// fera en recevant le tour (``Catalog/exhaustionSlackMs``).
    public func consuming(_ milliseconds: Int) -> DailyCredit {
        guard !isUnlimited, milliseconds > 0 else { return self }
        var copy = self
        copy.usedMs = min(limitMs, usedMs + milliseconds)
        if limitMs - copy.usedMs < exhaustionSlackMs { copy.usedMs = max(copy.usedMs, limitMs) }
        return copy
    }

    /// Le même crédit, **rechargé** si son heure de recharge est passée : rien
    /// de consommé, le barème et `isUnlimited` gardés (03/10/2026).
    ///
    /// Un crédit gardé — le cache de l'accueil, le dernier qu'un fil a connu —
    /// ne se relit jamais tel quel : épuisé hier à 22 h 30, il dirait encore
    /// « épuisé » ce matin dans l'avion, et le micro refuserait un vocal que la
    /// file aurait gardé. Chaque lecture d'un crédit gardé passe donc par ici —
    /// le fil et la feuille d'enregistrement, l'accueil et les réglages.
    ///
    /// La recharge suivante est **le même minuit, autant de jours plus tard
    /// qu'il faut** : le crédit rechargé garde un compte à rebours juste, et se
    /// rechargera encore s'il dort une nuit de plus. `day` tombe, faute de
    /// savoir l'écrire au fuseau du serveur ; le serveur le redira.
    public func refreshed(now: Date = .now, calendar: Calendar = .current) -> DailyCredit {
        guard let resetsAt, resetsAt <= now else { return self }
        var copy = self
        copy.usedMs = 0
        copy.day = nil
        let elapsedDays = calendar.dateComponents([.day], from: resetsAt, to: now).day ?? 0
        var next = calendar.date(byAdding: .day, value: max(0, elapsedDays), to: resetsAt) ?? now
        while next <= now {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? now.addingTimeInterval(86_400)
        }
        copy.resetsAt = next
        return copy
    }

    /// **Le plus avancé de deux crédits servis** pour le même voyage
    /// (03/10/2026) — les caches de l'écran du voyage et de l'accueil, le
    /// dernier qu'un fil a connu, un mot rejoué par la file. Aucun ne sait
    /// lequel est le plus frais : chacun a été écrit à sa dernière lecture.
    /// Mais la consommation d'une journée **ne fait que croître**, et le jour
    /// ne recule jamais (`services/dailyCredit.ts`). Donc :
    ///
    /// 1. le jour le plus tardif l'emporte — `day` quand les deux le portent,
    ///    sinon l'heure de recharge (un crédit rechargé par
    ///    ``refreshed(now:calendar:)`` n'a plus de `day`) ;
    /// 2. à jour égal, le plus consommé ;
    /// 3. illimité dès que l'un des deux le dit — le lecteur est abonné, et
    ///    un crédit servi avant l'achat ne le sait pas encore.
    ///
    /// Le premier trouvé gagnait jusqu'ici : un cache du matin à 5:00 passait
    /// devant celui de l'accueil, relu après un vocal de 4 minutes, et le fil
    /// hors ligne laissait dicter ce que le serveur refuserait.
    public func merged(with other: DailyCredit?) -> DailyCredit {
        guard let other else { return self }
        var latest: DailyCredit
        switch Self.dayOrder(self, other) {
        case .orderedAscending: latest = other
        case .orderedDescending: latest = self
        case .orderedSame: latest = other.usedMs > usedMs ? other : self
        }
        latest.isUnlimited = isUnlimited || other.isUnlimited
        return latest
    }

    /// Lequel des deux crédits est d'un jour plus tardif. `orderedSame`
    /// quand c'est le même jour, ou qu'on ne sait pas les départager.
    private static func dayOrder(_ a: DailyCredit, _ b: DailyCredit) -> ComparisonResult {
        // `AAAA-MM-JJ` se range dans l'ordre des jours.
        if let dayA = a.day, let dayB = b.day {
            return dayA == dayB ? .orderedSame : (dayA < dayB ? .orderedAscending : .orderedDescending)
        }
        if let resetA = a.resetsAt, let resetB = b.resetsAt {
            return resetA == resetB ? .orderedSame : (resetA < resetB ? .orderedAscending : .orderedDescending)
        }
        return .orderedSame
    }

    /// Le plus long tour qu'une journée entière laisse passer : la limite, et
    /// pour un vocal la tolérance du serveur en plus. Au-delà, attendre demain
    /// ne servirait à rien — le pot plein le refuserait encore.
    public func limitWithTolerance(forVoice isVoice: Bool) -> Int {
        isVoice ? limitMs + Catalog.voiceToleranceMs : limitMs
    }

    // MARK: - L'écrit

    /// Ce qu'un texte consomme. Les caractères se comptent en **scalaires
    /// Unicode**, comme le serveur (`[...text].length`) : un emoji composé ne
    /// coûte pas la même chose selon qu'on compte en UTF-16 ou en graphèmes, et
    /// les deux côtés doivent tomber sur le même nombre.
    public func cost(ofText text: String) -> Int {
        text.unicodeScalars.count * textMsPerCharacter
    }

    /// Ce texte part-il encore aujourd'hui ? Rien sur un pot vide — moins
    /// d'une seconde compris (``isExhausted``).
    public func allows(text: String) -> Bool {
        isUnlimited || (!isExhausted && cost(ofText: text) <= remainingMs)
    }

    /// Combien de caractères le reste du jour laisse écrire. Aucun sur un pot
    /// vide : « il te reste environ 5 caractères » sous « crédit épuisé »
    /// ferait deux phrases qui se contredisent.
    public var charactersLeft: Int {
        guard textMsPerCharacter > 0, !isExhausted else { return 0 }
        return remainingMs / textMsPerCharacter
    }

    // MARK: - La barre d'enregistrement

    /// Ce que la barre d'enregistrement montre, à un reste donné.
    public enum Phase: Sendable, Hashable {
        /// Rien à dire.
        case calm
        /// Moins de 30 secondes : l'avertissement rouge, doux, paraît.
        case warning
        /// Moins de 5 secondes : il pulse.
        case urgent
        /// Plus rien : l'enregistrement s'arrête net.
        case exhausted
    }

    /// La phase pour un reste donné — celui du jour, ou celui qui reste
    /// pendant qu'on parle (``remainingMs(whileRecording:)``).
    public func phase(remainingMs remaining: Int) -> Phase {
        guard !isUnlimited else { return .calm }
        if remaining <= 0 { return .exhausted }
        if remaining <= urgentRemainingMs { return .urgent }
        if remaining <= warningRemainingMs { return .warning }
        return .calm
    }

    /// La phase avant de commencer à parler : « épuisé » dès que le pot est
    /// vide au sens du serveur (``isExhausted``), moins d'une seconde
    /// comprise — on n'ouvre pas le micro pour la refermer aussitôt.
    public var phase: Phase { isExhausted ? .exhausted : phase(remainingMs: remainingMs) }
}

/// Les textes du crédit du jour : la barre d'enregistrement, la ligne et la
/// feuille des réglages du voyage, la bulle « reviens demain ».
///
/// **Doux, mais explicite** (Hugo, 03/10/2026) : on dit ce qui reste et ce qui
/// se passe, sans faire la leçon. Le chiffre de la limite est lu sur le solde,
/// jamais écrit en dur : si le barème bouge, les phrases suivent.
public enum DailyCreditCopy {
    public static let title = "Crédit du jour"
    public static let unlimited = "Illimité"

    /// « 5 min », « 3 min 20 », « 45 s ». Arrondi à la seconde **inférieure**
    /// pendant un compte à rebours : annoncer 30 s quand il en reste 29,6
    /// promettrait une demi-seconde qui n'existe pas.
    public static func duration(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes == 0 { return "\(rest) s" }
        if rest == 0 { return "\(minutes) min" }
        return rest < 10 ? "\(minutes) min 0\(rest)" : "\(minutes) min \(rest)"
    }

    /// « 2 650 caractères », séparateur de milliers français (espace fine
    /// insécable).
    public static func characters(_ count: Int) -> String {
        let formatted = count.formatted(.number.locale(Locale(identifier: "fr_FR")))
        return count > 1 ? "\(formatted) caractères" : "\(formatted) caractère"
    }

    // — La barre d'enregistrement

    /// L'avertissement, à partir de 30 secondes. Le nombre descend avec le
    /// temps : on lit le compte à rebours, pas une alerte figée.
    public static func warning(remainingMs: Int) -> String {
        let seconds = max(0, remainingMs) / 1000
        return seconds > 1
            ? "Plus que \(seconds) secondes avant la limite du jour"
            : "Plus qu’une seconde avant la limite du jour"
    }

    public static let exhaustedTitle = "Crédit du jour épuisé"
    public static let exhaustedDetail = "Reviens demain, ou passe en illimité"
    public static let unlimitedCallToAction = "Passer en illimité"

    /// Le texte dépasse ce qu'il reste aujourd'hui.
    public static func textTooLong(charactersLeft: Int) -> String {
        charactersLeft > 0
            ? "Ce message dépasse le crédit du jour : il te reste environ \(characters(charactersLeft))."
            : "Le crédit du jour est épuisé : reviens demain pour écrire la suite."
    }

    /// La bulle de MEMO quand le crédit tombe à zéro. **La même phrase que le
    /// serveur** (`DAILY_CREDIT_EXHAUSTED_MESSAGE`, `conversationCopy.ts`) :
    /// l'app la pose elle-même hors ligne, le serveur la pose en ligne.
    public static let exhaustedMessage =
        "Quelle journée ! Ce voyage a déjà raconté ses 5 minutes du jour. Je garde tout précieusement : reviens demain pour la suite, le crédit se recharge à minuit."

    // — Les réglages du voyage

    /// La légende de la ligne, pour qui n'est pas abonné.
    public static func rowCaption(limitMs: Int) -> String {
        "\(duration(limitMs)) par jour pour tout le voyage"
    }

    public static let rowCaptionUnlimited = "Tu racontes sans limite grâce à ton abonnement"

    /// « 3 min 20 / 5 min ».
    public static func rowValue(_ credit: DailyCredit) -> String {
        credit.isUnlimited
            ? unlimited
            : "\(duration(credit.remainingMs)) / \(duration(credit.limitMs))"
    }
}
