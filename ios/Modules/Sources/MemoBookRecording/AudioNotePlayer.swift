import AVFoundation
import Foundation
import Observation

public enum PlaybackError: Error, LocalizedError {
    case sessionUnavailable(any Error)
    case unreadable(any Error)

    public var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            "Le son est occupé par une autre application."
        case .unreadable:
            "Ce vocal ne peut pas être lu."
        }
    }
}

/// La lecture d'un vocal.
///
/// **Un seul vocal joue à la fois**, et c'est ce qui justifie un objet partagé
/// plutôt qu'un lecteur par bulle : lancer un vocal doit arrêter le précédent,
/// et une centaine de bulles ne doivent pas tenir une centaine de
/// `AVAudioPlayer`. La vue demande donc à ce lecteur *qui* joue
/// (``isPlaying(_:)``) au lieu de tenir son propre état.
///
/// **Pas de délégué.** `AVAudioPlayerDelegate` n'est pas `Sendable`, et sous
/// concurrence stricte l'implémenter proprement demanderait un pont dont on n'a
/// pas besoin : l'avancement est lu par une boucle sur l'acteur principal, comme
/// ``AudioRecorder`` le fait déjà de son niveau de micro. C'est aussi cette
/// boucle qui détecte la fin du vocal.
///
/// Confiné au `MainActor` pour la même raison que l'enregistreur :
/// `AVAudioPlayer` n'est pas `Sendable`, et son avancement alimente directement
/// l'interface.
@MainActor
@Observable
public final class AudioNotePlayer {
    /// Le vocal que le lecteur tient — **en train de jouer ou en pause**.
    /// `nil` quand rien n'est chargé.
    ///
    /// ⚠️ Ce n'est plus « celui qui joue » : une pause le garde (Hugo,
    /// 03/11/2026). C'est ce qui permet à la bulle de rester sur sa position
    /// au lieu de revenir au début.
    public private(set) var loadedId: String?

    /// Le vocal chargé joue vraiment — faux en pause.
    public private(set) var isRunning = false

    /// De 0 à 1 : où en est la lecture. C'est lui que la forme d'onde teinte.
    public private(set) var progress: Double = 0

    public private(set) var elapsed: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    public init() {}

    /// Ce vocal est **en train de jouer** — c'est l'état du bouton, qui montre
    /// alors une pause.
    public func isPlaying(_ id: String) -> Bool { loadedId == id && isRunning }

    /// Ce vocal est celui que le lecteur tient, qu'il joue ou qu'il soit en
    /// pause : c'est lui qui garde sa position, son chrono et sa tête de
    /// lecture.
    public func isLoaded(_ id: String) -> Bool { loadedId == id }

    /// Joue le vocal, le met en pause s'il joue déjà, le reprend s'il est en
    /// pause.
    ///
    /// **La pause garde la position** (Hugo, 03/11/2026, comme WhatsApp) : on
    /// repart d'où on s'est arrêté, pas du début. Un autre vocal en cours est
    /// arrêté sans cérémonie : deux récits qui se parlent par-dessus ne
    /// s'écoutent ni l'un ni l'autre.
    public func toggle(id: String, url: URL) throws {
        if loadedId == id {
            if isRunning { pause() } else { resume() }
            return
        }

        stop()

        let session = AVAudioSession.sharedInstance()
        do {
            // `.playback` et non `.playAndRecord` : l'enregistreur relâche la
            // session en s'arrêtant, et une lecture qui reprendrait sa catégorie
            // sortirait par l'écouteur d'oreille au lieu du haut-parleur.
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            throw PlaybackError.sessionUnavailable(error)
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            throw PlaybackError.unreadable(error)
        }

        loadedId = id
        isRunning = true
        progress = 0
        elapsed = 0
        startTicking()
    }

    /// Suspend la lecture **sans rien perdre** : le lecteur garde le fichier,
    /// la position et le chrono. C'est ce que le bouton play rejoue.
    public func pause() {
        guard let player, isRunning else { return }
        ticker?.cancel()
        ticker = nil
        player.pause()
        isRunning = false
        elapsed = player.currentTime
        progress = fraction(of: player)
    }

    /// Reprend là où la pause a laissé la lecture.
    public func resume() {
        guard let player, !isRunning else { return }
        player.play()
        isRunning = true
        startTicking()
    }

    /// Déplace la tête de lecture, de 0 à 1 — le doigt qui fait glisser le
    /// point sur l'onde (Hugo, 03/11/2026).
    ///
    /// Marche **en pause comme en lecture** : c'est souvent à l'arrêt qu'on
    /// cherche un passage. La position s'écrit tout de suite, sans attendre le
    /// prochain battement, pour que le point suive le doigt sans retard.
    public func seek(to fraction: Double) {
        guard let player else { return }
        let clamped = min(max(fraction, 0), 1)
        player.currentTime = player.duration * clamped
        elapsed = player.currentTime
        progress = clamped
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        loadedId = nil
        isRunning = false
        progress = 0
        elapsed = 0

        // On rend la main aux autres apps audio ; un échec ici n'a rien à
        // rattraper, la lecture est déjà terminée.
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fraction(of player: AVAudioPlayer) -> Double {
        player.duration > 0 ? min(max(player.currentTime / player.duration, 0), 1) : 0
    }

    /// Trente fois par seconde : assez fin pour que la forme d'onde se remplisse
    /// sans saccade, assez lâche pour ne pas peser sur le défilement du fil.
    private func startTicking() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                // ⚠️ L'annulation **sort tout de suite**. Avec un `try?`, le
                // battement qui suivait une pause voyait un lecteur arrêté et
                // appelait `stop()` : la position était perdue, et le vocal
                // repartait du début (Hugo, 03/11/2026).
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard let self, let player = self.player else { return }

                // La fin du vocal se lit ici, faute de délégué `Sendable`.
                guard player.isPlaying else {
                    self.stop()
                    return
                }

                self.elapsed = player.currentTime
                self.progress = self.fraction(of: player)
            }
        }
    }
}

/// Où vivent les vocaux le temps qu'on les réécoute.
///
/// ``AudioRecorder/stop()`` **efface** son fichier temporaire et ne rend que des
/// `Data` : sans cette étape, un vocal qu'on vient d'enregistrer ne serait plus
/// jouable une seconde après. L'écran qui affiche une bulle vocale doit donc
/// écrire l'audio quelque part, et c'est ici.
///
/// Dans les **caches** et non dans les documents : un vocal parti vers le
/// serveur n'a plus à être gardé, et le système peut reprendre la place s'il en
/// manque. C'est aussi ce qui évite de sauvegarder dans iCloud des fichiers qui
/// ne sont que du transit.
public enum VoiceNoteFile {
    private static var directory: URL {
        URL.cachesDirectory.appending(path: "VoiceNotes", directoryHint: .isDirectory)
    }

    /// Le vocal déjà écrit pour cet identifiant, s'il est encore là — iOS vide
    /// les caches sous pression disque. C'est ce qui évite de retélécharger un
    /// vocal à chaque ouverture du fil, pour l'écouter comme pour relire sa
    /// forme d'onde (``VoiceLevels``).
    public static func existing(id: String) -> URL? {
        let url = directory.appending(path: "\(id).m4a")
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }

    /// Écrit le vocal et rend son URL.
    public static func save(_ audio: RecordedAudio, id: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(id).m4a")
        try audio.data.write(to: url, options: .atomic)
        return url
    }

    /// Efface tous les vocaux gardés. À appeler quand une conversation est
    /// close : ce qui compte est parti sur le serveur.
    public static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
