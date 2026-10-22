package com.memobook.core

import java.text.BreakIterator
import java.text.Normalizer
import java.util.Locale

// Ce que MEMO lit dans un message avant de répondre. Le jumeau de
// `MemoBookCore/ChatAnalysis.swift`.
//
// **Des fonctions pures, et rien d'autre.** Aucun réseau, aucune horloge, aucun
// aléatoire : le même message rend toujours les mêmes signaux. C'est ce qui
// permet de tester le moteur de réponse phrase par phrase sur la JVM, sans
// émulateur — et c'est la raison pour laquelle tout ça vit dans `:core`, qui
// n'a aucune dépendance.
//
// **Le principe : des marqueurs, pas un dictionnaire.** On ne cherche pas à
// comprendre le français, on cherche des indices sûrs — une préposition devant
// un mot capitalisé, une unité derrière un nombre, un point d'interrogation
// final. Un indice manquant ne coûte qu'une relance moins précise ; un indice
// faux fait dire une bêtise, et c'est ça qu'on évite.
//
// **Les longueurs se comptent comme sur iOS** : en graphèmes (`String.count`
// de Swift), pas en unités UTF-16 — voir [ChatGraphemes]. Un emoji vaut un
// signe des deux côtés, et les seuils (25, 140, 400) tombent au même endroit.

/** Les indices relevés dans un message du voyageur. */
data class ChatSignals(
    val length: Length,
    val sentenceCount: Int,
    /** Le message situe le souvenir dans le temps. */
    val hasWhen: Boolean,
    /**
     * Les lieux, **verbatim** et dans l'ordre d'apparition. MEMO les répète, il
     * ne les complète pas.
     */
    val places: List<String>,
    /**
     * Les prénoms, verbatim. Un même mot ne peut pas être à la fois lieu et
     * personne : c'est la préposition qui tranche.
     */
    val people: List<String>,
    val isQuestion: Boolean,
    val subject: Subject?,
    val mood: Mood,
    /**
     * Le voyageur ne veut plus répondre. **Ce signal gagne sur tous les
     * autres** : `agents/agent-conversation.md` dit « ne jamais insister ».
     */
    val isRefusal: Boolean,
    /**
     * Les chiffres avec leur unité, recopiés tels quels — « 12 km », « 35 € ».
     * Le moteur ne convertit ni n'additionne : une métadonnée fausse est pire
     * qu'absente.
     */
    val figures: List<String>,
) {
    /**
     * Combien il y a de matière. C'est le premier signal, et souvent le seul
     * qui compte : deux mots ne font pas une page.
     */
    enum class Length {
        /** Moins de 25 caractères. On demande **un** détail précis. */
        TooShort,

        /** Jusqu'à 140 caractères. */
        Brief,

        /** Jusqu'à 400 caractères. */
        Substantial,

        /** Au-delà. On propose un découpage, on ne demande **pas** plus. */
        Long,
    }

    enum class Mood { Positive, Negative, Neutral }

    /**
     * Les six sujets sur lesquels MEMO sait légitimement répondre. Tout le
     * reste passe par le repli honnête — voir [ChatCopy.Answer.unknown].
     */
    enum class Subject { Book, Subscription, Photos, Corrections, Pace }

    /**
     * Le message ne porte aucun indice fort. La relance passe alors par la
     * rotation neutre.
     */
    val isBare: Boolean
        get() = !isQuestion && !isRefusal && places.isEmpty() && people.isEmpty() && figures.isEmpty() &&
            mood == Mood.Neutral

    companion object {
        /** Lit un message. C'est **le** point d'entrée de l'analyse. */
        fun read(text: String): ChatSignals {
            val trimmed = text.trim()
            val tokens = Tokenizer.tokens(trimmed)
            val folded = Tokenizer.fold(trimmed)

            // Les personnes d'abord : « avec Mila » est un signal bien plus sûr que
            // « de Testaccio ». Un mot déjà retenu comme quelqu'un ne peut plus être
            // un lieu, ce qui évite à MEMO de demander ce qui l'a marqué « là-bas »
            // à propos d'une personne.
            val people = Extraction.people(tokens, excluding = emptySet())
            val places = Extraction.places(tokens, excluding = people.toSet())
            val length = length(trimmed)

            return ChatSignals(
                length = length,
                sentenceCount = Extraction.sentenceCount(trimmed),
                hasWhen = Lexicon.timeMarkers.any { folded.contains(it) } ||
                    Extraction.hasClockTime(tokens) ||
                    Extraction.hasCalendarDate(tokens),
                places = places,
                people = people,
                isQuestion = Extraction.isQuestion(trimmed, folded),
                subject = Extraction.subject(folded),
                mood = Extraction.mood(folded),
                isRefusal = Extraction.isRefusal(folded, length),
                figures = Extraction.figures(tokens),
            )
        }

        private fun length(text: String): Length {
            val count = ChatGraphemes.count(text)
            return when {
                count < 25 -> Length.TooShort
                count < 141 -> Length.Brief
                count < 401 -> Length.Substantial
                else -> Length.Long
            }
        }
    }
}

// MARK: - Les caractères comme Swift les compte

/**
 * Ce que le `Character` de Swift donne et que la `Char` de Kotlin n'a pas : le
 * graphème. Une lettre accentuée décomposée, un drapeau, un emoji à
 * modificateur valent un seul signe, et se jugent à leur premier scalaire —
 * comme `Character.isLetter` ou `isNumber`.
 */
internal object ChatGraphemes {
    /** Les graphèmes de [text], dans l'ordre. */
    fun split(text: String): List<String> {
        if (text.isEmpty()) return emptyList()
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(text)
        val result = mutableListOf<String>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            result.add(text.substring(start, end))
            start = end
            end = iterator.next()
        }
        return result
    }

    /** `String.count` de Swift. */
    fun count(text: String): Int = split(text).size

    /** `String.prefix(_:)` de Swift : les [count] premiers graphèmes. */
    fun prefix(text: String, count: Int): String = split(text).take(count).joinToString("")

    /** `Character.isLetter` : le premier scalaire est alphabétique. */
    fun isLetter(grapheme: String): Boolean =
        grapheme.isNotEmpty() && Character.isAlphabetic(grapheme.codePointAt(0))

    /** `Character.isNumber` : le premier scalaire a une valeur numérique. */
    fun isNumber(grapheme: String): Boolean = grapheme.isNotEmpty() && isNumberScalar(grapheme.codePointAt(0))

    fun isNumberScalar(scalar: Int): Boolean = when (Character.getType(scalar).toByte()) {
        Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
        else -> false
    }

    /** `Character.isUppercase`. */
    fun isUppercase(grapheme: String): Boolean =
        grapheme.isNotEmpty() && Character.isUpperCase(grapheme.codePointAt(0))

    /** `Int(_:)` de Swift : des chiffres ASCII seulement, sans débordement. */
    fun swiftInt(text: String): Int? {
        val digits = if (text.startsWith("+") || text.startsWith("-")) text.substring(1) else text
        if (digits.isEmpty() || digits.any { it !in '0'..'9' }) return null
        return if (text.startsWith("-")) "-$digits".toIntOrNull() else digits.toIntOrNull()
    }

    /**
     * `Double(_:)` de Swift (`strtod`) : décimal, exposant, hexadécimal, et
     * `nan`, `inf`, `infinity`, sans tenir compte de la casse.
     */
    fun isSwiftDouble(text: String): Boolean {
        val body = text.removePrefix("+").removePrefix("-").lowercase(Locale.ROOT)
        if (body == "nan" || body == "inf" || body == "infinity") return true
        if (DECIMAL.matches(text) || HEXADECIMAL.matches(text)) return true
        return false
    }

    private val DECIMAL = Regex("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")
    private val HEXADECIMAL = Regex("^[+-]?0[xX]([0-9a-fA-F]+\\.?[0-9a-fA-F]*|\\.[0-9a-fA-F]+)([pP][+-]?\\d+)?$")
}

// MARK: - Découpage du message

/**
 * Un mot du message, sous ses deux formes : celle qu'on réaffiche et celle sur
 * laquelle on compare.
 */
internal data class ChatToken(
    /** Le mot tel qu'il a été écrit. C'est **lui** qui repart dans une réponse. */
    val text: String,
    /**
     * Le même, sans accents ni majuscules, apostrophe normalisée. Uniquement
     * pour comparer.
     */
    val folded: String,
    /**
     * Le mot ouvre une phrase. Une majuscule y est grammaticale et ne dit donc
     * rien : c'est ce qui évite de prendre « Hier » pour un prénom.
     */
    val opensSentence: Boolean,
) {
    val isCapitalized: Boolean
        get() = ChatGraphemes.split(text).firstOrNull()?.let(ChatGraphemes::isUppercase) == true
}

internal object Tokenizer {
    /**
     * Sans accents, en minuscules, apostrophes droites. Le repli suit le
     * `folding(options: [.diacriticInsensitive, .caseInsensitive,
     * .widthInsensitive], locale: fr_FR)` d'iOS : minuscules, formes pleine
     * chasse ramenées à l'ASCII, signes diacritiques retirés, et « œ » qui vaut
     * « oe ».
     */
    fun fold(text: String): String {
        val replaced = text.replace('’', '\'')
        val narrow = StringBuilder(replaced.length)
        for (character in replaced) {
            narrow.append(
                when (character) {
                    in '！'..'～' -> character - 0xFEE0
                    '　' -> ' '
                    else -> character
                },
            )
        }
        val lowered = narrow.toString().lowercase(Locale.FRENCH)
        val decomposed = Normalizer.normalize(lowered, Normalizer.Form.NFD)
        val stripped = StringBuilder(decomposed.length)
        var index = 0
        while (index < decomposed.length) {
            val scalar = decomposed.codePointAt(index)
            if (Character.getType(scalar) != Character.NON_SPACING_MARK.toInt()) stripped.appendCodePoint(scalar)
            index += Character.charCount(scalar)
        }
        return Normalizer.normalize(stripped.toString(), Normalizer.Form.NFC)
            .replace("œ", "oe")
            .replace("æ", "ae")
    }

    /** Les terminaisons de phrase. Une majuscule qui les suit est grammaticale. */
    private val terminators: Set<String> = setOf(".", "!", "?", "…", "\n")

    fun tokens(text: String): List<ChatToken> {
        val tokens = mutableListOf<ChatToken>()
        val current = StringBuilder()
        var opensSentence = true

        fun flush() {
            if (current.isEmpty()) return
            val word = current.toString()
            tokens.add(ChatToken(text = word, folded = fold(word), opensSentence = opensSentence))
            current.clear()
            opensSentence = false
        }

        for (character in ChatGraphemes.split(text)) {
            if (ChatGraphemes.isLetter(character) || ChatGraphemes.isNumber(character)) {
                current.append(character)
            } else {
                flush()
                if (character in terminators) opensSentence = true
            }
        }
        flush()

        return tokens
    }
}

// MARK: - Les relevés

internal object Extraction {
    fun sentenceCount(text: String): Int {
        val sentences = mutableListOf<String>()
        val current = StringBuilder()
        for (character in ChatGraphemes.split(text)) {
            if (character == "." || character == "!" || character == "?" || character == "…") {
                if (current.isNotEmpty()) sentences.add(current.toString())
                current.clear()
            } else {
                current.append(character)
            }
        }
        if (current.isNotEmpty()) sentences.add(current.toString())
        return maxOf(1, sentences.count { it.trim(::isHorizontalWhitespace).isNotEmpty() })
    }

    /** `CharacterSet.whitespaces` d'iOS : la tabulation et les espaces (Zs), sans les retours à la ligne. */
    private fun isHorizontalWhitespace(character: Char): Boolean =
        character == '\t' || Character.getType(character) == Character.SPACE_SEPARATOR.toInt()

    // MARK: Les lieux

    /**
     * Un mot capitalisé précédé d'une préposition de lieu, ou un nom de lieu
     * générique. Pas de gazetteer : « Trastevere » ne figure dans aucune liste,
     * et c'est bien le but.
     *
     * Les prépositions se lisent en deux temps. « à », « vers », « depuis »
     * désignent un lieu à elles seules. « de » ne dit rien — « le marché de
     * Testaccio » est un lieu, « l'appartement de Camille » est quelqu'un —, et
     * n'est donc retenu que s'il **suit un nom de lieu générique** de quelques
     * mots. C'est cette condition-là qui évite à MEMO de demander ce qui l'a
     * marqué « là-bas » à propos d'une personne.
     */
    fun places(tokens: List<ChatToken>, excluding: Set<String> = emptySet()): List<String> {
        val found = mutableListOf<String>()

        for ((index, token) in tokens.withIndex()) {
            if (token.folded in Lexicon.commonPlaces) {
                // Un nom de lieu générique ne compte que derrière un
                // **déterminant** : « le marché » est un endroit, « on a
                // marché » est un verbe. Sans cette condition, MEMO répondait
                // « marché, je note. Qu'est-ce qui t'a marqué là-bas ? » à
                // quelqu'un qui disait simplement avoir marché.
                if (index <= 0 || tokens[index - 1].folded !in Lexicon.determiners) continue
                append(token.text.lowercase(), found)
                continue
            }

            if (!token.isCapitalized ||
                token.folded in Lexicon.stopWords ||
                token.text in excluding ||
                index <= 0
            ) {
                continue
            }

            val previous = tokens[index - 1].folded
            if (previous in Lexicon.placePrepositions) {
                append(token.text, found)
            } else if (previous in Lexicon.weakPlacePrepositions && followsAGenericPlace(index, tokens)) {
                append(token.text, found)
            }
        }

        return found
    }

    /**
     * Un nom de lieu générique dans les trois mots qui précèdent. Trois, parce
     * que « le marché couvert de Testaccio » en compte deux entre les deux.
     */
    private fun followsAGenericPlace(before: Int, tokens: List<ChatToken>): Boolean {
        val start = maxOf(0, before - 4)
        return tokens.subList(start, before).any { it.folded in Lexicon.commonPlaces }
    }

    // MARK: Les personnes

    /**
     * Un mot capitalisé qui **n'ouvre pas** la phrase, précédé d'un possessif ou
     * d'un « avec ».
     *
     * « et » ne compte qu'après une première personne déjà trouvée : sans cette
     * condition, « et Rome était belle » ferait de Rome quelqu'un. C'est le
     * motif « avec Léa et Tom » qu'on veut attraper, et lui seul.
     */
    fun people(tokens: List<ChatToken>, excluding: Set<String>): List<String> {
        val found = mutableListOf<String>()

        for ((index, token) in tokens.withIndex()) {
            if (!token.isCapitalized ||
                token.opensSentence ||
                token.folded in Lexicon.stopWords ||
                token.text in excluding
            ) {
                continue
            }

            if (index <= 0) continue
            val previous = tokens[index - 1].folded

            val isIntroduced = previous in Lexicon.personPrepositions || (previous == "et" && found.isNotEmpty())
            if (!isIntroduced) continue

            append(token.text, found)
        }

        return found
    }

    // MARK: Le temps

    /** « 18h », « 18 h 30 ». Un nombre plausible comme heure suivi d'un « h ». */
    fun hasClockTime(tokens: List<ChatToken>): Boolean {
        for ((index, token) in tokens.withIndex()) {
            // « 18h30 » arrive en un seul mot : chiffres, un h, chiffres.
            val first = ChatGraphemes.split(token.folded).firstOrNull()
            if (first != null && ChatGraphemes.isNumber(first) && token.folded.contains("h")) return true

            val hour = ChatGraphemes.swiftInt(token.folded) ?: continue
            if (hour !in 0..23 || hour <= 0) continue
            if (index + 1 < tokens.size && tokens[index + 1].folded == "h") return true
        }
        return false
    }

    /** « 26 août » : un jour du mois suivi d'un nom de mois. */
    fun hasCalendarDate(tokens: List<ChatToken>): Boolean {
        for ((index, token) in tokens.withIndex()) {
            val day = ChatGraphemes.swiftInt(token.folded) ?: continue
            if (day !in 1..31) continue
            if (index + 1 >= tokens.size) continue
            if (tokens[index + 1].folded in Lexicon.months) return true
        }
        return false
    }

    private fun isLetterBefore(folded: String, index: Int): Boolean =
        index > 0 && Character.isAlphabetic(folded.codePointBefore(index))

    private fun isLetterAt(folded: String, index: Int): Boolean =
        index < folded.length && Character.isAlphabetic(folded.codePointAt(index))

    /**
     * [needle] apparaît **au début d'un mot** de [folded] — le jumeau exact de
     * `startsAWord` du serveur (`conversationHeuristics.ts`) : « coute » est
     * dans « tu m’écoutes ? », et ce n'est pas une question de prix.
     * [wholeWord] exige aussi qu'il le finisse : « euro » est dans « Europe ».
     */
    fun startsAWord(needle: String, folded: String, wholeWord: Boolean = false): Boolean {
        var from = 0
        while (true) {
            val found = folded.indexOf(needle, from)
            if (found < 0) return false
            val end = found + needle.length
            val startsHere = !isLetterBefore(folded, found)
            val endsHere = !isLetterAt(folded, end)
            if (startsHere && (!wholeWord || endsHere)) return true
            from = found + 1
        }
    }

    fun isAWord(needle: String, folded: String): Boolean = startsAWord(needle, folded, wholeWord = true)

    /**
     * Où finit chaque occurrence de [needle] en mot entier dans [folded] —
     * l'endroit d'où lire la suite. Le jumeau de `wholeWordEnds` du serveur.
     */
    fun wholeWordEnds(needle: String, folded: String): List<Int> {
        val ends = mutableListOf<Int>()
        var from = 0
        while (true) {
            val found = folded.indexOf(needle, from)
            if (found < 0) return ends
            val end = found + needle.length
            if (!isLetterBefore(folded, found) && !isLetterAt(folded, end)) ends.add(end)
            from = found + 1
        }
    }

    /**
     * Une question sans sa ponctuation finale ni son interpellation : « Ça
     * coûte combien, MEMO ? » rend « ca coute combien ». Le nom seul ne laisse
     * rien.
     */
    fun questionCore(folded: String): String {
        var rest = folded.trim()
        while (rest.isNotEmpty() && (rest.last().isWhitespace() || rest.last() in "?!.…")) rest = rest.dropLast(1)
        for (name in listOf("memobook", "memo")) {
            if (rest == name) return ""
            if (!(rest.endsWith(" $name") || rest.endsWith(",$name"))) continue
            rest = rest.dropLast(name.length)
            while (rest.isNotEmpty() && (rest.last().isWhitespace() || rest.last() == ',')) rest = rest.dropLast(1)
            break
        }
        return rest
    }

    /** Le texte parle du récit, de l'app ou de la journée de crédit ([Lexicon.creditAnchors]). */
    fun isAnchoredToTheStory(folded: String): Boolean =
        Lexicon.creditAnchors.any { startsAWord(it, folded) } ||
            Lexicon.appReferences.any { isAWord(it, folded) }

    fun mentionsATrip(folded: String): Boolean = Lexicon.travelMarkers.any { isAWord(it, folded) }

    /** Le crédit du téléphone, de la carte, de la banque — pas celui du récit. */
    fun talksAboutAnotherCredit(folded: String): Boolean {
        if (Lexicon.otherCreditWords.any { isAWord(it, folded) }) return true
        return Lexicon.rechargeWords.any { isAWord(it, folded) } && !folded.contains("se recharg")
    }

    /**
     * « Il me reste combien ? » vise le crédit si ce qui suit n'est rien, un
     * objet de crédit (« de temps », « de crédit ») suivi de rien, ou d'une fin
     * admise (« aujourd’hui », « pour raconter »), ou d'une suite qui parle du
     * récit sans trajet. « de jours de voyage », « avant l’embarquement » : non.
     */
    fun asksWhatRemains(folded: String): Boolean {
        for (question in Lexicon.remainingQuestions) {
            for (end in wholeWordEnds(question, folded)) {
                var after = folded.substring(end)
                while (after.isNotEmpty() && (after.first().isWhitespace() || after.first() == ',')) {
                    after = after.drop(1)
                }
                var tail = questionCore(after)
                for (objectWords in Lexicon.remainingObjects) {
                    if (tail == objectWords || tail.startsWith("$objectWords ")) {
                        tail = tail.drop(objectWords.length).trim()
                        break
                    }
                }
                if (tail in Lexicon.remainingTails) return true
                if (isAnchoredToTheStory(tail) && !mentionsATrip(tail)) return true
            }
        }
        return false
    }

    /**
     * Le message parle-t-il de l'abonnement, du crédit du jour, de la limite
     * du récit ou du temps qui reste pour raconter ? Le même jugement que
     * `talksAboutSubscription` du serveur, mot pour mot (03/10/2026) : le prix
     * d'un billet, un musée gratuit, la limite de vitesse, le temps d'un
     * trajet, le crédit du téléphone ou le wifi illimité parlent du voyage, et
     * MEMO n'y pose pas l'offre — jamais spontanément.
     */
    fun talksAboutSubscription(folded: String): Boolean {
        val otherOffer = Lexicon.otherOffers.any { isAWord(it, folded) }
        // 1. L'offre nommée — pas le wifi illimité ni l'abonnement de métro.
        if (!otherOffer && Lexicon.subscriptionWords.any { startsAWord(it, folded) }) return true
        // 2. Le crédit du jour, la limite du récit, le temps qui reste — pas le
        //    crédit du téléphone ni le temps de trajet.
        if (!talksAboutAnotherCredit(folded)) {
            if (Lexicon.creditPhrases.any { isAWord(it, folded) }) return true
            if (Lexicon.anchoredCreditPhrases.any { isAWord(it, folded) } &&
                isAnchoredToTheStory(folded) &&
                !mentionsATrip(folded)
            ) {
                return true
            }
            if (asksWhatRemains(folded)) return true
        }
        // 3. Une question de prix ou de limite qui est tout le message.
        if (isBarePriceQuestion(folded)) return true
        // 4. Un prix qui nomme l'app — mais « le carnet MemoBook » coûte le prix
        //    du carnet, et « une app gratuite pour le métro » en est une autre.
        return !otherOffer &&
            Lexicon.priceWords.any { isAWord(it, folded) } &&
            Lexicon.appReferences.any { isAWord(it, folded) } &&
            Lexicon.bookWords.none { folded.contains(it) }
    }

    /**
     * Le message entier, sans ses ouvertures (« et », « est-ce que »…) ni sa
     * ponctuation finale, est une question de prix ou de limite sans objet.
     */
    fun isBarePriceQuestion(folded: String): Boolean {
        var rest = questionCore(folded)
        var opened = true
        while (opened) {
            opened = false
            for (opener in Lexicon.bareQuestionOpeners) {
                if (!rest.startsWith("$opener ")) continue
                rest = rest.drop(opener.length + 1)
                while (rest.isNotEmpty() && rest.first().isWhitespace()) rest = rest.drop(1)
                opened = true
            }
        }
        return rest in Lexicon.barePriceQuestions
    }

    // MARK: La question

    fun isQuestion(text: String, folded: String): Boolean {
        if (text.endsWith("?")) return true
        return Lexicon.questionOpeners.any { folded.startsWith(it) }
    }

    fun subject(folded: String): ChatSignals.Subject? {
        // L'ordre compte : « corriger mon carnet » parle de correction, pas de
        // carnet. Le sujet le plus spécifique passe donc en premier.
        if (Lexicon.correctionWords.any { folded.contains(it) }) return ChatSignals.Subject.Corrections
        if (talksAboutSubscription(folded)) return ChatSignals.Subject.Subscription
        if (Lexicon.paceWords.any { folded.contains(it) }) return ChatSignals.Subject.Pace
        if (Lexicon.photoWords.any { folded.contains(it) }) return ChatSignals.Subject.Photos
        if (Lexicon.bookWords.any { folded.contains(it) }) return ChatSignals.Subject.Book
        return null
    }

    // MARK: L'humeur

    /**
     * Deux lexiques et un compteur d'intensifieurs. Les intensifieurs comptent
     * **double** du côté déjà majoritaire : « vraiment épuisé » est plus qu'un
     * « épuisé », et « c'était vraiment magnifique » plus qu'un « magnifique ».
     */
    fun mood(folded: String): ChatSignals.Mood {
        val positive = Lexicon.positiveWords.count { folded.contains(it) }
        val negative = Lexicon.negativeWords.count { folded.contains(it) }
        if (positive == negative) return ChatSignals.Mood.Neutral

        val intensity = Lexicon.intensifiers.count { folded.contains(it) }
        return if (positive + (if (positive > negative) intensity else 0) >
            negative + (if (negative > positive) intensity else 0)
        ) {
            ChatSignals.Mood.Positive
        } else {
            ChatSignals.Mood.Negative
        }
    }

    // MARK: Le refus

    /**
     * Un refus franc suffit ; « demain » seul ne compte que dans un message
     * très court. Sans cette nuance, « demain on part pour Lisbonne, j'ai hâte »
     * serait lu comme une fin de non-recevoir.
     */
    fun isRefusal(folded: String, length: ChatSignals.Length): Boolean {
        if (Lexicon.refusals.any { folded.contains(it) }) return true
        if (length != ChatSignals.Length.TooShort) return false
        return Lexicon.softRefusals.any { folded.contains(it) }
    }

    // MARK: Les chiffres

    /**
     * Un nombre collé à son unité (« 12km ») ou séparé d'elle (« 12 km »). Rendu
     * **normalisé sur une espace** — « 12 km » — parce que c'est ce qui se lit
     * dans une phrase, mais sans jamais toucher au nombre lui-même.
     */
    fun figures(tokens: List<ChatToken>): List<String> {
        val found = mutableListOf<String>()

        for ((index, token) in tokens.withIndex()) {
            val split = splitNumberAndUnit(token.folded)
            if (split != null) {
                append("${split.first} ${Lexicon.units[split.second] ?: split.second}", found)
                continue
            }

            val isNumeric = ChatGraphemes.swiftInt(token.folded) != null ||
                ChatGraphemes.isSwiftDouble(token.folded.replace(",", "."))
            if (!isNumeric || index + 1 >= tokens.size) continue
            val unit = Lexicon.units[tokens[index + 1].folded] ?: continue

            append("${token.text} $unit", found)
        }

        return found
    }

    /**
     * « 12km » → (« 12 », « km »). `null` dès que la coupure n'est pas nette :
     * on préfère ne rien relever qu'un chiffre mal découpé.
     */
    private fun splitNumberAndUnit(folded: String): Pair<String, String>? {
        val graphemes = ChatGraphemes.split(folded)
        val digits = graphemes.takeWhile { ChatGraphemes.isNumber(it) || it == "," || it == "." }
        if (digits.isEmpty()) return null
        val rest = graphemes.drop(digits.size).joinToString("")
        if (Lexicon.units[rest] == null) return null
        return digits.joinToString("") to rest
    }

    // MARK: -

    /**
     * Ajoute sans doublon, en gardant l'ordre d'apparition — c'est celui du
     * récit, et il vaut mieux qu'un tri.
     */
    private fun append(value: String, list: MutableList<String>) {
        if (value in list) return
        list.add(value)
    }
}

// MARK: - Les listes de mots

/**
 * Tous les mots que l'analyse cherche, au même endroit.
 *
 * Ils sont **repliés** : sans accents, en minuscules, apostrophes droites — la
 * forme que rend [Tokenizer.fold]. Écrire « épuisé » ici ne matcherait
 * jamais.
 */
internal object Lexicon {
    val timeMarkers: Set<String> = setOf(
        "hier", "avant-hier", "aujourd'hui", "ce matin", "ce midi", "ce soir",
        "cette nuit", "cet apres-midi", "l'apres-midi", "demain", "la veille",
        "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
        "la semaine derniere", "le week-end",
    )

    val months: Set<String> = setOf(
        "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout",
        "septembre", "octobre", "novembre", "decembre",
    )

    val placePrepositions: Set<String> = setOf(
        "a", "au", "aux", "vers", "depuis", "dans", "jusqu", "sur", "sous",
        "entre", "pres", "cote", "direction",
    )

    /**
     * Celles qui ne suffisent pas seules : elles ne comptent que derrière un
     * nom de lieu générique — voir [Extraction.places].
     */
    val weakPlacePrepositions: Set<String> = setOf("de", "du", "des", "d")

    /**
     * Ce qui, posé devant un nom de lieu générique, en fait un endroit plutôt
     * qu'un verbe.
     */
    val determiners: Set<String> = setOf(
        "le", "la", "les", "l", "un", "une", "du", "des", "au", "aux",
        "ce", "cet", "cette", "ces", "mon", "ma", "mes", "ton", "ta", "tes",
        "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
    )

    val personPrepositions: Set<String> = setOf(
        "avec", "chez", "mon", "ma", "mes", "notre", "nos", "sans",
    )

    val commonPlaces: Set<String> = setOf(
        "restaurant", "marche", "plage", "gare", "hotel", "musee", "col",
        "refuge", "village", "port", "ile", "quartier", "terrasse", "rue",
        "parc", "cafe", "montagne", "lac", "riviere", "sentier", "auberge",
        "aeroport", "cathedrale", "eglise", "chateau", "sommet", "vallee",
    )

    /**
     * Les mots capitalisés qui ne sont ni un lieu ni quelqu'un : pronoms,
     * connecteurs, jours, mois, et le nom de l'app elle-même.
     */
    val stopWords: Set<String> = setOf(
        "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "le", "la", "les", "un", "une", "des", "du", "de", "ce", "cet",
        "cette", "ca", "c", "et", "mais", "puis", "alors", "enfin", "bref",
        "donc", "or", "ni", "car", "quand", "comme", "hier", "demain",
        "aujourd", "memobook", "memo", "l", "d", "n", "s", "m", "t", "y",
        "apres", "avant", "aussi", "encore", "tres", "trop", "bien",
    ) + months + setOf("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")

    val questionOpeners: Set<String> = setOf(
        "est-ce que", "est-ce qu", "comment", "pourquoi", "qu'est-ce",
        "combien", "quand est-ce", "c'est quoi", "qui est-ce",
    )

    val bookWords: Set<String> = setOf(
        "carnet", "imprim", "livre", "reliure", "pages", "pdf", "apercu",
    )

    // L'abonnement, le crédit du jour, la limite du récit et le temps qui reste
    // pour raconter — et rien d'autre : pas le prix d'un billet ni la limite de
    // vitesse (03/10/2026). Les mêmes listes que le serveur
    // (`conversationHeuristics.ts`), lues par
    // [Extraction.talksAboutSubscription].

    /**
     * Les mots qui nomment l'offre à eux seuls, cherchés **en début de mot** :
     * « abonnement », « s’abonner », « résilier », « illimité ».
     */
    val subscriptionWords: Set<String> = setOf("abonn", "resili", "illimit")

    /**
     * Ce qui fait d'« illimité », d'« abonnement » ou d'un prix d'app une
     * autre offre que la nôtre, en mots entiers : le wifi illimité, le
     * kilométrage illimité, l'abonnement de métro, le forfait qu'on résilie.
     */
    val otherOffers: Set<String> = setOf(
        "wifi", "wi-fi", "internet", "data", "forfait", "forfaits", "telephone", "telephonique",
        "mobile", "kilometrage", "location", "metro", "transport", "transports", "navigo",
        "bus", "tram", "train", "trains", "pass", "parking", "velo", "velos", "ski", "musee",
        "musees", "buffet", "boisson", "boissons", "salle de sport", "piscine",
    )

    /**
     * Le crédit qui n'est pas le nôtre, en mots entiers : celui du téléphone,
     * de la carte, de la banque.
     */
    val otherCreditWords: Set<String> = setOf(
        "telephone", "telephones", "telephonique", "portable", "mobile", "sim", "forfait",
        "forfaits", "carte", "cartes", "bancaire", "banque", "operateur", "distributeur",
        "retrait", "data", "internet",
    )

    /**
     * Recharger un téléphone, en mots entiers — sauf le crédit qui « se
     * recharge » à minuit, qui est le nôtre.
     */
    val rechargeWords: Set<String> = setOf("recharger", "recharge", "recharges", "rechargement")

    /**
     * Le crédit du jour et la limite du récit, en locutions et en mots
     * entiers, qui n'ont pas d'autre sens en voyage. « crédit » ou « limite »
     * seuls n'y sont pas : « carte de crédit » et « limite de vitesse »
     * parlent du voyage.
     */
    val creditPhrases: Set<String> = setOf(
        "credit du jour", "credit restant", "credit quotidien", "credit de temps",
        "credit de recit", "mon credit", "ton credit", "notre credit", "votre credit",
        "combien de credit", "de credit il reste", "de credit il me reste",
        "limite du jour", "limite de recit", "limite du recit", "limite de minutes",
        "limite quotidienne", "limite par jour", "limite du credit",
        "raconter sans limite", "parler sans limite", "minutes de recit", "temps de recit",
        "raconter combien de temps", "parler combien de temps",
    )

    /**
     * Les locutions du temps et du crédit qui disent aussi le voyage :
     * « combien de minutes » est « à combien de minutes à pied », « limite de
     * temps » celle du Louvre. Elles ne visent l'offre que **rattachées au
     * récit** ([creditAnchors], [appReferences]) et loin d'un trajet
     * ([travelMarkers]).
     */
    val anchoredCreditPhrases: Set<String> = setOf(
        "le credit", "du credit", "plus de credit", "de credit",
        "limite de temps", "sans limite de temps", "est limite", "c'est limite a",
        "suis limite", "suis limitee", "suis bloque", "suis bloquee",
        "combien de minutes", "combien de temps", "minutes par jour", "minutes aujourd",
        "minutes du jour", "minutes restantes", "temps restant",
    )

    /** Ce qui rattache une locution au récit, cherché **en début de mot**. */
    val creditAnchors: Set<String> = setOf(
        "racont", "recit", "enregistr", "vocal", "vocaux", "abonn", "illimit", "aujourd",
        "par jour", "du jour", "minuit", "se recharg", "5 minutes", "cinq minutes",
    )

    /**
     * Un trajet, une visite, un départ — en mots entiers : le temps qu'il
     * faut, pas celui qui reste pour raconter.
     */
    val travelMarkers: Set<String> = setOf(
        "a pied", "de marche", "marche", "marcher", "pour aller", "pour rejoindre", "pour arriver",
        "en voiture", "en taxi", "en bus", "en train", "en metro", "en avion", "en bateau",
        "embarquement", "depart", "vol", "vols", "train", "bus", "metro", "avion", "bateau",
        "ferry", "trajet", "visite", "visiter", "attente", "escale", "correspondance", "check-in",
    )

    /**
     * « Il me reste combien ? » — la question d'exemple du prompt. Elle ne
     * vise le crédit que si rien ne la suit, hors [remainingObjects] puis
     * [remainingTails] (ou un mot du récit) — voir [Extraction.asksWhatRemains].
     */
    val remainingQuestions: List<String> = listOf(
        "il me reste combien", "il nous reste combien", "il reste combien",
        "combien il me reste", "combien il nous reste", "combien il reste",
        "combien me reste-t-il", "combien nous reste-t-il", "combien reste-t-il",
        "combien de temps il me reste", "combien de temps il nous reste", "combien de temps il reste",
        "combien de minutes il me reste", "combien de minutes il nous reste",
        "combien de minutes il reste", "temps qu'il me reste", "temps qu'il nous reste",
    )

    val remainingObjects: List<String> = listOf("de temps", "de minutes", "de credit", "en credit")

    val remainingTails: Set<String> = setOf(
        "", "aujourd'hui", "pour aujourd'hui", "ce soir", "pour ce soir", "pour raconter",
        "a raconter", "pour parler", "pour enregistrer", "a enregistrer",
    )

    /**
     * Le prix, en mots entiers. Seul, il parle d'un billet, d'un musée ou du
     * carnet : il ne vise l'offre que s'il nomme l'app ([appReferences]), ou
     * dans une question nue ([barePriceQuestions]).
     */
    val priceWords: Set<String> = setOf(
        "prix", "cout", "couts", "coute", "coutent", "couter", "coutera", "tarif", "tarifs",
        "payer", "payant", "payante", "paiement", "gratuit", "gratuite", "euro", "euros",
    )

    /**
     * L'app elle-même, en mots entiers : « l’app », « ton appli »,
     * « MemoBook ». « une app gratuite pour le métro » en est une autre.
     */
    val appReferences: Set<String> = setOf(
        "memobook", "memo", "l'app", "l'appli", "l'application", "ton app", "ton appli",
        "ton application", "votre app", "votre appli", "votre application", "cette app",
        "cette appli", "cette application",
    )

    /**
     * Une question de prix ou de limite **qui est tout le message** : sans
     * objet, elle ne peut viser que l'app. « Le musée, c'est payant ? » a un
     * objet, et n'y est pas.
     */
    val barePriceQuestions: Set<String> = setOf(
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
    )

    /** Ce qui peut précéder une question nue sans lui donner d'objet. */
    val bareQuestionOpeners: List<String> = listOf(
        "memo,", "et", "mais", "alors", "du coup", "sinon", "est-ce que",
    )

    val photoWords: Set<String> = setOf("photo", "pellicule", "image", "cliche")

    val correctionWords: Set<String> = setOf(
        "corriger", "corrige", "modifier", "modifie", "changer", "change",
        "retoucher", "retouche", "faute", "reecrire", "supprimer",
    )

    val paceWords: Set<String> = setOf(
        "relance", "relancer", "rythme", "notification", "rappel", "souvent",
        "frequence",
    )

    val positiveWords: Set<String> = setOf(
        "magnifique", "sublime", "incroyable", "genial", "adore", "coup de coeur",
        "dingue", "ravi", "heureux", "emu", "inoubliable", "parfait",
        "le meilleur", "fou rire", "superbe", "splendide", "hate", "j'ai aime",
        "on a aime", "content",
    )

    val negativeWords: Set<String> = setOf(
        "epuise", "creve", "decu", "galere", "rate", "penible", "perdu",
        "malade", "annule", "en retard", "nul", "difficile", "dur", "peur",
        "complique", "fatigue", "triste", "stresse", "cauchemar",
    )

    val intensifiers: Set<String> = setOf(
        "vraiment", "tellement", "trop", "hyper", "jamais vu", "le plus",
        "carrement", "franchement",
    )

    val refusals: Set<String> = setOf(
        "pas envie", "laisse tomber", "j'arrete", "pas maintenant",
        "non merci", "plus tard", "pas ce soir", "une autre fois",
        "je suis fatigue de", "arrete de",
    )

    /**
     * Ceux qui ne comptent que dans un message très court : ils sont trop
     * courants pour peser à eux seuls.
     */
    val softRefusals: Set<String> = setOf("demain", "stop", "plus tard", "non")

    /**
     * Unité repliée → unité telle qu'on la réécrit. Le nombre, lui, n'est
     * jamais retouché.
     */
    val units: Map<String, String> = mapOf(
        "e" to "€", "euro" to "€", "euros" to "€",
        "km" to "km", "kilometre" to "km", "kilometres" to "km",
        "m" to "m", "metre" to "m", "metres" to "m",
        "h" to "h", "heure" to "heures", "heures" to "heures",
        "min" to "min", "minute" to "minutes", "minutes" to "minutes",
        "jour" to "jour", "jours" to "jours",
        "pas" to "pas",
    )
}
