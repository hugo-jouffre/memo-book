import SwiftUI

/// L'unité de mesure de l'app. 1 rem = 16 pt, comme la racine typographique de
/// Figma (`Text Sizes/Text Regular` = 16, `Size/medium` = 16).
///
/// C'est le SEUL endroit de l'app où un point apparaît. Toute vue mesure en rem
/// — voir `docs/ui-development.md` §2.
///
/// SwiftUI n'a pas de notion de `rem` : c'est une unité web. On ne peut donc pas
/// « écrire du rem » littéralement dans une vue, on la définit ici et plus
/// aucune vue ne manipule autre chose. L'intention — une échelle relative à une
/// racine unique — est respectée ; seule la syntaxe diffère.
public enum Rem {
    public static let base: CGFloat = 16

    /// Convertit une valeur en rem vers des points. **Structure fixe
    /// uniquement** (marges d'écran, gouttières, rayons) : ne suit pas Dynamic
    /// Type. Ce qui doit grandir avec le texte passe par `@ScaledMetric` —
    /// `MemoBookMetric` en donne la base.
    public static func pt(_ value: CGFloat) -> CGFloat { value * base }
}

/// Raccourci de lecture : `rem(1.5)` plutôt que `24`.
public func rem(_ value: CGFloat) -> CGFloat { Rem.pt(value) }

/// La base du rem, mise à l'échelle par Dynamic Type.
///
/// À déclarer dans une vue dont une dimension doit suivre la taille de texte de
/// l'utilisateur — hauteur de bouton ou de champ, taille d'icône accolée à du
/// texte, cible tactile :
///
/// ```swift
/// @ScaledMetric(relativeTo: .body) private var unit: CGFloat = MemoBookMetric.unit
/// // …
/// .frame(minHeight: unit * 3)   // 3 rem, qui grandit en accessibilité
/// ```
public enum MemoBookMetric {
    /// La valeur à donner à un `@ScaledMetric`.
    public static let unit: CGFloat = Rem.base

    /// Cible tactile minimale (HIG). 2.75 rem.
    public static let minimumTapTarget: CGFloat = 2.75
}

/// Un trait. **Seule exception à la règle du rem** : bordures et séparateurs
/// restent en points (`Stroke/Border Width` = 1). Un filet ne grossit pas avec
/// le texte — c'est la convention iOS, et une bordure mise à l'échelle devient
/// un cadre.
public enum MemoBookStroke {
    public static let border: CGFloat = 1
}
