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
    public private(set) var isRecording = false

    /// La capture est suspendue. `isRecording` reste **vrai** : le vocal
    /// existe, il n'avance simplement plus. C'est ce qui permet à l'interface de
    /// montrer une pause plutôt qu'un retour au repos.
    public private(set) var isPaused = false
    /// Niveau normalisé entre 0 et 1, pour la waveform.
    public private(set) var level: Double = 0
    public private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var meterTask: Task<Void, Never>?
    private var fileURL: URL?

    /// Ce qui a déjà été enregistré avant la pause en cours.
    ///
    /// La durée ne peut plus se lire comme « maintenant moins le début » dès
    /// qu'on a suspendu : ce compteur porte le temps **réellement** capturé, et
    /// `startedAt` ne date plus que la reprise.
    private var recordedBeforePause: TimeInterval = 0

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
        isRecording = true
        isPaused = false
        recordedBeforePause = 0
        elapsed = 0
        startMetering()
    }

    /// Suspend la capture, sans rien perdre.
    ///
    /// `AVAudioRecorder` sait reprendre là où il s'est arrêté — un simple
    /// `record()` suffit — donc rien à recoller à la main. Le compteur de temps,
    /// lui, doit être figé : voir ``recordedBeforePause``.
    public func pause() {
        guard isRecording, !isPaused, let recorder else { return }
        recorder.pause()
        stopMetering()
        recordedBeforePause = capturedDuration
        startedAt = nil
        isPaused = true
        level = 0
    }

    public func resume() {
        guard isRecording, isPaused, let recorder else { return }
        recorder.record()
        startedAt = .now
        isPaused = false
        startMetering()
    }

    /// Le temps réellement capturé : ce qui précède la pause en cours, plus ce
    /// qui court depuis la reprise.
    private var capturedDuration: TimeInterval {
        guard let startedAt else { return recordedBeforePause }
        return recordedBeforePause + Date.now.timeIntervalSince(startedAt)
    }

    /// Arrête et renvoie le vocal. `nil` si aucun enregistrement n'était en cours.
    public func stop() throws -> RecordedAudio? {
        // `startedAt` est nul pendant une pause — c'est `recordedBeforePause`
        // qui porte alors la durée. On ne peut donc pas le déballer ici, mais
        // il faut une date de capture : celle de la reprise, ou celle du début
        // moins ce qui a déjà été enregistré.
        guard let recorder, let url = fileURL, isRecording else { return nil }
        let startedAt = self.startedAt ?? Date.now.addingTimeInterval(-recordedBeforePause)

        recorder.stop()
        stopMetering()

        let duration = capturedDuration

        self.recorder = nil
        fileURL = nil
        self.startedAt = nil
        recordedBeforePause = 0
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
            duration: duration,
            recordedAt: startedAt
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
        recordedBeforePause = 0
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
                self.elapsed = self.capturedDuration
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
