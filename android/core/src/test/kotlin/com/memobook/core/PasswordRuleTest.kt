package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Mêmes cas que `PasswordRuleTests.swift`. */
class PasswordRuleTest {
    @Test
    fun acceptsEightCharactersWithALetterAndADigit() {
        assertTrue(PasswordRule.isValid("carnet2026"))
        assertTrue(PasswordRule.isValid("a1234567"))
    }

    @Test
    fun refusesWhatTheServerRefuses() {
        assertFalse(PasswordRule.isValid("court1"), "moins de 8 caractères")
        assertFalse(PasswordRule.isValid("12345678"), "aucune lettre")
        assertFalse(PasswordRule.isValid("motdepasse"), "aucun chiffre")
        assertFalse(PasswordRule.isValid(""))
    }
}
