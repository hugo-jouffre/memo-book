package com.memobook.feature.profile

import com.memobook.core.TravellerProfile
import java.math.BigDecimal
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

/** Les valeurs du profil (`ProfileFormatting.kt`) : montants, délais, dates butoirs. */
class ProfileFormattingTest {
    private val paris = ZoneId.of("Europe/Paris")
    private val now = LocalDateTime.of(2026, 9, 1, 10, 0).atZone(paris).toInstant()

    /** Les espaces insécables du français, ramenées à des espaces pour la lecture. */
    private fun plain(text: String) = text.replace(' ', ' ').replace(' ', ' ')

    @Test fun anAmountInEurosHasTwoDecimalsAndItsSymbolAfter() {
        assertEquals("4,99 €", plain(BigDecimal("4.99").euros(Locale.FRANCE)))
        assertEquals("67,88 €", plain(BigDecimal("67.88").euros(Locale.FRANCE)))
        assertEquals("55,00 €", plain(BigDecimal("55").euros(Locale.FRANCE)))
    }

    /** La plus grande unité qui ne soit pas nulle, et la préposition dans la chaîne. */
    @Test fun theDelayNamesItsLargestUnit() {
        assertEquals("dans 3 semaines", now.plus(Duration.ofDays(21)).relativeDelay(now, paris))
        assertEquals("dans 1 semaine", now.plus(Duration.ofDays(10)).relativeDelay(now, paris))
        assertEquals("dans 3 jours", now.plus(Duration.ofDays(3)).relativeDelay(now, paris))
        assertEquals("dans 1 jour", now.plus(Duration.ofDays(1)).relativeDelay(now, paris))
        assertEquals("dans 3 heures", now.plus(Duration.ofHours(3)).relativeDelay(now, paris))
        assertEquals("dans 2 mois", LocalDateTime.of(2026, 11, 2, 10, 0).atZone(paris).toInstant().relativeDelay(now, paris))
        assertEquals("il y a 2 jours", now.minus(Duration.ofDays(2)).relativeDelay(now, paris))
    }

    /** Une date butoir se nomme, sans l'année. */
    @Test fun aDeadlineIsADayAndAMonth() {
        assertEquals("22 septembre", LocalDateTime.of(2026, 9, 22, 9, 0).atZone(paris).toInstant().dayAndMonth(Locale.FRANCE, paris))
    }

    @Test fun theTripCountAgrees() {
        assertEquals("0 voyage", TravellerProfile(fullName = "Camille", tripCount = 0).tripCountLabel)
        assertEquals("1 voyage", TravellerProfile(fullName = "Camille", tripCount = 1).tripCountLabel)
        assertEquals("5 voyages", TravellerProfile(fullName = "Camille", tripCount = 5).tripCountLabel)
    }
}
