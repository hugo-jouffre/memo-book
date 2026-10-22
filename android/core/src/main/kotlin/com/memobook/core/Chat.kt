package com.memobook.core

// La conversation avec MEMO : ce que le voyageur raconte, et ce que l'assistant
// en fait. Le jumeau de `MemoBookCore/Chat.swift` — pour l'instant son seul
// `ChatAuthor`, dont la bulle du design system a besoin ; le reste du fichier
// (vocaux, messages, décodage) arrive avec la phase A3.
//
// **Deux couleurs, deux auteurs, et c'est toute la lecture de l'écran** : le
// bleu à droite est ce que le voyageur a dit, le blanc à gauche est ce que MEMO
// en a compris.

/**
 * Qui parle.
 *
 * @property rawValue la valeur que le serveur écrit — le `rawValue` de l'énum Swift.
 */
enum class ChatAuthor(val rawValue: String) {
    /** L'assistant. Bulle blanche, alignée à gauche. */
    Memo("memo"),

    /** Le voyageur. Bulle bleue, alignée à droite. */
    Traveller("traveller"),
    ;

    /**
     * `true` quand c'est le voyageur : c'est cette seule question que l'écran
     * pose pour décider du côté, de la couleur et du sens de la queue.
     */
    val isTraveller: Boolean get() = this == Traveller
}
