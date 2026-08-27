import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// Les écrans du flow d'entrée dans l'app.
///
/// Le sélecteur en tête de *Sign Up* et de *Login* ne navigue pas : il change
/// l'onglet actif d'un même écran, comme le demande le détail fonctionnel.
public enum OnboardingStep: Hashable, Sendable {
    case splash
    case welcome
    /// `signIn` porte l'onglet actif. `.signUp` à l'arrivée depuis *Welcome*.
    case credentials(AuthTab)
    case forgotPassword
    case forgotPasswordNoAccount(email: String)
    case resetPassword(token: String)
    case completeProfile(SocialProfileDraft)
    /// Le flow est terminé : la liste des carnets prend la main.
    case home
}

public enum AuthTab: Hashable, Sendable {
    case signUp
    case signIn
}

/// Le pilote du flow d'entrée. Il porte l'étape courante, les appels réseau et
/// les erreurs — les vues, elles, ne font que dessiner.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var step: OnboardingStep = .splash

    /// L'erreur de *Login*, affichée en modale — c'est le seul endroit du flow
    /// où le détail fonctionnel en demande une.
    public var signInFailure: SignInFailure?

    /// L'email saisi sur *Login*, transporté jusqu'à *Mot de passe oublié* :
    /// personne ne devrait avoir à le retaper.
    public private(set) var carriedEmail = ""

    private let api: any MemoBookAPI
    private let sessions: any SessionStore

    /// Plancher d'affichage du *Splash*. Sans lui, l'écran clignote sur bon
    /// réseau : 80 ms de logo, c'est pire que pas de logo du tout.
    private let minimumSplashDuration: Duration
    /// Plafond au-delà duquel on cesse d'attendre le réseau et on montre un
    /// écran plutôt que de rester bloqué.
    private let maximumSplashDuration: Duration

    public init(
        api: any MemoBookAPI,
        sessions: any SessionStore,
        minimumSplashDuration: Duration = .milliseconds(800),
        maximumSplashDuration: Duration = .seconds(5)
    ) {
        self.api = api
        self.sessions = sessions
        self.minimumSplashDuration = minimumSplashDuration
        self.maximumSplashDuration = maximumSplashDuration
    }

    /// Une erreur de connexion, telle que la modale de *Login* l'affiche. Le
    /// message reste volontairement générique : dire lequel des deux champs est
    /// faux, c'est confirmer qu'une adresse a un compte.
    public struct SignInFailure: Identifiable, Sendable {
        public let id = UUID()
        public let message = "Une erreur s'est produite lors de votre tentative de connexion"
    }

    // MARK: - Splash

    /// Le routage du lancement, tel que le détail fonctionnel le décrit :
    /// session valide → *Home*, sinon *Welcome* au tout premier lancement, et
    /// *Connection* pour quelqu'un qui a déjà vu l'onboarding.
    public func start() async {
        let startedAt = ContinuousClock.now

        let hasSession = await withTimeout(maximumSplashDuration) { [api] in
            // L'enregistrement de l'appareil ne conditionne pas le routage :
            // une panne réseau ne doit pas coincer quelqu'un devant un logo.
            try? await api.ensureDeviceRegistered()
            return (try? await api.currentAccount()) != nil
        }

        // Le plancher se rattrape après coup : sur bon réseau il reste presque
        // toute son épaisseur, sur mauvais réseau il ne coûte rien.
        let elapsed = ContinuousClock.now - startedAt
        if elapsed < minimumSplashDuration {
            try? await Task.sleep(for: minimumSplashDuration - elapsed)
        }

        if hasSession == true {
            step = .home
        } else {
            step = sessions.hasSeenOnboarding ? .credentials(.signIn) : .welcome
        }
    }

    // MARK: - Navigation

    /// Le CTA « Découvre MemoBook ». Le flag passe à `true` immédiatement : il
    /// ne dépend pas de la suite du parcours.
    public func discoverMemoBook() {
        sessions.markOnboardingSeen()
        step = .credentials(.signUp)
    }

    public func select(tab: AuthTab) {
        step = .credentials(tab)
    }

    public func forgotPassword(email: String) {
        carriedEmail = email
        step = .forgotPassword
    }

    /// Le lien reçu par email. C'est le **seul** chemin vers *Mdp oublié -
    /// config* : l'écran n'est jamais atteignable par navigation directe.
    public func open(deepLink url: URL) -> Bool {
        guard url.scheme == "memobook", url.host == "reset-password" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let token = components?.queryItems?.first(where: { $0.name == "token" })?.value,
            !token.isEmpty
        else { return false }

        step = .resetPassword(token: token)
        return true
    }

    /// Après un mot de passe reconfiguré : retour à *Connection*.
    public func returnToSignIn() {
        step = .credentials(.signIn)
    }

    public func createAccountFromMissingAccount() {
        step = .credentials(.signUp)
    }

    // MARK: - Issues

    /// Ce que font l'inscription, la connexion et la complétion de profil quand
    /// elles réussissent : le flow se termine.
    public func finish(_ session: AuthenticatedSession) {
        if session.hasSeenOnboarding { sessions.markOnboardingSeen() }
        step = .home
    }

    public func requireProfile(_ draft: SocialProfileDraft) {
        step = .completeProfile(draft)
    }

    public func noAccount(for email: String) {
        step = .forgotPasswordNoAccount(email: email)
    }

    public func signInDidFail() {
        signInFailure = SignInFailure()
    }

    // MARK: - Outils

    /// Renvoie `nil` quand le travail n'a pas abouti dans le temps imparti.
    private func withTimeout(
        _ duration: Duration,
        _ work: @escaping @Sendable () async -> Bool
    ) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: duration)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
