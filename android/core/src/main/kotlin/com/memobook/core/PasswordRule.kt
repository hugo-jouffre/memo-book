package com.memobook.core

import java.text.BreakIterator

/**
 * La règle d'un mot de passe : au moins 8 caractères, une lettre et un
 * chiffre. La même que celle du serveur (`backend/src/routes/auth.ts`). Le
 * jumeau de `MemoBookCore/PasswordRule.swift`.
 *
 * Elle vit dans `:core` parce que **deux écrans la posent** :
 * l'inscription et le nouveau mot de passe après « Mot de passe oublié ».
 * Même raison que [EmailAddress] — deux copies auraient fini par diverger.
 */
object PasswordRule {
    /** La phrase affichée sous le champ. */
    const val hint = "8 caractères, 1 lettre, 1 chiffre"

    fun isValid(password: String): Boolean = Criterion.entries.all { it.isMet(password) }

    /**
     * Les trois critères, un par un, pour les cocher **pendant qu'on tape** —
     * la feuille « Modifier mon mot de passe » du profil (Hugo, 29/09/2026).
     * La même règle que [isValid], découpée : les deux ne peuvent pas
     * diverger, l'une est la conjonction de l'autre.
     */
    enum class Criterion {
        Length,
        Letter,
        Digit,
        ;

        val id: Criterion get() = this

        val label: String
            get() = when (this) {
                Length -> "8 caractères minimum"
                Letter -> "1 lettre"
                Digit -> "1 chiffre"
            }

        /** Les caractères se comptent comme `String.count` de Swift : un
         *  caractère affiché (graphème), pas une unité UTF-16. */
        fun isMet(password: String): Boolean = when (this) {
            Length -> password.graphemeCount() >= 8
            Letter -> password.codePoints().anyMatch { Character.isLetter(it) }
            Digit -> password.codePoints().anyMatch { it.isSwiftNumber() }
        }
    }
}

private fun String.graphemeCount(): Int {
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(this)
    var count = 0
    while (iterator.next() != BreakIterator.DONE) count++
    return count
}

/** `Character.isNumber` de Swift : tout chiffre Unicode, pas seulement 0–9. */
private fun Int.isSwiftNumber(): Boolean = when (Character.getType(this).toByte()) {
    Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
    else -> false
}
