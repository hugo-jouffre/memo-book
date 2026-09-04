import MemoBookDesign
import SwiftUI

/// Point d'entrée de l'interface, et le seul endroit qui décide de l'étape où
/// se trouve l'utilisateur : le tracé du M au lancement, l'accueil au tout
/// premier démarrage, puis l'entrée dans le compte, puis l'app.
///
/// Rien n'est mis derrière un écran d'attente réseau : les erreurs
/// appartiennent à l'écran qui fait l'appel — voir ``AppDependencies``.
/// L'écran de lancement, lui, n'attend que son animation : il ne retient pas
/// l'app pour un appel qui pourrait ne jamais revenir.
public struct RootView: View {
    /// L'écran d'accueil ne se montre qu'au premier lancement.
    @AppStorage(OnboardingStorage.hasSeenWelcome) private var hasSeenWelcome = false

    /// Provisoire : il n'y a pas encore d'authentification côté serveur, donc
    /// pas de session à restaurer. Ce drapeau tient lieu de session locale et
    /// devra céder la place à un vrai jeton. Voir ``AuthModel``.
    @AppStorage(OnboardingStorage.isSignedIn) private var isSignedIn = false

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
            } else if !isSignedIn {
                AuthView { isSignedIn = true }
            } else {
                NavigationStack(path: $path) {
                    HomeView(onIntent: handle)
                        .navigationDestination(for: HomeRoute.self) { route in
                            switch route {
                            case .trip(let id): MemoDetailView(memoId: id)
                            case .memos: MemoListView()
                            }
                        }
                }
                .tint(MemoBookColor.action)
            }
        }
        .animation(.snappy, value: hasSeenWelcome)
        .animation(.snappy, value: isSignedIn)
    }

    private func endLaunch() {
        // Court : le voile se lève pendant que l'accueil se pose, au lieu de
        // le cacher jusqu'à ce que tout soit déjà en place.
        withAnimation(.smooth(duration: 0.45)) { isLaunching = false }
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
    /// Le profil, l'impression et la carte de découverte n'ont pas d'écran
    /// dessiné : ils ne mènent nulle part, et c'est ici que ça se voit.
    private func handle(_ intent: HomeIntent) {
        switch intent {
        case .openTrip(let id):
            path.append(.trip(id: id))
        case .startRecording:
            // Enregistrer suppose un carnet ouvert : on passe par la liste
            // tant que l'accueil ne sait pas créer un voyage lui-même.
            path.append(.memos)
        case .openProfile, .orderPrint, .openShowcase:
            break
        }
    }
}

/// Les destinations que l'accueil peut pousser.
enum HomeRoute: Hashable {
    case trip(id: String)
    case memos
}
