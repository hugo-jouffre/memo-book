import Foundation

/// Tout ce que l'écran « Support et retours » et ses trois feuilles écrivent.
///
/// Le **contenu** des réponses, lui, vit dans ``Faq`` : c'est de la copie
/// rédactionnelle qui se relit et se corrige toute seule, et elle a sa propre
/// source de vérité (la page Notion « FAQ in-app MemoBook »).
///
/// Mêmes conventions typographiques que ``BookCopy`` : apostrophe `’` (U+2019),
/// espace insécable avant `?` et `!`, points de suspension `…` (U+2026).
///
/// ⚠️ **Trois coquilles de la maquette sont recopiées telles quelles** (R8
/// interdit de corriger en silence) :
///   - ``intro`` écrit « si tu ne trouve pas de réponse » — il manque le `s` de
///     la deuxième personne.
///   - ``Contact/title`` écrit « Ecris » sans accent sur le E capital.
///   - ``Contact/message`` écrit « dans les plus bref délais » — il manque le
///     `s` de « brefs » — et « whatsapp » sans capitale.
public enum SupportCopy {
    public static let title = "Support et retours"

    /// « Hello Margaux, » — le prénom vient du compte, comme pour le mot des
    /// fondateurs. Sans prénom, la phrase se contente du bonjour.
    public static func hello(_ firstName: String?) -> String {
        guard let firstName, !firstName.isEmpty else { return "Hello," }
        return "Hello \(firstName),"
    }

    /// Les deux paragraphes de présentation, sous la photo.
    ///
    /// ⚠️ Le second porte la coquille « tu ne trouve » (R8).
    public static let intro = [
        "Nous sommes Paul & Hugo, les développeurs de MemoBook. On adore voyager et on veut rendre la création des carnets de voyage rapide, intelligente et authentique.",
        "Voici notre foire aux questions, en espérant que celle-ci réponde à tes interrogations. Tu auras la possibilité de nous écrire si tu ne trouve pas de réponse.",
    ]

    // MARK: - La recherche

    /// Ce que le champ propose quand il est vide. Il dit **où** l'on cherche.
    ///
    /// ⚠️ **Aucune maquette ne dessine ce champ** (Hugo, 16/09/2026) : c'est le
    /// point 2 de la page Notion — « recherche interne » — qui attendait un
    /// écran. Il est écrit sur le motif des autres champs de l'app, au
    /// tutoiement, et reste à dessiner dans Figma.
    public static let searchPlaceholder = "Rechercher une question"

    /// Ce que la recherche a trouvé, annoncé sous le champ.
    public static func searchResults(_ count: Int) -> String {
        count == 1 ? "1 question trouvée" : "\(count) questions trouvées"
    }

    /// Rien ne répond. **La phrase ne s'arrête pas au constat** : la règle de
    /// rédaction de la page Notion vaut ici aussi — aucune limite sans une
    /// sortie, et la sortie est la ligne juste en dessous.
    public static func searchEmpty(_ query: String) -> String {
        "Aucune question ne parle de « \(query) ». **Écris-nous** : on te répond, et la réponse rejoindra cette page."
    }

    /// Le chapeau de la liste des questions. La maquette l'écrit en minuscules
    /// et le dessine en capitales : c'est une casse d'affichage, pas une casse
    /// de copie — VoiceOver doit lire « sujets courants », pas épeler.
    public static let topicsSection = "sujets courants"
    public static let contactSection = "Nous contacter"

    /// La ligne qui ouvre directement le formulaire, sous les deux questions de
    /// la section. Sans elle, « nous écrire » — que l'intro promet deux
    /// paragraphes plus haut — ne serait atteignable qu'après avoir lu une
    /// réponse, ce qui est exactement l'inverse de ce qu'on cherche quand on
    /// n'a rien trouvé.
    public static let writeToUs = "Écris à notre équipe"

    /// Le pied de page. Le numéro de version vient du bundle : l'écrire ici le
    /// figerait à la première version qui l'a affiché.
    public static func legal(version: String) -> String {
        "MemoBook v\(version) | Tous droits réservés"
    }

    // MARK: - La feuille d'une réponse

    public enum Answer {
        /// La question posée au lecteur sous la réponse. C'est elle que la page
        /// Notion appelle la mesure : « Consultations et clics *cette réponse
        /// t'a-t-elle aidé* par identifiant, pour repérer les questions mal
        /// formulées et les frictions produit. »
        public static let helpful = "Est-ce utile ?"
        public static let helpfulYes = "Cette réponse m’a aidé"
        public static let helpfulNo = "Cette réponse ne m’a pas aidé"

        /// Ce qu'on répond à quelqu'un qui vient de voter. Deux mots, et la
        /// question disparaît : laisser les deux pouces actifs invite à voter
        /// deux fois.
        public static let thanks = "Merci !"

        public static let stillStuck = "J’ai encore une question"
        public static let understood = "Compris"
    }

    // MARK: - La feuille « Nous contacter »

    public enum Contact {
        /// ⚠️ « Ecris » sans accent : coquille de la maquette (R8).
        public static let title = "Ecris à notre équipe"

        /// ⚠️ « les plus bref délais » et « whatsapp » : coquilles de la
        /// maquette (R8).
        public static let message =
            "Nous reviendrons vers toi dans les plus bref délais par mail ou par whatsapp si tu as renseigné ton numéro."

        public static let placeholder = "Ton message…"
        public static let send = "Envoyer"

        public static let confirmation = "Nous avons bien reçu ton message"

        /// Ce que VoiceOver annonce à la place du rond lime : une coche
        /// décorative ne dit rien que le titre ne dise déjà, mais son
        /// apparition, elle, mérite d'être signalée.
        public static let confirmationVoice = "Message envoyé"

        /// Le message n'est pas parti. L'écrire là où le formulaire était, et
        /// garder le texte saisi : le perdre serait pire que l'échec.
        public static let sendFailed =
            "Ton message n’a pas pu partir. Vérifie ta connexion et réessaie."
    }
}
