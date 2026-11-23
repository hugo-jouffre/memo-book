import Foundation
import MemoBookCore

// Jeu d'essai d'un carnet de la communauté ouvert — **temporaire**, comme celui
// de la galerie.
//
// Il recopie ce que `backend/prisma/seed.ts` pose en base : les deux doivent
// montrer le même écran, sans quoi l'aperçu SwiftUI cesse d'être une référence.
// C'est « Les Cyclades à la voile », le carnet du seed qui porte un récit.

extension PublicBook {
    /// L'adresse d'une photo d'essai, stable pour une clé donnée.
    ///
    /// ⚠️ **Des photographies de remplacement, pas du contenu final.** Elles
    /// existent pour que la mosaïque de la galerie et cet écran se jugent sur de
    /// **vraies images** — un aplat de marque ne dit rien du cadrage, de la
    /// lisibilité du voile sur un ciel blanc, ni de ce que devient un portrait
    /// dans une vignette large (T43). Le même hôte est utilisé par le seed, et
    /// les deux se remplacent le jour où de vrais carnets sont partagés.
    static func samplePhoto(_ seed: String, width: Int = 800, height: Int = 1000) -> URL? {
        URL(string: "https://picsum.photos/seed/\(seed)/\(width)/\(height)")
    }

    /// Le carnet tel qu'on le lit : trois étapes, un récit, des photos.
    public static let fixture = PublicBook(
        id: "gallery-cyclades",
        title: "D'île en île",
        dates: "du 1er au 21 juin 2026",
        summary: "3 semaines · 1 pays",
        coverPhotoUrl: samplePhoto("gallery-cyclades", width: 1200, height: 900),
        destinations: [Destination(name: "Grèce", countryCode: "GR")],
        pageCount: 92,
        // Les dix souvenirs du seed : quatre récits et six photos. Le jeu
        // d'essai recopie la base, chiffres compris — un compteur qui diverge
        // ferait douter du bon écran.
        memoryCount: 10,
        steps: [
            PublicBookStep(
                id: "step-paros",
                number: 1,
                place: "Paros",
                countryCode: "GR",
                dates: "du 1er au 8 juin 2026",
                photoUrl: samplePhoto("cyclades-paros"),
                transport: "boat",
                story: [
                    """
                    Nous sommes arrivés au port de Paros au petit matin, après \
                    une nuit de traversée que personne n'avait vraiment dormie. \
                    Le quai sentait le gasoil et le pain chaud.
                    """,
                    """
                    Le deuxième jour, le vent est tombé d'un coup. On a passé \
                    l'après-midi à l'ancre devant une plage sans nom, à regarder \
                    l'eau ne rien faire.
                    """,
                ],
                photoUrls: [
                    samplePhoto("cyclades-paros-1"),
                    samplePhoto("cyclades-paros-2"),
                    samplePhoto("cyclades-paros-3"),
                ]
                .compactMap { $0 }
            ),
            PublicBookStep(
                id: "step-naxos",
                number: 2,
                place: "Naxos",
                countryCode: "GR",
                dates: "du 8 au 15 juin 2026",
                photoUrl: samplePhoto("cyclades-naxos"),
                transport: "boat",
                story: [
                    """
                    Naxos sentait le thym. On a loué deux scooters pour monter \
                    jusqu'aux villages de l'intérieur, là où la mer disparaît \
                    derrière les oliviers et où plus personne ne parle anglais.
                    """
                ],
                photoUrls: [samplePhoto("cyclades-naxos-1")].compactMap { $0 }
            ),
            PublicBookStep(
                id: "step-amorgos",
                number: 3,
                place: "Amorgos",
                countryCode: "GR",
                dates: "du 15 au 21 juin 2026",
                photoUrl: samplePhoto("cyclades-amorgos"),
                transport: "walk",
                story: [
                    """
                    La dernière île était la plus raide. Le monastère est accroché \
                    à la falaise comme s'il avait été posé là par erreur, et il \
                    faut trois cents marches pour s'en convaincre.
                    """
                ],
                photoUrls: [
                    samplePhoto("cyclades-amorgos-1"),
                    samplePhoto("cyclades-amorgos-2"),
                ]
                .compactMap { $0 }
            ),
        ]
    )

    /// Un carnet partagé dont rien n'est encore rédigé : il a ses étapes, et pas
    /// une ligne. C'est l'état d'un vrai carnet partagé le jour même.
    public static let nothingToReadFixture = PublicBook(
        id: "gallery-kyoto",
        title: "Kyoto au printemps",
        dates: "depuis le 2 avril 2026",
        coverPhotoUrl: samplePhoto("gallery-kyoto", width: 1200, height: 900),
        destinations: [Destination(name: "Japon", countryCode: "JP")],
        steps: [
            PublicBookStep(id: "step-kyoto", number: 1, place: "Kyoto", countryCode: "JP")
        ]
    )
}
