import Foundation

/// Les textes de l'écran d'entrée, recopiés du nœud Figma
/// « Accueil - 1ère Connexion » (`3420:10409`) au caractère près — apostrophes
/// typographiques comprises (R8).
///
/// La mention légale vouvoyait dans la maquette (« vous acceptez ») ; Figma
/// tutoie depuis, et l'app suit (Hugo, 17/09/2026, T113).
enum WelcomeCopy {
    /// Le titre se lit en deux temps, comme ceux du paywall : la moitié
    /// courante à l'encre, la chute en vert et en gras.
    static let titleLead = "Raconte tes histoires, "
    static let titleStrong = "on s’occupe du reste."

    static let subtitle =
        "Crée ton journal de voyage à l'oral ou à l'écrit, et reçois un magnifique carnet imprimé !"

    /// Les trois temps du produit, sous les trois icônes de la marque.
    ///
    /// **Les bichromes** (`…Duo`), et non les traits d'encre qu'on pose
    /// ailleurs : cet écran est une vitrine, pas une barre d'outils. Le bleu
    /// d'aplat de la marque les fait ressortir sur le crème de la carte, et il
    /// les tient ensemble — c'est pour ça qu'aucune des trois ne reste
    /// monochrome.
    ///
    /// ⚠️ **L'imprimante est la version pleine.** `IconPrinterDuo` dessine un
    /// contour ; le micro et le cadre photo, eux, sont pleins. Les trois côte à
    /// côte, ça se voit : l'imprimante paraissait vide au milieu des deux
    /// autres. `Printer Filled 2` la remplit comme ses voisines.
    struct Feature: Identifiable {
        let icon: String
        let label: String
        var id: String { label }
    }

    static let features: [Feature] = [
        Feature(icon: "IconMicDuo", label: "1. Raconte"),
        Feature(icon: "IconPictureFrameDuo", label: "2. Ajoute"),
        Feature(icon: "IconPrinterFilledDuo", label: "3. Reçois"),
    ]

    static let rating = "🌟 4.9/5"
    static let community = "Rejoint par 12 000+ voyageurs"

    static let hello = "Hello ! 👋"
    static let helloDetail = "Nous allons t'accompagner dans tes récits."

    /// Pas de libellé pour Apple : `SignInWithAppleButton(.continue)` écrit le
    /// sien, dans la langue de l'appareil et dans la typographie du système.
    /// Le recopier ici donnerait deux vérités pour un seul texte, dont une que
    /// personne ne lit.
    static let google = "Continuer avec Google"
    static let email = "S'inscrire avec un e-mail"
    static let legal = "En continuant, tu acceptes nos Conditions d'utilisation."

    /// La flèche de retour des écrans d'entrée par e-mail. Elle ramène ici, et
    /// c'est la seule sortie de ces écrans-là.
    static let back = "Retour"

    enum Voice {
        static let hero = "Des carnets de voyage MemoBook posés sur une table"
        static let rating = "Noté 4,9 sur 5, rejoint par plus de 12 000 voyageurs"
    }
}
