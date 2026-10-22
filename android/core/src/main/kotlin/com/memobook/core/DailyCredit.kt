package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale

// Le jumeau de `MemoBookCore/DailyCredit.swift`.

/**
 * **Le crédit du jour d'un voyage** (Hugo, 03/10/2026).
 *
 * Tout le monde raconte gratuitement, dans la limite de **5 minutes par jour
 * et par voyage**, partagées entre les co-voyageurs qui ne sont pas abonnés.
 * Un seul crédit pour le vocal et l'écrit : un vocal consomme sa durée, un
 * texte une minute pour 800 caractères. Les photos ne consomment rien.
 * L'abonnement mensuel rend le récit illimité — **pour l'abonné seul** : il ne
 * prend rien au pot commun, et n'en ouvre pas un second à ses co-voyageurs.
 *
 * **Le serveur tranche, l'app prévient.** `services/dailyCredit.ts` mesure
 * chaque vocal, décompte dans la même transaction que la bulle, et refuse
 * au-delà (`429 daily_credit_exhausted`). Ce que l'app tient ici sert à
 * prévenir à 4:30, à faire pulser à 4:55 et à couper net à 5:00 — jamais à
 * décider seule : les seuils et le barème **voyagent avec le solde**, pour
 * qu'il n'y ait qu'une vérité à tenir d'accord.
 *
 * Les durées sont en **millisecondes de crédit**, comme côté serveur : un
 * texte en consomme 75 par caractère, et un vocal arrondi à la seconde aurait
 * laissé passer une demi-seconde à chaque envoi.
 *
 * @property isUnlimited Celui qui lit raconte sans limite : il est abonné.
 * @property limitMs Ce que le voyage peut raconter par jour.
 * @property usedMs Ce que le voyage a déjà raconté aujourd'hui, co-voyageurs compris.
 * @property textMsPerCharacter Ce qu'un caractère écrit consomme.
 * @property warningRemainingMs Le reste à partir duquel la barre d'enregistrement
 *   prévient (30 s).
 * @property urgentRemainingMs Le reste à partir duquel l'avertissement pulse (5 s).
 * @property exhaustionSlackMs Le reste **en dessous duquel le pot est vide** (1 s)
 *   — la règle `EXHAUSTION_SLACK_MS` du serveur, qui arrondit à zéro un reste de
 *   quelques millisecondes après un tour. Voir [isExhausted].
 * @property correctionFreeCharacters Les caractères de correction au clavier
 *   **offerts à chaque fiche**, cumulés : 200 (Hugo, 19/10/2026, QA D8). Pot vide,
 *   une correction passe tant qu'elle tient dedans — ce qu'il en reste pour une
 *   fiche voyage avec elle (`TranscriptCard.freeCorrectionCharactersLeft`). Voir
 *   [CorrectionMeasure].
 * @property day Le jour local du crédit, `AAAA-MM-JJ`.
 * @property resetsAt L'instant où le crédit se recharge — minuit, chez celui qui lit.
 */
@Serializable(with = DailyCredit.Serializer::class)
data class DailyCredit(
    val isUnlimited: Boolean = false,
    val limitMs: Int = Catalog.limitMs,
    val usedMs: Int = 0,
    val textMsPerCharacter: Int = Catalog.textMsPerCharacter,
    val warningRemainingMs: Int = Catalog.warningRemainingMs,
    val urgentRemainingMs: Int = Catalog.urgentRemainingMs,
    val exhaustionSlackMs: Int = Catalog.exhaustionSlackMs,
    val correctionFreeCharacters: Int = Catalog.correctionFreeCharacters,
    val day: String? = null,
    val resetsAt: Instant? = null,
) {
    /**
     * Le barème servi par défaut, celui du catalogue du serveur. Il ne sert
     * qu'au décodage d'une réponse incomplète et aux aperçus : la valeur qui
     * compte arrive toujours avec le solde.
     */
    object Catalog {
        const val limitMs = 300_000
        const val textMsPerCharacter = 75
        const val warningRemainingMs = 30_000
        const val urgentRemainingMs = 5_000

        /**
         * Ce qu'un dernier vocal peut dépasser du reste (`VOICE_TOLERANCE_MS`).
         * Le serveur ne le sert pas avec le solde : il ne sert qu'à reconnaître
         * un tour qui ne tiendra **jamais** dans une journée — voir
         * [DailyCredit.limitWithTolerance].
         */
        const val voiceToleranceMs = 3_000

        /**
         * Le reste en dessous duquel le pot est vide (`EXHAUSTION_SLACK_MS`).
         * Moins d'une seconde ne raconte rien : le serveur l'arrondit à zéro
         * après un tour, l'app le lit de même — sans quoi elle ouvrirait le
         * micro pour 400 ms, qu'elle refermerait aussitôt.
         */
        const val exhaustionSlackMs = 1_000

        /** Les caractères de correction offerts par fiche (`CORRECTION_FREE_CHARACTERS`). */
        const val correctionFreeCharacters = 200
    }

    // MARK: - Ce qui reste

    /** Ce qu'il reste aujourd'hui. Jamais négatif. */
    val remainingMs: Int get() = maxOf(0, limitMs - usedMs)

    /**
     * Plus rien pour aujourd'hui. Un abonné n'est jamais à court.
     *
     * **Moins d'une seconde, c'est plus rien** (03/10/2026) — comme au
     * serveur (`EXHAUSTION_SLACK_MS`). Le serveur ne laisse jamais ce reste ;
     * une estimation locale — un vocal arrêté à 0:59,6 hors ligne sur une
     * minute — ou un solde d'avant la règle, si. Lu « restant », il gardait
     * le micro ouvert pour un vocal de 400 ms, coupé aussitôt, puis refusé
     * au retour du réseau : une bulle vide « Partira demain ».
     */
    val isExhausted: Boolean get() = !isUnlimited && remainingMs < maxOf(1, exhaustionSlackMs)

    /** Où en est la jauge, entre 0 et 1. */
    val fraction: Double
        get() {
            if (limitMs <= 0) return 1.0
            return minOf(1.0, usedMs.toDouble() / limitMs.toDouble())
        }

    /**
     * Ce qu'il resterait une fois le vocal en cours compté.
     *
     * **Une projection, jamais un décompte** (Hugo, 06/10/2026) : elle ne
     * sert qu'au bandeau et à l'arrêt net **pendant que le vocal existe** —
     * en cours ou en pause. Rien ne l'écrit dans un crédit : un vocal mis en
     * pause puis abandonné ne coûte rien, nulle part. Seul l'envoyé compte —
     * le serveur à sa réception, l'app entre-temps pour ce qui attend la file
     * (la conversation, l'accueil, les réglages du voyage).
     */
    fun remainingMs(whileRecording: Int): Int = maxOf(0, remainingMs - maxOf(0, whileRecording))

    /**
     * Le même crédit, ce qu'on vient d'envoyer décompté — l'estimation que
     * l'app tient entre deux réponses du serveur, hors ligne surtout. Un
     * reste de moins d'une seconde s'arrondit à zéro, comme le serveur le
     * fera en recevant le tour ([Catalog.exhaustionSlackMs]).
     */
    fun consuming(milliseconds: Int): DailyCredit {
        if (isUnlimited || milliseconds <= 0) return this
        var used = minOf(limitMs, usedMs + milliseconds)
        if (limitMs - used < exhaustionSlackMs) used = maxOf(used, limitMs)
        return copy(usedMs = used)
    }

    /**
     * Le même crédit, **rechargé** si son heure de recharge est passée : rien
     * de consommé, le barème et `isUnlimited` gardés (03/10/2026).
     *
     * Un crédit gardé — le cache de l'accueil, le dernier qu'un fil a connu —
     * ne se relit jamais tel quel : épuisé hier à 22 h 30, il dirait encore
     * « épuisé » ce matin dans l'avion, et le micro refuserait un vocal que la
     * file aurait gardé. Chaque lecture d'un crédit gardé passe donc par ici —
     * le fil et la feuille d'enregistrement, l'accueil et les réglages.
     *
     * La recharge suivante est **le même minuit, autant de jours plus tard
     * qu'il faut** : le crédit rechargé garde un compte à rebours juste, et se
     * rechargera encore s'il dort une nuit de plus. `day` tombe, faute de
     * savoir l'écrire au fuseau du serveur ; le serveur le redira.
     *
     * Le `Calendar` de Swift est ici son fuseau, `zone` : les jours s'ajoutent
     * en jours civils, changements d'heure compris.
     */
    fun refreshed(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): DailyCredit {
        val resetsAt = resetsAt ?: return this
        if (resetsAt > now) return this
        val start = resetsAt.atZone(zone)
        val elapsedDays = ChronoUnit.DAYS.between(start, now.atZone(zone))
        var next = start.plusDays(maxOf(0L, elapsedDays)).toInstant()
        while (next <= now) {
            next = next.atZone(zone).plusDays(1).toInstant()
        }
        return copy(usedMs = 0, day = null, resetsAt = next)
    }

    /**
     * **Le plus avancé de deux crédits servis** pour le même voyage
     * (03/10/2026) — les caches de l'écran du voyage et de l'accueil, le
     * dernier qu'un fil a connu, un mot rejoué par la file. Aucun ne sait
     * lequel est le plus frais : chacun a été écrit à sa dernière lecture.
     * Mais la consommation d'une journée **ne fait que croître**, et le jour
     * ne recule jamais (`services/dailyCredit.ts`). Donc :
     *
     * 1. le jour le plus tardif l'emporte — `day` quand les deux le portent,
     *    sinon l'heure de recharge (un crédit rechargé par [refreshed] n'a plus
     *    de `day`) ;
     * 2. à jour égal, le plus consommé ;
     * 3. illimité dès que l'un des deux le dit — le lecteur est abonné, et
     *    un crédit servi avant l'achat ne le sait pas encore.
     *
     * Le premier trouvé gagnait jusqu'ici : un cache du matin à 5:00 passait
     * devant celui de l'accueil, relu après un vocal de 4 minutes, et le fil
     * hors ligne laissait dicter ce que le serveur refuserait.
     */
    fun merged(with: DailyCredit?): DailyCredit {
        val other = with ?: return this
        val order = dayOrder(this, other)
        val latest = when {
            order < 0 -> other
            order > 0 -> this
            else -> if (other.usedMs > usedMs) other else this
        }
        return latest.copy(isUnlimited = isUnlimited || other.isUnlimited)
    }

    /**
     * Le plus long tour qu'une journée entière laisse passer : la limite, et
     * pour un vocal la tolérance du serveur en plus. Au-delà, attendre demain
     * ne servirait à rien — le pot plein le refuserait encore.
     */
    fun limitWithTolerance(forVoice: Boolean): Int =
        if (forVoice) limitMs + Catalog.voiceToleranceMs else limitMs

    // MARK: - L'écrit

    /**
     * Ce qu'un texte consomme. Les caractères se comptent en **scalaires
     * Unicode**, comme le serveur (`[...text].length`) : un emoji composé ne
     * coûte pas la même chose selon qu'on compte en UTF-16 ou en graphèmes, et
     * les deux côtés doivent tomber sur le même nombre.
     */
    fun cost(ofText: String): Int = ofText.codePointCount(0, ofText.length) * textMsPerCharacter

    /**
     * Ce texte part-il encore aujourd'hui ? Rien sur un pot vide — moins
     * d'une seconde compris ([isExhausted]).
     */
    fun allows(text: String): Boolean = isUnlimited || (!isExhausted && cost(ofText = text) <= remainingMs)

    /**
     * Ce qu'une **correction au clavier** coûte au crédit (Hugo, 19/10/2026,
     * QA D8) : les caractères modifiés ([CorrectionMeasure]) au-delà de ce
     * qui reste des 200 offerts à la fiche, au barème d'un texte. `freeLeft`
     * inconnu — un serveur d'avant — vaut les 200 entiers : le serveur
     * tranchera.
     */
    fun cost(ofCorrection: String, replacing: String, freeLeft: Int?): Int {
        if (isUnlimited) return 0
        val changed = CorrectionMeasure.changedCharacters(replacing, ofCorrection)
        val offered = minOf(changed, maxOf(0, freeLeft ?: correctionFreeCharacters))
        return (changed - offered) * textMsPerCharacter
    }

    /**
     * Combien de caractères le reste du jour laisse écrire. Aucun sur un pot
     * vide : « il te reste environ 5 caractères » sous « crédit épuisé »
     * ferait deux phrases qui se contredisent.
     */
    val charactersLeft: Int
        get() {
            if (textMsPerCharacter <= 0 || isExhausted) return 0
            return remainingMs / textMsPerCharacter
        }

    // MARK: - La barre d'enregistrement

    /** Ce que la barre d'enregistrement montre, à un reste donné. */
    enum class Phase {
        /** Rien à dire. */
        Calm,

        /** Moins de 30 secondes : l'avertissement rouge, doux, paraît. */
        Warning,

        /** Moins de 5 secondes : il pulse. */
        Urgent,

        /** Plus rien : l'enregistrement s'arrête net. */
        Exhausted,
    }

    /**
     * La phase pour un reste donné — celui du jour, ou celui qui reste
     * pendant qu'on parle ([remainingMs] `(whileRecording)`).
     */
    fun phase(remainingMs: Int): Phase {
        if (isUnlimited) return Phase.Calm
        if (remainingMs <= 0) return Phase.Exhausted
        if (remainingMs <= urgentRemainingMs) return Phase.Urgent
        if (remainingMs <= warningRemainingMs) return Phase.Warning
        return Phase.Calm
    }

    /**
     * La phase avant de commencer à parler : « épuisé » dès que le pot est
     * vide au sens du serveur ([isExhausted]), moins d'une seconde
     * comprise — on n'ouvre pas le micro pour la refermer aussitôt.
     */
    val phase: Phase get() = if (isExhausted) Phase.Exhausted else phase(remainingMs = remainingMs)

    companion object {
        /**
         * Lequel des deux crédits est d'un jour plus tardif : négatif quand `b`
         * l'est (`orderedAscending`), positif quand c'est `a`, zéro quand c'est
         * le même jour, ou qu'on ne sait pas les départager.
         */
        private fun dayOrder(a: DailyCredit, b: DailyCredit): Int {
            // `AAAA-MM-JJ` se range dans l'ordre des jours.
            if (a.day != null && b.day != null) return a.day.compareTo(b.day).sign()
            if (a.resetsAt != null && b.resetsAt != null) return a.resetsAt.compareTo(b.resetsAt).sign()
            return 0
        }

        private fun Int.sign(): Int = if (this < 0) -1 else if (this > 0) 1 else 0
    }

    /** Le JSON servi : tout est facultatif, et la date de recharge peut être illisible. */
    @Serializable
    @SerialName("DailyCredit")
    private class Surrogate(
        val isUnlimited: Boolean? = null,
        val limitMs: Int? = null,
        val usedMs: Int? = null,
        val textMsPerCharacter: Int? = null,
        val warningRemainingMs: Int? = null,
        val urgentRemainingMs: Int? = null,
        val exhaustionSlackMs: Int? = null,
        val correctionFreeCharacters: Int? = null,
        val day: String? = null,
        val resetsAt: JsonElement? = null,
    )

    /**
     * Décodage tolérant : un serveur qui ne sert pas encore un champ ne doit
     * pas faire tomber le fil ni les réglages. On retombe sur le catalogue.
     */
    object Serializer : KSerializer<DailyCredit> {
        override val descriptor: SerialDescriptor = Surrogate.serializer().descriptor

        override fun deserialize(decoder: Decoder): DailyCredit {
            val raw = decoder.decodeSerializableValue(Surrogate.serializer())
            // Une date de recharge illisible ne coule pas le crédit (`try?`).
            val resetsAt = (raw.resetsAt as? JsonPrimitive)
                ?.takeIf { it.isString }
                ?.let { MemoBookDate.parse(it.content) }
            return DailyCredit(
                isUnlimited = raw.isUnlimited ?: false,
                limitMs = raw.limitMs ?: Catalog.limitMs,
                usedMs = raw.usedMs ?: 0,
                textMsPerCharacter = raw.textMsPerCharacter ?: Catalog.textMsPerCharacter,
                warningRemainingMs = raw.warningRemainingMs ?: Catalog.warningRemainingMs,
                urgentRemainingMs = raw.urgentRemainingMs ?: Catalog.urgentRemainingMs,
                // Servi depuis le 03/10/2026 ; un serveur d'avant ne le dit pas, et
                // sa règle est la même.
                exhaustionSlackMs = raw.exhaustionSlackMs ?: Catalog.exhaustionSlackMs,
                // Servi depuis le 19/10/2026 ; un serveur d'avant ne l'offre pas, mais
                // l'app ne fait que prévenir — il tranchera.
                correctionFreeCharacters = raw.correctionFreeCharacters ?: Catalog.correctionFreeCharacters,
                day = raw.day,
                resetsAt = resetsAt,
            )
        }

        override fun serialize(encoder: Encoder, value: DailyCredit) {
            encoder.encodeSerializableValue(
                Surrogate.serializer(),
                Surrogate(
                    isUnlimited = value.isUnlimited,
                    limitMs = value.limitMs,
                    usedMs = value.usedMs,
                    textMsPerCharacter = value.textMsPerCharacter,
                    warningRemainingMs = value.warningRemainingMs,
                    urgentRemainingMs = value.urgentRemainingMs,
                    exhaustionSlackMs = value.exhaustionSlackMs,
                    correctionFreeCharacters = value.correctionFreeCharacters,
                    day = value.day,
                    resetsAt = value.resetsAt?.let { JsonPrimitive(MemoBookDate.format(it)) },
                ),
            )
        }
    }
}

/**
 * Les textes du crédit du jour : la barre d'enregistrement, la ligne et la
 * feuille des réglages du voyage, la bulle « reviens demain ».
 *
 * **Doux, mais explicite** (Hugo, 03/10/2026) : on dit ce qui reste et ce qui
 * se passe, sans faire la leçon. Le chiffre de la limite est lu sur le solde,
 * jamais écrit en dur : si le barème bouge, les phrases suivent.
 *
 * La feuille « Crédit du jour » est dans `DailyCreditSheetCopy.kt`, comme sur iOS ;
 * [Sheet] y mène.
 */
object DailyCreditCopy {
    const val title = "Crédit du jour"
    const val unlimited = "Illimité"

    /** Sous la ligne d'un abonné, dans les réglages du voyage (18/10/2026). */
    const val cancelSubscription = "Résilier"

    /** La feuille « Crédit du jour » — `DailyCreditCopy.Sheet` de Swift. */
    val Sheet: DailyCreditSheetCopy get() = DailyCreditSheetCopy

    /**
     * « 5 min », « 3 min 20 », « 45 s ». Arrondi à la seconde **inférieure**
     * pendant un compte à rebours : annoncer 30 s quand il en reste 29,6
     * promettrait une demi-seconde qui n'existe pas.
     */
    fun duration(milliseconds: Int): String {
        val seconds = maxOf(0, milliseconds) / 1000
        val minutes = seconds / 60
        val rest = seconds % 60
        if (minutes == 0) return "$rest s"
        if (rest == 0) return "$minutes min"
        return if (rest < 10) "$minutes min 0$rest" else "$minutes min $rest"
    }

    /**
     * « 2 650 caractères », séparateur de milliers français (espace fine
     * insécable, U+202F — celle du `fr_FR` d'iOS, posée à la main pour ne pas
     * dépendre de la version des données de locale du JDK).
     */
    fun characters(count: Int): String {
        val formatted = frenchInteger().format(count.toLong())
        return if (count > 1) "$formatted caractères" else "$formatted caractère"
    }

    private fun frenchInteger(): DecimalFormat {
        val symbols = DecimalFormatSymbols(Locale.FRANCE).apply {
            groupingSeparator = ' '
            minusSign = '-'
        }
        return DecimalFormat("#,##0", symbols)
    }

    // — La barre d'enregistrement

    /**
     * L'avertissement, à partir de 30 secondes. Le nombre descend avec le
     * temps : on lit le compte à rebours, pas une alerte figée.
     */
    fun warning(remainingMs: Int): String {
        val seconds = maxOf(0, remainingMs) / 1000
        return if (seconds > 1) {
            "Plus que $seconds secondes avant la limite du jour"
        } else {
            "Plus qu’une seconde avant la limite du jour"
        }
    }

    const val exhaustedTitle = "Crédit du jour épuisé"
    const val exhaustedDetail = "Reviens demain, ou passe en illimité"
    const val unlimitedCallToAction = "Passer en illimité"

    /** Le texte dépasse ce qu'il reste aujourd'hui. */
    fun textTooLong(charactersLeft: Int): String =
        if (charactersLeft > 0) {
            "Ce message dépasse le crédit du jour : il te reste environ ${characters(charactersLeft)}."
        } else {
            "Le crédit du jour est épuisé : reviens demain pour écrire la suite."
        }

    /**
     * Une correction au-delà des 200 caractères offerts, pot vide — **la même
     * phrase que le refus du serveur** (`CORRECTION_BEYOND_FREE_MESSAGE`).
     */
    const val correctionBeyondFree =
        "Au-delà de 200 caractères modifiés, la correction passe par l’illimité."

    /**
     * La bulle de MEMO quand le crédit tombe à zéro. **La même phrase que le
     * serveur** (`DAILY_CREDIT_EXHAUSTED_MESSAGE`, `conversationCopy.ts`) :
     * l'app la pose elle-même hors ligne, le serveur la pose en ligne.
     */
    const val exhaustedMessage =
        "Quelle journée ! Ce voyage a déjà raconté ses 5 minutes du jour. Je garde tout précieusement : reviens demain pour la suite, le crédit se recharge à minuit."

    // — Les réglages du voyage

    /** La légende de la ligne, pour qui n'est pas abonné. */
    fun rowCaption(limitMs: Int): String = "${duration(limitMs)} par jour pour tout le voyage"

    const val rowCaptionUnlimited = "Tu racontes sans limite grâce à ton abonnement"

    /**
     * La même légende, **renouvellement coupé** (06/10/2026) : l'illimité a
     * une date de fin, et la ligne la dit — « jusqu’au 12 octobre ». `day`
     * arrive formaté (jour et mois) ; `null` rend la légende d'un abonné.
     */
    fun rowCaptionUnlimited(until: String?): String {
        val day = until ?: return rowCaptionUnlimited
        return "Tu racontes sans limite jusqu’au $day grâce à ton abonnement"
    }

    /**
     * **Ce qui reste**, en toutes lettres : « 3 min 20 restantes »
     * (Hugo, 08/10/2026). La jauge d'à côté se remplit avec ce qui est
     * raconté ; c'est le chiffre qui dit le reste, et il le dit sans
     * fraction à déchiffrer. « Épuisé » à zéro, en rouge à l'écran.
     */
    fun rowValue(credit: DailyCredit): String {
        if (credit.isUnlimited) return unlimited
        if (credit.isExhausted) return exhaustedValue
        val seconds = credit.remainingMs / 1000
        // Le singulier pour une unité seule — « 1 min restante », « 1 s
        // restante » ; « 1 min 30 restantes » compte bien plus d'une minute.
        val isSingular = seconds < 2 || seconds == 60
        return "${duration(credit.remainingMs)} ${if (isSingular) "restante" else "restantes"}"
    }

    /** La valeur de la ligne quand il ne reste rien aujourd'hui. */
    const val exhaustedValue = "Épuisé"
}
