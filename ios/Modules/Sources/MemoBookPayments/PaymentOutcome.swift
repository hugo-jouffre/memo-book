import Foundation
import MemoBookCore

/// Ce qu'une feuille de paiement rend.
public enum PaymentOutcome: Sendable, Hashable {
    /// Le paiement est parti chez Stripe.
    ///
    /// ⚠️ **Ce n'est pas « la commande est validée ».** C'est le webhook côté
    /// serveur qui fait foi : l'app peut être tuée à la seconde suivante, et la
    /// commande n'en sera pas moins payée. L'écran doit donc relire l'état
    /// auprès du serveur, jamais conclure depuis ce cas.
    case succeeded
    /// La personne a fermé la feuille. Sans conséquence, et sans message
    /// d'erreur : ce n'est pas un échec, c'est un choix.
    case cancelled
    case failed(String)
}

public enum PaymentError: LocalizedError {
    /// Aucune fenêtre pour présenter la feuille. En pratique : l'app est
    /// passée en arrière-plan entre la demande et la présentation.
    case noPresenter

    /// La feuille a rendu ``PaymentOutcome/failed(_:)``.
    ///
    /// Un cas relayé et non reformulé : le message vient de Stripe, qui est le
    /// seul à savoir si la carte a été refusée, si le plafond est atteint ou si
    /// l'authentification a échoué. Le réécrire ici perdrait ce que la personne
    /// a besoin de lire pour s'en sortir.
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .noPresenter:
            "Impossible d’ouvrir le paiement pour le moment. Réessaie."
        case .refused(let message):
            message
        }
    }
}
