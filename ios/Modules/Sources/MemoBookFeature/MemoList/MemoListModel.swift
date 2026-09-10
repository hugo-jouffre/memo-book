import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// La liste des carnets du compte connecté.
///
/// Elle n'enregistre plus l'appareil avant d'appeler : les carnets appartiennent
/// à un **compte**, et c'est la session qui les ouvre. Attendre un
/// enregistrement d'appareil ici, c'était refuser d'afficher une liste que le
/// serveur aurait très bien servie.
@MainActor
@Observable
public final class MemoListModel {
    public private(set) var memos: [MemoSummary] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let dependencies: AppDependencies
    private var api: any MemoBookAPI { dependencies.api }

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            memos = try await api.memos()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Crée un carnet et le renvoie pour que l'appelant y navigue aussitôt.
    public func createMemo(title: String, theme: String?) async -> Memo? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else {
            errorMessage = "Donne un titre à ton carnet."
            return nil
        }

        do {
            let memo = try await api.createMemo(
                NewMemo(title: cleanedTitle, theme: theme.flatMap(\.nilIfBlank))
            )
            errorMessage = nil
            await load()
            return memo
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func delete(_ memo: MemoSummary) async {
        do {
            try await api.deleteMemo(id: memo.id)
            memos.removeAll { $0.id == memo.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
