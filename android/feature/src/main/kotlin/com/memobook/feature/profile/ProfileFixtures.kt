package com.memobook.feature.profile

import com.memobook.core.AccountNotificationPreferences
import com.memobook.core.AuthProvider
import com.memobook.core.Connector
import com.memobook.core.CurrentTrip
import com.memobook.core.CurrentTripStatistics
import com.memobook.core.Gender
import com.memobook.core.OrderTracking
import com.memobook.core.PaymentCard
import com.memobook.core.PostalAddress
import com.memobook.core.ShippingCountry
import com.memobook.core.Subscription
import com.memobook.core.TransportUsage
import com.memobook.core.TravelFigures
import com.memobook.core.TravelStatistics
import com.memobook.core.TravellerProfile
import com.memobook.feature.home.fixtureDate
import com.memobook.feature.order.fixtures
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId

// Jeu d'essai du profil — **temporaire**, comme celui de l'accueil. Le jumeau
// de `ProfileFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement :
// - `TravellerProfile.fixture` (la maquette : abonnée, deux cartes, deux
//   commandes), et ses variantes `appleFixture`, `subscriberFixture`,
//   `freeFixture` et `emptyFixture` (un compte neuf, ancien abonné) ;
// - `Connector.fixtures`, les six connecteurs de la maquette ;
// - `TravelStatistics.fixture`, `detectingFixture` et `restingFixture`.
//
// L'écran est entièrement piloté par ces données : pas un libellé de valeur,
// pas un montant, pas un connecteur n'est écrit dans une vue. Le jour où l'API
// rend un `TravellerProfile`, ce fichier disparaît et rien d'autre ne bouge.
//
// Les valeurs sont celles de la maquette, pour que la comparaison avec Figma
// porte sur le dessin et non sur le contenu. L'abonnement seul compte à partir
// d'aujourd'hui, comme sur iOS : son sursis doit rester devant soi.

/** Dans `days` jours, à la même heure — le `Calendar.current.date(byAdding:)` d'iOS. */
private fun daysFromNow(days: Long): Instant = Instant.now().atZone(ZoneId.systemDefault()).plusDays(days).toInstant()

private val connectorFixtures = listOf(
    Connector(
        id = "strava",
        name = "Strava",
        promise = "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes runs",
        isEnabled = true,
        logoAssetName = "ConnectorStrava",
    ),
    Connector(
        id = "alltrails",
        name = "AllTrails",
        promise = "MemoBook pourra récupérer tes sentiers parcourus et t’aider à raconter des souvenirs de tes randonnées",
        isEnabled = true,
        logoAssetName = "ConnectorAllTrails",
    ),
    Connector(
        id = "garmin",
        name = "Garmin",
        promise = "MemoBook pourra récupérer tes activités enregistrées et t’aider à situer tes étapes sur le trajet",
        isEnabled = true,
        logoAssetName = "ConnectorGarmin",
    ),
    Connector(
        id = "polarsteps",
        name = "PolarSteps",
        promise = "MemoBook pourra récupérer tes récits Polarsteps et t’aider à compléter ton carnet",
        isEnabled = true,
        logoAssetName = "ConnectorPolarSteps",
    ),
    Connector(
        id = "airbnb",
        name = "Airbnb",
        promise = "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes réservations",
        isEnabled = true,
        logoAssetName = "ConnectorAirbnb",
    ),
    Connector(
        id = "booking",
        name = "Booking",
        promise = "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes réservations",
        isEnabled = true,
        logoAssetName = "ConnectorBooking",
    ),
)

/** Les six connecteurs de la maquette, dans son ordre. */
internal val Connector.Companion.fixtures: List<Connector> get() = connectorFixtures

private val travellerProfileFixture = TravellerProfile(
    fullName = "Maylis Garde",
    email = "maylis.garde@icloud.com",
    phoneNumber = "+33 6 98 69 34 48",
    // Ce que le serveur devine sur « Maylis » : c'est ce qui fait écrire
    // « Abonnée » à la feuille, comme la maquette.
    gender = Gender.Female,
    address = PostalAddress(
        street = "7 Rue Simon Fryd",
        postalCode = "69007",
        city = "Lyon",
        country = "FR",
        countryName = "France",
    ),
    shippingCountries = ShippingCountry.fixtures,
    wantsNewsletter = true,
    // Une coupée sur quatre, comme le seed : la ligne dit « 3 sur 4 » et la
    // feuille montre les deux états (D13, 19/10/2026).
    notifications = AccountNotificationPreferences(birthday = false),
    cards = listOf(
        PaymentCard(id = "card-business", label = "Carte business", last4 = "3246"),
        PaymentCard(id = "card-perso", label = "Carte perso", last4 = "1820"),
    ),
    selectedCardId = "card-perso",
    connectors = Connector.fixtures,
    // Abonnée, sur le voyage de la maquette : c'est l'état que montrent la
    // feuille « Mon Abonnement » et les trois feuilles de résiliation. Le
    // compte neuf, lui, n'est pas abonné : le profil lui propose « Découvrir
    // l'abonnement », qui ouvre le paywall.
    subscription = Subscription(
        price = BigDecimal("4.99"),
        interval = Subscription.Interval.Month,
        isActive = true,
        tripDestination = "Rome",
        tripTitle = "Rome entre amis",
        endsOn = daysFromNow(21),
        // Le mois en cours est réglé jusque dans douze jours : c'est ce qui fait
        // voir le sursis sur les deux dernières feuilles de résiliation. À zéro,
        // elles retombent sur « l'abonnement s'arrête aujourd'hui », qui est
        // l'autre cas à vérifier.
        paidThrough = daysFromNow(12),
    ),
    orders = listOf(
        OrderTracking(
            id = "order-rome",
            minimumDays = 5,
            maximumDays = 7,
            copies = 2,
            pageCount = 50,
        ),
        // Une commande laissée au moment de payer (T232) : son étiquette et
        // « Finaliser ma commande » se vérifient dans le bac à sable.
        OrderTracking(
            id = "order-lisbonne",
            status = OrderTracking.Status.PaymentAbandoned,
            minimumDays = 5,
            maximumDays = 7,
            copies = 1,
            pageCount = 42,
            memoId = "trip-lisbonne",
            tripTitle = "Lisbonne en famille",
            total = BigDecimal("39.9"),
        ),
    ),
    tripCount = 5,
    currentTrip = CurrentTrip(
        id = "trip-rome",
        startDate = fixtureDate(10, 12, 2026),
        endDate = fixtureDate(2, 1, 2027),
    ),
)

internal val TravellerProfile.Companion.fixture: TravellerProfile get() = travellerProfileFixture

/**
 * Le même profil, mais entré par Apple : l'adresse vient du compte tiers et ne
 * se corrige pas depuis l'app.
 */
internal val TravellerProfile.Companion.appleFixture: TravellerProfile
    get() = fixture.copy(signInProvider = AuthProvider.Apple)

/**
 * Le profil de quelqu'un qui paie : la pastille « Abonnée », et la ligne « Mon
 * abonnement » dans les services.
 */
internal val TravellerProfile.Companion.subscriberFixture: TravellerProfile
    get() = fixture.copy(subscription = fixture.subscription.updating(isActive = true))

/**
 * Le même profil, sans abonnement — jamais souscrit : le bouton « Découvrir
 * l'abonnement » et la version de découverte du paywall.
 */
internal val TravellerProfile.Companion.freeFixture: TravellerProfile
    get() = fixture.copy(subscription = Subscription(price = BigDecimal("4.99"), interval = Subscription.Interval.Month))

private val travellerProfileEmptyFixture = TravellerProfile(
    fullName = "Maylis Garde",
    email = "maylis.garde@icloud.com",
    // Sans adresse, mais avec la liste : c'est elle qui fait le menu de la
    // feuille, et un compte neuf la reçoit comme les autres.
    shippingCountries = ShippingCountry.fixtures,
    wantsNewsletter = false,
    connectors = Connector.fixtures.map { it.copy(isEnabled = false) },
    // **Ancien abonné, entre deux voyages.** C'est l'état le plus courant après
    // un premier carnet — l'app propose de résilier à la fin du voyage —, et
    // c'est lui qui fait voir le paywall de **retour**, deux écrans au lieu de
    // trois. Le seed pose le même état sur le compte de test gratuit.
    subscription = Subscription(price = BigDecimal("4.99"), interval = Subscription.Interval.Month, hasEndedBefore = true),
)

/**
 * Un compte tout neuf : ni adresse, ni carte, ni commande. C'est l'état que la
 * maquette ne montre pas, et que l'écran doit pourtant tenir.
 */
internal val TravellerProfile.Companion.emptyFixture: TravellerProfile get() = travellerProfileEmptyFixture

private val travelStatisticsFixture = TravelStatistics(
    tripCount = 5,
    overall = TravelFigures(
        countries = 6,
        regions = 8,
        cities = 13,
        encounters = 406,
        distanceKilometres = 2280,
    ),
    currentTrip = CurrentTripStatistics(
        id = "trip-rome",
        startDate = fixtureDate(10, 12, 2026),
        endDate = fixtureDate(2, 1, 2027),
        currentPlace = "Rome",
        dayCount = 21,
        validatedDays = 2,
        figures = TravelFigures(
            countries = 2,
            regions = 4,
            cities = 7,
            encounters = 206,
            distanceKilometres = 1280,
        ),
        recordings = 300,
        transports = listOf(
            TransportUsage(kind = TransportUsage.Kind.Plane, count = 1),
            TransportUsage(kind = TransportUsage.Kind.Train, count = 2),
            TransportUsage(kind = TransportUsage.Kind.Scooter),
        ),
    ),
)

/**
 * Les chiffres de la maquette, pour que la comparaison porte sur le dessin.
 *
 * **Ils ne sont pas cohérents entre eux, et c'est voulu** : 406 personnes et
 * 2 280 km sont ceux du dessin, pas d'un vrai compte — et le voyage en cours
 * s'écrit à 9 % pour que l'anneau ait un début d'arc à montrer.
 */
internal val TravelStatistics.Companion.fixture: TravelStatistics get() = travelStatisticsFixture

/**
 * Le même compte, pendant que l'agent relit trois souvenirs : c'est l'état que
 * la feuille annonce d'une ligne et relit toute seule.
 */
internal val TravelStatistics.Companion.detectingFixture: TravelStatistics
    get() = fixture.copy(pendingDetections = 3)

/**
 * Un compte qui n'a pas de voyage en cours : la seconde carte dit qu'il n'y en
 * a pas, elle ne disparaît pas.
 */
internal val TravelStatistics.Companion.restingFixture: TravelStatistics
    get() = fixture.copy(currentTrip = null)
