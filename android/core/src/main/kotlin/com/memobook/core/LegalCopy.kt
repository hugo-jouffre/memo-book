package com.memobook.core

/**
 * Tout ce que l'écran d'un document légal écrit **de lui-même**. Le titre et
 * le texte des chapitres, eux, vivent dans le document ([TermsOfUse],
 * [PrivacyPolicy]) : c'est le contrat, pas l'interface. Le jumeau de
 * `MemoBookCore/LegalCopy.swift`.
 *
 * Mêmes conventions typographiques que `BookCopy` : apostrophe `’` (U+2019),
 * espace insécable avant `?` et `!`.
 */
object LegalCopy {
    /**
     * Le titre d'une carte : « Chapitre 4 — Description du service ». Le
     * motif est celui de la maquette (« Chapitre 1 — Principes »), le titre
     * celui du site.
     */
    fun chapterTitle(chapter: LegalChapter): String =
        "Chapitre ${chapter.number} — ${chapter.title}"

    /** Le pied de page : la question, puis le lien vers le support. */
    const val helpPrompt = "Besoin d’aide ?"
    const val helpLink = "Découvrir notre FAQ"
}
