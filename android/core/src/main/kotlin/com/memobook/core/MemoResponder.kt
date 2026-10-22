package com.memobook.core

/**
 * Ce qui répond à la place de MEMO. Le jumeau de `MemoBookCore/MemoResponder.swift`.
 *
 * Le modèle de l'écran dépend de **cette interface**, jamais d'une
 * implémentation : c'est ce qui permet de le piloter avec le moteur local dans
 * les aperçus, et avec la vraie route le jour où elle existe. Même parti pris
 * que la source injectée de `HomeFeed` ou de `TripDetail`, à ceci près qu'ici
 * la source répond au lieu de charger.
 *
 * Elle vit dans `:core`, qui n'a aucune dépendance : le moteur se teste donc
 * phrase par phrase sur la JVM, sans émulateur.
 */
interface MemoResponder {
    /**
     * L'ouverture d'une conversation neuve.
     *
     * Séparée de [reply] parce qu'elle ne répond à rien : c'est MEMO qui parle
     * le premier, avant que le voyageur ait dit un mot. La maquette le montre
     * bien — la bulle blanche d'ouverture est **au-dessus** du premier vocal.
     */
    fun opening(context: ChatContext): MemoReply

    /**
     * La réponse de MEMO à un tour de parole.
     *
     * [MemoReply] porte les bulles **et leur rythme** : le répondeur ne dort
     * jamais, il décrit. C'est le modèle qui tient l'horloge — voir [MemoBeat].
     */
    suspend fun reply(turn: ChatTurn): MemoReply

    /**
     * La fiche de retranscription, une fois le vocal écouté.
     *
     * **La vraie route ne pourra pas rendre la fiche remplie.** La transcription
     * est un job asynchrone côté serveur : [reply] rend donc tout de suite une
     * fiche dont le récit est `null`, et le modèle appelle celle-ci pour
     * l'attendre. C'est l'implémentation distante qui y sondera
     * `GET /v1/entries/:id`, comme `MemoDetailModel` le fait déjà toutes les
     * trois secondes.
     *
     * Le moteur local n'a rien à attendre : l'implémentation par défaut suffit.
     */
    suspend fun awaitTranscript(card: TranscriptCard): TranscriptCard = card
}

/**
 * Ce qui peut rater, dit au voyageur.
 *
 * Les messages sont en tutoiement et disent quoi faire, pas ce qui s'est passé
 * techniquement : ils s'affichent tels quels dans un `ErrorBanner`.
 */
sealed class MemoResponderError(val errorDescription: String) : Exception(errorDescription) {
    data object Unreachable :
        MemoResponderError("Je n’ai pas réussi à te répondre. Vérifie ta connexion et réessaie.")

    data object TranscriptionUnavailable :
        MemoResponderError("Je n’ai pas réussi à écouter ce vocal. Réessaie, ou raconte-le-moi au clavier.")
}
