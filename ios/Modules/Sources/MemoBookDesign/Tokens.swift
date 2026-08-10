import SwiftUI
import UIKit

// ⚠️⚠️  PALETTE PROVISOIRE — À REMPLACER  ⚠️⚠️
//
// Les couleurs de l'app et des mises en page vont changer prochainement.
// En attendant cette nouvelle palette, aucun token ci-dessous ne porte de
// couleur de marque : ils pointent tous vers des couleurs système iOS.
//
// C'est délibéré. L'app est utilisable et cohérente, mais visiblement NON
// BRANDÉE — personne ne peut confondre ces valeurs avec le design final, et on
// ne fige pas une palette qu'on sait déjà fausse.
//
// Ce que ce fichier n'est PAS : il ne reprend ni `agents/design.md` (Carrot,
// Forest Green, Beige…), ni `memobook-design.md` du Drive. Les deux se
// contredisent, et les deux vont être remplacés.
//
// ➡️ Le jour venu : remplacer les valeurs `TODO` de ce seul fichier. Aucune
//    couleur n'est codée en dur ailleurs dans l'app — c'est ce qui rend la
//    bascule triviale.

/// Couleurs de l'app. **Toutes provisoires**, voir l'avertissement ci-dessus.
public enum MemoBookColor {
    /// Couleur d'action : boutons primaires, liens, sélection, teinte de
    /// navigation.
    ///
    /// TODO(design) — à définir. Quelle couleur porte l'action principale ?
    /// C'est le seul arbitrage qui compte vraiment : `agents/design.md` dit
    /// Carrot, le doc Drive dit vert. Trancher, puis remplacer ici.
    public static let action = Color(uiColor: .systemBlue)

    /// État « enregistrement en cours », et rien d'autre. Jamais un lien,
    /// jamais un CTA — c'est le voyant du micro qui s'allume.
    ///
    /// TODO(design) — à définir. Le rouge système est la convention iOS
    /// (Dictaphone) : c'est un placeholder qui a du sens, pas un choix figé.
    public static let recording = Color(uiColor: .systemRed)

    /// Texte principal. TODO(design) — à définir (un noir chaud, jamais `#000`).
    public static let ink = Color(uiColor: .label)

    /// Texte secondaire, légendes. TODO(design) — à définir.
    public static let inkSecondary = Color(uiColor: .secondaryLabel)

    /// Fond des écrans. TODO(design) — à définir.
    public static let background = Color(uiColor: .systemGroupedBackground)

    /// Cartes et zones de contenu. TODO(design) — à définir.
    public static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    public static let separator = Color(uiColor: .separator)

    /// Surfaces « carnet » : aperçu du livre, cartes de couverture.
    /// C'est ici que viendra le fond papier de la marque.
    ///
    /// TODO(design) — à définir.
    public static let paper = Color(uiColor: .tertiarySystemGroupedBackground)

    // Couleurs sémantiques — retours système uniquement (statuts, messages),
    // jamais de la décoration.
    //
    // TODO(design) — à définir.
    public static let valid = Color(uiColor: .systemGreen)
    public static let warning = Color(uiColor: .systemOrange)
    public static let error = Color(uiColor: .systemRed)
}

/// Échelle d'espacement de 8 pt, plus la marge latérale de référence.
///
/// Ces valeurs-là viennent des conventions iOS (HIG) et de la critique design,
/// pas d'un choix de marque : elles sont stables et n'attendent rien.
public enum MemoBookSpacing {
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 16
    public static let m: CGFloat = 24
    public static let l: CGFloat = 32
    public static let xl: CGFloat = 40

    /// Marge horizontale unique de tous les écrans.
    public static let screenMargin: CGFloat = 20

    /// Rayon unique des champs et des cartes.
    public static let cornerRadius: CGFloat = 14

    /// Taille minimale d'une cible tactile.
    public static let minimumTapTarget: CGFloat = 44
}

/// Typographies. **Provisoires elles aussi** : le README du dépôt les liste
/// comme « à documenter dès qu'elles sont figées en Phase 2/3 ».
///
/// En attendant, tout passe par les styles système (SF), qui donnent le Dynamic
/// Type et l'accessibilité gratuitement. Seule distinction conservée : les
/// titres de **carnet** utilisent un serif, parce que c'est une décision
/// éditoriale déjà actée — un carnet ne se lit pas comme du chrome système.
public enum MemoBookFont {
    /// Titres de **carnet** uniquement, jamais les titres d'écran système.
    ///
    /// TODO(design) — remplacer le serif système par la police de marque.
    public static func bookTitle(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    public static let screenTitle = Font.system(.largeTitle, weight: .bold)
    public static let sectionTitle = Font.system(.headline)
    public static let body = Font.system(.body)
    public static let caption = Font.system(.footnote)

    /// Transcription brute : le monospace signale « pas encore mis en forme ».
    public static let transcript = Font.system(.callout, design: .monospaced)
}
