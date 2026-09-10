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
    /// L'identifiant du vocal en cours, `nil` si rien ne joue.
    public private(set) var playingId: String?

    /// De 0 à 1 : où en est la lecture. C'est lui que la forme d'onde teinte.
    public private(set) var progress: Double = 0

    public private(set) var elapsed: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    public init() {}

    public func isPlaying(_ id: String) -> Bool { playingId == id }

    /// Joue le vocal, ou l'arrête s'il est déjà en train de jouer.
    ///
    /// Un autre vocal en cours est arrêté sans cérémonie : deux récits qui se
    /// parlent par-dessus ne s'écoutent ni l'un ni l'autre.
    public func toggle(id: String, url: URL) throws {
        if playingId == id {
            stop()
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

        playingId = id
        progress = 0
        elapsed = 0
        startTicking()
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        playingId = nil
        progress = 0
        elapsed = 0

        // On rend la main aux autres apps audio ; un échec ici n'a rien à
        // rattraper, la lecture est déjà terminée.
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Trente fois par seconde : assez fin pour que la forme d'onde se remplisse
    /// sans saccade, assez lâche pour ne pas peser sur le défilement du fil.
    private func startTicking() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, let player = self.player else { return }

                // La fin du vocal se lit ici, faute de délégué `Sendable`.
                guard player.isPlaying else {
                    self.stop()
                    return
                }

                self.elapsed = player.currentTime
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
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
