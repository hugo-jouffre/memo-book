import Foundation
import SwiftUI

#if canImport(AppTrackingTransparency)
    import AppTrackingTransparency
#endif

/// L'autorisation de suivi publicitaire d'iOS — le panneau « Autoriser
/// "MemoBook" à suivre votre activité ? ».
///
/// C'est une **valeur**, pas un service : deux fonctions, l'une qui lit la
/// réponse déjà donnée, l'autre qui pose la question. Même forme que
/// ``Connectivity`` et que les fonctions-sources des modèles d'écran — un
/// aperçu ou un test en fabrique une qui répond ce qu'il veut, sans protocole
/// ni double à écrire.
///
/// ## Ce que le panneau garde, et ce qu'il ne garde pas
///
/// ⚠️ **Le système ne pose la question qu'une seule fois par installation.**
/// Un second appel ne montre rien et rend la réponse déjà stockée. Ce n'est
/// donc pas à l'app de retenir qu'elle a demandé — elle le relit avec
/// ``current``, et ne demande que sur ``Decision/notDetermined``.
///
/// ⚠️ **Le panneau ne s'affiche que si l'app est active.** Appelé pendant que
/// l'écran de lancement couvre encore l'app, ou juste après un retour
/// d'arrière-plan, ``request`` rend la main sans rien montrer — et la question
/// est perdue pour cette session. C'est pour ça que l'accueil attend d'être
/// à la fois chargé, découvert et `scenePhase == .active` avant d'appeler.
///
/// ### Revoir le panneau en simulateur
///
/// `xcrun simctl privacy` ne connaît **pas** de service `tracking` : la
/// commande habituelle ne sert à rien ici. Deux chemins seulement :
///
/// - désinstaller l'app du simulateur (le conteneur part, la réponse avec) ;
/// - *Réglages ▸ Confidentialité et sécurité ▸ Suivi*, éteindre puis rallumer
///   « Autoriser les apps à demander de vous suivre » — ce qui remet **toutes**
///   les apps à `notDetermined`.
///
/// Un ⌘R ne suffit pas : Xcode réinstalle par-dessus sans vider le conteneur,
/// exactement comme pour le mot des fondateurs (voir ``OnboardingStorage``).
public struct TrackingAuthorization: Sendable {
    /// Ce que l'utilisateur a répondu.
    ///
    /// `restricted` — un appareil sous contrôle parental, ou « Autoriser les
    /// apps à demander » éteint dans les Réglages — est replié sur ``denied`` :
    /// les deux veulent dire la même chose pour l'app, on ne suit pas, et les
    /// distinguer inviterait à écrire un cas de plus qui ne changerait rien.
    public enum Decision: Sendable, Equatable {
        /// La question n'a pas encore été posée. Le seul cas où l'on demande.
        case notDetermined
        case granted
        case denied
    }

    /// La réponse déjà donnée, lue sans rien afficher.
    public let current: @Sendable () -> Decision

    /// Pose la question, et rend la réponse.
    ///
    /// Ne montre le panneau que si ``current`` vaut ``Decision/notDetermined``
    /// **et** que l'app est active — sinon rend la main tout de suite.
    public let request: @Sendable () async -> Decision

    public init(
        current: @escaping @Sendable () -> Decision,
        request: @escaping @Sendable () async -> Decision
    ) {
        self.current = current
        self.request = request
    }

    /// Le vrai panneau du système.
    public static let system = TrackingAuthorization(
        current: {
            #if canImport(AppTrackingTransparency)
                Decision(ATTrackingManager.trackingAuthorizationStatus)
            #else
                .denied
            #endif
        },
        request: {
            #if canImport(AppTrackingTransparency)
                // La version à fermeture plutôt que l'`async` générée par le
                // pont ObjC : celle-ci est garantie appelée une fois et une
                // seule, et `withCheckedContinuation` le vérifie en debug.
                await withCheckedContinuation { continuation in
                    ATTrackingManager.requestTrackingAuthorization { status in
                        continuation.resume(returning: Decision(status))
                    }
                }
            #else
                .denied
            #endif
        }
    )

    /// Ne demande rien et ne suit personne.
    ///
    /// C'est le défaut de l'environnement, donc ce que voient les aperçus Xcode
    /// (`#Preview`) : un panneau du système qui surgit dans le canevas
    /// bloquerait l'aperçu sans rien apprendre à personne. L'app, elle, y pose
    /// ``system`` — voir `RootView`.
    ///
    /// ``current`` rend ``Decision/denied`` et non ``Decision/notDetermined`` :
    /// c'est ce qui fait que l'accueil ne tente même pas de demander.
    public static let never = TrackingAuthorization(
        current: { .denied },
        request: { .denied }
    )
}

#if canImport(AppTrackingTransparency)
    extension TrackingAuthorization.Decision {
        init(_ status: ATTrackingManager.AuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .authorized: self = .granted
            // `.denied`, `.restricted`, et tout cas qu'une version future
            // ajouterait : on ne suit pas. Le défaut est **fermé**, et c'est
            // volontaire — un cas inconnu ne doit pas ouvrir le suivi.
            default: self = .denied
            }
        }
    }
#endif

extension EnvironmentValues {
    /// D'où l'accueil apprend s'il doit demander l'autorisation de suivi.
    ///
    /// Le défaut ne demande rien (``TrackingAuthorization/never``) : un aperçu
    /// Xcode n'a pas à faire surgir un panneau du système. C'est `RootView` qui
    /// pose le vrai — et seulement une fois la session ouverte, puisque c'est
    /// l'accueil qui porte la question.
    @Entry var trackingAuthorization: TrackingAuthorization = .never
}
