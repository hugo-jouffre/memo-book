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
    public private(set) var elapsed: TimeInterval = 0

    /// Le micro capte en ce moment : ni arrêté, ni en pause. C'est ce que
    /// l'interface anime.
    public var isCapturing: Bool { isRecording && !isPaused }

    private var recorder: AVAudioRecorder?

    /// Début du **segment** en cours. Une pause le remet à zéro et verse sa
    /// durée dans ``accumulated`` : sans ça, le temps continuait de courir
    /// pendant la pause.
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
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
        startedAt = .now
        openedAt = .now
        accumulated = 0
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

        recorder?.pause()
        stopMetering()
        accumulated += elapsedInCurrentSegment
        startedAt = nil
        isPaused = true
        // Le niveau retombe : une waveform figée à mi-hauteur laisserait croire
        // que le micro entend encore quelque chose.
        level = 0
    }

    public func resume() {
        guard isRecording, isPaused else { return }

        recorder?.record()
        startedAt = .now
        isPaused = false
        startMetering()
    }

    private var elapsedInCurrentSegment: TimeInterval {
        guard let startedAt else { return 0 }
        return Date.now.timeIntervalSince(startedAt)
    }

    /// Arrête et renvoie le vocal. `nil` si aucun enregistrement n'était en cours.
    public func stop() throws -> RecordedAudio? {
        guard let recorder, let url = fileURL, let openedAt else { return nil }

        let duration = accumulated + elapsedInCurrentSegment

        recorder.stop()
        stopMetering()

        self.recorder = nil
        fileURL = nil
        startedAt = nil
        self.openedAt = nil
        accumulated = 0
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
            // La durée **enregistrée**, pauses déduites : c'est celle du
            // fichier, et c'est elle que le serveur retrouvera.
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
        startedAt = nil
        openedAt = nil
        accumulated = 0
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
                self.elapsed = self.accumulated + self.elapsedInCurrentSegment
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
    static func normalize(decibels: Float) -> Double {
        let floor: Float = -50
        guard decibels.isFinite else { return 0 }
        guard decibels > floor else { return 0 }
        return Double(min((decibels - floor) / -floor, 1))
    }
}
