import SwiftUI

// La palette est tranchée (décision D1 de `docs/ui-development.md` §7.1). Les
// valeurs ci-dessous recopient les variables du fichier Figma
// « MemoBook — Product », telles que les écrans les résolvent — pas telles que
// la page *Design System* les affiche, qui est encore sur le mode par défaut du
// template acheté.
//
// Carrot, Carrot Darker, Forest Green et Kiwi n'existent plus.
//
// ⚠️ Aucune couleur en dur ailleurs dans l'app. Si un token manque, il s'ajoute
//    ici d'abord, et la vue s'écrit ensuite.

/// Les couleurs de marque, recopiées des variables Figma `Brand Colors/*`.
public enum MemoBookBrand {
    /// #28654B — l'action principale : CTA, bordure et texte de la tagline.
    public static let green = Color(hex: 0x28654B)

    /// #E2F32B — `Scheme/Accent`. Très saturé : mise en valeur ponctuelle
    /// (surlignage, sélection, badge), jamais du texte sur grande surface.
    public static let lime = Color(hex: 0xE2F32B)

    /// #AFD2F0 — l'accent illustratif de l'onboarding : bordures de cartes,
    /// pastilles numérotées, fonds d'icônes (à 30 %).
    public static let blue = Color(hex: 0xAFD2F0)

    /// #FCF2E9 — le fond des écrans.
    public static let beige = Color(hex: 0xFCF2E9)

    /// #CFBBAA
    public static let beigeDarker = Color(hex: 0xCFBBAA)

    /// #2D231A — le texte principal. Un noir chaud, jamais #000000.
    public static let black = Color(hex: 0x2D231A)

    /// #FFFCF8 — les surfaces : cartes, champs. Un blanc chaud, jamais #FFFFFF.
    public static let white = Color(hex: 0xFFFCF8)

    /// #C8C8C8 — bordures neutres, et le fond d'un CTA désactivé.
    public static let grey = Color(hex: 0xC8C8C8)

    /// #8E8E93 — `Grays/Gray`, le gris système iOS : texte secondaire et
    /// placeholders.
    public static let gray = Color(hex: 0x8E8E93)
}

/// Couleurs de l'app, par rôle. C'est cette table que les vues emploient —
/// jamais `MemoBookBrand` directement, sauf quand le rôle *est* la couleur
/// (l'accent illustratif de l'onboarding, par exemple).
public enum MemoBookColor {
    /// Couleur d'action : boutons primaires, liens, sélection, teinte de
    /// navigation.
    public static let action = MemoBookBrand.green

    /// Action indisponible : le CTA reste visible mais ne promet rien.
    public static let actionDisabled = MemoBookBrand.grey

    /// État « enregistrement en cours », et rien d'autre. Jamais un lien,
    /// jamais un CTA — c'est le voyant du micro qui s'allume.
    ///
    /// La palette de marque n'a pas de rouge : c'est `Semantic/Danger`, la seule
    /// couleur sémantique dont le rôle soit ici visuel plutôt que système.
    public static let recording = MemoBookColor.error

    /// Texte principal.
    public static let ink = MemoBookBrand.black

    /// Texte secondaire, légendes, placeholders.
    public static let inkSecondary = MemoBookBrand.gray

    /// Texte posé sur une surface d'action.
    public static let onAction = MemoBookBrand.white

    /// Fond des écrans.
    public static let background = MemoBookBrand.beige

    /// Cartes, champs et zones de contenu.
    public static let surface = MemoBookBrand.white

    /// `Scheme/Borders` — le noir de marque à 10 %.
    public static let separator = MemoBookBrand.black.opacity(0.1)

    /// Bordure d'un champ au repos.
    public static let fieldBorder = MemoBookBrand.grey

    /// Bordure d'un champ actif : le vert d'action, adouci.
    public static let fieldBorderFocused = MemoBookBrand.green.opacity(0.5)

    /// L'accent illustratif de l'onboarding : bordures des cartes bénéfices et
    /// pastilles numérotées.
    public static let illustration = MemoBookBrand.blue

    /// Fond des pastilles d'icône des cartes bénéfices.
    public static let illustrationSoft = MemoBookBrand.blue.opacity(0.3)

    /// Surfaces « carnet » : aperçu du livre, cartes de couverture.
    public static let paper = MemoBookBrand.beige

    // Couleurs sémantiques — retours système uniquement (statuts, messages),
    // jamais de la décoration. Recopiées de `agents/design.md` § Semantic.

    public static let info = Color(hex: 0x435AD8)
    public static let infoSoft = Color(hex: 0xD9DEF7)
    public static let valid = Color(hex: 0x27AE60)
    public static let validSoft = Color(hex: 0xBEE7CF)
    public static let warning = Color(hex: 0xFFBC39)
    public static let warningSoft = Color(hex: 0xFFF2D7)
    public static let error = Color(hex: 0xEB5757)
    public static let errorSoft = Color(hex: 0xFBDDDD)
}

/// Échelle d'espacement, en rem (`docs/ui-development.md` §2.2).
///
/// Ces valeurs viennent des variables Figma `Size/*` et des conventions iOS —
/// elles ne bougeront plus.
public enum MemoBookSpacing {
    /// 0.5 rem — espacement interne serré (titre ↔ sous-titre).
    public static let xs = rem(0.5)
    /// 1 rem — l'unité de base : marge d'écran, gouttière entre champs.
    public static let s = rem(1)
    /// 1.5 rem — gouttière entre blocs.
    public static let m = rem(1.5)
    /// 2 rem — espacement entre blocs (`Size/xlarge`).
    public static let l = rem(2)
    /// 2.5 rem — grand espacement vertical.
    public static let xl = rem(2.5)

    /// **La marge horizontale de tous les écrans, sans exception** — 1 rem.
    /// Décision D2 : les maquettes divergeaient (1 rem sur *Sign Up*, 1.5 rem
    /// sur *Welcome*), c'est la marge standard du mobile qui l'emporte.
    public static let screenMargin = rem(1)

    /// Rayon des champs, des boutons et du sélecteur — 0.875 rem (14).
    ///
    /// Relevé au `get_design_context` sur *Sign Up*, *Login* et *Mdp oublié* :
    /// les trois portent 14. Le §2.3 de `ui-development.md` annonçait 1 rem
    /// d'après un relevé plus ancien ; par R4, la valeur lue sur le nœud gagne.
    public static let cornerRadius = rem(0.875)

    /// Rayon des cartes et des pastilles — 1.25 rem (20).
    public static let cardCornerRadius = rem(1.25)

    /// Rayon d'un fond d'icône — 0.75 rem (Figma dessine 13 → arrondi R2).
    public static let iconCornerRadius = rem(0.75)

    /// Taille minimale d'une cible tactile — 2.75 rem (44), HIG.
    public static let minimumTapTarget = rem(2.75)
}

extension Color {
    /// Construit une couleur depuis un hexadécimal RVB, comme Figma l'écrit.
    ///
    /// Les couleurs de marque sont **fixes** : elles ne se déclinent pas encore
    /// en mode sombre. `Scheme/Background Dark` existe dans Figma, mais aucun
    /// écran ne le décline — le jour où Clara les dessine, c'est ici que la
    /// bascule s'écrira.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
