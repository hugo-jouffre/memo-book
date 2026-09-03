import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Accueil : les carnets en cours.
///
/// Une seule version de cet écran, avec le bouton « + » à une position fixe en
/// haut à droite — la critique design relève que deux variantes coexistaient
/// dans les maquettes, avec un bouton qui se déplaçait d'un écran à l'autre.
public struct MemoListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: MemoListModel?
    @State private var isCreating = false

    public init() {}

    public var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Mes carnets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(MemoBookColor.action)
                .accessibilityLabel("Nouveau carnet")
            }
        }
        .task {
            if model == nil { model = MemoListModel(dependencies: dependencies) }
            await model?.load()
        }
        .sheet(isPresented: $isCreating) {
            if let model {
                NewMemoSheet(model: model)
            }
        }
    }

    @ViewBuilder
    private func content(_ model: MemoListModel) -> some View {
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

            if model.memos.isEmpty && !model.isLoading {
                Section {
                    EmptyStateView(
                        systemImage: "book.closed",
                        title: "Aucun carnet",
                        message: "Crée ton premier carnet, puis raconte tes souvenirs à la voix."
                    )
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(model.memos) { memo in
                NavigationLink(value: memo.id) {
                    MemoRow(memo: memo)
                }
            }
            .onDelete { offsets in
                let targets = offsets.map { model.memos[$0] }
                Task {
                    for memo in targets { await model.delete(memo) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.load() }
        .navigationDestination(for: String.self) { memoId in
            MemoDetailView(memoId: memoId)
        }
    }
}

private struct MemoRow: View {
    let memo: MemoSummary

    private var subtitle: String {
        let souvenirs = memo.entryCount == 1 ? "1 souvenir" : "\(memo.entryCount) souvenirs"
        guard let theme = memo.theme, !theme.isEmpty else { return souvenirs }
        return "\(theme) · \(souvenirs)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            // Serif : c'est un titre de carnet, pas un titre d'écran système.
            Text(memo.title)
                .font(MemoBookFont.bookTitle(19))
                .foregroundStyle(MemoBookColor.ink)

            HStack(spacing: MemoBookSpacing.xs) {
                Text(subtitle)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkSecondary)

                if let render = memo.latestRender {
                    StatusBadge(render.status)
                }
            }
        }
        .padding(.vertical, MemoBookSpacing.xs / 2)
    }
}

/// Création d'un carnet : deux champs, pas un assistant de cinq écrans.
private struct NewMemoSheet: View {
    let model: MemoListModel

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var theme = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") {
                    TextField("Notre tour du monde", text: $title)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Thème") {
                    TextField("Voyage, naissance, projet…", text: $theme)
                        .textInputAutocapitalization(.sentences)
                }
                if let errorMessage = model.errorMessage {
                    Section { ErrorBanner(message: errorMessage) }
                }
            }
            .navigationTitle("Nouveau carnet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        isSaving = true
                        Task {
                            let memo = await model.createMemo(title: title, theme: theme)
                            isSaving = false
                            if memo != nil { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}
