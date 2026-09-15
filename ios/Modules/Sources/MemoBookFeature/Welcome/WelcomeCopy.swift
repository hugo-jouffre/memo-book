import Foundation

/// Les textes de l'écran d'entrée, recopiés du nœud Figma
/// « Accueil - 1ère Connexion » (`3420:10409`) au caractère près — apostrophes
/// typographiques comprises (R8).
///
/// ⚠️ Deux phrases de la maquette **vouvoient** : le chapeau des boutons
/// (« Nous allons t'accompagner… » tutoie, lui) et la mention légale (« vous
/// acceptez nos Conditions d'utilisation »). R9 veut le tutoiement partout ;
/// R8 interdit de réécrire une maquette soi-même. Elles sont donc recopiées
/// telles quelles et remontées à Clara — voir la fiche écran.
enum WelcomeCopy {
    /// Le titre se lit en deux temps, comme ceux du paywall : la moitié
    /// courante à l'encre, la chute en vert et en gras.
    static let titleLead = "Raconte tes histoires, "
    static let titleStrong = "on s’occupe du reste."

    static let subtitle =
        "Crée ton journal de voyage à l'oral ou à l'écrit, et reçois un magnifique carnet imprimé !"

    /// Les trois temps du produit, sous les trois icônes de la marque.
    struct Feature: Identifiable {
        let icon: String
        let label: String
        var id: String { label }
    }

    static let features: [Feature] = [
        Feature(icon: "IconMic", label: "1. Raconte"),
        Feature(icon: "IconPictureFrame", label: "2. Ajoute"),
        Feature(icon: "IconPrinter", label: "3. Reçois"),
    ]

    static let rating = "🌟 4.9/5"
    static let community = "Rejoint par 12 000+ voyageurs"

    static let hello = "Hello ! 👋"
    static let helloDetail = "Nous allons t'accompagner dans tes récits."

    static let apple = "Continuer avec Apple"
    static let google = "Continuer avec Google"
    static let email = "S'inscrire avec un e-mail"
    static let legal = "En continuant, vous acceptez nos Conditions d'utilisation."

    /// La flèche de retour des écrans d'entrée par e-mail. Elle ramène ici, et
    /// c'est la seule sortie de ces écrans-là.
    static let back = "Retour"

    enum Voice {
        static let hero = "Des carnets de voyage MemoBook posés sur une table"
        static let rating = "Noté 4,9 sur 5, rejoint par plus de 12 000 voyageurs"
    }
}
