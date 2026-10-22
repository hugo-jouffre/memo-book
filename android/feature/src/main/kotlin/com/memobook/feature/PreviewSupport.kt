package com.memobook.feature

import com.memobook.networking.MemoBookApi

/**
 * Le bac à sable — le `PreviewSupport.swift` d'iOS : un double d'API qui sert
 * le jeu d'essai, pour le lancement `previewSignedIn` et les aperçus.
 *
 * ⏳ Le double lui-même (`PreviewApi`) arrive avec la phase A3b.
 */
object PreviewSupport {
    fun api(): MemoBookApi = throw NotImplementedError("Le bac à sable (PreviewApi) arrive avec la phase A3b.")
}
