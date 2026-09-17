import Foundation

/// Tout ce que l'écran d'un document légal écrit **de lui-même**. Le titre et
/// le texte des chapitres, eux, vivent dans le document (``TermsOfUse``,
/// ``PrivacyPolicy``) : c'est le contrat, pas l'interface.
///
/// Mêmes conventions typographiques que ``BookCopy`` : apostrophe `’` (U+2019),
/// espace insécable avant `?` et `!`.
public enum LegalCopy {
    /// Le titre d'une carte : « Chapitre 4 — Description du service ». Le
    /// motif est celui de la maquette (« Chapitre 1 — Principes »), le titre
    /// celui du site.
    public static func chapterTitle(_ chapter: LegalChapter) -> String {
        "Chapitre \(chapter.number) — \(chapter.title)"
    }

    /// Le pied de page : la question, puis le lien vers le support.
    public static let helpPrompt = "Besoin d’aide ?"
    public static let helpLink = "Découvrir notre FAQ"

    /// Ce que VoiceOver dit du geste sur une carte.
    public static let expandHint = "Déplier"
    public static let collapseHint = "Replier"
}
