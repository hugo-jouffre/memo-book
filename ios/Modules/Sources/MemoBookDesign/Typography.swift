import SwiftUI

/// Les deux familles de MemoBook, décision D3 : **Sora** pour les titres et les
/// chiffres, **General Sans** pour tout le reste.
///
/// ⚠️ Les fichiers de police ne sont pas encore embarqués (`Info.plist` →
/// `UIAppFonts`). Tant qu'ils manquent, `Font.custom` retombe sur la police
/// système : les écrans restent lisibles et bien proportionnés, la marque
/// arrive le jour où les `.otf` entrent dans le dépôt. Rien d'autre à changer.
public enum MemoBookFontFamily {
    public static let soraBold = "Sora-Bold"
    public static let soraSemibold = "Sora-SemiBold"
    public static let sansRegular = "GeneralSans-Regular"
    public static let sansMedium = "GeneralSans-Medium"
    public static let sansSemibold = "GeneralSans-Semibold"
}

/// Les styles de texte de l'app, relevés sur les écrans du lot 1.
///
/// Chaque style se déclare avec `relativeTo:` — jamais une taille fixe, qui
/// figerait le texte et casserait Dynamic Type (R7).
public enum MemoBookFont {
    /// Titre d'écran — Sora SemiBold 2 rem, interligne 35, approche −0.41.
    /// Un seul par écran.
    public static let screenTitle = Font.custom(
        MemoBookFontFamily.soraSemibold,
        size: rem(2),
        relativeTo: .largeTitle
    )

    /// Titre de bloc, titre de carte — General Sans Semibold 1 rem.
    public static let sectionTitle = Font.custom(
        MemoBookFontFamily.sansSemibold,
        size: rem(1),
        relativeTo: .headline
    )

    /// Texte courant — General Sans Regular 1 rem.
    public static let body = Font.custom(
        MemoBookFontFamily.sansRegular,
        size: rem(1),
        relativeTo: .body
    )

    /// Texte secondaire dans une carte — General Sans Regular 0.75 rem.
    public static let description = Font.custom(
        MemoBookFontFamily.sansRegular,
        size: rem(0.75),
        relativeTo: .footnote
    )

    /// Libellé d'action — General Sans Medium 1 rem.
    public static let button = Font.custom(
        MemoBookFontFamily.sansMedium,
        size: rem(1),
        relativeTo: .body
    )

    /// Lien et mention discrète — General Sans Medium 0.75 rem.
    public static let link = Font.custom(
        MemoBookFontFamily.sansMedium,
        size: rem(0.75),
        relativeTo: .footnote
    )

    /// Pastille — General Sans Medium 0.875 rem, interligne 22, approche −0.41.
    public static let tagline = Font.custom(
        MemoBookFontFamily.sansMedium,
        size: rem(0.875),
        relativeTo: .subheadline
    )

    /// Chiffre d'une pastille numérotée — Sora SemiBold 1 rem.
    public static let badgeNumber = Font.custom(
        MemoBookFontFamily.soraSemibold,
        size: rem(1),
        relativeTo: .body
    )

    /// Légende, mention de bas d'écran.
    public static let caption = Font.custom(
        MemoBookFontFamily.sansRegular,
        size: rem(0.75),
        relativeTo: .footnote
    )

    /// Titres de **carnet** (les pages du livre, pas le chrome de l'app). Le
    /// serif est une décision éditoriale à part, non couverte par les variables
    /// de marque : un carnet ne se lit pas comme une barre de navigation.
    public static func bookTitle(_ size: CGFloat = rem(1.75)) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// Transcription brute : le monospace signale « pas encore mis en forme ».
    public static let transcript = Font.system(.callout, design: .monospaced)
}

/// Interlignes et approches relevés sur les nœuds Figma. Ils font partie du
/// dessin, pas de la décoration.
public enum MemoBookTracking {
    /// Titre d'écran et tagline.
    public static let tight: CGFloat = -0.408
    /// Corps de texte et titres de bloc.
    public static let body: CGFloat = 0.16
    /// Descriptions des cartes.
    public static let description: CGFloat = 0.12
}
