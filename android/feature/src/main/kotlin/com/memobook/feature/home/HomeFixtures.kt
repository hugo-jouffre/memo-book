package com.memobook.feature.home

import com.memobook.core.DailyCredit
import com.memobook.core.Destination
import com.memobook.core.HomeFeed
import com.memobook.core.Showcase
import com.memobook.core.Traveller
import com.memobook.core.Trip
import com.memobook.core.TripProgress
import com.memobook.core.TripStage
import com.memobook.core.TripStats
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import kotlin.random.Random

// Jeu d'essai de l'accueil — **temporaire**. Le jumeau de `HomeFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement :
// - [FixtureTripId], les identifiants fixes des cinq voyages du jeu d'essai ;
// - `HomeFeed.fixture` (cinq voyages : deux en cours, trois passés) et
//   `HomeFeed.emptyFixture` (un compte, aucun voyage) ;
// - [fixtureDate], la date de jeu d'essai partagée avec celui des voyages ;
// - `Trip.debugRandom(stage, index)`, le voyage tiré au sort du panneau d'essai
//   de l'accueil.
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une date,
// pas un compteur n'est écrit dans une vue. Le jour où l'API rend un
// `HomeFeed`, ce fichier disparaît et rien d'autre ne bouge.
//
// Les dates sont figées, pas relatives à aujourd'hui : une maquette qui change
// de texte selon le jour où on la regarde n'est pas comparable à Figma.

/**
 * Les identifiants des voyages du jeu d'essai.
 *
 * ⚠️ **Ce sont de vrais UUID, et c'est indispensable.** `RootView` refuse
 * d'ouvrir un voyage dont l'identifiant n'en est pas un
 * (`RootState.isResourceId`) — le serveur répond 400 à tout le reste, et on ne
 * pousse pas un écran sur une erreur. Avec des identifiants lisibles
 * (« trip-rome »), **aucun voyage du bac à sable ne s'ouvrait** : le raccourci
 * `previewSignedIn` montrait l'accueil et rien derrière, alors qu'il existe
 * précisément pour vérifier ce qu'il y a derrière.
 *
 * Ils sont **fixes**, et les mêmes que sur iOS : deux captures prises à une
 * semaine d'écart doivent se superposer, et un modèle mis de côté par voyage
 * (les couvertures, par exemple) doit se retrouver d'un lancement à l'autre.
 */
internal object FixtureTripId {
    const val rome = "1CE0FEED-0000-4000-A000-000000000001"
    const val tourDuMonde = "1CE0FEED-0000-4000-A000-000000000002"
    const val philippines = "1CE0FEED-0000-4000-A000-000000000003"
    const val colombie = "1CE0FEED-0000-4000-A000-000000000004"
    const val lisbonne = "1CE0FEED-0000-4000-A000-000000000005"
}

/**
 * Une date de jeu d'essai, à midi UTC pour qu'aucun fuseau ne la fasse
 * changer de jour à l'affichage. Partagée avec le jeu d'essai des voyages,
 * qui doit tomber sur les mêmes dates que l'accueil.
 *
 * Le `Date.fixture(_:_:_:)` d'iOS : `Instant` est une classe Java, sans
 * compagnon où poser l'extension.
 */
internal fun fixtureDate(day: Int, month: Int, year: Int): Instant =
    LocalDateTime.of(year, month, day, 12, 0).toInstant(ZoneOffset.UTC)

private val homeFeedFixture = HomeFeed(
    traveller = Traveller(id = "traveller-1", firstName = "Camille"),
    trips = listOf(
        Trip(
            id = FixtureTripId.rome,
            title = "Rome entre frère et sœur",
            destination = Destination(name = "Italie", countryCode = "IT", city = "Rome"),
            stage = TripStage.Ongoing,
            startDate = fixtureDate(26, 8, 2026),
            endDate = fixtureDate(15, 9, 2026),
            stats = TripStats(dayCount = 10, distanceKilometres = 37.0, photoCount = 24),
            companions = listOf(
                com.memobook.core.Companion(id = "c-1", name = "Léa Marchand"),
                com.memobook.core.Companion(id = "c-2", name = "Tom Marchand"),
            ),
            progress = TripProgress(memoryCount = 5, pageCount = 2, targetPageCount = 80),
            // Deux minutes racontées aujourd'hui : il en reste trois, et
            // l'avertissement ne paraît pas tout de suite.
            dailyCredit = DailyCredit(usedMs = 120_000),
        ),
        Trip(
            id = FixtureTripId.tourDuMonde,
            title = "Mon tour du monde",
            stage = TripStage.Ongoing,
            startDate = fixtureDate(2, 6, 2026),
            stats = TripStats(dayCount = 10, distanceKilometres = 37.0, photoCount = 24),
            progress = TripProgress(memoryCount = 12, pageCount = 18, targetPageCount = 60),
            dailyCredit = DailyCredit(),
        ),
        Trip(
            id = FixtureTripId.philippines,
            title = "Philippines avec Claire & Gus",
            destination = Destination(name = "Philippines", countryCode = "PH", city = "Palawan"),
            stage = TripStage.Past,
            startDate = fixtureDate(26, 8, 2025),
            endDate = fixtureDate(15, 9, 2025),
            stats = TripStats(dayCount = 21, distanceKilometres = 412.0, photoCount = 168),
            companions = listOf(
                com.memobook.core.Companion(id = "c-3", name = "Claire Nguyen"),
                com.memobook.core.Companion(id = "c-4", name = "Gustave Pelletier"),
            ),
            isPrintable = true,
        ),
        Trip(
            id = FixtureTripId.colombie,
            title = "Claire et Gus en Colombie",
            destination = Destination(name = "Colombie", countryCode = "CO", city = "Bogotá"),
            stage = TripStage.Past,
            startDate = fixtureDate(3, 2, 2025),
            endDate = fixtureDate(24, 2, 2025),
            stats = TripStats(dayCount = 22, distanceKilometres = 890.0, photoCount = 204),
            isPrintable = true,
            // Le voyage de Claire, rejoint par son code : le tiroir n'y
            // montre pas la croix (T233).
            canDelete = false,
        ),
        Trip(
            id = FixtureTripId.lisbonne,
            title = "Un week-end à Lisbonne",
            destination = Destination(name = "Portugal", countryCode = "PT", city = "Lisbonne"),
            stage = TripStage.Past,
            startDate = fixtureDate(11, 10, 2024),
            endDate = fixtureDate(14, 10, 2024),
            stats = TripStats(dayCount = 4, distanceKilometres = 26.0, photoCount = 61),
            isPrintable = false,
        ),
    ),
    showcase = Showcase(
        title = "Voir des exemples de carnet",
        subtitle = "Découvre à quoi ressemble un carnet MemoBook terminé",
    ),
)

/**
 * Le contenu de la maquette d'accueil.
 *
 * Recopié à chaque lecture, voyages compris : `Trip.dailyCredit` est une
 * variable, et un modèle qui décompterait le crédit d'un voyage du jeu d'essai
 * le décompterait pour tous les écrans — la structure d'iOS, elle, se recopie
 * d'elle-même.
 */
internal val HomeFeed.Companion.fixture: HomeFeed
    get() = homeFeedFixture.copy(trips = homeFeedFixture.trips.map { it.copy() })

private val homeFeedEmptyFixture = HomeFeed(
    traveller = Traveller(id = "traveller-1", firstName = "Camille"),
    trips = emptyList(),
    showcase = homeFeedFixture.showcase,
)

/** Le tout premier lancement : un compte, aucun voyage. */
internal val HomeFeed.Companion.emptyFixture: HomeFeed get() = homeFeedEmptyFixture

// region Bac à sable
//
// Sous `#if DEBUG` sur iOS. Ici, compilé dans les deux builds : seul le
// panneau d'essai de l'accueil s'en sert, et il n'existe qu'en Debug.

/**
 * Un voyage tiré au sort, pour le panneau d'essai de l'accueil.
 *
 * Les destinations viennent d'une petite banque plutôt que d'un générateur :
 * on veut des carnets **plausibles**, avec un drapeau et un titre qui se
 * lisent, pas du lorem ipsum.
 */
internal fun Trip.Companion.debugRandom(stage: TripStage, index: Int): Trip {
    val sample = debugDestinations.random()
    val id = "debug-${stage.rawValue}-$index-${UUID.randomUUID().toString().uppercase().take(4)}"

    // Un voyage à venir commence dans quelques semaines ; un voyage passé
    // s'est terminé il y a quelques mois. C'est ce décalage qui les range dans
    // la bonne section.
    val offset = if (stage == TripStage.Upcoming) Random.nextInt(20, 201) else Random.nextInt(-900, -29)
    val zone = ZoneId.systemDefault()
    val start = Instant.now().atZone(zone).plusDays(offset.toLong()).toInstant()
    val length = Random.nextInt(4, 26)
    val end = start.atZone(zone).plusDays(length.toLong()).toInstant()

    return Trip(
        id = id,
        title = sample.first,
        destination = sample.second,
        stage = stage,
        startDate = start,
        endDate = if (stage == TripStage.Ongoing) null else end,
        stats = TripStats(
            dayCount = length,
            distanceKilometres = Random.nextInt(20, 2_401).toDouble(),
            photoCount = Random.nextInt(5, 321),
        ),
        progress = if (stage == TripStage.Upcoming) {
            null
        } else {
            TripProgress(
                memoryCount = Random.nextInt(1, 41),
                pageCount = Random.nextInt(0, 71),
                targetPageCount = 80,
            )
        },
        isPrintable = stage == TripStage.Past,
    )
}

private val debugDestinations: List<Pair<String, Destination>> = listOf(
    "Road trip en Écosse" to Destination(name = "Écosse", countryCode = "GB", city = "Édimbourg"),
    "Les Lofoten en hiver" to Destination(name = "Norvège", countryCode = "NO", city = "Svolvær"),
    "Kyoto au printemps" to Destination(name = "Japon", countryCode = "JP", city = "Kyoto"),
    "Traversée du Chili" to Destination(name = "Chili", countryCode = "CL", city = "Santiago"),
    "Week-end à Porto" to Destination(name = "Portugal", countryCode = "PT", city = "Porto"),
    "Sur les routes du Kerala" to Destination(name = "Inde", countryCode = "IN", city = "Kochi"),
    "Cap sur l’Islande" to Destination(name = "Islande", countryCode = "IS", city = "Reykjavik"),
)

// endregion
