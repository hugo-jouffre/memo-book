import SwiftUI

/// Les pictogrammes empruntés à [Lucide](https://lucide.dev), là où le jeu de
/// marque n'a rien à proposer.
///
/// **Ce sont des remplaçants, et le nom le dit.** Le jeu de marque compte
/// trente-cinq icônes ; aucune ne représente un *type de voyage* (tour du
/// monde, randonnée, road trip) ni un *mode de transport*. Plutôt que
/// d'inventer une icône ou d'en détourner une, on prend celles d'une
/// bibliothèque libre — licence ISC, voir
/// `assets/icons/lucide-icons/README.md`, qui porte aussi le script d'import.
/// C'est une exception assumée à la règle R10 de `docs/ui-development.md`, et
/// le jour où Clara dessine la série, seule cette table change.
///
/// **La clé est celle de la source**, pas celle d'un asset iOS : c'est le nom
/// du fichier Lucide. Elle vient de la base pour les catégories de la galerie
/// (`gallery_categories.iconKey`) et du code pour les filtres d'un voyage. Une
/// clé que cette table ne connaît pas retombe sur la boussole, et la pastille
/// s'affiche quand même — une catégorie ajoutée en base n'attend donc pas la
/// prochaine version de l'app.
public enum LucideIcon {
    /// Les clés que l'app sait dessiner.
    public static let known: Set<String> = [
        "backpack",
        "bike",
        "building-2",
        "car-front",
        "compass",
        "footprints",
        "globe",
        "heart",
        "mountain-snow",
        "palmtree",
        "sailboat",
        "tent-tree",
        "train-front",
        "users",
        "utensils",
    ]

    /// Ce qu'on met quand on ne sait pas : une boussole. Neutre, et qui ne ment
    /// sur aucune catégorie.
    public static let fallback = "compass"

    /// Le pictogramme d'une clé. Toujours une image : il n'y a pas de cas où
    /// une pastille se retrouve sans rien à gauche de son libellé.
    public static func image(_ key: String?) -> Image {
        Image(brand: assetName(for: key))
    }

    /// « mountain-snow » → `IconLucideMountainSnow`. La même règle que
    /// `ios/Tools/import-lucide-icons.py`, et un test le vérifie : les deux
    /// noms se calculent des deux côtés, ils ne se recopient pas.
    static func assetName(for key: String?) -> String {
        let resolved = key.map { known.contains($0) ? $0 : fallback } ?? fallback

        let words = resolved.split(whereSeparator: { $0 == "-" || $0 == "_" })
        return "IconLucide" + words.map { $0.capitalized }.joined()
    }
}
