import Foundation

/// Ce qui répond à la place de MEMO.
///
/// Le modèle de l'écran dépend de **ce protocole**, jamais d'une implémentation :
/// c'est ce qui permet de le piloter avec le moteur local dans les aperçus, et
/// avec la vraie route le jour où elle existe. Même parti pris que la source
/// injectée de ``HomeFeed`` ou de ``TripDetail``, à ceci près qu'ici la source
/// répond au lieu de charger.
///
/// Il vit dans `MemoBookCore`, qui n'a aucune dépendance : le moteur se teste
/// donc phrase par phrase dans `MemoBookCoreTests`, sans simulateur.
public protocol MemoResponder: Sendable {
    /// L'ouverture d'une conversation neuve.
    ///
    /// Séparée de ``reply(to:)`` parce qu'elle ne répond à rien : c'est MEMO qui
    /// parle le premier, avant que le voyageur ait dit un mot. La maquette le
    /// montre bien — la bulle blanche d'ouverture est **au-dessus** du premier
    /// vocal.
    func opening(for context: ChatContext) -> MemoReply

    /// La réponse de MEMO à un tour de parole.
    ///
    /// ``MemoReply`` porte les bulles **et leur rythme** : le répondeur ne dort
    /// jamais, il décrit. C'est le modèle qui tient l'horloge — voir
    /// ``MemoBeat``.
    func reply(to turn: ChatTurn) async throws -> MemoReply

    /// La fiche de retranscription, une fois le vocal écouté.
    ///
    /// **La vraie route ne pourra pas rendre la fiche remplie.** La transcription
    /// est un job asynchrone côté serveur : `reply(to:)` rend donc tout de suite
    /// une fiche dont le récit est `nil`, et le modèle appelle celle-ci pour
    /// l'attendre. C'est l'implémentation distante qui y sondera
    /// `GET /v1/entries/:id`, comme `MemoDetailModel` le fait déjà toutes les
    /// trois secondes.
    ///
    /// Le moteur local n'a rien à attendre : l'implémentation par défaut suffit.
    func awaitTranscript(of card: TranscriptCard) async throws -> TranscriptCard
}

extension MemoResponder {
    public func awaitTranscript(of card: TranscriptCard) async throws -> TranscriptCard { card }
}

/// Ce qui peut rater, dit au voyageur.
///
/// Les messages sont en tutoiement et disent quoi faire, pas ce qui s'est passé
/// techniquement : ils s'affichent tels quels dans un ``ErrorBanner``.
public enum MemoResponderError: Error, LocalizedError {
    case unreachable
    case transcriptionUnavailable

    public var errorDescription: String? {
        switch self {
        case .unreachable:
            "Je n’ai pas réussi à te répondre. Vérifie ta connexion et réessaie."
        case .transcriptionUnavailable:
            "Je n’ai pas réussi à écouter ce vocal. Réessaie, ou raconte-le-moi au clavier."
        }
    }
}
