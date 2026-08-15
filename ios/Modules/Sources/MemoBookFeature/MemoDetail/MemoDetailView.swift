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
    @State private var editedEntry: Entry?

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
                    // Une photo n'a pas de texte à relire ; tout le reste
                    // s'ouvre pour correction, y compris un souvenir dont la
                    // rédaction a échoué — c'est justement là qu'on veut
                    // pouvoir reprendre la main.
                    if entry.kind == .photo {
                        EntryRow(entry: entry)
                    } else {
                        Button {
                            editedEntry = entry
                        } label: {
                            EntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .disabled(entry.isProcessing)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.load() }
        .sheet(item: $editedEntry) { entry in
            EntryEditorView(
                entry: entry,
                onSave: { text in
                    Task { await model.saveEditedText(entryId: entry.id, text: text) }
                },
                onRevert: {
                    Task { await model.revertToRedactedText(entryId: entry.id) }
                },
                onRetry: {
                    Task { await model.retryRedaction(entryId: entry.id) }
                }
            )
        }
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

    /// Ce que la ligne dit quand il n'y a pas encore de texte à montrer.
    ///
    /// Les deux étapes sont nommées distinctement : « transcription » puis
    /// « rédaction ». Un seul libellé fourre-tout donnerait l'impression que
    /// l'app est bloquée alors qu'elle avance.
    private var placeholder: String {
        if entry.kind == .photo { return "Photo ajoutée au carnet" }
        if entry.status == .failed { return entry.error ?? "La transcription a échoué." }
        if entry.status.isInProgress { return "Transcription en cours…" }
        if entry.redactionStatus.isInProgress { return "Rédaction en cours…" }
        return "Souvenir sans texte."
    }

    /// Le statut affiché est celui de l'étape en cours. Un souvenir transcrit
    /// mais pas encore rédigé n'est pas « prêt » : son texte va changer.
    private var displayedStatus: Status {
        if entry.kind == .photo || entry.status.isInProgress || entry.status == .failed {
            return entry.status
        }
        return entry.redactionStatus
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
                if entry.isEdited {
                    Label("Corrigé", systemImage: "pencil")
                        .font(MemoBookFont.caption)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(MemoBookColor.inkSecondary)
                        .accessibilityLabel("Corrigé à la main")
                }
                StatusBadge(displayedStatus)
            }

            if let title = entry.suggestedTitle, !title.isEmpty {
                Text(title)
                    .font(MemoBookFont.body.weight(.semibold))
                    .foregroundStyle(MemoBookColor.ink)
            }

            if let text = entry.displayText, !text.isEmpty {
                Text(text)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
                    .lineLimit(4)
            } else {
                Text(placeholder)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(
                        displayedStatus == .failed ? MemoBookColor.error : MemoBookColor.inkSecondary
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
