package com.memobook.core

/**
 * **Ce qu'une correction au clavier modifie** (Hugo, 19/10/2026, QA D8) —
 * le pendant de `correctionCharacters` côté serveur
 * (`services/dailyCredit.ts`), au caractère près. Le jumeau de
 * `MemoBookCore/CorrectionMeasure.swift`.
 *
 * Une fiche offre 200 caractères modifiés, cumulés
 * (`DailyCredit.correctionFreeCharacters`) : pot vide, on corrige encore un
 * nom propre, un mot, une phrase. Au-delà, la correction paie comme un texte ;
 * pot vide, elle attend l'illimité. L'app mesure ici pour **prévenir avant
 * l'envoi** — le serveur, lui, tranche.
 */
object CorrectionMeasure {
    /**
     * Les blancs entre deux mots : une liste fermée, **la même que le
     * serveur** (`CORRECTION_BLANKS`) — `isWhitespace` et `\s` ne s'accordent
     * pas sur chaque scalaire.
     */
    internal val blanks: Set<Int> = setOf(
        ' '.code, '\t'.code, '\n'.code, '\r'.code, 0x00A0, 0x2007, 0x2009, 0x202F,
    )

    /**
     * Au-delà, l'alignement mot à mot cède la place à la longueur du passage
     * modifié (`CORRECTION_ALIGNMENT_LIMIT`).
     */
    internal const val alignmentLimit = 4_000_000

    /**
     * Les caractères du nouveau texte qui n'étaient pas dans l'ancien, en
     * scalaires Unicode (points de code, pas unités UTF-16) : on écarte le
     * début et la fin communs, puis on aligne le milieu mot à mot (plus longue
     * sous-suite commune, pondérée par la longueur des mots). « Famine » →
     * « Fanny » : 3. Retirer : 0.
     */
    fun changedCharacters(before: String, after: String): Int {
        val a = before.codePoints().toArray()
        val b = after.codePoints().toArray()
        var start = 0
        while (start < a.size && start < b.size && a[start] == b[start]) start += 1
        var endA = a.size
        var endB = b.size
        while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
            endA -= 1
            endB -= 1
        }
        val inserted = endB - start
        if (inserted == 0 || endA == start) return inserted

        val left = tokens(a, start, endA)
        val right = tokens(b, start, endB)
        if (left.size.toLong() * right.size.toLong() > alignmentLimit) return inserted

        var previous = IntArray(right.size + 1)
        for (i in 1..left.size) {
            val row = IntArray(right.size + 1)
            for (j in 1..right.size) {
                row[j] =
                    if (left[i - 1] == right[j - 1]) previous[j - 1] + right[j - 1].size
                    else maxOf(previous[j], row[j - 1])
            }
            previous = row
        }
        return inserted - previous[right.size]
    }

    /** Coupe en mots et en blancs, chacun d'un seul tenant. */
    private fun tokens(scalars: IntArray, from: Int, until: Int): List<List<Int>> {
        val result = mutableListOf<MutableList<Int>>()
        for (index in from until until) {
            val scalar = scalars[index]
            val last = result.lastOrNull()?.first()
            if (last != null && (last in blanks) == (scalar in blanks)) {
                result.last().add(scalar)
            } else {
                result.add(mutableListOf(scalar))
            }
        }
        return result
    }
}
