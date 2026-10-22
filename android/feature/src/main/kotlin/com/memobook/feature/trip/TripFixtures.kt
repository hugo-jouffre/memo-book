package com.memobook.feature.trip

import com.memobook.core.Destination
import com.memobook.core.HomeFeed
import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.TripStep
import com.memobook.core.TripTransport
import com.memobook.feature.home.fixture
import com.memobook.feature.home.fixtureDate
import java.time.Instant
import java.time.ZoneId

// Jeu d'essai de l'accueil d'un voyage — **temporaire**, comme celui de
// l'accueil et du profil. Le jumeau de `TripFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement, `TripDetail.fixture(id)` :
// le voyage de l'accueil qui porte cet identifiant (le voyage de Rome pour un
// identifiant inconnu), ses trois étapes et sa relance.
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une date,
// pas une étape n'est écrite dans une vue. Le jour où l'API rend un
// `TripDetail`, ce fichier disparaît et rien d'autre ne bouge.
//
// Le voyage lui-même est **repris de l'accueil** plutôt que réinventé : ouvrir
// une carte doit mener à ce qu'elle montrait. Seules les étapes, la relance et
// les abonnés sont ajoutés ici, faute d'exister ailleurs.

/**
 * Le voyage d'identifiant donné, tel que l'accueil le connaît, complété de ce
 * que l'API ne sait pas encore rendre.
 */
internal fun TripDetail.Companion.fixture(id: String): TripDetail {
    val trip = HomeFeed.fixture.trips.firstOrNull { it.id == id } ?: fallbackTrip
    return TripDetail(trip = trip, prompt = prompt(trip), steps = steps(trip))
}

/**
 * Un identifiant inconnu ne doit pas donner un écran vide : le carnet de
 * démonstration prend le relais. Cas de figure du jeu d'essai uniquement —
 * l'API, elle, répondra 404 et l'écran affichera son bandeau d'erreur.
 */
private val fallbackTrip: Trip get() = HomeFeed.fixture.trips[0]

/** La relance de MemoBook, posée sur la dernière étape connue. */
private fun prompt(trip: Trip): String? {
    val place = steps(trip).lastOrNull()?.placeName ?: return null
    return "Comment ça se passe à $place ?"
}

/**
 * Quatre étapes, avec des pays et des transports **différents** : sans ça, les
 * trois filtres n'auraient rien à mordre et on ne saurait pas s'ils
 * fonctionnent.
 */
private fun steps(trip: Trip): List<TripStep> {
    // Un voyage qui annonce un pays garde le sien d'un bout à l'autre ; un tour
    // du monde en traverse plusieurs.
    val destination = trip.destination
    val itinerary: List<Pair<String, Destination>> =
        if (destination != null) {
            listOf(
                "Trastevere" to destination,
                "Monti" to destination,
                "Testaccio" to destination,
            )
        } else {
            listOf(
                "Lisbonne" to Destination(name = "Portugal", countryCode = "PT"),
                "Marrakech" to Destination(name = "Maroc", countryCode = "MA"),
                "Hanoï" to Destination(name = "Viêt Nam", countryCode = "VN"),
            )
        }

    val transports = listOf(TripTransport.Plane, TripTransport.Train, TripTransport.Walk)
    val start = trip.startDate ?: fixtureDate(26, 8, 2026)
    val companions = trip.companions.ifEmpty { listOf(com.memobook.core.Companion(id = "c-mila", name = "Mila Fontaine")) }

    return itinerary.mapIndexed { index, (place, stepDestination) ->
        TripStep(
            id = "${trip.id}-step-${index + 1}",
            number = index + 1,
            placeName = place,
            destination = stepDestination,
            startDate = start.adding(days = index * 5),
            endDate = start.adding(days = index * 5 + 4),
            // La première étape est faite avec tout le monde, les suivantes avec
            // une seule personne : la ligne « avec … » doit se voir dans ses
            // deux formes.
            companions = if (index == 0) companions else companions.take(1),
            transport = transports[index % transports.size],
            // La première étape est déjà validée, les autres non : les deux
            // états (coche vs. geste de validation) se voient sans manipuler.
            validatedAt = if (index == 0) start.adding(days = 4) else null,
            // Deux souvenirs par étape — un vocal et ses photos : la croix du
            // tiroir en efface deux (T235).
            entryIds = listOf("${trip.id}-step-${index + 1}-voice", "${trip.id}-step-${index + 1}-photos"),
        )
    }
}

/** Des jours du calendrier grégorien, dans le fuseau de l'appareil — comme sur iOS. */
private fun Instant.adding(days: Int): Instant =
    atZone(ZoneId.systemDefault()).plusDays(days.toLong()).toInstant()
