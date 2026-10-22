package com.memobook.core

import com.memobook.core.DailyCreditCopy.duration
import com.memobook.core.DailyCreditCopy.characters

// Le jumeau de `MemoBookCore/DailyCreditSheetCopy.swift`. Swift y étend
// `DailyCreditCopy` d'un `enum Sheet` ; Kotlin n'ajoute pas de membre à un
// `object` depuis un autre fichier : la feuille est donc l'objet
// `DailyCreditSheetCopy`, que `DailyCreditCopy.Sheet` désigne, et la ligne des
// réglages une fonction d'extension de `DailyCreditCopy`.

/**
 * Les textes de la feuille « Crédit du jour », ouverte depuis la ligne du
 * même nom dans les réglages du voyage.
 *
 * **La feuille explique, elle ne fait pas la leçon** (Hugo, 03/10/2026) : ce
 * qui reste aujourd'hui, ce que ça représente à l'écrit, les trois règles qui
 * font le crédit, et la porte de l'illimité. Elle remplace celle des limites
 * de souvenirs : la ligne n'est plus un garde-fou discret, c'est le levier de
 * l'abonnement, et elle se lit donc en entier, sans chiffre caché.
 *
 * Comme le reste de [DailyCreditCopy], **aucun chiffre n'est écrit en dur** :
 * la durée du crédit et le barème de l'écrit sont lus sur le solde servi par
 * le serveur. Si le barème bouge, les phrases suivent.
 */
object DailyCreditSheetCopy {
    const val close = "Fermer"

    /**
     * La grande ligne du haut : « Il reste 3 min 20 aujourd’hui », ou le
     * constat quand il n'y a plus rien.
     */
    fun remaining(credit: DailyCredit): String =
        if (credit.isExhausted) {
            "Plus rien pour aujourd’hui : reviens demain"
        } else {
            "Il reste ${duration(credit.remainingMs)} aujourd’hui"
        }

    /**
     * Ce que TalkBack lit sur la jauge : « 3 min 20 restantes sur
     * 5 min ». La barre se remplit avec ce qui est raconté (08/10/2026),
     * le reste se dit en mots. Un pourcentage nu se comprenait de
     * travers (03/10/2026).
     */
    fun gaugeAccessibilityValue(credit: DailyCredit): String =
        "${DailyCreditCopy.rowValue(credit)} sur ${duration(credit.limitMs)}"

    /**
     * Sous la jauge : ce que le reste vaut au clavier. Rien quand il n'y a
     * plus rien — « soit environ 0 caractère » ne dirait que l'évidence.
     */
    fun charactersEquivalent(credit: DailyCredit): String? {
        if (credit.isUnlimited || credit.charactersLeft <= 0) return null
        return "soit environ ${characters(credit.charactersLeft)} à l’écrit"
    }

    /** Le partage : le crédit est celui du voyage, pas celui du compte. */
    fun sharing(limitMs: Int): String =
        "${spelledDuration(limitMs)} par jour pour ce voyage, à partager entre les co-voyageurs qui ne sont pas abonnés."

    /**
     * Ce qui consomme, et ce qui ne consomme pas. Les 800 caractères
     * viennent du barème (une minute divisée par le coût d'un caractère).
     */
    fun consumption(textMsPerCharacter: Int): String {
        val perMinute = if (textMsPerCharacter > 0) 60_000 / textMsPerCharacter else 0
        return "Un vocal consomme sa durée ; à l’écrit, ${characters(perMinute)} valent une minute. Les photos ne consomment rien."
    }

    /** La recharge — minuit, à l'heure de celui qui lit. */
    const val recharge = "Le crédit se recharge chaque nuit, à minuit."

    /**
     * Le paragraphe d'un abonné, à la place de la jauge et du bouton. Il
     * rappelle ce que l'abonnement n'ouvre pas : ses co-voyageurs non
     * abonnés partagent toujours le crédit du voyage.
     */
    fun unlimitedExplanation(limitMs: Int): String =
        "Avec ton abonnement, tu racontes sans limite, à l’oral comme à l’écrit, et tes récits ne prennent rien au crédit du voyage. Tes co-voyageurs qui ne sont pas abonnés partagent toujours les ${spelledDuration(limitMs)} du jour."

    /**
     * Sous l'explication d'un abonné, **renouvellement coupé**
     * (06/10/2026) : la date où l'illimité s'arrête, et ce qui revient.
     */
    fun unlimitedEnds(on: String, limitMs: Int): String =
        "Ton abonnement ne se renouvellera pas : tu racontes sans limite jusqu’au $on, puis tu retrouves les ${spelledDuration(limitMs)} du jour."

    /**
     * « 5 minutes », « 1 minute » — en toutes lettres quand la durée tombe
     * sur une minute ronde, ce qui est le cas du crédit. Sinon la forme
     * courte de [DailyCreditCopy.duration].
     */
    internal fun spelledDuration(milliseconds: Int): String {
        val seconds = maxOf(0, milliseconds) / 1000
        if (seconds < 60 || seconds % 60 != 0) return duration(milliseconds)
        val minutes = seconds / 60
        return if (minutes > 1) "$minutes minutes" else "1 minute"
    }
}

/**
 * Ce que TalkBack lit sur la ligne des réglages : le titre, la légende
 * et le reste, en une phrase.
 */
fun DailyCreditCopy.rowAccessibilityLabel(credit: DailyCredit): String =
    if (credit.isUnlimited) {
        "$title, $unlimited. $rowCaptionUnlimited."
    } else {
        "$title, ${rowCaption(limitMs = credit.limitMs)}. ${DailyCreditSheetCopy.remaining(credit)}."
    }
