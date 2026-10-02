import Foundation

// L'aperçu de personnalisation : l'image qui surmonte l'écran
// « Personnalisations » et change à chaque réglage touché.
//
// Ce n'est pas l'aperçu du carnet (`BookPreview`, le PDF composé) : c'est une
// image **déjà rendue**, choisie parmi deux cents d'après cinq réglages. Ce
// fichier dit laquelle, et rien d'autre — ni où elle est hébergée, ni comment
// elle s'anime. `docs/apercu-personnalisation.md` fait foi.

/// Quelle image d'aperçu montrer pour un état du carnet.
///
/// Les noms disponibles sont une **donnée** — ``availableFileNames``, généré
/// depuis le dossier des visuels par
/// `ios/Tools/make-customisation-preview-manifest.py` —, pas un accès disque
/// dont on rattraperait l'échec : le choix se fait sans rien charger, et se
/// teste.
public enum BookCustomisationPreview {
    /// L'image de repli, dans le même dossier que les aperçus.
    ///
    /// **Sans cédille**, et c'est voulu : c'était le seul nom du dossier en
    /// Unicode décomposé, et le nom « évident » renvoyait un 404. L'ASCII le
    /// tient hors de portée du problème.
    public static let fallbackFileName = "apercu non existant.png"

    /// Le nom du fichier d'aperçu à afficher pour ce carnet.
    ///
    /// Cinq propriétés seulement le décident : `rulesEnabled`,
    /// `photoTextRatio`, `funFactsEnabled`, `decorationQuota`, et l'assortiment
    /// que forment les quatre polices. Le nombre de pages, le quiz, les zones
    /// libres et les mots fléchés n'y entrent pas — c'est ce qui permet à
    /// l'écran de ne recharger l'image que quand ce nom change.
    ///
    /// Le repli dans deux cas : un carnet « Personnalisé », dont les polices ne
    /// forment aucun des trois assortiments ; et une combinaison absente du
    /// manifeste.
    ///
    /// ⚠️ **Les pointillés sont lus tels quels.** La contrainte qui les éteint
    /// hors de l'assortiment par défaut vit en amont, sur l'écran : une fois
    /// posée, chaque état atteignable a son aperçu. Ne pas la redoubler ici —
    /// le jour où les rendus manquants arrivent, elle saute, et cette fonction
    /// ne doit pas avoir à bouger : relancer le script suffit. Un carnet que
    /// la contrainte n'a pas touché — passé sur *Manuscrit* avant elle, avec
    /// ses pointillés — tombe sur le repli plutôt que sur une image sans les
    /// pointillés qu'il imprimera.
    public static func fileName(
        for customisation: BookCustomisation,
        among available: Set<String> = availableFileNames
    ) -> String {
        // L'élément du manifeste, et non le nom composé : Swift tient « é » et
        // « e + accent » pour la même chaîne, une URL non. Les octets rendus
        // sont donc ceux du disque, que les tests comparent au dossier.
        guard let name = composedFileName(for: customisation),
              let index = available.firstIndex(of: name)
        else { return fallbackFileName }
        return available[index]
    }

    /// Le nom que la règle compose, que le fichier existe ou non. `nil` pour un
    /// carnet « Personnalisé ».
    ///
    /// L'ordre des segments et leur séparateur sont ceux des fichiers, au
    /// caractère près.
    static func composedFileName(for customisation: BookCustomisation) -> String? {
        guard let combo = BookFontCombo.matching(customisation),
              let typos = typographySegments[combo.id]
        else { return nil }

        let segments = [
            "Pointillés=\(customisation.rulesEnabled ? "on" : "off")",
            "Ratio image=\(customisation.photoTextRatio)%",
            "Fun fact=\(customisation.funFactsEnabled ? "on" : "off")",
            "Stickers=\(customisation.decorationQuota)",
            "Typos=\(typos)",
        ]
        return segments.joined(separator: ", ") + ".png"
    }

    /// Le segment `Typos=` de chaque assortiment, **tel que les fichiers
    /// l'écrivent** : une forme abrégée, non normalisée, qui nomme
    /// l'assortiment et non ses quatre polices.
    static let typographySegments: [String: String] = [
        BookFontCombo.travelJournal.id: "Playfair Display - Hansley - Gloria Hallelujah",
        // « Hellelujah » : une faute de frappe figée dans cinquante noms de
        // fichiers. La corriger ici ferait tomber *Manuscrit* sur le repli.
        BookFontCombo.handwritten.id: "Hansley - Gloria Hellelujah",
        BookFontCombo.editorial.id: "Playfair Display",
    ]
}
