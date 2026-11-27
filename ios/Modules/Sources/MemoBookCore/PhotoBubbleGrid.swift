import Foundation

/// **Comment une bulle range ses photos** (T305, Hugo — « les photos en nombre
/// impair se rangent comme sur WhatsApp : toute la largeur de la bulle
/// occupée, chacune au format qu'elle a »).
///
/// La bulle les posait toutes dans le même carré, et laissait un **trou** à la
/// dernière place quand elles étaient en nombre impair. Une photo portrait y
/// était rognée en carré, une panoramique aussi, et le trou se lisait comme
/// une photo qui manque.
///
/// La règle tient en deux temps :
///
/// 1. **deux par rangée**, jamais trois — à trois, une vignette tombe sous la
///    largeur d'un pouce sur un iPhone SE ; et la dernière, si elle est seule,
///    prend **toute la largeur** au lieu de laisser la place vide ;
/// 2. **une rangée remplit la largeur**, et ses photos y gardent leur format :
///    la hauteur commune se déduit de la somme de leurs rapports largeur sur
///    hauteur. C'est la mise en page « justifiée » des galeries, celle que
///    WhatsApp emploie.
///
/// ⚠️ **Les formats viennent du serveur** (`photoWidthPx`, `photoHeightPx`),
/// pas de l'image chargée : une hauteur de bulle qui se découvre au chargement
/// ferait sauter tout ce qui la suit dans le fil — le défaut que T295 et T313
/// ont chassé. Une photo sans mesure compte pour un carré.
public enum PhotoBubbleGrid {
    /// Deux par rangée, jamais trois.
    public static let maximumPerRow = 2

    /// Le rapport d'une photo sans mesure : un carré, comme la bulle faisait
    /// de toutes avant T305.
    public static let squareAspect: Double = 1

    /// Les rangées, par rangs de photos.
    ///
    /// Un nombre impair ne laisse plus de trou : c'est la **dernière** rangée
    /// qui n'a qu'une photo, et elle prend toute la largeur.
    public static func rows(of count: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        return stride(from: 0, to: count, by: maximumPerRow).map { start in
            start..<min(start + maximumPerRow, count)
        }
    }

    /// La hauteur d'une rangée qui remplit `width`, formats compris.
    ///
    /// - Parameters:
    ///   - aspects: le rapport largeur / hauteur de chaque photo de la rangée.
    ///   - width: la largeur utile de la bulle.
    ///   - spacing: l'espace entre deux photos d'une même rangée.
    ///   - maximum: la hauteur au-delà de laquelle on ne va pas — une photo
    ///     portrait seule prendrait sinon tout l'écran, et la bulle ne serait
    ///     plus une bulle.
    public static func rowHeight(
        aspects: [Double],
        width: Double,
        spacing: Double,
        maximum: Double
    ) -> Double {
        let usable = max(0, width - spacing * Double(max(0, aspects.count - 1)))
        let total = aspects.map { $0 > 0 ? $0 : squareAspect }.reduce(0, +)
        guard total > 0, usable > 0 else { return 0 }
        return min(maximum, usable / total)
    }

    /// Les largeurs d'une rangée, à la hauteur donnée.
    ///
    /// La dernière prend ce qui reste : à l'arrondi près, trois divisions ne
    /// retombent pas sur la largeur de la bulle, et un cheveu de fond entre la
    /// photo et le bord se verrait.
    public static func widths(
        aspects: [Double],
        height: Double,
        width: Double,
        spacing: Double
    ) -> [Double] {
        guard !aspects.isEmpty else { return [] }
        let kept = aspects.map { $0 > 0 ? $0 : squareAspect }
        var widths = kept.map { $0 * height }
        let gaps = spacing * Double(kept.count - 1)
        let last = width - gaps - widths.dropLast().reduce(0, +)
        if last > 0 { widths[widths.count - 1] = last }
        return widths
    }
}
