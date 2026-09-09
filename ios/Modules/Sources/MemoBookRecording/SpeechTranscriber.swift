import AVFoundation
import Foundation
import Observation
import Speech

/// La transcription **en direct** de ce qu'on est en train de dire.
///
/// Elle n'est pas la transcription du carnet : celle-là est faite par le
/// serveur, sur le fichier complet, et c'est elle qui fait foi. Celle-ci est un
/// **retour visuel** — les mots qui s'écrivent pendant qu'on parle, pour qu'on
/// voie que le micro entend. Rien de ce qu'elle produit n'est envoyé nulle part.
///
/// **Elle a le droit de ne pas marcher.** Reconnaissance vocale refusée, langue
/// non installée, moteur indisponible : dans tous ces cas elle se tait et
/// l'enregistrement continue sans elle. Un vocal qui se capture n'a pas à
/// dépendre d'un moteur de texte.
///
/// Elle tourne sur son **propre** `AVAudioEngine`, à côté de l'`AVAudioRecorder`
/// qui écrit le fichier : les deux lisent la même entrée de la session partagée.
/// Faire écrire le fichier par le moteur aurait évité ce doublon, mais aurait
/// aussi mis la capture du vocal — le cœur du produit — dans la dépendance du
/// chemin le plus fragile des deux.
@MainActor
@Observable
public final class SpeechTranscriber {
    /// Ce qui a été reconnu depuis le début de l'enregistrement, segments
    /// terminés et hypothèse en cours réunis.
    public private(set) var transcript = ""

    /// La reconnaissance tourne vraiment. Faux tant qu'elle n'a pas démarré, et
    /// après un échec : l'interface s'en sert pour ne pas réserver la place d'un
    /// texte qui ne viendra jamais.
    public private(set) var isTranscribing = false

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    /// Ce que les segments **déjà figés** ont donné. L'hypothèse en cours s'y
    /// ajoute à l'affichage : le moteur la réécrit à chaque mot, et repartir de
    /// zéro à chaque fois ferait clignoter tout le texte.
    private var settled = ""

    /// La reconnaissance sur l'appareil a échoué et on est repassé par les
    /// serveurs d'Apple. **Une seule fois par enregistrement** : sans ce
    /// drapeau, un moteur qui refuse en boucle relancerait la reconnaissance
    /// indéfiniment.
    private var hasFallenBackToServer = false

    /// - Parameter locale: la langue attendue. L'app ne parle que français —
    ///   voir `CFBundleLocalizations` — donc c'est le défaut, et non la langue
    ///   de l'appareil : quelqu'un dont l'iPhone est en anglais raconte quand
    ///   même ses souvenirs en français.
    public init(locale: Locale = Locale(identifier: "fr-FR")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// L'autorisation de reconnaissance vocale, demandée à part de celle du
    /// micro. iOS pose les deux questions séparément et c'est bien ainsi :
    /// enregistrer sa voix et l'envoyer à un moteur de reconnaissance ne sont
    /// pas le même consentement.
    public static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                // ⚠️ `@Sendable` n'est **pas** décoratif : il fait tomber le
                // crash au premier enregistrement de l'app. Cette classe est
                // `@MainActor`, donc une closure écrite ici hérite de son
                // isolation ; TCC, lui, rappelle depuis sa propre file. Swift 6
                // vérifie l'isolation à l'exécution et arrête le programme
                // (`_dispatch_assert_queue_fail`) au moment où l'utilisateur
                // répond à la demande — accordée comme refusée. Marquée
                // `@Sendable`, la closure n'est plus isolée, et
                // `CheckedContinuation` sait très bien être reprise depuis
                // n'importe quel fil.
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default: return false
        }
    }

    /// Démarre la reconnaissance. Ne lève rien : un échec se traduit par
    /// ``isTranscribing`` à faux, jamais par une erreur montrée à
    /// l'utilisateur — il enregistre, il ne configure pas un moteur.
    ///
    /// À appeler **après** ``AudioRecorder/start()``, qui a déjà posé la
    /// catégorie de session et obtenu le micro.
    public func start() async {
        guard !isTranscribing else { return }
        guard let recognizer else { return }
        // L'autorisation **d'abord** : c'est elle qui pose la question à
        // l'utilisateur, et `isAvailable` ne veut rien dire tant qu'on ne l'a
        // pas. Dans l'autre sens, le moteur se déclarait indisponible et la
        // question n'était jamais posée.
        guard await Self.requestAuthorization() else { return }
        guard recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Les hypothèses partielles **sont** la fonctionnalité : sans elles le
        // texte n'apparaîtrait qu'à la fin, et il n'y aurait rien à regarder
        // pendant qu'on parle.
        request.shouldReportPartialResults = true
        // **Sur l'appareil d'abord** : la voix ne sort pas du téléphone pour un
        // texte qui ne sert qu'à s'afficher. `supportsOnDeviceRecognition` dit
        // que le moteur en est capable, pas que le modèle français est
        // téléchargé — quand il ne l'est pas, la reconnaissance échoue tout de
        // suite et on repasse alors, une fois, par les serveurs d'Apple.
        request.requiresOnDeviceRecognition =
            recognizer.supportsOnDeviceRecognition && !hasFallenBackToServer

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        // ⚠️ **Le garde-fou le plus important du fichier.** `installTap` ne
        // renvoie pas d'erreur quand le format ne correspond pas au matériel :
        // il lève une exception Objective-C, que Swift ne peut pas rattraper —
        // l'app disparaît. Or l'entrée n'est pas toujours prête : la session
        // vient d'être posée par l'enregistreur, ou l'appareil n'a pas de micro.
        // Un format sans canal ni fréquence est le signe qu'il ne faut pas
        // poser la prise. On abandonne alors la transcription, jamais
        // l'enregistrement.
        guard format.channelCount > 0, format.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }

        self.request = request
        settled = ""
        transcript = ""
        isTranscribing = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Le moteur rappelle sur une file à lui ; tout ce qui suit touche à
            // l'état observé par les vues.
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.settled = self.transcript }
                }

                // Une erreur ici, c'est le plus souvent un modèle de langue
                // absent, la fin d'un segment ou une coupure réseau. On range
                // la reconnaissance sans rien dire : le texte déjà écrit reste
                // à l'écran, et l'enregistrement, lui, n'a jamais été menacé.
                if error != nil || result?.isFinal == true {
                    let shouldRetry = error != nil && !self.hasFallenBackToServer
                    self.finish()

                    // Une seule seconde chance, sans le mode hors-ligne : c'est
                    // le cas courant sur un appareil dont le français n'est pas
                    // installé, et il serait dommage de renoncer au texte pour ça.
                    if shouldRetry {
                        self.hasFallenBackToServer = true
                        await self.start()
                    }
                }
            }
        }
    }

    /// Arrête la reconnaissance et garde le texte obtenu.
    public func stop() {
        request?.endAudio()
        finish()
    }

    /// Repart de zéro : plus de texte, plus de moteur.
    public func reset() {
        stop()
        settled = ""
        transcript = ""
        hasFallenBackToServer = false
    }

    private func finish() {
        guard isTranscribing || engine.isRunning else { return }

        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        isTranscribing = false
    }
}
