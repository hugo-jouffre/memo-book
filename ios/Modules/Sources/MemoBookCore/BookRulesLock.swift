import Foundation

// Le verrou des pointillés : la contrainte entre typographie et pointillés.
//
// Aucun aperçu de personnalisation n'existe en `Pointillés=on` hors de
// l'assortiment par défaut. Décision du 01/10/2026 (Hugo) : choisir *Manuscrit*
// ou *Éditorial* éteint les pointillés et verrouille leur interrupteur ; revenir
// au défaut leur rend la valeur d'avant le premier verrouillage.
// `docs/apercu-personnalisation.md` fait foi.
//
// ⚠️ `rulesEnabled` n'est pas un réglage d'aperçu : ce sont les lignes
// pointillées **du carnet imprimé**. Le verrou retire donc une option du
// produit, et c'est tenable tant que les cent rendus manquants n'existent pas.

extension BookFontCombo {
    /// Cet assortiment permet-il les pointillés ?
    ///
    /// Seul le défaut : les deux autres n'ont pas d'aperçu avec. Le jour où les
    /// rendus manquants arrivent, c'est **ici** que la contrainte saute — rendre
    /// `true` — et nulle part ailleurs : le verrou, l'écran et les tests de
    /// couverture des aperçus lisent tous cette propriété.
    public var allowsRules: Bool { id == BookFontCombo.travelJournal.id }
}

/// Ce que le verrou décide, à chaque changement de typographie.
///
/// Une fonction pure, qui ne garde rien : la valeur d'avant le verrou vit
/// ailleurs (sur l'appareil, voir `BookRulesMemory`), et on la lui passe.
public enum BookRulesLock {
    /// Ce qu'un geste fait des pointillés.
    public struct Change: Sendable, Hashable {
        /// Les pointillés du carnet après le geste.
        public var rulesEnabled: Bool
        /// La valeur à mémoriser, **seulement s'il faut en écrire une**.
        /// `nil` ne veut pas dire « oublier » : la mémoire en place reste
        /// telle quelle. C'est ce qui empêche un second changement de
        /// typographie, verrou posé, d'écraser la valeur d'avant le premier.
        public var remember: Bool?

        public init(rulesEnabled: Bool, remember: Bool? = nil) {
            self.rulesEnabled = rulesEnabled
            self.remember = remember
        }
    }

    /// Les pointillés de ce carnet sont-ils verrouillés ?
    ///
    /// Sur un assortiment qui ne les permet pas, et seulement là. Un carnet
    /// « Personnalisé » n'est pas verrouillé : il n'a d'aperçu ni avec ni sans
    /// pointillés, le verrou n'y changerait rien.
    public static func isLocked(_ customisation: BookCustomisation) -> Bool {
        guard let combo = BookFontCombo.matching(customisation) else { return false }
        return !combo.allowsRules
    }

    /// Ce que deviennent les pointillés quand on choisit `combo`.
    ///
    /// - Vers un assortiment qui les interdit : éteints. Si le carnet n'était
    ///   pas encore verrouillé, on mémorise ce qu'ils valaient ; s'il l'était
    ///   déjà (*Manuscrit* → *Éditorial*), on ne touche pas à la mémoire.
    /// - Vers le défaut, depuis un verrou : la valeur mémorisée. Une mémoire
    ///   vide — le verrou a été posé sur un autre téléphone — rend **allumés** :
    ///   c'est la valeur par défaut, et personne n'a choisi « éteints ».
    /// - Vers le défaut, sans verrou : rien ne change.
    public static func choosing(
        _ combo: BookFontCombo,
        in customisation: BookCustomisation,
        remembered: Bool?
    ) -> Change {
        let wasLocked = isLocked(customisation)

        guard combo.allowsRules else {
            return Change(rulesEnabled: false, remember: wasLocked ? nil : customisation.rulesEnabled)
        }
        guard wasLocked else { return Change(rulesEnabled: customisation.rulesEnabled) }
        return Change(rulesEnabled: remembered ?? true)
    }

    /// Un carnet verrouillé dont les pointillés sont pourtant allumés, remis
    /// dans le rang. `nil` quand il n'y a rien à faire.
    ///
    /// C'est le cas des carnets passés sur *Manuscrit* ou *Éditorial* avant le
    /// verrou — les assortiments existent depuis le 16/09/2026, et les
    /// pointillés sont allumés par défaut —, ou d'une ancienne version de
    /// l'app qui les rallume. Décision du 02/10/2026 (Hugo) : l'écran les
    /// éteint à l'ouverture, et mémorise qu'ils étaient allumés — **sauf** si
    /// une mémoire existe déjà : elle dit ce qu'ils valaient avant le tout
    /// premier verrou, et c'est cette valeur-là que le retour au défaut rend.
    public static func normalised(_ customisation: BookCustomisation, remembered: Bool?) -> Change? {
        guard isLocked(customisation), customisation.rulesEnabled else { return nil }
        return Change(rulesEnabled: false, remember: remembered == nil ? true : nil)
    }
}
