package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/**
 * Un jour du calendrier, sans heure ni fuseau : une date de naissance. Le
 * jumeau de `MemoBookCore/CalendarDay.swift`.
 *
 * **Un jour et non un `Instant`**, parce qu'un `Instant` est un instant. La
 * naissance du 12 mai, envoyée comme minuit UTC, se relisait le 11 mai dans un
 * fuseau à l'ouest de Greenwich. Le serveur la garde en `DATE` et la rend
 * `AAAA-MM-JJ` ; ce type la transporte telle quelle, et c'est aussi lui qui lit
 * ce qu'on tape, `JJ/MM/AAAA`.
 *
 * Les initialiseurs faillibles d'iOS sont ici des fabriques qui rendent `null` :
 * `CalendarDay(year, month, day)`, `CalendarDay.fromIso(…)`, `CalendarDay.fromSlashed(…)`.
 */
@ConsistentCopyVisibility
@Serializable(with = CalendarDay.Serializer::class)
data class CalendarDay private constructor(
    val year: Int,
    val month: Int,
    val day: Int,
) : Comparable<CalendarDay> {

    /** `AAAA-MM-JJ`, la forme du serveur. */
    val iso: String get() = String.format(Locale.ROOT, "%04d-%02d-%02d", year, month, day)

    /** `JJ/MM/AAAA`, la forme qu'on tape. */
    val slashed: String get() = String.format(Locale.ROOT, "%02d/%02d/%04d", day, month, year)

    /** Une date de naissance qu'on peut croire : pas dans le futur, pas avant
     *  1900. La même borne que le serveur. */
    fun isPlausibleBirthDate(today: CalendarDay = CalendarDay(Instant.now())): Boolean =
        year >= 1900 && this <= today

    override fun compareTo(other: CalendarDay): Int =
        compareValuesBy(this, other, { it.year }, { it.month }, { it.day })

    companion object {
        /** `null` pour un jour qui n'existe pas — le 30 février, le mois 13. */
        operator fun invoke(year: Int, month: Int, day: Int): CalendarDay? = try {
            LocalDate.of(year, month, day)
            CalendarDay(year = year, month = month, day = day)
        } catch (_: DateTimeException) {
            null
        }

        /** Le jour qu'un instant désigne **dans ce fuseau** — celui de
         *  l'appareil, par défaut. */
        operator fun invoke(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): CalendarDay {
            val date = instant.atZone(zone).toLocalDate()
            return CalendarDay(year = date.year, month = date.monthValue, day = date.dayOfMonth)
        }

        /** `AAAA-MM-JJ`, la forme du serveur. */
        fun fromIso(iso: String): CalendarDay? {
            val parts = iso.split('-').filter { it.isNotEmpty() }
            if (parts.size != 3 || parts[0].length != 4 || parts[1].length != 2 || parts[2].length != 2) return null
            val year = parts[0].toIntOrNull() ?: return null
            val month = parts[1].toIntOrNull() ?: return null
            val day = parts[2].toIntOrNull() ?: return null
            return invoke(year, month, day)
        }

        /** `JJ/MM/AAAA`, la forme qu'on tape. */
        fun fromSlashed(slashed: String): CalendarDay? {
            val parts = slashed.split('/').filter { it.isNotEmpty() }
            if (parts.size != 3 || parts[0].length != 2 || parts[1].length != 2 || parts[2].length != 4) return null
            val day = parts[0].toIntOrNull() ?: return null
            val month = parts[1].toIntOrNull() ?: return null
            val year = parts[2].toIntOrNull() ?: return null
            return invoke(year, month, day)
        }
    }

    /** Lu et écrit `AAAA-MM-JJ` ; une autre forme est une erreur de décodage. */
    object Serializer : KSerializer<CalendarDay> {
        override val descriptor: SerialDescriptor =
            PrimitiveSerialDescriptor("com.memobook.core.CalendarDay", PrimitiveKind.STRING)

        override fun deserialize(decoder: Decoder): CalendarDay {
            val raw = decoder.decodeString()
            return fromIso(raw) ?: throw SerializationException("Jour illisible : $raw")
        }

        override fun serialize(encoder: Encoder, value: CalendarDay) {
            encoder.encodeString(value.iso)
        }
    }
}

