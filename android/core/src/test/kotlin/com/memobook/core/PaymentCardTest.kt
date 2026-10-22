package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * La date d'expiration se compose toute seule : le champ n'accepte que des
 * chiffres et pose la barre à la place de celui qui tape. Mêmes cas que
 * `PaymentCardTests.swift` (`PaymentCardExpiryTests`).
 */
class PaymentCardExpiryTest {
    @Test
    fun theFirstTwoDigitsStayBare() {
        assertEquals("", PaymentCard.formattedExpiry(""))
        assertEquals("1", PaymentCard.formattedExpiry("1"))
        assertEquals("12", PaymentCard.formattedExpiry("12"))
    }

    @Test
    fun theSlashAppearsOnTheThirdDigit() {
        assertEquals("12/2", PaymentCard.formattedExpiry("122"))
        assertEquals("12/28", PaymentCard.formattedExpiry("1228"))
    }

    /** La fonction est rappelée sur sa propre sortie à chaque frappe : elle ne
     *  doit donc rien ajouter à ce qu'elle a déjà écrit. */
    @Test
    fun anAlreadyFormattedValueDoesNotDouble() {
        assertEquals("12/28", PaymentCard.formattedExpiry("12/28"))
        assertEquals("12/28", PaymentCard.formattedExpiry(PaymentCard.formattedExpiry("1228")))
    }

    /** Le cas qui justifie la fonction : effacer le troisième chiffre emporte la
     *  barre, sinon il faut un second retour arrière sur un caractère qu'on n'a
     *  jamais tapé. */
    @Test
    fun deletingADigitTakesTheSlashWithIt() {
        assertEquals("12", PaymentCard.formattedExpiry("12/"))
        assertEquals("1", PaymentCard.formattedExpiry("1"))
    }

    @Test
    fun everythingButDigitsIsDroppedAndItStopsAtFour() {
        assertEquals("12/3", PaymentCard.formattedExpiry("1-2/3"))
        assertEquals("12/28", PaymentCard.formattedExpiry("ab12cd28ef"))
        assertEquals("12/28", PaymentCard.formattedExpiry("122899"))
    }
}
