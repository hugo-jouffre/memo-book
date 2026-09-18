import Foundation
import MemoBookCore

// Jeu d'essai des couvertures — **temporaire**, comme celui des quatre autres
// écrans du carnet.
//
// ⚠️ **Le contenu est celui du voyage de Rome**, et non celui de la maquette,
// qui raconte les Philippines. C'est le seul endroit où ce fichier s'écarte de
// la règle « les valeurs sont celles des maquettes » — et c'est pour une raison
// qui prime : on arrive sur les couvertures **depuis les réglages de Rome**, et
// ouvrir la couverture d'un carnet appelé « Rome 2026 » sur le mot
// PHILIPPINES se lit comme un bogue, pas comme un jeu d'essai. Le dessin, lui,
// est bien celui de Figma — c'est ce que la comparaison doit porter.

extension BookCovers {
    public static var fixture: BookCovers {
        BookCovers(
            front: BookCover(
                styleId: "front-photo",
                photoId: "photo-2",
                title: "ROME",
                subtitle: "Maylis, Claire et Augustin\nAoût 2026"
            ),
            back: BookCover(
                styleId: "back-framed",
                photoId: "photo-4",
                subtitle:
                    "Quelques jours à la découverte de Rome, entre ruelles baignées de soleil, marchés animés, architecture baroque et longues soirées italiennes.\n\nUn carnet de voyage fait de lieux, de rencontres et de petits moments que l’on aurait aimé ne jamais oublier.",
                statIds: ["stat-days", "stat-km", "stat-countries"]
            ),
            frontStyles: [
                CoverStyle(id: "front-plain", name: "Aplat", treatment: .plain, tint: .slate),
                CoverStyle(id: "front-framed", name: "Cadre", treatment: .framed, tint: .paper),
                CoverStyle(id: "front-photo", name: "Photo pleine page", treatment: .photo, tint: .ink),
                CoverStyle(id: "front-sand", name: "Sable", treatment: .plain, tint: .sand),
                CoverStyle(id: "front-kraft", name: "Kraft", treatment: .kraft, tint: .sand),
                CoverStyle(id: "front-forest", name: "Forêt", treatment: .plain, tint: .forest),
            ],
            backStyles: [
                CoverStyle(id: "back-sand", name: "Sable", treatment: .plain, tint: .sand),
                CoverStyle(id: "back-photo", name: "Photo pleine page", treatment: .photo, tint: .ink),
                // La pastille « Assortie à ta 1ère de couverture » se calcule
                // sur le devant choisi : « Cadre » ici, donc ce plat-là, comme
                // la maquette — et « Sable » si l'on choisit « Sable » devant.
                CoverStyle(id: "back-framed", name: "Cadre", treatment: .framed, tint: .paper),
                CoverStyle(id: "back-forest", name: "Forêt", treatment: .plain, tint: .forest),
                CoverStyle(id: "back-kraft", name: "Kraft", treatment: .kraft, tint: .sand),
            ],
            // Sans URL : un jeu d'essai n'a pas de photothèque. Les plats
            // dessinent alors l'aplat de repli du voyage — le même que les
            // cartes de l'accueil, teinté d'après l'identifiant.
            photos: (1...5).map { CoverPhoto(id: "photo-\($0)") },
            stats: [
                CoverStat(id: "stat-days", value: "21", label: "jours\nde voyage"),
                CoverStat(id: "stat-km", value: "2,3k", label: "km\nparcourus"),
                CoverStat(id: "stat-countries", value: "1", label: "pays\nvisité"),
                CoverStat(id: "stat-steps", value: "14", label: "étapes\nde voyage"),
                CoverStat(id: "stat-stays", value: "6", label: "logements\ndifférents"),
                CoverStat(id: "stat-meals", value: "38", label: "plats\ndécouverts"),
                CoverStat(id: "stat-people", value: "27", label: "personnes\nrencontrées"),
                CoverStat(id: "stat-transport", value: "4", label: "transports\nutilisés"),
            ]
        )
    }
}
