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
    /// L'adresse du back-end, lue dans l'`Info.plist` (`MemoBookAPIBaseURL`).
    ///
    /// Elle vit là plutôt qu'en dur dans le code pour une raison précise :
    /// **`localhost` ne marche pas depuis un vrai iPhone.** Sur l'appareil,
    /// `localhost` désigne le téléphone lui-même, pas le Mac qui fait tourner
    /// `npm run dev`. Pour tester sur un appareil, il faut y mettre l'adresse
    /// du Mac sur le réseau local — `http://192.168.1.42:3000`. Une seule
    /// ligne à changer dans `ios/project.yml`, sans toucher au Swift.
    ///
    /// `NSAllowsLocalNetworking` (déjà dans l'`Info.plist`) autorise le HTTP
    /// simple vers ces adresses. Il tombera quand l'API sera derrière HTTPS.
    static var fromBuildConfiguration: APIConfiguration {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "MemoBookAPIBaseURL") as? String,
            let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme != nil
        else {
            return .localDevelopment
        }

        return APIConfiguration(baseURL: url)
    }
}
