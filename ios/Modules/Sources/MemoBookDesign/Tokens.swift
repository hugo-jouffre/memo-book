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

    /// État « enregistrement en cours », et rien d'autre. Jamais un lien,
    /// jamais un CTA — c'est le voyant du micro qui s'allume. La convention
    /// iOS (Dictaphone) l'emporte ici sur la palette de marque.
    public static let recording = Color(uiColor: .systemRed)

    /// Texte principal, un noir chaud. — Figma `Brand Colors/Black`,
    /// aussi `Scheme/Text`.
    public static let ink = Color(hex: 0x2D231A)

    /// Texte secondaire, légendes. — Figma `Grays/Gray`.
    public static let inkSecondary = Color(hex: 0x8E8E93)

    /// Fond des écrans, le crème de la marque. — Figma
    /// `Scheme/Background Light`.
    public static let background = Color(hex: 0xFCF2E9)

    /// Cartes et zones de contenu. — Figma `Brand Colors/White`.
    public static let surface = Color(hex: 0xFFFCF8)

    /// Bordures des cartes et pastilles numérotées. — Figma
    /// `Brand Colors/Blue`.
    public static let outline = Color(hex: 0xAFD2F0)

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

    /// **La** hauteur d'un appel à l'action. Tous les CTA de l'app la
    /// partagent — « Continuer », « Continuer avec Apple », « Continuer avec
    /// Google » — pour qu'une pile de boutons se lise comme une pile et non
    /// comme trois contrôles différents.
    ///
    /// Valeur intermédiaire assumée : au-dessus des 48 pt que donnent le
    /// libellé et ses marges dans le design system, en dessous des 72 pt
    /// qu'atteignaient les boutons des fournisseurs tiers.
    public static let controlHeight: CGFloat = 56

    /// Hauteur d'un champ de saisie, alignée sur celle des CTA : formulaire et
    /// boutons forment une seule colonne de contrôles de même gabarit.
    public static let fieldHeight: CGFloat = controlHeight
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

    /// Même accroche, en graisse courante : pour les intitulés qui séparent
    /// deux blocs sans devoir peser autant qu'un titre (« Ou continue avec »).
    public static let taglineRegular = Font.custom(BrandFonts.generalSansRegular, size: 14, relativeTo: .subheadline)

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

    /// Titres de **carnet** uniquement, jamais les titres d'écran système.
    public static func bookTitle(_ size: CGFloat = 28) -> Font {
        .custom(BrandFonts.soraSemiBold, size: size, relativeTo: .title)
    }

    public static let screenTitle = h1

    /// Transcription brute : le monospace signale « pas encore mis en forme ».
    public static let transcript = Font.system(.callout, design: .monospaced)
}
