package com.memobook.feature.profile

import com.memobook.core.CurrentTrip
import com.memobook.core.TravellerProfile
import java.math.BigDecimal
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Currency
import java.util.Locale

// Mise en forme des valeurs du profil. Jumeau de `Profile/ProfileFormatting.swift`.
// Les règles vivent ici, pas dans les vues : un montant s'écrit pareil dans le
// tunnel de commande et sur l'offre du paywall.

/**
 * Un montant en euros, écrit selon la région de l'utilisateur.
 *
 * La maquette écrit « 67,88€ », collé. On passe quand même par le formateur du
 * système : c'est lui qui sait qu'un français attend une espace insécable avant
 * le symbole, et qu'un lecteur d'une autre région attend autre chose. L'écart
 * est signalé dans la fiche écran.
 */
val BigDecimal.euros: String
    get() = euros(Locale.getDefault())

fun BigDecimal.euros(locale: Locale): String =
    NumberFormat.getCurrencyInstance(locale).apply {
        currency = Currency.getInstance("EUR")
        minimumFractionDigits = 2
        maximumFractionDigits = 2
    }.format(this)

/**
 * Le temps qui nous sépare de cette date, écrit comme on le dit :
 * « dans 3 semaines ».
 *
 * **La préposition fait partie de la chaîne** — c'est le formateur qui la
 * choisit, « dans » ou « il y a ». La phrase de la feuille se termine donc par
 * le délai, elle ne l'encadre pas.
 *
 * Le formateur choisit aussi l'unité : la plus grande qui ne soit pas nulle,
 * comme le `.relative(presentation: .numeric)` d'iOS. Trois semaines
 * s'écrivent « dans 3 semaines », trois jours « dans 3 jours ». La maquette ne
 * montre que le premier cas ; le second sort tout seul.
 */
val Instant.relativeDelay: String
    get() = relativeDelay(Instant.now(), ZoneId.systemDefault())

fun Instant.relativeDelay(now: Instant, zone: ZoneId): String {
    val isFuture = this >= now
    var from = (if (isFuture) now else this).atZone(zone).toLocalDateTime()
    val to = (if (isFuture) this else now).atZone(zone).toLocalDateTime()

    // Les composantes du calendrier, de la plus grande à la plus petite :
    // chacune se retire avant de compter la suivante.
    val years = ChronoUnit.YEARS.between(from, to).also { from = from.plusYears(it) }
    val months = ChronoUnit.MONTHS.between(from, to).also { from = from.plusMonths(it) }
    val days = ChronoUnit.DAYS.between(from, to).also { from = from.plusDays(it) }
    val hours = ChronoUnit.HOURS.between(from, to).also { from = from.plusHours(it) }
    val minutes = ChronoUnit.MINUTES.between(from, to).also { from = from.plusMinutes(it) }
    val seconds = ChronoUnit.SECONDS.between(from, to)

    val phrase = when {
        years > 0 -> RelativeUnit.Year.phrase(years)
        months > 0 -> RelativeUnit.Month.phrase(months)
        days >= 7 -> RelativeUnit.Week.phrase(days / 7)
        days > 0 -> RelativeUnit.Day.phrase(days)
        hours > 0 -> RelativeUnit.Hour.phrase(hours)
        minutes > 0 -> RelativeUnit.Minute.phrase(minutes)
        else -> RelativeUnit.Second.phrase(seconds)
    }
    return if (isFuture) "dans $phrase" else "il y a $phrase"
}

/** Les unités du délai, accordées : en français, zéro et un sont au singulier. */
private enum class RelativeUnit(private val singular: String, private val plural: String) {
    Year("an", "ans"),
    Month("mois", "mois"),
    Week("semaine", "semaines"),
    Day("jour", "jours"),
    Hour("heure", "heures"),
    Minute("minute", "minutes"),
    Second("seconde", "secondes"),
    ;

    fun phrase(count: Long): String = "$count ${if (count <= 1) singular else plural}"
}

/**
 * « 22 septembre » — un jour qu'on nomme, et non un délai.
 *
 * Les deux cohabitent, et la distinction compte : [relativeDelay] répond à
 * « dans combien de temps » — c'est ce que la feuille « Mon Abonnement »
 * annonce d'une résiliation automatique encore lointaine. Une **date butoir**,
 * elle, répond à « jusqu'à quand », et on la vérifie sur son calendrier :
 * « dans 5 jours » se recompte, « le 22 septembre » se lit.
 *
 * Sans l'année : le mois payé se compte en jours, et personne ne se demande de
 * quelle année on parle.
 */
val Instant.dayAndMonth: String
    get() = dayAndMonth(Locale.getDefault(), ZoneId.systemDefault())

fun Instant.dayAndMonth(locale: Locale, zone: ZoneId): String =
    DateTimeFormatter.ofPattern("d MMMM", locale).format(atZone(zone))

/**
 * « 10/12/2026 - 02/01/2027 », la ligne du voyage en cours dans la carte de
 * chiffres du profil.
 *
 * Des dates **numériques** ici, alors que les cartes de l'accueil écrivent
 * « 26 août – 15 sept. 2026 » : la ligne est courte, poussée à droite d'un
 * intitulé, et deux mois abrégés n'y tiendraient pas.
 */
val CurrentTrip.dateRangeLabel: String?
    get() = numericRangeLabel(from = startDate, to = endDate)

/** « 5 voyages ». Le chiffre de la carte, accordé. */
val TravellerProfile.tripCountLabel: String
    get() = if (tripCount <= 1) "$tripCount voyage" else "$tripCount voyages"
