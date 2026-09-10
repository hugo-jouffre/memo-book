import MemoBookDesign
import MemoBookFeature
import MemoBookNetworking
import SwiftUI

@main
struct MemoBookApp: App {
    @State private var dependencies = AppDependencies(configuration: .fromBuildConfiguration)

    init() {
        // Sora et General Sans sont des ressources du module design : c'est du
        // code, pas `UIAppFonts`, qui les déclare à iOS. Voir `BrandFonts`.
        BrandFonts.registerIfNeeded()

        // Avant tout, pour que `RootView` lise des réglages déjà remis à zéro
        // si on le lui a demandé. Sans effet en release.
        OnboardingStorage.resetIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
    }
}

extension APIConfiguration {
    /// L'adresse de l'API, telle que la configuration de build l'a posée :
    /// `Config/Debug.xcconfig` pour le back-end local, `Config/Release.xcconfig`
    /// pour la production, en passant par la clé `MemoBookAPIBaseURL` de
    /// l'Info.plist.
    ///
    /// **Aucune URL n'est écrite dans le code**, et un build Release ne peut
    /// plus retomber en silence sur `localhost` — c'est exactement ce qu'il
    /// faisait avant, et ça n'aurait sauté qu'une fois l'app sur un téléphone.
    ///
    /// Si la clé manque, le projet a été construit de travers : en debug on
    /// repart du back-end local, en release on s'arrête net plutôt que de
    /// laisser une app livrée parler dans le vide.
    static var fromBuildConfiguration: APIConfiguration {
        if let configured = APIConfiguration.fromBundle() { return configured }

        #if DEBUG
            return .localDevelopment
        #else
            preconditionFailure(
                "MemoBookAPIBaseURL absente de l'Info.plist : le build ne sait pas à quelle API parler. Voir ios/Config/Release.xcconfig."
            )
        #endif
    }
}
