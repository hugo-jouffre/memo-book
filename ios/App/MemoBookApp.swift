import MemoBookDesign
import MemoBookFeature
import MemoBookNetworking
import SwiftUI

@main
struct MemoBookApp: App {
    @State private var dependencies = AppDependencies.forLaunch()

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

extension AppDependencies {
    /// Les dépendances de ce lancement-ci.
    ///
    /// **Le raccourci `-previewSignedIn` reçoit le jeu d'essai**, et pas
    /// seulement un compte inventé. C'est ce que `ios/CLAUDE.md` en promet
    /// depuis le début — « ouvre l'app directement sur l'accueil avec le jeu
    /// d'essai » — et ce qui n'était vrai qu'à moitié : l'app entrait bien, mais
    /// chaque écran derrière appelait le vrai client d'API et tombait sur une
    /// panne de réseau. On regardait un écran d'erreur au lieu de l'écran qu'on
    /// venait vérifier.
    ///
    /// Sans effet en release : ``OnboardingStorage/isPreviewingSignedIn`` y vaut
    /// toujours `false`, et ``PreviewAPI`` n'ouvre de toute façon aucun accès.
    static func forLaunch() -> AppDependencies {
        if OnboardingStorage.isPreviewingSignedIn {
            return AppDependencies.preview()
        }
        return AppDependencies(configuration: .fromBuildConfiguration)
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
    /// **Un iPhone ne parle jamais à `localhost`.** `Debug.xcconfig` ne donne
    /// plus la boucle locale qu'au simulateur, et
    /// ``APIConfiguration/effective(configured:productionFallback:runsInSimulator:)``
    /// remet la production à la place si elle passait quand même — deux
    /// garde-fous, parce que la panne est revenue deux fois (Hugo, 15/09/2026).
    ///
    /// Si les clés manquent, le projet a été construit de travers : dans le
    /// simulateur on repart du back-end local ; sur un appareil, en debug comme
    /// en release, on s'arrête net plutôt que de laisser l'app parler dans le
    /// vide — `localhost` y serait exactement ça.
    static var fromBuildConfiguration: APIConfiguration {
        #if targetEnvironment(simulator)
            let runsInSimulator = true
        #else
            let runsInSimulator = false
        #endif

        if let resolved = APIConfiguration.effective(
            configured: APIConfiguration.fromBundle(),
            productionFallback: APIConfiguration.fromBundle(key: .productionBaseURL),
            runsInSimulator: runsInSimulator
        ) {
            return resolved
        }

        #if DEBUG
            if runsInSimulator { return .localDevelopment }
        #endif
        preconditionFailure(
            "MemoBookAPIBaseURL et MemoBookProductionAPIBaseURL absentes de l'Info.plist : le build ne sait pas à quelle API parler. Voir ios/Config/Base.xcconfig."
        )
    }
}
