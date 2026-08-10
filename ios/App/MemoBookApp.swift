import MemoBookFeature
import MemoBookNetworking
import SwiftUI

@main
struct MemoBookApp: App {
    @State private var dependencies = AppDependencies(configuration: .fromBuildConfiguration)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
    }
}

extension APIConfiguration {
    /// En debug, l'app parle au back-end lancé en local (`npm run dev`).
    /// L'URL de production sera injectée ici quand l'API sera déployée.
    static var fromBuildConfiguration: APIConfiguration {
        #if DEBUG
            .localDevelopment
        #else
            .localDevelopment
        #endif
    }
}
