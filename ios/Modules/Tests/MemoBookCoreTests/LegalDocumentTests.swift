import Testing

@testable import MemoBookCore

// Les documents légaux sont du **contenu**, comme la foire aux questions, et
// se relisent aussi mal : un chapitre numéroté deux fois, un identifiant
// recopié de son voisin, une adresse de contact tapée avec une faute dans l'un
// des endroits où elle apparaît. Rien de tout ça ne casse la compilation.

@Suite("Documents légaux")
struct LegalDocumentTests {
    /// Les deux documents, passés à chaque règle : une règle qui ne tiendrait
    /// que pour l'un des deux ne serait pas une règle.
    static let documents = [TermsOfUse.document, PrivacyPolicy.document]

    @Test("Les chapitres sont numérotés de 1 à n, dans l’ordre", arguments: Self.documents)
    func chaptersAreNumberedInOrder(document: LegalDocument) {
        #expect(document.chapters.map(\.number) == Array(1...document.chapters.count))
    }

    @Test("Chaque identifiant est unique et suit document.slug", arguments: Self.documents)
    func identifiersAreUniqueAndWellFormed(document: LegalDocument) {
        let ids = document.chapters.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            let parts = id.split(separator: ".")
            #expect(parts.count == 2, "\(id)")
            #expect(parts.first.map(String.init) == document.id, "\(id)")
        }
    }

    /// Une carte repliée montre le début du chapitre : il faut donc qu'il y
    /// ait du texte à montrer, et pas seulement un intertitre.
    @Test("Chaque chapitre a un aperçu", arguments: Self.documents)
    func everyChapterHasAPreview(document: LegalDocument) {
        for chapter in document.chapters {
            #expect(!chapter.preview.isEmpty, "\(chapter.id)")
        }
    }

    /// L'adresse est écrite une fois et liée partout : aucun texte ne doit la
    /// porter **nue**, sans le lien qu'on touche pour écrire.
    @Test("L’adresse de contact est toujours un lien", arguments: Self.documents)
    func contactEmailIsAlwaysLinked(document: LegalDocument) {
        for chapter in document.chapters {
            for text in chapter.texts() where text.contains(LegalContact.email) {
                #expect(text.contains(LegalContact.emailLink), "\(chapter.id) : \(text)")
            }
        }
    }

    /// Même convention que la FAQ : l'apostrophe typographique, pas celle du
    /// clavier.
    @Test("Les textes n’emploient que l’apostrophe typographique", arguments: Self.documents)
    func textsUseTypographicApostrophe(document: LegalDocument) {
        for chapter in document.chapters {
            #expect(!chapter.title.contains("'"), "\(chapter.id)")
            for text in chapter.texts() {
                #expect(!text.contains("'"), "\(chapter.id) : \(text)")
            }
        }
    }

    /// Un `**` ouvert et jamais refermé s'afficherait tel quel dans l'app.
    @Test("Les demi-gras sont refermés", arguments: Self.documents)
    func emphasisIsBalanced(document: LegalDocument) {
        for chapter in document.chapters {
            for text in chapter.texts() {
                let marks = text.components(separatedBy: "**").count - 1
                #expect(marks.isMultiple(of: 2), "\(chapter.id) : \(text)")
            }
        }
    }

    @Test("Un chapitre se retrouve par son identifiant", arguments: Self.documents)
    func chapterIsFoundById(document: LegalDocument) {
        let first = document.chapters[0]
        #expect(document.chapter(id: first.id) == first)
        #expect(document.chapter(id: "\(document.id).inconnu") == nil)
    }
}
