import MemoBookCore
import MemoBookDesign
import PhotosUI
import SwiftUI

/// L'écran central du cœur produit : je raconte, je vois ce qui a été compris,
/// je génère mon carnet.
public struct MemoDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: MemoDetailModel?
    @State private var noteText = ""
    @State private var isWritingNote = false
    @State private var photoItem: PhotosPickerItem?

    private let memoId: String

    public init(memoId: String) {
        self.memoId = memoId
    }

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.memo?.title ?? "Carnet")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = MemoDetailModel(memoId: memoId, api: dependencies.api) }
            await model?.load()
        }
        .onDisappear { model?.stopPolling() }
    }

    @ViewBuilder
    private func content(_ model: MemoDetailModel) -> some View {
        VStack(spacing: 0) {
            entriesList(model)
            recordingBar(model)
        }
        .background(MemoBookColor.background)
        .sheet(isPresented: $isWritingNote) {
            NoteSheet(text: $noteText) { text in
                Task { await model.addNote(text) }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await model.addPhoto(
                        data: data,
                        filename: "photo-\(UUID().uuidString).jpg",
                        mimeType: "image/jpeg"
                    )
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private func entriesList(_ model: MemoDetailModel) -> some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    ErrorBanner(message: errorMessage) {
                        Task { await model.load() }
                    }
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                BookStatusCard(render: model.latestRender, canGenerate: model.canGenerate) {
                    Task { await model.generateBook() }
                }
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }

            Section("Souvenirs") {
                if model.entries.isEmpty && !model.isLoading {
                    EmptyStateView(
                        systemImage: "waveform",
                        title: "Rien à raconter pour l'instant",
                        message: "Appuie sur le micro et raconte ta journée. Le texte apparaîtra ici."
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(model.entries) { entry in
                    EntryRow(entry: entry)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.load() }
    }

    /// Barre d'action du bas. La critique design relève que la barre des
    /// maquettes cumulait quatre actions : ici le micro est l'action
    /// principale, la note et la photo sont secondaires et visuellement en retrait.
    @ViewBuilder
    private func recordingBar(_ model: MemoDetailModel) -> some View {
        VStack(spacing: MemoBookSpacing.xs) {
            if model.recorder.isRecording {
                RecordingIndicator(
                    level: model.recorder.level,
                    elapsed: model.recorder.elapsed
                )
            }

            HStack {
                Button {
                    isWritingNote = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20))
                        .frame(
                            width: MemoBookSpacing.minimumTapTarget,
                            height: MemoBookSpacing.minimumTapTarget
                        )
                }
                .tint(MemoBookColor.action)
                .accessibilityLabel("Écrire une note")

                Spacer()

                RecordButton(
                    isRecording: model.recorder.isRecording,
                    isBusy: model.isUploading
                ) {
                    Task { await model.toggleRecording() }
                }

                Spacer()

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .frame(
                            width: MemoBookSpacing.minimumTapTarget,
                            height: MemoBookSpacing.minimumTapTarget
                        )
                }
                .tint(MemoBookColor.action)
                .accessibilityLabel("Ajouter une photo")
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
        }
        .padding(.vertical, MemoBookSpacing.s)
        .background(.bar)
    }
}

private struct RecordingIndicator: View {
    let level: Double
    let elapsed: TimeInterval

    private var formattedElapsed: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            // Waveform minimale : douze barres pilotées par le niveau du micro.
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(MemoBookColor.recording)
                        .frame(width: 3, height: barHeight(at: index))
                }
            }
            .frame(height: 24)
            .animation(.easeOut(duration: 0.1), value: level)

            Text(formattedElapsed)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(MemoBookColor.inkSecondary)
                .monospacedDigit()
        }
        .accessibilityLabel("Enregistrement en cours, \(formattedElapsed)")
    }

    private func barHeight(at index: Int) -> CGFloat {
        // Les barres centrales réagissent plus fort que celles des extrémités,
        // ce qui donne la forme de fuseau attendue d'une waveform.
        let distanceFromCenter = abs(Double(index) - 5.5) / 5.5
        let amplitude = level * (1 - distanceFromCenter * 0.6)
        return max(4, CGFloat(amplitude) * 24)
    }
}

private struct EntryRow: View {
    let entry: Entry

    private var icon: String {
        switch entry.kind {
        case .audio: "waveform"
        case .text: "text.alignleft"
        case .photo: "photo"
        }
    }

    private var placeholder: String {
        switch entry.status {
        case .failed: entry.error ?? "La transcription a échoué."
        case .ready where entry.kind == .photo: "Photo ajoutée au carnet"
        default: "Transcription en cours…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            HStack(spacing: MemoBookSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(MemoBookColor.action)
                Text(entry.capturedAt, format: .dateTime.day().month().hour().minute())
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkSecondary)
                Spacer()
                StatusBadge(entry.status)
            }

            if let transcript = entry.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
            } else {
                Text(placeholder)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(
                        entry.status == .failed ? MemoBookColor.error : MemoBookColor.inkSecondary
                    )
            }
        }
        .padding(.vertical, MemoBookSpacing.xs / 2)
    }
}

private struct NoteSheet: View {
    @Binding var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(MemoBookFont.body)
                .padding(MemoBookSpacing.screenMargin)
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            text = ""
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ajouter") {
                            onSave(text)
                            text = ""
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
