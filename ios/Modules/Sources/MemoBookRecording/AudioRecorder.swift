import AVFoundation
import Foundation
import Observation

/// Un vocal terminé, prêt à partir vers l'API.
public struct RecordedAudio: Sendable, Hashable {
    public let data: Data
    public let filename: String
    public let mimeType: String
    public let duration: TimeInterval
    public let recordedAt: Date

    /// L'initialiseur est **public** parce que le vocal ne naît plus seulement
    /// du micro : il se relit aussi de la file d'attente, quand il a passé la
    /// nuit sur le disque en attendant le réseau. Voir ``PendingRecordingStore``.
    public init(
        data: Data,
        filename: String,
        mimeType: String,
        duration: TimeInterval,
        recordedAt: Date
    ) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.duration = duration
        self.recordedAt = recordedAt
    }
}

public enum RecordingError: Error, LocalizedError {
    case permissionDenied
    case sessionUnavailable(any Error)
    case recorderUnavailable(any Error)
    case emptyRecording

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "MemoBook a besoin du micro pour enregistrer tes souvenirs. Autorise l'accès dans Réglages."
        case .sessionUnavailable:
            "Le micro est occupé par une autre application."
        case .recorderUnavailable:
            "L'enregistrement n'a pas pu démarrer."
        case .emptyRecording:
            "L'enregistrement est vide, réessaie."
        }
    }
}

/// Capture d'un vocal.
///
/// Confiné au `MainActor` : `AVAudioRecorder` n'est pas `Sendable` et son
/// niveau alimente directement l'interface, donc il n'y a rien à gagner à le
/// faire vivre ailleurs.
@MainActor
@Observable
public final class AudioRecorder {
    /// Un enregistrement est **ouvert** : il tourne, ou il est en pause. Ce
    /// n'est pas la même chose que « le micro capte » — voir ``isCapturing``.
    public private(set) var isRecording = false

    /// L'enregistrement est ouvert mais suspendu. Le fichier est conservé, la
    /// reprise écrit à la suite.
    public private(set) var isPaused = false

    /// Niveau normalisé entre 0 et 1, pour la waveform.
    public private(set) var level: Double = 0

    /// Ce que le **fichier** contient déjà, en secondes, pauses déduites.
    ///
    /// Lu sur `AVAudioRecorder.currentTime`, et non plus à l'horloge murale
    /// (03/10/2026) : le crédit du jour se compte sur ce chiffre pendant qu'on
    /// parle, et le serveur relit la durée dans le fichier. Un appel qui
    /// interrompt la session, un passage en arrière-plan, un enregistreur qui
    /// démarre avec un temps de retard — l'horloge les comptait, le fichier
    /// non, et la barre aurait coupé trop tôt.
    public private(set) var elapsed: TimeInterval = 0

    /// ``elapsed`` en millisecondes — l'unité du crédit du jour.
    public var elapsedMilliseconds: Int { Int((elapsed * 1000).rounded(.down)) }

    /// Le micro capte en ce moment : ni arrêté, ni en pause. C'est ce que
    /// l'interface anime.
    public var isCapturing: Bool { isRecording && !isPaused }

    private var recorder: AVAudioRecorder?

    /// Le jour raconté : l'instant où l'enregistrement s'est ouvert.
    private var openedAt: Date?

    private var meterTask: Task<Void, Never>?
    private var fileURL: URL?

    /// AAC dans un conteneur MPEG-4 : lu tel quel par l'API de transcription,
    /// et bien plus léger qu'un WAV pour l'upload en itinérance.
    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    public init() {}

    public func start() async throws {
        guard !isRecording else { return }
        guard await RecordingPermission.request() else { throw RecordingError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            throw RecordingError.sessionUnavailable(error)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memo-\(UUID().uuidString).m4a")

        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
        } catch {
            throw RecordingError.recorderUnavailable(error)
        }

        fileURL = url
        openedAt = .now
        isRecording = true
        isPaused = false
        elapsed = 0
        startMetering()
    }

    /// Suspend la capture sans rien perdre : le fichier reste ouvert et
    /// ``resume()`` écrit à la suite. C'est le geste du bouton « pause » de la
    /// feuille d'enregistrement — on reprend son souffle, on ne s'arrête pas.
    public func pause() {
        guard isRecording, !isPaused else { return }

        // Le temps du fichier relevé **avant** la pause : c'est lui que la
        // barre affiche pendant qu'elle dure, et la reprise repart de là.
        refreshElapsed()
        recorder?.pause()
        stopMetering()
        isPaused = true
        // Le niveau retombe : une waveform figée à mi-hauteur laisserait croire
        // que le micro entend encore quelque chose.
        level = 0
    }

    public func resume() {
        guard isRecording, isPaused else { return }

        recorder?.record()
        isPaused = false
        startMetering()
    }

    /// Relève le temps du fichier. Seulement pendant que l'enregistreur
    /// tourne : en pause ou arrêté, `currentTime` n'a pas toujours de sens —
    /// on garde alors le dernier relevé, qui ne bouge pas plus que le fichier.
    private func refreshElapsed() {
        guard let recorder, recorder.isRecording else { return }
        elapsed = max(elapsed, recorder.currentTime)
    }

    /// Arrête et renvoie le vocal. `nil` si aucun enregistrement n'était en cours.
    public func stop() throws -> RecordedAudio? {
        guard let recorder, let url = fileURL, let openedAt else { return nil }

        refreshElapsed()
        let duration = elapsed

        recorder.stop()
        stopMetering()

        self.recorder = nil
        fileURL = nil
        self.openedAt = nil
        isRecording = false
        isPaused = false
        level = 0

        // La session est relâchée pour rendre la main aux autres apps audio ;
        // un échec ici n'invalide pas l'enregistrement déjà capturé.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw RecordingError.emptyRecording }

        return RecordedAudio(
            data: data,
            filename: url.lastPathComponent,
            mimeType: "audio/mp4",
            // La durée **du fichier**, pauses déduites : c'est elle que le
            // serveur retrouvera en le relisant.
            duration: duration,
            recordedAt: openedAt
        )
    }

    /// Abandonne l'enregistrement en cours sans rien conserver.
    public func cancel() {
        recorder?.stop()
        stopMetering()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        recorder = nil
        fileURL = nil
        openedAt = nil
        isRecording = false
        isPaused = false
        level = 0
        elapsed = 0
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let recorder = self.recorder else { return }

                recorder.updateMeters()
                self.level = Self.normalize(decibels: recorder.averagePower(forChannel: 0))
                self.refreshElapsed()
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    /// `averagePower` va de -160 dB (silence) à 0 dB (saturation). En dessous de
    /// -50 dB il n'y a rien d'audible : on écrase cette plage pour que la
    /// waveform réagisse à la voix, pas au bruit de fond.
    ///
    /// `nonisolated` : une fonction pure, que ``VoiceLevels`` appelle hors de
    /// l'acteur principal en relisant un fichier.
    nonisolated static func normalize(decibels: Float) -> Double {
        let floor: Float = -50
        guard decibels.isFinite else { return 0 }
        guard decibels > floor else { return 0 }
        return Double(min((decibels - floor) / -floor, 1))
    }
}
