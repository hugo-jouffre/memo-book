import MemoBookDesign
import SwiftUI

/// Point d'entrée de l'interface. Toute la navigation part d'ici : une seule
/// `NavigationStack`, comme le veut la structure d'une app iOS classique.
public struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    public init() {}

    public var body: some View {
        NavigationStack {
            if dependencies.isReady {
                MemoListView()
            } else if let startupError = dependencies.startupError {
                ContentUnavailableView {
                    Label("Connexion impossible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(startupError)
                } actions: {
                    Button("Réessayer") {
                        Task { await dependencies.prepare() }
                    }
                    .tint(MemoBookColor.action)
                }
            } else {
                ProgressView("Préparation…")
            }
        }
        .tint(MemoBookColor.action)
        .task { await dependencies.prepare() }
    }
}
