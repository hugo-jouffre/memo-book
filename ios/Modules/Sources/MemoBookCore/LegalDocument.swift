import Foundation

// Les documents légaux de l'app — conditions d'utilisation, politique de
// confidentialité — recopiés du site memobook.fr. Ce fichier porte la
// **forme** ; chaque document a le sien (``TermsOfUse``, ``PrivacyPolicy``).
//
// C'est du contenu **juridique**, et il se lit autrement que le reste de l'app :
//   - il **vouvoie**, seule exception à R9. Un contrat n'est pas une phrase de
//     l'interface ; on ne tutoie pas dans un contrat, et le texte du site est
//     celui qui engage. Recopié tel quel, signalé dans la fiche (T147).
//   - il dit « utilisateur », « consommateur », « produit » — le vocabulaire
//     du Code de la consommation et du RGPD, pas celui de la marque.
//
// Mêmes conventions typographiques que ``Faq`` : apostrophe `’`, espace
// insécable avant `?` et `!`, `…`.

/// Un document légal : son titre d'écran et ses chapitres.
public struct LegalDocument: Sendable, Hashable, Identifiable {
    /// `cgu`, `confidentialite` — le préfixe des identifiants de chapitres.
    public let id: String
    public let title: String
    public let chapters: [LegalChapter]

    public init(id: String, title: String, chapters: [LegalChapter]) {
        self.id = id
        self.title = title
        self.chapters = chapters
    }

    /// Le chapitre que pointe un identifiant.
    public func chapter(id: String) -> LegalChapter? {
        chapters.first { $0.id == id }
    }
}

/// Un chapitre : son numéro, son titre, et ce qu'il dit.
public struct LegalChapter: Sendable, Hashable, Identifiable {
    /// `<document>.slug` — immuable, comme ``FaqEntry/id`` : c'est lui qu'un
    /// écran pointerait pour ouvrir la page sur un chapitre précis.
    public let id: String

    /// Le numéro du chapitre, celui du site. Il **s'écrit** dans le titre de
    /// la carte (« Chapitre 4 — … ») et ordonne la page.
    public let number: Int
    public let title: String

    /// Le corps, bloc par bloc. Une liste et non une chaîne à `\n`, pour la
    /// même raison que ``FaqEntry/answer`` : l'écart entre deux blocs est une
    /// mesure du design system, et un intertitre n'est pas un paragraphe.
    public let blocks: [LegalBlock]

    public init(id: String, number: Int, title: String, blocks: [LegalBlock]) {
        self.id = id
        self.number = number
        self.title = title
        self.blocks = blocks
    }

    /// Ce que la carte montre **repliée** : le texte courant du chapitre, d'un
    /// seul tenant, que l'écran tronque à quelques lignes.
    ///
    /// Tout le texte et non le premier paragraphe : celui du chapitre 4 des
    /// CGU tient en deux lignes et s'arrête sur deux-points — une carte qui
    /// montrerait ça seul aurait l'air vide. Les intertitres n'y sont pas :
    /// « 4.1 Phase bêta » au milieu d'une phrase ne se lit pas.
    public var preview: String {
        texts(includingHeadings: false).joined(separator: " ")
    }

    /// Tous les textes du chapitre, quel que soit le bloc qui les porte.
    public func texts(includingHeadings: Bool = true) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .heading(let text): includingHeadings ? [text] : []
            case .paragraph(let text): [text]
            case .lines(let lines), .bullets(let lines): lines
            }
        }
    }
}

/// Un bloc du corps d'un chapitre.
///
/// Le texte peut porter deux balises Markdown, et seulement celles-là : un
/// lien (`[…](mailto:…)`, `[…](https://…)`) et un demi-gras (`**…**`) pour
/// l'étiquette d'une ligne — « **Finalité :** … ».
public enum LegalBlock: Sendable, Hashable {
    /// Un intertitre — « 4.1 Phase bêta gratuite », « Droit de rétractation ».
    case heading(String)
    /// Un paragraphe.
    case paragraph(String)
    /// Des lignes serrées, sans puce : un bloc d'identité, une fiche
    /// « données collectées / finalité / base légale / durée ».
    case lines([String])
    /// Une liste à puces.
    case bullets([String])
}

/// Ce que les deux documents partagent : l'adresse à laquelle tout renvoie.
/// Écrite une fois, liée partout.
public enum LegalContact {
    public static let email = "hugo.jouffre.freelance@gmail.com"
    public static let emailLink = "[\(email)](mailto:\(email))"
}
