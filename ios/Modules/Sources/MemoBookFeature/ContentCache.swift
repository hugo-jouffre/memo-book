import Foundation
import MemoBookCore

/// Ce que l'app garde du serveur sur l'appareil, pour rouvrir vite.
///
/// **C'est l'ancien `HomeFeedCache`, devenu générique.** Il n'existait que pour
/// l'accueil, et que pour une raison — tenir la promesse de la boîte
/// d'information hors ligne. Il sert désormais aussi à **ouvrir plus vite** :
/// un écran qui a déjà été vu se dessine avec ce qu'on avait, et se remet à jour
/// quand la réponse arrive (Hugo, 16/09/2026). C'est la même mécanique,
/// employée deux fois.
///
/// ### Ce qu'on garde, et ce qu'on ne garde pas
///
/// La règle est simple : **une copie de ce que le serveur sait, et rien
/// d'autre**. Ce qui n'existe nulle part ailleurs — un vocal en attente — vit
/// dans `Application Support` et n'est pas là (voir `PendingRecordingStore`).
///
/// | Gardé | Pourquoi |
/// |---|---|
/// | l'accueil (``Slot/home``) | le premier écran, et le seul qui doit s'ouvrir sans réseau |
/// | le profil (``Slot/profile``) | son quota, son abonnement et son adresse changent rarement |
/// | un voyage (``Slot/trip``) | on y revient dix fois par jour pendant un voyage |
/// | ses réglages (``Slot/tripSettings``) | trente valeurs pour un écran qu'on ouvre pour en changer une |
/// | la galerie (``Slot/gallery``) | des carnets publics, qui bougent à l'échelle de la semaine |
///
/// Ce qu'on **ne garde pas**, et c'est délibéré : la conversation — elle change
/// à chaque phrase, et un fil périmé se lit comme un message perdu ; la
/// cagnotte et les commandes — c'est de l'argent, et un solde périmé est pire
/// qu'un solde absent ; les rendus PDF — ce sont des fichiers, ils ont leur
/// propre cache d'URL.
///
/// ### Où ça vit
///
/// Dans **Caches**, jamais ailleurs : c'est une copie, iOS peut la purger sous
/// pression disque, et on la redemande. Et ça s'efface à la déconnexion — ce
/// sont les voyages de quelqu'un, la personne suivante ne doit pas les voir
/// passer, même une demi-seconde (``clearAll()``).
actor ContentCache {
    /// Ce qu'on range, et sous quel nom de fichier.
    ///
    /// Une énumération et non une chaîne libre : deux écrans qui écriraient
    /// sous la même clé se recouvriraient l'un l'autre, et le compilateur ne
    /// dirait rien.
    enum Slot: Hashable {
        case home
        case profile
        case statistics
        case gallery
        case trip(String)
        case tripSettings(String)

        /// Le nom du fichier. L'identifiant du voyage y entre **haché** plutôt
        /// qu'en clair : un UUID est un nom de fichier valide, mais on ne pose
        /// pas d'identifiants de ressources dans l'arborescence d'un appareil.
        var filename: String {
            switch self {
            case .home: "home.json"
            case .profile: "profile.json"
            case .statistics: "statistics.json"
            case .gallery: "gallery.json"
            case .trip(let id): "trip-\(Self.digest(id)).json"
            case .tripSettings(let id): "trip-settings-\(Self.digest(id)).json"
            }
        }

        private static func digest(_ value: String) -> String {
            // `hashValue` change d'un lancement à l'autre (il est salé) : on
            // veut une empreinte **stable**, sinon le cache d'hier ne se relit
            // jamais. Une somme simple suffit — il ne s'agit pas de sécurité,
            // seulement de ne pas écrire un identifiant en clair.
            var hash: UInt64 = 5381
            for byte in value.utf8 { hash = hash &* 33 &+ UInt64(byte) }
            return String(hash, radix: 36)
        }
    }

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init() {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appending(path: "memobook-content", directoryHint: .isDirectory)
    }

    /// Ce qu'on avait. `nil` quand il n'y a rien, quand iOS a fait le ménage, ou
    /// quand le fichier date d'un modèle qui a changé depuis — dans les trois
    /// cas, il n'y a rien à réparer, il y a un appel à faire.
    func read<Value: Decodable & Sendable>(_ slot: Slot, as type: Value.Type) -> Value? {
        guard let data = try? Data(contentsOf: url(for: slot)) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    func write(_ slot: Slot, _ value: some Encodable & Sendable) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Une écriture ratée n'est pas une erreur d'écran : au pire, il n'y
        // aura rien à relire au prochain lancement.
        try? data.write(
            to: url(for: slot),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Efface tout. À la déconnexion, et à elle seule.
    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(for slot: Slot) -> URL {
        directory.appending(path: slot.filename)
    }
}
