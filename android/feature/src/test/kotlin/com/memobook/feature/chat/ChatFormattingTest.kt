package com.memobook.feature.chat

import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

/** Les dates et les durées du chat (`ChatFormatting.kt`), en français. */
class ChatFormattingTest {
    private val paris = ZoneId.of("Europe/Paris")
    private val moment = LocalDateTime.of(2026, 8, 26, 18, 30).atZone(paris).toInstant()

    @Test fun theCardDateHasNoYearButTalkBackHearsItAll() {
        assertEquals("26 août", moment.chatDayLabel(Locale.FRANCE, paris))
        assertEquals("mercredi 26 août 2026", moment.chatFullDayLabel(Locale.FRANCE, paris))
    }

    /** Minutes non complétées, secondes toujours sur deux chiffres, et rien sous zéro. */
    @Test fun theDurationUnderAWaveform() {
        assertEquals("0:37", 37.0.chatDurationLabel)
        assertEquals("0:37", 36.6.chatDurationLabel)
        assertEquals("1:05", 65.0.chatDurationLabel)
        assertEquals("0:00", (-3.0).chatDurationLabel)
        // Au-delà de l'heure, les minutes continuent de compter.
        assertEquals("62:05", 3725.0.chatDurationLabel)
    }

    /** « 0:37 » lu à voix haute donne « zéro deux-points trente-sept ». */
    @Test fun theSpokenDuration() {
        assertEquals("37 secondes", 37.0.chatSpokenDurationLabel)
        assertEquals("1 seconde", 1.0.chatSpokenDurationLabel)
        assertEquals("0 seconde", 0.0.chatSpokenDurationLabel)
        assertEquals("1 minute", 60.0.chatSpokenDurationLabel)
        assertEquals("1 minute et 5 secondes", 65.0.chatSpokenDurationLabel)
        assertEquals("2 minutes et 1 seconde", 121.0.chatSpokenDurationLabel)
    }
}
