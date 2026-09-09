import Foundation
import MemoBookCore

/// Le dernier accueil reçu du serveur, gardé sur le disque.
///
/// **Il existe pour que la boîte d'information ne mente pas.** « Tu peux
/// consulter tes récits » est une promesse : sans copie locale, une app ouverte
/// dans un train affichait un bandeau d'erreur et rien d'autre. C'est le
/// premier cache de l'app, et il arrive à l'endroit que l'architecture avait
/// prévu — « une couche au-dessus de `MemoBookAPI` se justifiera le jour d'un
/// cache local ou d'un mode hors-ligne, pas avant ».
///
/// Il tient dans le dossier **Caches**, et pas ailleurs : c'est une copie de ce
/// que le serveur sait déjà. Si iOS le purge sous pression disque, on le
/// redemande. Les vocaux en attente, eux, ne sont nulle part ailleurs — ils
/// vivent dans `Application Support`, voir ``PendingRecordingStore``.
///
/// ⚠️ **Il se vide à la déconnexion.** Ce sont les voyages de quelqu'un : la
/// personne suivante qui ouvre l'app sur ce téléphone ne doit pas les voir
/// passer, même une demi-seconde.
actor HomeFeedCache {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    init() {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = base.appending(path: "home-feed.json")
    }

    /// Ce qu'on a montré la dernière fois. `nil` si rien n'a encore été reçu,
    /// si iOS a fait le ménage, ou si le fichier date d'un modèle qui a changé
    /// depuis — dans les trois cas, il n'y a rien à réparer, il y a un appel à
    /// refaire.
    func read() -> HomeFeed? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HomeFeed.self, from: data)
    }

    func write(_ feed: HomeFeed) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(feed) else { return }

        // Une écriture ratée n'est pas une erreur d'écran : au pire, il n'y
        // aura rien à relire hors ligne.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
