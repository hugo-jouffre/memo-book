import Foundation
import MemoBookNetworking
import Observation

/// Les dépendances que les écrans partagent. Un seul point d'assemblage :
/// l'app en construit une instance réelle, les aperçus SwiftUI une simulée.
@MainActor
@Observable
public final class AppDependencies {
    public let api: any MemoBookAPI

    /// Ce que l'app retient d'une session : le jeton, et le fait d'avoir déjà
    /// vu le Welcome Screen.
    public let sessions: any SessionStore

    /// Le pilote du flow d'entrée. Il vit ici parce qu'il survit à tous les
    /// écrans : c'est lui qui décide, au lancement, s'il faut montrer le
    /// Welcome, la connexion, ou passer directement aux carnets.
    public let onboarding: OnboardingModel

    /// Ce qui parle aux SDK Apple, Google et Facebook. Aucun n'est encore
    /// intégré : par défaut, les trois boutons disent qu'ils ne sont pas
    /// disponibles plutôt que d'échouer en silence.
    public let social: any SocialSignInBroker

    public init(
        api: any MemoBookAPI,
        sessions: any SessionStore,
        social: any SocialSignInBroker = UnwiredSocialSignInBroker()
    ) {
        self.api = api
        self.sessions = sessions
        self.social = social
        self.onboarding = OnboardingModel(api: api, sessions: sessions)
    }

    public convenience init(configuration: APIConfiguration = .localDevelopment) {
        let sessions = KeychainSessionStore()
        self.init(
            api: MemoBookAPIClient(configuration: configuration, sessionStore: sessions),
            sessions: sessions
        )
    }

    /// Ferme la session et renvoie sur l'écran de connexion.
    public func signOut() async {
        await api.signOut()
        onboarding.returnToSignIn()
    }
}
