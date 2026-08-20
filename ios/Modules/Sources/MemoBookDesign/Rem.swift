import CoreGraphics

/// L'unité de mesure de l'app.
///
/// Toutes les dimensions de MemoBook s'expriment en **rem**, jamais en points :
/// espacements, tailles, rayons, hauteurs de contrôle. `1 rem = 16 pt`, ce qui
/// correspond à la racine typographique de Figma (`Text Sizes/Text Regular`).
///
/// SwiftUI ne connaît pas le rem — c'est une unité web. On la définit donc ici,
/// et **ce fichier est le seul endroit de l'app où un point apparaît**. Le
/// reste du code passe par `rem(_:)` ou par les tokens de `MemoBookSpacing`.
///
/// Deux régimes, à ne pas confondre (voir `docs/ui-development.md` §2.4) :
///
/// - **structure fixe** — marges d'écran, gouttières entre blocs, rayons :
///   `rem(1.5)`, qui ne bouge pas avec la taille de texte de l'utilisateur ;
/// - **éléments qui suivent le texte** — hauteur de bouton et de champ, taille
///   d'une icône accolée à du texte : `@ScaledMetric(relativeTo: .body) var
///   unit: CGFloat = Rem.base`, puis `unit * 3`.
///
/// Une seule exception à la règle : les **traits** (bordures, séparateurs)
/// restent en points. Un filet ne grossit pas avec le texte.
public enum Rem {
    /// La racine. 1 rem vaut 16 pt.
    public static let base: CGFloat = 16

    /// Convertit une valeur exprimée en rem vers des points.
    public static func pt(_ value: CGFloat) -> CGFloat { value * base }

    /// Épaisseur d'un trait, en points et non en rem (`Stroke/Border Width`).
    public static let hairline: CGFloat = 1
}

/// Raccourci de lecture : `rem(1.5)` plutôt que `24`.
///
/// À utiliser partout où une dimension est écrite en dur aujourd'hui.
public func rem(_ value: CGFloat) -> CGFloat { Rem.pt(value) }
