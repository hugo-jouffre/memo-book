import Foundation

/// **Le dernier carnet composé, gardé sur le téléphone** (T299, Hugo,
/// 08/11/2026 — « la dernière version est gardée sur le téléphone, donc lisible
/// sans réseau »).
///
/// L'aperçu retéléchargeait son PDF à chaque ouverture. La composition, elle,
/// ne se relançait plus pour rien depuis T224 — l'empreinte du carnet dit si
/// quelque chose a changé —, mais le transfert restait : plusieurs mégaoctets
/// avant la première page, à chaque fois, et rien du tout sans réseau. C'est
/// cette attente-là que le ticket nomme.
///
/// ### Un seul carnet par voyage, et c'est ce qui le borne
///
/// Un voyage n'a qu'un carnet. Le fichier porte donc le voyage, et une
/// composition nouvelle remplace la précédente : le dossier ne grandit pas
/// avec le temps, il grandit avec le nombre de voyages qu'on a ouverts.
///
/// À côté du PDF, une fiche dit **quel rendu** il montre
/// (``Kept/renderId``) et **quand** on l'a reçu. Le premier sert à ne pas
/// retélécharger ce qu'on a déjà — c'est l'économie —, le second à le dire à
/// l'écran quand c'est tout ce qu'on a.
///
/// ### Où ça vit, et pourquoi là
///
/// Dans **Caches**, comme ``ContentCache`` et pour la même raison : c'est une
/// copie de ce que le serveur sait, iOS peut la purger sous pression disque, et
/// on la redemande. La règle de `ios/CLAUDE.md` — « ce qui n'existe nulle part
/// ailleurs va dans `Application Support` » — ne s'applique pas : un carnet
/// composé se recompose, contrairement à un vocal en attente.
///
/// Et ça s'efface à la déconnexion (``clearAll()``, appelé par
/// `AppDependencies.forgetAccountContent()`) : ce sont les voyages de
/// quelqu'un.
actor BookDocumentStore {
    /// Le carnet qu'on avait, et ce qu'on sait de lui.
    struct Kept: Sendable, Equatable {
        let data: Data
        /// Le rendu derrière ce PDF. C'est lui qu'on compare à
        /// `BookPreview.readyRenderId` : égaux, il n'y a rien à retélécharger.
        let renderId: String
        /// Quand ce PDF est arrivé sur l'appareil — la date que l'écran
        /// affiche quand c'est la seule version qu'on peut montrer.
        let keptAt: Date
    }

    /// La fiche posée à côté du PDF.
    private struct Card: Codable {
        let renderId: String
        let keptAt: Date
    }

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init() {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appending(path: "memobook-books", directoryHint: .isDirectory)
    }

    /// Le carnet gardé pour ce voyage. `nil` quand il n'y en a pas, quand iOS a
    /// fait le ménage, ou quand le PDF et sa fiche se sont désolidarisés — dans
    /// les trois cas il n'y a rien à réparer, il y a un appel à faire.
    func kept(for memoId: String) -> Kept? {
        guard let data = try? Data(contentsOf: documentUrl(for: memoId)),
            !data.isEmpty,
            let cardData = try? Data(contentsOf: cardUrl(for: memoId)),
            let card = try? Self.decoder.decode(Card.self, from: cardData)
        else { return nil }

        return Kept(data: data, renderId: card.renderId, keptAt: card.keptAt)
    }

    /// Garde ce PDF comme le carnet de ce voyage, en remplaçant le précédent.
    ///
    /// **Le PDF d'abord, la fiche ensuite** : interrompue entre les deux,
    /// l'écriture laisse un PDF sans fiche, que ``kept(for:)`` refuse — on
    /// retéléchargera. L'ordre inverse laisserait une fiche qui promet un
    /// fichier absent.
    func keep(_ data: Data, renderId: String, for memoId: String, at date: Date = .now) {
        guard !data.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Une écriture ratée n'est pas une erreur d'écran : au pire, la
        // prochaine ouverture retéléchargera.
        guard
            (try? data.write(
                to: documentUrl(for: memoId),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )) != nil,
            let card = try? Self.encoder.encode(Card(renderId: renderId, keptAt: date))
        else { return }

        try? card.write(
            to: cardUrl(for: memoId),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Efface tout. À la déconnexion, et à elle seule.
    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func documentUrl(for memoId: String) -> URL {
        directory.appending(path: "book-\(cacheFilenameDigest(memoId)).pdf")
    }

    private func cardUrl(for memoId: String) -> URL {
        directory.appending(path: "book-\(cacheFilenameDigest(memoId)).json")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
