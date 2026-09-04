import Foundation
import MemoBookCore
import MemoBookDesign
import SwiftUI

// Mise en forme des données d'un voyage.
//
// Tout passe par `FormatStyle` plutôt que par des chaînes assemblées à la
// main : c'est ce qui donne « 26 août – 15 sept. 2026 » en français et
// « Aug 26 – Sep 15, 2026 » en anglais, avec l'année écrite une seule fois,
// sans que l'écran ait à connaître une seule règle de langue.

extension Trip {
    /// La ligne de dates sous le titre. `nil` quand le voyage n'a aucune date :
    /// la vue omet alors la ligne plutôt que d'afficher un tiret seul.
    var dateRangeLabel: String? {
        switch (startDate, endDate) {
        case let (start?, end?) where start < end:
            (start..<end).formatted(.interval.day().month(.abbreviated).year())
        case let (start?, _):
            // Un voyage commencé qui n'a pas de fin : c'est le cas courant
            // d'un carnet ouvert, pas une donnée manquante.
            start.formatted(.dateTime.day().month(.abbreviated).year())
        case (nil, let end?):
            end.formatted(.dateTime.day().month(.abbreviated).year())
        case (nil, nil):
            nil
        }
    }
}

extension TripStats {
    /// Les compteurs, dans l'ordre de la maquette. Seuls ceux que le serveur a
    /// renvoyés apparaissent.
    var items: [TripStatItem] {
        var items: [TripStatItem] = []

        if let dayCount {
            items.append(TripStatItem(kind: .duration, text: Self.dayLabel(dayCount)))
        }
        if let distanceKilometres {
            items.append(TripStatItem(kind: .distance, text: Self.distanceLabel(distanceKilometres)))
        }
        if let photoCount {
            items.append(TripStatItem(kind: .photos, text: Self.photoLabel(photoCount)))
        }

        return items
    }

    /// La même chose sur une seule ligne, pour les cartes compactes.
    var inlineSummary: String? {
        let parts = items.map(\.text)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private static func dayLabel(_ count: Int) -> String {
        count <= 1 ? "\(count) jour" : "\(count) jours"
    }

    private static func photoLabel(_ count: Int) -> String {
        count <= 1 ? "\(count) photo" : "\(count) photos"
    }

    /// Le kilomètre est l'unité de stockage, pas l'unité d'affichage : un
    /// utilisateur réglé en impérial lit des miles.
    private static func distanceLabel(_ kilometres: Double) -> String {
        Measurement(value: kilometres, unit: UnitLength.kilometers)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .road,
                    numberFormatStyle: .number.precision(.fractionLength(0))
                )
            )
    }
}

/// Un compteur prêt à afficher : son texte et l'icône qui va avec.
struct TripStatItem: Hashable, Identifiable {
    enum Kind: Hashable {
        case duration
        case distance
        case photos

        /// Le pictogramme du compteur.
        ///
        /// Les photos ont leur icône dans le jeu de marque. La durée et la
        /// distance n'en ont pas — le jeu ne contient ni calendrier ni tracé —
        /// et restent sur un symbole système en attendant. C'est le seul
        /// endroit à changer le jour où les deux manquantes arrivent.
        @ViewBuilder
        var icon: some View {
            switch self {
            case .photos:
                Image(brand: "IconPictureFrame")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            case .duration:
                Image(systemName: "calendar").resizable().scaledToFit()
            case .distance:
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    let kind: Kind
    let text: String

    var id: Kind { kind }
}
