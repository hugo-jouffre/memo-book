import AVFoundation
import MemoBookCore
@testable import MemoBookFeature
import MemoBookRecording
import XCTest

/// La forme d'onde d'un vocal arrivé **sans relevé** : relue dans son fichier
/// (Hugo, 30/09/2026 — les vocaux des voyages passés n'avaient plus qu'une
/// ligne plate). Un vrai fichier AAC, fabriqué ici : une seconde de silence,
/// puis une seconde de son.
@MainActor
final class VoiceWaveformTests: XCTestCase {
    /// Une seconde de silence, puis une seconde de la à mi-volume, en AAC —
    /// le format des vocaux de l'app.
    private func voiceFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "voix-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ]
        // Le fichier ne se referme — et ne s'écrit en entier — qu'en quittant
        // ce bloc.
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let format = file.processingFormat
            let rate = format.sampleRate
            let frames = AVAudioFrameCount(rate * 2)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<Int(frames) {
                samples[index] = index < Int(rate)
                    ? 0
                    : 0.5 * sin(2 * .pi * 440 * Float(index) / Float(rate))
            }
            try file.write(from: buffer)
        }
        return url
    }

    func testTheLevelsAreReadBackFromTheFileOnTheMicrophoneScale() async throws {
        let levels = await VoiceLevels.read(from: try voiceFile())

        // Une valeur tous les 90 ms, comme en direct : deux secondes en font
        // vingt-deux, à l'amorce de l'encodeur près.
        XCTAssertGreaterThanOrEqual(levels.count, 20)
        XCTAssertLessThanOrEqual(levels.count, 26)

        let half = levels.count / 2
        let silence = levels[2..<(half - 2)]
        let voice = levels[(half + 2)..<(levels.count - 1)]
        XCTAssertEqual(silence.max() ?? 1, 0, accuracy: 0.05, "Le silence reste au plancher.")
        XCTAssertGreaterThan(voice.min() ?? 0, 0.6, "Le son se lit comme une voix.")
    }

    func testAnUnreadableFileGivesNoLevels() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "rien-\(UUID().uuidString).m4a")
        try Data("pas un son".utf8).write(to: url)

        let levels = await VoiceLevels.read(from: url)
        XCTAssertTrue(levels.isEmpty, "La bulle garde sa ligne plate plutôt qu'une onde inventée.")
    }

    /// Le vocal d'un voyage passé arrive sans niveaux : le fil descend son
    /// fichier — avec la session, par le transport — et dessine sa vraie onde.
    func testAVoiceWithoutLevelsGetsTheWaveformOfItsFile() async throws {
        let audio = try Data(contentsOf: try voiceFile())
        let note = VoiceNote(
            id: "vocal-\(UUID().uuidString)",
            duration: 2,
            remoteUrl: URL(string: "https://api.test/v1/entries/e1/media")
        )
        let thread = ChatThread(
            id: "trip",
            title: "Lisbonne 2024",
            context: ChatContext(tripId: "trip", stepId: nil),
            messages: [ChatMessage(id: note.id, author: .traveller, body: .voice(note), sentAt: .now)],
            suggestions: [],
            now: .now
        )
        let model = ChatModel(
            transport: ChatTransport(
                load: { thread },
                poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
                send: { _ in .queued },
                editTranscript: { _, _ in throw CancellationError() },
                media: { _ in audio }
            )
        )
        await model.load()

        XCTAssertTrue(model.levels(of: note).isEmpty, "Rien à dessiner avant d'avoir lu le fichier.")
        await model.deriveLevelsIfNeeded(for: note)
        XCTAssertGreaterThanOrEqual(model.levels(of: note).count, 20)

        // Un relevé du serveur passe toujours avant : on ne relit pas ce qu'on a.
        let recorded = VoiceNote(id: "relevé", duration: 1, levels: [0.2, 0.8, 0.4])
        XCTAssertEqual(model.levels(of: recorded), [0.2, 0.8, 0.4])
    }
}
