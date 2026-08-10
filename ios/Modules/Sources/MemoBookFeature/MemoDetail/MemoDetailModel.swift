import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
import Observation

@MainActor
@Observable
public final class MemoDetailModel {
    public private(set) var memo: MemoDetail?
    public private(set) var isLoading = false
    public private(set) var isUploading = false
    public private(set) var errorMessage: String?
    public private(set) var permissionDenied = false

    public let recorder = AudioRecorder()

    private let memoId: String
    private let api: any MemoBookAPI
    private var pollingTask: Task<Void, Never>?

    /// Intervalle de rafraîchissement pendant qu'une étape est en cours.
    /// Assez court pour que l'attente reste vivante, assez long pour ne pas
    /// marteler l'API depuis un réseau mobile.
    private static let pollInterval = Duration.seconds(3)

    public init(memoId: String, api: any MemoBookAPI) {
        self.memoId = memoId
        self.api = api
    }

    // MARK: - État dérivé

    public var entries: [Entry] { memo?.entries ?? [] }

    public var latestRender: Render? { memo?.latestRender }

    /// `true` tant qu'une transcription ou une génération est en cours.
    public var hasWorkInProgress: Bool {
        entries.contains { $0.status.isInProgress }
            || (latestRender?.status.isInProgress ?? false)
    }

    public var canGenerate: Bool {
        !entries.isEmpty && !(latestRender?.status.isInProgress ?? false)
    }

    // MARK: - Chargement

    public func load() async {
        isLoading = memo == nil
        defer { isLoading = false }

        do {
            memo = try await api.memo(id: memoId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        updatePolling()
    }

    /// Rafraîchit tant qu'il reste quelque chose à attendre, puis s'arrête.
    /// Sans cet arrêt, un carnet ouvert en arrière-plan interrogerait l'API
    /// indéfiniment.
    private func updatePolling() {
        guard hasWorkInProgress else {
            pollingTask?.cancel()
            pollingTask = nil
            return
        }

        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }

                guard let refreshed = try? await self.api.memo(id: self.memoId) else { continue }
                self.memo = refreshed

                if !self.hasWorkInProgress {
                    self.pollingTask = nil
                    return
                }
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Enregistrement

    public func toggleRecording() async {
        if recorder.isRecording {
            await finishRecording()
        } else {
            await beginRecording()
        }
    }

    private func beginRecording() async {
        do {
            try await recorder.start()
            errorMessage = nil
            permissionDenied = false
        } catch RecordingError.permissionDenied {
            permissionDenied = true
            errorMessage = RecordingError.permissionDenied.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishRecording() async {
        let recorded: RecordedAudio?
        do {
            recorded = try recorder.stop()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let recorded else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            _ = try await api.uploadAudio(
                memoId: memoId,
                data: recorded.data,
                filename: recorded.filename,
                mimeType: recorded.mimeType,
                // La date du souvenir est celle de l'enregistrement, pas celle
                // de l'envoi : c'est elle qui regroupe les entrées par journée,
                // et un upload différé (hors réseau) ne doit pas la fausser.
                capturedAt: recorded.recordedAt,
                placeLabel: nil
            )
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelRecording() {
        recorder.cancel()
    }

    // MARK: - Souvenirs écrits

    public func addNote(_ text: String) async {
        guard let cleaned = text.nilIfBlank else { return }

        do {
            _ = try await api.addTextEntry(
                memoId: memoId,
                entry: NewTextEntry(transcript: cleaned)
            )
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addPhoto(data: Data, filename: String, mimeType: String) async {
        isUploading = true
        defer { isUploading = false }

        do {
            _ = try await api.uploadPhoto(
                memoId: memoId,
                data: data,
                filename: filename,
                mimeType: mimeType,
                capturedAt: .now,
                placeLabel: nil
            )
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Génération

    public func generateBook() async {
        do {
            _ = try await api.startRender(memoId: memoId)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
