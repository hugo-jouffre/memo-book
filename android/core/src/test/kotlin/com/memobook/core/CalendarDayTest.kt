package com.memobook.core

import kotlinx.serialization.builtins.ListSerializer
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Un jour sans heure ni fuseau : la date de naissance des « Dernières
 * questions ». Ce qui compte ici, c'est qu'un jour qui n'existe pas ne se
 * crée pas, et qu'il traverse le serveur sans reculer d'un jour. Mêmes cas que
 * `CalendarDayTests.swift`.
 */
class CalendarDayTest {
    @Test
    fun readsWhatIsTypedAndWhatTheServerSends() {
        val typed = assertNotNull(CalendarDay.fromSlashed("12/05/1994"))
        assertEquals("1994-05-12", typed.iso)
        assertEquals(typed, CalendarDay.fromIso("1994-05-12"))
        assertEquals("12/05/1994", typed.slashed)
    }

    @Test
    fun refusesADayThatDoesNotExist() {
        assertNull(CalendarDay.fromSlashed("30/02/1994"))
        assertNull(CalendarDay.fromSlashed("12/13/1994"))
        assertNull(CalendarDay.fromSlashed("1/5/1994"))
        assertNull(CalendarDay.fromIso("1994-5-12"))
        assertNotNull(CalendarDay.fromSlashed("29/02/2000"))
    }

    @Test
    fun aBirthDateIsNeitherInTheFutureNorBefore1900() {
        val today = assertNotNull(CalendarDay(year = 2026, month = 9, day = 26))
        assertTrue(assertNotNull(CalendarDay(year = 1994, month = 5, day = 12)).isPlausibleBirthDate(today = today))
        assertTrue(today.isPlausibleBirthDate(today = today))
        assertFalse(assertNotNull(CalendarDay(year = 2026, month = 9, day = 27)).isPlausibleBirthDate(today = today))
        assertFalse(assertNotNull(CalendarDay(year = 1899, month = 12, day = 31)).isPlausibleBirthDate(today = today))
    }

    /** Le jour part et revient en `AAAA-MM-JJ` : c'est ce qui l'empêche de
     *  reculer d'un jour dans un fuseau à l'ouest de Greenwich. */
    @Test
    fun codesAsTheServerDay() {
        val day = assertNotNull(CalendarDay(year = 1994, month = 5, day = 12))
        val serializer = ListSerializer(CalendarDay.serializer())
        val data = MemoBookJson.encodeToString(serializer, listOf(day))
        assertEquals("""["1994-05-12"]""", data)
        assertEquals(listOf(day), MemoBookJson.decodeFromString(serializer, data))
    }

    /** La date du profil se lit comme un jour ; une forme illisible ne fait
     *  pas tomber le profil — la date manque, c'est tout. */
    @Test
    fun theProfileReadsItsBirthDateAndSurvivesAnUnreadableOne() {
        fun profile(birthDate: String): TravellerProfile {
            val json = """
                {
                  "fullName": "Camille Dupont",
                  "birthDate": "$birthDate",
                  "address": { "street": "7 Rue", "postalCode": "69007", "city": "Lyon", "country": "France" },
                  "wantsNewsletter": false,
                  "walletBalance": 0,
                  "cards": [],
                  "connectors": [],
                  "subscription": { "weeklyPrice": 1.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
                  "orders": []
                }
            """
            return MemoBookJson.decodeFromString(TravellerProfile.serializer(), json)
        }

        assertEquals(CalendarDay(year = 1994, month = 5, day = 12), profile(birthDate = "1994-05-12").birthDate)
        val unreadable = profile(birthDate = "le 12 mai")
        assertNull(unreadable.birthDate)
        assertEquals("Camille Dupont", unreadable.fullName)
    }
}
