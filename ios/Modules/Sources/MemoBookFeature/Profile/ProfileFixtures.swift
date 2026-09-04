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
        address: PostalAddress(
            street: "7 Rue Simon Fryd",
            postalCode: "69007",
            city: "Lyon",
            country: "France"
        ),
        wantsNewsletter: true,
        walletBalance: 67.88,
        cards: [
            PaymentCard(id: "card-business", label: "Carte business", last4: "3246"),
            PaymentCard(id: "card-perso", label: "Carte perso", last4: "1820"),
        ],
        selectedCardId: "card-perso",
        connectors: Connector.fixtures,
        subscription: Subscription(weeklyPrice: 1.99),
        orders: [
            OrderTracking(
                id: "order-rome",
                minimumDays: 5,
                maximumDays: 7,
                copies: 2,
                pageCount: 50
            )
        ]
    )

    /// Un compte tout neuf : ni adresse, ni carte, ni commande. C'est l'état
    /// que la maquette ne montre pas, et que l'écran doit pourtant tenir.
    public static let emptyFixture = TravellerProfile(
        fullName: "Maylis Garde",
        email: "maylis.garde@icloud.com",
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
        subscription: Subscription(weeklyPrice: 1.99)
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
