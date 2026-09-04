import Foundation
import MemoBookCore
import Observation

/// Ce que l'écran de profil sait faire : charger le profil, et enregistrer ce
/// qu'on y change.
///
/// Même construction que ``HomeModel`` : le modèle ne connaît pas l'API, il
/// reçoit **une source**. Aujourd'hui le jeu d'essai, demain `api.profile()` —
/// une seule ligne à changer, et les aperçus continuent de montrer les quatre
/// états sans serveur.
///
/// **Rien n'est encore persisté.** Les réglages vivent en mémoire le temps de
/// la session : c'est écrit une fois ici plutôt que répété à chaque bouton, et
/// c'est `save()` qui deviendra un appel réseau. La seule action qui agit
/// vraiment est la déconnexion, portée par ``RootView``.
@MainActor
@Observable
public final class ProfileModel {
    public private(set) var profile: TravellerProfile?
    public private(set) var errorMessage: String?

    private let source: () async throws -> TravellerProfile

    public init(source: @escaping () async throws -> TravellerProfile = { .fixture }) {
        self.source = source
    }

    /// `true` tant qu'on n'a rien à montrer. L'écran affiche alors sa coquille
    /// plutôt qu'un demi-profil.
    public var isLoading: Bool { profile == nil && errorMessage == nil }

    public func load() async {
        do {
            profile = try await source()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Ce qu'on change depuis l'écran
    //
    // Des méthodes plutôt qu'un `profile` ouvert en écriture : une vue ne doit
    // pas pouvoir remplacer un profil entier par mégarde, et c'est ici que
    // viendront se brancher les appels réseau — un seul endroit à modifier.

    public func setNewsletter(_ isOn: Bool) {
        mutate { $0.wantsNewsletter = isOn }
    }

    public func setConnector(id: String, isEnabled: Bool) {
        mutate { profile in
            guard let index = profile.connectors.firstIndex(where: { $0.id == id }) else { return }
            profile.connectors[index].isEnabled = isEnabled
        }
    }

    public func selectCard(id: String) {
        mutate { $0.selectedCardId = id }
    }

    public func save(address: PostalAddress) {
        mutate { $0.address = address }
    }

    /// Enregistre une carte à partir du formulaire.
    ///
    /// **Seuls les quatre derniers chiffres sont conservés** — voir
    /// ``PaymentCard``. Le numéro complet, la date et le cryptogramme ne sont ni
    /// gardés ni journalisés : le jour où le paiement existe, ils partiront
    /// directement au prestataire sans passer par nos modèles.
    public func addCard(number: String, label: String) {
        let digits = number.filter(\.isNumber)
        guard digits.count >= 4 else { return }

        mutate { profile in
            let card = PaymentCard(
                id: UUID().uuidString,
                label: label,
                last4: String(digits.suffix(4))
            )
            profile.cards.append(card)
            profile.selectedCardId = card.id
        }
    }

    public func activateSubscription() {
        mutate { $0.subscription.isActive = true }
    }

    private func mutate(_ change: (inout TravellerProfile) -> Void) {
        guard var profile else { return }
        change(&profile)
        self.profile = profile
    }
}
