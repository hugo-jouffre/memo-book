import Foundation

/// Tout ce que les limites de souvenirs font écrire, en un seul endroit.
///
/// ⚠️ **Le mot « jeton » n'y figure pas, et le mot « token » non plus** (Hugo,
/// 16/09/2026). L'app compte des **souvenirs** : c'est l'unité du produit, et
/// elle se comprend sans explication — un vocal d'une minute vaut dix messages
/// parce qu'il coûte dix fois plus à transcrire, à rédiger et à relire, et
/// c'est exactement ce que la feuille dit.
///
/// ⚠️ **Aucune maquette ne dessine cet écran.** La ligne, la jauge et la
/// feuille d'extension sont écrites sur les motifs existants — la ligne de
/// cagnotte, `BrandSlider` pour la jauge, le parcours du paywall pour la
/// feuille — et restent à dessiner dans Figma.
public enum MemoryCopy {
    /// La ligne des réglages du voyage.
    public static let rowTitle = "Limites de souvenirs"

    /// Sous l'intitulé de la ligne : **ce que ça coûte, avant qu'on le
    /// demande** (Clara, 26/09/2026). Un compteur « 1 240 / 3 000 » sans cette
    /// phrase se lit comme un forfait qui déborde, et fait craindre un
    /// prélèvement.
    public static let rowCaption = "Comprises dans ton abonnement, sans frais en plus"

    /// La valeur en bout de ligne : « 1 240 / 3 000 ».
    public static func rowValue(used: Int, allowance: Int) -> String {
        "\(number(used)) / \(number(allowance))"
    }

    // MARK: La feuille

    public static let sheetTitle = "Tes limites de souvenirs"

    /// Le chapeau, qui dit **ce que c'est** avant de dire où on en est — et,
    /// d'abord, que rien ne se paie sans qu'on le choisisse (Clara,
    /// 26/09/2026 : la phrase d'avant laissait croire à un prélèvement au-delà
    /// de la limite).
    public static let sheetIntro =
        "Ton abonnement comprend chaque semaine de quoi raconter tous les jours. Si tu atteins la limite, rien n’est prélevé : tu attends le renouvellement, ou tu choisis d’étendre."

    /// Le chapeau de la comparaison : étendre est un geste, jamais un
    /// débordement facturé.
    public static func compareIntro(price: String) -> String {
        "Étendre est un choix, jamais automatique : \(price)/semaine, et tu reviens aux limites comprises quand tu veux."
    }

    /// « Il te reste 1 760 souvenirs, jusqu'au 14 octobre. »
    public static func remaining(_ count: Int, renewsOn: String?) -> String {
        let core = count == 1 ? "Il te reste 1 souvenir" : "Il te reste \(number(count)) souvenirs"
        guard let renewsOn else { return "\(core)." }
        return "\(core), jusqu’au \(renewsOn)."
    }

    /// Le barème, écrit **avec les valeurs du serveur** : l'app ne connaît pas
    /// le tarif, elle le rend.
    public static func pricing(text: Int, voicePerMinute: Int) -> [String] {
        [
            "Un message écrit : \(unit(text)).",
            "Une minute de vocal : \(unit(voicePerMinute)).",
        ]
    }

    public static let pricingHeading = "Ce que ça consomme"

    /// Pourquoi un vocal pèse davantage. **La question se pose, donc on y
    /// répond** : sans cette phrase, le rapport de dix se lit comme une
    /// pénalité au lieu d'un coût.
    public static let voiceExplanation =
        "Un vocal passe par la transcription, la rédaction puis la relecture — c’est ce qui coûte, et c’est ce qui fait un beau carnet."

    // MARK: Les deux paliers

    public static let compareHeading = "Rester, ou étendre"

    public static func includedDetail(_ allowance: Int) -> String {
        "\(number(allowance)) souvenirs par semaine, compris dans ton abonnement. De quoi raconter tous les jours, vocaux compris."
    }

    public static func extendedDetail(allowance: Int, price: String) -> String {
        "\(number(allowance)) souvenirs par semaine pour \(price). Pour les voyages racontés à plusieurs, tous les jours, en vocal."
    }

    public static let includedPrice = "Compris"

    /// Le bouton qui étend.
    public static func upgradeCta(price: String) -> String { "Étendre pour \(price)/semaine" }

    /// Celui qui revient au palier compris. Rouge et sans fond — c'est l'action
    /// qui défait, comme « Résilier mon abonnement ».
    public static let downgradeCta = "Revenir aux limites comprises"

    public static let close = "Fermer"

    /// Le bandeau qui apparaît sur la ligne quand il ne reste presque plus
    /// rien — voir ``MemoryAllowance/isRunningLow``.
    public static let runningLow =
        "**Tu approches de tes limites de souvenirs.** Elles se renouvellent chaque semaine ; tu peux aussi les étendre."

    /// Et quand il ne reste rien du tout.
    public static let exhausted =
        "**Tes limites de souvenirs sont atteintes pour cette semaine.** Rien n’est prélevé : attends le renouvellement, ou étends-les."

    // MARK: Mise en forme

    /// « 1 240 » — avec l'espace des milliers de la région. Un budget se lit
    /// d'un coup d'œil ou ne se lit pas.
    static func number(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// « 10 souvenirs », accordé.
    static func unit(_ value: Int) -> String {
        value == 1 ? "1 souvenir" : "\(number(value)) souvenirs"
    }
}
