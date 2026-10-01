import Foundation
import MemoBookRecording
import Observation

/// Ce que la feuille d'enregistrement sait faire : ouvrir le micro, le
/// suspendre, tout reprendre depuis le début, et rendre le vocal.
///
/// Il ne tient plus que l'``AudioRecorder`` — celui-là même que la conversation
/// emploie, et qui n'a jamais fait tomber l'app. Le ``SpeechTranscriber``, qui
/// écrivait les mots à mesure qu'on parlait, **n'est plus branché ici** : c'est
/// lui qui faisait disparaître l'app à l'ouverture de la feuille sur l'iPhone
/// de Hugo (iPhone 13, iOS 18.7.2), et jamais sur le simulateur, où la
/// reconnaissance vocale n'est pas disponible et où il ne démarrait donc pas.
/// Trois verrous posés le 19/09 n'ont pas suffi : `installTap` lève une
/// exception Objective-C que Swift ne rattrape pas, et il reste des formats de
/// matériel qu'on ne sait pas prévoir. Le texte n'était qu'un retour visuel —
/// c'est le vocal qui fait le carnet, et le serveur qui le transcrit (T176).
@MainActor
@Observable
public final class RecordingModel {
    public let recorder: AudioRecorder

    /// Les niveaux relevés depuis le début, pour la frise. On n'en garde que ce
    /// qui se voit : la frise n'est pas un historique, et une heure de vocal ne
    /// doit pas faire grossir un tableau qu'on ne dessinera jamais.
    public private(set) var levels: [Double] = []

    /// Le relevé **entier**, lui, sert à la bulle du vocal une fois qu'il est
    /// dit : c'est la forme d'onde du souvenir, et elle doit dessiner tout ce
    /// qui a été raconté.
    ///
    /// Deux tableaux et non un seul parce qu'ils ne répondent pas à la même
    /// question. ``levels`` dit « qu'est-ce qui passe sous le micro en ce
    /// moment » — les quarante dernières barres, qui défilent. Celui-ci dit
    /// « à quoi ressemble ce vocal » — du premier mot au dernier. Réduire le
    /// second au premier donnerait à un vocal de deux minutes la silhouette de
    /// ses trois dernières secondes.
    public private(set) var capturedLevels: [Double] = []

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

    public init(recorder: AudioRecorder = AudioRecorder()) {
        self.recorder = recorder
    }

    public var isRecording: Bool { recorder.isRecording }
    public var isPaused: Bool { recorder.isPaused }
    public var isCapturing: Bool { recorder.isCapturing }
    public var elapsed: TimeInterval { recorder.elapsed }
    public var level: Double { recorder.level }

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

    /// Le geste du gros bouton : ouvrir le micro, reprendre après une pause,
    /// ou refermer et envoyer.
    ///
    /// **En pause, il reprend.** Il disait « Reprendre » et envoyait le vocal
    /// (Hugo, 29/09/2026) : `isRecording` reste vrai pendant une pause, et le
    /// geste tombait dans « refermer ». La pause se lève d'abord ; envoyer
    /// demande alors un second appui, sur un disque qui dit « Envoyer ».
    public func toggle() async -> RecordedAudio? {
        if isPaused {
            togglePause()
            return nil
        }
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
        capturedLevels = []
        startSampling()
    }

    public func togglePause() {
        guard isRecording else { return }

        if isPaused {
            recorder.resume()
            startSampling()
        } else {
            recorder.pause()
            stopSampling()
        }
    }

    /// Tout jeter et repartir de zéro : le vocal en cours et la frise.
    /// C'est le geste qu'on fait quand on s'est emmêlé dans sa phrase.
    public func restart() async {
        recorder.cancel()
        stopSampling()
        levels = []
        capturedLevels = []
        errorMessage = nil
        await start()
    }

    /// Referme tout et rend le vocal. `nil` si rien n'a été capturé.
    public func finish() -> RecordedAudio? {
        stopSampling()

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
        recorder.cancel()
        levels = []
        capturedLevels = []
    }

    // MARK: - La frise

    private func startSampling() {
        stopSampling()
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.samplingInterval)
                guard let self, self.isCapturing else { return }
                self.levels.append(self.level)
                self.capturedLevels.append(self.level)
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
///
/// **Assez pour remplir la plus large des deux frises.** La feuille
/// d'enregistrement en tient une quarantaine sur un iPhone 17, et davantage sur
/// un Max : en dessous, la frise s'arrêtait avant le bord droit faute
/// d'échantillons à dessiner (Hugo, 19/09/2026). Ce sont des `Double` — en
/// garder soixante-quatre ne coûte rien.
enum BrandWaveformCapacity {
    static let maximum = 64
}
