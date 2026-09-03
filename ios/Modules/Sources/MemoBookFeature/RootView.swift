import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Point d'entrée de l'interface, et le seul endroit qui décide de l'étape où
/// se trouve l'utilisateur : accueil au tout premier lancement, puis entrée
/// dans le compte, puis l'app.
///
/// Rien n'est mis derrière un écran d'attente réseau : les erreurs
/// appartiennent à l'écran qui fait l'appel — voir ``AppDependencies``.
///
/// La seule exception est la **restauration de session** : elle décide de
/// l'écran à montrer, donc elle doit répondre avant qu'on montre quoi que ce
/// soit. Elle est bornée par le délai du client d'API, et son échec ouvre
/// simplement l'écran d'entrée plutôt qu'un mur d'erreur.
public struct RootView: View {
    /// L'écran d'accueil ne se montre qu'au premier lancement.
    @AppStorage(OnboardingStorage.hasSeenWelcome) private var hasSeenWelcome = false

    @Environment(AppDependencies.self) private var dependencies
    @State private var stage: Stage = .restoring

    private enum Stage: Equatable {
        /// On regarde si la session gardée au trousseau vaut encore quelque chose.
        case restoring
        case signedOut
        case signedIn(Account)
    }

    public init() {}

    public var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView { hasSeenWelcome = true }
            } else {
                switch stage {
                case .restoring:
                    restoring
                case .signedOut:
                    AuthView { stage = .signedIn($0) }
                case .signedIn:
                    NavigationStack {
                        MemoListView()
                    }
                    .tint(MemoBookColor.action)
                }
            }
        }
        .animation(.snappy, value: hasSeenWelcome)
        .animation(.snappy, value: stage)
        .task { await restore() }
    }

    /// Volontairement muet : sans jeton en trousseau, la décision est immédiate
    /// et cet écran n'apparaît pas. Avec un jeton, il dure le temps d'un
    /// aller-retour — y afficher « Connexion… » ferait clignoter un mot.
    private var restoring: some View {
        Color.clear
            .background(BrandBackdrop())
            .environment(\.colorScheme, .light)
    }

    /// Décide de l'écran d'ouverture.
    ///
    /// Une session périmée ou révoquée renvoie 401, que le client traduit en
    /// oubli du jeton : on repart proprement sur l'écran d'entrée. Une panne
    /// réseau y mène aussi — se retrouver devant le formulaire est désagréable,
    /// mais moins que de bloquer quelqu'un derrière un écran d'attente sans
    /// issue.
    private func restore() async {
        guard stage == .restoring else { return }

        guard await dependencies.api.hasStoredSession() else {
            stage = .signedOut
            return
        }

        do {
            stage = .signedIn(try await dependencies.api.currentAccount())
        } catch {
            stage = .signedOut
        }
    }
}
