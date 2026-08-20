import SwiftUI

// Les tokens de design de MemoBook.
//
// Source de vérité : `agents/design.md`, qui recopie les variables du fichier
// Figma « MemoBook — Product ». Toute valeur ci-dessous doit s'y retrouver
// telle quelle. En cas d'écart, c'est Figma qui a raison, et on met les deux à
// jour dans le même commit.
//
// Aucune couleur, aucune dimension ne se code en dur ailleurs dans l'app.
// Les dimensions s'écrivent en rem (voir `Rem.swift`), jamais en points.

private extension Color {
    /// Construit une couleur depuis un hexadécimal `RRGGBB`, comme dans Figma.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Les couleurs de l'app.
///
/// Le nommage est **sémantique** : on écrit `MemoBookColor.action`, pas
/// `MemoBookColor.green`. Le jour où l'accent change, un seul token bouge.
public enum MemoBookColor {
    // MARK: Marque

    /// Couleur d'action : boutons primaires, liens, sélection, teinte de
    /// navigation. `Brand Colors/Green`.
    public static let action = Color(hex: 0x28654B)

    /// Accent du scheme, `Scheme/Accent` = `Brand Colors/Lime`.
    ///
    /// Très saturé : il met en valeur ponctuellement (surlignage, sélection,
    /// badge). Jamais du texte sombre sur grande surface, jamais un fond de CTA
    /// sans contraste vérifié — c'est `action` qui porte les boutons.
    public static let accent = Color(hex: 0xE2F32B)

    /// Accent illustratif de l'onboarding : bordures de cartes, pastilles
    /// numérotées, et à 30 % en fond d'icône. `Brand Colors/Blue`.
    public static let illustration = Color(hex: 0xAFD2F0)

    /// Texte principal. `Brand Colors/Black` — un noir chaud, jamais `#000000`.
    public static let ink = Color(hex: 0x2D231A)

    /// Texte secondaire, légendes, placeholders. `Grays/Gray`.
    public static let inkSecondary = Color(hex: 0x8E8E93)

    /// Fond des écrans. `Scheme/Background Light` = `Brand Colors/Beige`.
    public static let background = Color(hex: 0xFCF2E9)

    /// Cartes, champs et zones de contenu. `Brand Colors/White` — un blanc
    /// chaud, jamais `#FFFFFF`.
    public static let surface = Color(hex: 0xFFFCF8)

    /// Surfaces « carnet » : aperçu du livre, cartes de couverture. Plus
    /// soutenu que le fond d'écran, pour que le carnet s'en détache.
    /// `Brand Colors/Beige Darker`.
    public static let paper = Color(hex: 0xCFBBAA)

    /// Filets et séparateurs. `Scheme/Borders` : le noir de marque à 10 %.
    public static let separator = Color(hex: 0x2B231B, opacity: 0.1)

    /// Bordure neutre d'un champ au repos. `Brand Colors/Grey`.
    public static let border = Color(hex: 0xC8C8C8)

    // MARK: Retours système
    //
    // Ces couleurs ne servent qu'aux statuts et aux messages, jamais à la
    // décoration. `agents/design.md` définit aussi une variante douce pour
    // chacune ; seule celle d'erreur est reprise ici, faute d'usage pour les
    // autres.

    /// État « enregistrement en cours », et rien d'autre. Jamais un lien,
    /// jamais un CTA — c'est le voyant du micro qui s'allume.
    public static let recording = Color(hex: 0xEB5757)

    public static let valid = Color(hex: 0x27AE60)
    public static let warning = Color(hex: 0xFFBC39)
    public static let error = Color(hex: 0xEB5757)

    /// Fond des bandeaux d'erreur. `Semantic/Danger Soft`.
    public static let errorSoft = Color(hex: 0xFBDDDD)
}

/// Espacements, rayons et tailles de contrôle, **tous en rem**.
///
/// Les valeurs viennent des maquettes Figma et des conventions iOS (HIG).
/// Voir `docs/ui-development.md` §2.2 pour l'échelle complète.
public enum MemoBookSpacing {
    /// 0.5 rem — espacement interne serré.
    public static let xs = rem(0.5)
    /// 1 rem — l'unité de base.
    public static let s = rem(1)
    /// 1.5 rem — gouttière entre blocs.
    public static let m = rem(1.5)
    /// 2 rem — espacement entre sections.
    public static let l = rem(2)
    /// 2.5 rem — grand espacement vertical.
    public static let xl = rem(2.5)

    /// Marge horizontale unique de tous les écrans : **1 rem**.
    ///
    /// Les maquettes hésitaient entre 1 et 1.5 rem ; c'est 1 rem qui a été
    /// retenu — la marge standard du mobile, et la plus généreuse en largeur de
    /// contenu. Décision D2 de `docs/ui-development.md`.
    public static let screenMargin = rem(1)

    /// Rayon des cartes et des champs (Figma : 20).
    public static let cornerRadius = rem(1.25)

    /// Rayon des boutons (Figma : 16).
    public static let buttonCornerRadius = rem(1)

    /// Rayon d'un fond d'icône (Figma : 13, arrondi sur l'échelle).
    public static let iconBackgroundRadius = rem(0.75)

    /// Hauteur d'un bouton primaire ou d'un champ de saisie (Figma : 48).
    ///
    /// Pour un contrôle qui doit grandir avec le Dynamic Type, préférer
    /// `@ScaledMetric(relativeTo: .body) var unit = Rem.base` puis `unit * 3`.
    public static let controlHeight = rem(3)

    /// Taille minimale d'une cible tactile (HIG : 44 pt).
    public static let minimumTapTarget = rem(2.75)
}

/// Les typographies de l'app.
///
/// Deux familles : **Sora** pour les titres et les chiffres, **General Sans**
/// pour tout le reste. Les tailles sont exprimées en rem et déclarées avec
/// `relativeTo:`, ce qui conserve le Dynamic Type.
///
/// > ⚠️ Les fichiers de police ne sont pas encore embarqués dans l'app — voir
/// > `ios/App/Resources/Fonts/README.md`. Tant qu'ils manquent, iOS retombe
/// > silencieusement sur la police système : la mise en page est juste, seul le
/// > dessin des lettres diffère. Rien d'autre à faire le jour où les fichiers
/// > arrivent.
public enum MemoBookFont {
    /// Les noms PostScript attendus par `Font.custom`. À ne pas deviner : ils
    /// se lisent dans le Livre des polices une fois les fichiers installés.
    public enum Family {
        public static let titleBold = "Sora-Bold"
        public static let titleSemibold = "Sora-SemiBold"
        public static let textRegular = "GeneralSans-Regular"
        public static let textMedium = "GeneralSans-Medium"
        public static let textSemibold = "GeneralSans-Semibold"
    }

    /// Titre d'écran : Sora Bold 2 rem.
    public static let screenTitle = Font.custom(Family.titleBold, size: rem(2), relativeTo: .largeTitle)

    /// Titre de bloc ou de carte : General Sans Semibold 1 rem.
    public static let sectionTitle = Font.custom(Family.textSemibold, size: rem(1), relativeTo: .headline)

    /// Texte courant : General Sans Regular 1 rem.
    public static let body = Font.custom(Family.textRegular, size: rem(1), relativeTo: .body)

    /// Libellé de bouton : General Sans Medium 1 rem.
    public static let button = Font.custom(Family.textMedium, size: rem(1), relativeTo: .body)

    /// Pastille, tagline : General Sans Medium 0.875 rem.
    public static let tagline = Font.custom(Family.textMedium, size: rem(0.875), relativeTo: .subheadline)

    /// Description secondaire, légende : General Sans Regular 0.75 rem.
    public static let caption = Font.custom(Family.textRegular, size: rem(0.75), relativeTo: .footnote)

    /// Chiffre d'une pastille numérotée : Sora SemiBold 1 rem.
    public static let badge = Font.custom(Family.titleSemibold, size: rem(1), relativeTo: .body)

    /// Titres de **carnet** uniquement, jamais les titres d'écran système : un
    /// carnet ne se lit pas comme une barre de navigation.
    ///
    /// TODO(design) — le carnet imprimé a ses propres polices (Playfair
    /// Display, Gloria Hallelujah). Reste à décider si l'aperçu dans l'app les
    /// reprend ; en attendant, le serif système en tient lieu.
    public static func bookTitle(_ size: CGFloat = rem(1.75)) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// Transcription brute : le monospace signale « pas encore mis en forme ».
    public static let transcript = Font.system(.callout, design: .monospaced)
}
