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

    /// `needle` apparaît **au début d'un mot** de `folded` — le jumeau exact de
    /// `startsAWord` du serveur (`conversationHeuristics.ts`) : « coute » est
    /// dans « tu m’écoutes ? », et ce n'est pas une question de prix.
    /// `wholeWord` exige aussi qu'il le finisse : « euro » est dans « Europe ».
    static func startsAWord(_ needle: String, in folded: String, wholeWord: Bool = false) -> Bool {
        var searchRange = folded.startIndex..<folded.endIndex
        while let found = folded.range(of: needle, range: searchRange) {
            let startsHere =
                found.lowerBound == folded.startIndex
                || !folded[folded.index(before: found.lowerBound)].isLetter
            let endsHere = found.upperBound == folded.endIndex || !folded[found.upperBound].isLetter
            if startsHere && (!wholeWord || endsHere) { return true }
            searchRange = folded.index(after: found.lowerBound)..<folded.endIndex
        }
        return false
    }

    static func isAWord(_ needle: String, in folded: String) -> Bool {
        startsAWord(needle, in: folded, wholeWord: true)
    }

    /// Où finit chaque occurrence de `needle` en mot entier dans `folded` —
    /// l'endroit d'où lire la suite. Le jumeau de `wholeWordEnds` du serveur.
    static func wholeWordEnds(_ needle: String, in folded: String) -> [String.Index] {
        var ends: [String.Index] = []
        var searchRange = folded.startIndex..<folded.endIndex
        while let found = folded.range(of: needle, range: searchRange) {
            let startsHere =
                found.lowerBound == folded.startIndex
                || !folded[folded.index(before: found.lowerBound)].isLetter
            let endsHere = found.upperBound == folded.endIndex || !folded[found.upperBound].isLetter
            if startsHere && endsHere { ends.append(found.upperBound) }
            searchRange = folded.index(after: found.lowerBound)..<folded.endIndex
        }
        return ends
    }

    /// Une question sans sa ponctuation finale ni son interpellation : « Ça
    /// coûte combien, MEMO ? » rend « ca coute combien ». Le nom seul ne laisse
    /// rien.
    static func questionCore(_ folded: String) -> String {
        var rest = Substring(folded.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = rest.last, last.isWhitespace || "?!.…".contains(last) { rest = rest.dropLast() }
        for name in ["memobook", "memo"] {
            if rest == name { return "" }
            guard rest.hasSuffix(" \(name)") || rest.hasSuffix(",\(name)") else { continue }
            rest = rest.dropLast(name.count)
            while let last = rest.last, last.isWhitespace || last == "," { rest = rest.dropLast() }
            break
        }
        return String(rest)
    }

    /// Le texte parle du récit, de l'app ou de la journée de crédit
    /// (``Lexicon/creditAnchors``).
    static func isAnchoredToTheStory(_ folded: String) -> Bool {
        Lexicon.creditAnchors.contains(where: { startsAWord($0, in: folded) })
            || Lexicon.appReferences.contains(where: { isAWord($0, in: folded) })
    }

    static func mentionsATrip(_ folded: String) -> Bool {
        Lexicon.travelMarkers.contains(where: { isAWord($0, in: folded) })
    }

    /// Le crédit du téléphone, de la carte, de la banque — pas celui du récit.
    static func talksAboutAnotherCredit(_ folded: String) -> Bool {
        if Lexicon.otherCreditWords.contains(where: { isAWord($0, in: folded) }) { return true }
        return Lexicon.rechargeWords.contains(where: { isAWord($0, in: folded) })
            && !folded.contains("se recharg")
    }

    /// « Il me reste combien ? » vise le crédit si ce qui suit n'est rien, un
    /// objet de crédit (« de temps », « de crédit ») suivi de rien, ou d'une fin
    /// admise (« aujourd’hui », « pour raconter »), ou d'une suite qui parle du
    /// récit sans trajet. « de jours de voyage », « avant l’embarquement » : non.
    static func asksWhatRemains(_ folded: String) -> Bool {
        for question in Lexicon.remainingQuestions {
            for end in wholeWordEnds(question, in: folded) {
                var after = folded[end...]
                while let first = after.first, first.isWhitespace || first == "," { after = after.dropFirst() }
                var tail = questionCore(String(after))
                for object in Lexicon.remainingObjects where tail == object || tail.hasPrefix("\(object) ") {
                    tail = String(tail.dropFirst(object.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
                if Lexicon.remainingTails.contains(tail) { return true }
                if isAnchoredToTheStory(tail) && !mentionsATrip(tail) { return true }
            }
        }
        return false
    }

    /// Le message parle-t-il de l'abonnement, du crédit du jour, de la limite
    /// du récit ou du temps qui reste pour raconter ? Le même jugement que
    /// `talksAboutSubscription` du serveur, mot pour mot (03/10/2026) : le prix
    /// d'un billet, un musée gratuit, la limite de vitesse, le temps d'un
    /// trajet, le crédit du téléphone ou le wifi illimité parlent du voyage, et
    /// MEMO n'y pose pas l'offre — jamais spontanément.
    static func talksAboutSubscription(_ folded: String) -> Bool {
        let otherOffer = Lexicon.otherOffers.contains(where: { isAWord($0, in: folded) })
        // 1. L'offre nommée — pas le wifi illimité ni l'abonnement de métro.
        if !otherOffer, Lexicon.subscriptionWords.contains(where: { startsAWord($0, in: folded) }) {
            return true
        }
        // 2. Le crédit du jour, la limite du récit, le temps qui reste — pas le
        //    crédit du téléphone ni le temps de trajet.
        if !talksAboutAnotherCredit(folded) {
            if Lexicon.creditPhrases.contains(where: { isAWord($0, in: folded) }) { return true }
            if Lexicon.anchoredCreditPhrases.contains(where: { isAWord($0, in: folded) }),
                isAnchoredToTheStory(folded),
                !mentionsATrip(folded)
            {
                return true
            }
            if asksWhatRemains(folded) { return true }
        }
        // 3. Une question de prix ou de limite qui est tout le message.
        if isBarePriceQuestion(folded) { return true }
        // 4. Un prix qui nomme l'app — mais « le carnet MemoBook » coûte le prix
        //    du carnet, et « une app gratuite pour le métro » en est une autre.
        return !otherOffer
            && Lexicon.priceWords.contains(where: { isAWord($0, in: folded) })
            && Lexicon.appReferences.contains(where: { isAWord($0, in: folded) })
            && !Lexicon.bookWords.contains(where: folded.contains)
    }

    /// Le message entier, sans ses ouvertures (« et », « est-ce que »…) ni sa
    /// ponctuation finale, est une question de prix ou de limite sans objet.
    static func isBarePriceQuestion(_ folded: String) -> Bool {
        var rest = Substring(questionCore(folded))
        var opened = true
        while opened {
            opened = false
            for opener in Lexicon.bareQuestionOpeners where rest.hasPrefix("\(opener) ") {
                rest = rest.dropFirst(opener.count + 1)
                while let first = rest.first, first.isWhitespace { rest = rest.dropFirst() }
                opened = true
            }
        }
        return Lexicon.barePriceQuestions.contains(String(rest))
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
        if talksAboutSubscription(folded) { return .subscription }
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

    // L'abonnement, le crédit du jour, la limite du récit et le temps qui reste
    // pour raconter — et rien d'autre : pas le prix d'un billet ni la limite de
    // vitesse (03/10/2026). Les mêmes listes que le serveur
    // (`conversationHeuristics.ts`), lues par
    // ``Extraction/talksAboutSubscription(_:)``.

    /// Les mots qui nomment l'offre à eux seuls, cherchés **en début de mot** :
    /// « abonnement », « s’abonner », « résilier », « illimité ».
    static let subscriptionWords: Set<String> = ["abonn", "resili", "illimit"]

    /// Ce qui fait d'« illimité », d'« abonnement » ou d'un prix d'app une
    /// autre offre que la nôtre, en mots entiers : le wifi illimité, le
    /// kilométrage illimité, l'abonnement de métro, le forfait qu'on résilie.
    static let otherOffers: Set<String> = [
        "wifi", "wi-fi", "internet", "data", "forfait", "forfaits", "telephone", "telephonique",
        "mobile", "kilometrage", "location", "metro", "transport", "transports", "navigo",
        "bus", "tram", "train", "trains", "pass", "parking", "velo", "velos", "ski", "musee",
        "musees", "buffet", "boisson", "boissons", "salle de sport", "piscine",
    ]

    /// Le crédit qui n'est pas le nôtre, en mots entiers : celui du téléphone,
    /// de la carte, de la banque.
    static let otherCreditWords: Set<String> = [
        "telephone", "telephones", "telephonique", "portable", "mobile", "sim", "forfait",
        "forfaits", "carte", "cartes", "bancaire", "banque", "operateur", "distributeur",
        "retrait", "data", "internet",
    ]

    /// Recharger un téléphone, en mots entiers — sauf le crédit qui « se
    /// recharge » à minuit, qui est le nôtre.
    static let rechargeWords: Set<String> = ["recharger", "recharge", "recharges", "rechargement"]

    /// Le crédit du jour et la limite du récit, en locutions et en mots
    /// entiers, qui n'ont pas d'autre sens en voyage. « crédit » ou « limite »
    /// seuls n'y sont pas : « carte de crédit » et « limite de vitesse »
    /// parlent du voyage.
    static let creditPhrases: Set<String> = [
        "credit du jour", "credit restant", "credit quotidien", "credit de temps",
        "credit de recit", "mon credit", "ton credit", "notre credit", "votre credit",
        "combien de credit", "de credit il reste", "de credit il me reste",
        "limite du jour", "limite de recit", "limite du recit", "limite de minutes",
        "limite quotidienne", "limite par jour", "limite du credit",
        "raconter sans limite", "parler sans limite", "minutes de recit", "temps de recit",
        "raconter combien de temps", "parler combien de temps",
    ]

    /// Les locutions du temps et du crédit qui disent aussi le voyage :
    /// « combien de minutes » est « à combien de minutes à pied », « limite de
    /// temps » celle du Louvre. Elles ne visent l'offre que **rattachées au
    /// récit** (``creditAnchors``, ``appReferences``) et loin d'un trajet
    /// (``travelMarkers``).
    static let anchoredCreditPhrases: Set<String> = [
        "le credit", "du credit", "plus de credit", "de credit",
        "limite de temps", "sans limite de temps", "est limite", "c'est limite a",
        "suis limite", "suis limitee", "suis bloque", "suis bloquee",
        "combien de minutes", "combien de temps", "minutes par jour", "minutes aujourd",
        "minutes du jour", "minutes restantes", "temps restant",
    ]

    /// Ce qui rattache une locution au récit, cherché **en début de mot**.
    static let creditAnchors: Set<String> = [
        "racont", "recit", "enregistr", "vocal", "vocaux", "abonn", "illimit", "aujourd",
        "par jour", "du jour", "minuit", "se recharg", "5 minutes", "cinq minutes",
    ]

    /// Un trajet, une visite, un départ — en mots entiers : le temps qu'il
    /// faut, pas celui qui reste pour raconter.
    static let travelMarkers: Set<String> = [
        "a pied", "de marche", "marche", "marcher", "pour aller", "pour rejoindre", "pour arriver",
        "en voiture", "en taxi", "en bus", "en train", "en metro", "en avion", "en bateau",
        "embarquement", "depart", "vol", "vols", "train", "bus", "metro", "avion", "bateau",
        "ferry", "trajet", "visite", "visiter", "attente", "escale", "correspondance", "check-in",
    ]

    /// « Il me reste combien ? » — la question d'exemple du prompt. Elle ne
    /// vise le crédit que si rien ne la suit, hors ``remainingObjects`` puis
    /// ``remainingTails`` (ou un mot du récit) — voir
    /// ``Extraction/asksWhatRemains(_:)``.
    static let remainingQuestions: [String] = [
        "il me reste combien", "il nous reste combien", "il reste combien",
        "combien il me reste", "combien il nous reste", "combien il reste",
        "combien me reste-t-il", "combien nous reste-t-il", "combien reste-t-il",
        "combien de temps il me reste", "combien de temps il nous reste", "combien de temps il reste",
        "combien de minutes il me reste", "combien de minutes il nous reste",
        "combien de minutes il reste", "temps qu'il me reste", "temps qu'il nous reste",
    ]

    static let remainingObjects: [String] = ["de temps", "de minutes", "de credit", "en credit"]

    static let remainingTails: Set<String> = [
        "", "aujourd'hui", "pour aujourd'hui", "ce soir", "pour ce soir", "pour raconter",
        "a raconter", "pour parler", "pour enregistrer", "a enregistrer",
    ]

    /// Le prix, en mots entiers. Seul, il parle d'un billet, d'un musée ou du
    /// carnet : il ne vise l'offre que s'il nomme l'app (``appReferences``), ou
    /// dans une question nue (``barePriceQuestions``).
    static let priceWords: Set<String> = [
        "prix", "cout", "couts", "coute", "coutent", "couter", "coutera", "tarif", "tarifs",
        "payer", "payant", "payante", "paiement", "gratuit", "gratuite", "euro", "euros",
    ]

    /// L'app elle-même, en mots entiers : « l’app », « ton appli »,
    /// « MemoBook ». « une app gratuite pour le métro » en est une autre.
    static let appReferences: Set<String> = [
        "memobook", "memo", "l'app", "l'appli", "l'application", "ton app", "ton appli",
        "ton application", "votre app", "votre appli", "votre application", "cette app",
        "cette appli", "cette application",
    ]

    /// Une question de prix ou de limite **qui est tout le message** : sans
    /// objet, elle ne peut viser que l'app. « Le musée, c'est payant ? » a un
    /// objet, et n'y est pas.
    static let barePriceQuestions: Set<String> = [
        "combien ca coute", "ca coute combien", "combien ca coute par mois",
        "ca coute combien par mois", "c'est combien", "c'est combien par mois", "combien c'est",
        "combien ca fait", "c'est payant", "c'est gratuit", "payant", "gratuit",
        "c'est quoi le prix", "quel est le prix", "quel prix", "il faut payer", "faut payer",
        "c'est quoi la limite", "quelle est la limite", "il y a une limite", "y a une limite",
        "c'est quoi la limite de temps", "quelle est la limite de temps",
        "il y a une limite de temps", "y a une limite de temps", "c'est limite",
        "c'est limite a combien", "pourquoi c'est limite", "je suis limite", "je suis limitee",
        "pourquoi je suis limite", "pourquoi je suis limitee", "je suis bloque", "je suis bloquee",
        "pourquoi je suis bloque", "pourquoi je suis bloquee",
    ]

    /// Ce qui peut précéder une question nue sans lui donner d'objet.
    static let bareQuestionOpeners: [String] = [
        "memo,", "et", "mais", "alors", "du coup", "sinon", "est-ce que",
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
