import Foundation

// Ce que MEMO lit dans un message avant de répondre.
//
// **Des fonctions pures, et rien d'autre.** Aucun réseau, aucune horloge, aucun
// aléatoire : le même message rend toujours les mêmes signaux. C'est ce qui
// permet de tester le moteur de réponse phrase par phrase dans
// `MemoBookCoreTests`, sans simulateur — et c'est la raison pour laquelle tout
// ça vit dans `MemoBookCore`, qui n'a aucune dépendance.
//
// **Le principe : des marqueurs, pas un dictionnaire.** On ne cherche pas à
// comprendre le français, on cherche des indices sûrs — une préposition devant
// un mot capitalisé, une unité derrière un nombre, un point d'interrogation
// final. Un indice manquant ne coûte qu'une relance moins précise ; un indice
// faux fait dire une bêtise, et c'est ça qu'on évite.

/// Les indices relevés dans un message du voyageur.
public struct ChatSignals: Sendable, Hashable {
    /// Combien il y a de matière. C'est le premier signal, et souvent le seul
    /// qui compte : deux mots ne font pas une page.
    public enum Length: Sendable, Hashable {
        /// Moins de 25 caractères. On demande **un** détail précis.
        case tooShort
        /// Jusqu'à 140 caractères.
        case brief
        /// Jusqu'à 400 caractères.
        case substantial
        /// Au-delà. On propose un découpage, on ne demande **pas** plus.
        case long
    }

    public enum Mood: Sendable, Hashable {
        case positive
        case negative
        case neutral
    }

    /// Les six sujets sur lesquels MEMO sait légitimement répondre. Tout le
    /// reste passe par le repli honnête — voir ``ChatCopy/Answer/unknown``.
    public enum Subject: Sendable, Hashable {
        case book
        case subscription
        case photos
        case corrections
        case pace
    }

    public var length: Length
    public var sentenceCount: Int

    /// Le message situe le souvenir dans le temps.
    public var hasWhen: Bool

    /// Les lieux, **verbatim** et dans l'ordre d'apparition. MEMO les répète, il
    /// ne les complète pas.
    public var places: [String]

    /// Les prénoms, verbatim. Un même mot ne peut pas être à la fois lieu et
    /// personne : c'est la préposition qui tranche.
    public var people: [String]

    public var isQuestion: Bool
    public var subject: Subject?
    public var mood: Mood

    /// Le voyageur ne veut plus répondre. **Ce signal gagne sur tous les
    /// autres** : `agents/agent-conversation.md` dit « ne jamais insister ».
    public var isRefusal: Bool

    /// Les chiffres avec leur unité, recopiés tels quels — « 12 km », « 35 € ».
    /// Le moteur ne convertit ni n'additionne : une métadonnée fausse est pire
    /// qu'absente.
    public var figures: [String]

    /// Le message ne porte aucun indice fort. La relance passe alors par la
    /// rotation neutre.
    public var isBare: Bool {
        !isQuestion && !isRefusal && places.isEmpty && people.isEmpty && figures.isEmpty
            && mood == .neutral
    }
}

extension ChatSignals {
    /// Lit un message. C'est **le** point d'entrée de l'analyse.
    public static func read(_ text: String) -> ChatSignals {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = Tokenizer.tokens(of: trimmed)
        let folded = Tokenizer.fold(trimmed)

        // Les personnes d'abord : « avec Mila » est un signal bien plus sûr que
        // « de Testaccio ». Un mot déjà retenu comme quelqu'un ne peut plus être
        // un lieu, ce qui évite à MEMO de demander ce qui l'a marqué « là-bas »
        // à propos d'une personne.
        let people = Extraction.people(in: tokens, excluding: [])
        let places = Extraction.places(in: tokens, excluding: Set(people))
        let length = Self.length(of: trimmed)

        return ChatSignals(
            length: length,
            sentenceCount: Extraction.sentenceCount(of: trimmed),
            hasWhen: Lexicon.timeMarkers.contains(where: folded.contains)
                || Extraction.hasClockTime(in: tokens)
                || Extraction.hasCalendarDate(in: tokens),
            places: places,
            people: people,
            isQuestion: Extraction.isQuestion(trimmed, folded: folded),
            subject: Extraction.subject(in: folded),
            mood: Extraction.mood(in: folded),
            isRefusal: Extraction.isRefusal(in: folded, length: length),
            figures: Extraction.figures(in: tokens)
        )
    }

    private static func length(of text: String) -> Length {
        switch text.count {
        case ..<25: .tooShort
        case ..<141: .brief
        case ..<401: .substantial
        default: .long
        }
    }
}

// MARK: - Découpage du message

/// Un mot du message, sous ses deux formes : celle qu'on réaffiche et celle sur
/// laquelle on compare.
struct ChatToken: Sendable, Hashable {
    /// Le mot tel qu'il a été écrit. C'est **lui** qui repart dans une réponse.
    let text: String

    /// Le même, sans accents ni majuscules, apostrophe normalisée. Uniquement
    /// pour comparer.
    let folded: String

    /// Le mot ouvre une phrase. Une majuscule y est grammaticale et ne dit donc
    /// rien : c'est ce qui évite de prendre « Hier » pour un prénom.
    let opensSentence: Bool

    var isCapitalized: Bool { text.first?.isUppercase == true }
}

enum Tokenizer {
    /// Sans accents, en minuscules, apostrophes droites. Le repli est fait avec
    /// la locale française : c'est elle qui sait que « œ » vaut « oe ».
    static func fold(_ text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
    }

    /// Les terminaisons de phrase. Une majuscule qui les suit est grammaticale.
    private static let terminators: Set<Character> = [".", "!", "?", "…", "\n"]

    static func tokens(of text: String) -> [ChatToken] {
        var tokens: [ChatToken] = []
        var current = ""
        var opensSentence = true

        func flush() {
            guard !current.isEmpty else { return }
            tokens.append(
                ChatToken(text: current, folded: fold(current), opensSentence: opensSentence)
            )
            current = ""
            opensSentence = false
        }

        for character in text {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flush()
                if terminators.contains(character) { opensSentence = true }
            }
        }
        flush()

        return tokens
    }
}

// MARK: - Les relevés

enum Extraction {
    static func sentenceCount(of text: String) -> Int {
        let sentences = text.split(whereSeparator: { ".!?…".contains($0) })
        return max(1, sentences.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)
    }

    // MARK: Les lieux

    /// Un mot capitalisé précédé d'une préposition de lieu, ou un nom de lieu
    /// générique. Pas de gazetteer : « Trastevere » ne figure dans aucune liste,
    /// et c'est bien le but.
    ///
    /// Les prépositions se lisent en deux temps. « à », « vers », « depuis »
    /// désignent un lieu à elles seules. « de » ne dit rien — « le marché de
    /// Testaccio » est un lieu, « l'appartement de Camille » est quelqu'un —, et
    /// n'est donc retenu que s'il **suit un nom de lieu générique** de quelques
    /// mots. C'est cette condition-là qui évite à MEMO de demander ce qui l'a
    /// marqué « là-bas » à propos d'une personne.
    static func places(in tokens: [ChatToken], excluding people: Set<String> = []) -> [String] {
        var found: [String] = []

        for (index, token) in tokens.enumerated() {
            if Lexicon.commonPlaces.contains(token.folded) {
                // Un nom de lieu générique ne compte que derrière un
                // **déterminant** : « le marché » est un endroit, « on a
                // marché » est un verbe. Sans cette condition, MEMO répondait
                // « marché, je note. Qu'est-ce qui t'a marqué là-bas ? » à
                // quelqu'un qui disait simplement avoir marché.
                guard index > 0, Lexicon.determiners.contains(tokens[index - 1].folded) else {
                    continue
                }
                append(token.text.lowercased(), to: &found)
                continue
            }

            guard token.isCapitalized,
                !Lexicon.stopWords.contains(token.folded),
                !people.contains(token.text),
                index > 0
            else { continue }

            let previous = tokens[index - 1].folded
            if Lexicon.placePrepositions.contains(previous) {
                append(token.text, to: &found)
            } else if Lexicon.weakPlacePrepositions.contains(previous),
                followsAGenericPlace(before: index, in: tokens)
            {
                append(token.text, to: &found)
            }
        }

        return found
    }

    /// Un nom de lieu générique dans les trois mots qui précèdent. Trois, parce
    /// que « le marché couvert de Testaccio » en compte deux entre les deux.
    private static func followsAGenericPlace(before index: Int, in tokens: [ChatToken]) -> Bool {
        let start = max(0, index - 4)
        return tokens[start..<index].contains { Lexicon.commonPlaces.contains($0.folded) }
    }

    // MARK: Les personnes

    /// Un mot capitalisé qui **n'ouvre pas** la phrase, précédé d'un possessif ou
    /// d'un « avec ».
    ///
    /// « et » ne compte qu'après une première personne déjà trouvée : sans cette
    /// condition, « et Rome était belle » ferait de Rome quelqu'un. C'est le
    /// motif « avec Léa et Tom » qu'on veut attraper, et lui seul.
    static func people(in tokens: [ChatToken], excluding places: Set<String>) -> [String] {
        var found: [String] = []

        for (index, token) in tokens.enumerated() {
            guard token.isCapitalized,
                !token.opensSentence,
                !Lexicon.stopWords.contains(token.folded),
                !places.contains(token.text)
            else { continue }

            guard index > 0 else { continue }
            let previous = tokens[index - 1].folded

            let isIntroduced =
                Lexicon.personPrepositions.contains(previous)
                || (previous == "et" && !found.isEmpty)
            guard isIntroduced else { continue }

            append(token.text, to: &found)
        }

        return found
    }

    // MARK: Le temps

    /// « 18h », « 18 h 30 ». Un nombre plausible comme heure suivi d'un « h ».
    static func hasClockTime(in tokens: [ChatToken]) -> Bool {
        for (index, token) in tokens.enumerated() {
            // « 18h30 » arrive en un seul mot : chiffres, un h, chiffres.
            if token.folded.first?.isNumber == true, token.folded.contains("h") { return true }

            guard let hour = Int(token.folded), (0...23).contains(hour), hour > 0 else { continue }
            if index + 1 < tokens.count, tokens[index + 1].folded == "h" { return true }
        }
        return false
    }

    /// « 26 août » : un jour du mois suivi d'un nom de mois.
    static func hasCalendarDate(in tokens: [ChatToken]) -> Bool {
        for (index, token) in tokens.enumerated() {
            guard let day = Int(token.folded), (1...31).contains(day) else { continue }
            guard index + 1 < tokens.count else { continue }
            if Lexicon.months.contains(tokens[index + 1].folded) { return true }
        }
        return false
    }

    // MARK: La question

    static func isQuestion(_ text: String, folded: String) -> Bool {
        if text.hasSuffix("?") { return true }
        return Lexicon.questionOpeners.contains { folded.hasPrefix($0) }
    }

    static func subject(in folded: String) -> ChatSignals.Subject? {
        // L'ordre compte : « corriger mon carnet » parle de correction, pas de
        // carnet. Le sujet le plus spécifique passe donc en premier.
        if Lexicon.correctionWords.contains(where: folded.contains) { return .corrections }
        if Lexicon.subscriptionWords.contains(where: folded.contains) { return .subscription }
        if Lexicon.paceWords.contains(where: folded.contains) { return .pace }
        if Lexicon.photoWords.contains(where: folded.contains) { return .photos }
        if Lexicon.bookWords.contains(where: folded.contains) { return .book }
        return nil
    }

    // MARK: L'humeur

    /// Deux lexiques et un compteur d'intensifieurs. Les intensifieurs comptent
    /// **double** du côté déjà majoritaire : « vraiment épuisé » est plus qu'un
    /// « épuisé », et « c'était vraiment magnifique » plus qu'un « magnifique ».
    static func mood(in folded: String) -> ChatSignals.Mood {
        let positive = Lexicon.positiveWords.filter(folded.contains).count
        let negative = Lexicon.negativeWords.filter(folded.contains).count
        guard positive != negative else { return .neutral }

        let intensity = Lexicon.intensifiers.filter(folded.contains).count
        return positive + (positive > negative ? intensity : 0)
            > negative + (negative > positive ? intensity : 0)
            ? .positive : .negative
    }

    // MARK: Le refus

    /// Un refus franc suffit ; « demain » seul ne compte que dans un message
    /// très court. Sans cette nuance, « demain on part pour Lisbonne, j'ai hâte »
    /// serait lu comme une fin de non-recevoir.
    static func isRefusal(in folded: String, length: ChatSignals.Length) -> Bool {
        if Lexicon.refusals.contains(where: folded.contains) { return true }
        guard length == .tooShort else { return false }
        return Lexicon.softRefusals.contains(where: folded.contains)
    }

    // MARK: Les chiffres

    /// Un nombre collé à son unité (« 12km ») ou séparé d'elle (« 12 km »). Rendu
    /// **normalisé sur une espace** — « 12 km » — parce que c'est ce qui se lit
    /// dans une phrase, mais sans jamais toucher au nombre lui-même.
    static func figures(in tokens: [ChatToken]) -> [String] {
        var found: [String] = []

        for (index, token) in tokens.enumerated() {
            if let split = splitNumberAndUnit(token.folded) {
                append("\(split.number) \(Lexicon.units[split.unit] ?? split.unit)", to: &found)
                continue
            }

            guard Int(token.folded) != nil || Double(token.folded.replacingOccurrences(of: ",", with: ".")) != nil,
                index + 1 < tokens.count,
                let unit = Lexicon.units[tokens[index + 1].folded]
            else { continue }

            append("\(token.text) \(unit)", to: &found)
        }

        return found
    }

    /// « 12km » → (« 12 », « km »). `nil` dès que la coupure n'est pas nette :
    /// on préfère ne rien relever qu'un chiffre mal découpé.
    private static func splitNumberAndUnit(_ folded: String) -> (number: String, unit: String)? {
        let digits = folded.prefix { $0.isNumber || $0 == "," || $0 == "." }
        guard !digits.isEmpty else { return nil }
        let rest = String(folded.dropFirst(digits.count))
        guard Lexicon.units[rest] != nil else { return nil }
        return (String(digits), rest)
    }

    // MARK: -

    /// Ajoute sans doublon, en gardant l'ordre d'apparition — c'est celui du
    /// récit, et il vaut mieux qu'un tri.
    private static func append(_ value: String, to list: inout [String]) {
        guard !list.contains(value) else { return }
        list.append(value)
    }
}

// MARK: - Les listes de mots

/// Tous les mots que l'analyse cherche, au même endroit.
///
/// Ils sont **repliés** : sans accents, en minuscules, apostrophes droites — la
/// forme que rend ``Tokenizer/fold(_:)``. Écrire « épuisé » ici ne matcherait
/// jamais.
enum Lexicon {
    static let timeMarkers: Set<String> = [
        "hier", "avant-hier", "aujourd'hui", "ce matin", "ce midi", "ce soir",
        "cette nuit", "cet apres-midi", "l'apres-midi", "demain", "la veille",
        "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
        "la semaine derniere", "le week-end",
    ]

    static let months: Set<String> = [
        "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout",
        "septembre", "octobre", "novembre", "decembre",
    ]

    static let placePrepositions: Set<String> = [
        "a", "au", "aux", "vers", "depuis", "dans", "jusqu", "sur", "sous",
        "entre", "pres", "cote", "direction",
    ]

    /// Celles qui ne suffisent pas seules : elles ne comptent que derrière un
    /// nom de lieu générique — voir ``Extraction/places(in:excluding:)``.
    static let weakPlacePrepositions: Set<String> = ["de", "du", "des", "d"]

    /// Ce qui, posé devant un nom de lieu générique, en fait un endroit plutôt
    /// qu'un verbe.
    static let determiners: Set<String> = [
        "le", "la", "les", "l", "un", "une", "du", "des", "au", "aux",
        "ce", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes",
        "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
    ]

    static let personPrepositions: Set<String> = [
        "avec", "chez", "mon", "ma", "mes", "notre", "nos", "sans",
    ]

    static let commonPlaces: Set<String> = [
        "restaurant", "marche", "plage", "gare", "hotel", "musee", "col",
        "refuge", "village", "port", "ile", "quartier", "terrasse", "rue",
        "parc", "cafe", "montagne", "lac", "riviere", "sentier", "auberge",
        "aeroport", "cathedrale", "eglise", "chateau", "sommet", "vallee",
    ]

    /// Les mots capitalisés qui ne sont ni un lieu ni quelqu'un : pronoms,
    /// connecteurs, jours, mois, et le nom de l'app elle-même.
    static let stopWords: Set<String> = {
        var words: Set<String> = [
            "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
            "le", "la", "les", "un", "une", "des", "du", "de", "ce", "cet",
            "cette", "ca", "c", "et", "mais", "puis", "alors", "enfin", "bref",
            "donc", "or", "ni", "car", "quand", "comme", "hier", "demain",
            "aujourd", "memobook", "memo", "l", "d", "n", "s", "m", "t", "y",
            "apres", "avant", "aussi", "encore", "tres", "trop", "bien",
        ]
        words.formUnion(months)
        words.formUnion(["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"])
        return words
    }()

    static let questionOpeners: Set<String> = [
        "est-ce que", "est-ce qu", "comment", "pourquoi", "qu'est-ce",
        "combien", "quand est-ce", "c'est quoi", "qui est-ce",
    ]

    static let bookWords: Set<String> = [
        "carnet", "imprim", "livre", "reliure", "pages", "pdf", "apercu",
    ]

    static let subscriptionWords: Set<String> = [
        "abonnement", "prix", "coute", "tarif", "payer", "paiement", "resilier",
        "euros",
    ]

    static let photoWords: Set<String> = ["photo", "pellicule", "image", "cliche"]

    static let correctionWords: Set<String> = [
        "corriger", "corrige", "modifier", "modifie", "changer", "change",
        "retoucher", "retouche", "faute", "reecrire", "supprimer",
    ]

    static let paceWords: Set<String> = [
        "relance", "relancer", "rythme", "notification", "rappel", "souvent",
        "frequence",
    ]

    static let positiveWords: Set<String> = [
        "magnifique", "sublime", "incroyable", "genial", "adore", "coup de coeur",
        "dingue", "ravi", "heureux", "emu", "inoubliable", "parfait",
        "le meilleur", "fou rire", "superbe", "splendide", "hate", "j'ai aime",
        "on a aime", "content",
    ]

    static let negativeWords: Set<String> = [
        "epuise", "creve", "decu", "galere", "rate", "penible", "perdu",
        "malade", "annule", "en retard", "nul", "difficile", "dur", "peur",
        "complique", "fatigue", "triste", "stresse", "cauchemar",
    ]

    static let intensifiers: Set<String> = [
        "vraiment", "tellement", "trop", "hyper", "jamais vu", "le plus",
        "carrement", "franchement",
    ]

    static let refusals: Set<String> = [
        "pas envie", "laisse tomber", "j'arrete", "pas maintenant",
        "non merci", "plus tard", "pas ce soir", "une autre fois",
        "je suis fatigue de", "arrete de",
    ]

    /// Ceux qui ne comptent que dans un message très court : ils sont trop
    /// courants pour peser à eux seuls.
    static let softRefusals: Set<String> = ["demain", "stop", "plus tard", "non"]

    /// Unité repliée → unité telle qu'on la réécrit. Le nombre, lui, n'est
    /// jamais retouché.
    static let units: [String: String] = [
        "e": "€", "euro": "€", "euros": "€",
        "km": "km", "kilometre": "km", "kilometres": "km",
        "m": "m", "metre": "m", "metres": "m",
        "h": "h", "heure": "heures", "heures": "heures",
        "min": "min", "minute": "minutes", "minutes": "minutes",
        "jour": "jour", "jours": "jours",
        "pas": "pas",
    ]
}
