import Foundation
import MemoBookCore

// Jeu d'essai du profil — **temporaire**, comme celui de l'accueil.
//
// L'écran est entièrement piloté par ces données : pas un libellé de valeur,
// pas un montant, pas un connecteur n'est écrit dans une vue. Le jour où l'API
// rend un `TravellerProfile`, ce fichier disparaît et rien d'autre ne bouge.
//
// Les valeurs sont celles de la maquette, pour que la comparaison avec Figma
// porte sur le dessin et non sur le contenu.

extension TravellerProfile {
    public static let fixture = TravellerProfile(
        fullName: "Maylis Garde",
        email: "maylis.garde@icloud.com",
        phoneNumber: "+33 6 98 69 34 48",
        // Ce que le serveur devine sur « Maylis » : c'est ce qui fait écrire
        // « Abonnée » à la feuille, comme la maquette.
        gender: .female,
        address: PostalAddress(
            street: "7 Rue Simon Fryd",
            postalCode: "69007",
            city: "Lyon",
            country: "FR",
            countryName: "France"
        ),
        shippingCountries: ShippingCountry.fixtures,
        wantsNewsletter: true,
        walletBalance: 0,
        cards: [
            PaymentCard(id: "card-business", label: "Carte business", last4: "3246"),
            PaymentCard(id: "card-perso", label: "Carte perso", last4: "1820"),
        ],
        selectedCardId: "card-perso",
        connectors: Connector.fixtures,
        // Abonnée, sur le voyage de la maquette : c'est l'état que montrent la
        // feuille « Mon Abonnement » et les trois feuilles de résiliation. Le
        // compte neuf, lui, n'est pas abonné et ouvre la feuille du mode
        // d'emploi.
        subscription: Subscription(
            weeklyPrice: 1.99,
            isActive: true,
            tripDestination: "Rome",
            tripTitle: "Rome entre amis",
            endsOn: Calendar.current.date(byAdding: .day, value: 21, to: .now),
            // La semaine en cours est réglée jusque dans cinq jours : c'est ce
            // qui fait voir le sursis sur les deux dernières feuilles de
            // résiliation. À zéro, elles retombent sur « l'abonnement s'arrête
            // aujourd'hui », qui est l'autre cas à vérifier.
            paidThrough: Calendar.current.date(byAdding: .day, value: 5, to: .now)
        ),
        orders: [
            OrderTracking(
                id: "order-rome",
                minimumDays: 5,
                maximumDays: 7,
                copies: 2,
                pageCount: 50
            )
        ],
        offeredSteps: 3,
        remainingSteps: 2,
        tripCount: 5,
        currentTrip: CurrentTrip(
            id: "trip-rome",
            startDate: .fixture(10, 12, 2026),
            endDate: .fixture(2, 1, 2027)
        )
    )

    /// Le même profil, mais entré par Apple : l'adresse vient du compte tiers et
    /// ne se corrige pas depuis l'app.
    public static var appleFixture: TravellerProfile {
        var profile = fixture
        profile.signInProvider = .apple
        return profile
    }

    /// Le profil de quelqu'un qui paie : plus de quota d'étapes, la carte de
    /// chiffres ouverte, et la ligne « Mon abonnement » dans les services.
    ///
    /// Le quota repasse à `nil` **et** l'abonnement à actif : les deux ensemble,
    /// parce que c'est ce que le serveur écrit le jour d'une souscription. Un
    /// abonné qui garderait ses étapes offertes n'existe pas.
    public static var subscriberFixture: TravellerProfile {
        var profile = fixture
        profile.subscription.isActive = true
        profile.offeredSteps = nil
        profile.remainingSteps = nil
        return profile
    }

    /// Un compte tout neuf : ni adresse, ni carte, ni commande. C'est l'état
    /// que la maquette ne montre pas, et que l'écran doit pourtant tenir.
    public static let emptyFixture = TravellerProfile(
        fullName: "Maylis Garde",
        email: "maylis.garde@icloud.com",
        // Sans adresse, mais avec la liste : c'est elle qui fait le menu de la
        // feuille, et un compte neuf la reçoit comme les autres.
        shippingCountries: ShippingCountry.fixtures,
        wantsNewsletter: false,
        walletBalance: 0,
        connectors: Connector.fixtures.map {
            Connector(
                id: $0.id,
                name: $0.name,
                promise: $0.promise,
                isEnabled: false,
                logoAssetName: $0.logoAssetName
            )
        },
        // **Ancien abonné, entre deux voyages.** C'est l'état le plus courant
        // après un premier carnet — l'abonnement s'éteint tout seul à la fin du
        // voyage —, et c'est lui qui fait voir le paywall de **retour**, deux
        // écrans au lieu de trois. Le seed pose le même état sur le compte de
        // test gratuit.
        subscription: Subscription(weeklyPrice: 1.99, hasEndedBefore: true)
    )
}

extension Connector {
    /// Les six connecteurs de la maquette, dans son ordre.
    static let fixtures: [Connector] = [
        Connector(
            id: "strava",
            name: "Strava",
            promise:
                "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes runs",
            isEnabled: true,
            logoAssetName: "ConnectorStrava"
        ),
        Connector(
            id: "alltrails",
            name: "All Trails",
            promise:
                "MemoBook pourra récupérer tes sentiers parcourus et t’aider à raconter des souvenirs de tes randonnées",
            isEnabled: true,
            logoAssetName: "ConnectorAllTrails"
        ),
        Connector(
            id: "garmin",
            name: "Garmin",
            promise:
                "MemoBook pourra récupérer tes activités enregistrées et t’aider à situer tes étapes sur le trajet",
            isEnabled: true,
            logoAssetName: "ConnectorGarmin"
        ),
        Connector(
            id: "polarsteps",
            name: "PolarSteps",
            promise:
                "MemoBook pourra récupérer tes récits PolarSteps et t’aider à compléter ton carnet",
            isEnabled: true,
            logoAssetName: "ConnectorPolarSteps"
        ),
        Connector(
            id: "airbnb",
            name: "Airbnb",
            promise:
                "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes réservations",
            isEnabled: true,
            logoAssetName: "ConnectorAirbnb"
        ),
        Connector(
            id: "booking",
            name: "Booking",
            promise:
                "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes réservations",
            isEnabled: true,
            logoAssetName: "ConnectorBooking"
        ),
    ]
}

extension TravelStatistics {
    /// Les chiffres de la maquette, pour que la comparaison porte sur le dessin.
    ///
    /// **Ils ne sont pas cohérents entre eux, et c'est voulu** : 406 personnes
    /// et 2 280 km sont ceux du dessin, pas d'un vrai compte — et le voyage en
    /// cours s'écrit à 9 % pour que l'anneau ait un début d'arc à montrer.
    public static let fixture = TravelStatistics(
        tripCount: 5,
        overall: TravelFigures(
            countries: 6,
            regions: 8,
            cities: 13,
            encounters: 406,
            distanceKilometres: 2280
        ),
        currentTrip: CurrentTripStatistics(
            id: "trip-rome",
            startDate: .fixture(10, 12, 2026),
            endDate: .fixture(2, 1, 2027),
            currentPlace: "Rome",
            dayCount: 21,
            validatedDays: 2,
            figures: TravelFigures(
                countries: 2,
                regions: 4,
                cities: 7,
                encounters: 206,
                distanceKilometres: 1280
            ),
            recordings: 300,
            transports: [
                TransportUsage(kind: .plane, count: 1),
                TransportUsage(kind: .train, count: 2),
                TransportUsage(kind: .scooter),
            ]
        )
    )

    /// Le même compte, pendant que l'agent relit trois souvenirs : c'est
    /// l'état que la feuille annonce d'une ligne et relit toute seule.
    public static var detectingFixture: TravelStatistics {
        var statistics = fixture
        statistics.pendingDetections = 3
        return statistics
    }

    /// Un compte qui n'a pas de voyage en cours : la seconde carte dit qu'il
    /// n'y en a pas, elle ne disparaît pas.
    public static var restingFixture: TravelStatistics {
        var statistics = fixture
        statistics.currentTrip = nil
        return statistics
    }
}
