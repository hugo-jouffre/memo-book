import AVFoundation
import Foundation
import Observation

/// La lecture à voix haute d'un message.
///
/// C'est le haut-parleur que la maquette pose à côté de chaque bulle de MEMO.
/// Il ne remplace pas VoiceOver et ne lui parle pas : c'est une commande de
/// **confort**, pour écouter ce que MEMO a écrit en gardant les yeux sur la
/// route — et c'est exactement l'usage d'une app de voyage.
///
/// Confiné au `MainActor`, comme les deux autres objets audio du module :
/// `AVSpeechSynthesizer` n'est pas `Sendable`, et son état alimente
/// directement le bouton qui le pilote.
@MainActor
@Observable
public final class SpeechReader {
    /// L'identifiant du message en cours de lecture, `nil` si rien ne parle.
    public private(set) var readingId: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var watcher: Task<Void, Never>?

    public init() {}

    public func isReading(_ id: String) -> Bool { readingId == id }

    /// Lit le texte, ou s'arrête s'il est déjà en train d'être lu.
    ///
    /// La voix suit la langue de l'app et non celle du système : MemoBook parle
    /// français, et un texte français lu par une voix anglaise est
    /// incompréhensible.
    public func toggle(id: String, text: String) {
        if readingId == id {
            stop()
            return
        }

        stop()

        // `.playback` avec `.duckOthers` : la lecture baisse la musique au lieu
        // de la couper, et la rend intacte en s'arrêtant.
        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        synthesizer.speak(utterance)
        readingId = id

        startWatching()
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
        synthesizer.stopSpeaking(at: .immediate)
        readingId = nil
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// La fin de la lecture se lit par sondage, faute de délégué `Sendable` —
    /// même parti pris que ``AudioNotePlayer``. Quatre fois par seconde suffit :
    /// il ne s'agit que d'éteindre un bouton.
    private func startWatching() {
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard self.synthesizer.isSpeaking else {
                    self.stop()
                    return
                }
            }
        }
    }
}
