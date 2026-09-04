import SwiftUI
import UIKit

// Palette et typographie de la marque, reprises des variables Figma du fichier
// « MemoBook — Product ». Ce fichier est la seule source de vérité : aucune
// couleur ni police n'est codée en dur ailleurs dans l'app.
//
// Les couleurs sont volontairement **fixes** et non adaptatives. MemoBook est
// un carnet de papier crème : basculer en sombre retournerait la marque plutôt
// que de la servir. Les écrans qui utilisent cette palette forcent donc
// `.colorScheme(.light)`.

private extension Color {
    /// `#rrggbb` → couleur sRGB. Les valeurs viennent des variables Figma,
    /// autant les garder lisibles telles quelles dans le code.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Couleurs de l'app. Noms Figma en commentaire de chaque token.
public enum MemoBookColor {
    /// Couleur d'action : boutons primaires, liens, sélection, teinte de
    /// navigation. — Figma `Brand Colors/Green`.
    public static let action = Color(hex: 0x28654B)

    /// Vert clair de la marque : les signaux discrets, là où le vert du CTA
    /// serait trop appuyé. — Figma `Brand Colors/Green Lighter`, relevé sur le
    /// nœud de l'accueil.
    public static let actionLight = Color(hex: 0x3D9A6F)

    /// État « enregistrement en cours », et rien d'autre. Jamais un lien,
    /// jamais un CTA — c'est le voyant du micro qui s'allume. La convention
    /// iOS (Dictaphone) l'emporte ici sur la palette de marque.
    public static let recording = Color(uiColor: .systemRed)

    /// Texte principal, un noir chaud. — Figma `Brand Colors/Black`,
    /// aussi `Scheme/Text`.
    public static let ink = Color(hex: 0x2D231A)

    /// Texte secondaire, légendes. — Figma `Grays/Gray`.
    ///
    /// Le gris **système** d'iOS. Il tient sur les écrans d'entrée dans l'app,
    /// mais ce n'est pas le gris de la marque : voir ``inkMuted``.
    public static let inkSecondary = Color(hex: 0x8E8E93)

    /// Texte secondaire de la marque : l'encre à 50 %, pas un gris neutre. Un
    /// gris tiré du noir chaud se pose sur le crème sans le refroidir, ce que
    /// le gris système fait. — Figma `Brand Colors/Grey Typo` (`#2B231B80`),
    /// relevé sur le nœud de l'accueil.
    public static let inkMuted = Color(hex: 0x2B231B).opacity(0.5)

    /// Fond des écrans, le crème de la marque. — Figma
    /// `Scheme/Background Light`.
    public static let background = Color(hex: 0xFCF2E9)

    /// Cartes et zones de contenu. — Figma `Brand Colors/White`.
    public static let surface = Color(hex: 0xFFFCF8)

    /// Bordures des cartes et pastilles numérotées. — Figma
    /// `Brand Colors/Blue`.
    public static let outline = Color(hex: 0xAFD2F0)

    /// Accent du scheme, très saturé. Il souligne un chiffre ou une pastille —
    /// jamais un aplat large, jamais un fond de bouton. — Figma
    /// `Scheme/Accent` (Lime).
    public static let accent = Color(hex: 0xE2F32B)

    /// Le filet qui sépare deux blocs dans une même carte : le noir de la
    /// marque à 10 %, pas un gris. — Figma `Scheme/Borders`.
    public static let hairline = Color(hex: 0x2B231B).opacity(0.1)

    /// Bleu assez soutenu pour porter du texte sur un aplat bleu clair.
    ///
    /// ⚠️ **Ce n'est pas encore une variable Figma.** `Brand Colors/Blue`
    /// (#AFD2F0) est un bleu d'aplat : posé en texte sur son propre fond clair,
    /// il tombe à 1,3:1 et devient illisible. Ces deux valeurs gardent sa
    /// teinte (209°) en montant la saturation et en baissant la clarté, ce qui
    /// donne 5,1:1 et 3,1:1 sur le fond de la carte de découverte. À faire
    /// entrer dans les variables Figma sous le nom qu'aura choisi Clara —
    /// voir T12 dans `docs/ui-development.md`.
    public static let blueText = Color(hex: 0x4780B3)
    public static let blueTextSoft = Color(hex: 0x74A6D0)

    /// Beige soutenu, pour les séparateurs et les aplats discrets. — Figma
    /// `Brand Colors/Beige Darker`.
    public static let separator = Color(hex: 0xCFBBAA)

    /// Aplat d'un contrôle désactivé. Volontairement gris et non teinté :
    /// « indisponible » ne doit pas ressembler à une couleur de marque.
    public static let disabled = Color(hex: 0xC3C3C7)

    /// Surfaces « carnet » : aperçu du livre, cartes de couverture.
    public static let paper = Color(hex: 0xFFFCF8)

    /// Texte posé sur `action` ou sur une surface sombre. — Figma
    /// `Brand Colors/White`.
    public static let onAction = Color(hex: 0xFFFCF8)

    // Couleurs sémantiques — retours système uniquement (statuts, messages),
    // jamais de la décoration.
    public static let valid = Color(hex: 0x28654B)
    public static let warning = Color(uiColor: .systemOrange)
    public static let error = Color(uiColor: .systemRed)
}

/// Échelle d'espacement de 8 pt, plus les marges de référence.
public enum MemoBookSpacing {
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 16
    public static let m: CGFloat = 24
    public static let l: CGFloat = 32
    public static let xl: CGFloat = 40

    /// **La** marge horizontale de l'app. Tout ce qui touche le bord d'un
    /// écran — texte, cartes, boutons, listes — s'aligne dessus, sans
    /// exception : c'est cet alignement unique qui fait qu'un écran se lit
    /// comme une colonne et pas comme un empilement de blocs.
    ///
    /// La changer ici la change partout. Aucun écran ne doit coder sa propre
    /// marge latérale.
    public static let screenMargin: CGFloat = 24

    /// Rayon des champs et des cartes.
    public static let cornerRadius: CGFloat = 14

    /// Rayon des cartes de la page d'accueil et du bouton principal.
    public static let largeCornerRadius: CGFloat = 20

    /// Taille minimale d'une cible tactile.
    public static let minimumTapTarget: CGFloat = 44

    /// Hauteur d'un champ de saisie. Plus haute qu'un bouton (48) : le champ
    /// doit loger son étiquette flottante en plus de son texte.
    public static let fieldHeight: CGFloat = 56
}

/// Typographies de la marque : Sora pour les titres, General Sans pour tout le
/// reste. Les deux sont embarquées dans ce module (voir `BrandFonts`).
///
/// Chaque style passe par `relativeTo:` pour suivre le Dynamic Type : les
/// tailles ci-dessous sont celles de la maquette à la taille système par
/// défaut, et grandissent avec les réglages d'accessibilité.
public enum MemoBookFont {
    /// Interlettrage de la maquette : 1 % de la taille du corps.
    public static func tracking(_ size: CGFloat) -> CGFloat { size * 0.01 }

    /// Titre d'écran. — Figma `App/h1` (Sora SemiBold 32).
    public static let h1 = Font.custom(BrandFonts.soraSemiBold, size: 32, relativeTo: .largeTitle)

    /// Pastille d'accroche. — Figma `App/pastille notes` (General Sans Semibold 14).
    public static let tagline = Font.custom(BrandFonts.generalSansSemibold, size: 14, relativeTo: .subheadline)

    /// Corps de texte accentué. — Figma `App/body semibold` (General Sans Semibold 16).
    public static let bodySemibold = Font.custom(BrandFonts.generalSansSemibold, size: 16, relativeTo: .body)

    /// Corps de texte courant (General Sans Regular 16).
    public static let body = Font.custom(BrandFonts.generalSansRegular, size: 16, relativeTo: .body)

    /// Texte secondaire des cartes (General Sans Regular 12).
    public static let caption = Font.custom(BrandFonts.generalSansRegular, size: 12, relativeTo: .caption)

    /// Libellé des boutons. Le composant versionné du design system dit Sora
    /// SemiBold 16, interligne 1,5 — ce sont ces 24 pt de ligne qui donnent au
    /// bouton sa hauteur de 48. L'écran d'accueil, lui, surcharge son instance
    /// en General Sans Medium : c'est la définition du composant qui fait foi.
    public static let button = Font.custom(BrandFonts.soraSemiBold, size: 16, relativeTo: .body)

    /// Titres de section dans les écrans système.
    public static let sectionTitle = Font.custom(BrandFonts.generalSansSemibold, size: 17, relativeTo: .headline)

    /// Salutation de l'accueil : « Bienvenue Camille ». Plus petite qu'un
    /// titre d'écran, parce qu'elle partage sa ligne avec l'avatar. —
    /// `Heading 5` (24).
    ///
    /// General Sans **Regular** et non Sora : la salutation s'adresse, elle ne
    /// titre pas. Sora reste aux titres de section et de carte.
    public static let greeting = Font.custom(BrandFonts.generalSansRegular, size: 24, relativeTo: .title2)

    /// Titre d'une section de l'accueil, et titre d'une carte de voyage. —
    /// `Heading 6` / `Text Large` (20).
    public static let heading = Font.custom(BrandFonts.soraSemiBold, size: 20, relativeTo: .title3)

    /// Ligne de métadonnées : dates, compteurs, sous-titres de carte. —
    /// `Text Small` (14).
    public static let label = Font.custom(BrandFonts.generalSansMedium, size: 14, relativeTo: .subheadline)

    /// Surtitre en capitales et pastilles d'état. — `Text Tiny` (12).
    public static let overline = Font.custom(BrandFonts.generalSansSemibold, size: 12, relativeTo: .caption)

    /// Titres de **carnet** uniquement, jamais les titres d'écran système.
    public static func bookTitle(_ size: CGFloat = 28) -> Font {
        .custom(BrandFonts.soraSemiBold, size: size, relativeTo: .title)
    }

    public static let screenTitle = h1

    /// Transcription brute : le monospace signale « pas encore mis en forme ».
    public static let transcript = Font.system(.callout, design: .monospaced)
}
