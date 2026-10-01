import AVFoundation
import Foundation

/// La forme d'onde d'un vocal, **relue dans son fichier**.
///
/// Les niveaux se relèvent d'ordinaire pendant l'enregistrement
/// (``AudioRecorder/level``, échantillonné par l'écran). Mais tous les vocaux
/// n'en ont pas : ceux d'avant que le serveur les garde, ceux que la file
/// renvoie sans eux, ceux d'un co-voyageur enregistrés ailleurs. Leur bulle
/// dessinait alors une ligne plate, et on ne voyait plus la voix (Hugo,
/// 30/09/2026). Le fichier, lui, a tout : on le relit.
///
/// **La même échelle que le micro** : une valeur tous les 90 ms, la puissance
/// moyenne de la tranche en décibels, ramenée de 0 à 1 par
/// ``AudioRecorder/normalize(decibels:)``. Une onde relue et une onde relevée
/// en direct se ressemblent donc, et c'est ``BrandWaveform`` qui les ramène à
/// la largeur de la bulle.
public enum VoiceLevels {
    /// L'intervalle de l'échantillonnage en direct, repris ici.
    static let interval: TimeInterval = 0.09

    /// Les niveaux du fichier, lus hors de l'acteur principal. Vide si le
    /// fichier ne se lit pas : la bulle garde alors sa ligne plate.
    public static func read(from url: URL) async -> [Double] {
        await Task.detached(priority: .utility) { measure(url) }.value
    }

    static func measure(_ url: URL) -> [Double] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let window = AVAudioFrameCount(max(1, (format.sampleRate * interval).rounded()))

        // Une tranche à la fois, et non le fichier entier : trois minutes de
        // PCM en flottants pèsent une trentaine de mégaoctets.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window) else { return [] }

        var levels: [Double] = []
        levels.reserveCapacity(Int(file.length / AVAudioFramePosition(window)) + 1)

        while file.framePosition < file.length {
            do {
                try file.read(into: buffer, frameCount: window)
            } catch {
                break
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let samples = buffer.floatChannelData?[0] else { break }

            var energy: Float = 0
            for index in 0..<frames {
                energy += samples[index] * samples[index]
            }
            let rms = (energy / Float(frames)).squareRoot()
            levels.append(AudioRecorder.normalize(decibels: 20 * log10(max(rms, 1e-7))))
        }
        return levels
    }
}
