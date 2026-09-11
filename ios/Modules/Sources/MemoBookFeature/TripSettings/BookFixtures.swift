import Foundation
import MemoBookCore

// Jeu d'essai du parcours « carnet » — **temporaire**, comme celui du profil.
//
// Les quatre écrans sont entièrement pilotés par ces données : pas un libellé
// de valeur, pas un montant, pas une date n'est écrit dans une vue. Le jour où
// l'API rend ces structures, ce fichier disparaît et rien d'autre ne bouge.
//
// Les valeurs sont celles des maquettes, pour que la comparaison avec Figma
// porte sur le dessin et non sur le contenu.

extension TripSettings {
    public static var fixture: TripSettings {
        TripSettings(
            tripId: "trip-rome",
            name: "Rome 2026",
            // Le même solde que ``TravellerProfile/fixture`` : la cagnotte
            // appartient au compte, les deux écrans lisent la même somme. Les
            // désaccorder ici ferait croire à un bogue quand il n'y en a pas.
            walletBalance: 67.88,
            startDate: Self.day(26, 8, 2026),
            endDate: Self.day(15, 9, 2026),
            narrationPace: .everyTwoDays,
            wantsNotifications: true,
            companions: [
                Companion(id: "clara", name: "@clara_prn"),
                Companion(id: "ana", name: "@ana.prn"),
            ],
            theme: "City trip & découvertes",
            isPublicGallery: false,
            styleSummary: "Pointillés, cadres, etc.",
            isPrintable: true,
            customisation: .fixture
        )
    }

    /// Une date fixe, sans dépendre du jour où l'aperçu tourne : deux captures
    /// prises à un mois d'écart doivent se superposer.
    fileprivate static func day(_ day: Int, _ month: Int, _ year: Int) -> Date {
        Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}

extension BookCustomisation {
    /// Les valeurs de la maquette « Personnalisations du carnet — Mise en
    /// page ». Ce sont aussi les défauts de la base (`memos`, M4) : les deux
    /// disent la même chose, et c'est voulu — un carnet neuf ressemble à ce que
    /// la maquette montre.
    public static var fixture: BookCustomisation {
        BookCustomisation(
            photoTextRatio: 50,
            targetPageCount: 60,
            funFactsEnabled: true,
            rulesEnabled: true,
            decorationQuota: 2,
            fontTitle: "Hansley",
            fontDisplay: "Playfair",
            fontHand: "Gloria Hallelujah",
            fontFacts: "Playfair",
            quizEnabled: true,
            freeZonesEnabled: true,
            crosswordEnabled: true
        )
    }
}

extension Wallet {
    /// La cagnotte de la maquette : cinq contributions, deux natures.
    public static var fixture: Wallet {
        Wallet(
            balance: 65.97,
            entries: [
                WalletEntry(
                    id: "w-1",
                    amount: 10,
                    kind: .gift,
                    label: "Marie D.",
                    date: TripSettings.day(19, 8, 2026)
                ),
                WalletEntry(
                    id: "w-2",
                    amount: 1.99,
                    kind: .topup,
                    label: "Abonnement MB",
                    date: TripSettings.day(18, 8, 2026)
                ),
                WalletEntry(
                    id: "w-3",
                    amount: 1.99,
                    kind: .topup,
                    label: "Abonnement MB",
                    date: TripSettings.day(11, 8, 2026)
                ),
                WalletEntry(
                    id: "w-4",
                    amount: 20,
                    kind: .gift,
                    label: "Bruno Dupont",
                    date: TripSettings.day(15, 8, 2026)
                ),
                WalletEntry(
                    id: "w-5",
                    amount: 30,
                    kind: .gift,
                    label: "Julie et Tom",
                    date: TripSettings.day(8, 8, 2026)
                ),
                WalletEntry(
                    id: "w-6",
                    amount: 1.99,
                    kind: .topup,
                    label: "Abonnement MB",
                    date: TripSettings.day(4, 8, 2026)
                ),
            ],
            tripTitle: "Rome",
            estimate: WalletEstimate(pageCount: 50, cost: 89.90)
        )
    }

    /// La cagnotte qui n'a rien reçu — l'écran « Cagnotte Vide ».
    ///
    /// L'estimation, elle, existe déjà : le carnet se remplit pendant que la
    /// cagnotte reste vide, et c'est justement ce que la barre à zéro raconte.
    public static var emptyFixture: Wallet {
        Wallet(
            balance: 0,
            entries: [],
            tripTitle: "Rome",
            estimate: WalletEstimate(pageCount: 50, cost: 89.90)
        )
    }
}

extension BookPreview {
    /// Le carnet de la maquette, prêt à feuilleter.
    ///
    /// **Sans PDF** : un aperçu n'a pas de document dans un jeu d'essai, et
    /// c'est très bien — c'est l'état « le carnet existe, le fichier n'est pas
    /// encore là » que R11 réclame et que la maquette ne dessine pas.
    public static var fixture: BookPreview {
        BookPreview(
            memoId: "memo-rome",
            title: "Rome et la Dolce Vita",
            status: .ready,
            pageCount: 10,
            tripDate: TripSettings.day(12, 10, 2026),
            excerpt: BookExcerpt(
                quote: "Ce voyage commence bien avant le décollage...",
                detail:
                    "Les ruines dorées du Colisée nous rappellent la grandeur de l’histoire à chaque coin de rue."
            ),
            hasConfiguredCovers: false
        )
    }

    /// Le carnet en train de se composer — l'écran « On compose ton Carnet ».
    public static var composingFixture: BookPreview {
        BookPreview(
            memoId: "memo-rome",
            title: "Rome et la Dolce Vita",
            status: .composing,
            pageCount: 10
        )
    }
}
