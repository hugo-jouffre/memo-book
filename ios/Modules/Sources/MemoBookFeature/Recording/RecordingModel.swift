import Foundation
import MemoBookRecording
import Observation

/// Ce que la feuille d'enregistrement sait faire : ouvrir le micro, le
/// suspendre, tout reprendre depuis le début, et rendre le vocal.
///
/// Il tient **deux** choses côte à côte, et l'ordre entre elles n'est pas
/// négociable : l'``AudioRecorder`` d'abord — c'est lui qui obtient le micro et
/// pose la session —, le ``SpeechTranscriber`` ensuite, en second et sans
/// conséquence. Si la reconnaissance vocale ne démarre pas, le vocal se capture
/// quand même : c'est le vocal qui fait le carnet, le texte à l'écran n'est
/// qu'un retour.
@MainActor
@Observable
public final class RecordingModel {
    public let recorder: AudioRecorder
    public let transcriber: SpeechTranscriber

    /// Les niveaux relevés depuis le début, pour la frise. On n'en garde que ce
    /// qui se voit : la frise n'est pas un historique, et une heure de vocal ne
    /// doit pas faire grossir un tableau qu'on ne dessinera jamais.
    public private(set) var levels: [Double] = []

    /// Ce qui a empêché d'enregistrer, dit à l'utilisateur. Le micro refusé,
    /// surtout : c'est le seul cas où il y a quelque chose à faire.
    public private(set) var errorMessage: String?

    /// Un aller-retour est en cours (démarrage, arrêt) : le bouton ne doit pas
    /// être pressé deux fois.
    public private(set) var isBusy = false

    private var sampler: Task<Void, Never>?

    /// Un échantillon toutes les 80 ms. C'est la cadence de la frise, et donc
    /// sa vitesse : plus court, elle défile trop vite pour qu'on suive ; plus
    /// long, elle saute d'une barre à l'autre.
    private static let samplingInterval = Duration.milliseconds(80)

    public init(
        recorder: AudioRecorder = AudioRecorder(),
        transcriber: SpeechTranscriber = SpeechTranscriber()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    public var isRecording: Bool { recorder.isRecording }
    public var isPaused: Bool { recorder.isPaused }
    public var isCapturing: Bool { recorder.isCapturing }
    public var elapsed: TimeInterval { recorder.elapsed }
    public var level: Double { recorder.level }
    public var transcript: String { transcriber.transcript }

    /// Rien n'a encore été enregistré : ni son, ni temps. C'est l'état
    /// d'ouverture de la feuille, et celui où « Recommencer » n'a rien à faire.
    public var isUntouched: Bool { !isRecording && levels.isEmpty }

    /// Le chrono, en `m:ss`. Les minutes ne sont pas complétées à deux
    /// chiffres : la maquette écrit « 0:06 », pas « 00:06 ».
    public var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Les gestes

    /// Le geste du gros bouton : ouvrir le micro, ou refermer.
    public func toggle() async -> RecordedAudio? {
        if isRecording { return finish() }
        await start()
        return nil
    }

    public func start() async {
        guard !isRecording, !isBusy else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            // C'est cet appel qui fait apparaître la demande d'accès au micro.
            try await recorder.start()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        errorMessage = nil
        levels = []
        startSampling()

        // La reconnaissance vocale démarre **après**, et son échec ne remonte
        // pas : elle demande sa propre autorisation, et un refus ne doit pas
        // arrêter un enregistrement qui tourne déjà.
        await transcriber.start()
    }

    public func togglePause() {
        guard isRecording else { return }

        if isPaused {
            recorder.resume()
            startSampling()
            Task { await transcriber.start() }
        } else {
            recorder.pause()
            stopSampling()
            // Le moteur de reconnaissance se referme sur la pause : le laisser
            // ouvert sur du silence le fait expirer tout seul, et on perdrait
            // le texte déjà écrit.
            transcriber.stop()
        }
    }

    /// Tout jeter et repartir de zéro : le vocal en cours, la frise, le texte.
    /// C'est le geste qu'on fait quand on s'est emmêlé dans sa phrase.
    public func restart() async {
        recorder.cancel()
        transcriber.reset()
        stopSampling()
        levels = []
        errorMessage = nil
        await start()
    }

    /// Referme tout et rend le vocal. `nil` si rien n'a été capturé.
    public func finish() -> RecordedAudio? {
        stopSampling()
        transcriber.stop()

        do {
            return try recorder.stop()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// La feuille se referme sans qu'on ait rien validé : on n'invente pas un
    /// souvenir à partir d'un enregistrement abandonné.
    public func discard() {
        stopSampling()
        transcriber.reset()
        recorder.cancel()
        levels = []
    }

    // MARK: - La frise

    private func startSampling() {
        stopSampling()
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.samplingInterval)
                guard let self, self.isCapturing else { return }
                self.levels.append(self.level)
                // On ne garde que ce que la frise peut montrer, plus une
                // poignée de barres d'avance pour que le défilé reste continu.
                if self.levels.count > BrandWaveformCapacity.maximum {
                    self.levels.removeFirst(self.levels.count - BrandWaveformCapacity.maximum)
                }
            }
        }
    }

    private func stopSampling() {
        sampler?.cancel()
        sampler = nil
    }
}

/// Le nombre d'échantillons qu'on garde. Il vit ici et non dans la vue parce
/// que c'est le modèle qui remplit le tableau.
enum BrandWaveformCapacity {
    static let maximum = 40
}
