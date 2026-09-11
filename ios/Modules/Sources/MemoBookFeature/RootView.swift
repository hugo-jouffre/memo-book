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
    ///
    /// **Faux au démarrage.** Le tracé n'est pas une marque d'ouverture, c'est
    /// l'attente de l'accueil : il ne s'écrit que lorsqu'on va vers l'accueil,
    /// et pendant que celui-ci se charge. Quelqu'un qui n'a pas encore de compte
    /// arrive donc directement sur l'écran d'entrée, sans animation devant.
    @State private var isLaunching = false

    /// Les feuilles modales ouvertes dans l'app. C'est ce compteur qui fait
    /// reculer l'écran du dessous — voir ``BrandSheetPresentation``.
    @State private var sheets = BrandSheetPresentation()

    /// Ce que la session sait de l'abonnement. Elle vit ici parce que le profil
    /// l'écrit et que l'accueil le lit — voir ``SubscriptionSession``.
    @State private var subscription = SubscriptionSession()

    /// La pile de navigation de l'app, une fois entré.
    @State private var path: [HomeRoute] = []

    /// Ce qui empêche d'aller là où on vient de demander à aller. Une alerte
    /// **sur l'accueil**, et non un écran poussé qui ne montrerait qu'une
    /// erreur : quand la destination n'existe pas, on ne quitte pas la page.
    @State private var routingProblem: String?

    public init() {}

    public var body: some View {
        ZStack {
            // **Pas** de fondu sur le contenu entier. C'est l'écran de
            // lancement qui s'efface par-dessus, et chaque bloc de l'accueil qui
            // monte à son tour — un fondu global les recouvrirait tous et la
            // cascade ne se verrait plus.
            content

            if isLaunching {
                LaunchView { endLaunch() }
                    // Le signe grandit d'un cheveu en s'effaçant : il s'éloigne
                    // au lieu de s'éteindre.
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        // Le compteur de feuilles descend à tous les écrans **et à toutes les
        // feuilles** : c'est lui qui les relie.
        .environment(\.brandSheetPresentation, sheets)
        .environment(\.subscriptionSession, subscription)
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
                    AuthView { enterApp(as: $0) }
                case .signedIn:
                    NavigationStack(path: $path) {
                        HomeView(model: dependencies.homeModel(), onIntent: handle)
                            .navigationDestination(for: HomeRoute.self, destination: destination)
                    }
                    .tint(MemoBookColor.action)
                }
            }
        }
        .animation(.snappy, value: hasSeenWelcome)
        .animation(.snappy, value: stage)
        // L'app entière recule pendant qu'une feuille est ouverte, comme dans
        // les Réglages. C'est ici que ça se joue et non dans l'écran qui
        // présente : le recul doit emporter la pile de navigation avec lui, et
        // c'est le seul niveau qui occupe vraiment tout l'écran, safe areas
        // comprises — plus bas, les coins arrondis couperaient le fond au ras de
        // la barre d'état.
        .brandSheetPresenter(isPresented: sheets.isPresenting)
        // L'accueil se pose **derrière** le tracé du M, pas après lui : sans
        // cette information, sa cascade se jouait entièrement sous le voile et
        // l'écran apparaissait déjà en place.
        .environment(\.launchOverlayIsVisible, isLaunching)
        .alert(
            "Impossible d’ouvrir ce voyage",
            isPresented: .init(
                get: { routingProblem != nil },
                set: { if !$0 { routingProblem = nil } }
            ),
            presenting: routingProblem
        ) { _ in
            Button("D’accord", role: .cancel) { routingProblem = nil }
        } message: { message in
            Text(message)
        }
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

        // Le raccourci de vérification en simulateur — sans effet en release.
        // Voir ``OnboardingStorage/previewSignedInArgument``.
        if OnboardingStorage.isPreviewingSignedIn {
            hasSeenWelcome = true
            enterApp(as: Account(id: "preview", firstName: "Camille", createdAt: .now))
            return
        }

        // Pas de jeton en trousseau : la décision est immédiate, on ouvre
        // l'écran d'entrée. **Pas de tracé du M** — il n'y a rien à attendre, et
        // une animation devant un formulaire ne fait que retarder la saisie.
        guard await dependencies.api.hasStoredSession() else {
            stage = .signedOut
            return
        }

        do {
            let account = try await dependencies.api.currentAccount()
            enterApp(as: account)
        } catch {
            stage = .signedOut
        }
    }

    /// Entrer dans l'app, d'où qu'on vienne — session restaurée au lancement, ou
    /// formulaire tout juste envoyé.
    ///
    /// C'est **le seul chemin** vers l'accueil, et c'est pour ça que le tracé du
    /// M est ici : il couvre le chargement de l'accueil, qui est la seule chose
    /// qu'il ait jamais eu à couvrir. L'écran d'accueil du tout premier
    /// démarrage, lui, ne passe pas par là et n'a donc pas d'animation devant.
    private func enterApp(as account: Account) {
        stage = .signedIn(account)
        guard hasSeenWelcome else { return }
        isLaunching = true
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
            // Et ce que l'app gardait de ce compte : le dernier accueil reçu
            // dort sur le disque pour être relu hors ligne, il ne doit pas
            // attendre la personne suivante sur ce téléphone.
            await dependencies.forgetAccountContent()
            path.removeAll()
            stage = .signedOut
        }
    }

    /// Où mène chaque intention de l'accueil.
    ///
    /// Les voyages sont désormais une ressource du back-end : l'accueil vient
    /// de `GET /v1/home`, l'écran d'un voyage de `GET /v1/trips/:id`, et
    /// l'identifiant qui les relie est celui du serveur. Ouvrir une carte mène
    /// donc au voyage qu'elle montrait — mais aucune de ses étapes ne mène
    /// encore au carnet, faute d'un identifiant commun.
    ///
    /// L'impression n'a pas d'écran dessiné : elle ne mène nulle part, et c'est
    /// ici que ça se voit. La carte de découverte, elle, ouvre désormais la
    /// galerie des carnets de la communauté.
    ///
    /// L'enregistrement, lui, ne passe pas par ici : la feuille rend son vocal
    /// à ``HomeModel/upload(_:)``, qui l'envoie aux carnets en cours. Il n'y a
    /// pas d'écran au bout, donc rien à router.
    private func handle(_ intent: HomeIntent) {
        switch intent {
        case .openProfile:
            path.append(.profile)
        case .openTrip(let id):
            // **On n'ouvre pas un voyage dont l'identifiant n'est pas celui
            // d'une ressource.** Les voyages du bac à sable n'existent que dans
            // l'app : les pousser quand même ouvrait un écran vide sur
            // « Requête invalide. » — le 400 que le serveur renvoie à un
            // identifiant qui n'est pas un UUID, et qui n'a rien à dire à
            // l'utilisateur. On reste sur l'accueil, et on le dit.
            guard UUID(uuidString: id) != nil else {
                routingProblem =
                    "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à ouvrir."
                return
            }
            // Sortir de la création **remplace** l'étape au lieu de s'empiler
            // dessus : la flèche de retour du voyage doit ramener à l'accueil,
            // et non au formulaire qu'on vient de finir. Les deux écritures
            // n'en font qu'une, ce qui évite la page blanche qu'un `dismiss()`
            // suivi d'un empilement laissait derrière lui.
            if path.last == .tripCreation { path.removeLast() }
            path.append(.trip(id: id))
        case .openGallery:
            path.append(.gallery)
        case .createTrip:
            path.append(.tripCreation)
        case .orderPrint(let tripId):
            // **L'imprimante ouvre l'aperçu**, et non un tunnel de commande.
            // On ne commande pas un carnet qu'on n'a pas vu : l'aperçu porte
            // « Commander ce carnet » en bas de page, donc rien n'est perdu —
            // on ajoute seulement l'étape qui manquait.
            guard UUID(uuidString: tripId) != nil else {
                routingProblem =
                    "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à prévisualiser."
                return
            }
            path.append(.bookPreview(memoId: tripId))
        case .joinTrip, .importFromPolarsteps, .openHelp:
            break
        }
    }

    /// Où mène chaque intention de l'accueil d'un voyage.
    ///
    /// Les deux mènent au **même** écran : raconter la suite et ouvrir une
    /// étape sont la même conversation, posée à deux endroits différents du
    /// voyage. C'est ce qui évite un deuxième écran de saisie qui aurait dit la
    /// même chose.
    private func handle(_ intent: TripIntent) {
        switch intent {
        case .tellMore(let tripId):
            path.append(.chat(tripId: tripId, stepId: nil))
        case .openStep(let tripId, let stepId):
            path.append(.chat(tripId: tripId, stepId: stepId))
        case .openSettings(let tripId):
            path.append(.tripSettings(id: tripId))
        case .openBookPreview(let tripId):
            path.append(.bookPreview(memoId: tripId))
        }
    }

    /// Où mène l'unique intention du profil.
    ///
    /// La cagnotte s'ouvre **sans voyage** depuis le profil : il n'y a pas de
    /// carnet à financer dans ce contexte, seulement un solde à consulter.
    /// L'écran s'en accommode — voir ``BookCopy/Wallet/subtitle(trip:)``.
    private func handle(_ intent: ProfileIntent) {
        switch intent {
        case .openWallet:
            path.append(.wallet(tripId: nil))
        }
    }

    /// Où mène chaque intention de la conversation.
    private func handle(_ intent: ChatIntent) {
        switch intent {
        case .openSettings(let tripId):
            path.append(.tripSettings(id: tripId))
        case .openBookPreview(let memoId):
            path.append(.bookPreview(memoId: memoId))
        }
    }

    /// Où mène chaque intention des paramètres d'un voyage.
    ///
    /// Trois destinations existent — la cagnotte, l'aperçu du carnet, et rien
    /// d'autre. Les dix lignes de réglage qui restent ouvriront des feuilles
    /// que les maquettes ne dessinent pas encore : elles sont **inertes et
    /// signalées**, plutôt que branchées sur un écran inventé (R3).
    private func handle(_ intent: TripSettingsIntent) {
        switch intent {
        case .openWallet:
            path.append(.wallet(tripId: currentTripId))
        case .openBookPreview:
            // Le carnet d'un voyage porte aujourd'hui le même identifiant que
            // lui : un voyage est un `memo` côté serveur. La distinction existe
            // dans les routes (`/v1/trips/:id` et `/v1/memos/:id`) parce qu'elle
            // existera dans le produit — un voyage pourra donner deux carnets.
            guard let tripId = currentTripId else { return }
            path.append(.bookPreview(memoId: tripId))
        case .openCustomisation:
            guard let tripId = currentTripId else { return }
            path.append(.bookCustomisation(tripId: tripId))
        case .renameTrip, .editDates, .editPace, .manageNotifications, .editCompanions,
            .editTheme, .connectTricount, .orderBook, .openHelp:
            break
        }
    }

    /// Où mène l'unique intention des personnalisations.
    ///
    /// Les couvertures n'ont pas d'écran dessiné : la ligne est inerte plutôt
    /// que branchée sur un écran inventé (R3).
    private func handle(_ intent: BookCustomisationIntent) {
        switch intent {
        case .openCovers:
            break
        }
    }

    /// Où mène chaque intention de l'aperçu du carnet.
    private func handle(_ intent: BookPreviewIntent) {
        switch intent {
        case .openWallet:
            path.append(.wallet(tripId: currentTripId))
        case .customise:
            guard let tripId = currentTripId else { return }
            path.append(.tripSettings(id: tripId))
        case .order, .configureCovers, .shareFeedback:
            // La commande d'impression et le choix des couvertures n'ont pas
            // d'écran dessiné. Le mot des fondateurs, lui, ouvre un courrier
            // — la feuille s'en occupe elle-même.
            break
        }
    }

    /// Où mène chaque intention de la cagnotte.
    private func handle(_ intent: WalletIntent) {
        switch intent {
        case .openBookPreview:
            guard let tripId = currentTripId else { return }
            path.append(.bookPreview(memoId: tripId))
        case .shareWallet, .inviteFriends, .addFunds, .topUpUnavailable, .openHelp:
            // Le partage de la cagnotte passe par la feuille du système, que la
            // vue présente elle-même. Recharger attend Stripe, et l'écran le
            // dit — voir ``BookCopy/Wallet/addUnavailable``.
            break
        }
    }

    /// Le voyage ouvert, s'il y en a un dans la pile.
    ///
    /// Il se lit **dans le chemin** plutôt que d'être porté par chaque écran :
    /// la cagnotte et l'aperçu s'ouvrent depuis les réglages d'un voyage, depuis
    /// sa conversation ou depuis son accueil, et tous les trois doivent revenir
    /// au même voyage. Le déduire du chemin évite de le trimballer dans quatre
    /// intentions.
    private var currentTripId: String? {
        for route in path.reversed() {
            switch route {
            case .trip(let id), .tripSettings(let id), .bookPreview(let id),
                .bookCustomisation(let id):
                return id
            case .chat(let tripId, _):
                return tripId
            case .wallet(let tripId):
                if let tripId { return tripId }
            case .profile, .gallery, .tripCreation, .memos:
                continue
            }
        }
        return nil
    }

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .profile:
            ProfileView(model: dependencies.profileModel(), onSignOut: signOut, onIntent: handle)
        case .trip(let id):
            TripHomeView(
                tripId: id,
                model: dependencies.tripModel(id: id),
                onIntent: handle
            )
        case .chat(let tripId, let stepId):
            ChatView(tripId: tripId, stepId: stepId, onIntent: handle)
        case .gallery:
            // La galerie **réémet** des intentions : son bouton du bas crée un
            // carnet ou ramène au voyage en cours. Elles repassent donc par le
            // même routeur que celles de l'accueil, et non par un second.
            GalleryView(model: dependencies.galleryModel(), onIntent: handle)
        case .tripCreation:
            // Elle **réémet** une intention, comme la galerie : « Commencer ! »
            // ouvre le voyage qui vient d'être créé, et c'est encore ce
            // routeur-ci qui le pousse.
            TripCreationView(model: dependencies.tripCreationModel(), onIntent: handle)
        case .memos:
            MemoListView()
        case .tripSettings(let id):
            TripSettingsView(model: dependencies.tripSettingsModel(tripId: id), onIntent: handle)
        case .bookPreview(let memoId):
            BookPreviewFlowView(model: dependencies.bookPreviewModel(memoId: memoId), onIntent: handle)
        case .wallet(let tripId):
            WalletView(model: dependencies.walletModel(tripId: tripId), onIntent: handle)
        case .bookCustomisation(let tripId):
            BookCustomisationView(
                model: dependencies.bookCustomisationModel(tripId: tripId),
                onIntent: handle
            )
        }
    }
}

extension EnvironmentValues {
    /// Le tracé du M couvre encore l'écran.
    ///
    /// Il descend jusqu'à l'accueil pour que celui-ci retarde sa cascade
    /// d'apparition : elle doit **prolonger** le tracé, donc commencer quand le
    /// voile se lève, et non pendant qu'il cache tout.
    @Entry var launchOverlayIsVisible: Bool = false
}

/// Les destinations que l'accueil peut pousser.
enum HomeRoute: Hashable {
    case profile
    case trip(id: String)
    /// La conversation avec MEMO. `stepId` la pose sur une étape précise ;
    /// `nil` la pose sur le voyage entier.
    case chat(tripId: String, stepId: String?)
    /// Les carnets de la communauté, ouverts par la carte de découverte.
    case gallery
    /// Les six étapes de « Créer un voyage ».
    case tripCreation
    case memos
    /// Les réglages d'un voyage, ouverts par la roue crantée — depuis son
    /// accueil comme depuis la conversation.
    case tripSettings(id: String)
    /// L'aperçu du carnet : la page qui se monte, puis le PDF qu'on feuillette.
    ///
    /// L'identifiant est celui du **carnet** et non du voyage : c'est le carnet
    /// qu'on compose, et `memos` est la ressource qui le porte.
    case bookPreview(memoId: String)
    /// Ma cagnotte. `tripId` ne dit pas *quelle* cagnotte — il n'y en a qu'une
    /// par compte — mais **quel carnet on finance**, pour l'estimation de pages
    /// et de coût. `nil` quand on arrive du profil.
    case wallet(tripId: String?)
    /// Les personnalisations du carnet, ouvertes par « Style du carnet ».
    case bookCustomisation(tripId: String)
}
