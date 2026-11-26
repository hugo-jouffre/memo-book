package com.memobook.feature.chat

import com.memobook.core.TranscriptCard
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToLong

// La mise en forme du chat : dates, durées, compteurs. Jumeau de
// `Chat/ChatFormatting.swift`.
//
// À part de la vue, et par des formateurs plutôt que par concaténation — même
// parti pris que `TripFormatting` et `ProfileFormatting`. C'est `java.time` qui
// sait écrire un jour de la semaine en français, à la locale de l'app.

/**
 * « 26 août » — la date que porte une fiche de retranscription.
 *
 * Sans l'année : dans un fil de conversation, elle est presque toujours celle
 * du jour, et l'écrire à chaque fiche mange la ligne pour rien. Voir
 * [chatFullDayLabel] pour la version que lit TalkBack.
 */
val Instant.chatDayLabel: String
    get() = chatDayLabel(Locale.getDefault(), ZoneId.systemDefault())

fun Instant.chatDayLabel(locale: Locale, zone: ZoneId): String =
    DateTimeFormatter.ofPattern("d MMMM", locale).format(atZone(zone))

/**
 * « mercredi 26 août 2026 » — ce que TalkBack annonce.
 *
 * En toutes lettres et avec l'année, parce qu'une annonce vocale ne se relit
 * pas : ce qui est ambigu à l'oreille est perdu.
 */
val Instant.chatFullDayLabel: String
    get() = chatFullDayLabel(Locale.getDefault(), ZoneId.systemDefault())

fun Instant.chatFullDayLabel(locale: Locale, zone: ZoneId): String =
    DateTimeFormatter.ofPattern("EEEE d MMMM y", locale).format(atZone(zone))

/**
 * **La date que la fiche affiche** : celle que le récit raconte, et `null`
 * quand il ne s'est pas situé (T308). Jumeau de `TranscriptCard.livedDatesLabel`.
 *
 * Une journée donne « 28 août », une période « 28–30 août » : l'année n'y est
 * pas, comme pour [chatDayLabel] — dans un fil, elle est presque toujours
 * celle du jour. Ce que les deux bornes partagent ne s'écrit qu'une fois,
 * comme l'intervalle de `TripDates`.
 *
 * `null` n'est pas un trou à combler : la fiche n'affichait le jour de
 * l'**enregistrement** que faute de mieux, et un dimanche imprimé sur une
 * journée de vendredi est pire qu'une fiche sans date.
 */
val TranscriptCard.livedDatesLabel: String?
    get() = livedDatesLabel(Locale.getDefault(), ZoneId.systemDefault())

fun TranscriptCard.livedDatesLabel(locale: Locale, zone: ZoneId): String? {
    val from = livedFrom ?: return null
    val to = livedTo
    if (to == null || to <= from) return from.chatDayLabel(locale, zone)
    val start = from.atZone(zone)
    val end = to.atZone(zone)
    val day = DateTimeFormatter.ofPattern("d", locale)
    return if (start.monthValue == end.monthValue && start.year == end.year) {
        "${day.format(start)}–${to.chatDayLabel(locale, zone)}"
    } else {
        "${from.chatDayLabel(locale, zone)} – ${to.chatDayLabel(locale, zone)}"
    }
}

/**
 * La même chose pour TalkBack : en toutes lettres, avec l'année — une annonce
 * vocale ne se relit pas.
 */
val TranscriptCard.livedDatesSpokenLabel: String?
    get() = livedDatesSpokenLabel(Locale.getDefault(), ZoneId.systemDefault())

fun TranscriptCard.livedDatesSpokenLabel(locale: Locale, zone: ZoneId): String? {
    val from = livedFrom ?: return null
    val to = livedTo
    if (to == null || to <= from) return from.chatFullDayLabel(locale, zone)
    return "${from.chatFullDayLabel(locale, zone)} – ${to.chatFullDayLabel(locale, zone)}"
}

/**
 * « 0:37 » — la durée, en secondes (le `TimeInterval` d'iOS), sous une forme
 * d'onde.
 *
 * Le motif minute-seconde du système d'iOS (`.minuteSecond(padMinuteToLength: 1)`) :
 * les minutes ne sont pas complétées, les secondes le sont toujours, et un
 * vocal qui dépasserait les soixante minutes compte ses minutes au-delà de 59
 * au lieu de repartir de zéro.
 */
val Double.chatDurationLabel: String
    get() {
        val total = roundedSeconds(this)
        return "${total / 60}:${(total % 60).toString().padStart(2, '0')}"
    }

/**
 * « 37 secondes » — ce que TalkBack annonce. Un « 0:37 » lu à voix haute
 * donne « zéro deux-points trente-sept ».
 *
 * Les minutes et les secondes seulement, en toutes lettres, et l'unité nulle
 * se tait — le `.units(allowed: [.minutes, .seconds], width: .wide)` d'iOS.
 */
val Double.chatSpokenDurationLabel: String
    get() {
        val total = roundedSeconds(this)
        val minutes = total / 60
        val seconds = total % 60
        fun unit(count: Long, singular: String) = if (count <= 1) "$count $singular" else "$count ${singular}s"
        return when {
            minutes == 0L -> unit(seconds, "seconde")
            seconds == 0L -> unit(minutes, "minute")
            else -> "${unit(minutes, "minute")} et ${unit(seconds, "seconde")}"
        }
    }

/** Le `max(0, rounded())` d'iOS : à la seconde la plus proche, jamais négatif. */
private fun roundedSeconds(interval: Double): Long =
    if (interval.isNaN()) 0 else maxOf(0.0, interval).roundToLong()
