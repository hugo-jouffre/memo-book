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
            // Un voyage **entamé** : 1 min 40 racontée aujourd'hui, il en reste
            // 3 min 20 — la jauge verte au tiers, la ligne d'un non-abonné.
            // C'est l'état de tout le monde, celui qu'il faut voir par défaut ;
            // le panneau de débogage rejoue le neuf, les 30 dernières secondes,
            // l'épuisé et l'abonné. Le crédit se recharge au prochain minuit.
            dailyCredit: DailyCredit(
                usedMs: 100_000,
                resetsAt: Calendar.current.date(
                    byAdding: .day,
                    value: 1,
                    to: Calendar.current.startOfDay(for: .now)
                )
            ),
            startDate: Self.day(26, 8, 2026),
            endDate: Self.day(15, 9, 2026),
            narrationPace: .everyTwoDays,
            wantsNotifications: true,
            // Le propriétaire **est dans la liste** : c'est ce que montre la
            // feuille « Inviter un proche », et c'est ce qui fait lire la liste
            // comme celle du voyage entier. Il en est retiré là où l'on compte
            // les autres — voir ``TripSettings/guests``.
            companions: [
                Companion(id: "margaux", name: "Margaux Dupont", isOwner: true),
                Companion(id: "tom", name: "Tom John", role: "Ton pote d’enfance"),
                // Le troisième n'est jamais entré : c'est lui qui montre
                // l'action « Renvoyer » du glissé.
                Companion(id: "ana", name: "@ana.prn", isPending: true),
            ],
            accessCode: "JHKFDA",
            theme: "City trip & découvertes",
            isPublicGallery: false,
            styleSummary: "Pointillés, cadres, etc.",
            // **Pas de PDF** : un jeu d'essai n'a pas de carnet composé, et c'est
            // très bien — c'est l'état que R11 réclame et que la maquette ne
            // dessine pas. Les feuilles de personnalisation s'ouvrent alors sans
            // les deux pages au-dessus d'elles (voir `BookPagesPeek`). Pour les
            // voir en simulateur, poser ici l'URL d'un PDF de carnet.
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
            fontDisplay: "Playfair Display",
            fontHand: "Gloria Hallelujah",
            fontFacts: "Playfair Display",
            quizEnabled: true,
            freeZonesEnabled: true,
            crosswordEnabled: true
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
