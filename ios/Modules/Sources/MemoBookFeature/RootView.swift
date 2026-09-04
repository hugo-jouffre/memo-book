import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Point d'entrée de l'interface, et le seul endroit qui décide de l'étape où
/// se trouve l'utilisateur : le tracé du M au lancement, l'accueil au tout
/// premier démarrage, puis l'entrée dans le compte, puis l'app.
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

    /// Le M est en train de s'écrire par-dessus tout le reste.
    @State private var isLaunching = true

    /// La pile de navigation de l'app, une fois entré.
    @State private var path: [HomeRoute] = []

    public init() {}

    public var body: some View {
        ZStack {
            if isLaunching {
                LaunchView { endLaunch() }
                    // Le signe grandit d'un cheveu en s'effaçant : il s'éloigne
                    // au lieu de s'éteindre.
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            } else {
                // **Pas** de fondu sur le contenu entier. C'est l'écran de
                // lancement qui s'efface par-dessus, et chaque bloc de
                // l'accueil qui monte à son tour — un fondu global les
                // recouvrirait tous et la cascade ne se verrait plus.
                content
                    .transition(.identity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
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
                    NavigationStack(path: $path) {
                        HomeView(onIntent: handle)
                            .navigationDestination(for: HomeRoute.self, destination: destination)
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

    private func endLaunch() {
        // Court : le voile se lève pendant que l'accueil se pose, au lieu de
        // le cacher jusqu'à ce que tout soit déjà en place.
        withAnimation(.smooth(duration: 0.45)) { isLaunching = false }
    }

    /// Ferme la session.
    ///
    /// L'ordre compte : on vide d'abord la pile de navigation, sinon l'écran de
    /// profil resterait poussé au-dessus de l'écran d'entrée le temps de
    /// l'animation. ``MemoBookAPI/signOut()`` ne peut pas échouer — il oublie le
    /// jeton local même si le serveur est injoignable — donc rien à rattraper
    /// ici : quelqu'un qui demande à sortir sort.
    private func signOut() {
        Task {
            await dependencies.api.signOut()
            path.removeAll()
            stage = .signedOut
        }
    }

    /// Où mène chaque intention de l'accueil.
    ///
    /// **Câblage provisoire.** Les voyages ne sont pas encore une ressource du
    /// back-end : l'accueil montre un jeu d'essai, et un identifiant de voyage
    /// n'est pas encore un identifiant de carnet. Ouvrir un voyage mène donc au
    /// détail du carnet, qui affichera son bandeau « Carnet introuvable » tant
    /// que les deux ne sont pas les mêmes. C'est la bonne destination, pas
    /// encore la bonne donnée.
    ///
    /// L'impression et la carte de découverte n'ont pas d'écran dessiné : elles
    /// ne mènent nulle part, et c'est ici que ça se voit.
    private func handle(_ intent: HomeIntent) {
        switch intent {
        case .openProfile:
            path.append(.profile)
        case .openTrip(let id):
            path.append(.trip(id: id))
        case .startRecording:
            // Enregistrer suppose un carnet ouvert : on passe par la liste
            // tant que l'accueil ne sait pas créer un voyage lui-même.
            path.append(.memos)
        case .orderPrint, .openShowcase:
            break
        }
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .profile:
            ProfileView(onSignOut: signOut)
        case .trip(let id):
            MemoDetailView(memoId: id)
        case .memos:
            MemoListView()
        }
    }
}

/// Les destinations que l'accueil peut pousser.
enum HomeRoute: Hashable {
    case profile
    case trip(id: String)
    case memos
}
