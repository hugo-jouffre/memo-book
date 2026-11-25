import CoreLocation
import Foundation
import MemoBookCore
import Photos
import PhotosUI
import SwiftUI

/// Une photo choisie, et **ce qu'elle sait d'elle-même**.
///
/// Avant le 20/11/2026, une photo n'arrivait au carnet qu'en octets : ni sa
/// date de prise de vue, ni l'endroit où elle avait été prise. Mesuré sur un
/// vrai carnet, 88 souvenirs sur 108 étaient donc muets, et le lieu d'une
/// étape ne tenait qu'à **un seul** récit (T280).
public struct PickedPhoto: Sendable, Hashable {
    public let data: Data

    /// Sa date de prise de vue. `nil` pour une photo prise à l'instant — le
    /// serveur retombe alors sur la date du tour, ce qui est juste.
    public let capturedAt: Date?

    /// Où elle a été prise, nom lisible — « Kanazawa ». `nil` quand la photo
    /// n'a pas de position, ou que le nom n'a pas pu être trouvé.
    public let placeName: String?

    /// **Elle est passée par une messagerie, et n'a plus de mémoire** (T315).
    ///
    /// Ni date de prise de vue ni position : ce que la photothèque en dit est
    /// le jour où le fichier est arrivé sur le téléphone. ``capturedAt`` ment
    /// donc, et c'est pour ça qu'on demande — voir ``PhotoFilename``.
    public let isForwarded: Bool

    public init(
        data: Data,
        capturedAt: Date? = nil,
        placeName: String? = nil,
        isForwarded: Bool = false
    ) {
        self.data = data
        self.capturedAt = capturedAt
        self.placeName = placeName
        self.isForwarded = isForwarded
    }

    /// La même photo, rangée au jour et à l'endroit que le voyageur vient de
    /// donner (T315). Ce qu'il laisse vide ne remplace rien.
    ///
    /// Le jour est posé à **midi** : une journée prise à minuit bascule à la
    /// veille dès que le serveur la lit en UTC depuis l'est de Greenwich, et
    /// la photo change de page.
    public func placed(day: Date?, place: String?) -> PickedPhoto {
        let trimmed = place?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PickedPhoto(
            data: data,
            capturedAt: day.map(Self.noon(of:)) ?? capturedAt,
            placeName: (trimmed?.isEmpty == false ? trimmed : nil) ?? placeName,
            isForwarded: isForwarded
        )
    }

    static func noon(of day: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}

/// **D'où vient une photo** : sa date, et le nom de l'endroit où elle a été
/// prise.
///
/// ## Un nom, jamais des coordonnées
///
/// La position est lue sur la photo (`PHAsset.location`) et transformée en nom
/// **ici, sur l'appareil**. C'est le choix central de T280 : le carnet reçoit
/// « Kanazawa », jamais 36,56 / 136,65. Rien à stocker de sensible côté
/// serveur, aucun géocodeur à tenir, aucune clé à payer.
///
/// ## Et aucune autorisation de plus
///
/// - `PHAsset` demande la photothèque, que ``PhotoFlow`` réclame **déjà** en
///   `.readWrite` avant d'ouvrir quoi que ce soit ;
/// - `CLGeocoder` n'en demande **aucune** : il traduit une coordonnée qu'on a
///   déjà, il ne va pas chercher où est le téléphone. Le projet n'utilise
///   `CLLocationManager` nulle part, et ce fichier ne l'introduit pas.
///
/// ## Ce qu'il ne sait pas faire
///
/// Le géocodage demande le réseau. Hors ligne, les photos partent **sans
/// lieu** : leur date suffit à les ranger, et un lieu deviné serait pire que
/// pas de lieu. On ne garde pas la coordonnée pour réessayer plus tard — ce
/// serait précisément la donnée qu'on a choisi de ne pas conserver.
actor PhotoOrigin {
    /// Les noms déjà trouvés, par **cellule** d'environ un kilomètre.
    ///
    /// Quatre photos d'une même journée tombent dans la même cellule : c'est
    /// un seul appel au géocodeur au lieu de quatre. Apple le limite en
    /// cadence, et une journée de voyage se photographie par poignées.
    private var byCell: [String: String?] = [:]

    private let geocoder = CLGeocoder()

    /// Deux décimales : environ 1,1 km à l'équateur, moins en remontant. Assez
    /// fin pour distinguer deux villes, assez grossier pour qu'une promenade
    /// ne relance pas le géocodeur à chaque photo.
    private static func cell(of location: CLLocation) -> String {
        let latitude = (location.coordinate.latitude * 100).rounded() / 100
        let longitude = (location.coordinate.longitude * 100).rounded() / 100
        return "\(latitude),\(longitude)"
    }

    /// Le nom de l'endroit, ou `nil` — hors ligne, en pleine mer, ou si le
    /// géocodeur ne rend rien d'utilisable.
    func name(of location: CLLocation) async -> String? {
        let key = Self.cell(of: location)
        if let known = byCell[key] { return known }

        let found: String?
        do {
            let marks = try await geocoder.reverseGeocodeLocation(location)
            found = marks.first.flatMap(Self.readableName)
        } catch {
            // Hors ligne, cadence dépassée, rien trouvé : on ne sait pas, et
            // on ne retient pas l'échec — la photo suivante réessaiera.
            return nil
        }
        byCell[key] = found
        return found
    }

    /// Ce qu'on garde d'un repère, et dans cet ordre.
    ///
    /// La ville d'abord : c'est ce que le carnet imprime en haut d'une étape,
    /// et ce que quelqu'un répondrait à « où étais-tu ? ». Puis ce qui
    /// l'entoure, de plus en plus large — en pleine campagne, `locality` est
    /// vide et l'arrondissement ou la région disent encore quelque chose.
    /// `name` en dernier : il vaut parfois une adresse entière.
    nonisolated static func readableName(_ mark: CLPlacemark) -> String? {
        let candidates = [mark.locality, mark.subAdministrativeArea, mark.administrativeArea, mark.name]
        for candidate in candidates {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

extension PhotoOrigin {
    /// Ce que la photothèque sait d'une photo choisie : sa date, sa position.
    ///
    /// `itemIdentifier` n'est renseigné que si le sélecteur a été ouvert avec
    /// `photoLibrary: .shared()` **et** que l'app a l'accès — les deux sont
    /// vrais ici (voir ``PhotoFlow``). Sinon on ne sait rien, et la photo part
    /// comme avant.
    nonisolated static func asset(of item: PhotosPickerItem) -> PHAsset? {
        guard let id = item.itemIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// **Le nom d'origine du fichier**, celui que la photothèque a reçu —
    /// voir ``MemoBookCore/PhotoFilename`` pour ce qu'il raconte (T315).
    ///
    /// `PHAssetResource` et non `PHAsset` : la fiche n'expose aucun nom, la
    /// ressource oui. La première suffit — une photo en a une, deux avec sa
    /// version retouchée, et les deux portent le même nom d'origine.
    nonisolated static func filename(of asset: PHAsset) -> String? {
        PHAssetResource.assetResources(for: asset).first?.originalFilename
    }

    /// Cette photo a-t-elle perdu sa mémoire en route.
    ///
    /// **Deux conditions, et il faut les deux** : le nom dit la messagerie, et
    /// la photo n'a **aucune position**. Une photo qui a gardé sa position a
    /// gardé ses métadonnées — quel que soit son nom —, et il n'y a alors rien
    /// à demander.
    nonisolated static func isForwarded(_ asset: PHAsset?) -> Bool {
        guard let asset, asset.location == nil, let name = filename(of: asset) else { return false }
        return PhotoFilename.isForwarded(name)
    }

    /// Décrit une série de photos choisies, dans l'ordre du choix.
    ///
    /// Les octets sont déjà chargés par l'appelant : cette fonction ne
    /// s'occupe que de ce qui les entoure.
    static func describe(_ items: [PhotosPickerItem], images: [Data]) async -> [PickedPhoto] {
        let origin = PhotoOrigin()
        var described: [PickedPhoto] = []
        for (index, data) in images.enumerated() {
            let asset = index < items.count ? Self.asset(of: items[index]) : nil
            let place = await asset?.location.asyncFlatMap { await origin.name(of: $0) }
            described.append(
                PickedPhoto(
                    data: data,
                    capturedAt: asset?.creationDate,
                    placeName: place ?? nil,
                    isForwarded: Self.isForwarded(asset)
                )
            )
        }
        return described
    }
}

extension Optional {
    /// `flatMap`, mais pour une transformation qui attend.
    fileprivate func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
